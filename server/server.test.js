"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { once } = require("node:events");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { WebSocket } = require("ws");
const { buildIceServers, createQqServer } = require("./server");

const BUILD_HASH = "a".repeat(64);

async function startServer(options = {}) {
  const app = createQqServer({ heartbeatMs: 1000, ...options });
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  const address = app.server.address();
  return { ...app, port: address.port };
}

async function connect(port) {
  const socket = new WebSocket(`ws://127.0.0.1:${port}/signal`);
  await once(socket, "open");
  return socket;
}

function receive(socket) {
  return new Promise((resolve, reject) => {
    const onMessage = (data) => {
      cleanup();
      resolve(JSON.parse(data.toString("utf8")));
    };
    const onError = (error) => {
      cleanup();
      reject(error);
    };
    const cleanup = () => {
      socket.off("message", onMessage);
      socket.off("error", onError);
    };
    socket.on("message", onMessage);
    socket.on("error", onError);
  });
}

function send(socket, payload) {
  socket.send(JSON.stringify(payload));
}

async function stop(app, sockets = []) {
  for (const socket of sockets) socket.terminate();
  await new Promise((resolve) => app.server.close(resolve));
}

test("health endpoint reports readiness", async () => {
  const app = await startServer();
  const response = await fetch(`http://127.0.0.1:${app.port}/health`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, rooms: 0 });
  await stop(app);
});

test("static Web builds revalidate cached files after a deploy", async () => {
  const publicDir = fs.mkdtempSync(path.join(os.tmpdir(), "qq-web-"));
  fs.writeFileSync(path.join(publicDir, "index.html"), "<main>qq</main>");
  const app = await startServer({ publicDir });
  try {
    const first = await fetch(`http://127.0.0.1:${app.port}/`);
    const etag = first.headers.get("etag");
    assert.equal(first.status, 200);
    assert.equal(first.headers.get("cache-control"), "no-cache");
    assert.ok(etag);
    assert.equal(await first.text(), "<main>qq</main>");

    const second = await fetch(`http://127.0.0.1:${app.port}/`, {
      headers: { "If-None-Match": etag },
    });
    assert.equal(second.status, 304);
  } finally {
    await stop(app);
    fs.rmSync(publicDir, { recursive: true, force: true });
  }
});

test("host and guest receive stable peer ids and relay signaling", async () => {
  const app = await startServer();
  const host = await connect(app.port);
  const guest = await connect(app.port);
  send(host, { type: "host", room: "ABC123", protocolVersion: 6, contentHash: BUILD_HASH });
  const hostAssigned = await receive(host);
  assert.equal(hostAssigned.id, 1);
  assert.equal(hostAssigned.role, "host");
  assert.equal(hostAssigned.participantRole, "player");

  const hostPeerJoined = receive(host);
  send(guest, { type: "join", room: "ABC123", protocolVersion: 6, contentHash: BUILD_HASH });
  const guestAssigned = await receive(guest);
  assert.equal(guestAssigned.id, 2);
  assert.deepEqual(guestAssigned.peers, [1]);
  assert.equal(guestAssigned.participantRole, "player");
  assert.equal((await hostPeerJoined).id, 2);

  const offerReceived = receive(host);
  send(guest, { type: "offer", to: 1, sdp: "test-sdp" });
  assert.deepEqual(await offerReceived, { type: "offer", from: 2, sdp: "test-sdp" });
  await stop(app, [host, guest]);
});

