import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";

const ORIGIN = "https://wizkinews.com";
const schema = ["0001_levels.sql", "0002_accounts.sql"].map(path => readFileSync(new URL("../migrations/" + path, import.meta.url), "utf8")).join("\n");
const encode = bytes => "MG1-" + deflateSync(Buffer.from(bytes)).toString("base64");
const playable = (x = 10) => encode([1, 1, 0, 0, x, 2, 0, 0, 5, 100, 5]);

async function runtime(t, uploadLimit = 1000) {
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [{
    name: "library-test", compatibilityDate: "2026-10-27", compatibilityFlags: ["nodejs_compat"],
    modules: ["worker.js", "levels.js", "accounts.js", "api_helpers.js"].map(path => ({ type: "ESModule", path,
      contents: readFileSync(new URL("../src/" + path, import.meta.url), "utf8") })),
    bindings: { ALLOWED_ORIGINS: ORIGIN },
    d1Databases: { LEVELS_DB: "local-levels" },
    durableObjects: { ROOMS: { className: "GameRoom", useSQLite: true }, LOBBIES: { className: "LobbyDirectory", useSQLite: true } },
    ratelimits: {
      CONNECT_LIMITER: { namespace_id: "271002", simple: { limit: 1000, period: 60 } },
      UPLOAD_LIMITER: { namespace_id: "271003", simple: { limit: uploadLimit, period: 60 } },
      AUTH_LIMITER: { namespace_id: "271004", simple: { limit: 1000, period: 60 } },
      REGISTER_LIMITER: { namespace_id: "271005", simple: { limit: 1000, period: 60 } },
    },
    outboundService: () => { throw new Error("Unexpected external request"); },
  }] }));
  t.after(() => mf.dispose());
  const db = await mf.getD1Database("LEVELS_DB");
  const statements = schema.match(/CREATE TABLE[\s\S]+?;|CREATE INDEX[^;]+;|CREATE TRIGGER[\s\S]+?END;|ALTER TABLE[^;]+;/g);
  await db.batch(statements.map(sql => db.prepare(sql)));
  const registered = await mf.dispatchFetch("https://rooms.example/auth/register", { method: "POST",
    headers: { Origin: ORIGIN, "Content-Type": "application/json" },
    body: JSON.stringify({ username: "Creator", password: "A test password for grapplers." }),
  });
  assert.equal(registered.status, 201, await registered.clone().text());
  mf.testToken = (await registered.json()).token;
  return { mf, db };
}

function upload(mf, levelCode = playable(), extra = {}) {
  return mf.dispatchFetch("https://rooms.example/levels", { method: "POST",
    headers: { Origin: ORIGIN, "Content-Type": "application/json", Authorization: "Bearer " + mf.testToken },
    body: JSON.stringify({ title: "First course", author: "Creator", level_code: levelCode, ...extra }),
  });
}

