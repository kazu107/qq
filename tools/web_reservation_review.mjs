import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright');
const output = resolve('tools/.local/reservations/browser'); await mkdir(output, { recursive: true });
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
    const seq = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: seq });
    await page.waitForFunction(expected => JSON.parse(window.qqLayoutState || '{}').sequence === expected, seq);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function until(predicate) {
    for (let i = 0; i < 150; i++) { const state = await command('inspect'); if (predicate(state)) return state; await page.waitForTimeout(100); }
    throw new Error('Reservation view timed out');
  }
  async function point(state, x, y, click = true) {
    const box = await page.locator('#canvas').boundingBox();
    const px = box.x + x * box.width / state.viewport[0], py = box.y + y * box.height / state.viewport[1];
    if (click) await page.mouse.click(px, py); else await page.mouse.move(px, py);
    return command('inspect');
  }
  async function button(state, id) {
    const control = state.controls.find(item => item.name === id); assert(control, id);
    return point(state, control.rect[0] + control.rect[2] / 2, control.rect[1] + control.rect[3] / 2);
  }
  async function card(state, id) {
    const item = state.echo.hand.find(item => item.id === id); assert(item, id);
    return point(state, item.rect[0] + item.rect[2] / 2, item.rect[1] + item.rect[3] / 2);
  }
  for (const language of ['ja', 'en']) {
    await command('echo_fixture', { language });
    let state = await until(state => state.screen === 'Battle' && state.echo?.hand.length === 4);
    state = await command('echo_control', { setup: true });
    state = await card(state, 'heavy_swing');
    state = await command('reservation_control', { player: ['focus', 'reload', 'weaken', 'recast_jam'] });
    assert.equal(state.echo.pending, 4);
    const heavy = state.echo.hand.find(item => item.id === 'heavy_swing').runtime;
    const quick = state.echo.hand.find(item => item.id === 'quick_slash').runtime;
    assert(state.echo.timeline.find(item => item.runtime === heavy).reserved);
    state = await card(state, 'quick_slash');
    assert(state.echo.timeline.find(item => item.runtime === quick).reserved && !state.echo.timeline.find(item => item.runtime === heavy).reserved);
    state = await command('echo_control', { delay: 20 });
    assert(state.echo.timeline.find(item => item.runtime === heavy).reserved && !state.echo.timeline.find(item => item.runtime === quick).reserved);
    state = await button(state, 'DeveloperPanelToggle');
    for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
      await page.setViewportSize(size); state = await command('inspect');
      for (const id of ['reservation_boost', 'reservation_hex']) {
        const points = state.echo.status_regions.find(region => region.id === id).points;
        state = await point(state, points.reduce((n, p) => n + p[0], 0) / points.length, points.reduce((n, p) => n + p[1], 0) / points.length, false);
        state = await until(state => state.echo.tooltip !== '');
        assert(state.echo.tooltip.toLowerCase().includes(language === 'ja' ? '予約' : 'manual'));
        const popup = state.controls.find(item => item.name === 'WorldStatusTooltip'); assert(popup);
        const [x, y, w, h] = popup.rect;
        assert(x >= 0 && y >= 0 && x + w <= state.viewport[0] + 1 && y + h <= state.viewport[1] + 1, `Tooltip clipped ${language} ${id}`);
      }
      await page.screenshot({ path: resolve(output, `reservation-${language}-${size.width}.png`) });
    }
    await page.setViewportSize({ width: 1440, height: 900 });
    state = await command('echo_control', { seconds: 13.2 });
    assert.equal(state.echo.enemy_hp, 485); assert.equal(state.echo.pending, 0);
    assert.equal(state.echo.hand.find(item => item.id === 'heavy_swing').cooldown, 19);
    state = await until(state => state.echo.numbers.includes('-15'));
    await page.screenshot({ path: resolve(output, `resolved-${language}.png`) });
    state = await button(state, 'DeveloperPanelToggle');
    state = await button(state, 'DevReserveSelf'); assert.equal(state.echo.pending, 1);
    state = await button(state, 'DevReserveEnemy'); assert.equal(state.echo.enemy_pending, 1);
    state = await button(state, 'DevReserveClear'); assert.equal(state.echo.pending + state.echo.enemy_pending, 0);
    checks.push(`${language}:real_input_dynamic_targets_combined_effects_3_sizes_hover_developer`);
  }
  assert.deepEqual(errors, []); console.log('WEB_RESERVATION_REVIEW_OK', checks);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ checks, errors }, null, 2));
  await browser.close(); await new Promise(done => app.server.close(done));
}
