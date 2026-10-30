"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { once } = require("node:events");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { WebSocket } = require("ws");
const { createSignalingServer, cloudflareIceServers, loadConfiguration } = require("./signaling");

test("optional env files load settings and preserve deployed environment overrides", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "multi-grappler-env-"));
  const previous = { ...process.env };
  t.after(() => { process.env = previous; fs.rmSync(directory, { recursive: true, force: true }); });
  const file = path.join(directory, ".env");
  fs.writeFileSync(file, 'MULTI_GRAPPLER_TEST_FILE="file-value"\nMULTI_GRAPPLER_TEST_OVERRIDE=file-value\n');
  process.env.MULTI_GRAPPLER_TEST_OVERRIDE = "environment-value";
  loadConfiguration(file);
  assert.equal(process.env.MULTI_GRAPPLER_TEST_FILE, "file-value");
  assert.equal(process.env.MULTI_GRAPPLER_TEST_OVERRIDE, "environment-value");
  assert.doesNotThrow(() => loadConfiguration(path.join(directory, "missing.env")));
});

async function client(url) {
  const ws = new WebSocket(url);
  ws.inbox = [];
  ws.on("message", raw => ws.inbox.push(JSON.parse(raw)));
  await once(ws, "open");
  ws.sendJSON = message => ws.send(JSON.stringify(message));
  ws.next = async type => {
    const until = Date.now() + 2000;
    while (Date.now() < until) {
      const index = ws.inbox.findIndex(message => message.type === type);
      if (index !== -1) return ws.inbox.splice(index, 1)[0];
      await new Promise(resolve => setTimeout(resolve, 5));
    }
    throw new Error(`Missing ${type}: ${JSON.stringify(ws.inbox)}`);
  };
  return ws;
}

test("room codes, capacity, signaling isolation, guest departure, and host teardown", async t => {
  let code = 123456;
  const app = createSignalingServer({ getIceServers: async () => [], randomCode: () => code++ });
  await new Promise(resolve => app.server.listen(0, "127.0.0.1", resolve));
  t.after(() => app.close());
  const url = `ws://127.0.0.1:${app.server.address().port}`;
  const host = await client(url);
  host.sendJSON({ type: "create", level_code: "MG1-AAAA", max_players: 3 });
  const created = await host.next("created");
  assert.equal(created.room, "00123456");
  assert.equal(created.peer_id, 1);
  const wrong = await client(url);
  wrong.sendJSON({ type: "join", room: "00000000" });
  assert.match((await wrong.next("error")).message, /not found/);
  const guest = await client(url);
  guest.sendJSON({ type: "ping" });
  await guest.next("pong");
  guest.sendJSON({ type: "join", room: created.room });
  const joined = await guest.next("joined");
  assert.equal(joined.level_code, "MG1-AAAA");
  assert.equal((await host.next("peer_joined")).peer_id, joined.peer_id);
  const second = await client(url);
  second.sendJSON({ type: "join", room: created.room });
  const joined2 = await second.next("joined");
  await host.next("peer_joined");
  wrong.sendJSON({ type: "join", room: created.room });
  assert.match((await wrong.next("error")).message, /full/);
  guest.sendJSON({ type: "signal", to: 1, from: 999, data: { kind: "sdp", type: "answer", sdp: "test" } });
  assert.equal((await host.next("signal")).from, joined.peer_id);
  guest.sendJSON({ type: "signal", to: joined2.peer_id, data: { kind: "sdp", type: "offer", sdp: "test" } });
  assert.match((await guest.next("error")).message, /target/);
  const otherHost = await client(url);
  otherHost.sendJSON({ type: "create", level_code: "MG1-AAAA", max_players: 2 });
  assert.notEqual((await otherHost.next("created")).room, created.room);
  guest.close();
  assert.equal((await host.next("peer_left")).peer_id, joined.peer_id);
  wrong.sendJSON({ type: "join", room: created.room });
  await wrong.next("joined");
  host.terminate();
  await second.next("room_closed");
  await wrong.next("room_closed");
  assert.equal(app.rooms.has(created.room), false);
  assert.equal(app.rooms.size, 1);
});

test("credential failures release reserved slots", async t => {
  let calls = 0;
  const app = createSignalingServer({ getIceServers: async () => { if (++calls === 2) throw new Error("TURN down"); return []; } });
  await new Promise(resolve => app.server.listen(0, "127.0.0.1", resolve));
  t.after(() => app.close());
  const url = `ws://127.0.0.1:${app.server.address().port}`;
  const host = await client(url);
  host.sendJSON({ type: "create", level_code: "MG1-AAAA", max_players: 2 });
  const { room } = await host.next("created");
  const guest = await client(url);
  guest.sendJSON({ type: "join", room });
  assert.match((await guest.next("error")).message, /credentials/);
  assert.equal(app.rooms.get(room).peers.size, 1);
  guest.sendJSON({ type: "join", room });
  await guest.next("joined");
  assert.equal(app.rooms.get(room).peers.size, 2);
});

test("Cloudflare generates expiring credentials on the backend", async t => {
  const oldFetch = global.fetch;
  const oldEnv = { ...process.env };
  t.after(() => { global.fetch = oldFetch; process.env = oldEnv; });
  process.env.CLOUDFLARE_TURN_KEY_ID = "test-key";
  process.env.CLOUDFLARE_TURN_API_TOKEN = "test-token";
  process.env.TURN_TTL_SECONDS = "3600";
  global.fetch = async (url, options) => {
    assert.match(url, /test-key\/credentials\/generate-ice-servers$/);
    assert.equal(options.headers.Authorization, "Bearer test-token");
    assert.equal(JSON.parse(options.body).ttl, 3600);
    return { ok: true, json: async () => ({ iceServers: [{ urls: ["turn:example.test"], username: "temporary", credential: "temporary" }] }) };
  };
  const servers = await cloudflareIceServers();
  assert.equal(servers[0].username, "temporary");
  assert.equal(JSON.stringify(servers).includes("test-token"), false);
});
