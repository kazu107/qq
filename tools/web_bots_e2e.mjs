import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/web-bots');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-validation'), iceServers: [] });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true,
  args: ['--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--autoplay-policy=no-user-gesture-required'] });
const clients = [];
const errors = [];
const report = { cases: [], states: [] };
const state = page => page.evaluate(() => JSON.parse(window.qqState || '{}'));
const command = (page, action, extra = {}) => page.evaluate(data => window.qqCommand(JSON.stringify(data)), { action, ...extra });
async function wait(page, predicate, timeout = 45000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const value = await state(page);
    assert.equal(value.error || '', '', 'Network rejected bot flow');
    if (predicate(value)) return value;
    await new Promise(done => setTimeout(done, 100));
  }
  throw new Error(`Bot state timeout: ${JSON.stringify(await state(page))}`);
}
async function leaveAll() {
  await command(clients[0], 'leave');
  for (const page of clients) {
    await command(page, 'leave');
    await command(page, 'clear_error');
  }
}
async function claimRewards(page) {
  for (let queue = 0; queue < 2; queue++) {
    const rewards = (await state(page)).rewards || [];
    if (!rewards.length) return;
    const id = rewards[0].id;
    await command(page, 'choose_reward', { id });
    await wait(page, value => !(value.rewards || []).some(reward => reward.id === id));
  }
}
try {
  for (let index = 0; index < 3; index++) {
    const page = await browser.newPage({ viewport: { width: 960, height: 600 } });
    page.on('pageerror', error => errors.push({ index, error: String(error) }));
    page.on('console', message => {
      if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push({ index, error: message.text() });
    });
    clients.push(page);
    await page.goto(`http://127.0.0.1:${app.server.address().port}/`);
    await wait(page, value => value.ticks > 2, 90000);
  }
  const [host, guest, watcher] = clients;
  console.log('Bot scenario: one human + bot');
  await command(host, 'host', { room: 'BOTS02', players: 2 });
  await wait(host, value => value.connected && value.room === 'BOTS02');
  await command(host, 'add_bot', { starter: 'tempo' });
  let value = await wait(host, value => value.players.length === 2);
  const firstBot = value.players.find(player => player.is_bot);
  assert.equal(firstBot.starter_id, 'tempo');
  await command(host, 'remove_bot', { id: firstBot.peer_id });
  await wait(host, value => value.players.length === 1);
  await command(host, 'add_bot', { starter: 'balanced' });
  await wait(host, value => value.players.length === 2);
  await command(watcher, 'join', { room: 'BOTS02', name: 'Observer', spectator: true });
  await wait(watcher, value => value.players.length === 3);
  await command(host, 'rules', { target_wins: 2, interval: 1 });
  await command(host, 'lobby_ready');
  await command(host, 'prepare');
  await wait(host, value => value.phase === 'preparation' && value.arena_ready === 1);
  await command(host, 'ready');
  await wait(host, value => value.phase === 'battle' && value.battle_ready === 1);
  await new Promise(done => setTimeout(done, 500));
  assert.equal((await state(host)).battle_time, 0, 'Bot started before human');
  await command(host, 'start');
  await wait(host, value => value.battle_time > 3 && value.bot_matches[0].active > 0);
  assert.deepEqual((await state(watcher)).run, {});
  for (let round = 0; round < 2; round++) {
    await command(host, 'force_pair', { index: 0, winner: 'enemy' });
    await wait(host, value => value.results.all_complete);
    await wait(host, value => value.results.continue_ready_count === 1);
    assert.equal((await state(host)).phase, 'round_result', 'Bot skipped human results');
    await command(host, 'ack');
    if (round === 0) {
      await wait(host, value => value.phase === 'preparation' && value.arena_ready === 1);
      const botDetails = (await state(host)).details.find(player => player.peer_id >= 1000000000);
      assert.equal(botDetails.wins, 1);
      assert(botDetails.owned_cards.length > 0);
	  await claimRewards(host);
      await command(host, 'ready');
      await wait(host, value => value.phase === 'battle');
      await command(host, 'start');
      await wait(host, value => value.battle_time > 0);
    }
  }
  value = await wait(host, value => value.phase === 'finished');
  assert(value.results.standings[0].is_bot, 'Bot winner was not ranked');
  assert.equal(value.results.standings.length, 2, 'Spectator scored');
  report.cases.push('human + bot + spectator: add/remove, chosen deck, preparation, countdown, AI, rewards, first-to-two, human result barrier');
  report.states.push(value);
  await leaveAll();

  console.log('Bot scenario: two humans + two bots');
  await command(host, 'host', { room: 'BOTS04', players: 4 });
  await wait(host, value => value.connected && value.room === 'BOTS04');
  await command(guest, 'join', { room: 'BOTS04', name: 'Human 2' });
  await wait(host, value => value.players.length === 2);
  await command(host, 'add_bot', { starter: 'fortress' });
  await wait(host, value => value.players.length === 3);
  await command(host, 'add_bot', { starter: 'balanced' });
  await wait(host, value => value.players.length === 4);
  await command(watcher, 'join', { room: 'BOTS04', name: 'Observer', spectator: true });
  await wait(watcher, value => value.players.length === 5);
  for (const page of [host, guest]) await command(page, 'lobby_ready');
  await wait(host, value => value.players.filter(player => player.ready).length === 4);
  await command(host, 'prepare');
  await wait(host, value => value.phase === 'preparation' && value.arena_ready === 2);
  for (const page of [host, guest]) await command(page, 'ready');
  for (const page of [host, guest]) await wait(page, value => value.phase === 'battle');
  for (const page of [host, guest]) await command(page, 'start');
  await wait(host, value => value.bot_matches.length === 2 && value.bot_matches.every(match => match.time > 2 && match.bots === 1));
  const hostMatch = (await state(host)).matches.match_id;
  assert.notEqual(hostMatch, (await state(guest)).matches.match_id);
  await command(guest, 'drop_transport');
  await wait(guest, value => value.reconnecting);
  await wait(guest, value => value.connected && !value.reconnecting);
  await command(host, 'force_pair', { index: 0 });
  await wait(host, value => value.results.completed_count === 1);
  assert.equal((await state(host)).results.all_complete, false);
  await command(host, 'force_pair', { index: 1 });
  for (const page of [host, guest, watcher]) await wait(page, value => value.results.all_complete);
  assert.equal((await state(watcher)).results.standings.length, 4);
  assert.deepEqual((await state(watcher)).run, {});
  for (const page of [host, guest]) await command(page, 'ack');
  await wait(host, value => value.phase === 'preparation' && value.arena_ready === 2);
  for (const page of [host, guest]) {
    await claimRewards(page);
    await command(page, 'ready');
  }
  await wait(guest, value => value.phase === 'battle' && value.side === 'enemy');
  for (const page of [host, guest]) await command(page, 'start');
  await wait(host, value => value.bot_matches.every(match => match.time > 1 && match.bots === 1));
  for (let index = 0; index < 2; index++) await command(host, 'force_pair', { index, winner: 'enemy' });
  await wait(guest, value => value.results.all_complete && value.results.standings.find(player => player.peer_id === 2)?.wins === 1);
  assert.equal((await state(guest)).details.find(player => player.peer_id === 2).wins, 1);
  for (const page of [host, guest]) await command(page, 'ack');
  await wait(guest, value => value.phase === 'preparation' && value.run.arena_wins === 1);
  report.cases.push('two humans + two bots + spectator: parallel matches, reconnect, independent results, shared barrier, second-round side swap and correct winner stats');
  report.states.push(await state(host));
  await leaveAll();

  console.log('Bot scenario: spectator host + two bots');
  await command(host, 'host', { room: 'BOTSAA', players: 2 });
  await wait(host, value => value.connected && value.room === 'BOTSAA');
  await command(host, 'role', { role: 'spectator' });
  await wait(host, value => value.players[0]?.role === 'spectator');
  await command(host, 'fill_bots');
  await wait(host, value => value.players.length === 3);
  await command(host, 'rules', { target_wins: 1 });
  await command(host, 'prepare');
  await wait(host, value => value.phase === 'battle' && value.battle_time > 1 && value.bot_matches[0].bots === 2);
  assert.equal((await state(host)).side, 'spectator');
  await command(host, 'force_pair', { index: 0, winner: 'player' });
  await wait(host, value => value.phase === 'finished');
  assert.deepEqual((await state(host)).run, {});
  report.cases.push('spectator host + two bots: automatic countdown, two AI controllers, bot-only results advance without deadlock');
  assert.deepEqual(errors, []);
  report.status = 'passed';
  console.log('WEB_BOTS_E2E_OK', report.cases);
} catch (error) {
  report.status = 'failed';
  report.error = String(error);
  report.errors = errors;
  report.lastStates = [];
  for (const page of clients) report.lastStates.push(await state(page));
  throw error;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
