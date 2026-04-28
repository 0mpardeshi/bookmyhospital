import { corsPreflight, getAuthContext, json } from "../_shared/core.ts";
import { updateAppointment } from "../_shared/appointments.ts";

Deno.serve(async (req) => {
  const preflight = corsPreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" });
  }

  try {
    const auth = await getAuthContext(req);
    const body = await req.json();

    const appointment = await updateAppointment({
      actorUserId: auth.userId,
      actorRole: auth.role as any,
      appointmentId: String(body.appointmentId),
      scheduledStartAt: body.scheduledStartAt,
      scheduledEndAt: body.scheduledEndAt,
      providerNote: body.providerNote,
      status: body.status,
    });

    return json(200, { ok: true, appointment });
  } catch (error) {
    return json(400, { ok: false, error: (error as Error).message });
  }
});
