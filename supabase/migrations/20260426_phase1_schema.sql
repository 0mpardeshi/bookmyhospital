-- ============================================================================
-- BookMyHospital Phase 1 - Core Schema
-- Stack target: Supabase PostgreSQL
-- Scope: patients, hospitals, clinics, doctors, appointments, notifications
-- ============================================================================

-- Critical: UUID generation for primary keys.
create extension if not exists pgcrypto;

-- Critical: case-insensitive unique emails.
create extension if not exists citext;

-- Keep app objects isolated in dedicated schema.
create schema if not exists app;

-- --------------------------------------------------------------------------
-- Enums
-- --------------------------------------------------------------------------

-- Role values expected in auth JWT app_metadata.role.
create type app.user_role as enum ('patient', 'hospital', 'clinic', 'admin');

-- Appointment workflow states for MVP + future live sync.
create type app.appointment_status as enum (
  'pending',
  'confirmed',
  'delayed',
  'completed',
  'cancelled',
  'declined'
);

-- Notification categories used by mobile UI and filtering.
create type app.notification_type as enum ('system', 'appointment', 'reminder', 'critical');

-- --------------------------------------------------------------------------
-- Shared functions
-- --------------------------------------------------------------------------

-- Returns current authenticated role from JWT; empty string if missing.
create or replace function app.current_role()
returns text
language sql
stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
$$;

-- Convenience helper for admin checks inside policies.
create or replace function app.is_admin()
returns boolean
language sql
stable
as $$
  select app.current_role() = 'admin';
$$;

-- Reusable trigger to keep updated_at correct.
create or replace function app.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- --------------------------------------------------------------------------
-- patients
-- --------------------------------------------------------------------------

