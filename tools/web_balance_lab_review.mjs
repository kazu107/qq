import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/balance-lab/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], checks = [];
let sequence = 0;
try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
  const page = await context.newPage();
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
  async function inspectUntil(predicate) {
    let last;
    for (let attempt = 0; attempt < 100; attempt++) {
      const state = await command('inspect');
      last = state;
      if (predicate(state)) return state;
      await page.waitForTimeout(100);
    }
    await writeFile(resolve(output, 'timeout-state.json'), JSON.stringify(last.balance, null, 2));
    throw new Error('Balance Lab did not reach expected state');
  }
  function control(state, name) {
    const found = state.controls.find(item => item.name === name);
    assert(found, `Missing ${name}`);
    return found.rect;
  }
  async function click(state, rect, xFraction = 0.5) {
    const box = await page.locator('#canvas').boundingBox();
    await page.mouse.click(box.x + (rect[0] + rect[2] * xFraction) * box.width / state.viewport[0], box.y + (rect[1] + rect[3] / 2) * box.height / state.viewport[1]);
  }
  async function button(state, name) {
    await click(state, control(state, name));
    return command('inspect');
  }
  async function typeValue(state, name, value) {
    await click(state, control(state, name), 0.35);
    await command('inspect');
    await page.keyboard.press('Control+A');
    await page.waitForTimeout(30);
    await page.keyboard.type(String(value), { delay: 20 });
    await page.keyboard.press('Enter');
    return command('inspect');
  }
  async function search(state, text) {
    await typeValue(state, 'BalanceSearch', text);
    await page.waitForTimeout(250);
    return command('inspect');
  }
  let state = await command('screen', { screen: 'balance' });
  state = await inspectUntil(state => state.balance?.ready);
  const initialHash = state.balance.game_hash;
  assert.equal(state.balance.published_damage, 4);
  assert(state.balance.entries.length >= 93);
  for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size);
    state = await command('inspect');
    const overflow = state.controls.filter(item => !item.scroll && item.rect[2] > 1 && item.rect[3] > 1 &&
      (item.rect[0] < -2 || item.rect[1] < -2 || item.rect[0] + item.rect[2] > state.viewport[0] + 2 || item.rect[1] + item.rect[3] > state.viewport[1] + 2));
    assert.deepEqual(overflow, [], `Lab viewport overflow at ${size.width}`);
    await page.screenshot({ path: resolve(output, `layout-${size.width}x${size.height}.png`) });
  }
  checks.push('three_viewport_layouts');
  await page.setViewportSize({ width: 1440, height: 900 });
  state = await command('inspect');
  state = await search(state, 'quick_slash');
  assert.equal(state.balance.entries.length, 1);
  await command('balance_focus', { path: 'effects.0.amount' });
  state = await command('inspect');
  state = await typeValue(state, 'BalanceValue_effects_0_amount', 9);
  assert(state.balance.document.changes.some(item => item.id === 'quick_slash' && item.path === 'effects.0.amount' && item.after === 9));
  assert.equal(state.balance.published_damage, 4);
  await command('balance_focus', { path: 'recast_time' });
  state = await command('inspect');
  state = await typeValue(state, 'BalanceValue_recast_time', 4.25);
  assert(state.balance.document.changes.some(item => item.path === 'recast_time' && item.after === 4.25));
  await page.screenshot({ path: resolve(output, 'edited-card.png') });
  checks.push('real_pointer_and_keyboard_card_edits');
  state = await button(state, 'BalanceBulk');
  assert(state.controls.some(item => item.name === 'BalanceBulkApply'));
  await click(state, control(state, 'BalanceBulkField'));
  state = await command('inspect');
  for (let i = 0; i < 20 && state.balance.bulk.focused_path !== 'recast_time'; i++) {
    await page.keyboard.press('ArrowDown');
    state = await command('inspect');
  }
  assert.equal(state.balance.bulk.focused_path, 'recast_time');
  await page.keyboard.press('Enter');
  state = await command('inspect');
  state = await typeValue(state, 'BalanceBulkAmount', 0.5);
  await writeFile(resolve(output, 'bulk-before.json'), JSON.stringify(state.balance, null, 2));
  assert(state.balance.document.changes.some(item => item.path === 'recast_time' && item.after === 4.25), 'Bulk preview applied before confirmation');
  state = await button(state, 'BalanceBulkApply');
  await writeFile(resolve(output, 'bulk-after.json'), JSON.stringify(state.balance, null, 2));
  assert(state.balance.document.changes.some(item => item.id === 'quick_slash' && item.path === 'recast_time' && item.after === 2.125));
  checks.push('filtered_bulk_preview_and_explicit_apply');
  state = await button(state, 'BalanceRelicsTab');
  state = await search(state, 'reactive_barrier');
  assert.equal(state.balance.entries.length, 1);
  await command('balance_focus', { path: 'parameters.starting_shield' });
  state = await command('inspect');
  state = await typeValue(state, 'BalanceValue_parameters_starting_shield', 42);
  await writeFile(resolve(output, 'relic-edit-state.json'), JSON.stringify(state.balance, null, 2));
  assert(state.balance.relics.includes('reactive_barrier'));
  state = await button(state, 'BalanceManualAfter');
  state = await inspectUntil(state => Boolean(state.balance?.manual));
  await writeFile(resolve(output, 'manual-state.json'), JSON.stringify(state.balance, null, 2));
  await page.screenshot({ path: resolve(output, 'manual-ready.png') });
  assert.equal(state.balance.manual.shield, 42);
  assert.equal(state.balance.manual.damage, 9);
  assert.equal(state.balance.manual.sandbox, true);
  await page.screenshot({ path: resolve(output, 'manual-ready.png') });
  state = await button(state, 'BalanceManualStart');
  state = await button(state, 'BalanceManualCard_quick_slash');
  await page.waitForTimeout(2200);
  state = await command('inspect');
  assert(state.balance.manual.time > 1);
  await page.screenshot({ path: resolve(output, 'manual-running.png') });
  state = await button(state, 'BalanceManualClose');
  state = await inspectUntil(state => !state.balance?.manual);
  assert.equal(state.balance.game_hash, initialHash);
  checks.push('legacy_relic_edit_and_isolated_manual_battle');
  state = await typeValue(state, 'BalanceMatches', 1);
  assert.equal(state.balance.config.count, 1);
  state = await typeValue(state, 'BalanceTimeLimit', 10);
  assert.equal(state.balance.config.limit, 10);
  state = await button(state, 'BalanceCompare');
  state = await inspectUntil(state => state.balance?.reports?.length === 2 && !state.balance.running && state.balance.reports[1].completed === 1);
  assert.equal(state.balance.reports[0].completed, 1);
  assert.equal(state.balance.game_hash, initialHash);
  await page.screenshot({ path: resolve(output, 'matched-ab-report.png') });
  state = await button(state, 'BalanceCancelCompare');
  checks.push('matched_seed_ab_progress_results_no_progression_mutation');
  state = await typeValue(state, 'BalanceMatches', 200);
  state = await typeValue(state, 'BalanceTimeLimit', 180);
  state = await button(state, 'BalanceCompare');
  state = await button(state, 'BalanceCancelCompare');
  assert.equal(state.balance.running, false);
  assert(state.balance.reports[1].completed < 200);
  checks.push('long_comparison_cancellation');
  const downloadPromise = page.waitForEvent('download');
  await button(state, 'BalanceExport');
  const download = await downloadPromise;
  const path = resolve(output, 'exported-diff.json');
  await download.saveAs(path);
  const document = JSON.parse(await readFile(path, 'utf8'));
  assert.equal(document.format, 'queuequest-balance-diff-v1');
  assert(document.changes.some(item => item.id === 'reactive_barrier' && item.after === 42));
  await page.waitForTimeout(1500);
  await page.reload();
  await boot();
  state = await command('balance_open');
  state = await inspectUntil(state => state.balance?.ready);
  assert.deepEqual(state.balance.document.changes, document.changes, 'Draft lost across browser reload');
  assert.equal(state.balance.published_damage, 4);
  checks.push('json_download_and_device_draft_reload');
  state = await button(state, 'BalanceResetSelected');
  assert(!state.balance.document.changes.some(item => item.id === 'quick_slash'));
  state = await button(state, 'BalanceResetAll');
  await page.keyboard.press('Enter');
  state = await command('inspect');
  assert.equal(state.balance.document.changes.length, 0);
  checks.push('selected_reset_and_confirmed_reset_all');
  assert.deepEqual(errors, []);
  console.log('WEB_BALANCE_LAB_REVIEW_OK', checks);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ checks, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
