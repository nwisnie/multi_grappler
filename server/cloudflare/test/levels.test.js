import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { createHash } from "node:crypto";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";

const ORIGIN = "https://wizkinews.com";
const schema = ["0001_levels.sql", "0002_accounts.sql", "0003_level_times.sql"].map(path => readFileSync(new URL("../migrations/" + path, import.meta.url), "utf8")).join("\n");
const encode = bytes => "MG1-" + deflateSync(Buffer.from(bytes)).toString("base64");
const playable = (x = 10) => encode([1, 1, 0, 0, x, 2, 0, 0, 5, 100, 5]);
const raceCode = (x = 10) => encode([1, 0, 0, 0, x, 2, 82, 1, 1, 2, 20, 20]);

function timeRequest(mf, id, time, token = mf.testToken, extra = {}) {
  return mf.dispatchFetch(`https://rooms.example/levels/${id}/times`, { method: "POST",
    headers: { Origin: ORIGIN, "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}) },
    body: JSON.stringify({ time_ms: time, ...extra }),
  });
}

function deleteRequest(mf, id, token = mf.testToken, origin = ORIGIN, scheme = "https") {
  return mf.dispatchFetch(`${scheme}://rooms.example/levels/${id}`, { method: "DELETE",
    headers: { Origin: origin, ...(token ? { Authorization: "Bearer " + token } : {}) },
  });
}

test("only the original uploader's live account can delete a publication", async t => {
  const { mf, db } = await runtime(t);
  const { id } = await (await upload(mf, raceCode())).json();
  await timeRequest(mf, id, 1000);
  const otherToken = await racer(db, 42);
  // A duplicate upload and even matching display attribution do not grant ownership.
  await db.prepare("UPDATE users SET username = 'Creator' WHERE id = 'racer-42'").run();
  const duplicate = await mf.dispatchFetch("https://rooms.example/levels", { method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + otherToken },
    body: JSON.stringify({ title: "Claimed", level_code: raceCode() }),
  });
  assert.equal((await duplicate.json()).duplicate, true);
  assert.equal((await deleteRequest(mf, id, "")).status, 401);
  assert.equal((await deleteRequest(mf, id, "f".repeat(64))).status, 401);
  assert.equal((await deleteRequest(mf, id, otherToken)).status, 403);
  await db.prepare("UPDATE account_sessions SET expires_at = 0 WHERE user_id = 'racer-42'").run();
  assert.equal((await deleteRequest(mf, id, otherToken)).status, 401);
  assert.equal((await deleteRequest(mf, id, mf.testToken, "https://untrusted.example")).status, 403);
  assert.equal((await deleteRequest(mf, id, mf.testToken, ORIGIN, "http")).status, 400);
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM levels").first("count"), 1);
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM level_times").first("count"), 1);
  await db.prepare("UPDATE levels SET author_id = NULL WHERE id = ?").bind(id).run();
  assert.equal((await deleteRequest(mf, id)).status, 403, "Unclaimed legacy authors cannot be deleted by matching usernames");
  assert.equal((await deleteRequest(mf, "0".repeat(64))).status, 404);
});

