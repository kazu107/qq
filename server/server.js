"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { WebSocketServer, WebSocket } = require("ws");

const MAX_SIGNAL_BYTES = 64 * 1024;
const ROOM_CODE_PATTERN = /^[A-Z0-9]{6}$/;
const SIGNAL_TYPES = new Set(["offer", "answer", "candidate"]);
const MIN_TARGET_WINS = 1;
const MAX_TARGET_WINS = 20;
const DEFAULT_TARGET_WINS = 12;
const MIN_PLAYERS = 2;
const MAX_PLAYERS = 8;
const DEFAULT_PLAYERS = 2;
const MAX_SPECTATORS = 4;
const MIME_TYPES = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".wasm", "application/wasm"],
  [".pck", "application/octet-stream"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".json", "application/json; charset=utf-8"],
]);

function buildIceServers(env = process.env) {
  const servers = [
    { urls: ["stun:stun.l.google.com:19302", "stun:stun.cloudflare.com:3478"] },
  ];
  if (env.TURN_URL) {
    const turn = { urls: env.TURN_URL };
    if (env.TURN_USERNAME) turn.username = env.TURN_USERNAME;
    if (env.TURN_CREDENTIAL) turn.credential = env.TURN_CREDENTIAL;
    servers.push(turn);
  }
  return servers;
}

function createQqServer(options = {}) {
  const publicDir = path.resolve(options.publicDir || path.join(__dirname, "..", "build", "web"));
  const rooms = new Map();
  const clients = new Map();
  const iceServers = options.iceServers || buildIceServers(options.env || process.env);

  const server = http.createServer((request, response) => {
    setSecurityHeaders(response);
    if (request.url === "/health") {
      response.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
      response.end(JSON.stringify({ ok: true, rooms: rooms.size }));
      return;
    }
    serveStatic(publicDir, request, response);
  });

  const websocketServer = new WebSocketServer({ noServer: true, maxPayload: MAX_SIGNAL_BYTES });

  server.on("upgrade", (request, socket, head) => {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (pathname !== "/signal") {
      socket.destroy();
      return;
    }
    websocketServer.handleUpgrade(request, socket, head, (websocket) => {
      websocketServer.emit("connection", websocket, request);
    });
  });

  websocketServer.on("connection", (socket) => {
    clients.set(socket, { room: "", id: 0, role: "", participantRole: "", alive: true });
    socket.on("pong", () => {
      const client = clients.get(socket);
      if (client) client.alive = true;
    });
    socket.on("message", (data, isBinary) => {
      if (isBinary || data.length > MAX_SIGNAL_BYTES) {
        sendError(socket, "invalid_packet", "Only small JSON signaling messages are accepted.");
        return;
      }
      let message;
      try {
        message = JSON.parse(data.toString("utf8"));
      } catch {
        sendError(socket, "invalid_json", "The signaling message is not valid JSON.");
        return;
      }
      handleMessage(socket, message, rooms, clients, iceServers);
    });
    socket.on("close", () => removeClient(socket, rooms, clients));
    socket.on("error", () => removeClient(socket, rooms, clients));
  });

  const heartbeat = setInterval(() => {
    for (const [socket, client] of clients.entries()) {
      if (!client.alive) {
        socket.terminate();
        continue;
      }
      client.alive = false;
      socket.ping();
    }
  }, options.heartbeatMs || 25000);
  heartbeat.unref();

  server.on("close", () => {
    clearInterval(heartbeat);
    for (const socket of clients.keys()) socket.terminate();
    websocketServer.close();
  });

  return { server, rooms, clients };
}

