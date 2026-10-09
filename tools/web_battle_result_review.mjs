import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/battle-result-review');
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
  async function command(action, screen) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, screen, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function click(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing ${name}`);
    const rect = await page.locator('#canvas').boundingBox();
    const [x, y, w, h] = control.rect;
    await page.mouse.click(rect.x + (x + w / 2) * rect.width / state.viewport[0], rect.y + (y + h / 2) * rect.height / state.viewport[1]);
    return command('inspect');
  }
  function verifyBounds(state) {
    const [width, height] = state.viewport;
    const overflow = state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && w > 1 && h > 1 && (x < -2 || y < -2 || x + w > width + 2 || y + h > height + 2);
    });
    assert.deepEqual(overflow, [], 'Modal overflow');
  }
  let state = await command('screen', 'battle');
  assert(!state.outcome.visible);
  state = await command('battle_simulate');
  assert(!state.outcome.visible, 'Outcome interrupted final impact/collapse');
  for (let attempt = 0; attempt < 40 && !state.outcome.visible; attempt++) {
    await page.waitForTimeout(150);
    state = await command('inspect');
  }
  assert(state.outcome.visible && state.outcome.finished, 'Collapse never completed');
  await page.screenshot({ path: resolve(output, 'outcome.png') });
  state = await click(state, 'BattleDetailsButton');
  assert(state.outcome.details && state.outcome.samples > 2);
  for (const viewport of [{ width: 1440, height: 900 }, { width: 1280, height: 720 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    state = await command('inspect');
    verifyBounds(state);
    await page.screenshot({ path: resolve(output, `details-${viewport.width}x${viewport.height}.png`) });
    cases.push(`${viewport.width}x${viewport.height}: comparison table, HP chart, scrollable details`);
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  state = await command('inspect');
  const scroll = state.controls.find(item => item.name === 'BattleDetailsScroll');
  const [sx, sy, sw, sh] = scroll.rect;
  await page.mouse.move((sx + sw / 2) * 1440 / state.viewport[0], (sy + sh / 2) * 900 / state.viewport[1]);
  await page.mouse.wheel(0, 700);
  for (const metric of ['damage', 'heal', 'shield', 'absorbed']) {
    state = await command('inspect');
    state = await click(state, `Contribution_${metric}`);
    assert(state.outcome.details);
    await page.screenshot({ path: resolve(output, `contributions-${metric}.png`) });
    cases.push(`Contribution selector: ${metric}`);
  }
  state = await click(state, 'BattleDetailsClose');
  assert(state.outcome.visible && !state.outcome.details);
  await click(state, 'BattleContinueButton');
  state = await command('inspect');
  assert.equal(state.screen, 'Reward', 'Continue did not reach rewards');
  cases.push('Outcome -> details -> metric selectors -> back -> rewards');
  assert.deepEqual(errors, []);
  console.log('WEB_BATTLE_RESULT_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
