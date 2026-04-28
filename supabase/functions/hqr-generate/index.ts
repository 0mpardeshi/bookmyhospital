import { admin, corsPreflight, getAuthContext, json } from "../_shared/core.ts";
import {
  nowEpochSeconds,
  randomNonce,
  signHqrToken,
} from "../_shared/hqr.ts";

type Role = "patient" | "hospital" | "clinic" | "admin";

const WINDOW_SECONDS = 900;

function mustEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value || !value.trim()) throw new Error(`Missing env: ${name}`);
  return value.trim();
}

Deno.serve(async (req: Request) => {
  try {
    const pre = corsPreflight(req);
    if (pre) return pre;
    if (req.method !== "POST") return json(405, { error: "Method not allowed" });

    const { userId, role } = await getAuthContext(req);
    const actorRole = role as Role;
    if (!["hospital", "clinic", "admin"].includes(actorRole)) {
      return json(403, { error: "Only provider/admin can generate HQR" });
    }

    const body = await req.json().catch(() => null) as { bookingId?: string } | null;
    const bookingId = String(body?.bookingId ?? "").trim();
    if (!bookingId) return json(400, { error: "bookingId is required" });

    const { data: appointment, error: appointmentError } = await admin
      .from("appointments")
      .select("id,status,hospital_id,clinic_id")
      .eq("id", bookingId)
      .single();

    if (appointmentError || !appointment) {
      return json(404, { error: "Appointment not found" });
    }

    if (!["confirmed"].includes(String(appointment.status))) {
      return json(409, { error: "HQR can be generated only for accepted/confirmed appointments" });
    }

    const facilityId = String(appointment.hospital_id ?? appointment.clinic_id ?? "");
    if (!facilityId) return json(500, { error: "Appointment facility missing" });

    if (actorRole === "hospital") {
      const { data: hospital } = await admin
        .from("hospitals")
        .select("owner_user_id")
        .eq("id", facilityId)
        .single();
      if (!hospital || hospital.owner_user_id !== userId) {
        return json(403, { error: "Hospital does not own this appointment" });
      }
    }

    if (actorRole === "clinic") {
      const { data: clinic } = await admin
        .from("clinics")
        .select("owner_user_id")
        .eq("id", facilityId)
        .single();
      if (!clinic || clinic.owner_user_id !== userId) {
        return json(403, { error: "Clinic does not own this appointment" });
      }
    }

    const ts = nowEpochSeconds();
    const nonce = randomNonce();
    const secret = mustEnv("HQR_SIGNING_SECRET");
    const verifyBaseUrl = mustEnv("HQR_VERIFY_BASE_URL");
    const token = await signHqrToken(secret, {
      bookingId,
      facilityId,
      ts,
      nonce,
    });

    const tokenHash = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(token),
    );
    const tokenHashHex = Array.from(new Uint8Array(tokenHash))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    const expiresAt = new Date((ts + WINDOW_SECONDS) * 1000).toISOString();
    await admin.from("hqr_tokens").insert({
      appointment_id: bookingId,
      facility_id: facilityId,
      issued_for_user_id: userId,
      token_nonce: nonce,
      token_hash: tokenHashHex,
      issued_at: new Date(ts * 1000).toISOString(),
      expires_at: expiresAt,
    });

    const verifyUrl = `${verifyBaseUrl}?token=${encodeURIComponent(token)}`;
    return json(200, {
      ok: true,
      bookingId,
      expiresInSeconds: WINDOW_SECONDS,
      expiresAt,
      token,
      verifyUrl,
    });
  } catch (error) {
    return json(500, { error: (error as Error).message });
  }
});
