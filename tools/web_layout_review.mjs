import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright')
  : require('playwright');
const output = resolve('tools/.local/web-layout-review');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
const samples = [];
const sizes = [
  { width: 1440, height: 900 }, { width: 1280, height: 960 },
  { width: 1920, height: 800 }, { width: 1280, height: 720 },
  { width: 960, height: 600 }, { width: 900, height: 1200 },
];
const screens = {
  hub: 'Hub', settings: 'Settings', setup: 'RunSetup', arena_setup: 'RunSetup',
  meta: 'MetaProgress', library: 'CardLibrary', tutorials: 'BattleTutorial', online: 'OnlineLobby',
  map: 'Map', arena: 'Arena', battle: 'Battle', reward: 'Reward', event: 'Facility', result: 'RunResult',
};
let sequence = 0;

try {
  const page = await browser.newPage({ viewport: sizes[0] });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
  });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(metric =>
    metric.event === 'scene_transition' && metric.details.screen === 'Hub'), undefined, { timeout: 90000 });
  await page.waitForSelector('#status', { state: 'detached' });

  async function inspect(action, screen) {
    const requestedSequence = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, screen, sequence: requestedSequence });
    await page.waitForFunction(expected => {
      const state = JSON.parse(window.qqLayoutState || '{}');
      return state.sequence === expected.sequence && (!expected.screen || state.screen === expected.screen);
    }, { sequence: requestedSequence, screen: action === 'screen' ? screens[screen] : '' }, { timeout: 30000 });
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }

  for (const size of sizes) {
    await page.setViewportSize(size);
    for (const screen of process.env.QQ_LAYOUT_SCREENS?.split(',') || Object.keys(screens)) {
      const state = await inspect('screen', screen);
      const [width, height] = state.viewport;
      assert(Math.abs(width / height - size.width / size.height) < 0.002, `Letterboxing remained at ${size.width}x${size.height}`);
      const canvas = await page.locator('#canvas').boundingBox();
      assert(Math.abs(canvas.x) < 1 && Math.abs(canvas.y) < 1 && Math.abs(canvas.width - size.width) < 1 && Math.abs(canvas.height - size.height) < 1);
      const overflow = state.controls.filter(control => {
        if (control.scroll) return false;
        const [x, y, w, h] = control.rect;
        return w > 1 && h > 1 && (x < -2 || y < -2 || x + w > width + 2 || y + h > height + 2);
      });
      const sample = { size, screen, ...state, overflow };
      if (state.battle) {
        for (const [x, y] of state.battle.status_corners) {
          assert(x >= 0 && y >= 0 && x <= width && y <= height, `A 3D status plate was clipped at ${size.width}x${size.height}`);
        }
      }
      samples.push(sample);
      await page.screenshot({ path: resolve(output, `${size.width}x${size.height}-${screen}.png`) });
      console.log(`LAYOUT ${size.width}x${size.height} ${screen} overflow=${overflow.length}`);
    }
  }
  await writeFile(resolve(output, process.env.QQ_LAYOUT_SCREENS ? 'focused-report.json' : 'report.json'), JSON.stringify({ errors, samples }, null, 2));
  assert.deepEqual(errors, []);
  const failures = samples.filter(sample => sample.overflow.length > 0);
  assert.deepEqual(failures.map(sample => ({ size: sample.size, screen: sample.screen, overflow: sample.overflow })), []);
  console.log(`WEB_LAYOUT_REVIEW_OK ${samples.length} screen/size combinations, live resize, no black bands or clipped controls`);
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
