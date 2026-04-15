require('dotenv').config();

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const http = require('http');
const { Server } = require('socket.io');
const {
  connectMongo,
  seedMongoIfNeeded,
  upsertUser,
  listHospitals,
  getHospitalById,
  createPendingHospital,
  reviewHospital,
  updateHospitalAvailability,
  createBooking,
  listBookings,
  createComplaint,
  listComplaints,
  disciplineHospital,
  overview,
  hospitalAuth,
} = require('./store');

const PORT = Number(process.env.PORT || 8080);
const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'],
  },
});

const uploadsRoot = path.join(__dirname, '..', 'uploads');
const complaintsDir = path.join(uploadsRoot, 'complaints');
fs.mkdirSync(complaintsDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, complaintsDir),
  filename: (_, file, cb) => {
    const safeName = file.originalname.replace(/[^a-zA-Z0-9_.-]/g, '_');
    cb(null, `${Date.now()}_${safeName}`);
  },
});
const upload = multer({ storage });

app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use('/uploads', express.static(uploadsRoot));

function emitOverview() {
  overview()
    .then((payload) => io.emit('overview:update', payload))
    .catch((error) => console.error('Failed to emit overview:', error.message));
}

async function refreshSnapshot() {
  io.emit('hospital:snapshot', await listHospitals({ status: 'approved' }));
  io.emit('bookings:snapshot', await listBookings());
  emitOverview();
}

function respondNotFound(res, message) {
  return res.status(404).json({ error: message || 'Not found' });
}

app.get('/health', async (_req, res) => {
  res.json({ ok: true, service: 'bookmyhospital-backend', mongo: Boolean(process.env.MONGODB_URI) });
});

app.post('/api/auth/google-login', async (req, res) => {
  const { email, name, role = 'patient', location = 'Unknown', hospitalId = null, googleId = null } = req.body || {};
  if (!email || !name) {
    return res.status(400).json({ error: 'email and name are required' });
  }

  const user = await upsertUser({
    email,
    name,
    role,
    location,
    hospitalId,
    googleId,
    status: 'active',
  });

  return res.json({ user });
});

app.post('/api/hospitals/auth', async (req, res) => {
  const { email } = req.body || {};
  if (!email) return res.status(400).json({ error: 'email is required' });
  const hospital = await hospitalAuth({ email });
  if (!hospital) return res.status(404).json({ error: 'Hospital account not found or not approved' });
  return res.json({ hospital });
});

app.get('/api/hospitals', async (req, res) => {
  const status = req.query.status || 'approved';
  const location = req.query.location || undefined;
  const hospitals = await listHospitals({ status, location });
  res.json({ hospitals });
});

app.get('/api/hospitals/:id', async (req, res) => {
  const hospital = await getHospitalById(req.params.id);
  if (!hospital) return respondNotFound(res, 'Hospital not found');
  res.json({ hospital });
});

app.post('/api/hospitals/register', async (req, res) => {
  const payload = req.body || {};
  const required = ['name', 'email', 'location'];
  const missing = required.filter((key) => !payload[key]);
  if (missing.length) {
    return res.status(400).json({ error: `Missing fields: ${missing.join(', ')}` });
  }

  const hospital = await createPendingHospital(payload);
  io.emit('hospital:pending', hospital);
  emitOverview();
  return res.status(201).json({ hospital });
});

