-- ============================================================================
-- BookMyHospital Phase 4
-- HQR verification + anti-fraud security
-- ============================================================================

create extension if not exists pgcrypto;

create schema if not exists app;

-- --------------------------------------------------------------------------
-- HQR token registry (single-use enforcement)
-- --------------------------------------------------------------------------

create table if not exists app.hqr_tokens (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references app.appointments(id) on delete cascade,
  facility_id uuid not null,
  issued_for_user_id uuid not null references auth.users(id) on delete restrict,
  token_nonce text not null,
  token_hash text not null unique,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_hqr_tokens_valid_window check (expires_at > issued_at)
);

create index if not exists idx_hqr_tokens_appointment on app.hqr_tokens(appointment_id);
create index if not exists idx_hqr_tokens_expires_at on app.hqr_tokens(expires_at);
create index if not exists idx_hqr_tokens_nonce on app.hqr_tokens(token_nonce);

drop trigger if exists trg_hqr_tokens_touch_updated_at on app.hqr_tokens;
create trigger trg_hqr_tokens_touch_updated_at
before update on app.hqr_tokens
for each row execute procedure app.touch_updated_at();

-- --------------------------------------------------------------------------
-- HQR verification attempts (rate limiting + forensics)
-- --------------------------------------------------------------------------

create table if not exists app.hqr_verification_attempts (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  appointment_id uuid references app.appointments(id) on delete set null,
  facility_id uuid,
  token_hash text,
  success boolean not null default false,
  reason text not null,
  requester_ip text,
  created_at timestamptz not null default now()
);

create index if not exists idx_hqr_attempts_actor_created
  on app.hqr_verification_attempts(actor_user_id, created_at desc);
create index if not exists idx_hqr_attempts_appointment_created
  on app.hqr_verification_attempts(appointment_id, created_at desc);
create index if not exists idx_hqr_attempts_token_hash
  on app.hqr_verification_attempts(token_hash);

-- --------------------------------------------------------------------------
-- Check-in state on appointments
-- --------------------------------------------------------------------------

alter table app.appointments
  add column if not exists checked_in_at timestamptz,
  add column if not exists checked_in_by_user_id uuid references auth.users(id) on delete set null;

create index if not exists idx_appointments_checked_in_at
  on app.appointments(checked_in_at);

-- --------------------------------------------------------------------------
-- Enable RLS and keep direct client access blocked.
-- Edge functions use service role key and bypass RLS.
-- --------------------------------------------------------------------------

alter table app.hqr_tokens enable row level security;
alter table app.hqr_verification_attempts enable row level security;

drop policy if exists p_hqr_tokens_no_client_access on app.hqr_tokens;
create policy p_hqr_tokens_no_client_access
on app.hqr_tokens
as restrictive
for all
to authenticated
using (false)
with check (false);

drop policy if exists p_hqr_attempts_no_client_access on app.hqr_verification_attempts;
create policy p_hqr_attempts_no_client_access
on app.hqr_verification_attempts
as restrictive
for all
to authenticated
using (false)
with check (false);
