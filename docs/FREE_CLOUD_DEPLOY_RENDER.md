# BookMyHospital Backend — $0 Cloud Deployment (Render Free)

This guide moves backend hosting off your laptop to Render Free (always online, no same-Wi-Fi dependency).

## What is already prepared in this repo

- `render.yaml` at repo root (Blueprint config)
- `backend/Dockerfile`
- `backend/.dockerignore`
- `.gitignore` updated for secrets and build outputs

## 1) Prerequisites (free)

- GitHub account (free)
- Render account (free) — sign in with GitHub
- MongoDB Atlas free cluster URI
- Cloudinary free account keys (optional but recommended for media)

## 2) Push this project to GitHub

Run these commands from project root:

1. `cd /home/om/$/bookmyhospital`
2. `git init`
3. `git config user.name "Om"`
4. `git config user.email "om@example.com"`
5. `git add .`
6. `git commit -m "Prepare cloud deployment on Render Free"`
7. `git branch -M main`
8. Create an empty GitHub repo named `bookmyhospital`
9. `git remote add origin https://github.com/<YOUR_GITHUB_USERNAME>/bookmyhospital.git`
10. `git push -u origin main`

## 3) Deploy on Render (Free)

1. Open Render Dashboard → **New +** → **Blueprint**.
2. Select your `bookmyhospital` repo.
3. Render detects `render.yaml` automatically.
4. Click **Apply**.

## 4) Set environment variables on Render service

In service settings, add real values:

- `MONGODB_URI=<your real atlas uri>`
- `MONGODB_DB_NAME=bookmyhospital`
- `CLOUDINARY_CLOUD_NAME=<real>`
- `CLOUDINARY_API_KEY=<real>`
- `CLOUDINARY_API_SECRET=<real>`
- `CLOUDINARY_FOLDER=bookmyhospital/complaints`
- `API_BASE_URL=https://<your-render-service>.onrender.com`

## 5) Validate cloud backend

- Open `https://<your-render-service>.onrender.com/health`
- Expect: `{ "ok": true, ... }`

## 6) Build APKs against cloud backend URL

Client APK:
- `cd /home/om/$/bookmyhospital/apps/bmh_client`
- `flutter pub get`
- `flutter build apk --debug --dart-define=API_BASE_URL=https://<your-render-service>.onrender.com`

Admin APK:
- `cd /home/om/$/bookmyhospital/apps/bmh_admin`
- `flutter pub get`
- `flutter build apk --debug --dart-define=API_BASE_URL=https://<your-render-service>.onrender.com`

## Output APK locations

- Client: `apps/bmh_client/build/app/outputs/flutter-apk/app-debug.apk`
- Admin: `apps/bmh_admin/build/app/outputs/flutter-apk/app-debug.apk`

## Notes for free tier

- Render free services may sleep on inactivity; first request after sleep can be slow.
- This is still far more stable than laptop+tunnel and removes same-network dependency.
- For truly no-sleep behavior later, switch to paid plan.