app.patch('/api/hospitals/:id/status', async (req, res) => {
  const { status } = req.body || {};
  if (!['approved', 'deactivated', 'banned', 'pending'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }

  const action = status === 'approved' ? 'approve' : 'decline';
  const hospital = await reviewHospital(req.params.id, action);
  if (!hospital) return respondNotFound(res, 'Hospital not found');

  io.emit(`hospital:${status}`, hospital);
  emitOverview();
  return res.json({ hospital });
});

app.patch('/api/hospitals/:id/availability', async (req, res) => {
  const hospital = await updateHospitalAvailability(req.params.id, req.body || {});
  if (!hospital) return respondNotFound(res, 'Hospital not found');

  io.emit('hospital:availability-updated', hospital);
  emitOverview();
  return res.json({ hospital });
});

app.post('/api/hospitals/:id/login', async (req, res) => {
  const hospital = await getHospitalById(req.params.id);
  if (!hospital) return respondNotFound(res, 'Hospital not found');
  if (hospital.status !== 'approved') {
    return res.status(403).json({ error: 'Hospital is not approved yet' });
  }
  return res.json({ hospital });
});

app.get('/api/hospitals/:id/bookings', async (req, res) => {
  const hospital = await getHospitalById(req.params.id);
  if (!hospital) return respondNotFound(res, 'Hospital not found');
  const bookings = await listBookings({ hospitalId: hospital.id || hospital.hospitalId });
  res.json({ bookings });
});

app.post('/api/bookings', async (req, res) => {
  const payload = req.body || {};
  const { hospitalId, type, patientName, patientEmail = null, patientId = null } = payload;
  if (!hospitalId || !type || !patientName) {
    return res.status(400).json({ error: 'hospitalId, type and patientName are required' });
  }

  const hospital = await getHospitalById(hospitalId);
  if (!hospital) return respondNotFound(res, 'Hospital not found');

  const booking = await createBooking({
    hospitalId: hospital.id || hospital.hospitalId,
    hospitalName: hospital.name,
    patientId,
    patientName,
    patientEmail,
    type,
    priority: payload.priority || 'normal',
    status: 'confirmed',
  });

  const updates = {};
  if (type === 'bed' || type === 'emergency') {
    updates.bedsAvailable = Math.max(0, Number(hospital.bedsAvailable || 0) - 1);
    updates.queueWaitMinutes = Math.max(5, Number(hospital.queueWaitMinutes || 30) + (type === 'emergency' ? 2 : 5));
  }
  if (type === 'appointment') {
    updates.doctorsAvailable = Math.max(0, Number(hospital.doctorsAvailable || 0) - 1);
    updates.queueWaitMinutes = Math.max(5, Number(hospital.queueWaitMinutes || 30) + 10);
  }

  if (Object.keys(updates).length) {
    await updateHospitalAvailability(hospital.id || hospital.hospitalId, updates);
  }

  io.emit('booking:created', booking);
  await refreshSnapshot();
  return res.status(201).json({ booking });
});

app.post('/api/complaints', upload.array('proofs', 5), async (req, res) => {
  const { hospitalId, patientName, description, patientId = null } = req.body || {};
  if (!hospitalId || !patientName || !description) {
    return res.status(400).json({ error: 'hospitalId, patientName and description are required' });
  }

  const hospital = await getHospitalById(hospitalId);
  if (!hospital) return respondNotFound(res, 'Hospital not found');

  const proofUrls = (req.files || []).map((file) => `${req.protocol}://${req.get('host')}/uploads/complaints/${file.filename}`);
  const complaint = await createComplaint({
    hospitalId: hospital.id || hospital.hospitalId,
    hospitalName: hospital.name,
    patientId,
    patientName,
    description,
    proofUrls,
    status: 'open',
  });

  io.emit('complaint:created', complaint);
  emitOverview();
  return res.status(201).json({ complaint });
});

app.get('/api/complaints', async (_req, res) => {
  const complaints = await listComplaints();
  res.json({ complaints });
});

app.get('/api/admin/overview', async (_req, res) => {
  const payload = await overview();
  res.json(payload);
});

app.get('/api/admin/bookings', async (_req, res) => {
  const bookings = await listBookings();
  res.json({ bookings });
});

app.patch('/api/admin/hospitals/:id/discipline', async (req, res) => {
  const { action } = req.body || {};
  if (!action) return res.status(400).json({ error: 'action is required' });

  const hospital = await disciplineHospital(req.params.id, action);
  if (!hospital) return respondNotFound(res, 'Hospital not found');

  io.emit('hospital:status-updated', hospital);
  emitOverview();
  return res.json({ hospital });
});

app.get('/api/admin/hospitals/pending', async (_req, res) => {
  const hospitals = await listHospitals({ status: 'pending' });
  res.json({ hospitals });
});

app.get('/api/admin/hospitals/approved', async (_req, res) => {
  const hospitals = await listHospitals({ status: 'approved' });
  res.json({ hospitals });
});

io.on('connection', async (socket) => {
  socket.emit('overview:update', await overview());
  socket.emit('hospital:snapshot', await listHospitals({ status: 'approved' }));
  socket.emit('bookings:snapshot', await listBookings());
});

async function start() {
  await connectMongo();
  await seedMongoIfNeeded();

  server.listen(PORT, () => {
    console.log(`BookMyHospital backend listening on http://localhost:${PORT}`);
    if (process.env.MONGODB_URI) {
      console.log('MongoDB connected mode enabled');
    } else {
      console.log('Running in memory fallback mode. Set MONGODB_URI for persistent data.');
    }
  });
}

start().catch((error) => {
  console.error('Failed to start backend:', error);
  process.exit(1);
});
require('dotenv').config();

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const http = require('http');
const { Server } = require('socket.io');
const {
  connectMongo,
  seedMongoIfNeeded,
  upsertUser,
  listHospitals,
  getHospitalById,
  createPendingHospital,
  reviewHospital,
  updateHospitalAvailability,
  createBooking,
  listBookings,
  createComplaint,
  listComplaints,
  disciplineHospital,
  overview,
  hospitalAuth,
} = require('./store');

const PORT = Number(process.env.PORT || 8080);
const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'],
  },
});

