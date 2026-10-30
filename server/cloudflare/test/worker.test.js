import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";

const ORIGIN = "https://wizkinews.com";
const source = readFileSync(new URL("../src/worker.js", import.meta.url), "utf8");
// Inspection and clock controls exist only in this local test entry point.
const harness = `
  import { GameRoom } from './worker.js';
  import worker from './worker.js';
  export default {
    async fetch(request, env) {
      const match = /^\\/test\\/(snapshot|expire|expireHost)\\/(\\d{8})$/.exec(new URL(request.url).pathname);
      if (!match) return worker.fetch(request, env);
      const stub = env.ROOMS.get(env.ROOMS.idFromName(match[2]));
      return Response.json(await stub[match[1]]() ?? null);
    }
  };
  export class TestRoom extends GameRoom {
    constructor(ctx, env) { super(ctx, env); this.activationId = crypto.randomUUID(); }
    async snapshot() {
      return { activationId: this.activationId, room: this.room, stored: await this.ctx.storage.get('room') ?? null,
        peers: this.peers().map(ws => ws.deserializeAttachment()), alarm: await this.ctx.storage.getAlarm() };
    }
    async expire() { this.room.expiresAt = Date.now() - 1; await this.alarm(); }
    async expireHost() {
      const ws = this.host(); const peer = ws.deserializeAttachment();
      peer.connectedAt = 0; ws.serializeAttachment(peer); await this.alarm();
    }
  }
`;

function runtime(t, options = {}) {
  const mf = new Miniflare(convertV4MiniflareOptions({
    workers: [{
      name: "test", compatibilityDate: "2026-10-27",
      modules: [
        { type: "ESModule", path: "entry.js", contents: harness },
        { type: "ESModule", path: "worker.js", contents: source },
      ],
      bindings: { ALLOWED_ORIGINS: ORIGIN, ...options.bindings },
      durableObjects: { ROOMS: { className: "TestRoom", useSQLite: true } },
      ratelimits: {
        CREATE_LIMITER: { namespace_id: "271001", simple: { limit: options.createLimit || 1000, period: 60 } },
        CONNECT_LIMITER: { namespace_id: "271002", simple: { limit: 1000, period: 60 } },
      },
      outboundService: options.outboundService || (() => { throw new Error("Unexpected external network request"); }),
    }],
  }));
  t.after(() => mf.dispose());
  return mf;
}

async function client(mf, path = "/") {
  const response = await mf.dispatchFetch("https://rooms.example" + path, { headers: { Upgrade: "websocket", Origin: ORIGIN } });
  assert.equal(response.status, 101);
  const ws = response.webSocket;
  const inbox = [];
  ws.addEventListener("message", event => inbox.push(JSON.parse(event.data)));
  ws.accept();
  ws.sendJSON = message => ws.send(JSON.stringify(message));
  ws.next = async type => {
    const deadline = Date.now() + 3000;
    while (Date.now() < deadline) {
      const index = inbox.findIndex(message => message.type === type);
      if (index !== -1) return inbox.splice(index, 1)[0];
      await new Promise(resolve => setTimeout(resolve, 5));
    }
    throw new Error(`Missing ${type}: ${JSON.stringify(inbox)}`);
  };
  return ws;
}

async function host(mf, limit = 3) {
  const ws = await client(mf);
  ws.sendJSON({ type: "create", level_code: "MG1-AAAA", max_players: limit });
  const created = await ws.next("created");
  assert.match(created.room, /^\d{8}$/);
  assert.equal(created.peer_id, 1);
  return { ws, room: created.room, created };
}

async function join(mf, room) {
  const ws = await client(mf, "/rooms/" + room);
  ws.sendJSON({ type: "join", room });
  const joined = await ws.next("joined");
  return { ws, id: joined.peer_id, joined };
}

async function object(mf, room) {
  // HTTP inspection avoids a Node-side RPC stub retaining active object references
  // while the runtime's eviction control is trying to hibernate it.
  const call = async method => (await mf.dispatchFetch(`https://rooms.example/test/${method}/${room}`)).json();
  return { snapshot: () => call("snapshot"), expire: () => call("expire"), expireHost: () => call("expireHost") };
}

