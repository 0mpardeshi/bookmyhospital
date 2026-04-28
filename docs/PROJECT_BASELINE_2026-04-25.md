# BookMyHospital — Technical Baseline (2026-04-25)

## Objective
Establish an evidence-based snapshot of what is in the repository, what is deployed, and what versions are currently in use so future complex updates can be done safely.

## Repository footprint
- Monorepo contains:
  - `apps/bmh_client` (Flutter app for Patient + Hospital)
  - `apps/bmh_admin` (Flutter app for Admin)
  - `backend` (Node.js + Express + Socket.IO API)
  - `render.yaml` (Render blueprint)
  - `docs/*` (architecture/deployment/viva docs)
- GitHub default branch: `main`
- Public repo URL: `https://github.com/0mpardeshi/bookmyhospital`

## Version and release evidence
### Client app (`apps/bmh_client`)
- In-code build marker: `R4 2026-04-16` (in `lib/main.dart`)
- `pubspec.yaml` version: `1.0.2+3`
- Git tag exists: `stable-client-r4-20260416`
- Tag points to commit: `871b47e`

### Admin app (`apps/bmh_admin`)
- In-code build marker: `R5 2026-04-16` (in `lib/main.dart`)
- `pubspec.yaml` version: `1.0.3+4`
- Git tag exists for phone baseline: `stable-admin-r2-20260416`
- R2 tag points to commit: `eddd674`
- Newer admin commit on `main`: `134b8fd` (R5 auth retry + URL normalization)

### Important implication
- Your phone statement is consistent with tags: client is on R4, admin baseline tag is R2.
- Current `main` branch includes newer admin improvements (R5 code) than your R2 phone build.

## Backend baseline
- Active entrypoint by `backend/package.json`: `src/server.js`
- Runtime/deploy target from `render.yaml`:
  - rootDir: `backend`
  - build: `npm ci`
  - start: `npm run start`
  - health: `/health`
- Data layer: `backend/src/store.js`
- Supports MongoDB (if configured), otherwise in-memory fallback.
- Complaint media uploads:
  - Cloudinary when keys are present
  - local `/uploads` fallback otherwise
- AI helper flow:
  - data-aware local recommendation engine first
  - Gemini/Groq optional provider fallback
  - local text fallback if providers unavailable

## Deployment state (external checks)
- GitHub repo reachable and contains expected top-level folders/files.
- Render health endpoint check attempted at:
  - `https://bookmyhospital-api.onrender.com/health`
  - Returned HTTP 503 during check window (likely free-tier cold start / temporary unavailability).

## Key commit timeline (Apr 15–16, 2026)
- `68e154c` Pre-production deploy config + dashboards + complaint media
- `8a3ef7d` Fix hospital approval endpoint payload compatibility
- `b745bd6` Admin workflow hardening
- `da58c9e` Production hardening for admin auth/config
- `e539df9` Polling tuning for low network
- `8cd3f19` AI assistant + notifications + resilience
- `eddd674` Build/version marker bump
- `2884008` Ratings + status lock + data-aware AI
- `871b47e` R4 Render cold-start auth/AI fixes
- `134b8fd` Admin R5 auth retry + URL normalization

## Architecture summary
- Flutter apps are currently implemented as largely single-file app logic (`lib/main.dart` in both apps).
- Backend is API + realtime socket events.
- Admin controls verification and disciplinary actions.
- Client supports patient booking, complaints, ratings, and hospital dashboard with account status lock behavior.

## Risks and technical debt discovered
1. **Legacy duplicate backend file**
   - `backend/src/index.js` appears legacy and includes duplicated code regions.
   - Not runtime-critical currently (because `start` points to `server.js`), but a maintenance hazard.
2. **Monolithic app files**
   - Both Flutter apps keep most logic in single `main.dart`; future feature velocity will suffer without modularization.
3. **Render free-tier reliability**
   - health check can return 503/slow first hit when sleeping.
4. **Default Flutter identifiers**
   - Android application IDs remain `com.example.*` (not production brand IDs).
5. **No GitHub Releases objects**
   - Tags exist, but formal release pages are not populated with release notes/binaries.

## What was done during this baseline task
- Added root `.env` placeholder file for safer local/dev setup alignment:
  - `/home/om/$/bookmyhospital-git/.env`
  - Contains non-secret placeholders and expected keys.

## Confidence statement
- Based on source + commit history + tags, repository appears internally consistent for the known lifecycle (R2/R4/R5 progression).
- It is not possible to prove recovery of files that were deleted from an older local machine unless there is another remote backup or historical repository.
- For practical engineering purposes, current GitHub repo is sufficient to proceed with structured upgrades.

## Recommended next move before major feature work
1. Freeze a branch: `baseline-2026-04-25`.
2. Modularize apps (`main.dart` split by features/services/models/widgets).
3. Remove or archive legacy `backend/src/index.js` to prevent confusion.
4. Add API contract doc + smoke tests for critical routes.
5. Add build pipeline to generate signed APK artifacts per tag.
