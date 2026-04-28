-- ============================================================================
-- BookMyHospital Phase 2
-- Scope:
-- 1) Queue logic (auto position + resequencing)
-- 2) Double-booking prevention at DB level
-- 3) Status transition guardrails
-- 4) Realtime publication for appointment live sync
-- 5) Notification history + appointment-triggered notifications
-- ============================================================================

-- Critical for exclusion constraints combining equality + overlap.
create extension if not exists btree_gist;

-- --------------------------------------------------------------------------
-- Ensure status enum supports phase-2 workflow states
-- --------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'appointment_status'
      and e.enumlabel = 'pending'
  ) then
    alter type app.appointment_status add value 'pending';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'appointment_status'
      and e.enumlabel = 'confirmed'
  ) then
    alter type app.appointment_status add value 'confirmed';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'appointment_status'
      and e.enumlabel = 'delayed'
  ) then
    alter type app.appointment_status add value 'delayed';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'appointment_status'
      and e.enumlabel = 'completed'
  ) then
    alter type app.appointment_status add value 'completed';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'appointment_status'
      and e.enumlabel = 'cancelled'
  ) then
    alter type app.appointment_status add value 'cancelled';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app'
      and t.typname = 'appointment_status'
      and e.enumlabel = 'declined'
  ) then
    alter type app.appointment_status add value 'declined';
  end if;
end $$;

-- --------------------------------------------------------------------------
-- Queue columns for appointment ordering
-- --------------------------------------------------------------------------

alter table app.appointments
  add column if not exists queue_position integer,
  add column if not exists provider_note text;

alter table app.appointments
  drop constraint if exists chk_queue_position_positive;

alter table app.appointments
  add constraint chk_queue_position_positive
  check (queue_position is null or queue_position >= 1);

-- --------------------------------------------------------------------------
-- Queue helper: define active statuses that occupy queue slots
-- --------------------------------------------------------------------------

create or replace function app.is_queue_active_status(s app.appointment_status)
returns boolean
language sql
immutable
as $$
  select s in ('pending', 'confirmed', 'delayed');
$$;

-- --------------------------------------------------------------------------
-- Queue resequencing per doctor + UTC date
-- --------------------------------------------------------------------------

create or replace function app.resequence_queue(p_doctor_id uuid, p_slot_date date)
returns void
language plpgsql
as $$
begin
  with ordered as (
    select
      id,
      row_number() over (
        order by scheduled_start_at asc, created_at asc, id asc
      ) as new_pos
    from app.appointments
    where doctor_id = p_doctor_id
      and (scheduled_start_at at time zone 'UTC')::date = p_slot_date
      and app.is_queue_active_status(status)
  )
  update app.appointments a
  set queue_position = o.new_pos
  from ordered o
  where a.id = o.id;
end;
$$;

-- --------------------------------------------------------------------------
-- Trigger: assign queue position on insert
-- --------------------------------------------------------------------------

create or replace function app.trg_assign_queue_on_insert()
returns trigger
language plpgsql
as $$
declare
  v_slot_date date;
begin
  if app.is_queue_active_status(new.status) then
    v_slot_date := (new.scheduled_start_at at time zone 'UTC')::date;

    -- Lock competing rows for deterministic queue assignment under concurrency.
    perform 1
    from app.appointments
    where doctor_id = new.doctor_id
      and (scheduled_start_at at time zone 'UTC')::date = v_slot_date
      and app.is_queue_active_status(status)
    for update;

    new.queue_position := coalesce((
      select max(queue_position)
      from app.appointments
      where doctor_id = new.doctor_id
        and (scheduled_start_at at time zone 'UTC')::date = v_slot_date
        and app.is_queue_active_status(status)
    ), 0) + 1;
  else
    new.queue_position := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_assign_queue_on_insert on app.appointments;
create trigger trg_assign_queue_on_insert
before insert on app.appointments
for each row
execute procedure app.trg_assign_queue_on_insert();

-- --------------------------------------------------------------------------
-- Trigger: resequence queue after updates that affect ordering/scope/status
-- --------------------------------------------------------------------------

