import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const out = resolve('tools/.local/hub-edges/browser');
await mkdir(out, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], samples = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text())) errors.push(message.text()); });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  const sizes = [{ width: 1440, height: 900 }, { width: 1280, height: 720 }, { width: 900, height: 1200 }, { width: 1920, height: 800 }];
  for (const size of sizes) {
    await page.setViewportSize(size); await page.waitForTimeout(200);
    await page.screenshot({ path: resolve(out, `hub-${size.width}x${size.height}.png`) });
  }
  await page.evaluate(() => window.qqLayoutCommand(JSON.stringify({ action: 'hub_background_flat_fixture', sequence: 785 })));
  await page.waitForFunction(() => JSON.parse(window.qqLayoutState || '{}').sequence === 785);
  for (const size of sizes) {
    await page.setViewportSize(size); await page.waitForTimeout(200);
    const file = `flat-${size.width}x${size.height}.png`;
    await page.screenshot({ path: resolve(out, file) });
    samples.push({ file, width: size.width, height: size.height });
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(out, 'report.json'), JSON.stringify({ samples, errors }, null, 2));
  console.log('WEB_HUB_EDGES_REVIEW_OK Hub screenshots and flat-field samples at four sizes, errors=0');
} finally { await browser.close(); app.server.closeAllConnections(); await new Promise(done => app.server.close(done)); }
