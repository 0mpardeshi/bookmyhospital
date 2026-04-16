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
  createNotification,
  listPatientNotifications,
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

function hasUsableSecret(value) {
  const key = String(value || '').trim();
  if (!key) return false;
  if (key.includes('replace_with_') || key.includes('your_')) return false;
  return true;
}

function buildAiSystemPrompt(lowDataMode) {
  return [
    'You are BookMyHospital AI assistant.',
    'Give practical medical system guidance, not diagnosis.',
    'Prioritize emergency triage, hospital booking guidance, complaint and safety workflow.',
    lowDataMode
      ? 'Use very short responses: max 3 bullet points, compact language.'
      : 'Use concise and clear responses with actionable steps.',
  ].join(' ');
}

async function askGemini({ message, lowDataMode }) {
  const geminiKey = process.env.GEMINI_API_KEY;
  if (!hasUsableSecret(geminiKey)) return null;

  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${geminiKey}`;
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: `${buildAiSystemPrompt(lowDataMode)}\n\nUser: ${message}` }] }],
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: lowDataMode ? 140 : 320,
      },
    }),
  });

  if (!response.ok) return null;
  const json = await response.json();
  return json?.candidates?.[0]?.content?.parts?.[0]?.text || null;
}

async function askGroq({ message, lowDataMode }) {
  const groqKey = process.env.GROQ_API_KEY;
  if (!hasUsableSecret(groqKey)) return null;

  const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${groqKey}`,
    },
    body: JSON.stringify({
      model: 'llama-3.1-8b-instant',
      temperature: 0.3,
      max_tokens: lowDataMode ? 140 : 320,
      messages: [
        { role: 'system', content: buildAiSystemPrompt(lowDataMode) },
        { role: 'user', content: message },
      ],
    }),
  });

  if (!response.ok) return null;
  const json = await response.json();
  return json?.choices?.[0]?.message?.content || null;
}

function localAiFallback({ message, lowDataMode }) {
  const text = String(message || '').toLowerCase();
  if (text.includes('emergency') || text.includes('urgent') || text.includes('bleeding')) {
    return lowDataMode
      ? 'Emergency protocol:\n• Call local emergency number now\n• Pre-book nearest emergency bed\n• Keep airway clear and share vitals'
      : 'Emergency protocol:\n1) Call local emergency services immediately.\n2) In BookMyHospital, choose Emergency Bed pre-booking at nearest approved hospital.\n3) Keep patient airway clear, monitor breathing/pulse, and carry basic records while traveling.';
  }
  if (text.includes('complaint')) {
    return lowDataMode
      ? 'Complaint flow:\n• Select hospital\n• Add proof files\n• Submit and track admin action'
      : 'Complaint flow:\n1) Open the selected hospital card and raise a complaint.\n2) Attach clear photo/video proof if available.\n3) Admin reviews and can deactivate/ban hospital for violations.';
  }
  return lowDataMode
    ? 'I can help with booking, complaints, emergency routing, and app support. Ask in one line for fastest response.'
    : 'I can help with emergency triage guidance, booking flow, complaint workflow, and low-network usage tips. Tell me your situation and I will give short actionable steps.';
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

app.post('/api/admin/auth', async (req, res) => {
  const { accessCode } = req.body || {};
  if (!accessCode) {
    return res.status(400).json({ error: 'accessCode is required' });
  }

  const expectedCode = String(process.env.ADMIN_ACCESS_CODE || 'BMH-DEV-2026').trim();
  if (accessCode !== expectedCode) {
    return res.status(401).json({ error: 'Invalid admin access code' });
  }

  return res.json({ ok: true, role: 'admin' });
});

app.post('/api/ai/help', async (req, res) => {
  const { message, lowDataMode = false } = req.body || {};
  if (!message || !String(message).trim()) {
    return res.status(400).json({ error: 'message is required' });
  }

  const normalizedMessage = String(message).trim();
  try {
    const geminiReply = await askGemini({ message: normalizedMessage, lowDataMode: Boolean(lowDataMode) });
    if (geminiReply) {
      return res.json({ reply: geminiReply, provider: 'gemini', fallback: false });
    }

    const groqReply = await askGroq({ message: normalizedMessage, lowDataMode: Boolean(lowDataMode) });
    if (groqReply) {
      return res.json({ reply: groqReply, provider: 'groq', fallback: false });
    }
  } catch (error) {
    console.warn('AI provider unavailable, using fallback:', error.message);
  }

  return res.json({
    reply: localAiFallback({ message: normalizedMessage, lowDataMode: Boolean(lowDataMode) }),
    provider: 'local-fallback',
    fallback: true,
  });
});

app.get('/api/patients/:patientId/notifications', async (req, res) => {
  const patientId = String(req.params.patientId || '').trim();
  if (!patientId) {
    return res.status(400).json({ error: 'patientId is required' });
  }
  const notifications = await listPatientNotifications(patientId);
  return res.json({ notifications });
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
  const { status, action } = req.body || {};

  let reviewAction = null;
  let eventName = null;

  if (action === 'approve' || status === 'approved') {
    reviewAction = 'approve';
    eventName = 'hospital:approved';
  } else if (action === 'decline' || ['deactivated', 'banned', 'pending'].includes(status)) {
    reviewAction = 'decline';
    eventName = 'hospital:declined';
  }

  if (!reviewAction) {
    return res.status(400).json({
      error: 'Invalid review payload. Use action=approve|decline or status=approved|deactivated|banned|pending',
    });
  }

  const hospital = await reviewHospital(req.params.id, reviewAction);
  if (!hospital) return respondNotFound(res, 'Hospital not found');

  io.emit(eventName, hospital);
  emitOverview();
  return res.json({
    hospital,
    status: reviewAction === 'approve' ? 'approved' : 'deactivated',
    action: reviewAction,
  });
});

app.patch('/api/hospitals/:id/availability', async (req, res) => {
  const hospitalSnapshot = await getHospitalById(req.params.id);
  if (!hospitalSnapshot) return respondNotFound(res, 'Hospital not found');
  if (hospitalSnapshot.status !== 'approved') {
    return res.status(403).json({ error: 'Hospital account is not active' });
  }

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
  if (hospital.status !== 'approved') {
    return res.status(403).json({ error: 'Hospital is not currently active for bookings' });
  }

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

  if (action === 'deactivate' || action === 'ban') {
    const complaints = await listComplaints();
    const targetComplaints = complaints.filter((c) => c.hospitalId === (hospital.id || hospital.hospitalId));
    const patientIds = [...new Set(targetComplaints.map((c) => String(c.patientId || '').trim()).filter(Boolean))];

    const baseMessage = 'The corrupted entity has been neutralized — Batman';
    const title = action === 'ban' ? 'Hospital Permanently Banned' : 'Hospital Deactivated';

    for (const patientId of patientIds) {
      const notification = await createNotification({
        patientId,
        hospitalId: hospital.id || hospital.hospitalId,
        title,
        message: baseMessage,
        type: action,
      });
      io.emit('patient:notification', notification);
    }
  }

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