create or replace function app.trg_resequence_queue_on_update()
returns trigger
language plpgsql
as $$
declare
  v_old_date date;
  v_new_date date;
begin
  v_old_date := (old.scheduled_start_at at time zone 'UTC')::date;
  v_new_date := (new.scheduled_start_at at time zone 'UTC')::date;

  -- Leaving active queue => clear queue position.
  if app.is_queue_active_status(old.status) and not app.is_queue_active_status(new.status) then
    new.queue_position := null;
  end if;

  -- Entering active queue => assign temporary tail position.
  if not app.is_queue_active_status(old.status)
     and app.is_queue_active_status(new.status)
     and new.queue_position is null then
    new.queue_position := coalesce((
      select max(queue_position)
      from app.appointments
      where doctor_id = new.doctor_id
        and (scheduled_start_at at time zone 'UTC')::date = v_new_date
        and app.is_queue_active_status(status)
        and id <> new.id
    ), 0) + 1;
  end if;

  -- Resequence old bucket if appointment moved away.
  if old.doctor_id <> new.doctor_id
     or v_old_date <> v_new_date
     or app.is_queue_active_status(old.status) <> app.is_queue_active_status(new.status) then
    perform app.resequence_queue(old.doctor_id, v_old_date);
  end if;

  -- Resequence new bucket to ensure contiguous positions.
  perform app.resequence_queue(new.doctor_id, v_new_date);

  return new;
end;
$$;

drop trigger if exists trg_resequence_queue_on_update on app.appointments;
create trigger trg_resequence_queue_on_update
before update on app.appointments
for each row
execute procedure app.trg_resequence_queue_on_update();

-- --------------------------------------------------------------------------
-- Hard DB-level anti-double-booking
-- Rule: same doctor cannot have overlapping active appointments.
-- --------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ex_appointments_no_overlap_active'
  ) then
    alter table app.appointments
      add constraint ex_appointments_no_overlap_active
      exclude using gist (
        doctor_id with =,
        tstzrange(scheduled_start_at, scheduled_end_at, '[)') with &&
      )
      where (status in ('pending', 'confirmed', 'delayed'));
  end if;
end $$;

-- Prevent duplicate active appointments for same patient/doctor/slot tuple.
create unique index if not exists uq_patient_doctor_slot_active
on app.appointments (patient_user_id, doctor_id, scheduled_start_at, scheduled_end_at)
where status in ('pending', 'confirmed', 'delayed');

-- --------------------------------------------------------------------------
-- Enforce legal status transitions in DB
-- --------------------------------------------------------------------------

create or replace function app.trg_enforce_appointment_transition()
returns trigger
language plpgsql
as $$
begin
  -- No status change is always valid.
  if old.status = new.status then
    return new;
  end if;

  -- Allowed transitions:
  -- pending   -> confirmed | declined | cancelled
  -- confirmed -> delayed   | completed | cancelled
  -- delayed   -> confirmed | completed | cancelled
  -- completed/declined/cancelled are terminal.
  if old.status = 'pending' and new.status in ('confirmed', 'declined', 'cancelled') then
    return new;
  elsif old.status = 'confirmed' and new.status in ('delayed', 'completed', 'cancelled') then
    return new;
  elsif old.status = 'delayed' and new.status in ('confirmed', 'completed', 'cancelled') then
    return new;
  else
    raise exception 'Invalid appointment status transition: % -> %', old.status, new.status;
  end if;
end;
$$;

drop trigger if exists trg_enforce_appointment_transition on app.appointments;
create trigger trg_enforce_appointment_transition
before update of status on app.appointments
for each row
execute procedure app.trg_enforce_appointment_transition();

-- --------------------------------------------------------------------------
-- Realtime publication for appointment live status sync
-- --------------------------------------------------------------------------

-- Critical: include full row images in UPDATE events.
alter table app.appointments replica identity full;

-- Add appointments table to Supabase realtime publication if absent.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'app'
      and tablename = 'appointments'
  ) then
    alter publication supabase_realtime add table app.appointments;
  end if;
end $$;

-- --------------------------------------------------------------------------
-- Notification history audit
-- --------------------------------------------------------------------------

