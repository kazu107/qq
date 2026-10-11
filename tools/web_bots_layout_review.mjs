import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/web-bots-layout');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
const cases = [];
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
  for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size);
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action: 'screen', screen: 'online_bots', sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    const state = await page.evaluate(() => JSON.parse(window.qqLayoutState));
    assert.equal(state.screen, 'OnlineLobby');
    assert(state.controls.some(item => item.name === 'OnlineAddBotButton'));
    assert.equal(state.controls.filter(item => item.name.startsWith('OnlineRemoveBot_')).length, 3);
    const overflow = state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && (x < -2 || y < -2 || x + w > state.viewport[0] + 2 || y + h > state.viewport[1] + 2);
    });
    assert.deepEqual(overflow, []);
    await page.screenshot({ path: resolve(output, `lobby-${size.width}x${size.height}.png`) });
    cases.push({ size, buttons: 3 });
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_BOTS_LAYOUT_OK', JSON.stringify(cases));
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
