import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash, scryptSync } from "node:crypto";
import { deflateSync } from "node:zlib";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";

const ORIGIN = "https://wizkinews.com";
const PASSWORD = "Test password for grapplers.";
const CODE = "MG1-" + deflateSync(Buffer.from([1, 1, 0, 0, 10, 2, 0, 0, 5, 100, 5])).toString("base64");

async function runtime(t, authLimit = 1000, registrationLimit = 1000) {
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [{
    name: "account-test", compatibilityDate: "2026-10-27", compatibilityFlags: ["nodejs_compat"],
    modules: ["worker.js", "levels.js", "accounts.js", "api_helpers.js"].map(path => ({
      type: "ESModule", path, contents: readFileSync(new URL("../src/" + path, import.meta.url), "utf8"),
    })),
    bindings: { ALLOWED_ORIGINS: ORIGIN },
    d1Databases: { LEVELS_DB: "local-accounts" },
    durableObjects: { ROOMS: { className: "GameRoom", useSQLite: true }, LOBBIES: { className: "LobbyDirectory", useSQLite: true } },
    ratelimits: Object.fromEntries([
      ["CONNECT_LIMITER", 1000], ["UPLOAD_LIMITER", 1000], ["AUTH_LIMITER", authLimit], ["REGISTER_LIMITER", registrationLimit],
    ].map(([name, limit], index) => [name, { namespace_id: String(280000 + index), simple: { limit, period: 60 } }])),
    outboundService: () => { throw new Error("Unexpected external request"); },
  }] }));
  t.after(() => mf.dispose());
  const db = await mf.getD1Database("LEVELS_DB");
  for (const file of ["0001_levels.sql", "0002_accounts.sql"]) {
    const sql = readFileSync(new URL("../migrations/" + file, import.meta.url), "utf8");
    const statements = sql.match(/CREATE TABLE[\s\S]+?;|CREATE INDEX[^;]+;|CREATE TRIGGER[\s\S]+?END;|ALTER TABLE[^;]+;/g);
    await db.batch(statements.map(statement => db.prepare(statement)));
    if (file === "0001_levels.sql") await db.prepare("INSERT INTO levels VALUES (?, ?, ?, ?, ?)")
      .bind("a".repeat(64), "Legacy course", "Legacy creator", "2026-01-01T00:00:00Z", CODE).run();
  }
  return { mf, db };
}

