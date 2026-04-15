# BookMyHospital (MVP)

Two installable Android apps plus backend API:

- `apps/bmh_client`: Patient + Hospital app
- `apps/bmh_admin`: Admin-only app
- `backend`: Express + Socket.IO service

## What is implemented

### A) Patient + Hospital app
- Role landing: **Join as Patient** or **Join as Hospital**
- Patient flow:
  - Google Sign-In integration (with fallback demo account if OAuth not configured yet)
  - Live hospital availability list (beds, ICU, OT, doctors, surgeons, wait time)
  - Pre-book bed and appointment
  - Complaint submission
- Hospital flow:
  - Registration with hospital profile details and documents link
  - Submission enters **pending verification** queue
  - Approved hospitals can log in with their email to open their own live dashboard

### B) Admin app
- Secure admin code login (demo: `BMH-DEV-2026`)
- Manual verification queue for pending hospitals (approve/decline)
- User usage analytics by location
- Complaint review and strict actions:
  - deactivate hospital
  - permanent ban

### Backend
- REST APIs for auth, hospital registration, approvals, availability updates, bookings, complaints
- Socket.IO event broadcasting hooks for real-time updates
- Seeded demo data:
  - 3 approved hospitals
  - 1 patient account
  - 1 admin/dev account
- MongoDB-backed persistence when `MONGODB_URI` is configured
- Complaint proof uploads served from `/uploads`

## Demo accounts

- Patient: `patient.demo@bmh.in`
- Admin: `admin.demo@bmh.in`
- Hospitals (seeded approved):
  - `citycare@bmh.in`
  - `sunrise@bmh.in`
  - `greenvalley@bmh.in`

## Security note

API keys must be stored in `.env` only. Never hardcode keys in app source.

## Environment

Use `.env` in repository root:

- `PORT`
- `API_BASE_URL`
- `GOOGLE_WEB_CLIENT_ID`
- `FIREBASE_PROJECT_ID`
- `MONGODB_URI`
- `MONGODB_DB_NAME`
- `GROQ_API_KEY`
- `GEMINI_API_KEY`

## Run locally

### 1) Start backend
- Open terminal in `backend`
- Run install and start scripts

### 2) Run patient/hospital app
- Open terminal in `apps/bmh_client`
- Run package install
- Start on Android emulator/device with:
  - Dart define: `API_BASE_URL=http://10.0.2.2:8080` for emulator

### 3) Run admin app
- Open terminal in `apps/bmh_admin`
- Run package install
- Start on Android emulator/device with same API base URL

## Build APKs for Telegram sharing

From each app folder:

- Build debug APK for quick sharing in college demo.
- After setting the production backend URL, rebuild the APKs so they point to the online server.
- APK output location:
  - `build/app/outputs/flutter-apk/app-debug.apk`

Share the two APK files over Telegram:

- `bmh_client` APK (patient + hospital)
- `bmh_admin` APK

## Play Store path later

- Configure Firebase project + Android package IDs + SHA keys
- Replace demo admin code with secure backend auth
- Add cloud media storage (Cloudinary/S3/Firebase Storage) for complaint proofs
- Keep MongoDB Atlas backups and monitoring in place
- Add security hardening, audit logs, and legal compliance docs
- Build release AAB and publish through Play Console
# BookMyHospital (MVP)

Two installable Android apps plus backend API:

- `apps/bmh_client`: Patient + Hospital app
- `apps/bmh_admin`: Admin-only app
- `backend`: Express + Socket.io service

## What is implemented

### A) Patient + Hospital app
- Role landing: **Join as Patient** or **Join as Hospital**
- Patient flow:
  - Google Sign-In integration (with fallback demo account if OAuth not configured yet)
  - Live hospital availability list (beds, ICU, OT, doctors, surgeons, wait time)
  - Pre-book bed and appointment
  - Complaint submission (MVP includes text + backend field for proof URL)
- Hospital flow:
  - Registration with hospital profile details and documents link
  - Submission enters **pending verification** queue
  - Demo approved-hospital dashboard to update live availability

### B) Admin app
 Approved hospitals can log in with their email to open their own live dashboard
- Complaint review and strict actions:
  - deactivate hospital
- REST APIs for auth, hospital registration, approvals, availability updates, bookings, complaints
- Socket.io event broadcasting hooks for real-time updates
- Seeded demo data:
 MongoDB-backed persistence when `MONGODB_URI` is configured
 Complaint proof uploads stored through the backend upload endpoint and served from `/uploads`
  - 3 approved hospitals
  - 1 patient account
  - 1 admin/dev account

 `MONGODB_URI`
 `MONGODB_DB_NAME`
  - `sunrise@bmh.in`
  - `greenvalley@bmh.in`

## Security note

 After setting the production backend URL, rebuild the APKs so they point to the online server.
## Environment

Use `.env` in repository root:

 Keep MongoDB Atlas backups and monitoring in place
- `FIREBASE_PROJECT_ID`
- `GROQ_API_KEY`
- `GEMINI_API_KEY`

## Run locally

### 1) Start backend
- Open terminal in `backend`
- Run install and start scripts

### 2) Run patient/hospital app
- Open terminal in `apps/bmh_client`
- Run package install
- Start on Android emulator/device with:
  - Dart define: `API_BASE_URL=http://10.0.2.2:8080` for emulator

### 3) Run admin app
- Open terminal in `apps/bmh_admin`
- Run package install
- Start on Android emulator/device with same API base URL

## Build APKs for Telegram sharing

From each app folder:

- Build debug APK for quick sharing in college demo.
- APK output location:
  - `build/app/outputs/flutter-apk/app-debug.apk`

Share the two APK files over Telegram:

- `bmh_client` APK (patient + hospital)
- `bmh_admin` APK

## Play Store path later

- Configure Firebase project + Android package IDs + SHA keys
- Replace demo admin code with secure backend auth
- Add proper media upload storage (images/videos) for complaint proofs
- Add production DB (Mongo/Postgres/Firebase) and backups
- Add security hardening, audit logs, and legal compliance docs
- Build release AAB and publish through Play Console
