import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/blender-web-review');
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
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 120000 });
  await page.waitForSelector('#status', { state: 'detached' });

  async function command(action, screen, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, screen, sequence: expected, ...extra });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected, { timeout: 30000 });
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }

  async function click(name) {
    const state = await command('inspect');
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing control ${name}`);
    const canvas = await page.locator('#canvas').boundingBox();
    const [x, y, w, h] = control.rect;
    await page.mouse.click(canvas.x + (x + w / 2) * canvas.width / state.viewport[0], canvas.y + (y + h / 2) * canvas.height / state.viewport[1]);
    await page.waitForTimeout(150);
    return command('inspect');
  }

  function validateBounds(state) {
    const [width, height] = state.viewport;
    const overflow = state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && w > 1 && h > 1 && (x < -2 || y < -2 || x + w > width + 2 || y + h > height + 2);
    });
    assert.deepEqual(overflow, [], 'Viewport overflow');
  }

  for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size);
    let state = await command('screen', 'art_lab');
    await page.waitForFunction(() => JSON.parse(window.qqLayoutState || '{}').screen === 'ArtLab');
    await page.waitForTimeout(1000);
    state = await command('inspect');
    validateBounds(state);
    assert.equal(state.art.catalog, 282, 'Incomplete runtime art registry');
    assert(state.art.tiles > 0 && state.art.tiles <= 24, 'Unbounded thumbnail grid');
    await page.screenshot({ path: resolve(output, `art-${size.width}x${size.height}.png`) });
    const first = state.controls.find(item => item.name.startsWith('ArtInspect_'));
    assert(first, 'No asset inspection action');
    state = await click(first.name);
    validateBounds(state);
    assert.equal(state.art.preview, true);
    await click('ArtPreviewClose');
    state = await command('inspect');
    assert.equal(state.art.preview, false);
    for (const asset_id of ['environment_fatigue', 'boss_eternity_zero', 'environment_field']) {
      state = await command('art_preview', undefined, { asset_id });
      validateBounds(state);
      assert.equal(state.art.preview, true, `Preview failed: ${asset_id}`);
      await page.screenshot({ path: resolve(output, `${asset_id}-${size.width}x${size.height}.png`) });
      await click('ArtPreviewClose');
    }
    cases.push({ screen: 'art_lab', size, catalog: state.art.catalog, tiles: state.art.tiles, columns: state.art.columns });
  }

  await page.setViewportSize({ width: 1440, height: 900 });
  for (const screen of ['setup', 'map', 'arena', 'battle', 'result']) {
    let state = await command('screen', screen);
    await page.waitForTimeout(600);
    state = await command('inspect');
    validateBounds(state);
    if (screen === 'battle') {
      assert.equal(state.battle.authored_field, true, 'Battle fell back to code-generated field');
      assert.equal(state.battle.authored_player, true);
      assert.equal(state.battle.authored_enemy, true);
      assert.deepEqual(state.battle.detail_counts, { grass: 112, rocks: 18, flowers: 16, ruin_clusters: 2, barrels: 2, crates: 4, distant_hills: 5, distant_trees: 18, distant_ruins: 2 });
    }
    await page.screenshot({ path: resolve(output, `${screen}.png`) });
    cases.push({ screen, authored_field: state.battle?.authored_field });
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ errors, cases }, null, 2));
  console.log('WEB_BLENDER_ART_REVIEW_OK', JSON.stringify({ cases, errors }));
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