function call(mf, path, body, token = "") {
  const headers = { Origin: ORIGIN, "Content-Type": "application/json" };
  if (token) headers.Authorization = "Bearer " + token;
  return mf.dispatchFetch("https://rooms.example" + path, {
    method: body === undefined ? "GET" : "POST", headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function register(mf, username = "Grappler") {
  const response = await call(mf, "/auth/register", { username, password: PASSWORD });
  assert.equal(response.status, 201, await response.clone().text());
  return response.json();
}

test("register unique usernames, hash salted passwords, sign in without case sensitivity", async t => {
  const { mf, db } = await runtime(t);
  const first = await register(mf);
  const second = await register(mf, "OtherPlayer");
  assert.equal(first.user.username, "Grappler");
  assert.match(first.token, /^[a-f0-9]{64}$/);
  assert.equal("password" in first.user, false);
  const rows = (await db.prepare("SELECT * FROM users ORDER BY username").all()).results;
  assert.notEqual(rows[0].password_hash, rows[1].password_hash);
  assert.notEqual(rows[0].password_salt, rows[1].password_salt);
  assert.equal(rows[0].password_hash, scryptSync(PASSWORD, Buffer.from(rows[0].password_salt, "hex"), 32, { N: 16384, r: 8, p: 5, maxmem: 32 * 1024 * 1024 }).toString("hex"));
  assert.equal((await call(mf, "/auth/register", { username: "gRAPPLER", password: PASSWORD })).status, 409);
  const signedIn = await call(mf, "/auth/login", { username: "grappler", password: PASSWORD });
  assert.equal(signedIn.status, 200);
  assert.equal((await signedIn.json()).user.id, first.user.id);
  const badPassword = await call(mf, "/auth/login", { username: "Grappler", password: "Incorrect long password." });
  const absentUser = await call(mf, "/auth/login", { username: "UnknownPlayer", password: PASSWORD });
  assert.equal(badPassword.status, 401);
  assert.deepEqual(await badPassword.json(), await absentUser.json());
  assert.notEqual(first.token, second.token);
});

test("upload requires a real session and derives attribution from the account", async t => {
  const { mf, db } = await runtime(t);
  const upload = { title: "Authenticated course", author: "ImpersonatedPlayer", level_code: CODE };
  assert.equal((await call(mf, "/levels", upload)).status, 401);
  assert.equal((await call(mf, "/levels", upload, "0".repeat(64))).status, 401);
  const account = await register(mf);
  const uploaded = await call(mf, "/levels", upload, account.token);
  assert.equal(uploaded.status, 201);
  const { id } = await uploaded.json();
  const record = await db.prepare("SELECT author, author_id FROM levels WHERE id = ?").bind(id).first();
  assert.deepEqual(record, { author: "Grappler", author_id: account.user.id });
  const summaries = await (await call(mf, "/levels")).json();
  assert.equal(summaries.levels.length, 2);
  assert.equal(summaries.levels[1].author, "Legacy creator");
  assert.equal(await db.prepare("SELECT author_id FROM levels WHERE title = 'Legacy course'").first("author_id"), null);
  assert.equal((await call(mf, "/levels/" + id)).status, 200);
  const stored = await db.prepare("SELECT token_hash FROM account_sessions WHERE user_id = ?").bind(account.user.id).first();
  assert.notEqual(stored.token_hash, account.token);
  assert.equal(stored.token_hash, createHash("sha256").update(account.token).digest("hex"));
  assert.equal((await call(mf, "/auth/logout", {}, account.token)).status, 200);
  assert.equal((await call(mf, "/levels", upload, account.token)).status, 401);
  assert.equal((await call(mf, "/auth/me", undefined, account.token)).status, 401);
});

test("expired sessions fail; each account retains at most five sessions", async t => {
  const { mf, db } = await runtime(t);
  const first = await register(mf);
  let current = first;
  for (let index = 0; index < 5; index++) {
    current = await (await call(mf, "/auth/login", { username: "Grappler", password: PASSWORD })).json();
  }
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM account_sessions").first("count"), 5);
  assert.equal((await call(mf, "/auth/me", undefined, first.token)).status, 401);
  assert.equal((await call(mf, "/auth/me", undefined, current.token)).status, 200);
  await db.prepare("UPDATE account_sessions SET expires_at = 0").run();
  assert.equal((await call(mf, "/levels", { title: "Expired", level_code: CODE }, current.token)).status, 401);
});

test("validate credentials, request bounds, HTTPS, browser preflights and origins", async t => {
  const { mf } = await runtime(t);
  for (const username of ["", "ab", "a".repeat(25), "with spaces", "player<script>", "nonasciié"]) {
    assert.equal((await call(mf, "/auth/register", { username, password: PASSWORD })).status, 400);
  }
  for (const password of ["abc", "a".repeat(33), 12345]) {
    for (const action of ["register", "login"]) {
      assert.equal((await call(mf, "/auth/" + action, { username: "ValidName", password })).status, 400);
    }
  }
  for (const length of [4, 32]) {
    const body = { username: "Boundary" + length, password: "a".repeat(length) };
    assert.equal((await call(mf, "/auth/register", body)).status, 201);
    assert.equal((await call(mf, "/auth/login", body)).status, 200);
  }
  assert.equal((await mf.dispatchFetch("https://rooms.example/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{" })).status, 400);
  assert.equal((await mf.dispatchFetch("https://rooms.example/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: " ".repeat(3000) })).status, 413);
  assert.equal((await mf.dispatchFetch("https://rooms.example/auth/login", { method: "POST" })).status, 415);
  assert.equal((await mf.dispatchFetch("http://rooms.example/auth/login", { method: "POST" })).status, 400);
  assert.equal((await mf.dispatchFetch("https://rooms.example/auth/login", { method: "POST", headers: { Origin: "https://untrusted.example" } })).status, 403);
  const preflight = await mf.dispatchFetch("https://rooms.example/auth/login", { method: "OPTIONS", headers: { Origin: ORIGIN } });
  assert.equal(preflight.status, 204);
  assert.match(preflight.headers.get("Access-Control-Allow-Headers"), /Authorization/);
});

test("limit account attempts and account creation before expensive password work", async t => {
  const { mf } = await runtime(t, 2, 1);
  await register(mf);
  assert.equal((await call(mf, "/auth/register", { username: "OtherName", password: PASSWORD })).status, 429);
  assert.equal((await call(mf, "/auth/login", { username: "Grappler", password: PASSWORD })).status, 429);
});