test("room directory tracks compatible rooms, player counts, and host rules", async () => {
  const app = await startServer();
  const directory = await connect(app.port);
  const host = await connect(app.port);
  const guest = await connect(app.port);
  send(directory, { type: "list_rooms", protocolVersion: 6, contentHash: BUILD_HASH });
  assert.deepEqual(await receive(directory), { type: "room_list", rooms: [] });

  const createdList = receive(directory);
  send(host, {
    type: "host",
    room: "LIST42",
    name: "Arena Host",
    targetWins: 7,
    protocolVersion: 6,
    contentHash: BUILD_HASH,
  });
  await receive(host);
  assert.deepEqual((await createdList).rooms, [{
    code: "LIST42",
    hostName: "Arena Host",
    players: 1,
    maxPlayers: 2,
    spectators: 0,
    maxSpectators: 4,
    targetWins: 7,
    joinable: true,
    spectatorJoinable: true,
  }]);

  const updatedRules = receive(directory);
  send(host, { type: "update_room", targetWins: 4, maxPlayers: 2 });
  assert.equal((await updatedRules).rooms[0].targetWins, 4);

  const joinedList = receive(directory);
  const hostPeerJoined = receive(host);
  send(guest, { type: "join", room: "LIST42", protocolVersion: 6, contentHash: BUILD_HASH });
  await receive(guest);
  await hostPeerJoined;
  const joinedRoom = (await joinedList).rooms[0];
  assert.equal(joinedRoom.players, 2);
  assert.equal(joinedRoom.joinable, false);
  await stop(app, [directory, host, guest]);
});

test("room validation rejects missing, mismatched, and full rooms", async () => {
  const app = await startServer();
  const host = await connect(app.port);
  const missing = await connect(app.port);
  send(missing, { type: "join", room: "NOPE00", protocolVersion: 6, contentHash: BUILD_HASH });
  assert.equal((await receive(missing)).code, "room_not_found");

  send(host, { type: "host", room: "ROOM42", protocolVersion: 6, contentHash: BUILD_HASH });
  await receive(host);
  const mismatch = await connect(app.port);
  send(mismatch, { type: "join", room: "ROOM42", protocolVersion: 7, contentHash: BUILD_HASH });
  assert.equal((await receive(mismatch)).code, "build_mismatch");

  const guest = await connect(app.port);
  const hostJoined = receive(host);
  send(guest, { type: "join", room: "ROOM42", protocolVersion: 6, contentHash: BUILD_HASH });
  await receive(guest);
  await hostJoined;
  const extra = await connect(app.port);
  send(extra, { type: "join", room: "ROOM42", protocolVersion: 6, contentHash: BUILD_HASH });
  assert.equal((await receive(extra)).code, "room_full");
  await stop(app, [host, missing, mismatch, guest, extra]);
});

test("even-capacity rooms accept multiple players and separate spectators", async () => {
  const app = await startServer();
  const host = await connect(app.port);
  send(host, {
    type: "host",
    room: "MULTI8",
    protocolVersion: 6,
    contentHash: BUILD_HASH,
    maxPlayers: 4,
  });
  await receive(host);

  const guests = [];
  for (let index = 0; index < 3; index += 1) {
    const guest = await connect(app.port);
    guests.push(guest);
    send(guest, { type: "join", room: "MULTI8", protocolVersion: 6, contentHash: BUILD_HASH });
    const assigned = await receive(guest);
    assert.equal(assigned.id, index + 2);
    assert.equal(assigned.participantRole, "player");
    assert.equal(assigned.peers.length, index + 1);
  }

  const extra = await connect(app.port);
  send(extra, { type: "join", room: "MULTI8", protocolVersion: 6, contentHash: BUILD_HASH });
  assert.equal((await receive(extra)).code, "room_full");

  const spectator = await connect(app.port);
  send(spectator, { type: "join", room: "MULTI8", protocolVersion: 6, contentHash: BUILD_HASH, spectator: true });
  const spectatorAssigned = await receive(spectator);
  assert.equal(spectatorAssigned.id, 5);
  assert.equal(spectatorAssigned.participantRole, "spectator");
  assert.deepEqual(spectatorAssigned.peers, [1, 2, 3, 4]);

  await stop(app, [host, ...guests, extra, spectator]);
});

test("TURN credentials are only sourced from server environment", () => {
  const servers = buildIceServers({
    TURN_URL: "turns:relay.example.test:5349",
    TURN_USERNAME: "user",
    TURN_CREDENTIAL: "secret",
  });
  assert.equal(servers.length, 2);
  assert.deepEqual(servers[1], {
    urls: "turns:relay.example.test:5349",
    username: "user",
    credential: "secret",
  });
});
