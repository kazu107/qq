import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/facility-polish/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [];
let sequence = 0;

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (/SCRIPT ERROR|Parse Error|ERROR:/.test(message.text())) errors.push(message.text());
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
  function control(state, name) {
    const item = state.controls.find(item => item.name === name);
    assert(item, `Missing ${name}`);
    return item.rect;
  }
  async function point(state, rect, fraction = 0.5) {
    const box = await page.locator('#canvas').boundingBox();
    return [box.x + (rect[0] + rect[2] * fraction) * box.width / state.viewport[0],
      box.y + (rect[1] + rect[3] / 2) * box.height / state.viewport[1]];
  }
  function inside(inner, outer) {
    return inner[0] >= outer[0] - 1 && inner[1] >= outer[1] - 1 &&
      inner[0] + inner[2] <= outer[0] + outer[2] + 1 && inner[1] + inner[3] <= outer[1] + outer[3] + 1;
  }
  for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size);
    let state = await command('screen', 'forge');
    assert.equal(state.facility.type, 'forge');
    assert.equal(state.facility.previews.length, 6);
    for (const cardId of ['quick_slash', 'guard', 'strike']) {
      const prefix = `ChoiceCardPreview_upgrade_${cardId}_${cardId}_`;
      const before = state.facility.previews.find(item => item.id === prefix + 'before');
      const after = state.facility.previews.find(item => item.id === prefix + 'after');
      const button = control(state, 'ForgeChoiceButton_upgrade_' + cardId);
      assert(before && after && before.text !== after.text, 'Both grades must be distinct');
      assert(before.rect[0] + before.rect[2] < after.rect[0] && Math.abs(before.rect[1] - after.rect[1]) < 1, 'Cards must be side by side');
      assert(inside(before.rect, button) && inside(after.rect, button), 'Preview clipped by button');
    }
    const before = state.facility.previews.find(item => item.id.endsWith('quick_slash_before'));
    const after = state.facility.previews.find(item => item.id.endsWith('quick_slash_after'));
    assert(before.text.startsWith('クイックスラッシュ +1') && after.text.startsWith('クイックスラッシュ +2'));
    assert(after.bbcode.includes('[color='), 'Upgraded tooltip must preserve colored comparisons');
    for (const card of [before, after]) {
      await page.mouse.move(...await point(state, card.rect));
      await page.waitForTimeout(700);
      const hovered = await command('inspect');
      assert.equal(hovered.facility.tooltip, card.text, 'Hover must display the matching grade tooltip');
    }
    await page.mouse.move(0, 0);
    await page.screenshot({ path: resolve(output, `forge-${size.width}x${size.height}.png`) });
    await page.mouse.click(...await point(state, control(state, 'ForgeChoiceButton_upgrade_quick_slash'), 0.25));
    state = await command('inspect');
    assert(state.facility.previews.find(item => item.id.endsWith('quick_slash_before')).text.startsWith('クイックスラッシュ +2'), 'Actual upgrade did not update current preview');

    state = await command('screen', 'shop');
    assert.equal(state.facility.type, 'shop');
    assert(!state.controls.some(item => item.name === 'ShopChoiceButton_courier_job'));
    assert(state.controls.some(item => item.name === 'ShopChoiceButton_buy_repair_kit'));
    await page.screenshot({ path: resolve(output, `shop-${size.width}x${size.height}.png`) });
    state = await command('screen', 'map');
    assert(!state.controls.some(item => item.name === 'MapRouteLegend'));
    cases.push(`${size.width}x${size.height}: forge pairs/grades/purchase, shop choices, map legend`);
  }
  assert.deepEqual(errors, []);
  console.log('WEB_FACILITY_POLISH_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ errors, cases }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
