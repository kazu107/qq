import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/action-icons-web');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
  });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 120000 });
  await page.waitForSelector('#status', { state: 'detached' });
  let sequence = 0;
  async function command(action, screen) {
    const expected = ++sequence;
    await page.evaluate(data => window.qqLayoutCommand(JSON.stringify(data)), { action, screen, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  function bounds(state) {
    const overflow = state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && (x < -2 || y < -2 || x + w > state.viewport[0] + 2 || y + h > state.viewport[1] + 2);
    });
    assert.deepEqual(overflow, []);
  }
  async function move(rect, state) {
    const canvas = await page.locator('#canvas').boundingBox();
    await page.mouse.move(canvas.x + (rect[0] + rect[2] / 2) * canvas.width / state.viewport[0], canvas.y + (rect[1] + rect[3] / 2) * canvas.height / state.viewport[1]);
  }
  for (const screen of ['hub', 'settings', 'setup', 'map', 'arena', 'meta', 'library', 'reward', 'event', 'result', 'online_bots', 'online_arena', 'battle']) {
    let state = await command('screen', screen);
    await page.waitForTimeout(500);
    state = await command('inspect');
    bounds(state);
    const icons = state.controls.filter(item => item.icon);
    cases.push({ screen, icons: icons.map(item => ({ name: item.name, icon: item.icon })) });
    await page.screenshot({ path: resolve(output, `${screen}.png`) });
  }
  let state = await command('status_icons');
  assert.equal(state.status_icons.regions.length, 4);
  await move(state.status_icons.regions[0].rect, state);
  await page.waitForTimeout(250);
  state = await command('inspect');
  await writeFile(resolve(output, 'status-hover-state.json'), JSON.stringify(state, null, 2));
  await page.screenshot({ path: resolve(output, 'status-hover.png') });
  assert.equal(state.status_icons.tooltip_visible, true, '3D status icon did not open its hover details');
  assert(state.status_icons.tooltip_text.includes('30.0'));
  const start = state.controls.find(item => item.name === 'BattleStartButton');
  await move(start.rect, state);
  await page.mouse.down();
  await page.mouse.up();
  await move(state.status_icons.regions[0].rect, state);
  await page.waitForTimeout(600);
  state = await command('inspect');
  assert(state.status_icons.tooltip_visible && !state.status_icons.tooltip_text.includes('30.0'), 'Status seconds did not update while hovered');
  await page.mouse.move(2, 2);
  await page.waitForTimeout(100);
  state = await command('inspect');
  assert.equal(state.status_icons.tooltip_visible, false, 'Status tooltip remained after mouse exit');
  for (const size of [{ width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size);
    for (const screen of ['library', 'arena', 'online_bots', 'online_arena', 'battle']) {
      state = await command('screen', screen);
      await page.waitForTimeout(250);
      state = await command('inspect');
      bounds(state);
      await page.screenshot({ path: resolve(output, `${screen}-${size.width}x${size.height}.png`) });
    }
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_ACTION_ICONS_REVIEW_OK', cases.length, 'screens, 3 sizes, live status hover/exit, no script errors');
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