test("independent public rooms, capacity, authority, hibernation, departures and storage cleanup", async t => {
  const mf = runtime(t);
  const first = await host(mf);
  const second = await host(mf);
  assert.notEqual(first.room, second.room);
  const guest = await join(mf, first.room);
  assert.equal(guest.joined.level_code, "MG1-AAAA");
  assert.equal((await first.ws.next("peer_joined")).peer_id, guest.id);
  const third = await join(mf, first.room);
  await first.ws.next("peer_joined");
  const full = await client(mf, "/rooms/" + first.room);
  assert.match((await full.next("error")).message, /full/);
  const unknown = await client(mf, "/rooms/00000000");
  assert.match((await unknown.next("error")).message, /not found/);

  const stub = await object(mf, first.room);
  // Touch it immediately before explicit eviction; it may already have naturally
  // hibernated while the preceding assertions were running.
  const before = await stub.snapshot();
  assert.equal(before.stored.levelCode, "MG1-AAAA");
  try {
    await mf.unsafeEvictDurableObject("test", "TestRoom", { name: first.room, webSockets: "hibernate" });
  } catch (error) {
    // workerd may have hibernated it between the inspection response and this
    // call. The activation-ID assertion below still requires a cold restart.
    if (!error.message.includes("it is not currently running")) throw error;
  }
  // A heartbeat still works while the object is evicted.
  guest.ws.send('{"type":"ping"}');
  await guest.ws.next("pong");
  guest.ws.sendJSON({ type: "signal", to: 1, from: 999, data: { kind: "sdp", type: "answer", sdp: "test" } });
  assert.equal((await first.ws.next("signal")).from, guest.id);
  assert.notEqual((await stub.snapshot()).activationId, before.activationId);
  guest.ws.sendJSON({ type: "signal", to: third.id, data: { kind: "sdp", type: "offer", sdp: "test" } });
  assert.match((await guest.ws.next("error")).message, /target/);
  first.ws.sendJSON({ type: "signal", to: third.id, data: { kind: "ice", media: "0", index: 0, candidate: "test" } });
  assert.equal((await third.ws.next("signal")).from, 1);
  assert.equal((await stub.snapshot()).stored.levelCode, "MG1-AAAA");

  guest.ws.close();
  assert.equal((await first.ws.next("peer_left")).peer_id, guest.id);
  const replacement = await join(mf, first.room);
  assert.ok(replacement.id > third.id);
  await first.ws.next("peer_joined");
  first.ws.close();
  await third.ws.next("room_closed");
  await replacement.ws.next("room_closed");
  const ended = await stub.snapshot();
  assert.equal(ended.room, null);
  assert.equal(ended.stored, null);
  assert.equal(ended.alarm, null);
  assert.equal((await (await object(mf, second.room)).snapshot()).room.code, second.room);
  const gone = await client(mf, "/rooms/" + first.room);
  assert.match((await gone.next("error")).message, /not found/);
});

test("TURN credentials stay server-side and concurrent joins reserve capacity", async t => {
  let calls = 0;
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const mf = runtime(t, {
    bindings: { CLOUDFLARE_TURN_KEY_ID: "fake-key", CLOUDFLARE_TURN_API_TOKEN: "fake-token" },
    outboundService: async request => {
      assert.match(request.url, /fake-key\/credentials\/generate-ice-servers$/);
      assert.equal(request.headers.get("Authorization"), "Bearer fake-token");
      assert.equal((await request.json()).ttl, 86400);
      if (++calls === 2) await gate;
      return Response.json({ iceServers: [{ urls: ["turn:example.test:3478"], username: "temporary", credential: "temporary" }] });
    },
  });
  const first = await host(mf, 2);
  assert.equal(first.created.ice_servers[0].username, "temporary");
  assert.equal(JSON.stringify(first.created).includes("fake-token"), false);
  const guest = await client(mf, "/rooms/" + first.room);
  guest.sendJSON({ type: "join", room: first.room });
  const excess = await client(mf, "/rooms/" + first.room);
  assert.match((await excess.next("error")).message, /full/);
  release();
  await guest.next("joined");
  assert.equal(calls, 2);
});

test("credential failure releases a slot and host exit during credential fetch cannot revive a room", async t => {
  let calls = 0;
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const mf = runtime(t, {
    bindings: { CLOUDFLARE_TURN_KEY_ID: "fake-key", CLOUDFLARE_TURN_API_TOKEN: "fake-token" },
    outboundService: async () => {
      if (++calls === 2) return new Response("failure", { status: 503 });
      if (calls === 3) await gate;
      return Response.json({ iceServers: [{ urls: ["stun:example.test"] }] });
    },
  });
  const first = await host(mf, 2);
  const failed = await client(mf, "/rooms/" + first.room);
  failed.sendJSON({ type: "join", room: first.room });
  assert.match((await failed.next("error")).message, /credentials/);
  const waiting = await client(mf, "/rooms/" + first.room);
  waiting.sendJSON({ type: "join", room: first.room });
  first.ws.close();
  await waiting.next("room_closed");
  release();
  assert.equal((await (await object(mf, first.room)).snapshot()).stored, null);
});

test("origins, anonymous creation limits, malformed signaling, stale hosts and room expiration", async t => {
  const mf = runtime(t, { createLimit: 3 });
  assert.equal((await mf.dispatchFetch("https://rooms.example/health")).status, 200);
  assert.equal((await mf.dispatchFetch("https://rooms.example/", { headers: { Upgrade: "websocket", Origin: "https://evil.example" } })).status, 403);
  const first = await host(mf);
  first.ws.sendJSON({ type: "signal", to: 1, data: {} });
  assert.match((await first.ws.next("error")).message, /target/);
  const guest = await join(mf, first.room);
  await first.ws.next("peer_joined");
  guest.ws.sendJSON({ type: "signal", to: 1, data: { kind: "sdp", type: "answer", sdp: 123 } });
  assert.match((await guest.ws.next("error")).message, /Invalid WebRTC/);
  await (await object(mf, first.room)).expire();
  await first.ws.next("room_closed");
  await guest.ws.next("room_closed");
  const second = await host(mf);
  await (await object(mf, second.room)).expireHost();
  const snapshot = await (await object(mf, second.room)).snapshot();
  assert.equal(snapshot.stored, null);
  await host(mf);
  assert.equal((await mf.dispatchFetch("https://rooms.example/", { headers: { Upgrade: "websocket", Origin: ORIGIN } })).status, 429);
});
