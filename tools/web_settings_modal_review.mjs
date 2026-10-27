import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const out = resolve('tools/.local/settings-modal/browser');
await mkdir(out, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text())) errors.push(message.text()); });
  const url = `http://127.0.0.1:${app.server.address().port}/?pack=local`;
  async function ready() {
    await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
    await page.waitForSelector('#status', { state: 'detached' });
  }
  let sequence = 0;
  async function inspect() {
    const seq = ++sequence;
    await page.evaluate(value => window.qqLayoutCommand(JSON.stringify({ action: 'inspect', sequence: value })), seq);
    await page.waitForFunction(value => JSON.parse(window.qqLayoutState || '{}').sequence === value, seq);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function click(state, name) {
    const control = state.controls.find(control => control.name === name);
    assert(control, name);
    const canvas = await page.locator('#canvas').boundingBox(), [x,y,w,h] = control.rect;
    await page.mouse.click(canvas.x + (x + w / 2) * canvas.width / state.viewport[0], canvas.y + (y + h / 2) * canvas.height / state.viewport[1]);
    await page.waitForTimeout(150);
    return inspect();
  }
  await page.goto(url, { waitUntil: 'commit' }); await ready();
  let state = await inspect();
  const hub = state.screen_instance;
  state = await click(state, 'OpenSettingsButton');
  assert(state.settings_modal.visible); assert.equal(state.screen_instance, hub); assert.equal(state.settings_modal.hint, 'hub');
  await page.screenshot({ path: resolve(out, 'initial.png') });
  const cached = state.settings_modal.instance;
  for (let index = 0; index < 20; index++) {
    await page.keyboard.press(index < 10 ? 'Tab' : 'Shift+Tab');
    state = await inspect(); assert(state.settings_modal.focus_inside, 'Focus escaped the modal');
  }
  state = await click(state, 'MasterVolumeSlider');
  await page.keyboard.press('Home'); for (let index = 0; index < 7; index++) await page.keyboard.press('ArrowRight');
  state = await inspect(); assert(Math.abs(state.settings_modal.master - .35) < .001);
  state = await click(state, 'SfxVolumeSlider');
  await page.keyboard.press('Home'); for (let index = 0; index < 9; index++) await page.keyboard.press('ArrowRight');
  state = await inspect(); assert(Math.abs(state.settings_modal.sfx - .45) < .001);
  await page.screenshot({ path: resolve(out, 'ja-desktop.png') });
  state = await click(state, 'LanguageOptionButton');
  await page.screenshot({ path: resolve(out, 'language-menu.png') });
  const languageControl = state.controls.find(control => control.name === 'LanguageOptionButton');
  const canvas = await page.locator('#canvas').boundingBox();
  const [lx,ly,lw,lh] = languageControl.rect;
  await page.mouse.click(canvas.x + (lx + lw / 2) * canvas.width / state.viewport[0], canvas.y + (ly + lh + 26) * canvas.height / state.viewport[1]);
  await page.waitForTimeout(350);
  state = await inspect(); assert.equal(state.settings_modal.language, 'en'); assert(state.settings_modal.visible);
  assert.equal(state.screen_instance, hub);
  state = await click(state, 'SettingsCloseButton');
  assert.equal(state.settings_modal.visible, false); assert.equal(state.screen_instance, hub);
  assert.equal(state.controls.find(control => control.name === 'RunStartButton').text, 'New Game');
  state = await click(state, 'OpenSettingsButton'); assert.equal(state.settings_modal.instance, cached);
  for (const size of [{ width: 1440, height: 900 }, { width: 1280, height: 720 }, { width: 960, height: 600 }, { width: 900, height: 1200 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(size); await page.waitForTimeout(300); state = await inspect();
    const [x,y,w,h] = state.settings_modal.rect;
    assert(x >= 0 && y >= 0 && x + w <= state.viewport[0] + 1 && y + h <= state.viewport[1] + 1, 'Modal is outside viewport');
    assert(state.settings_modal.horizontal_overflow <= 1, 'Settings body has horizontal overflow');
    assert(state.controls.some(control => control.name === 'SettingsCloseButton'));
    assert(state.controls.some(control => control.name === 'SettingsBackButton'));
    await page.screenshot({ path: resolve(out, `en-${size.width}x${size.height}.png`) });
    cases.push(`${size.width}x${size.height}: modal fits, no horizontal overflow, close remains visible`);
  }
  await page.keyboard.press('Escape'); await page.waitForTimeout(150); state = await inspect();
  assert(!state.settings_modal.visible); assert.equal(state.screen_instance, hub);
  await page.setViewportSize({ width: 1440, height: 900 }); await page.waitForTimeout(200);
  state = await inspect(); state = await click(state, 'OpenSettingsButton');
  await page.mouse.click(10,10); await page.waitForTimeout(150); state = await inspect();
  assert(!state.settings_modal.visible); assert.equal(state.screen_instance, hub);
  await page.reload({ waitUntil: 'commit' }); await ready();
  state = await click(await inspect(), 'OpenSettingsButton');
  assert.equal(state.settings_modal.language, 'en');
  assert(Math.abs(state.settings_modal.master - .35) < .001 && Math.abs(state.settings_modal.sfx - .45) < .001);
  assert.deepEqual(errors, []);
  console.log('WEB_SETTINGS_MODAL_OK', JSON.stringify({ cases, checks: 'same-scene/cached-instance/tab-focus/real-dropdown/localized-Hub/Escape/backdrop/persisted-after-reload', errors }));
} finally {
  await writeFile(resolve(out, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close(); app.server.closeAllConnections(); await new Promise(done => app.server.close(done));
}
