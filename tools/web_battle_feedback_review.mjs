import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/battle-feedback-tests/browser');
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
    await command('screen', { screen: 'battle' });
    await page.waitForTimeout(700);
    // Warm first-use WebGL effect pipelines before measuring a 200ms UI transition.
    await command('feedback_damage');
    await page.waitForTimeout(1500);
    await command('feedback_damage');
    await page.waitForTimeout(1100);
    const state = await command('inspect');
    const feedback = state.feedback;
    const samples = feedback.samples;
    await writeFile(resolve(output, `samples-${viewport.width}x${viewport.height}.json`), JSON.stringify(feedback, null, 2));
    await page.screenshot({ path: resolve(output, `battle-${viewport.width}x${viewport.height}.png`) });
    assert.deepEqual(feedback.immediate_audio, ['card_strike'], 'Resolution SE did not play immediately');
    assert.deepEqual(feedback.audio, ['card_strike'], 'Visual marker replayed resolution SE');
    assert(samples.length >= 5, 'Too few HP animation frames');
    assert.equal(samples[0].displayed, 1, 'HP fill jumped on damage');
    assert.equal(samples[0].target, 0.5);
    assert.match(samples[0].text, /^30 \/ 60$/);
    const middle = samples.filter(sample => sample.ms >= 65 && sample.ms <= 150);
    assert(middle.length > 0, 'Missing intermediate animation frames');
    for (const sample of middle) {
      assert(Math.abs(sample.displayed - (1 - Math.min(200, sample.ms) / 400)) < 0.13, `HP animation timing drift: ${JSON.stringify(sample)}`);
    }
    assert(samples.some(sample => sample.displayed > 0.5 && sample.displayed < 1), 'HP change was not animated');
    assert(samples.some(sample => sample.ms >= 200 && sample.ms <= 300 && sample.displayed === 0.5), 'HP did not reach target in 200ms');
    assert(samples.every((sample, index) => index === 0 || sample.displayed <= samples[index - 1].displayed), 'HP fill reversed during damage');
    cases.push({ viewport, feedback });
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_BATTLE_FEEDBACK_OK', JSON.stringify({ cases: cases.map(item => ({ viewport: item.viewport, frames: item.feedback.samples.length })), errors }));
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
