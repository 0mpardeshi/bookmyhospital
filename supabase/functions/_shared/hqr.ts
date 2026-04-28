import { admin } from "./core.ts";

const encoder = new TextEncoder();

export type HqrPayload = {
  bookingId: string;
  facilityId: string;
  ts: number;
  nonce: string;
};

export function base64UrlEncode(bytes: Uint8Array): string {
  const b64 = btoa(String.fromCharCode(...bytes));
  return b64.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

export function base64UrlDecode(input: string): Uint8Array {
  const normalized = input.replaceAll("-", "+").replaceAll("_", "/");
  const pad = normalized.length % 4 === 0 ? "" : "=".repeat(4 - (normalized.length % 4));
  const raw = atob(`${normalized}${pad}`);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

function canonical(payload: HqrPayload): string {
  return `${payload.bookingId}.${payload.ts}.${payload.facilityId}.${payload.nonce}`;
}

export async function hmacSha256(secret: string, message: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return new Uint8Array(sig);
}

export async function signHqrToken(secret: string, payload: HqrPayload): Promise<string> {
  const payloadB64 = base64UrlEncode(encoder.encode(JSON.stringify(payload)));
  const sig = await hmacSha256(secret, canonical(payload));
  const sigB64 = base64UrlEncode(sig);
  return `${payloadB64}.${sigB64}`;
}

export async function verifyHqrToken(
  secret: string,
  token: string,
): Promise<{ payload: HqrPayload; tokenHash: string }> {
  const parts = token.split(".");
  if (parts.length !== 2) {
    throw new Error("Malformed token");
  }

  const payloadRaw = new TextDecoder().decode(base64UrlDecode(parts[0]));
  const payload = JSON.parse(payloadRaw) as Partial<HqrPayload>;
  if (!payload.bookingId || !payload.facilityId || !payload.ts || !payload.nonce) {
    throw new Error("Token payload missing fields");
  }

  const hqrPayload: HqrPayload = {
    bookingId: String(payload.bookingId),
    facilityId: String(payload.facilityId),
    ts: Number(payload.ts),
    nonce: String(payload.nonce),
  };

  const expected = await hmacSha256(secret, canonical(hqrPayload));
  const expectedB64 = base64UrlEncode(expected);
  if (expectedB64 !== parts[1]) {
    throw new Error("Token signature mismatch");
  }

  const hash = await crypto.subtle.digest("SHA-256", encoder.encode(token));
  const tokenHash = base64UrlEncode(new Uint8Array(hash));
  return { payload: hqrPayload, tokenHash };
}

export function nowEpochSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export function randomNonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return base64UrlEncode(bytes);
}

export async function logVerificationAttempt(input: {
  actorUserId: string;
  appointmentId?: string | null;
  facilityId?: string | null;
  tokenHash?: string | null;
  success: boolean;
  reason: string;
  requesterIp?: string | null;
}) {
  await admin.from("hqr_verification_attempts").insert({
    actor_user_id: input.actorUserId,
    appointment_id: input.appointmentId ?? null,
    facility_id: input.facilityId ?? null,
    token_hash: input.tokenHash ?? null,
    success: input.success,
    reason: input.reason,
    requester_ip: input.requesterIp ?? null,
  });

  await admin.from("notifications").insert({
    recipient_user_id: input.actorUserId,
    sender_user_id: null,
    appointment_id: input.appointmentId ?? null,
    type: "critical",
    title: input.success ? "HQR Verification Success" : "HQR Verification Failed",
    body: input.reason,
    is_read: false,
  });
}

export async function assertRateLimit(actorUserId: string) {
  const since = new Date(Date.now() - 60_000).toISOString();
  const { count, error } = await admin
    .from("hqr_verification_attempts")
    .select("id", { count: "exact", head: true })
    .eq("actor_user_id", actorUserId)
    .gte("created_at", since);

  if (error) throw new Error(error.message);
  if ((count ?? 0) >= 5) {
    throw new Error("Rate limit exceeded: max 5 verification attempts/min");
  }
}
