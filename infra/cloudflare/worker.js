/**
 * BookMyHospital Supabase Proxy Worker
 * -------------------------------------------------------------
 * Purpose:
 * - Hide direct Supabase project URL from client apps.
 * - Inject anon API key server-side to reduce key sprawl.
 * - Forward user JWT so Supabase RLS remains enforced.
 * - Restrict proxy to known Supabase API routes only.
 */

export default {
  async fetch(request, env) {
    // Critical: Support CORS preflight for Flutter web/mobile network stacks.
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(),
      });
    }

    const incoming = new URL(request.url);

    // Critical: allowlist only specific Supabase endpoints to avoid open proxy abuse.
    const allowlist = [
      '/rest/v1/',
      '/auth/v1/',
      '/storage/v1/',
      '/functions/v1/',
      '/realtime/v1/',
    ];

    const allowed = allowlist.some((prefix) => incoming.pathname.startsWith(prefix));
    if (!allowed) {
      return json(404, { error: 'Route not allowed by proxy policy' });
    }

    // Critical: Build hidden upstream URL using secret env var.
    const upstream = new URL(incoming.pathname + incoming.search, env.SUPABASE_URL);

    // Clone headers before mutation.
    const headers = new Headers(request.headers);

    // Critical: Inject apikey server-side; client never needs hardcoded endpoint key.
    headers.set('apikey', env.SUPABASE_ANON_KEY);

    // Default content negotiation for API consistency.
    if (!headers.has('accept')) {
      headers.set('accept', 'application/json');
    }

    // Remove origin host headers that may break upstream routing.
    headers.delete('host');
    headers.delete('x-forwarded-host');
    headers.delete('x-forwarded-proto');
    headers.delete('cf-connecting-ip');

    const method = request.method.toUpperCase();
    const hasBody = !['GET', 'HEAD'].includes(method);

    // Forward request to Supabase.
    const upstreamResponse = await fetch(upstream.toString(), {
      method,
      headers,
      body: hasBody ? request.body : undefined,
      redirect: 'manual',
    });

    // Preserve important response headers (e.g., content-range for pagination).
    const outHeaders = new Headers(upstreamResponse.headers);

    // Attach CORS + safety headers.
    for (const [k, v] of Object.entries(corsHeaders())) {
      outHeaders.set(k, v);
    }
    outHeaders.set('x-content-type-options', 'nosniff');
    outHeaders.set('referrer-policy', 'no-referrer');

    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      statusText: upstreamResponse.statusText,
      headers: outHeaders,
    });
  },
};

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'access-control-allow-headers': 'authorization,content-type,apikey,x-client-info,prefer',
    'access-control-expose-headers': 'content-range,range-unit',
    'vary': 'origin',
  };
}

function json(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...corsHeaders(),
    },
  });
}
