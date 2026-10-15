import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/content-progression-browser');
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
  async function settled(action, extra = {}) {
    let state = await command(action, extra);
    for (let i = 0; i < 12; i++) {
      if (state.content_progress && (state.screen !== 'CardLibrary' || state.controls.some(item => item.name === 'SealCard_strike'))) return state;
      state = await command('inspect');
    }
    assert.fail('Content screen did not settle');
  }
  function checkBounds(state) {
    const [width, height] = state.viewport;
    const overflow = state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && w > 1 && h > 1 && (x < -2 || y < -2 || x + w > width + 2 || y + h > height + 2);
    });
    assert.deepEqual(overflow, [], 'Content page viewport overflow');
  }
  async function click(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing ${name}`);
    const canvas = await page.locator('#canvas').boundingBox();
    const [x, y, w, h] = control.rect;
    await page.mouse.click(canvas.x + (x + w / 2) * canvas.width / state.viewport[0], canvas.y + (y + h / 2) * canvas.height / state.viewport[1]);
    return command('inspect');
  }
  for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    for (const [screen, xp] of [['library', 0], ['meta', 3], ['library', 125]]) {
      let state = await settled('content_fixture', { screen, xp });
      checkBounds(state);
      assert.equal(state.content_progress.xp, xp);
      if (screen === 'library') {
        assert(!state.controls.some(item => item.name.startsWith('UnlockCard_')));
        state = await click(state, 'SealCard_strike');
        assert(state.content_progress.sealed_cards.includes('strike'), 'Pointer toggle did not seal card');
        assert(!state.content_pool.cards.includes('strike'), 'Sealed card remains eligible');
        state = await click(state, 'SealCard_strike');
        assert(!state.content_progress.sealed_cards.includes('strike'), 'Pointer toggle did not unseal card');
      } else {
        assert(state.controls.some(item => item.name === 'MetaContentProgressBar'));
        assert(!state.controls.some(item => item.name.startsWith('UnlockRelic_')));
      }
      await page.screenshot({ path: resolve(output, `${screen}-xp${xp}-${viewport.width}x${viewport.height}.png`) });
      await writeFile(resolve(output, `${screen}-xp${xp}-${viewport.width}x${viewport.height}.json`), JSON.stringify(state, null, 2));
      cases.push({ screen, xp, viewport, sealed: state.content_progress.sealed_cards });
    }
  }
  assert.deepEqual(errors, [], 'Browser runtime errors');
  await writeFile(resolve(output, 'results.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log(`WEB_CONTENT_PROGRESSION_OK ${cases.length} layouts; real pointer seal/unseal, progress, bounds, no runtime errors`);
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
