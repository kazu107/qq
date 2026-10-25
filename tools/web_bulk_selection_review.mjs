import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/bulk-selection/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], checks = [];
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
  async function until(predicate) {
    let last;
    for (let i = 0; i < 100; i++) {
      const state = await command('inspect');
      last = state;
      if (predicate(state)) return state;
      await page.waitForTimeout(100);
    }
    await writeFile(resolve(output, 'timeout-state.json'), JSON.stringify(last, null, 2));
    await page.screenshot({ path: resolve(output, 'timeout.png') });
    throw new Error('Bulk selection state timed out');
  }
  async function click(state, name, fraction = 0.5) {
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing ${name}`);
    const [x, y, w, h] = control.rect, box = await page.locator('#canvas').boundingBox();
    await page.mouse.click(box.x + (x + w * fraction) * box.width / state.viewport[0], box.y + (y + h / 2) * box.height / state.viewport[1]);
    return command('inspect');
  }
  async function type(state, name, text) {
    await click(state, name, 0.35);
    await page.keyboard.press('Control+A');
    await page.waitForTimeout(35);
    if (text === '') await page.keyboard.press('Backspace');
    else await page.keyboard.type(text, { delay: 40 });
    return command('inspect');
  }
  async function field(state, path) {
    state = await click(state, 'BalanceBulkField');
    await page.keyboard.press('Home');
    state = await command('inspect');
    for (let i = 0; i < 50 && state.balance.bulk.focused_path !== path; i++) {
      await page.keyboard.press('ArrowDown'); state = await command('inspect');
    }
    assert.equal(state.balance.bulk.focused_path, path);
    await page.keyboard.press('Enter');
    return command('inspect');
  }
  await command('screen', { screen: 'balance' });
  let state = await until(state => state.balance?.ready);
  const gameHash = state.balance.game_hash;
  state = await type(state, 'BalanceSearch', 'guard');
  state = await until(state => state.balance.entries.some(entry => entry.id === 'guard') && state.balance.entries.every(entry => entry.id.includes('guard')));
  state = await click(state, 'BalanceBulk');
  state = await field(state, 'recast_time');
  state = await type(state, 'BalanceBulkAmount', '0.5');
  state = await click(state, 'BalanceBulkTarget_guard');
  assert(!state.balance.bulk.targets.find(item => item.id === 'guard').selected);
  assert(state.balance.bulk.targets.find(item => item.id === 'quick_guard').selected);
  assert.equal(state.balance.document.changes.length, 0);
  assert(!/^ガード \/ /m.test(state.balance.bulk.preview));
  const selected = state.balance.bulk.selected;
  state = await type(state, 'BalanceBulkSearch', 'quick_guard');
  assert.equal(state.balance.bulk.selected, selected);
  assert.equal(state.balance.bulk.targets.filter(item => item.visible).length, 1);
  state = await click(state, 'BalanceBulkExcludeAll');
  assert(state.balance.bulk.apply_disabled && state.balance.bulk.selected === 0);
  state = await click(state, 'BalanceBulkIncludeAll');
  assert.equal(state.balance.bulk.selected, state.balance.bulk.eligible);
  await page.screenshot({ path: resolve(output, 'before-search-clear.png') });
  state = await type(state, 'BalanceBulkSearch', '');
  state = await until(state => state.balance.bulk.targets.find(item => item.id === 'guard').visible);
  await writeFile(resolve(output, 'before-apply.json'), JSON.stringify(state.balance, null, 2));
  state = await click(state, 'BalanceBulkTarget_guard');
  for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size); state = await command('inspect');
    const overflow = state.controls.filter(item => !item.scroll && item.rect[2] > 1 && item.rect[3] > 1 &&
      (item.rect[0] < -2 || item.rect[1] < -2 || item.rect[0] + item.rect[2] > state.viewport[0] + 2 || item.rect[1] + item.rect[3] > state.viewport[1] + 2));
    assert.deepEqual(overflow, [], `Bulk dialog overflow at ${size.width}`);
    await page.screenshot({ path: resolve(output, `selection-${size.width}.png`) });
    checks.push(`layout:${size.width}`);
  }
  await page.setViewportSize({ width: 1440, height: 900 }); state = await command('inspect');
  state = await click(state, 'BalanceBulkApply');
  assert(!state.balance.bulk);
  assert(!state.balance.document.changes.some(change => change.id === 'guard' && change.path === 'recast_time'));
  assert(state.balance.document.changes.some(change => change.id === 'quick_guard' && change.path === 'recast_time' && change.after === 8));
  assert.equal(state.balance.game_hash, gameHash);
  const document = state.balance.document;
  state = await click(state, 'BalanceBulk');
  assert(!state.balance.bulk.targets.find(item => item.id === 'guard').selected, 'Exclusion lost on reopen');
  state = await field(state, 'recast_time');
  state = await type(state, 'BalanceBulkAmount', '0.1');
  state = await click(state, 'BalanceBulkCancel');
  assert.deepEqual(state.balance.document, document, 'Cancel applied the preview');
  checks.push('real_pointer_exclude_search_all_none_apply_cancel_reopen_isolation');
  await command('content_fixture', { language: 'en', screen: 'balance' });
  state = await until(state => state.balance?.ready);
  state = await click(state, 'BalanceBulk');
  assert(state.captions.some(text => text.startsWith('Targets ')));
  await page.screenshot({ path: resolve(output, 'selection-en-all.png') });
  state = await click(state, 'BalanceBulkCancel');
  state = await click(state, 'BalanceRelicsTab');
  state = await type(state, 'BalanceSearch', 'reactive_barrier');
  state = await until(state => state.balance.entries.length === 1 && state.balance.selected === 'reactive_barrier');
  state = await click(state, 'BalanceBulk');
  assert(state.balance.bulk.targets[0].selected && state.balance.bulk.targets[0].id === 'reactive_barrier');
  checks.push('english_labels_relic_scope');
  assert.deepEqual(errors, []);
  console.log('WEB_BULK_SELECTION_REVIEW_OK', checks);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ checks, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