const uploadsRoot = path.join(__dirname, '..', 'uploads');
const complaintsDir = path.join(uploadsRoot, 'complaints');
fs.mkdirSync(complaintsDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, complaintsDir),
  filename: (_, file, cb) => {
    const safeName = file.originalname.replace(/[^a-zA-Z0-9_.-]/g, '_');
    cb(null, `${Date.now()}_${safeName}`);
  },
});
const upload = multer({ storage });

app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use('/uploads', express.static(uploadsRoot));

app.get('/api/hospitals', (req, res) => {
  const { status = 'approved', location } = req.query;
  const source = status === 'pending' ? db.pendingHospitals : db.hospitals;
  const data = location
    ? source.filter((h) => h.location.toLowerCase() === String(location).toLowerCase())
    : source;
  res.json({ hospitals: data });
});

app.get('/api/hospitals/:id', (req, res) => {
  const hospital = db.hospitals.find((h) => h.id === req.params.id);
  if (!hospital) {
    return res.status(404).json({ message: 'Hospital not found' });
  }
  res.json({ hospital });
});

app.post('/api/hospitals/register', (req, res) => {
  const payload = req.body || {};
  if (!payload.name || !payload.email || !payload.location) {
    return res.status(400).json({ message: 'name, email, location are required' });
  }

  const hospital = {
    id: `pending_${Date.now()}`,
    name: payload.name,
    email: payload.email,
    location: payload.location,
    specialities: payload.specialities || [],
    equipment: payload.equipment || [],
    bedsTotal: Number(payload.bedsTotal || 0),
    bedsAvailable: Number(payload.bedsAvailable || 0),
    icuTotal: Number(payload.icuTotal || 0),
    icuAvailable: Number(payload.icuAvailable || 0),
    otTotal: Number(payload.otTotal || 0),
    otAvailable: Number(payload.otAvailable || 0),
    doctorsAvailable: Number(payload.doctorsAvailable || 0),
    surgeonsAvailable: Number(payload.surgeonsAvailable || 0),
    queueWaitMinutes: Number(payload.queueWaitMinutes || 30),
    status: 'pending',
    docsSubmitted: true,
    createdAt: new Date().toISOString(),
  };

  db.pendingHospitals.push(hospital);
  io.emit('hospital:pending', hospital);
  broadcastOverview();

  return res.status(201).json({
    message: 'Registration submitted. Awaiting admin approval.',
    hospital,
  });
});

app.patch('/api/hospitals/:id/status', (req, res) => {
  const { id } = req.params;
  const { action } = req.body || {};

  const index = db.pendingHospitals.findIndex((h) => h.id === id);
  if (index < 0) {
    return res.status(404).json({ message: 'Pending hospital not found' });
  }

  const hospital = db.pendingHospitals[index];
  db.pendingHospitals.splice(index, 1);

  if (action === 'approve') {
    hospital.status = 'approved';
    db.hospitals.push(hospital);
    io.emit('hospital:approved', hospital);
  } else {
    io.emit('hospital:declined', hospital);
  }

  broadcastOverview();
  return res.json({ message: `Hospital ${action}d`, hospital });
});

app.patch('/api/hospitals/:id/availability', (req, res) => {
  const { id } = req.params;
  const hospital = db.hospitals.find((h) => h.id === id);
  if (!hospital) {
    return res.status(404).json({ message: 'Hospital not found' });
  }

  const editable = [
    'bedsAvailable',
    'icuAvailable',
    'otAvailable',
    'doctorsAvailable',
    'surgeonsAvailable',
    'queueWaitMinutes',
  ];

  editable.forEach((key) => {
    if (Object.prototype.hasOwnProperty.call(req.body, key)) {
      hospital[key] = Number(req.body[key]);
    }
  });

  emitHospitalSnapshot(hospital);
  broadcastOverview();
  return res.json({ hospital });
});

