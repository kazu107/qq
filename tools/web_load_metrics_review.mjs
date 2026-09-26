import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright')
  : require('playwright');
const output = resolve('tools/.local/web-load-metrics');
await mkdir(output, { recursive: true });
const app = createQqServer();
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
  });
  const openedAt = Date.now();
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(entry => entry.event === 'boot_ready'), undefined, { timeout: 90000 });
  await page.waitForFunction(() => window.qqLoadMetrics?.some(entry => entry.event === 'scene_transition' && entry.details.screen === 'Hub'), undefined, { timeout: 30000 });
  const report = { boot_wall_ms: Date.now() - openedAt, transitions: [] };
  async function sampleMemory() {
    return page.evaluate(async () => {
      let pageEstimate = null;
      try {
        if (performance.measureUserAgentSpecificMemory) {
          const result = await Promise.race([
            performance.measureUserAgentSpecificMemory(),
            new Promise((_, reject) => setTimeout(() => reject(new Error('memory sample timeout')), 3000)),
          ]);
          pageEstimate = result.bytes;
        }
      } catch { /* Browser support and isolation vary. */ }
      return {
        page_estimate_bytes: pageEstimate,
        js_heap_bytes: performance.memory?.usedJSHeapSize ?? null,
      };
    });
  }
  report.memory = { after_boot: await sampleMemory() };

  async function clickScene(x, y, screen) {
    const previous = await page.evaluate(name =>
      (window.qqLoadMetrics || []).filter(entry => entry.event === 'scene_transition' && entry.details.screen === name).length,
      screen);
    const startedAt = Date.now();
    await page.mouse.click(x, y);
    await page.waitForFunction(({ name, count }) =>
      (window.qqLoadMetrics || []).filter(entry => entry.event === 'scene_transition' && entry.details.screen === name).length > count,
      { name: screen, count: previous }, { timeout: 30000 });
    const metric = await page.evaluate(name =>
      (window.qqLoadMetrics || []).filter(entry => entry.event === 'scene_transition' && entry.details.screen === name).at(-1),
      screen);
    report.transitions.push({ screen, click_to_visible_ms: Date.now() - startedAt, game_elapsed_ms: metric.elapsed_ms });
  }

  await clickScene(720, 498, 'BattleTutorial');
  await clickScene(1290, 264, 'Battle');
  report.memory.after_first_battle = await sampleMemory();
  await clickScene(1360, 74, 'BattleTutorial');
  await clickScene(1290, 264, 'Battle');
  report.memory.after_second_battle = await sampleMemory();
  await clickScene(1360, 74, 'BattleTutorial');
  await clickScene(1325, 117, 'Hub');
  await page.screenshot({ path: resolve(output, 'hub.png') });
  await clickScene(720, 581, 'CardLibrary');
  await page.waitForFunction(() => window.qqLoadMetrics?.some(entry => entry.event === 'library_initial'), undefined, { timeout: 30000 });
  await page.screenshot({ path: resolve(output, 'library-initial.png') });
  const initialLibrary = await page.evaluate(() => window.qqLoadMetrics.filter(entry => entry.event === 'library_initial').at(-1));
  assert(initialLibrary.details.built > 0 && initialLibrary.details.built < initialLibrary.details.total,
    'The library did not defer offscreen cards');
  report.memory.after_library_initial = await sampleMemory();
  await page.mouse.move(1000, 720);
  await page.mouse.wheel(0, 1700);
  await page.waitForFunction(initial =>
    window.qqLoadMetrics?.some(entry => entry.event === 'library_page' && entry.details.built > initial),
    initialLibrary.details.built, { timeout: 30000 });
  await page.screenshot({ path: resolve(output, 'library-scrolled.png') });
  report.memory.after_library_scroll = await sampleMemory();
  report.game_metrics = await page.evaluate(() => window.qqLoadMetrics || []);
  report.pack_resource = await page.evaluate(() => {
    const entry = performance.getEntriesByType('resource').find(item => item.name.endsWith('/index.pck'));
    return entry ? { duration_ms: entry.duration, transfer_bytes: entry.transferSize, decoded_bytes: entry.decodedBodySize } : null;
  });
  if (errors.length) throw new Error(JSON.stringify(errors));
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(`WEB_LOAD_METRICS_OK ${JSON.stringify({ boot_wall_ms: report.boot_wall_ms, transitions: report.transitions, pack_resource: report.pack_resource, memory: report.memory })}`);
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
