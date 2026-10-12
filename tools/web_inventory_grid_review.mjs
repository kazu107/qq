import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/inventory-grid-review');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [];
const columns = { map: new Set(), arena: new Set() };
try {
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
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
  function enclosed(outer, inner) {
    return inner[0] >= outer[0] - 1 && inner[1] >= outer[1] - 1 && inner[0] + inner[2] <= outer[0] + outer[2] + 1 && inner[1] + inner[3] <= outer[1] + outer[3] + 1;
  }
  for (const size of [{ width: 1920, height: 1080 }, { width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size);
    for (const screen of ['map', 'arena', 'online_arena']) {
      await command('screen', screen);
      await page.waitForTimeout(200);
      let state = await command('inspect');
      const inventory = state.loadout;
      assert(inventory.rows.length >= 5 && !inventory.horizontal_bar && inventory.scroll_x === 0);
      if (columns[screen]) columns[screen].add(inventory.columns);
      for (const row of inventory.rows) {
        assert(enclosed(row.rect, row.preview_rect), `${screen}: card art escaped its cell`);
        assert(Math.abs(row.rect[0] + row.rect[2] / 2 - row.preview_rect[0] - row.preview_rect[2] / 2) <= 1, `${screen}: card art was not centered`);
        assert(row.rect[0] + row.rect[2] <= inventory.scroll_rect[0] + inventory.scroll_rect[2] + 1, `${screen}: horizontal clipping`);
      }
      const oldColumns = inventory.columns;
      await page.waitForTimeout(250);
      state = await command('inspect');
      assert.equal(state.loadout.columns, oldColumns, 'Column count oscillated');
      cases.push({ screen, size, columns: oldColumns });
      await page.screenshot({ path: resolve(output, `${screen}-${size.width}x${size.height}.png`) });
    }
  }
  for (const [screen, values] of Object.entries(columns)) assert(values.size > 1 && Math.max(...values) > 1, `${screen}: resolution did not affect column count`);
  await page.setViewportSize({ width: 1440, height: 900 });
  await command('screen', 'result_partial');
  let state = await command('finish_score');
  assert.equal(state.score.efficiency, 316, 'One early battle incorrectly gained full efficiency');
  await page.screenshot({ path: resolve(output, 'partial-run-score.png') });
  assert.deepEqual(errors, []);
  console.log('WEB_INVENTORY_GRID_REVIEW_OK', JSON.stringify({ cases, partialEfficiency: state.score.efficiency, errors }));
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
