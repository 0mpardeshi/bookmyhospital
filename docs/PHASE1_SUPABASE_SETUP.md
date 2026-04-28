# Phase 1 Setup — Supabase Free Tier + Cloudflare Proxy

This guide is executable end-to-end for BookMyHospital Phase 1.

## 0) First-run workspace commands (already wired)

From repository root:

```bash
npm run phase1:tools:check
npm run phase1:supabase:login
npm run phase1:supabase:link
npm run phase1:supabase:db:push
npm run phase1:proxy:secret:url
npm run phase1:proxy:secret:anon
npm run phase1:proxy:deploy
```

These scripts are preconfigured in root `package.json`.

---

## 1) Create Supabase Project (Free)

1. Open Supabase dashboard and create a new project.
2. Select nearest region to users for lower latency.
3. Wait until project status becomes healthy.

**Critical:** keep the following project values ready from Settings → API:
- Project URL
- Anon key

---

## 2) Apply Phase 1 SQL (Schema + RLS)

Run these in Supabase SQL Editor in this order:

1. `supabase/migrations/20260425_phase1_schema.sql`
2. `supabase/migrations/20260425_phase1_rls.sql`

**Critical validation after run:**
- Tables exist in `app` schema.
- RLS is enabled on all Phase 1 tables.

---

## 3) Configure JWT role claims for users

RLS expects `app_metadata.role` in JWT.

Examples (run in SQL Editor):

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"patient"}'::jsonb
where email = 'patient@bookmyhospital.in';

update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"hospital"}'::jsonb
where email = 'hospital@bookmyhospital.in';

update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"clinic"}'::jsonb
where email = 'clinic@bookmyhospital.in';
```

**Critical:** users must sign out/sign in again after role update so new JWT contains role claim.

---

## 4) Deploy Cloudflare Worker Proxy

### Install toolchain

- Install Node.js LTS
- Install Wrangler CLI:

```bash
npm i -g wrangler
wrangler login
```

### Deploy

From `infra/cloudflare` folder:

```bash
wrangler secret put SUPABASE_URL
wrangler secret put SUPABASE_ANON_KEY
wrangler deploy
```

When prompted:
- `SUPABASE_URL` = exact Supabase Project URL
- `SUPABASE_ANON_KEY` = exact Supabase anon key

Worker URL format after deploy:
- `https://bookmyhospital-supabase-proxy.<account>.workers.dev`

---

## 5) Environment Variables to use

Use these exact variable names in app/build/deploy pipelines:

### Flutter app runtime
- `BMH_SUPABASE_PROXY_URL`
- `BMH_ENV`

### Cloudflare Worker secrets
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

### Supabase server-side (Edge Functions later phases)
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`

---

## 6) Security requirements (must follow)

1. Client app calls Worker URL only.
2. Client app never calls `*.supabase.co` directly in production.
3. Service role key is never stored in client app.
4. Authorization Bearer JWT must be forwarded for RLS enforcement.

---

## 7) Quick verification checklist

1. Patient login can read/update only own patient row.
2. Hospital login cannot read another hospital private record.
3. Clinic login cannot update hospital-owned data.
4. Unknown proxy routes return `404` from Worker.
5. Requests without valid JWT fail scoped data access under RLS.
