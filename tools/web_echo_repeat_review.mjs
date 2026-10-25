import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/echo-repeat/browser'); await mkdir(output, { recursive: true });
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
    let state;
    for (let i = 0; i < 150; i++) { state = await command('inspect'); if (predicate(state)) return state; await page.waitForTimeout(100); }
    await writeFile(resolve(output, 'timeout.json'), JSON.stringify(state, null, 2));
    await page.screenshot({ path: resolve(output, 'timeout.png') }); throw new Error('Echo view timed out');
  }
  async function point(state, x, y, click = true) {
    const box = await page.locator('#canvas').boundingBox();
    const px = box.x + x * box.width / state.viewport[0], py = box.y + y * box.height / state.viewport[1];
    if (click) await page.mouse.click(px, py); else await page.mouse.move(px, py);
    return command('inspect');
  }
  async function button(state, id) {
    const control = state.controls.find(item => item.name === id); assert(control, `Missing ${id}`);
    return point(state, control.rect[0] + control.rect[2] / 2, control.rect[1] + control.rect[3] / 2);
  }
  async function card(state, id) {
    const item = state.echo.hand.find(item => item.id === id); assert(item);
    return point(state, item.rect[0] + item.rect[2] / 2, item.rect[1] + item.rect[3] / 2);
  }
  for (const language of ['ja', 'en']) {
    await command('echo_fixture', { language });
    let state = await until(state => state.screen === 'Battle' && state.echo?.hand.length === 4);
    state = await command('echo_control', { setup: true });
    state = await card(state, 'heavy_swing'); state = await card(state, 'echo_cast');
    assert.equal(state.echo.charges, 0);
    state = await command('echo_control', { seconds: 2.4 });
    assert.equal(state.echo.charges, 1);
    const heavy = state.echo.hand.find(item => item.id === 'heavy_swing').runtime;
    const quick = state.echo.hand.find(item => item.id === 'quick_slash').runtime;
    assert(state.echo.timeline.find(item => item.runtime === heavy).repeat);
    state = await card(state, 'quick_slash');
    assert(state.echo.timeline.find(item => item.runtime === quick).repeat && !state.echo.timeline.find(item => item.runtime === heavy).repeat);
    state = await command('echo_control', { delay: 20 });
    assert(state.echo.timeline.find(item => item.runtime === heavy).repeat && !state.echo.timeline.find(item => item.runtime === quick).repeat);
    state = await button(state, 'DeveloperPanelToggle');
    for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
      await page.setViewportSize(size); state = await command('inspect');
      const points = state.echo.status_regions[0].points;
      state = await point(state, points.reduce((n, p) => n + p[0], 0) / points.length, points.reduce((n, p) => n + p[1], 0) / points.length, false);
      state = await until(state => state.echo.tooltip !== '');
      assert(state.echo.tooltip.includes(language === 'ja' ? '残り1/3' : '1/3 charges'));
      const popup = state.controls.find(item => item.name === 'WorldStatusTooltip'); assert(popup);
      const [x, y, w, h] = popup.rect;
      assert(x >= 0 && y >= 0 && x + w <= state.viewport[0] + 1 && y + h <= state.viewport[1] + 1, 'Echo tooltip clipped');
      await page.screenshot({ path: resolve(output, `candidate-${language}-${size.width}.png`) });
    }
    await page.setViewportSize({ width: 1440, height: 900 });
    state = await command('echo_control', { seconds: 10.8 });
    assert.equal(state.echo.enemy_hp, 466); assert.equal(state.echo.charges, 0);
    state = await until(state => state.echo.numbers.filter(value => value === '-17').length === 2);
    await page.screenshot({ path: resolve(output, `two-hits-${language}.png`) });
    state = await button(state, 'DeveloperPanelToggle');
    state = await button(state, 'DevEchoReady'); assert.equal(state.echo.charges, 1);
    state = await button(state, 'DevEchoClear'); assert.equal(state.echo.charges, 0);
    checks.push(`${language}:real_card_input_already_casting_dynamic_candidate_3_sizes_hover_two_hits_debug`);
  }
  assert.deepEqual(errors, []); console.log('WEB_ECHO_REPEAT_REVIEW_OK', checks);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ checks, errors }, null, 2));
  await browser.close(); await new Promise(done => app.server.close(done));
}
