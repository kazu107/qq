import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/loadout-hover-review');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
const cases = [];
let sequence = 0;
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
  });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 90000 });
  await page.waitForSelector('#status', { state: 'detached' });
  async function inspect(screen) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action: screen ? 'screen' : 'inspect', screen, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  function point(rect, state, offset = 0) {
    const [x, y, w, h] = rect;
    const viewport = page.viewportSize();
    return [(x + w / 2 + offset) * viewport.width / state.viewport[0], (y + h / 2) * viewport.height / state.viewport[1]];
  }
  for (const screen of ['map', 'arena']) {
    await page.mouse.move(1, 1);
    let state = await inspect(screen);
    assert(state.loadout.cards.every(card => !card.close));
    assert(state.loadout.rows.every(row => !row.actions && row.buttons === 2));
    const initialCount = state.loadout.cards.length;
    const initialCard = state.loadout.cards[0];
    await page.mouse.move(...point(initialCard.rect, state));
    state = await inspect();
    assert(state.loadout.cards[0].close, `${screen}: missing hover close`);
    await page.screenshot({ path: resolve(output, `${screen}-deck-close.png`) });
    for (let index = 0; index < 8; index++) {
      await page.mouse.move(...point(state.loadout.cards[0].close_rect, state, index % 2 ? 4 : -4));
      state = await inspect();
      assert(state.loadout.cards[0].close, `${screen}: close button flickered`);
    }
    await page.mouse.click(...point(state.loadout.cards[0].close_rect, state));
    state = await inspect();
    assert.equal(state.loadout.cards.length, initialCount - 1);
    const rowName = `${screen === 'arena' ? 'Arena' : ''}LoadoutCardFrame_${initialCard.id}`;
    let row = state.loadout.rows.find(item => item.name === rowName);
    assert(row, 'Unequipped card vanished from owned inventory');
    const frameBefore = row.rect;
    await page.mouse.move(...point(row.rect, state));
    state = await inspect();
    row = state.loadout.rows.find(item => item.name === rowName);
    assert(row.actions);
    assert.deepEqual(row.rect, frameBefore, 'Showing actions resized the frame');
    for (let index = 0; index < 8; index++) {
      await page.mouse.move(...point(row.equip_rect, state, index % 2 ? 4 : -4));
      state = await inspect();
      row = state.loadout.rows.find(item => item.name === rowName);
      assert(row.actions, 'Inventory action flickered while moving across buttons');
    }
    await page.screenshot({ path: resolve(output, `${screen}-inventory-actions.png`) });
    await page.mouse.click(...point(row.equip_rect, state));
    state = await inspect();
    assert.equal(state.loadout.cards.length, initialCount, 'Inventory equip button failed');
    await page.mouse.move(1, 1);
    state = await inspect();
    assert(state.loadout.rows.every(item => !item.actions) && state.loadout.cards.every(card => !card.close), 'Actions stuck after cursor exited');
    // Scroll under a stationary cursor, then leave the browser canvas.
    row = state.loadout.rows.find(item => item.name === rowName);
    await page.mouse.move(...point(row.rect, state));
    await page.mouse.wheel(0, 420);
    await page.mouse.move(1, 1);
    state = await inspect();
    assert(state.loadout.rows.every(item => !item.actions), 'Scrolled actions remained visible');
    cases.push(`${screen}: real hover, stable close button, unequip/equip, fixed frame size, child hover, scroll and missed exit`);
  }
  assert.deepEqual(errors, []);
  console.log('WEB_LOADOUT_HOVER_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
