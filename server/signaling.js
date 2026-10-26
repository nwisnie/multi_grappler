"use strict";

const http = require("node:http");
const { randomInt } = require("node:crypto");
const { WebSocketServer, WebSocket } = require("ws");

// No level execution and no gameplay packets on this service.
function createSignalingServer(options = {}) {
  const rooms = new Map();
  const origins = options.allowedOrigins || (process.env.ALLOWED_ORIGINS || "").split(",").filter(Boolean);
  const getIceServers = options.getIceServers || cloudflareIceServers;
  const server = http.createServer((req, res) => {
    res.writeHead(req.url === "/health" ? 200 : 404, { "Content-Type": "text/plain" });
    res.end(req.url === "/health" ? "ok\n" : "not found\n");
  });
  const wss = new WebSocketServer({
    server,
    maxPayload: 32768,
    verifyClient: ({ origin }) => !origins.length || origins.includes(origin),
  });
  const send = (ws, message) => {
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(message));
  };
  const error = (ws, message) => send(ws, { type: "error", message });

  function leave(ws) {
    const room = ws.room;
    ws.room = null;
    if (!room) return;
    room.peers.delete(ws.peerId);
    if (ws.peerId === 1) {
      rooms.delete(room.code);
      for (const peer of room.peers.values()) {
        peer.room = null;
        send(peer, { type: "room_closed" });
        peer.close(1000, "Host left");
      }
      room.peers.clear();
    } else {
      send(room.peers.get(1), { type: "peer_left", peer_id: ws.peerId });
    }
  }

  wss.on("connection", (ws) => {
    ws.alive = true;
    ws.busy = false;
    ws.rateStart = Date.now();
    ws.messages = 0;
    ws.on("pong", () => { ws.alive = true; });
    ws.on("error", () => {});
    ws.on("close", () => leave(ws));
    ws.on("message", async (raw, binary) => {
      if (Date.now() - ws.rateStart > 10000) {
        ws.rateStart = Date.now();
        ws.messages = 0;
      }
      if (++ws.messages > 300) return ws.close(1008, "Rate limit");
      let message;
      try { message = JSON.parse(raw.toString()); } catch { return error(ws, "Invalid JSON."); }
      if (binary || !message || typeof message !== "object" || Array.isArray(message)) return error(ws, "Invalid message.");
      if (message.type === "create" || message.type === "join") {
        if (ws.room || ws.busy) return error(ws, "Already joining a room.");
        ws.busy = true;
        try {
          let room;
          if (message.type === "create") {
            if (typeof message.level_code !== "string" || !/^MG1-[A-Za-z0-9+/]+={0,2}$/.test(message.level_code) || message.level_code.length > 16384) {
              return error(ws, "Provide a valid MG1- level code.");
            }
            if (!Number.isInteger(message.max_players) || message.max_players < 2 || message.max_players > 8) return error(ws, "Player limit must be 2-8.");
            if (rooms.size >= (options.maxRooms || 1000)) return error(ws, "Room service is full. Try again later.");
            const iceServers = await getIceServers();
            if (ws.readyState !== WebSocket.OPEN) return;
            let code;
            do { code = (options.randomCode ? options.randomCode() : randomInt(100000000)).toString().padStart(8, "0"); } while (rooms.has(code));
            room = { code, levelCode: message.level_code, limit: message.max_players, nextId: 2, peers: new Map() };
            ws.peerId = 1;
            ws.room = room;
            room.peers.set(1, ws);
            rooms.set(code, room);
            send(ws, { type: "created", room: code, peer_id: 1, level_code: room.levelCode, ice_servers: iceServers });
          } else {
            if (typeof message.room !== "string" || !/^\d{8}$/.test(message.room)) return error(ws, "Use exactly 8 digits.");
            room = rooms.get(message.room);
            if (!room) return error(ws, "Room not found. Check the code or ask the host to create a new game.");
            if (room.peers.size >= room.limit) return error(ws, "This room is full.");
            // Reserve a slot before awaiting the credential service.
            ws.peerId = room.nextId++;
            ws.room = room;
            room.peers.set(ws.peerId, ws);
            const iceServers = await getIceServers();
            if (ws.readyState !== WebSocket.OPEN || ws.room !== room) return;
            send(ws, { type: "joined", room: room.code, peer_id: ws.peerId, level_code: room.levelCode, ice_servers: iceServers });
            send(room.peers.get(1), { type: "peer_joined", peer_id: ws.peerId });
          }
        } catch {
          leave(ws);
          error(ws, "Could not obtain connection credentials. Ask the host to check the room service configuration.");
        } finally {
          ws.busy = false;
        }
        return;
      }
      const room = ws.room;
      if (!room) return error(ws, "Join a room first.");
      if (message.type === "signal") {
        const target = room.peers.get(message.to);
        // Star topology: guests only negotiate with the host. Sender IDs are never trusted.
        if (!target || target === ws || (ws.peerId !== 1 && message.to !== 1)) return error(ws, "Invalid signaling target.");
        const data = message.data;
        const sdp = data && data.kind === "sdp" && ["offer", "answer"].includes(data.type) && typeof data.sdp === "string" && data.sdp.length <= 24576;
        const ice = data && data.kind === "ice" && typeof data.media === "string" && Number.isInteger(data.index) && typeof data.candidate === "string" && data.candidate.length <= 4096;
        if (!sdp && !ice) return error(ws, "Invalid WebRTC signal.");
        send(target, { type: "signal", from: ws.peerId, data });
      } else if (message.type === "kick" && ws.peerId === 1 && message.peer_id !== 1) {
        const target = room.peers.get(message.peer_id);
        if (target) {
          leave(target);
          target.close(1000, "WebRTC disconnected");
        }
      } else if (message.type === "leave") {
        leave(ws);
        ws.close(1000, "Left room");
      } else error(ws, "Unknown request.");
    });
  });

  // A killed browser/machine must also release its room, even without a close frame.
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) { leave(ws); ws.terminate(); continue; }
      ws.alive = false;
      ws.ping();
    }
  }, options.heartbeatMs || 10000);
  heartbeat.unref();
  return {
    server, rooms,
    close: async () => {
      clearInterval(heartbeat);
      for (const ws of wss.clients) { leave(ws); ws.terminate(); }
      await new Promise(resolve => wss.close(resolve));
      await new Promise(resolve => server.close(resolve));
    },
  };
}