test("deleting a publication removes all its records, preserves other levels, and resets times on republication", async t => {
  const { mf, db } = await runtime(t);
  const { id } = await (await upload(mf, raceCode())).json();
  const other = await (await upload(mf, raceCode(11))).json();
  await timeRequest(mf, other.id, 500);
  await timeRequest(mf, id, 900);
  for (let index = 1; index <= 12; index++) {
    assert.equal((await timeRequest(mf, id, index * 1000, await racer(db, index))).status, 200);
  }
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM level_times WHERE level_id = ?").bind(id).first("count"), 13);
  const results = await Promise.all([deleteRequest(mf, id), deleteRequest(mf, id)]);
  assert.deepEqual(results.map(result => result.status).sort(), [200, 404]);
  const deleted = results.find(result => result.status === 200);
  assert.deepEqual(await deleted.json(), { id });
  assert.equal(deleted.headers.get("Access-Control-Allow-Origin"), ORIGIN);
  assert.equal(deleted.headers.get("Cache-Control"), "no-store");
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM level_times WHERE level_id = ?").bind(id).first("count"), 0);
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM level_times WHERE level_id = ?").bind(other.id).first("count"), 1);
  assert.equal((await mf.dispatchFetch(`https://rooms.example/levels/${id}`)).status, 404);
  assert.equal((await mf.dispatchFetch(`https://rooms.example/levels/${id}/times`)).status, 404);
  assert.equal((await timeRequest(mf, id, 100)).status, 404);
  const list = await (await mf.dispatchFetch("https://rooms.example/levels")).json();
  assert.deepEqual(list.levels.map(level => level.id), [other.id]);
  assert.equal(list.levels[0].top_time_ms, 500);
  const republished = await upload(mf, raceCode());
  assert.equal(republished.status, 201);
  assert.equal((await republished.json()).id, id);
  const times = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}/times`, {
    headers: { Authorization: "Bearer " + mf.testToken },
  })).json();
  assert.deepEqual(times, { leaderboard: [], top_time_ms: null, personal_time_ms: null });
});

test("level deletion supports authenticated browser preflight only on individual publications", async t => {
  const { mf } = await runtime(t);
  const url = "https://rooms.example/levels/" + "a".repeat(64);
  const response = await mf.dispatchFetch(url, { method: "OPTIONS", headers: {
    Origin: ORIGIN, "Access-Control-Request-Method": "DELETE", "Access-Control-Request-Headers": "Authorization",
  } });
  assert.equal(response.status, 204);
  assert.match(response.headers.get("Access-Control-Allow-Methods"), /DELETE/);
  assert.match(response.headers.get("Access-Control-Allow-Headers"), /Authorization/);
  for (const path of ["/levels", "/levels/" + "a".repeat(64) + "/times"]) {
    const options = await mf.dispatchFetch("https://rooms.example" + path, { method: "OPTIONS" });
    assert.doesNotMatch(options.headers.get("Access-Control-Allow-Methods"), /DELETE/);
    assert.equal((await mf.dispatchFetch("https://rooms.example" + path, { method: "DELETE" })).status, 405);
  }
  assert.equal((await mf.dispatchFetch(url, { method: "PUT" })).status, 405);
  assert.equal((await deleteRequest(mf, "bad-id")).status, 404);
});

async function racer(db, index) {
  const id = "racer-" + index, token = index.toString(16).padStart(64, "0");
  await db.batch([
    db.prepare(`INSERT INTO users (id, username, username_key, password_salt, password_hash, created_at)
      VALUES (?, ?, ?, 'test-salt', 'test-hash', '2026-01-01')`).bind(id, "Racer" + index, "racer" + index),
    db.prepare("INSERT INTO account_sessions VALUES (?, ?, ?)")
      .bind(createHash("sha256").update(token).digest("hex"), id, Date.now() + 3600000),
  ]);
  return token;
}

test("times require a signed-in account, a published race, and bounded integer milliseconds", async t => {
  const { mf, db } = await runtime(t);
  const { id } = await (await upload(mf, raceCode())).json();
  assert.equal((await timeRequest(mf, id, 1000, "")).status, 401);
  assert.equal((await timeRequest(mf, id, 1000, "f".repeat(64))).status, 401);
  for (const time of [0, -1, 1.5, "1000", null, 86400001, Number.MAX_SAFE_INTEGER]) {
    assert.equal((await timeRequest(mf, id, time)).status, 400, String(time));
  }
  assert.equal((await timeRequest(mf, "0".repeat(64), 1000)).status, 404);
  const nonrace = await (await upload(mf)).json();
  assert.equal((await timeRequest(mf, nonrace.id, 1000)).status, 400);
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM level_times").first("count"), 0);
  const token = await racer(db, 42);
  await db.prepare("UPDATE account_sessions SET expires_at = 0 WHERE user_id = 'racer-42'").run();
  assert.equal((await timeRequest(mf, id, 1000, token)).status, 401);
  assert.equal((await timeRequest(mf, id, 1000)).status, 200);
  await mf.dispatchFetch("https://rooms.example/auth/logout", { method: "POST", headers: { Authorization: "Bearer " + mf.testToken } });
  assert.equal((await timeRequest(mf, id, 900)).status, 401);
});

test("top 10 is ordered per level, shows usernames and retains personal bests outside the top 10", async t => {
  const { mf, db } = await runtime(t);
  const { id } = await (await upload(mf, raceCode())).json();
  const empty = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}/times`)).json();
  assert.deepEqual(empty, { leaderboard: [], top_time_ms: null, personal_time_ms: null });
  const tokens = [];
  for (let index = 1; index <= 12; index++) {
    tokens.push(await racer(db, index));
    const response = await timeRequest(mf, id, index * 1000, tokens.at(-1), { user_id: "racer-1", username: "Forged" });
    assert.equal(response.status, 200, await response.clone().text());
  }
  const publicResult = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}/times`)).json();
  assert.equal(publicResult.leaderboard.length, 10);
  assert.deepEqual(publicResult.leaderboard.map(row => row.time_ms), Array.from({ length: 10 }, (_, index) => (index + 1) * 1000));
  assert.deepEqual(publicResult.leaderboard.map(row => row.rank), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  assert.equal(publicResult.leaderboard[0].username, "Racer1");
  assert.equal(publicResult.personal_time_ms, null);
  const headers = { Authorization: "Bearer " + tokens[11] };
  const personal = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}/times`, { headers })).json();
  assert.equal(personal.personal_time_ms, 12000);
  const list = await (await mf.dispatchFetch("https://rooms.example/levels", { headers })).json();
  assert.equal(list.levels[0].top_time_ms, 1000);
  assert.equal(list.levels[0].personal_time_ms, 12000);
  const anonymous = await (await mf.dispatchFetch("https://rooms.example/levels")).json();
  assert.equal(anonymous.levels[0].personal_time_ms, null);
  const second = await (await upload(mf, raceCode(11))).json();
  const independent = await (await mf.dispatchFetch(`https://rooms.example/levels/${second.id}/times`, { headers })).json();
  assert.equal(independent.personal_time_ms, null);
  assert.equal(independent.leaderboard.length, 0);
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM level_times WHERE level_id = ?").bind(id).first("count"), 12);
  await db.prepare("DELETE FROM levels WHERE id = ?").bind(id).run();
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM level_times").first("count"), 0);
});

