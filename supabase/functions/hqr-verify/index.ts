import { admin, corsPreflight, getAuthContext, json } from "../_shared/core.ts";
import {
  assertRateLimit,
  logVerificationAttempt,
  nowEpochSeconds,
  verifyHqrToken,
} from "../_shared/hqr.ts";

const WINDOW_SECONDS = 900;

function mustEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value || !value.trim()) throw new Error(`Missing env: ${name}`);
  return value.trim();
}

function requesterIp(req: Request): string | null {
  return req.headers.get("x-forwarded-for")
    ?? req.headers.get("cf-connecting-ip")
    ?? null;
}

Deno.serve(async (req: Request) => {
  const ip = requesterIp(req);
  let actorUserId = "";
  try {
    const pre = corsPreflight(req);
    if (pre) return pre;
    if (!(req.method === "POST" || req.method === "GET")) {
      return json(405, { error: "Method not allowed" });
    }

    const auth = await getAuthContext(req);
    actorUserId = auth.userId;
    await assertRateLimit(actorUserId);

    const token = req.method === "GET"
      ? String(new URL(req.url).searchParams.get("token") ?? "").trim()
      : String(((await req.json().catch(() => ({}))) as { token?: string }).token ?? "").trim();
    if (!token) {
      await logVerificationAttempt({
        actorUserId,
        success: false,
        reason: "Missing token",
        requesterIp: ip,
      });
      return json(400, { ok: false, verified: false, reason: "Missing token" });
    }

    const secret = mustEnv("HQR_SIGNING_SECRET");
    const { payload, tokenHash } = await verifyHqrToken(secret, token);

    const age = Math.abs(nowEpochSeconds() - payload.ts);
    if (age > WINDOW_SECONDS) {
      await logVerificationAttempt({
        actorUserId,
        appointmentId: payload.bookingId,
        facilityId: payload.facilityId,
        tokenHash,
        success: false,
        reason: "Token expired",
        requesterIp: ip,
      });
      return json(401, { ok: false, verified: false, reason: "Token expired" });
    }

    const tokenHashHex = Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))),
    ).map((b) => b.toString(16).padStart(2, "0")).join("");

    const { data: tokenRow, error: tokenRowError } = await admin
      .from("hqr_tokens")
      .select("id,appointment_id,facility_id,expires_at,used_at")
      .eq("token_hash", tokenHashHex)
      .single();

    if (tokenRowError || !tokenRow) {
      await logVerificationAttempt({
        actorUserId,
        appointmentId: payload.bookingId,
        facilityId: payload.facilityId,
        tokenHash,
        success: false,
        reason: "Token not issued by server",
        requesterIp: ip,
      });
      return json(401, { ok: false, verified: false, reason: "Token not issued by server" });
    }

    if (tokenRow.used_at) {
      await logVerificationAttempt({
        actorUserId,
        appointmentId: payload.bookingId,
        facilityId: payload.facilityId,
        tokenHash,
        success: false,
        reason: "Token already used",
        requesterIp: ip,
      });
      return json(409, { ok: false, verified: false, reason: "Token already used" });
    }

    if (new Date(tokenRow.expires_at).getTime() < Date.now()) {
      await logVerificationAttempt({
        actorUserId,
        appointmentId: payload.bookingId,
        facilityId: payload.facilityId,
        tokenHash,
        success: false,
        reason: "Server token window expired",
        requesterIp: ip,
      });
      return json(401, { ok: false, verified: false, reason: "Token expired" });
    }

    const { data: appointment, error: appointmentError } = await admin
      .from("appointments")
      .select("id,status,patient_user_id,hospital_id,clinic_id")
      .eq("id", payload.bookingId)
      .single();

    if (appointmentError || !appointment) {
      await logVerificationAttempt({
        actorUserId,
        appointmentId: payload.bookingId,
        facilityId: payload.facilityId,
        tokenHash,
        success: false,
        reason: "Appointment not found",
        requesterIp: ip,
      });
      return json(404, { ok: false, verified: false, reason: "Appointment not found" });
    }

    if (String(appointment.status) !== "confirmed") {
      await logVerificationAttempt({
        actorUserId,
        appointmentId: payload.bookingId,
        facilityId: payload.facilityId,
        tokenHash,
        success: false,
        reason: "Appointment not accepted",
        requesterIp: ip,
      });
      return json(409, { ok: false, verified: false, reason: "Appointment not accepted" });
    }

    if (String(appointment.patient_user_id) !== actorUserId) {
      await logVerificationAttempt({
        actorUserId,
        appointmentId: payload.bookingId,
        facilityId: payload.facilityId,
        tokenHash,
        success: false,
        reason: "Patient does not own appointment",
        requesterIp: ip,
      });
      return json(403, { ok: false, verified: false, reason: "Patient does not own appointment" });
    }

    const appointmentFacilityId = String(appointment.hospital_id ?? appointment.clinic_id ?? "");
    if (appointmentFacilityId !== payload.facilityId) {
      await logVerificationAttempt({
        actorUserId,
        appointmentId: payload.bookingId,
        facilityId: payload.facilityId,
        tokenHash,
        success: false,
        reason: "Facility mismatch",
        requesterIp: ip,
      });
      return json(409, { ok: false, verified: false, reason: "Facility mismatch" });
    }

    const nowIso = new Date().toISOString();
    await admin
      .from("hqr_tokens")
      .update({
        used_at: nowIso,
        used_by_user_id: actorUserId,
      })
      .eq("id", tokenRow.id);

    await admin
      .from("appointments")
      .update({
        checked_in_at: nowIso,
        checked_in_by_user_id: actorUserId,
      })
      .eq("id", appointment.id);

    await logVerificationAttempt({
      actorUserId,
      appointmentId: payload.bookingId,
      facilityId: payload.facilityId,
      tokenHash,
      success: true,
      reason: "Verified",
      requesterIp: ip,
    });

    return json(200, {
      ok: true,
      verified: true,
      bookingId: appointment.id,
      checkedInAt: nowIso,
      message: "Verified",
    });
  } catch (error) {
    if (actorUserId) {
      await logVerificationAttempt({
        actorUserId,
        success: false,
        reason: `Unhandled verification error: ${(error as Error).message}`,
        requesterIp: ip,
      }).catch(() => {});
    }
    return json(500, { ok: false, verified: false, error: (error as Error).message });
  }
});
