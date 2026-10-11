import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomBytes } from 'node:crypto';

const require = createRequire(import.meta.url);
const { WebSocket } = require('ws');
const sockets = [];
const room = randomBytes(3).toString('hex').toUpperCase();
// Deliberately isolated from the actual game hash; this room never appears to players.
const identity = { protocolVersion: 13, contentHash: 'a'.repeat(64) };
async function connect() {
  const socket = new WebSocket('wss://masterqueue.kazu107.xyz/signal');
  sockets.push(socket);
  await new Promise((done, reject) => {
    socket.once('open', done);
    socket.once('error', reject);
  });
  return socket;
}
function request(socket, payload) {
  return new Promise((done, reject) => {
    const timer = setTimeout(() => { socket.off('message', listener); reject(new Error('Public bot response timeout')); }, 15000);
    function listener(bytes) {
      clearTimeout(timer);
      socket.off('message', listener);
      done(JSON.parse(bytes.toString('utf8')));
    }
    socket.on('message', listener);
    socket.send(JSON.stringify(payload));
  });
}
try {
  const host = await connect();
  assert.equal((await request(host, { type: 'host', room, name: 'Bot release check', maxPlayers: 2, ...identity })).id, 1);
  const added = await request(host, { type: 'add_bot', starterId: 'fortress' });
  assert.equal(added.type, 'bots_updated', 'Heroku bot server not deployed yet');
  assert.equal(added.accepted, true);
  assert.equal(added.bots[0].starterId, 'fortress');
  const directory = await connect();
  const listed = await request(directory, { type: 'list_rooms', ...identity });
  const entry = listed.rooms.find(entry => entry.code === room);
  assert.equal(entry.players, 2);
  assert.equal(entry.bots, 1);
  assert.equal(entry.joinable, false);
  host.send(JSON.stringify({ type: 'set_room_active', active: true }));
  assert.equal((await request(host, { type: 'remove_bot', id: added.bots[0].id })).code, 'match_active');
  host.send(JSON.stringify({ type: 'set_room_active', active: false }));
  assert.equal((await request(host, { type: 'remove_bot', id: added.bots[0].id })).accepted, true);
  console.log('PUBLIC_WEB_BOTS_SERVER_OK add/remove, directory capacity and active-match lock');
} finally {
  for (const socket of sockets) {
    if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'leave' }));
    socket.close();
  }
}
