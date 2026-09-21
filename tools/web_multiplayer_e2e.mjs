import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const playwright = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright')
  : require('playwright');
const output = resolve('tools/.local/web-multiplayer');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-validation'), iceServers: [] });
await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${app.server.address().port}`;
const browser = await playwright.chromium.launch({ channel: 'chrome', headless: true,
  args: ['--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--autoplay-policy=no-user-gesture-required'] });
const clients = [];
const errors = [];
const report = { cases: [], states: [] };
const state = page => page.evaluate(() => JSON.parse(window.qqState || '{}'));
const command = (page, action, fields = {}) => page.evaluate(payload => window.qqCommand(JSON.stringify(payload)), { action, ...fields });
const wait = async (page, predicate, timeout = 30000) => {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const value = await state(page);
    if (predicate(value)) return value;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`State timeout: ${JSON.stringify(await state(page))}`);
};
try {
  for (let i = 0; i < 5; i++) {
	console.log('Loading client', i);
    const context = await browser.newContext({ viewport: { width: 960, height: 540 } });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push({ client: i, error: String(error) }));
    page.on('console', message => {
      if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push({ client: i, error: message.text() });
    });
    clients.push(page);
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await wait(page, data => data.ticks > 2, 90000);
	console.log('Client ready', i);
  }
  for (const count of [2, 4]) {
	console.log('Starting scenario', count);
    const room = `TEST0${count}`;
    const players = clients.slice(0, count);
    const spectator = clients[4];
    await command(players[0], 'host', { room, players: count });
    await wait(players[0], data => data.players?.length === 1);
    for (let i = 1; i < count; i++) await command(players[i], 'join', { room, name: `P${i+1}` });
    await command(spectator, 'join', { room, name: 'Observer', spectator: true });
    await wait(players[0], data => data.players?.length === count + 1);
    for (const page of players) await command(page, 'lobby_ready');
    await wait(players[0], data => data.players.filter(p => p.ready).length >= count);
    await command(players[0], 'prepare');
    for (const page of [...players, spectator]) await wait(page, data => data.phase === 'preparation');
    for (const page of players) await command(page, 'ready');
    for (const page of players) await wait(page, data => data.phase === 'battle');
    for (const page of players) await command(page, 'start');
    for (const page of players) await wait(page, data => data.battle_time > 1);
    const reconnectTarget = players[1];
    const reconnectMatchId = (await state(reconnectTarget)).matches.match_id;
    await command(reconnectTarget, 'drop_transport');
    await wait(reconnectTarget, data => data.reconnecting && !data.connected);
    await wait(reconnectTarget, data => data.connected && !data.reconnecting, 30000);
    const reconnectedState = await wait(reconnectTarget, data => data.battle_time > 1.2, 30000);
    assert.equal(reconnectedState.matches.match_id, reconnectMatchId, 'Guest did not return to the same match');
    await command(players[0], 'marker_hp');
    for (const page of players) await wait(page, data => data.player_hp >= 30 && data.player_hp <= 40);
    const snapshots = await Promise.all(players.map(state));
    assert.equal(new Set(snapshots.map(s => s.matches.match_id)).size, count / 2);
    for (const a of snapshots) for (const b of snapshots) {
      if (a.matches.match_id === b.matches.match_id) {
        assert.equal(a.player_hp, b.player_hp);
        assert.equal(a.enemy_hp, b.enemy_hp);
      }
    }
    assert.deepEqual((await state(spectator)).run, {}, 'Spectator acquired a player run');
    for (let i = 0; i < count / 2; i++) {
      await command(players[0], 'finish_pair', { index: i });
      await wait(players[0], data => data.results.completed_count === i + 1, 30000);
      const result = (await state(players[0])).results;
      assert.equal(result.all_complete, i + 1 === count / 2, 'Round advanced before all parallel matches finished');
    }
    for (const page of [...players, spectator]) await wait(page, data => data.results.all_complete);
    const final = await state(spectator);
    assert.equal(final.results.standings.length, count, 'Spectator entered scoring');
    assert.deepEqual(final.run, {});
    assert.ok((await state(players[1])).diagnostics.accepted > 10, 'No sustained WebRTC snapshots');
    report.cases.push(`${count} players + spectator: preparation, countdown, same-match guest reconnect, parallel independent HP, fatigue simultaneous death, result barrier, spectator exclusion`);
    report.states.push(await Promise.all([...players, spectator].map(state)));
    for (const page of players) await command(page, 'ack');
    for (const page of players) await wait(page, data => data.phase === 'preparation');
    // Host authority cannot be reconstructed; clients exit when the host closes the room.
    await command(players[0], 'leave');
    for (const page of [...players.slice(1), spectator]) {
      await wait(page, data => !data.connected);
      await command(page, 'leave');
      await command(page, 'clear_error');
    }
    report.cases.push(`${count} players: host disconnect handled; clients remain responsive`);
  }
  assert.deepEqual(errors, [], 'Godot/browser errors');
  report.status = 'passed';
  console.log('WEB_MULTIPLAYER_E2E_OK', report.cases);
} catch (error) {
  report.status = 'failed';
  report.error = String(error);
  report.errors = errors;
  report.lastStates = await Promise.all(clients.map(state));
  throw error;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
  await new Promise(resolve => app.server.close(resolve));
}
