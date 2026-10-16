import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const app = createQqServer({ publicDir: resolve('build/web-validation'), iceServers: [] });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true,
  args: ['--disable-background-timer-throttling', '--disable-renderer-backgrounding'] });
const errors = [];
const clients = [];
const state = page => page.evaluate(() => JSON.parse(window.qqState || '{}'));
const command = (page, action, extra = {}) => page.evaluate(payload => window.qqCommand(JSON.stringify(payload)), { action, ...extra });
async function wait(page, predicate, timeout = 30000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const value = await state(page);
    if (predicate(value)) return value;
    await page.waitForTimeout(100);
  }
  assert.fail(`State timeout: ${JSON.stringify(await state(page))}`);
}
try {
  for (let index = 0; index < 3; index++) {
    const context = await browser.newContext({ viewport: { width: 640, height: 360 } });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => {
      if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
    });
    clients.push(page);
    await page.goto(`http://127.0.0.1:${app.server.address().port}`);
    await wait(page, data => data.ticks > 2, 90000);
  }
  const [host, guest, observer] = clients;
  await command(host, 'host', { room: 'GOLD01', players: 2 });
  await wait(host, data => data.players?.length === 1);
  await command(guest, 'join', { room: 'GOLD01', name: 'Buyer' });
  await command(observer, 'join', { room: 'GOLD01', name: 'Observer', spectator: true });
  await wait(host, data => data.players?.length === 3);
  for (const page of [host, guest]) await command(page, 'lobby_ready');
  await wait(host, data => data.players.filter(player => player.ready).length >= 2);
  await command(host, 'prepare');
  for (const page of clients) await wait(page, data => data.phase === 'preparation');
  await command(host, 'spending_fixture');
  for (const page of [host, guest]) await wait(page, data => data.run.gold === 200);
  await command(host, 'arena_action', { kind: 'buy_card', args: { index: 0 } });
  await wait(host, data => data.gold_spent === 22 && data.saved_gold_spent === 22);
  assert.equal((await state(guest)).gold_spent, 0, 'Host payment credited the guest');
  await command(host, 'arena_action', { kind: 'buy_card', args: { index: 0 } });
  await host.waitForTimeout(500);
  assert.equal((await state(host)).gold_spent, 22, 'Repeated purchase was counted');
  await command(guest, 'arena_action', { kind: 'buy_relic', args: { index: 0 } });
  await wait(guest, data => data.gold_spent === 50 && data.saved_gold_spent === 50 && data.run.gold === 185);
  assert.equal((await state(host)).gold_spent, 22, 'Guest payment credited the host');
  await command(guest, 'arena_action', { kind: 'reroll' });
  await wait(guest, data => data.gold_spent === 57 && data.saved_gold_spent === 57);
  await command(observer, 'arena_action', { kind: 'buy_card', args: { index: 0 } });
  await observer.waitForTimeout(500);
  assert.equal((await state(observer)).gold_spent, 0, 'Spectator was credited');
  assert.deepEqual((await state(observer)).run, {}, 'Spectator acquired a player run');
  assert.deepEqual(errors, []);
  const output = resolve('tools/.local/gold-spending-tests/network');
  await mkdir(output, { recursive: true });
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ states: await Promise.all(clients.map(state)), errors }, null, 2));
  console.log('WEB_GOLD_SPENDING_NETWORK_OK host=22 guest=57 observer=0; gross payments and deferred persistence verified');
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