app.post('/api/bookings', (req, res) => {
  const payload = req.body || {};
  if (!payload.hospitalId || !payload.patientName || !payload.type) {
    return res.status(400).json({ message: 'hospitalId, patientName, type are required' });
  }

  const hospital = db.hospitals.find((h) => h.id === payload.hospitalId);
  if (!hospital) {
    return res.status(404).json({ message: 'Hospital not found' });
  }

  const bookingType = String(payload.type);
  const booking = {
    id: `book_${Date.now()}`,
    ...payload,
    status: 'confirmed',
    createdAt: new Date().toISOString(),
    hospitalName: hospital.name,
    priority: bookingType.toLowerCase().includes('emergency') ? 'high' : 'normal',
  };

  if (bookingType.toLowerCase().includes('bed') || bookingType.toLowerCase().includes('emergency')) {
    hospital.bedsAvailable = Math.max(0, Number(hospital.bedsAvailable || 0) - 1);
    hospital.queueWaitMinutes = Math.max(5, Number(hospital.queueWaitMinutes || 30) - 2);
  }

  if (bookingType.toLowerCase().includes('appointment')) {
    hospital.doctorsAvailable = Math.max(0, Number(hospital.doctorsAvailable || 0) - 1);
  }

  db.bookings.push(booking);
  emitHospitalSnapshot(hospital);
  io.emit('booking:created', booking);
  broadcastOverview();
  return res.status(201).json({ booking });
});

app.get('/api/bookings', (req, res) => {
  const { hospitalId } = req.query;
  const bookings = hospitalId
    ? db.bookings.filter((b) => b.hospitalId === hospitalId)
    : db.bookings;
  res.json({ bookings });
});

app.get('/api/hospitals/:id/bookings', (req, res) => {
  const bookings = db.bookings.filter((b) => b.hospitalId === req.params.id);
  res.json({ bookings });
});

app.post('/api/complaints', (req, res) => {
  const payload = req.body || {};
  if (!payload.hospitalId || !payload.patientName || !payload.description) {
    return res.status(400).json({ message: 'hospitalId, patientName, description are required' });
  }

  const complaint = {
    id: `comp_${Date.now()}`,
    ...payload,
    status: 'open',
    createdAt: new Date().toISOString(),
  };

  db.complaints.push(complaint);
  const hospital = db.hospitals.find((h) => h.id === complaint.hospitalId);
  if (hospital) {
    hospital.complaintsCount += 1;
  }

  io.emit('complaint:created', complaint);
  broadcastOverview();
  return res.status(201).json({ complaint });
});

app.get('/api/admin/overview', (_, res) => {
  const byLocation = db.users.reduce((acc, user) => {
    const key = user.location || 'Unknown';
    acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});

  res.json({
    hospitalsApproved: db.hospitals.length,
    hospitalsPending: db.pendingHospitals.length,
    complaints: db.complaints,
    usersByLocation: byLocation,
    bookings: db.bookings,
  });
});

app.get('/api/admin/bookings', (_, res) => {
  res.json({ bookings: db.bookings });
});

app.patch('/api/admin/hospitals/:id/discipline', (req, res) => {
  const { id } = req.params;
  const { action } = req.body || {};

  const hospital = db.hospitals.find((h) => h.id === id);
  if (!hospital) {
    return res.status(404).json({ message: 'Hospital not found' });
  }

  if (!['deactivate', 'activate', 'ban'].includes(action)) {
    return res.status(400).json({ message: 'action must be deactivate|activate|ban' });
  }

  if (hospital.status === 'banned') {
    return res.status(400).json({ message: 'Hospital already banned permanently' });
  }

  if (action === 'ban') {
    hospital.status = 'banned';
  } else if (action === 'deactivate') {
    hospital.status = 'deactivated';
  } else {
    hospital.status = 'approved';
  }

  io.emit('hospital:status-updated', hospital);
  return res.json({ hospital });
});

io.on('connection', (socket) => {
  socket.emit('overview:update', getOverviewPayload());
  socket.emit('bookings:snapshot', db.bookings);
});

server.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`BookMyHospital backend running on port ${PORT}`);
});
