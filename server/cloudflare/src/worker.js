import { DurableObject } from "cloudflare:workers";

const PING = '{"type":"ping"}';
const PONG = '{"type":"pong"}';
const SETUP_TIMEOUT = 30_000;
const PEER_TIMEOUT = 180_000;
const MAX_MESSAGE_BYTES = 32768;
const NOT_FOUND = "Room not found. Check the code or ask the host to create a new game.";

function text(body, status = 200) {
  return new Response(body + "\n", { status, headers: { "Content-Type": "text/plain", "Cache-Control": "no-store" } });
}

function randomCode() {
  // Rejection sampling keeps all eight-digit codes equally likely.
  let value;
  do { value = crypto.getRandomValues(new Uint32Array(1))[0]; } while (value >= 4_200_000_000);
  return String(value % 100_000_000).padStart(8, "0");
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") return text("ok");
    const match = /^\/rooms\/(\d{8})$/.exec(url.pathname);
    const creating = url.pathname === "/";
    if (!creating && !match) return text("not found", 404);
    if (request.method !== "GET" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return text("WebSocket required", 426);
    }
    const allowed = (env.ALLOWED_ORIGINS || "").split(",").map(value => value.trim()).filter(Boolean);
    if (!allowed.includes(request.headers.get("Origin"))) return text("Origin not allowed", 403);
    const key = request.headers.get("CF-Connecting-IP") || "local";
    if (!(await env.CONNECT_LIMITER.limit({ key })).success ||
        (creating && !(await env.CREATE_LIMITER.limit({ key })).success)) return text("Too many attempts. Try again in a minute.", 429);
    try {
      // A successful upgrade reserves the code atomically in that code's object.
      // No global room registry, always-on coordinator, or client-chosen host ID.
      for (let attempt = 0; attempt < 16; attempt++) {
        const code = creating ? randomCode() : match[1];
        const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
        const internal = new Request(`https://room.internal/${creating ? "host" : "join"}/${code}`, request);
        const response = await stub.fetch(internal);
        if (!creating || response.status !== 409) return response;
      }
      return text("Could not allocate a room. Try again.", 503);
    } catch {
      // Never return upstream bodies, tokens, or TURN credentials in errors/logs.
      return text("Room service unavailable. Try again.", 503);
    }
  },
};