test("publish, browse newest metadata, download exact level, and retry idempotently", async t => {
  const { mf } = await runtime(t);
  const empty = await mf.dispatchFetch("https://rooms.example/levels");
  assert.deepEqual(await empty.json(), { levels: [], capacity: 100 });
  const published = await upload(mf);
  assert.equal(published.status, 201);
  assert.equal(published.headers.get("Access-Control-Allow-Origin"), ORIGIN);
  const { id } = await published.json();
  assert.match(id, /^[a-f0-9]{64}$/);
  const duplicate = await upload(mf, playable(), { title: "Retry" });
  assert.equal(duplicate.status, 200);
  assert.deepEqual(await duplicate.json(), { id, duplicate: true });
  const differentlyCompressed = "MG1-" + deflateSync(Buffer.from([1, 1, 0, 0, 10, 2, 0, 0, 5, 100, 5]), { level: 0 }).toString("base64");
  const compressedRetry = await upload(mf, differentlyCompressed);
  assert.deepEqual(await compressedRetry.json(), { id, duplicate: true });
  await upload(mf, playable(11), { title: "Second course", author: "" });
  const list = await (await mf.dispatchFetch("https://rooms.example/levels")).json();
  assert.equal(list.levels.length, 2);
  assert.equal(list.levels[0].title, "Second course");
  assert.equal(list.levels[0].author, "Creator");
  assert.equal(list.levels[1].title, "First course");
  assert.equal("level_code" in list.levels[0], false);
  const level = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}`)).json();
  assert.equal(level.level.level_code, playable());
  assert.equal((await mf.dispatchFetch("https://rooms.example/levels/" + "0".repeat(64))).status, 404);
});

test("concurrent uploads stop at 100, retain existing levels, allow duplicate retry at capacity", async t => {
  const { mf, db } = await runtime(t);
  // Distinct valid levels: different spawn cells, all clear of the terrain.
  const code = index => encode([1, 1, 0, 0, index % 100, 10 + Math.floor(index / 100), 0, 0, 5, 100, 5]);
  const responses = await Promise.all(Array.from({ length: 110 }, (_, index) => upload(mf, code(index))));
  assert.equal(responses.filter(response => response.status === 201).length, 100);
  assert.equal(responses.filter(response => response.status === 409).length, 10);
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM levels").first("count"), 100);
  const firstAccepted = responses.findIndex(response => response.status === 201);
  const duplicate = await upload(mf, code(firstAccepted));
  assert.equal(duplicate.status, 200);
  assert.equal((await duplicate.json()).duplicate, true);
  // The migration protects the cap even if an administrator bypasses the API.
  await assert.rejects(db.prepare("INSERT INTO levels (id, title, author, created_at, level_code) VALUES (?, ?, ?, ?, ?)")
    .bind("f".repeat(64), "Overflow", "Admin", new Date().toISOString(), playable()).run(), /level_library_full/);
  const list = await (await mf.dispatchFetch("https://rooms.example/levels")).json();
  assert.equal(list.levels.length, 100);
});

test("reject invalid data, compressed bombs, nonplayable spawns, and invalid race trailers", async t => {
  const { mf, db } = await runtime(t);
  for (const code of ["MG1-AAAA", "bad", encode([1, 0, 0, 0, 255, 255]),
    encode([1, 1, 0, 0, 10, 4, 0, 0, 5, 100, 5]), // spawn intersects terrain
    encode([1, 1, 0, 0, 10, 2, 9, 0, 5, 100, 5]), // unknown segment kind
    encode([1, 0, 0, 0, 10, 2, 82, 1, 2, 2, 20, 20]), // laps with separate finish
    encode([1, 0, 0, 0, 10, 2, 82, 1, 1, 1, 10, 2]), // checkpoint duplicates spawn
    encode(new Uint8Array(100_000)), playable() + "A".repeat(16384)]) {
    assert.equal((await upload(mf, code)).status, 400, code.slice(0, 50));
  }
  for (const extra of [{ title: " " }, { title: "X".repeat(65) }, { title: 42 }]) {
    assert.equal((await upload(mf, playable(), extra)).status, 400);
  }
  const headers = { "Content-Type": "application/json", Authorization: "Bearer " + mf.testToken };
  assert.equal((await mf.dispatchFetch("https://rooms.example/levels", { method: "POST", headers, body: "{" })).status, 400);
  assert.equal((await mf.dispatchFetch("https://rooms.example/levels", { method: "POST", headers, body: " ".repeat(21_000) })).status, 413);
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM levels").first("count"), 0);
  const race = encode([1, 0, 0, 0, 10, 2, 82, 2, 3, 1, 20, 20, 30, 30]);
  assert.equal((await upload(mf, race)).status, 201);
});

test("browser preflight, origin checks, methods, and upload throttling", async t => {
  const { mf } = await runtime(t, 1);
  const preflight = await mf.dispatchFetch("https://rooms.example/levels", { method: "OPTIONS", headers: { Origin: ORIGIN, "Access-Control-Request-Headers": "content-type" } });
  assert.equal(preflight.status, 204);
  assert.match(preflight.headers.get("Access-Control-Allow-Methods"), /POST/);
  assert.match(preflight.headers.get("Access-Control-Allow-Headers"), /Authorization/);
  assert.equal((await mf.dispatchFetch("https://rooms.example/levels", { headers: { Origin: "https://untrusted.example" } })).status, 403);
  assert.equal((await mf.dispatchFetch("https://rooms.example/levels", { method: "DELETE" })).status, 405);
  assert.equal((await upload(mf)).status, 201);
  assert.equal((await upload(mf, playable(11))).status, 429);
});

test("accept maximum-size Godot payload and reject curves outside the board", async t => {
  const { mf } = await runtime(t);
  const bytes = [1, 0, 4, 128, 10, 2];
  for (let index = 0; index < 1024; index++) bytes.push(1, 1, 30, 3, 30, 2, 29);
  for (let index = 0; index < 128; index++) bytes.push(index % 100, 50 + Math.floor(index / 100));
  bytes.push(82, 128, 50, 1);
  for (let index = 0; index < 128; index++) bytes.push(index % 100, 60 + Math.floor(index / 100));
  assert.equal((await upload(mf, encode(bytes))).status, 201);
  const overshoot = encode([1, 1, 0, 0, 10, 2, 1, 0, 0, 100, 0, 1, 1]);
  assert.equal((await upload(mf, overshoot)).status, 400);
});