test("slower and equal retries preserve a best, concurrent finishes keep the fastest, ties are stable", async t => {
  const { mf, db } = await runtime(t);
  const { id } = await (await upload(mf, raceCode())).json();
  const first = await (await timeRequest(mf, id, 12000)).json();
  assert.equal(first.improved, true);
  const before = await db.prepare("SELECT achieved_at FROM level_times WHERE level_id = ?").bind(id).first("achieved_at");
  for (const time of [14000, 12000]) {
    const result = await (await timeRequest(mf, id, time)).json();
    assert.equal(result.improved, false);
    assert.equal(result.personal_time_ms, 12000);
  }
  assert.equal(await db.prepare("SELECT achieved_at FROM level_times WHERE level_id = ?").bind(id).first("achieved_at"), before);
  const responses = await Promise.all([11000, 7000, 9000, 5000, 8000].map(time => timeRequest(mf, id, time)));
  assert.ok(responses.every(response => response.status === 200));
  assert.equal(await db.prepare("SELECT time_ms FROM level_times WHERE level_id = ?").bind(id).first("time_ms"), 5000);
  for (const index of [22, 21]) await timeRequest(mf, id, 5000, await racer(db, index));
  // Force the timestamp tie to verify the final deterministic user-ID ordering.
  await db.prepare("UPDATE level_times SET achieved_at = '2026-01-01'").run();
  const a = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}/times`)).json();
  const b = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}/times`)).json();
  assert.deepEqual(a, b);
  assert.deepEqual(a.leaderboard.map(row => row.user_id), a.leaderboard.map(row => row.user_id).sort());
});

