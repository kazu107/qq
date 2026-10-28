import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/scrollbar-skin/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true, ignoreDefaultArgs: ['--hide-scrollbars'] });
const errors = [], cases = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text())) errors.push(message.text()); });
  let sequence = 0;
  async function command(action = 'inspect', extra = {}) {
    const seq = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: seq });
    await page.waitForFunction(value => JSON.parse(window.qqLayoutState || '{}').sequence === value, seq);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function point(state, x, y) {
    const box = await page.locator('#canvas').boundingBox();
    return { x: box.x + x * box.width / state.viewport[0], y: box.y + y * box.height / state.viewport[1] };
  }
  async function click(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, name);
    const [x, y, w, h] = control.rect, position = await point(state, x + w / 2, y + h / 2);
    await page.mouse.click(position.x, position.y);
    await page.waitForTimeout(140);
    return command();
  }
  async function verify(label, owner) {
    await page.waitForTimeout(160);
    const state = await command();
    const bars = state.scroll_bars.filter(bar => bar.max > bar.page + 1 && (!owner || bar.owner === owner));
    assert(bars.length, label + ': no overflow bar found');
    for (const bar of bars) {
      assert.equal(bar.rect[bar.horizontal ? 3 : 2], 14, label + ': invisible or oversized bar');
      assert.equal(bar.texture, `res://assets/icons/controls/scrollbar_${bar.horizontal ? 'h' : 'v'}_grabber.png`);
    }
    cases.push({ label, bars });
    await page.screenshot({ path: resolve(output, `${label}.png`) });
    return state;
  }
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  let state = await click(await command(), 'HubMetaProgressButton');
  state = await verify('meta', 'MetaWindowScroll');
  const bar = state.scroll_bars.find(item => item.owner === 'MetaWindowScroll');
  const [x, y, w, h] = bar.rect;
  const thumb = Math.max(32, h * bar.page / bar.max);
  const start = await point(state, x + w / 2, y + 5 + thumb / 2);
  const end = await point(state, x + w / 2, y + Math.min(h - 12, 5 + thumb / 2 + h * .45));
  await page.mouse.move(start.x, start.y);
  await page.screenshot({ path: resolve(output, 'meta-hover.png') });
  await page.mouse.down();
  await page.mouse.move(end.x, end.y, { steps: 8 });
  await page.screenshot({ path: resolve(output, 'meta-pressed.png') });
  await page.mouse.up();
  state = await command();
  assert(state.scroll_bars.find(item => item.owner === 'MetaWindowScroll').value > bar.value + 50, 'Dragging the thumb did not scroll');
  await page.keyboard.press('Escape');
  state = await click(await command(), 'VersionHistoryButton');
  await verify('history', 'VersionHistoryContent');
  await page.keyboard.press('Escape');
  state = await click(await command(), 'BattleTutorialButton');
  await verify('tutorials', 'TutorialScroll');
  await page.keyboard.press('Escape');
  await command('screen', { screen: 'library' });
  await page.waitForTimeout(700);
  await verify('library');
  for (const screen of ['map', 'arena']) {
    await command('screen', { screen });
    await command('scroll_bar_inventory_fixture');
    await verify(screen);
  }
  await command('screen', { screen: 'battle' });
  state = await command('scroll_bar_log_fixture');
  state = await click(state, 'BattleLogButton');
  await verify('battle-log', 'BattleLogText');
  await command('screen', { screen: 'hub_developer' });
  await verify('developer', 'DeveloperActionsScroll');
  state = await command('wheel_fixture_focus', { name: 'DebugCardSlot0' });
  state = await click(state, 'DebugCardSlot0');
  await verify('picker', 'CardIconPickerScroll');
  await page.keyboard.press('Escape');
  await command('screen', { screen: 'hub' });
  state = await click(await command(), 'HubMetaProgressButton');
  for (const viewport of [{ width: 960, height: 600 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(viewport);
    await verify(`meta-${viewport.width}`, 'MetaWindowScroll');
  }
  const dom = await browser.newPage({ viewport: { width: 900, height: 650 } });
  const webAssets = new Set();
  dom.on('response', response => { if (response.ok() && response.url().includes('/account/scrollbars/')) webAssets.add(new URL(response.url()).pathname.split('/').at(-1)); });
  dom.on('pageerror', error => errors.push(String(error)));
  await dom.goto(`http://127.0.0.1:${app.server.address().port}/account?lang=en`);
  await dom.evaluate(() => {
    const fixture = document.createElement('div');
    fixture.id = 'scrollbarFixture';
    fixture.style.cssText = 'position:fixed;inset:60px 100px;background:#10212d;overflow:scroll;z-index:10';
    const content = document.createElement('div');
    content.style.cssText = 'width:1400px;height:1800px;padding:30px';
    content.textContent = 'Scroll bar / Blender rail and thumb';
    fixture.append(content); document.body.append(fixture);
  });
  assert.equal(await dom.locator('#scrollbarFixture').evaluate(element => getComputedStyle(element, '::-webkit-scrollbar').width), '12px');
  assert.equal(await dom.locator('#scrollbarFixture').evaluate(element => element.offsetWidth - element.clientWidth), 12);
  await dom.waitForTimeout(300);
  for (const file of ['scrollbar_v_track.png', 'scrollbar_h_track.png', 'scrollbar_v_grabber.png', 'scrollbar_h_grabber.png']) assert(webAssets.has(file), 'Web panel did not paint ' + file);
  await dom.screenshot({ path: resolve(output, 'web-panels.png') });
  await dom.locator('#scrollbarFixture').hover();
  await dom.mouse.wheel(0, 180);
  await dom.waitForTimeout(300);
  assert((await dom.locator('#scrollbarFixture').evaluate(element => element.scrollTop)) > 0);
  await dom.close();
  assert.deepEqual(errors, []);
  console.log('WEB_SCROLLBAR_SKIN_OK', JSON.stringify({ cases: cases.map(item => item.label), drag: true, webPanels: true, errors }));
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close(); app.server.closeAllConnections(); await new Promise(done => app.server.close(done));
}