export class GameRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.room = null;
    ctx.blockConcurrencyWhile(async () => { this.room = await ctx.storage.get("room") || null; });
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(PING, PONG));
  }

  peers() {
    return this.ctx.getWebSockets().filter(ws => {
      const peer = ws.deserializeAttachment();
      return ws.readyState === WebSocket.OPEN && !peer.left && peer.generation === this.room?.generation;
    });
  }

  host() { return this.peers().find(ws => ws.deserializeAttachment().peerId === 1); }

  send(ws, message) {
    if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(message));
  }

  error(ws, message) { this.send(ws, { type: "error", message }); }

  async fetch(request) {
    const [, role, code] = new URL(request.url).pathname.split("/");
    if (!/^\d{8}$/.test(code) || !["host", "join"].includes(role)) return text("not found", 404);
    const now = Date.now();
    if (role === "host") {
      if (this.room) return text("Code in use", 409);
      const ttl = Number(this.env.ROOM_TTL_SECONDS || 43200);
      if (!Number.isInteger(ttl) || ttl < 300 || ttl > 86400) return text("Invalid room TTL", 503);
      this.room = { code, generation: crypto.randomUUID(), phase: "pending", nextId: 2, expiresAt: now + ttl * 1000 };
      await this.ctx.storage.put("room", this.room);
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    // Return protocol errors after upgrading so Godot can display the reason.
    this.ctx.acceptWebSocket(server);
    const peer = { generation: this.room?.generation, peerId: 0, ready: false, left: false, connectedAt: now, rateStart: now, messages: 0 };
    server.serializeAttachment(peer);
    if (role === "join" && (!this.room || this.room.phase !== "open" || !this.host())) {
      this.error(server, NOT_FOUND);
      server.close(1000, "Room not found");
    } else if (role === "join" && this.peers().length > this.room.limit) {
      this.error(server, "This room is full.");
      server.close(1000, "Room full");
    } else {
      peer.peerId = role === "host" ? 1 : this.room.nextId++;
      server.serializeAttachment(peer);
      await this.ctx.storage.put("room", this.room);
      const alarm = await this.ctx.storage.getAlarm();
      if (!alarm || alarm > now + SETUP_TIMEOUT) await this.ctx.storage.setAlarm(now + SETUP_TIMEOUT);
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, raw) {
    const peer = ws.deserializeAttachment();
    if (!this.room || peer.left || peer.generation !== this.room.generation) return ws.close(1000, "Room ended");
    if (Date.now() - peer.rateStart >= 10000) { peer.rateStart = Date.now(); peer.messages = 0; }
    if (++peer.messages > 300 || typeof raw !== "string" || new TextEncoder().encode(raw).byteLength > MAX_MESSAGE_BYTES) {
      await this.leave(ws);
      return ws.close(1008, "Message limit");
    }
    ws.serializeAttachment(peer);
    let message;
    try { message = JSON.parse(raw); } catch { return this.error(ws, "Invalid JSON."); }
    if (!message || typeof message !== "object" || Array.isArray(message)) return this.error(ws, "Invalid message.");
    if (message.type === "create" || message.type === "join") {
      if (peer.ready || peer.busy) return this.error(ws, "Already joining a room.");
      const creating = message.type === "create";
      if ((peer.peerId === 1) !== creating) return this.error(ws, "Invalid room request.");
      if (creating) {
        if (typeof message.level_code !== "string" || !/^MG1-[A-Za-z0-9+/]+={0,2}$/.test(message.level_code) || message.level_code.length > 16384) {
          return this.error(ws, "Provide a valid MG1- level code.");
        }
        if (!Number.isInteger(message.max_players) || message.max_players < 2 || message.max_players > 8) return this.error(ws, "Player limit must be 2-8.");
      } else if (message.room !== this.room.code) return this.error(ws, NOT_FOUND);
      peer.busy = true;
      ws.serializeAttachment(peer);
      const generation = this.room.generation;
      try {
        // This external await can interleave with leave/close/join events.
        // The socket's reserved ID/slot survives hibernation; recheck afterwards.
        const iceServers = await iceServersFor(this.env);
        const current = ws.deserializeAttachment();
        if (ws.readyState !== WebSocket.OPEN || current.left || this.room?.generation !== generation) return;
        if (!creating && !this.host()) return;
        current.ready = true;
        current.busy = false;
        ws.serializeAttachment(current);
        if (creating) {
          this.room.phase = "open";
          this.room.levelCode = message.level_code;
          this.room.limit = message.max_players;
          await this.ctx.storage.put("room", this.room);
        }
        this.send(ws, { type: creating ? "created" : "joined", room: this.room.code, peer_id: peer.peerId, level_code: this.room.levelCode, ice_servers: iceServers });
        if (!creating) this.send(this.host(), { type: "peer_joined", peer_id: peer.peerId });
      } catch {
        this.error(ws, "Could not obtain connection credentials. Ask the host to check the room service configuration.");
        await this.leave(ws);
        ws.close(1000, "Credentials unavailable");
      }
      return;
    }
    if (!peer.ready) return this.error(ws, "Join a room first.");
    if (message.type === "signal") {
      const target = this.peers().find(other => other.deserializeAttachment().peerId === message.to && other.deserializeAttachment().ready);
      if (!target || target === ws || (peer.peerId !== 1 && message.to !== 1)) return this.error(ws, "Invalid signaling target.");
      const data = message.data;
      const sdp = data && data.kind === "sdp" && ["offer", "answer"].includes(data.type) && typeof data.sdp === "string" && data.sdp.length <= 24576;
      const ice = data && data.kind === "ice" && typeof data.media === "string" && Number.isInteger(data.index) && typeof data.candidate === "string" && data.candidate.length <= 4096;
      if (!sdp && !ice) return this.error(ws, "Invalid WebRTC signal.");
      this.send(target, { type: "signal", from: peer.peerId, data });
    } else if (message.type === "kick" && peer.peerId === 1 && message.peer_id !== 1) {
      const target = this.peers().find(other => other.deserializeAttachment().peerId === message.peer_id);
      if (target) { await this.leave(target); target.close(1000, "WebRTC disconnected"); }
    } else if (message.type === "leave") {
      await this.leave(ws);
      ws.close(1000, "Left room");
    } else this.error(ws, "Unknown request.");
  }

  async leave(ws) {
    const peer = ws.deserializeAttachment();
    if (peer.left || !this.room || peer.generation !== this.room.generation) return;
    peer.left = true;
    ws.serializeAttachment(peer);
    if (peer.peerId === 1) await this.shutdown("Host left");
    else if (peer.ready) this.send(this.host(), { type: "peer_left", peer_id: peer.peerId });
  }

  async shutdown(reason) {
    const peers = this.peers();
    this.room = null;
    for (const ws of peers) {
      const peer = ws.deserializeAttachment();
      peer.left = true;
      ws.serializeAttachment(peer);
      this.send(ws, { type: "room_closed" });
      ws.close(1000, reason);
    }
    // deleteAll does not delete an outstanding alarm.
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }

  async webSocketClose(ws, code) {
    await this.leave(ws);
    ws.close(code === 1005 || code === 1006 ? 1000 : code, "Disconnected");
  }

  async webSocketError(ws) {
    await this.leave(ws);
    ws.close(1011, "Connection error");
  }

  async alarm() {
    if (!this.room) return;
    const host = this.host();
    if (!host || Date.now() >= this.room.expiresAt) return this.shutdown("Room expired");
    let next = this.room.expiresAt;
    for (const ws of this.peers()) {
      const peer = ws.deserializeAttachment();
      const seen = this.ctx.getWebSocketAutoResponseTimestamp(ws)?.getTime() || peer.connectedAt;
      const deadline = peer.ready ? seen + PEER_TIMEOUT : peer.connectedAt + SETUP_TIMEOUT;
      if (Date.now() >= deadline) {
        await this.leave(ws);
        ws.close(1000, "Connection timed out");
        if (!this.room) return;
      } else next = Math.min(next, deadline);
    }
    await this.ctx.storage.setAlarm(next);
  }
}

export async function iceServersFor(env) {
  const key = env.CLOUDFLARE_TURN_KEY_ID;
  const token = env.CLOUDFLARE_TURN_API_TOKEN;
  if (!key && !token) return JSON.parse(env.ICE_SERVERS_JSON || '[{"urls":["stun:stun.cloudflare.com:3478"]}]');
  if (!key || !token) throw new Error("Both TURN secrets are required");
  const ttl = Number(env.TURN_TTL_SECONDS || 86400);
  if (!Number.isInteger(ttl) || ttl < 60 || ttl > 172800) throw new Error("Invalid TURN TTL");
  const response = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(key)}/credentials/generate-ice-servers`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ttl }),
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error("TURN credentials unavailable");
  const data = await response.json();
  if (!Array.isArray(data.iceServers) || !data.iceServers.length) throw new Error("Missing ICE servers");
  return data.iceServers;
}
