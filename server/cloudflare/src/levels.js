import { RequestError, boundedBytes, readJson } from "./api_helpers.js";
import { requireUser } from "./accounts.js";

const MAX_LEVELS = 100;
const MAX_BODY = 20_480;
// Keep in sync with LevelCodec and LevelDocument in the Godot client.
const MAX_PAYLOAD = 6 + 1024 * 7 + 128 * 2 + 4 + 128 * 2 + 3 + 129 * 5;
const FULL = "The level library is full (100/100). No more levels can be uploaded right now.";

function cell(x, y) { return x < 100 && y < 100; }
function same(a, b) { return a[0] === b[0] && a[1] === b[1]; }
function distance(a, b) { return Math.hypot(a[0] - b[0], a[1] - b[1]); }
function pointOnCurve(a, b, c, t) {
  return a.map((value, axis) => value * (1 - t) ** 2 + 2 * c[axis] * (1 - t) * t + b[axis] * t * t);
}

// Validate portable data only. Never load scenes, scripts, or Godot resources.
function validatePayload(bytes) {
  const invalid = () => { throw new RequestError("Provide a valid, playable MG1- level code."); };
  if (bytes.length < 6 || bytes[0] !== 1) invalid();
  const segments = bytes[1] | bytes[2] << 8;
  const orbs = bytes[3];
  if (segments > 1024 || orbs > 128 || !cell(bytes[4], bytes[5])) invalid();
  let spawn = [bytes[4] + 0.5, bytes[5] + 0.5];
  const terrain = [];
  let offset = 6;
  let hasRace = false;
  for (let index = 0; index < segments; index++) {
    if (offset + 5 > bytes.length) invalid();
    const kind = bytes[offset++];
    const a = [bytes[offset++], bytes[offset++]];
    const b = [bytes[offset++], bytes[offset++]];
    if (kind > 1 || [...a, ...b].some(value => value > 100) || same(a, b)) invalid();
    let points = [a, b];
    if (kind === 1) {
      if (offset + 2 > bytes.length) invalid();
      const m = [bytes[offset++], bytes[offset++]];
      if (m.some(value => value > 100) || same(a, m) || same(b, m)) invalid();
      const c = m.map((value, axis) => value * 2 - (a[axis] + b[axis]) * 0.5);
      for (let axis = 0; axis < 2; axis++) {
        const denominator = a[axis] - 2 * c[axis] + b[axis];
        const t = (a[axis] - c[axis]) / denominator;
        if (Math.abs(denominator) > 0.00001 / 120 && t > 0 && t < 1) {
          const value = pointOnCurve(a, b, c, t)[axis];
          if (value < -0.001 / 120 || value > 100 + 0.001 / 120) invalid();
        }
      }
      // Same world-space sampling tolerance as LevelDocument.sample_segment.
      let steps = Math.max(2, Math.ceil(Math.sqrt(Math.hypot(...a.map((value, axis) => (value - 2 * c[axis] + b[axis]) * 120)) / 2)));
      steps += steps % 2;
      points = Array.from({ length: steps + 1 }, (_, step) => pointOnCurve(a, b, c, step / steps));
    }
    terrain.push(points);
  }
  if (offset + orbs * 2 > bytes.length) invalid();
  for (let index = 0; index < orbs; index++) if (!cell(bytes[offset++], bytes[offset++])) invalid();
  if (offset < bytes.length) {
    if (offset + 4 > bytes.length || bytes[offset++] !== 82) invalid();
    const count = bytes[offset++], laps = bytes[offset++], finish = bytes[offset++];
    hasRace = count > 0;
    if (count > 128 || laps < 1 || laps > 50 || offset + count * 2 > bytes.length ||
        (finish !== 1 && (count === 0 || finish !== count + 1 || laps !== 1))) invalid();
    const occupied = new Set([`${bytes[4]},${bytes[5]}`]);
    for (let index = 0; index < count; index++) {
      const x = bytes[offset++], y = bytes[offset++], key = `${x},${y}`;
      if (!cell(x, y) || occupied.has(key)) invalid();
      occupied.add(key);
    }
    if (offset < bytes.length) {
      if (offset + 3 > bytes.length || bytes[offset++] !== 76) invalid();
      const lines = bytes[offset++], spawnPercent = bytes[offset++];
      if (lines < 1 || lines > count + 1 || spawnPercent > 100 || offset + lines * 5 !== bytes.length) invalid();
      const seen = new Set();
      for (let index = 0; index < lines; index++) {
        const number = bytes[offset++];
        const a = [bytes[offset++], bytes[offset++]], b = [bytes[offset++], bytes[offset++]];
        if (number < 1 || number > count + 1 || seen.has(number) || !cell(...a) || !cell(...b) || same(a, b)) invalid();
        seen.add(number);
        if (number === 1) spawn = a.map((value, axis) => value + 0.5 + (b[axis] - value) * spawnPercent / 100);
      }
    }
  }
  // Line spawns may lie between cells. Check the actual player position only
  // after decoding the optional checkpoint geometry.
  for (const points of terrain) {
    for (let step = 1; step < points.length; step++) {
      const p = points[step - 1], q = points[step];
      const dx = q[0] - p[0], dy = q[1] - p[1];
      const t = Math.max(0, Math.min(1, ((spawn[0] - p[0]) * dx + (spawn[1] - p[1]) * dy) / (dx * dx + dy * dy) || 0));
      if (distance(spawn, [p[0] + t * dx, p[1] + t * dy]) <= (60 + 48 * 1.18 + 7) / 120) {
        throw new RequestError("The spawn overlaps terrain. Move it to a clear point before uploading.");
      }
    }
  }
  return { hasRace };
}

