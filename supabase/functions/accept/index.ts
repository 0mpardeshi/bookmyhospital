import { corsPreflight, getAuthContext, json } from "../_shared/core.ts";
import { acceptAppointment } from "../_shared/appointments.ts";

Deno.serve(async (req) => {
  const preflight = corsPreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" });
  }

  try {
    const auth = await getAuthContext(req);
    const body = await req.json();

    const appointment = await acceptAppointment({
      actorUserId: auth.userId,
      actorRole: auth.role as any,
      appointmentId: String(body.appointmentId),
    });

    return json(200, { ok: true, appointment });
  } catch (error) {
    return json(400, { ok: false, error: (error as Error).message });
  }
});
