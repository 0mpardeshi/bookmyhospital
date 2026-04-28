import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

// Critical: service role key is only used in Edge runtime (server-side), never in client app.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing required env: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY");
}

// Admin client used by Edge Functions only.
export const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

export function json(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "POST,OPTIONS",
      "access-control-allow-headers": "authorization,content-type",
    },
  });
}

export function corsPreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return json(204, {});
  }
  return null;
}

function extractBearer(req: Request): string | null {
  const raw = req.headers.get("authorization") ?? "";
  const match = raw.match(/^Bearer\s+(.+)$/i);
  return match?.[1] ?? null;
}

// Validate caller token and return identity + role claim for authorization checks.
export async function getAuthContext(req: Request): Promise<{ userId: string; role: string }> {
  const token = extractBearer(req);
  if (!token) {
    throw new Error("Missing bearer token");
  }

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) {
    throw new Error("Invalid or expired token");
  }

  const role = String(data.user.app_metadata?.role ?? "");
  if (!role) {
    throw new Error("Missing role claim in app_metadata.role");
  }

  return {
    userId: data.user.id,
    role,
  };
}
