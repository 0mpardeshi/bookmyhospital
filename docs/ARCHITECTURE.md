# BookMyHospital Architecture (MVP)

## Components

1. **Client App (`bmh_client`)**
   - Patient onboarding and emergency booking flow
   - Hospital registration and live inventory update flow

2. **Admin App (`bmh_admin`)**
   - Manual hospital verification
   - Complaint governance and disciplinary controls
   - Location-based usage analytics

3. **Backend (`backend`)**
   - API gateway for both apps
   - Socket.io real-time event stream
   - Seeded in-memory store for demo

## Key Domain Objects

- User (`patient`, `admin`)
- Hospital (`pending`, `approved`, `deactivated`, `banned`)
- Booking
- Complaint

## Real-time Events

- `overview:update`
- `hospital:pending`
- `hospital:approved`
- `hospital:availability-updated`
- `booking:created`
- `complaint:created`

## Security & Scale Notes

- Replace demo auth with JWT-based role auth and refresh tokens
- Use signed URL upload for complaint proof files
- Add moderation workflow with immutable audit trail
- Add district/state-level analytics for policy reporting
- For government pitch: include uptime, SLA, encryption at rest, incident response policy
