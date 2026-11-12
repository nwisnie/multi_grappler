import { scrypt, timingSafeEqual } from "node:crypto";
import { Buffer } from "node:buffer";
import { RequestError, readJson, requireSecureTransport } from "./api_helpers.js";

const SESSION_LIFETIME = 24 * 60 * 60 * 1000;
// OWASP's 16 MiB scrypt profile. Version the scheme before changing these settings.
const SCRYPT = { N: 16384, r: 8, p: 5, maxmem: 32 * 1024 * 1024 };
const hex = bytes => Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
const randomHex = length => hex(crypto.getRandomValues(new Uint8Array(length)));

function passwordHash(password, salt) {
  return new Promise((resolve, reject) => {
    scrypt(password, Buffer.from(salt, "hex"), 32, SCRYPT, (error, result) => error ? reject(error) : resolve(result));
  });
}

async function tokenHash(token) {
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))));
}

function bearer(request) {
  const match = /^Bearer ([a-f0-9]{64})$/.exec(request.headers.get("Authorization") || "");
  return match?.[1] || "";
}

export async function requireUser(request, env) {
  requireSecureTransport(request);
  const token = bearer(request);
  if (!token) throw new RequestError("Sign in or create an account to upload levels.", 401);
  const user = await env.LEVELS_DB.prepare(`SELECT users.id, users.username FROM account_sessions
    JOIN users ON users.id = account_sessions.user_id WHERE token_hash = ? AND expires_at > ?`)
    .bind(await tokenHash(token), Date.now()).first();
  if (!user) throw new RequestError("Your session has expired. Please sign in again.", 401);
  return user;
}

async function issueSession(env, user) {
  const token = randomHex(32), expiresAt = Date.now() + SESSION_LIFETIME;
  // Bound each account to five live sessions; the batch is transactional.
  await env.LEVELS_DB.batch([
    env.LEVELS_DB.prepare("DELETE FROM account_sessions WHERE expires_at <= ?").bind(Date.now()),
    env.LEVELS_DB.prepare(`DELETE FROM account_sessions WHERE token_hash IN (
      SELECT token_hash FROM account_sessions WHERE user_id = ? ORDER BY expires_at DESC, rowid DESC LIMIT -1 OFFSET 4)`)
      .bind(user.id),
    env.LEVELS_DB.prepare("INSERT INTO account_sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)")
      .bind(await tokenHash(token), user.id, expiresAt),
  ]);
  return { user: { id: user.id, username: user.username }, token, expires_at: expiresAt };
}

export async function accounts(request, env) {
  const origin = request.headers.get("Origin");
  const allowed = (env.ALLOWED_ORIGINS || "").split(",").map(value => value.trim());
  const headers = { "Access-Control-Allow-Origin": origin || "*", Vary: "Origin", "Cache-Control": "no-store" };
  const json = (body, status = 200) => Response.json(body, { status, headers });
  if (origin && !allowed.includes(origin)) return json({ error: "Origin not allowed." }, 403);
  const action = new URL(request.url).pathname;
  const method = action === "/auth/me" ? "GET" : "POST";
  if (!["/auth/register", "/auth/login", "/auth/logout", "/auth/me"].includes(action)) return json({ error: "Not found." }, 404);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: {
    ...headers, "Access-Control-Allow-Methods": method + ", OPTIONS", "Access-Control-Allow-Headers": "Content-Type, Authorization",
  } });
  if (request.method !== method) return json({ error: "Method not allowed." }, 405);
  if (!env.LEVELS_DB) return json({ error: "Accounts are not configured yet." }, 503);
  try {
    requireSecureTransport(request);
    const key = request.headers.get("CF-Connecting-IP") || "local";
    if (!(await env.AUTH_LIMITER.limit({ key: "ip:" + key })).success) throw new RequestError("Too many account requests. Try again in a minute.", 429);
    if (action === "/auth/me") return json({ user: await requireUser(request, env) });
    if (action === "/auth/logout") {
      const token = bearer(request);
      if (token) await env.LEVELS_DB.prepare("DELETE FROM account_sessions WHERE token_hash = ?").bind(await tokenHash(token)).run();
      return json({ signed_out: true });
    }
    const body = await readJson(request, 2048);
    const username = typeof body.username === "string" ? body.username.trim() : "";
    if (!/^[A-Za-z0-9_]{3,24}$/.test(username)) throw new RequestError("Use 3–24 letters, numbers, or underscores for your username.");
    if (typeof body.password !== "string" || Array.from(body.password).length < 4 || Array.from(body.password).length > 32) {
      throw new RequestError("Use a password with 4–32 characters.");
    }
    const usernameKey = username.toLowerCase();
    if (!(await env.AUTH_LIMITER.limit({ key: "user:" + usernameKey })).success) throw new RequestError("Too many account requests. Try again in a minute.", 429);
    if (action === "/auth/register") {
      if (!(await env.REGISTER_LIMITER.limit({ key })).success) throw new RequestError("Too many accounts created. Try again in a minute.", 429);
      const salt = randomHex(16), id = crypto.randomUUID();
      const hash = hex(await passwordHash(body.password, salt));
      const user = await env.LEVELS_DB.prepare(`INSERT INTO users (id, username, username_key, password_salt, password_hash, created_at)
        VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(username_key) DO NOTHING RETURNING id, username`)
        .bind(id, username, usernameKey, salt, hash, new Date().toISOString()).first();
      if (!user) throw new RequestError("That username is already taken.", 409);
      return json(await issueSession(env, user), 201);
    }
    const user = await env.LEVELS_DB.prepare("SELECT id, username, password_salt, password_hash, password_scheme FROM users WHERE username_key = ?").bind(usernameKey).first();
    // Unknown usernames take the same password-hashing path as existing accounts.
    const derived = await passwordHash(body.password, user?.password_salt || "0".repeat(32));
    const matches = timingSafeEqual(derived, Buffer.from(user?.password_hash || "0".repeat(64), "hex"));
    if (!user || !matches || user.password_scheme !== "scrypt-v1") throw new RequestError("Incorrect username or password.", 401);
    return json(await issueSession(env, user));
  } catch (error) {
    if (error instanceof RequestError) return json({ error: error.message }, error.status);
    // Never log passwords, Authorization headers, tokens, hashes, or request bodies.
    console.error(JSON.stringify({ event: "account_request_failed", action }));
    return json({ error: "The account service is temporarily unavailable. Try again shortly." }, 503);
  }
}