create table if not exists app.patients (
  -- Critical: one-to-one with Supabase auth user.
  user_id uuid primary key references auth.users(id) on delete cascade,

  full_name text not null check (char_length(trim(full_name)) >= 2),
  email citext not null unique,
  phone text not null check (char_length(trim(phone)) between 8 and 20),
  date_of_birth date,
  city text not null,
  state text not null,

  -- HIPAA-aligned consent capture (explicit booleans).
  consent_treatment boolean not null default false,
  consent_data_processing boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_patients_touch_updated_at
before update on app.patients
for each row execute procedure app.touch_updated_at();

-- --------------------------------------------------------------------------
-- hospitals
-- --------------------------------------------------------------------------

create table if not exists app.hospitals (
  id uuid primary key default gen_random_uuid(),

  -- Critical: owner account for auth + RLS ownership checks.
  owner_user_id uuid not null unique references auth.users(id) on delete restrict,

  legal_name text not null,
  registration_number text not null unique,
  email citext not null unique,
  phone text not null check (char_length(trim(phone)) between 8 and 20),

  address_line1 text not null,
  address_line2 text,
  city text not null,
  state text not null,
  postal_code text not null,

  latitude numeric(9,6),
  longitude numeric(9,6),

  -- Critical: provider must be verified + active for patient-facing visibility.
  verified boolean not null default false,
  active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_hospitals_city_state on app.hospitals(city, state);
create index if not exists idx_hospitals_verified_active on app.hospitals(verified, active);

create trigger trg_hospitals_touch_updated_at
before update on app.hospitals
for each row execute procedure app.touch_updated_at();

-- --------------------------------------------------------------------------
-- clinics
-- --------------------------------------------------------------------------

create table if not exists app.clinics (
  id uuid primary key default gen_random_uuid(),

  -- Critical: clinic owner identity for role-based control.
  owner_user_id uuid not null unique references auth.users(id) on delete restrict,

  -- Nullable to allow independent clinics not attached to hospitals.
  hospital_id uuid references app.hospitals(id) on delete set null,

  legal_name text not null,
  registration_number text not null unique,
  email citext not null unique,
  phone text not null check (char_length(trim(phone)) between 8 and 20),

  address_line1 text not null,
  address_line2 text,
  city text not null,
  state text not null,
  postal_code text not null,

  latitude numeric(9,6),
  longitude numeric(9,6),

  verified boolean not null default false,
  active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_clinics_hospital_id on app.clinics(hospital_id);
create index if not exists idx_clinics_city_state on app.clinics(city, state);
create index if not exists idx_clinics_verified_active on app.clinics(verified, active);

create trigger trg_clinics_touch_updated_at
before update on app.clinics
for each row execute procedure app.touch_updated_at();

-- --------------------------------------------------------------------------
-- doctors
-- --------------------------------------------------------------------------

create table if not exists app.doctors (
  id uuid primary key default gen_random_uuid(),

  -- Doctor belongs to exactly one provider type.
  hospital_id uuid references app.hospitals(id) on delete cascade,
  clinic_id uuid references app.clinics(id) on delete cascade,

  full_name text not null check (char_length(trim(full_name)) >= 2),
  license_number text not null unique,
  specialty text not null,
  email citext unique,
  phone text check (char_length(trim(phone)) between 8 and 20),

  years_experience integer not null default 0 check (years_experience >= 0),
  available boolean not null default true,
  active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Critical integrity: one and only one provider link.
  constraint chk_doctor_exactly_one_provider
    check (num_nonnulls(hospital_id, clinic_id) = 1)
);

create index if not exists idx_doctors_hospital_id on app.doctors(hospital_id);
create index if not exists idx_doctors_clinic_id on app.doctors(clinic_id);
create index if not exists idx_doctors_specialty on app.doctors(specialty);

create trigger trg_doctors_touch_updated_at
before update on app.doctors
for each row execute procedure app.touch_updated_at();

-- --------------------------------------------------------------------------
-- appointments
-- --------------------------------------------------------------------------

create table if not exists app.appointments (
  id uuid primary key default gen_random_uuid(),

  -- Critical: patient is linked to authenticated identity.
  patient_user_id uuid not null references app.patients(user_id) on delete cascade,

  doctor_id uuid not null references app.doctors(id) on delete restrict,

  -- Appointment is attached to exactly one provider type.
  hospital_id uuid references app.hospitals(id) on delete restrict,
  clinic_id uuid references app.clinics(id) on delete restrict,

  status app.appointment_status not null default 'pending',

  reason text not null check (char_length(trim(reason)) >= 3),
  scheduled_start_at timestamptz not null,
  scheduled_end_at timestamptz not null,

  -- Optional lifecycle audit fields.
  cancelled_by_user_id uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz,
  cancellation_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chk_appointment_time_range
    check (scheduled_end_at > scheduled_start_at),

  constraint chk_appointment_exactly_one_provider
    check (num_nonnulls(hospital_id, clinic_id) = 1)
);

create index if not exists idx_appointments_patient_user_id on app.appointments(patient_user_id);
create index if not exists idx_appointments_doctor_id on app.appointments(doctor_id);
create index if not exists idx_appointments_hospital_id on app.appointments(hospital_id);
create index if not exists idx_appointments_clinic_id on app.appointments(clinic_id);
create index if not exists idx_appointments_status_start on app.appointments(status, scheduled_start_at);

create trigger trg_appointments_touch_updated_at
before update on app.appointments
for each row execute procedure app.touch_updated_at();

-- --------------------------------------------------------------------------
-- notifications
-- --------------------------------------------------------------------------

create table if not exists app.notifications (
  id uuid primary key default gen_random_uuid(),

  -- Critical: recipient defines row ownership for RLS.
  recipient_user_id uuid not null references auth.users(id) on delete cascade,

  sender_user_id uuid references auth.users(id) on delete set null,
  appointment_id uuid references app.appointments(id) on delete set null,

  type app.notification_type not null default 'system',
  title text not null,
  body text not null,

  is_read boolean not null default false,
  read_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_notifications_recipient_created
  on app.notifications(recipient_user_id, created_at desc);

create index if not exists idx_notifications_read
  on app.notifications(is_read);

create trigger trg_notifications_touch_updated_at
before update on app.notifications
for each row execute procedure app.touch_updated_at();

-- --------------------------------------------------------------------------
-- Base grants (RLS still controls row access)
-- --------------------------------------------------------------------------

grant usage on schema app to authenticated;
grant select, insert, update on app.patients to authenticated;
grant select, insert, update on app.hospitals to authenticated;
grant select, insert, update on app.clinics to authenticated;
grant select, insert, update on app.doctors to authenticated;
grant select, insert, update on app.appointments to authenticated;
grant select, insert, update on app.notifications to authenticated;
