import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/grade-five/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], checks = [];
let sequence = 0;
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/.test(message.text())) errors.push(message.text()); });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  async function boot() {
    await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
    await page.waitForSelector('#status', { state: 'detached' });
  }
  await boot();
  async function command(action, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function waitFor(predicate) {
    for (let i = 0; i < 100; i++) {
      const state = await command('inspect');
      if (predicate(state)) return state;
      await page.waitForTimeout(100);
    }
    throw new Error('Grade lab state timed out');
  }
  function control(state, id) {
    const found = state.controls.find(item => item.name === id);
    assert(found, `Missing ${id}`);
    return found.rect;
  }
  async function click(state, rect, fraction = 0.5) {
    const box = await page.locator('#canvas').boundingBox();
    await page.mouse.click(box.x + (rect[0] + rect[2] * fraction) * box.width / state.viewport[0], box.y + (rect[1] + rect[3] / 2) * box.height / state.viewport[1]);
  }
  async function button(state, id) { await click(state, control(state, id)); return command('inspect'); }
  async function typeLive(state, path, text) {
    await command('balance_focus', { path }); state = await command('inspect');
    await click(state, state.balance.fields[path].edit_rect, 0.4);
    await command('inspect');
    await page.keyboard.press('Control+A'); await page.waitForTimeout(30);
    await page.keyboard.type(text, { delay: 70 });
    // Deliberately do not press Enter or move focus.
    return command('inspect');
  }
  let state = await command('screen', { screen: 'balance' });
  state = await waitFor(state => state.balance?.ready);
  const beforeHash = state.balance.game_hash;
  assert.equal(state.balance.grade_tabs.length, 6);
  for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size); state = await command('inspect');
    for (const tab of state.balance.grade_tabs) {
      const [x, y, w, h] = tab.rect;
      assert(x >= 0 && y >= 0 && x + w <= state.viewport[0] + 1 && y + h <= state.viewport[1] + 1, 'Grade tabs clipped');
    }
    await page.screenshot({ path: resolve(output, `tabs-${size.width}.png`) });
  }
  await page.setViewportSize({ width: 1440, height: 900 }); state = await command('inspect');
  await click(state, state.balance.grade_tabs[5].rect); state = await command('inspect');
  assert.equal(state.balance.editor_grade, 5);
  assert.equal(state.balance.config.grade, 5);
  await click(state, control(state, 'BalanceTimeLimit'), 0.35);
  await command('inspect');
  await page.keyboard.press('Control+A');
  await page.keyboard.type('10', { delay: 70 });
  state = await command('inspect');
  assert.equal(state.balance.config.limit, 10, 'Typing a minimum-bound number was clamped mid-input');
  const amountPath = 'grade_overrides.5.effects.0.amount';
  state = await typeLive(state, amountPath, '77');
  assert(state.balance.document.changes.some(item => item.path === amountPath && item.after === 77), 'Live integer typing did not apply');
  assert(state.balance.grade_previews['5'].includes('80'), 'Live preview did not include attack');
  assert(state.balance.grade_previews['4'].includes('11'), 'Another grade changed unexpectedly');
  state = await button(state, 'BalanceChangedOnly');
  state = await typeLive(state, amountPath, '9');
  assert(state.balance.fields[amountPath], 'Changed-only filtering removed the active editor while typing');
  assert.equal(state.balance.fields[amountPath].text, '9');
  state = await typeLive(state, amountPath, '77');
  assert(state.balance.document.changes.some(item => item.path === amountPath && item.after === 77), 'Changed-only filtering interrupted live typing');
  state = await button(state, 'BalanceChangedOnly');
  state = await typeLive(state, 'grade_overrides.5.recast_time', '4.75');
  await writeFile(resolve(output, 'live-state.json'), JSON.stringify(state.balance, null, 2));
  assert(state.balance.document.changes.some(item => item.path === 'grade_overrides.5.recast_time' && item.after === 4.75), 'Live decimal typing required Enter');
  await page.screenshot({ path: resolve(output, 'live-grade5.png') });
  await click(state, state.balance.grade_tabs[4].rect); state = await command('inspect');
  assert.equal(state.balance.fields['grade_overrides.4.effects.0.amount'].value, 8);
  await click(state, state.balance.grade_tabs[5].rect); state = await command('inspect');
  assert.equal(state.balance.fields[amountPath].value, 77);
  state = await button(state, 'BalanceManualAfter');
  state = await waitFor(state => Boolean(state.balance?.manual));
  assert.equal(state.balance.manual.damage, 77);
  assert.equal(state.balance.published_damage, 4);
  state = await button(state, 'BalanceManualClose');
  state = await waitFor(state => !state.balance?.manual);
  assert.equal(state.balance.game_hash, beforeHash);
  const downloadPromise = page.waitForEvent('download');
  state = await button(state, 'BalanceExport');
  const download = await downloadPromise; const path = resolve(output, 'grade-diff.json'); await download.saveAs(path);
  const document = JSON.parse(await readFile(path, 'utf8'));
  assert.equal(document.format, 'queuequest-balance-diff-v2');
  assert(document.changes.some(item => item.path === amountPath));
  await page.waitForTimeout(1200); await page.reload(); await boot();
  state = await command('balance_open'); state = await waitFor(state => state.balance?.ready);
  await click(state, state.balance.grade_tabs[5].rect); state = await command('inspect');
  assert.equal(state.balance.fields[amountPath].value, 77, 'Grade override lost after reload');
  state = await button(state, 'BalanceResetGrade');
  assert.equal(state.balance.fields[amountPath].value, 9);
  checks.push('six_tabs_three_sizes_live_integer_decimal_changed_filter_grade_isolation_manual_export_reload_reset');
  assert.deepEqual(errors, []);
  console.log('WEB_GRADE_FIVE_REVIEW_OK', checks);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ checks, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