function handleMessage(socket, message, rooms, clients, iceServers) {
  if (!message || typeof message !== "object" || Array.isArray(message)) {
    sendError(socket, "invalid_message", "The signaling message must be an object.");
    return;
  }
  const type = String(message.type || "");
  const client = clients.get(socket);
  if (!client) return;

  if (type === "list_rooms") {
    const protocolVersion = Number(message.protocolVersion);
    const contentHash = String(message.contentHash || "");
    if (!Number.isInteger(protocolVersion) || contentHash.length !== 64) {
      sendError(socket, "invalid_directory_request", "The room directory build identity is invalid.");
      return;
    }
    Object.assign(client, { role: "directory", protocolVersion, contentHash });
    sendRoomList(socket, rooms, clients, client);
    return;
  }

  if (type === "update_room") {
    if (client.role !== "host" || !client.room) {
      sendError(socket, "host_only", "Only the room host can update room settings.");
      return;
    }
    const room = rooms.get(client.room);
    const targetWins = sanitizeTargetWins(message.targetWins);
    const maxPlayers = sanitizeMaxPlayers(message.maxPlayers);
    if (!room || targetWins === null || maxPlayers === null || countParticipants(room, clients, "player") > maxPlayers) {
      sendError(socket, "invalid_room_settings", "The room settings are invalid.");
      return;
    }
    room.targetWins = targetWins;
    room.maxPlayers = maxPlayers;
    broadcastRoomLists(rooms, clients);
    return;
  }

  if (type === "host" || type === "join") {
    if (client.room) {
      sendError(socket, "already_joined", "This connection already belongs to a room.");
      return;
    }
    const roomCode = String(message.room || "").trim().toUpperCase();
    const protocolVersion = Number(message.protocolVersion);
    const contentHash = String(message.contentHash || "");
    if (!ROOM_CODE_PATTERN.test(roomCode) || !Number.isInteger(protocolVersion) || contentHash.length !== 64) {
      sendError(socket, "invalid_room_request", "The room code or build identity is invalid.");
      return;
    }
    if (type === "host") {
      if (rooms.has(roomCode)) {
        sendError(socket, "room_exists", "That room code is already in use. Try another code.");
        return;
      }
      const room = {
        code: roomCode,
        protocolVersion,
        contentHash,
        hostName: sanitizeDisplayName(message.name),
        targetWins: sanitizeTargetWins(message.targetWins) ?? DEFAULT_TARGET_WINS,
        maxPlayers: sanitizeMaxPlayers(message.maxPlayers) ?? DEFAULT_PLAYERS,
        peers: new Map([[1, socket]]),
      };
      rooms.set(roomCode, room);
      Object.assign(client, { room: roomCode, id: 1, role: "host", participantRole: "player" });
      send(socket, { type: "assigned", id: 1, role: "host", participantRole: "player", room: roomCode, peers: [], iceServers });
      broadcastRoomLists(rooms, clients);
      return;
    }
    const room = rooms.get(roomCode);
    if (!room) {
      sendError(socket, "room_not_found", "No Web multiplayer room was found for that code.");
      return;
    }
    if (room.protocolVersion !== protocolVersion || room.contentHash !== contentHash) {
      sendError(socket, "build_mismatch", "Both players must use the same game build.");
      return;
    }
    const participantRole = message.spectator === true ? "spectator" : "player";
    const roleCount = countParticipants(room, clients, participantRole);
    const roleLimit = participantRole === "spectator" ? MAX_SPECTATORS : room.maxPlayers;
    if (roleCount >= roleLimit) {
      sendError(socket, participantRole === "spectator" ? "spectator_full" : "room_full", "That room has no open slot for the selected role.");
      return;
    }
    const guestId = nextPeerId(room);
    const existingPeerIds = [...room.peers.keys()].sort((left, right) => left - right);
    room.peers.set(guestId, socket);
    Object.assign(client, { room: roomCode, id: guestId, role: "guest", participantRole });
    send(socket, { type: "assigned", id: guestId, role: "guest", participantRole, room: roomCode, peers: existingPeerIds, iceServers });
    for (const peerId of existingPeerIds) {
      send(room.peers.get(peerId), { type: "peer_joined", id: guestId, participantRole });
    }
    broadcastRoomLists(rooms, clients);
    return;
  }

  if (!client.room || !SIGNAL_TYPES.has(type)) {
    sendError(socket, "invalid_state", "Join a room before sending peer signaling messages.");
    return;
  }
  const room = rooms.get(client.room);
  const targetId = Number(message.to);
  const target = room && room.peers.get(targetId);
  if (!room || !Number.isInteger(targetId) || targetId === client.id || !target) {
    sendError(socket, "peer_not_found", "The requested peer is not connected to this room.");
    return;
  }
  const forwarded = { type, from: client.id };
  if (type === "offer" || type === "answer") {
    const sdp = String(message.sdp || "");
    if (!sdp || sdp.length > MAX_SIGNAL_BYTES - 1024) {
      sendError(socket, "invalid_sdp", "The WebRTC session description is invalid.");
      return;
    }
    forwarded.sdp = sdp;
  } else {
    const candidate = String(message.candidate || "");
    if (!candidate || candidate.length > 8192) {
      sendError(socket, "invalid_candidate", "The ICE candidate is invalid.");
      return;
    }
    forwarded.mid = String(message.mid || "").slice(0, 128);
    forwarded.index = Number.isInteger(Number(message.index)) ? Number(message.index) : 0;
    forwarded.candidate = candidate;
  }
  send(target, forwarded);
}

