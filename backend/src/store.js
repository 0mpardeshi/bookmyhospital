const crypto = require('crypto');
const mongoose = require('mongoose');

function getMongoUri() {
  const uri = String(process.env.MONGODB_URI || '').trim();
  if (!uri) return '';
  if (uri.includes('replace_with_') || uri.includes('your_')) return '';
  return uri;
}

const useMongo = Boolean(getMongoUri());
const dbName = process.env.MONGODB_DB_NAME || 'bookmyhospital';

const memory = {
  users: [
    {
      id: 'patient_demo_1',
      role: 'patient',
      name: 'Demo Patient',
      email: 'patient.demo@bmh.in',
      location: 'Pune',
      createdAt: new Date().toISOString(),
    },
    {
      id: 'dev_admin_1',
      role: 'admin',
      name: 'Demo Admin',
      email: 'admin.demo@bmh.in',
      location: 'Pune',
      createdAt: new Date().toISOString(),
    },
  ],
  hospitals: [
    {
      id: 'hosp_1',
      ownerEmail: 'citycare@bmh.in',
      name: 'CityCare Multispeciality Hospital',
      email: 'citycare@bmh.in',
      status: 'approved',
      location: 'Pune',
      specialities: ['Cardiology', 'Trauma', 'Critical Care'],
      bedsTotal: 80,
      bedsAvailable: 11,
      icuTotal: 20,
      icuAvailable: 3,
      otTotal: 7,
      otAvailable: 1,
      doctorsAvailable: 18,
      surgeonsAvailable: 6,
      avgReview: 4.5,
      equipment: ['MRI', 'CT Scan', 'Ventilator', 'Cath Lab'],
      queueWaitMinutes: 34,
      docsSubmitted: true,
      complaintsCount: 0,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    {
      id: 'hosp_2',
      ownerEmail: 'sunrise@bmh.in',
      name: 'Sunrise Emergency & Trauma',
      email: 'sunrise@bmh.in',
      status: 'approved',
      location: 'Mumbai',
      specialities: ['Emergency', 'Orthopedics'],
      bedsTotal: 55,
      bedsAvailable: 8,
      icuTotal: 10,
      icuAvailable: 2,
      otTotal: 4,
      otAvailable: 1,
      doctorsAvailable: 9,
      surgeonsAvailable: 3,
      avgReview: 4.2,
      equipment: ['Ventilator', 'X-Ray', 'ICU Monitoring'],
      queueWaitMinutes: 29,
      docsSubmitted: true,
      complaintsCount: 1,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    {
      id: 'hosp_3',
      ownerEmail: 'greenvalley@bmh.in',
      name: 'Green Valley Women & Child Hospital',
      email: 'greenvalley@bmh.in',
      status: 'approved',
      location: 'Nashik',
      specialities: ['Pediatrics', 'Gynecology'],
      bedsTotal: 42,
      bedsAvailable: 6,
      icuTotal: 8,
      icuAvailable: 2,
      otTotal: 3,
      otAvailable: 1,
      doctorsAvailable: 7,
      surgeonsAvailable: 2,
      avgReview: 4.6,
      equipment: ['NICU', 'Ultrasound'],
      queueWaitMinutes: 21,
      docsSubmitted: true,
      complaintsCount: 0,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
  ],
  bookings: [],
  complaints: [],
  notifications: [],
};

const schemas = {};

function ensureSchemas() {
  if (!useMongo || schemas.User) return;

  const baseOptions = {
    timestamps: true,
    versionKey: false,
    toJSON: {
      virtuals: true,
      transform: (_, ret) => {
        ret.id = ret.id || ret.userId || ret.hospitalId || ret.bookingId || ret.complaintId || String(ret._id);
        delete ret._id;
        return ret;
      },
    },
  };

  const userSchema = new mongoose.Schema(
    {
      userId: { type: String, unique: true, default: () => `user_${crypto.randomUUID()}` },
      role: { type: String, required: true, enum: ['patient', 'hospital', 'admin'] },
      name: { type: String, required: true },
      email: { type: String, required: true, unique: true, index: true },
      location: { type: String, default: 'Unknown' },
      hospitalId: { type: String, default: null },
      status: { type: String, default: 'active' },
      googleId: { type: String, default: null },
    },
    baseOptions,
  );

  const hospitalSchema = new mongoose.Schema(
    {
      hospitalId: { type: String, unique: true, default: () => `hosp_${crypto.randomUUID()}` },
      ownerEmail: { type: String, index: true },
      name: { type: String, required: true },
      email: { type: String, required: true, unique: true, index: true },
      status: { type: String, enum: ['pending', 'approved', 'deactivated', 'banned'], default: 'pending' },
      location: { type: String, required: true, index: true },
      specialities: { type: [String], default: [] },
      equipment: { type: [String], default: [] },
      bedsTotal: { type: Number, default: 0 },
      bedsAvailable: { type: Number, default: 0 },
      icuTotal: { type: Number, default: 0 },
      icuAvailable: { type: Number, default: 0 },
      otTotal: { type: Number, default: 0 },
      otAvailable: { type: Number, default: 0 },
      doctorsAvailable: { type: Number, default: 0 },
      surgeonsAvailable: { type: Number, default: 0 },
      avgReview: { type: Number, default: 0 },
      queueWaitMinutes: { type: Number, default: 30 },
      docsSubmitted: { type: Boolean, default: false },
      complaintsCount: { type: Number, default: 0 },
    },
    baseOptions,
  );

  const bookingSchema = new mongoose.Schema(
    {
      bookingId: { type: String, unique: true, default: () => `book_${crypto.randomUUID()}` },
      hospitalId: { type: String, required: true, index: true },
      hospitalName: { type: String, required: true },
      patientId: { type: String, default: null },
      patientName: { type: String, required: true },
      patientEmail: { type: String, default: null },
      type: { type: String, required: true },
      priority: { type: String, default: 'normal' },
      status: { type: String, default: 'confirmed' },
    },
    baseOptions,
  );

  const complaintSchema = new mongoose.Schema(
    {
      complaintId: { type: String, unique: true, default: () => `comp_${crypto.randomUUID()}` },
      hospitalId: { type: String, required: true, index: true },
      hospitalName: { type: String, required: true },
      patientId: { type: String, default: null },
      patientName: { type: String, required: true },
      description: { type: String, required: true },
      proofUrls: { type: [String], default: [] },
      status: { type: String, default: 'open' },
    },
    baseOptions,
  );

  const notificationSchema = new mongoose.Schema(
    {
      notificationId: { type: String, unique: true, default: () => `note_${crypto.randomUUID()}` },
      patientId: { type: String, required: true, index: true },
      hospitalId: { type: String, default: null },
      title: { type: String, required: true },
      message: { type: String, required: true },
      type: { type: String, default: 'info' },
      read: { type: Boolean, default: false },
    },
    baseOptions,
  );

  schemas.User = mongoose.models.User || mongoose.model('User', userSchema);
  schemas.Hospital = mongoose.models.Hospital || mongoose.model('Hospital', hospitalSchema);
  schemas.Booking = mongoose.models.Booking || mongoose.model('Booking', bookingSchema);
  schemas.Complaint = mongoose.models.Complaint || mongoose.model('Complaint', complaintSchema);
  schemas.Notification = mongoose.models.Notification || mongoose.model('Notification', notificationSchema);
}

function normalize(record, type) {
  if (!record) return null;
  if (record.toJSON) return record.toJSON();
  const plain = { ...record };
  if (type === 'hospital') plain.id = plain.id || plain.hospitalId;
  if (type === 'booking') plain.id = plain.id || plain.bookingId;
  if (type === 'complaint') plain.id = plain.id || plain.complaintId;
  if (type === 'notification') plain.id = plain.id || plain.notificationId;
  if (type === 'user') plain.id = plain.id || plain.userId;
  return plain;
}

function normalizeList(list, type) {
  return list.map((item) => normalize(item, type));
}

async function connectMongo() {
  if (!useMongo) return false;
  ensureSchemas();
  if (mongoose.connection.readyState !== 1) {
    await mongoose.connect(getMongoUri(), {
      dbName,
      serverSelectionTimeoutMS: 10000,
    });
  }
  return true;
}

async function seedMongoIfNeeded() {
  if (!useMongo) return;
  ensureSchemas();

  const counts = await Promise.all([
    schemas.User.countDocuments(),
    schemas.Hospital.countDocuments(),
  ]);

  if (counts[0] === 0) {
    await schemas.User.insertMany(memory.users.map((u) => ({ ...u, userId: u.id })));
  }
  if (counts[1] === 0) {
    await schemas.Hospital.insertMany(
      memory.hospitals.map((h) => ({
        ...h,
        hospitalId: h.id,
        status: h.status,
      })),
    );
  }
}

async function listUsers() {
  if (useMongo) return normalizeList(await schemas.User.find().sort({ createdAt: 1 }), 'user');
  return memory.users;
}

async function findUserByEmail(email) {
  if (useMongo) return normalize(await schemas.User.findOne({ email }), 'user');
  return memory.users.find((u) => u.email.toLowerCase() === String(email).toLowerCase()) || null;
}

async function upsertUser(user) {
  if (useMongo) {
    ensureSchemas();
    const saved = await schemas.User.findOneAndUpdate(
      { email: user.email },
      { $set: user, $setOnInsert: { userId: `user_${crypto.randomUUID()}` } },
      { upsert: true, new: true },
    );
    return normalize(saved, 'user');
  }
  const idx = memory.users.findIndex((u) => u.email.toLowerCase() === String(user.email).toLowerCase());
  if (idx >= 0) {
    memory.users[idx] = { ...memory.users[idx], ...user };
    return memory.users[idx];
  }
  const created = { id: `user_${Date.now()}`, createdAt: new Date().toISOString(), ...user };
  memory.users.push(created);
  return created;
}

async function listHospitals({ status = 'approved', location } = {}) {
  if (useMongo) {
    ensureSchemas();
    const query = {};
    if (status) query.status = status;
    if (location) query.location = new RegExp(`^${location}$`, 'i');
    const hospitals = await schemas.Hospital.find(query).sort({ createdAt: 1 });
    return normalizeList(hospitals, 'hospital');
  }
  const list = status === 'pending'
    ? memory.hospitals.filter((h) => h.status === 'pending')
    : memory.hospitals.filter((h) => h.status === status);
  return location ? list.filter((h) => h.location.toLowerCase() === String(location).toLowerCase()) : list;
}

async function getHospitalById(id) {
  if (useMongo) {
    ensureSchemas();
    return normalize(await schemas.Hospital.findOne({ $or: [{ hospitalId: id }, { _id: id }] }), 'hospital');
  }
  return memory.hospitals.find((h) => h.id === id) || null;
}

async function findHospitalByEmail(email) {
  if (useMongo) {
    ensureSchemas();
    return normalize(await schemas.Hospital.findOne({ email }), 'hospital');
  }
  return memory.hospitals.find((h) => h.email.toLowerCase() === String(email).toLowerCase()) || null;
}

async function createPendingHospital(payload) {
  if (useMongo) {
    ensureSchemas();
    const hospital = await schemas.Hospital.create({
      ...payload,
      status: 'pending',
      docsSubmitted: true,
      queueWaitMinutes: Number(payload.queueWaitMinutes || 30),
    });
    return normalize(hospital, 'hospital');
  }

  const hospital = {
    id: `pending_${Date.now()}`,
    ...payload,
    status: 'pending',
    docsSubmitted: true,
    queueWaitMinutes: Number(payload.queueWaitMinutes || 30),
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  memory.hospitals.push(hospital);
  return hospital;
}

async function reviewHospital(id, action) {
  if (useMongo) {
    ensureSchemas();
    const hospital = await schemas.Hospital.findOne({ $or: [{ hospitalId: id }, { _id: id }] });
    if (!hospital) return null;
    if (action === 'approve') hospital.status = 'approved';
    if (action === 'decline') hospital.status = 'deactivated';
    await hospital.save();
    return normalize(hospital, 'hospital');
  }

  const index = memory.hospitals.findIndex((h) => h.id === id);
  if (index < 0) return null;
  const hospital = memory.hospitals[index];
  if (action === 'approve') hospital.status = 'approved';
  if (action === 'decline') hospital.status = 'deactivated';
  memory.hospitals[index] = hospital;
  return hospital;
}

async function updateHospitalAvailability(id, updates) {
  if (useMongo) {
    ensureSchemas();
    const hospital = await schemas.Hospital.findOne({ $or: [{ hospitalId: id }, { _id: id }] });
    if (!hospital) return null;
    const keys = ['bedsAvailable', 'icuAvailable', 'otAvailable', 'doctorsAvailable', 'surgeonsAvailable', 'queueWaitMinutes'];
    keys.forEach((key) => {
      if (Object.prototype.hasOwnProperty.call(updates, key)) {
        hospital[key] = Number(updates[key]);
      }
    });
    await hospital.save();
    return normalize(hospital, 'hospital');
  }

  const hospital = memory.hospitals.find((h) => h.id === id);
  if (!hospital) return null;
  ['bedsAvailable', 'icuAvailable', 'otAvailable', 'doctorsAvailable', 'surgeonsAvailable', 'queueWaitMinutes'].forEach((key) => {
    if (Object.prototype.hasOwnProperty.call(updates, key)) {
      hospital[key] = Number(updates[key]);
    }
  });
  hospital.updatedAt = new Date().toISOString();
  return hospital;
}

async function createBooking(payload) {
  if (useMongo) {
    ensureSchemas();
    const booking = await schemas.Booking.create(payload);
    return normalize(booking, 'booking');
  }
  const booking = {
    id: `book_${Date.now()}`,
    ...payload,
    createdAt: new Date().toISOString(),
  };
  memory.bookings.push(booking);
  return booking;
}

async function listBookings({ hospitalId } = {}) {
  if (useMongo) {
    ensureSchemas();
    const query = hospitalId ? { hospitalId } : {};
    return normalizeList(await schemas.Booking.find(query).sort({ createdAt: -1 }), 'booking');
  }
  const bookings = hospitalId ? memory.bookings.filter((b) => b.hospitalId === hospitalId) : memory.bookings;
  return bookings;
}

async function createComplaint(payload) {
  if (useMongo) {
    ensureSchemas();
    const complaint = await schemas.Complaint.create(payload);
    return normalize(complaint, 'complaint');
  }
  const complaint = {
    id: `comp_${Date.now()}`,
    ...payload,
    status: 'open',
    createdAt: new Date().toISOString(),
  };
  memory.complaints.push(complaint);
  return complaint;
}

async function listComplaints() {
  if (useMongo) {
    ensureSchemas();
    return normalizeList(await schemas.Complaint.find().sort({ createdAt: -1 }), 'complaint');
  }
  return memory.complaints;
}

async function createNotification(payload) {
  if (useMongo) {
    ensureSchemas();
    const notification = await schemas.Notification.create(payload);
    return normalize(notification, 'notification');
  }
  const notification = {
    id: `note_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
    ...payload,
    read: Boolean(payload.read || false),
    createdAt: new Date().toISOString(),
  };
  memory.notifications.unshift(notification);
  return notification;
}

async function listPatientNotifications(patientId) {
  if (useMongo) {
    ensureSchemas();
    return normalizeList(
      await schemas.Notification.find({ patientId }).sort({ createdAt: -1 }).limit(100),
      'notification',
    );
  }
  return memory.notifications
    .filter((n) => n.patientId === patientId)
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
    .slice(0, 100);
}

async function disciplineHospital(id, action) {
  if (useMongo) {
    ensureSchemas();
    const hospital = await schemas.Hospital.findOne({ $or: [{ hospitalId: id }, { _id: id }] });
    if (!hospital) return null;
    if (hospital.status === 'banned') return hospital;
    if (action === 'ban') hospital.status = 'banned';
    if (action === 'deactivate') hospital.status = 'deactivated';
    if (action === 'activate') hospital.status = 'approved';
    await hospital.save();
    return normalize(hospital, 'hospital');
  }

  const hospital = memory.hospitals.find((h) => h.id === id);
  if (!hospital) return null;
  if (hospital.status === 'banned') return hospital;
  if (action === 'ban') hospital.status = 'banned';
  if (action === 'deactivate') hospital.status = 'deactivated';
  if (action === 'activate') hospital.status = 'approved';
  hospital.updatedAt = new Date().toISOString();
  return hospital;
}

async function overview() {
  const hospitals = await listHospitals({ status: 'approved' });
  const pendingHospitals = await listHospitals({ status: 'pending' });
  const complaints = await listComplaints();
  const bookings = await listBookings();
  const users = await listUsers();

  return {
    hospitalsTotal: hospitals.length + pendingHospitals.length,
    hospitalsApproved: hospitals.length,
    hospitalsPending: pendingHospitals.length,
    complaints,
    usersByLocation: users.reduce((acc, user) => {
      const key = user.location || 'Unknown';
      acc[key] = (acc[key] || 0) + 1;
      return acc;
    }, {}),
    bookings,
    activePatients: users.filter((u) => u.role === 'patient').length,
  };
}

async function hospitalAuth({ email }) {
  const hospital = await findHospitalByEmail(email);
  if (!hospital) return null;
  return hospital.status === 'approved' ? hospital : null;
}

module.exports = {
  useMongo,
  connectMongo,
  seedMongoIfNeeded,
  upsertUser,
  findUserByEmail,
  listHospitals,
  getHospitalById,
  findHospitalByEmail,
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
};
