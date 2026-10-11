import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/tutorial-focus-review');
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
  async function command(action, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, sequence: expected, ...extra });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  function bounds(state) {
    const overflow = state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && (x < -2 || y < -2 || x + w > state.viewport[0] + 2 || y + h > state.viewport[1] + 2);
    });
    assert.deepEqual(overflow, []);
  }
  await command('tutorial_start', { tutorial: 'battle_basics' });
  await command('tutorial_seek', { key: 'basic_wait_delay' });
  let state;
  for (let tick = 0; tick < 100; tick++) {
    state = await command('inspect');
    if (state.tutorial.step.key === 'basic_delay_result') break;
  }
  assert.equal(state.tutorial.step.key, 'basic_delay_result');
  const sliding = state.tutorial.samples.filter(sample => sample.sliding);
  assert(sliding.length > 0, 'No rendered delay slide was observed');
  for (const sample of sliding) {
    assert.equal(sample.key, 'basic_wait_delay', 'Result overtook the visible card animation');
    assert.equal(sample.paused, false, 'Animation was frozen by tutorial pause');
  }
  assert.equal(state.tutorial.sliding, false);
  await page.screenshot({ path: resolve(output, 'basics-delay-result.png') });
  cases.push({ lesson: 'basics', slidingFrames: sliding.length, pending: state.tutorial.sliding });
  await command('tutorial_start', { tutorial: 'slots_recast' });
  state = await command('tutorial_seek', { key: 'slots_complete' });
  assert.equal(state.tutorial.step.key, 'slots_complete');
  assert.deepEqual(state.tutorial.focus, [0, 0, 0, 0]);
  await page.screenshot({ path: resolve(output, 'slots-complete.png') });
  cases.push({ lesson: 'slots', focus: state.tutorial.focus });
  for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size);
    await command('tutorial_start', { tutorial: 'combat_exam' });
    state = await command('tutorial_seek', { key: 'exam_battle' });
    assert.equal(state.tutorial.step.key, 'exam_battle');
    assert.equal(state.tutorial.dim, false);
    assert.deepEqual(state.tutorial.focus, [0, 0, 0, 0]);
    bounds(state);
    await page.screenshot({ path: resolve(output, `exam-${size.width}x${size.height}.png`) });
    cases.push({ lesson: 'exam', size, dim: state.tutorial.dim });
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_TUTORIAL_FOCUS_OK', JSON.stringify(cases));
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