test("time routes enforce browser origins, preflight, methods, body size, and secure transport", async t => {
  const { mf } = await runtime(t);
  const { id } = await (await upload(mf, raceCode())).json();
  const url = `https://rooms.example/levels/${id}/times`;
  const preflight = await mf.dispatchFetch(url, { method: "OPTIONS", headers: { Origin: ORIGIN } });
  assert.equal(preflight.status, 204);
  assert.match(preflight.headers.get("Access-Control-Allow-Methods"), /POST/);
  assert.match(preflight.headers.get("Access-Control-Allow-Headers"), /Authorization/);
  assert.equal((await mf.dispatchFetch(url, { headers: { Origin: "https://untrusted.example" } })).status, 403);
  assert.equal((await mf.dispatchFetch(url, { method: "DELETE" })).status, 405);
  const headers = { Authorization: "Bearer " + mf.testToken, "Content-Type": "application/json" };
  assert.equal((await mf.dispatchFetch(url, { method: "POST", headers, body: "{" })).status, 400);
  assert.equal((await mf.dispatchFetch(url, { method: "POST", headers, body: " ".repeat(1100) })).status, 413);
  assert.equal((await mf.dispatchFetch(url.replace("https:", "http:"), { method: "POST", headers, body: '{"time_ms":1000}' })).status, 400);
});

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
  const { mf, db } = await runtime(t);
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
  const creatorId = await db.prepare("SELECT id FROM users WHERE username = 'Creator'").first("id");
  assert.equal(list.levels[0].author_id, creatorId);
  assert.equal(list.levels[1].author_id, creatorId);
  assert.equal(list.levels[1].title, "First course");
  assert.equal("level_code" in list.levels[0], false);
  const level = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}`)).json();
  assert.equal(level.level.level_code, playable());
  assert.equal(level.level.author_id, creatorId);
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
  assert.equal((await deleteRequest(mf, list.levels[0].id)).status, 200);
  assert.equal((await upload(mf, code(120))).status, 201, "Deleting a publication frees a library slot");
  assert.equal(await db.prepare("SELECT COUNT(*) AS count FROM levels").first("count"), 100);
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

test("publish and download mixed checkpoint lines with a chosen spawn position", async t => {
  const { mf } = await runtime(t);
  const code = encode([1, 0, 0, 0, 10, 10, 82, 2, 3, 1, 20, 10, 30, 10,
    76, 2, 25, 1, 10, 6, 10, 14, 2, 20, 5, 20, 15]);
  const response = await upload(mf, code);
  assert.equal(response.status, 201, await response.clone().text());
  const { id } = await response.json();
  const downloaded = await (await mf.dispatchFetch(`https://rooms.example/levels/${id}`)).json();
  assert.equal(downloaded.level.level_code, code);
  const spawnOnly = encode([1, 0, 0, 0, 10, 10, 82, 0, 1, 1, 76, 1, 50, 1, 5, 10, 15, 10]);
  assert.equal((await upload(mf, spawnOnly)).status, 201);
});

test("reject malformed checkpoint lines and check terrain at the actual line spawn", async t => {
  const { mf } = await runtime(t);
  const base = [1, 0, 0, 0, 10, 10, 82, 1, 1, 1, 20, 10];
  for (const trailer of [
    [76], [76, 0, 50], [76, 1, 101, 2, 20, 5, 20, 15],
    [76, 1, 50, 0, 20, 5, 20, 15], [76, 1, 50, 3, 20, 5, 20, 15],
    [76, 1, 50, 2, 100, 5, 20, 15], [76, 1, 50, 2, 20, 5, 20, 5],
    [76, 2, 50, 2, 20, 5, 20, 15, 2, 25, 5, 25, 15],
    [76, 1, 50, 2, 20, 5, 20, 15, 0],
  ]) {
    assert.equal((await upload(mf, encode([...base, ...trailer]))).status, 400, JSON.stringify(trailer));
  }
  const lineSpawn = (terrainY, percent) => encode([1, 1, 0, 0, 10, 10, 0, 5, terrainY, 15, terrainY,
    82, 0, 1, 1, 76, 1, percent, 1, 10, 2, 10, 18]);
  assert.equal((await upload(mf, lineSpawn(10, 0))).status, 201, "Line may cross terrain away from the spawn point");
  assert.equal((await upload(mf, lineSpawn(10, 50))).status, 400, "Midpoint spawn intersects terrain");
  assert.equal((await upload(mf, lineSpawn(2, 0))).status, 400, "Endpoint spawn intersects terrain even though the center is clear");
  assert.equal((await upload(mf, lineSpawn(10, 100))).status, 201, "Spawn can use endpoint B");
});

test("accept maximum terrain, orbs and all 129 checkpoint lines", async t => {
  const { mf } = await runtime(t);
  const bytes = [1, 0, 4, 128, 10, 2];
  for (let index = 0; index < 1024; index++) bytes.push(1, 1, 30, 3, 30, 2, 29);
  for (let index = 0; index < 128; index++) bytes.push(index % 100, 50 + Math.floor(index / 100));
  bytes.push(82, 128, 50, 1);
  for (let index = 0; index < 128; index++) bytes.push(index % 100, 60 + Math.floor(index / 100));
  bytes.push(76, 129, 50, 1, 10, 1, 10, 3);
  for (let index = 0; index < 128; index++) bytes.push(index + 2, index % 100, 60, index % 100, 62);
  const response = await upload(mf, encode(bytes));
  assert.equal(response.status, 201, await response.clone().text());
});