async function decodeCode(code, requireRace = false) {
  if (typeof code !== "string" || code.length > 16384 || !/^MG1-[A-Za-z0-9+/]+={0,2}$/.test(code) || (code.length - 4) % 4) {
    throw new RequestError("Provide a valid MG1- level code.");
  }
  let payload;
  try {
    const encoded = code.slice(4), binary = atob(encoded);
    if (btoa(binary) !== encoded) throw new Error("Noncanonical Base64");
    const compressed = Uint8Array.from(binary, character => character.charCodeAt(0));
    payload = await boundedBytes(new Blob([compressed]).stream().pipeThrough(new DecompressionStream("deflate")), MAX_PAYLOAD);
  } catch {
    throw new RequestError("The level code is damaged or exceeds the level limits.");
  }
  const { hasRace } = validatePayload(payload);
  if (requireRace && !hasRace) throw new RequestError("This level has no race to finish.");
  return payload;
}

function name(value, maximum) {
  if (typeof value !== "string") throw new RequestError("Provide a level name.");
  const clean = value.replace(/[\x00-\x1f\x7f]/g, " ").trim();
  if (clean.length > maximum) throw new RequestError(`Names must be at most ${maximum} characters.`);
  if (!clean) throw new RequestError("Give your level a name.");
  return clean;
}

const SUMMARY = `SELECT levels.id, title, author, author_id, created_at,
  (SELECT MIN(time_ms) FROM level_times WHERE level_id = levels.id) AS top_time_ms,
  (SELECT time_ms FROM level_times WHERE level_id = levels.id AND user_id = ?) AS personal_time_ms
  FROM levels`;

function timeQueries(db, id, userId) {
  return [
    db.prepare(`SELECT level_times.user_id, users.username, time_ms, achieved_at FROM level_times
      JOIN users ON users.id = level_times.user_id WHERE level_id = ?
      ORDER BY time_ms, achieved_at, level_times.user_id LIMIT 10`).bind(id),
    db.prepare("SELECT time_ms FROM level_times WHERE level_id = ? AND user_id = ?").bind(id, userId),
  ];
}

function timeResponse(results) {
  const leaderboard = results[0].results.map((entry, index) => ({ rank: index + 1, ...entry }));
  return { leaderboard, top_time_ms: leaderboard[0]?.time_ms ?? null,
    personal_time_ms: results[1].results[0]?.time_ms ?? null };
}

