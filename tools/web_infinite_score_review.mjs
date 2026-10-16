import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/infinite-score-tests/browser');
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
  for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    for (const screen of ['result_infinite', 'result_infinite_record', 'result_infinite_empty', 'result']) {
      await command('screen', { screen });
      if (screen === 'result_infinite') await page.waitForTimeout(4600);
      else await command('finish_score');
      const state = await command('inspect');
      const [width, height] = state.viewport;
      const overflow = state.controls.filter(item => {
        const [x, y, w, h] = item.rect;
        return !item.scroll && w > 1 && h > 1 && (x < -2 || y < -2 || x + w > width + 2 || y + h > height + 2);
      });
      assert.deepEqual(overflow, [], `Result viewport overflow in ${screen}`);
      if (screen === 'result') {
        assert.equal(state.score.max_score, 10000);
        assert.match(state.score_ui.total, /\/ 10,000$/);
        assert(['S', 'A', 'B', 'C', 'D', 'E'].includes(state.score_ui.reach));
      } else {
        assert.equal(state.score.max_score, 0);
        assert.equal(state.score.rank, '');
        assert(!state.score_ui.total.includes('/'));
        assert.deepEqual(state.score_ui.bars.map(bar => bar.id), ['progress', 'boss', 'challenge', 'efficiency']);
        for (const bar of state.score_ui.bars) {
          assert.equal(bar.value, state.score[bar.id]);
          assert.equal(bar.max, Math.max(1, state.score.total_score));
          assert(!bar.label.includes('/'));
        }
        if (screen === 'result_infinite_empty') assert.equal(state.score.total_score, 0);
        else assert(state.score.total_score > 10000);
        if (screen === 'result_infinite_record') {
          assert(state.score.is_new_record);
          assert.equal(state.score.high_score, state.score.total_score);
          assert(state.score_ui.record.includes('自己ベスト更新'));
        }
        if (screen === 'result_infinite') assert(state.score_ui.record.includes('記録対象外'));
      }
      await page.screenshot({ path: resolve(output, `${screen}-${viewport.width}x${viewport.height}.png`) });
      cases.push({ screen, viewport, score: state.score, ui: state.score_ui });
    }
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_INFINITE_SCORE_OK', JSON.stringify({ layouts: cases.length, errors }));
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
