-- ============================================================================
-- BookMyHospital Phase 1 - Row Level Security policies
-- Scope: patient / hospital / clinic role isolation
-- Executed AFTER schema migration so tables exist
-- ============================================================================

-- --------------------------------------------------------------------------
-- Enable RLS on all app tables
-- --------------------------------------------------------------------------

alter table app.patients enable row level security;
alter table app.hospitals enable row level security;
alter table app.clinics enable row level security;
alter table app.doctors enable row level security;
alter table app.appointments enable row level security;
alter table app.notifications enable row level security;

-- --------------------------------------------------------------------------
-- patients
-- --------------------------------------------------------------------------

-- Patient can read own profile; admin can read all.
drop policy if exists patients_select_self_or_admin on app.patients;
create policy patients_select_self_or_admin
on app.patients
for select
to authenticated
using (
  auth.uid() = user_id
  or app.is_admin()
);

-- Patient can insert only own profile.
drop policy if exists patients_insert_self on app.patients;
create policy patients_insert_self
on app.patients
for insert
to authenticated
with check (
  auth.uid() = user_id
  and app.current_role() = 'patient'
);

-- Patient can update only own profile; admin override allowed.
drop policy if exists patients_update_self_or_admin on app.patients;
create policy patients_update_self_or_admin
on app.patients
for update
to authenticated
using (
  auth.uid() = user_id
  or app.is_admin()
)
with check (
  auth.uid() = user_id
  or app.is_admin()
);

-- --------------------------------------------------------------------------
-- hospitals
-- --------------------------------------------------------------------------

-- Patients/clinics can read only verified+active hospitals.
-- Hospital owner can read own record; admin can read all.
drop policy if exists hospitals_select_scoped on app.hospitals;
create policy hospitals_select_scoped
on app.hospitals
for select
to authenticated
using (
  (
    verified = true
    and active = true
    and app.current_role() in ('patient', 'clinic')
  )
  or (
    owner_user_id = auth.uid()
    and app.current_role() = 'hospital'
  )
  or app.is_admin()
);

-- Hospital role can insert only own hospital record.
drop policy if exists hospitals_insert_owner on app.hospitals;
create policy hospitals_insert_owner
on app.hospitals
for insert
to authenticated
with check (
  owner_user_id = auth.uid()
  and app.current_role() = 'hospital'
);

-- Owner/admin update scope.
drop policy if exists hospitals_update_owner_or_admin on app.hospitals;
create policy hospitals_update_owner_or_admin
on app.hospitals
for update
to authenticated
using (
  owner_user_id = auth.uid()
  or app.is_admin()
)
with check (
  owner_user_id = auth.uid()
  or app.is_admin()
);

-- --------------------------------------------------------------------------
-- clinics
-- --------------------------------------------------------------------------

-- Patients/hospitals can read only verified+active clinics.
-- Clinic owner can read own record; admin can read all.
drop policy if exists clinics_select_scoped on app.clinics;
create policy clinics_select_scoped
on app.clinics
for select
to authenticated
using (
  (
    verified = true
    and active = true
    and app.current_role() in ('patient', 'hospital')
  )
  or (
    owner_user_id = auth.uid()
    and app.current_role() = 'clinic'
  )
  or app.is_admin()
);

-- Clinic role can insert only own clinic record.
drop policy if exists clinics_insert_owner on app.clinics;
create policy clinics_insert_owner
on app.clinics
for insert
to authenticated
with check (
  owner_user_id = auth.uid()
  and app.current_role() = 'clinic'
);

-- Owner/admin update scope.
drop policy if exists clinics_update_owner_or_admin on app.clinics;
create policy clinics_update_owner_or_admin
on app.clinics
for update
to authenticated
using (
  owner_user_id = auth.uid()
  or app.is_admin()
)
with check (
  owner_user_id = auth.uid()
  or app.is_admin()
);

-- --------------------------------------------------------------------------
-- doctors
-- --------------------------------------------------------------------------

-- Patients can read doctors only from verified+active providers.
-- Hospital/clinic owners can read doctors in their scope.
-- Admin can read all.
drop policy if exists doctors_select_scoped on app.doctors;
create policy doctors_select_scoped
on app.doctors
for select
to authenticated
using (
  (
    app.current_role() = 'patient'
    and active = true
    and (
      (
        hospital_id is not null
        and exists (
          select 1
          from app.hospitals h
          where h.id = doctors.hospital_id
            and h.verified = true
            and h.active = true
        )
      )
      or
      (
        clinic_id is not null
        and exists (
          select 1
          from app.clinics c
          where c.id = doctors.clinic_id
            and c.verified = true
            and c.active = true
        )
      )
    )
  )
  or (
    app.current_role() = 'hospital'
    and exists (
      select 1
      from app.hospitals h
      where h.id = doctors.hospital_id
        and h.owner_user_id = auth.uid()
    )
  )
  or (
    app.current_role() = 'clinic'
    and exists (
      select 1
      from app.clinics c
      where c.id = doctors.clinic_id
        and c.owner_user_id = auth.uid()
    )
  )
  or app.is_admin()
);

