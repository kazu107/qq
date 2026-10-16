import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/gold-spending-tests/browser');
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
  async function command(action, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }]) {
    await page.setViewportSize(viewport);
    for (const fixture of [{ spent: 0, claimed: 0, target: 25 }, { spent: 1500, claimed: 4, target: 1500 }, { spent: 10000, claimed: 7, target: 10000 }]) {
      let state = await command('gold_spending_fixture', fixture);
      for (let frame = 0; !state.gold_spending && frame < 15; frame++) state = await command('inspect');
      state = await command('gold_spending_focus');
      const gold = state.gold_spending;
      assert.equal(gold.name, '累計ゴールド使用額');
      assert.equal(gold.max, fixture.target);
      assert.equal(gold.value, Math.min(fixture.spent, fixture.target));
      assert.equal(gold.disabled, fixture.spent < fixture.target);
      assert(gold.progress_rect[1] + gold.progress_rect[3] <= gold.bar_rect[1] + 1, 'Progress number is not above its bar');
      const [x, y, width, height] = gold.button_rect;
      assert(x >= 0 && y >= 0 && x + width <= state.viewport[0] + 1 && y + height <= state.viewport[1] + 1, 'Achievement claim button is clipped');
      if (!gold.disabled) {
        const canvas = await page.locator('#canvas').boundingBox();
        await page.mouse.click(canvas.x + (x + width / 2) * canvas.width / state.viewport[0], canvas.y + (y + height / 2) * canvas.height / state.viewport[1]);
        state = await command('inspect');
        assert.equal(state.gold_spending.claimed, fixture.claimed + 1, 'Pointer claim failed');
        assert(state.gold_spending.disabled, 'Same tier can be claimed twice');
      }
      await page.screenshot({ path: resolve(output, `${fixture.spent}-${viewport.width}x${viewport.height}.png`) });
      cases.push({ viewport, fixture, result: state.gold_spending });
    }
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_GOLD_SPENDING_OK', JSON.stringify({ layouts: cases.length, errors }));
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
