const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const fs = require('fs');
const { Readable } = require('stream');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const http = require('http');
const { Server } = require('socket.io');
const { v2: cloudinary } = require('cloudinary');
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

const cloudinaryCloudName = String(process.env.CLOUDINARY_CLOUD_NAME || '').trim();
const cloudinaryApiKey = String(process.env.CLOUDINARY_API_KEY || '').trim();
const cloudinaryApiSecret = String(process.env.CLOUDINARY_API_SECRET || '').trim();
const cloudinaryFolder = String(process.env.CLOUDINARY_FOLDER || 'bookmyhospital/complaints').trim();
const cloudStorageEnabled = Boolean(
  cloudinaryCloudName &&
  cloudinaryApiKey &&
  cloudinaryApiSecret &&
  !cloudinaryCloudName.includes('replace_with_') &&
  !cloudinaryApiKey.includes('replace_with_') &&
  !cloudinaryApiSecret.includes('replace_with_'),
);

if (cloudStorageEnabled) {
  cloudinary.config({
    cloud_name: cloudinaryCloudName,
    api_key: cloudinaryApiKey,
    api_secret: cloudinaryApiSecret,
    secure: true,
  });
}

const upload = multer({ storage: multer.memoryStorage() });

app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use('/uploads', express.static(uploadsRoot));

function uploadStream(buffer, options) {
  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(options, (error, result) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(result);
    });
    Readable.from(buffer).pipe(stream);
  });
}

async function persistComplaintProof(file) {
  const safeName = `${Date.now()}_${file.originalname.replace(/[^a-zA-Z0-9_.-]/g, '_')}`;
  if (cloudStorageEnabled) {
    const result = await uploadStream(file.buffer, {
      folder: cloudinaryFolder,
      resource_type: 'auto',
      public_id: safeName.replace(/\.[^.]+$/, ''),
      overwrite: false,
    });
    return result.secure_url;
  }

  const filePath = path.join(complaintsDir, safeName);
  await fs.promises.writeFile(filePath, file.buffer);
  return `${process.env.API_BASE_URL || `http://localhost:${PORT}`}/uploads/complaints/${safeName}`;
}

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

  const proofUrls = [];
  for (const file of req.files || []) {
    proofUrls.push(await persistComplaintProof(file));
  }
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
    if (cloudStorageEnabled) {
      console.log(`Cloudinary complaint uploads enabled in folder: ${cloudinaryFolder}`);
    } else {
      console.log('Cloudinary not configured; using local complaint storage fallback.');
    }
  });
}

start().catch((error) => {
  console.error('Failed to start backend:', error);
  process.exit(1);
});
