import { admin } from "./core.ts";

export type Role = "patient" | "hospital" | "clinic" | "admin";

const ALLOWED_STATUSES = new Set([
  "pending",
  "confirmed",
  "delayed",
  "completed",
  "cancelled",
  "declined",
]);

async function assertProviderOwnsAppointment(
  appointmentId: string,
  actorUserId: string,
  actorRole: Role,
): Promise<void> {
  if (actorRole === "admin") {
    return;
  }

  if (actorRole === "hospital") {
    const { data, error } = await admin
      .from("appointments")
      .select("id,hospitals!inner(owner_user_id)")
      .eq("id", appointmentId)
      .single();

    if (error || !data) {
      throw new Error("Appointment not found");
    }

    const owner = (data as unknown as { hospitals: { owner_user_id: string } }).hospitals.owner_user_id;
    if (owner !== actorUserId) {
      throw new Error("Hospital is not owner of this appointment");
    }
    return;
  }

  if (actorRole === "clinic") {
    const { data, error } = await admin
      .from("appointments")
      .select("id,clinics!inner(owner_user_id)")
      .eq("id", appointmentId)
      .single();

    if (error || !data) {
      throw new Error("Appointment not found");
    }

    const owner = (data as unknown as { clinics: { owner_user_id: string } }).clinics.owner_user_id;
    if (owner !== actorUserId) {
      throw new Error("Clinic is not owner of this appointment");
    }
    return;
  }

  throw new Error("Provider-only operation");
}

export async function bookAppointment(input: {
  actorUserId: string;
  actorRole: Role;
  patientUserId: string;
  doctorId: string;
  hospitalId?: string | null;
  clinicId?: string | null;
  reason: string;
  scheduledStartAt: string;
  scheduledEndAt: string;
}) {
  if (!(input.actorRole === "patient" || input.actorRole === "admin")) {
    throw new Error("Only patient/admin can book");
  }

  if (input.actorRole === "patient" && input.actorUserId !== input.patientUserId) {
    throw new Error("Patient can book only for self");
  }

  const { data, error } = await admin
    .from("appointments")
    .insert({
      patient_user_id: input.patientUserId,
      doctor_id: input.doctorId,
      hospital_id: input.hospitalId ?? null,
      clinic_id: input.clinicId ?? null,
      status: "pending",
      reason: input.reason,
      scheduled_start_at: input.scheduledStartAt,
      scheduled_end_at: input.scheduledEndAt,
    })
    .select("id,status,queue_position,scheduled_start_at,scheduled_end_at")
    .single();

  if (error) {
    throw new Error(error.message);
  }

  return data;
}

export async function acceptAppointment(input: {
  actorUserId: string;
  actorRole: Role;
  appointmentId: string;
}) {
  await assertProviderOwnsAppointment(input.appointmentId, input.actorUserId, input.actorRole);

  const { data, error } = await admin
    .from("appointments")
    .update({
      status: "confirmed",
      provider_note: "Accepted by provider",
    })
    .eq("id", input.appointmentId)
    .select("id,status,queue_position")
    .single();

  if (error) {
    throw new Error(error.message);
  }

  return data;
}

export async function declineAppointment(input: {
  actorUserId: string;
  actorRole: Role;
  appointmentId: string;
  reason: string;
}) {
  await assertProviderOwnsAppointment(input.appointmentId, input.actorUserId, input.actorRole);

  const { data, error } = await admin
    .from("appointments")
    .update({
      status: "declined",
      provider_note: input.reason,
      cancelled_at: new Date().toISOString(),
      cancellation_reason: input.reason,
      cancelled_by_user_id: input.actorUserId,
    })
    .eq("id", input.appointmentId)
    .select("id,status")
    .single();

  if (error) {
    throw new Error(error.message);
  }

  return data;
}

export async function updateAppointment(input: {
  actorUserId: string;
  actorRole: Role;
  appointmentId: string;
  scheduledStartAt?: string;
  scheduledEndAt?: string;
  providerNote?: string;
  status?: string;
}) {
  const { data: current, error: currentError } = await admin
    .from("appointments")
    .select("id,patient_user_id,status")
    .eq("id", input.appointmentId)
    .single();

  if (currentError || !current) {
    throw new Error("Appointment not found");
  }

  if (input.actorRole === "patient") {
    if (current.patient_user_id !== input.actorUserId) {
      throw new Error("Not your appointment");
    }
    if (!["pending", "confirmed", "delayed"].includes(current.status)) {
      throw new Error("Appointment not editable in this state");
    }
  } else if (input.actorRole === "hospital" || input.actorRole === "clinic") {
    await assertProviderOwnsAppointment(input.appointmentId, input.actorUserId, input.actorRole);
  } else if (input.actorRole !== "admin") {
    throw new Error("Unauthorized role");
  }

  const patch: Record<string, unknown> = {};

  if (input.scheduledStartAt) {
    patch.scheduled_start_at = input.scheduledStartAt;
  }
  if (input.scheduledEndAt) {
    patch.scheduled_end_at = input.scheduledEndAt;
  }
  if (typeof input.providerNote === "string") {
    patch.provider_note = input.providerNote;
  }
  if (input.status) {
    if (!ALLOWED_STATUSES.has(input.status)) {
      throw new Error("Invalid status");
    }
    patch.status = input.status;
  }

  if (Object.keys(patch).length === 0) {
    throw new Error("No update fields provided");
  }

  const { data, error } = await admin
    .from("appointments")
    .update(patch)
    .eq("id", input.appointmentId)
    .select("id,status,queue_position,scheduled_start_at,scheduled_end_at,provider_note")
    .single();

  if (error) {
    throw new Error(error.message);
  }

  return data;
}

export async function completeAppointment(input: {
  actorUserId: string;
  actorRole: Role;
  appointmentId: string;
}) {
  await assertProviderOwnsAppointment(input.appointmentId, input.actorUserId, input.actorRole);

  const { data, error } = await admin
    .from("appointments")
    .update({
      status: "completed",
      provider_note: "Completed",
    })
    .eq("id", input.appointmentId)
    .select("id,status")
    .single();

  if (error) {
    throw new Error(error.message);
  }

  return data;
}

export async function cancelAppointment(input: {
  actorUserId: string;
  actorRole: Role;
  appointmentId: string;
  reason: string;
}) {
  const { data: row, error: rowError } = await admin
    .from("appointments")
    .select("id,patient_user_id")
    .eq("id", input.appointmentId)
    .single();

  if (rowError || !row) {
    throw new Error("Appointment not found");
  }

  if (input.actorRole === "patient") {
    if (row.patient_user_id !== input.actorUserId) {
      throw new Error("Not your appointment");
    }
  } else if (input.actorRole === "hospital" || input.actorRole === "clinic") {
    await assertProviderOwnsAppointment(input.appointmentId, input.actorUserId, input.actorRole);
  } else if (input.actorRole !== "admin") {
    throw new Error("Unauthorized role");
  }

  const { data, error } = await admin
    .from("appointments")
    .update({
      status: "cancelled",
      cancelled_by_user_id: input.actorUserId,
      cancelled_at: new Date().toISOString(),
      cancellation_reason: input.reason,
    })
    .eq("id", input.appointmentId)
    .select("id,status,cancelled_at,cancellation_reason")
    .single();

  if (error) {
    throw new Error(error.message);
  }

  return data;
}