create table if not exists app.notification_history (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null,
  event_type text not null check (event_type in ('insert', 'update', 'delete')),
  changed_by_user_id uuid,
  old_row jsonb,
  new_row jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_notification_history_notification_id
  on app.notification_history(notification_id);

create index if not exists idx_notification_history_created_at
  on app.notification_history(created_at desc);

create or replace function app.trg_log_notification_history()
returns trigger
language plpgsql
security definer
set search_path = app, public
as $$
begin
  if tg_op = 'INSERT' then
    insert into app.notification_history (
      notification_id, event_type, changed_by_user_id, new_row
    )
    values (
      new.id, 'insert', auth.uid(), to_jsonb(new)
    );
    return new;
  elsif tg_op = 'UPDATE' then
    insert into app.notification_history (
      notification_id, event_type, changed_by_user_id, old_row, new_row
    )
    values (
      new.id, 'update', auth.uid(), to_jsonb(old), to_jsonb(new)
    );
    return new;
  elsif tg_op = 'DELETE' then
    insert into app.notification_history (
      notification_id, event_type, changed_by_user_id, old_row
    )
    values (
      old.id, 'delete', auth.uid(), to_jsonb(old)
    );
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_log_notification_history on app.notifications;
create trigger trg_log_notification_history
after insert or update or delete on app.notifications
for each row
execute procedure app.trg_log_notification_history();

-- --------------------------------------------------------------------------
-- Auto-notify appointment status changes + booking creation
-- --------------------------------------------------------------------------

create or replace function app.trg_appointment_notifications()
returns trigger
language plpgsql
security definer
set search_path = app, public
as $$
declare
  v_provider_user_id uuid;
begin
  -- Resolve provider owner recipient.
  if coalesce(new.hospital_id, old.hospital_id) is not null then
    select h.owner_user_id
      into v_provider_user_id
    from app.hospitals h
    where h.id = coalesce(new.hospital_id, old.hospital_id);
  elsif coalesce(new.clinic_id, old.clinic_id) is not null then
    select c.owner_user_id
      into v_provider_user_id
    from app.clinics c
    where c.id = coalesce(new.clinic_id, old.clinic_id);
  end if;

  -- Insert-time notifications.
  if tg_op = 'INSERT' then
    insert into app.notifications (
      recipient_user_id, sender_user_id, appointment_id, type, title, body
    )
    values (
      new.patient_user_id,
      v_provider_user_id,
      new.id,
      'appointment',
      'Appointment booked',
      format('Booking created with status %s. Queue position: %s.', new.status::text, coalesce(new.queue_position::text, 'N/A'))
    );

    if v_provider_user_id is not null then
      insert into app.notifications (
        recipient_user_id, sender_user_id, appointment_id, type, title, body
      )
      values (
        v_provider_user_id,
        new.patient_user_id,
        new.id,
        'appointment',
        'New booking received',
        format('New appointment request %s for doctor %s.', new.id::text, new.doctor_id::text)
      );
    end if;

    return new;
  end if;

  -- Update-time notifications only when status changes.
  if tg_op = 'UPDATE' and old.status is distinct from new.status then
    insert into app.notifications (
      recipient_user_id, sender_user_id, appointment_id, type, title, body
    )
    values (
      new.patient_user_id,
      v_provider_user_id,
      new.id,
      'appointment',
      'Appointment status updated',
      format('Status changed: %s -> %s. Queue position: %s.', old.status::text, new.status::text, coalesce(new.queue_position::text, 'N/A'))
    );

    if v_provider_user_id is not null then
      insert into app.notifications (
        recipient_user_id, sender_user_id, appointment_id, type, title, body
      )
      values (
        v_provider_user_id,
        new.patient_user_id,
        new.id,
        'appointment',
        'Appointment transition recorded',
        format('Appointment %s transitioned: %s -> %s.', new.id::text, old.status::text, new.status::text)
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_appointment_notifications on app.appointments;
create trigger trg_appointment_notifications
after insert or update on app.appointments
for each row
execute procedure app.trg_appointment_notifications();