async function cloudflareIceServers() {
  const key = process.env.CLOUDFLARE_TURN_KEY_ID;
  const token = process.env.CLOUDFLARE_TURN_API_TOKEN;
  if (!key && !token) {
    return JSON.parse(process.env.ICE_SERVERS_JSON || '[{"urls":["stun:stun.cloudflare.com:3478"]}]');
  }
  if (!key || !token) throw new Error("Both Cloudflare TURN settings are required");
  const ttl = Number(process.env.TURN_TTL_SECONDS || 86400);
  if (!Number.isInteger(ttl) || ttl < 60 || ttl > 172800) throw new Error("Invalid TURN TTL");
  const response = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(key)}/credentials/generate-ice-servers`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ttl }),
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error("TURN credential generation failed");
  const data = await response.json();
  if (!Array.isArray(data.iceServers) || !data.iceServers.length) throw new Error("Missing ICE servers");
  return data.iceServers;
}

if (require.main === module) {
  const app = createSignalingServer();
  const port = Number(process.env.PORT || 9080);
  app.server.listen(port, process.env.HOST || "0.0.0.0", () => console.log(`Room service listening on ${port}`));
  for (const signal of ["SIGINT", "SIGTERM"]) process.once(signal, async () => { await app.close(); process.exit(0); });
}

module.exports = { createSignalingServer, cloudflareIceServers };