function removeClient(socket, rooms, clients) {
  const client = clients.get(socket);
  if (!client) return;
  clients.delete(socket);
  if (!client.room) return;
  const room = rooms.get(client.room);
  if (!room) return;
  room.peers.delete(client.id);
  if (client.id === 1 || room.peers.size === 0) {
    for (const peerSocket of room.peers.values()) {
      send(peerSocket, { type: "peer_left", id: client.id });
      peerSocket.close(1001, "host_left");
    }
    rooms.delete(client.room);
    broadcastRoomLists(rooms, clients);
    return;
  }
  for (const peerSocket of room.peers.values()) {
    send(peerSocket, { type: "peer_left", id: client.id });
  }
  broadcastRoomLists(rooms, clients);
}

function sanitizeDisplayName(value) {
  const name = String(value || "").trim().slice(0, 24);
  return name || "Web Host";
}

function sanitizeTargetWins(value) {
  const targetWins = Number(value);
  if (!Number.isInteger(targetWins) || targetWins < MIN_TARGET_WINS || targetWins > MAX_TARGET_WINS) return null;
  return targetWins;
}

function sanitizeMaxPlayers(value) {
  const maxPlayers = Number(value);
  if (!Number.isInteger(maxPlayers) || maxPlayers < MIN_PLAYERS || maxPlayers > MAX_PLAYERS || maxPlayers % 2 !== 0) return null;
  return maxPlayers;
}

function countParticipants(room, clients, participantRole) {
  let count = 0;
  for (const socket of room.peers.values()) {
    if (clients.get(socket)?.participantRole === participantRole) count += 1;
  }
  return count;
}

function nextPeerId(room) {
  let peerId = 2;
  while (room.peers.has(peerId)) peerId += 1;
  return peerId;
}

function buildRoomList(rooms, clients, client) {
  const entries = [];
  for (const room of rooms.values()) {
    if (room.protocolVersion !== client.protocolVersion || room.contentHash !== client.contentHash) continue;
    entries.push({
      code: room.code,
      hostName: room.hostName,
      players: countParticipants(room, clients, "player"),
      maxPlayers: room.maxPlayers,
      spectators: countParticipants(room, clients, "spectator"),
      maxSpectators: MAX_SPECTATORS,
      targetWins: room.targetWins,
      joinable: countParticipants(room, clients, "player") < room.maxPlayers,
      spectatorJoinable: countParticipants(room, clients, "spectator") < MAX_SPECTATORS,
    });
  }
  entries.sort((left, right) => left.code.localeCompare(right.code));
  return entries;
}

function sendRoomList(socket, rooms, clients, client) {
  send(socket, { type: "room_list", rooms: buildRoomList(rooms, clients, client) });
}

function broadcastRoomLists(rooms, clients) {
  for (const [socket, client] of clients.entries()) {
    if (client.role === "directory") sendRoomList(socket, rooms, clients, client);
  }
}

function serveStatic(publicDir, request, response) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    response.writeHead(405, { Allow: "GET, HEAD" });
    response.end();
    return;
  }
  const requestPath = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
  const relativePath = requestPath === "/" ? "index.html" : requestPath.replace(/^\/+/, "");
  const filePath = path.resolve(publicDir, relativePath);
  if (!filePath.startsWith(`${publicDir}${path.sep}`) && filePath !== path.join(publicDir, "index.html")) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }
  fs.stat(filePath, (statError, stats) => {
    if (statError || !stats.isFile()) {
      response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      response.end("Web build not found. Run tools/build_web.ps1 before deploying.");
      return;
    }
    const extension = path.extname(filePath).toLowerCase();
    const etag = `"${stats.size.toString(16)}-${Math.trunc(stats.mtimeMs).toString(16)}"`;
    const headers = {
      "Content-Type": MIME_TYPES.get(extension) || "application/octet-stream",
      "Cache-Control": "no-cache",
      ETag: etag,
    };
    if (request.headers["if-none-match"] === etag) {
      response.writeHead(304, headers);
      response.end();
      return;
    }
    response.writeHead(200, { ...headers, "Content-Length": stats.size });
    if (request.method === "HEAD") {
      response.end();
      return;
    }
    fs.createReadStream(filePath).pipe(response);
  });
}

function setSecurityHeaders(response) {
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "same-origin");
  response.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
}

function send(socket, payload) {
  if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(payload));
}

function sendError(socket, code, message) {
  send(socket, { type: "error", code, message });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 8060);
  const { server } = createQqServer();
  server.listen(port, "0.0.0.0", () => {
    process.stdout.write(`qq Web server listening on ${port}\n`);
  });
}

module.exports = { buildIceServers, createQqServer };
