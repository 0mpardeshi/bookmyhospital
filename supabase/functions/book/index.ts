import { corsPreflight, getAuthContext, json } from "../_shared/core.ts";
import { bookAppointment } from "../_shared/appointments.ts";

Deno.serve(async (req) => {
  const preflight = corsPreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" });
  }

  try {
    const auth = await getAuthContext(req);
    const body = await req.json();

    const appointment = await bookAppointment({
      actorUserId: auth.userId,
      actorRole: auth.role as any,
      patientUserId: String(body.patientUserId),
      doctorId: String(body.doctorId),
      hospitalId: body.hospitalId ?? null,
      clinicId: body.clinicId ?? null,
      reason: String(body.reason),
      scheduledStartAt: String(body.scheduledStartAt),
      scheduledEndAt: String(body.scheduledEndAt),
    });

    return json(200, { ok: true, appointment });
  } catch (error) {
    return json(400, { ok: false, error: (error as Error).message });
  }
});
