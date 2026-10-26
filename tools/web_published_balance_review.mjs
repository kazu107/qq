import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const document = JSON.parse(await readFile(process.env.QQ_BALANCE_FIXTURE || 'tests/fixtures/published_balance.json', 'utf8'));
const expectedIds = new Set(document.changes.map(change => change.id));
const output = resolve(process.env.QQ_BALANCE_REVIEW_OUTPUT || 'tools/.local/published-balance/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cards = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/.test(message.text())) errors.push(message.text()); });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  let sequence = 0;
  async function command(action, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function inspectUntil(predicate) {
    for (let i = 0; i < 100; i++) {
      const state = await command('inspect');
      if (predicate(state)) return state;
      await page.waitForTimeout(100);
    }
    throw new Error('Published balance view did not become ready');
  }
  async function click(state, rect) {
    const box = await page.locator('#canvas').boundingBox();
    await page.mouse.click(box.x + (rect[0] + rect[2] / 2) * box.width / state.viewport[0], box.y + (rect[1] + rect[3] / 2) * box.height / state.viewport[1]);
    return command('inspect');
  }
  await command('screen', { screen: 'balance' });
  let state = await inspectUntil(state => state.balance?.ready);
  assert.equal(state.balance.document.changes.length, 0);
  for (const id of expectedIds) {
    const search = state.controls.find(control => control.name === 'BalanceSearch');
    assert(search);
    await click(state, search.rect);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(id, { delay: 15 });
    state = await inspectUntil(state => state.balance?.entries.some(entry => entry.id === id));
    state = await click(state, state.balance.entries.find(entry => entry.id === id).rect);
    assert.equal(state.balance.selected, id);
    const values = [];
    for (let grade = 0; grade <= 5; grade++) {
      state = await click(state, state.balance.grade_tabs[grade].rect);
      for (const change of document.changes.filter(change => change.id === id)) {
        const match = /^grade_overrides\.(\d+)\./.exec(change.path);
        if ((match ? Number(match[1]) : 0) !== grade) continue;
        assert.equal(state.balance.fields[change.path]?.value, change.after, `${id}:${change.path}`);
      }
      values.push({ grade, preview: state.balance.grade_previews[String(grade)] });
    }
    assert.equal(state.balance.document.changes.length, 0, 'Published baseline created a draft edit');
    cards.push({ id, values });
    if (id === 'guard' || id === 'heavy_swing') {
      assert(state.balance.grade_previews['5'].includes(id === 'guard' ? '28' : '52'));
      await page.screenshot({ path: resolve(output, `${id}-grade5.png`) });
    }
    if (id === 'echo_cast' || id === 'timekeeper_amplify' || expectedIds.size <= 12) {
      await page.screenshot({ path: resolve(output, `${id}-grade5.png`) });
    }
  }
  assert.equal(cards.length, expectedIds.size);
  assert.deepEqual(errors, []);
  console.log(`WEB_PUBLISHED_BALANCE_REVIEW_OK ${document.changes.length} fields, ${cards.length} cards, ${cards.length * 6} grade tabs, no draft edits or browser errors`);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cards, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
