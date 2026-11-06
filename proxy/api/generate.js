// SketchLift proxy: keeps the Gemini API key on the server, never in the APK.
// POST /api/generate  { model?: string, body: <Gemini generateContent request> }
// Header X-Device-Id: per-install random id (used for the free daily limit).
export const config = { runtime: 'edge' };

const DEFAULT_MODEL = process.env.GEMINI_MODEL || 'gemini-3.8-flash';
// Only cheap/fast "flash" models are allowed through the free proxy.
const FALLBACKS = ['gemini-flash-latest', 'gemini-3.7-flash', 'gemini-3.5-flash'];
const MODEL_RE = /^gemini-[a-z0-9.-]*flash[a-z0-9.-]*$/;
const DAILY_LIMIT = Number(process.env.DAILY_LIMIT || 5);
const MAX_BYTES = 6 * 1024 * 1024; // 6 MB request cap
// Best-effort in-memory counter (per edge instance). Real enforcement also happens in-app.
const counts = new Map();

function cors(extra = {}) {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, X-Device-Id, X-App',
    'Access-Control-Allow-Methods': 'POST, OPTIONS, GET',
    ...extra,
  };
}
const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: cors({ 'Content-Type': 'application/json' }) });

export default async function handler(req) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors() });
  if (req.method === 'GET') {
    // GET ?models=1 lists flash models available to this key (handy when Google renames models).
    if (new URL(req.url).searchParams.get('models') && process.env.GEMINI_API_KEY) {
      const r = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200',
        { headers: { 'x-goog-api-key': process.env.GEMINI_API_KEY } });
      const d = await r.json();
      return json({ models: (d.models || []).map(m => m.name.replace('models/', '')).filter(n => MODEL_RE.test(n)) });
    }
    return json({ ok: true, service: 'sketchlift-proxy', limit: DAILY_LIMIT, default_model: DEFAULT_MODEL });
  }
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (req.headers.get('x-app') !== 'sketchlift') return json({ error: 'forbidden' }, 403);

  const key = process.env.GEMINI_API_KEY;
  if (!key) return json({ error: 'server_not_configured' }, 500);

  const device = (req.headers.get('x-device-id') || '').slice(0, 64);
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(device)) return json({ error: 'missing_device_id' }, 400);

  const len = Number(req.headers.get('content-length') || 0);
  if (len > MAX_BYTES) return json({ error: 'too_large' }, 413);

  const day = new Date().toISOString().slice(0, 10);
  const k = `${day}:${device}`;
  const used = counts.get(k) || 0;
  if (used >= DAILY_LIMIT) return json({ error: 'daily_limit', limit: DAILY_LIMIT }, 429);

  let payload;
  try { payload = await req.json(); } catch { return json({ error: 'bad_json' }, 400); }
  const model = MODEL_RE.test(payload.model || '') ? payload.model : DEFAULT_MODEL;
  if (!payload.body || !Array.isArray(payload.body.contents)) return json({ error: 'bad_request' }, 400);

  // Try the requested model, then fall back when Google says busy (503) or retired (404).
  const chain = [model, ...FALLBACKS.filter(m => m !== model)];
  let r;
  for (const m of chain) {
    r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent`,
      { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
        body: JSON.stringify(payload.body) }
    );
    if (![404, 429, 500, 503].includes(r.status)) break;
  }
  if (r.ok) counts.set(k, used + 1);
  const text = await r.text();
  return new Response(text, {
    status: r.status,
    headers: cors({ 'Content-Type': 'application/json', 'X-Remaining': String(Math.max(0, DAILY_LIMIT - used - 1)) }),
  });
}