-- Hospital/clinic owner can insert doctors only in their owned scope.
drop policy if exists doctors_insert_scoped on app.doctors;
create policy doctors_insert_scoped
on app.doctors
for insert
to authenticated
with check (
  app.is_admin()
  or (
    app.current_role() = 'hospital'
    and hospital_id is not null
    and clinic_id is null
    and exists (
      select 1
      from app.hospitals h
      where h.id = doctors.hospital_id
        and h.owner_user_id = auth.uid()
    )
  )
  or (
    app.current_role() = 'clinic'
    and clinic_id is not null
    and hospital_id is null
    and exists (
      select 1
      from app.clinics c
      where c.id = doctors.clinic_id
        and c.owner_user_id = auth.uid()
    )
  )
);

-- Owner/admin update scope.
drop policy if exists doctors_update_scoped on app.doctors;
create policy doctors_update_scoped
on app.doctors
for update
to authenticated
using (
  app.is_admin()
  or (
    app.current_role() = 'hospital'
    and exists (
      select 1
      from app.hospitals h
      where h.id = doctors.hospital_id
        and h.owner_user_id = auth.uid()
    )
  )
  or (
    app.current_role() = 'clinic'
    and exists (
      select 1
      from app.clinics c
      where c.id = doctors.clinic_id
        and c.owner_user_id = auth.uid()
    )
  )
)
with check (
  app.is_admin()
  or (
    app.current_role() = 'hospital'
    and exists (
      select 1
      from app.hospitals h
      where h.id = doctors.hospital_id
        and h.owner_user_id = auth.uid()
    )
  )
  or (
    app.current_role() = 'clinic'
    and exists (
      select 1
      from app.clinics c
      where c.id = doctors.clinic_id
        and c.owner_user_id = auth.uid()
    )
  )
);

-- --------------------------------------------------------------------------
-- appointments
-- --------------------------------------------------------------------------

-- Patient reads own appointments.
-- Hospital/clinic owner reads appointments in owned scope.
-- Admin reads all.
drop policy if exists appointments_select_scoped on app.appointments;
create policy appointments_select_scoped
on app.appointments
for select
to authenticated
using (
  (
    app.current_role() = 'patient'
    and patient_user_id = auth.uid()
  )
  or (
    app.current_role() = 'hospital'
    and hospital_id is not null
    and exists (
      select 1
      from app.hospitals h
      where h.id = appointments.hospital_id
        and h.owner_user_id = auth.uid()
    )
  )
  or (
    app.current_role() = 'clinic'
    and clinic_id is not null
    and exists (
      select 1
      from app.clinics c
      where c.id = appointments.clinic_id
        and c.owner_user_id = auth.uid()
    )
  )
  or app.is_admin()
);

-- Patient creates own appointment only.
drop policy if exists appointments_insert_patient_self on app.appointments;
create policy appointments_insert_patient_self
on app.appointments
for insert
to authenticated
with check (
  app.current_role() = 'patient'
  and patient_user_id = auth.uid()
);

-- Patient can update own appointment.
-- Hospital/clinic owners can update in owned scope.
-- Admin can update all.
drop policy if exists appointments_update_scoped on app.appointments;
create policy appointments_update_scoped
on app.appointments
for update
to authenticated
using (
  (
    app.current_role() = 'patient'
    and patient_user_id = auth.uid()
  )
  or (
    app.current_role() = 'hospital'
    and hospital_id is not null
    and exists (
      select 1
      from app.hospitals h
      where h.id = appointments.hospital_id
        and h.owner_user_id = auth.uid()
    )
  )
  or (
    app.current_role() = 'clinic'
    and clinic_id is not null
    and exists (
      select 1
      from app.clinics c
      where c.id = appointments.clinic_id
        and c.owner_user_id = auth.uid()
    )
  )
  or app.is_admin()
)
with check (
  (
    app.current_role() = 'patient'
    and patient_user_id = auth.uid()
  )
  or (
    app.current_role() = 'hospital'
    and hospital_id is not null
    and exists (
      select 1
      from app.hospitals h
      where h.id = appointments.hospital_id
        and h.owner_user_id = auth.uid()
    )
  )
  or (
    app.current_role() = 'clinic'
    and clinic_id is not null
    and exists (
      select 1
      from app.clinics c
      where c.id = appointments.clinic_id
        and c.owner_user_id = auth.uid()
    )
  )
  or app.is_admin()
);

-- --------------------------------------------------------------------------
-- notifications
-- --------------------------------------------------------------------------

-- Recipient can read own notifications; admin can read all.
drop policy if exists notifications_select_recipient_or_admin on app.notifications;
create policy notifications_select_recipient_or_admin
on app.notifications
for select
to authenticated
using (
  recipient_user_id = auth.uid()
  or app.is_admin()
);

-- Hospital/clinic/admin can insert notifications only as themselves.
drop policy if exists notifications_insert_sender_self on app.notifications;
create policy notifications_insert_sender_self
on app.notifications
for insert
to authenticated
with check (
  sender_user_id = auth.uid()
  and app.current_role() in ('hospital', 'clinic', 'admin')
);

-- Recipient can mark as read; admin can update all.
drop policy if exists notifications_update_recipient_or_admin on app.notifications;
create policy notifications_update_recipient_or_admin
on app.notifications
for update
to authenticated
using (
  recipient_user_id = auth.uid()
  or app.is_admin()
)
with check (
  recipient_user_id = auth.uid()
  or app.is_admin()
);