export async function levels(request, env) {
  const origin = request.headers.get("Origin");
  const allowed = (env.ALLOWED_ORIGINS || "").split(",").map(value => value.trim());
  const headers = { "Access-Control-Allow-Origin": origin || "*", Vary: "Origin", "Cache-Control": "no-store" };
  const json = (body, status = 200) => Response.json(body, { status, headers });
  if (origin && !allowed.includes(origin)) return json({ error: "Origin not allowed." }, 403);
  const path = new URL(request.url).pathname;
  const collection = path === "/levels";
  const match = /^\/levels\/([a-f0-9]{64})(\/times)?$/.exec(path);
  const times = Boolean(match?.[2]);
  if (!collection && !match) return json({ error: "Level not found." }, 404);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: {
    ...headers, "Access-Control-Allow-Methods": collection || times ? "GET, POST, OPTIONS" : "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization", "Access-Control-Max-Age": "86400",
  } });
  if (request.method !== "GET" && !((collection || times) && request.method === "POST")) return json({ error: "Method not allowed." }, 405);
  const key = request.headers.get("CF-Connecting-IP") || "local";
  const limiter = request.method === "POST" && collection ? env.UPLOAD_LIMITER : env.CONNECT_LIMITER;
  if (!(await limiter.limit({ key })).success) return json({ error: "Too many requests. Try again in a minute." }, 429);
  if (!env.LEVELS_DB) return json({ error: "The level library is not configured yet." }, 503);
  try {
    // Optional authentication personalizes reads without accepting a client user ID.
    const user = request.method === "POST" || request.headers.has("Authorization") ? await requireUser(request, env) : null;
    if (times) {
      const level = await env.LEVELS_DB.prepare("SELECT level_code FROM levels WHERE id = ?").bind(match[1]).first();
      if (!level) return json({ error: "This published level is no longer available." }, 404);
      if (request.method === "GET") return json(timeResponse(await env.LEVELS_DB.batch(timeQueries(env.LEVELS_DB, match[1], user?.id ?? null))));
      const body = await readJson(request, 1024);
      if (!Number.isSafeInteger(body.time_ms) || body.time_ms < 1 || body.time_ms > 86400000) {
        throw new RequestError("Provide a completion time in whole milliseconds between 1 and 86400000.");
      }
      await decodeCode(level.level_code, true);
      // The conditional upsert cannot replace a faster best, including concurrent retries.
      // The batch returns the ranking from the same transaction as the submitted best.
      const results = await env.LEVELS_DB.batch([
        env.LEVELS_DB.prepare(`INSERT INTO level_times (level_id, user_id, time_ms, achieved_at) VALUES (?, ?, ?, ?)
          ON CONFLICT(level_id, user_id) DO UPDATE SET time_ms = excluded.time_ms, achieved_at = excluded.achieved_at
          WHERE excluded.time_ms < level_times.time_ms RETURNING time_ms`)
          .bind(match[1], user.id, body.time_ms, new Date().toISOString()),
        ...timeQueries(env.LEVELS_DB, match[1], user.id),
      ]);
      return json({ ...timeResponse(results.slice(1)), improved: results[0].results.length > 0 });
    }
    if (request.method === "GET") {
      if (collection) {
        const { results } = await env.LEVELS_DB.prepare(SUMMARY + " ORDER BY created_at DESC, levels.id LIMIT 100").bind(user?.id ?? null).all();
        return json({ levels: results, capacity: MAX_LEVELS });
      }
      const level = await env.LEVELS_DB.prepare("SELECT id, title, author, author_id, created_at, level_code FROM levels WHERE id = ?").bind(match[1]).first();
      return level ? json({ level }) : json({ error: "This level is no longer available. Refresh the library." }, 404);
    }
    const body = await readJson(request, MAX_BODY);
    const title = name(body.title, 64);
    const payload = await decodeCode(body.level_code);
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", payload));
    const id = Array.from(hash, byte => byte.toString(16).padStart(2, "0")).join("");
    const createdAt = new Date().toISOString();
    // Capacity and insert are one atomic statement, even with concurrent uploads.
    const inserted = await env.LEVELS_DB.prepare(`INSERT INTO levels (id, title, author, author_id, created_at, level_code)
      SELECT ?, ?, ?, ?, ?, ? WHERE (SELECT COUNT(*) FROM levels) < 100
      ON CONFLICT(id) DO NOTHING RETURNING id`).bind(id, title, user.username, user.id, createdAt, body.level_code).first();
    if (inserted) return json({ id, duplicate: false }, 201);
    const existing = await env.LEVELS_DB.prepare("SELECT id FROM levels WHERE id = ?").bind(id).first();
    if (existing) return json({ id, duplicate: true });
    return json({ error: FULL }, 409);
  } catch (error) {
    if (error instanceof RequestError) return json({ error: error.message }, error.status);
    console.error(JSON.stringify({ event: "level_library_failed", method: request.method }));
    return json({ error: "The level library is temporarily unavailable. Try again shortly." }, 503);
  }
}
