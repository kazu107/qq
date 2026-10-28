import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/battle-stutter/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
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
    await command('screen', { screen: 'battle_performance' });
    await page.waitForTimeout(700);
    await command('battle_profile_capture', { seconds: 8 });
    await page.waitForFunction(() => Boolean(window.qqFrameReport), undefined, { timeout: 25000 });
    const report = await page.evaluate(() => JSON.parse(window.qqFrameReport));
    assert(report.frame.count > 10 && report.ui.count > 10, 'Battle profiler did not collect live frames');
    assert(report.battle_time > 1 && report.events > 10, 'Battle simulation/effects did not advance');
    assert(report.ui.p95_ms < 100, 'UI frame regression exceeds a loose device-independent guard');
    await page.screenshot({ path: resolve(output, `profile-${viewport.width}.png`) });
    cases.push({ viewport, report });
    await command('screen', { screen: 'hub' });
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_BATTLE_PERFORMANCE_OK', JSON.stringify({ cases, errors }));
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
