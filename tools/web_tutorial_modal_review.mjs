import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/tutorial-modal/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
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
  async function click(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, name);
    const box = await page.locator('#canvas').boundingBox(), [x, y, w, h] = control.rect;
    await page.mouse.click(box.x + (x + w / 2) * box.width / state.viewport[0], box.y + (y + h / 2) * box.height / state.viewport[1]);
    await page.waitForTimeout(130);
    return command();
  }
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  let state = await command();
  const hub = state.screen_instance;
  state = await click(state, 'BattleTutorialButton');
  assert(state.tutorial_modal.visible && state.tutorial_modal.count === 14);
  assert.equal(state.screen_instance, hub);
  assert.equal(state.tutorial_modal.hint, 'hub');
  const content = state.tutorial_modal.content_instance;
  await page.screenshot({ path: resolve(output, 'ja-desktop.png') });
  for (let i = 0; i < 12; i++) {
    await page.keyboard.press(i < 6 ? 'Tab' : 'Shift+Tab');
    state = await command();
    assert(state.tutorial_modal.focus_inside, 'Tab focus escaped the tutorial');
  }
  for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(viewport);
    await page.waitForTimeout(220);
    state = await command();
    const [x, y, w, h] = state.tutorial_modal.rect;
    assert(x >= 0 && y >= 0 && x + w <= state.viewport[0] + 1 && y + h <= state.viewport[1] + 1, 'Tutorial frame outside viewport');
    assert(state.tutorial_modal.horizontal_overflow <= 1, 'Tutorial horizontal overflow');
    await page.screenshot({ path: resolve(output, `ja-${viewport.width}x${viewport.height}.png`) });
    cases.push({ viewport, columns: state.tutorial_modal.columns });
  }
  await page.keyboard.press('Escape');
  state = await command();
  assert(!state.tutorial_modal.visible && state.screen_instance === hub);
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.waitForTimeout(200);
  state = await click(await command(), 'BattleTutorialButton');
  assert.equal(state.tutorial_modal.content_instance, content);
  state = await command('tutorial_modal_focus', { name: 'TutorialStart_combat_exam' });
  const scroll = state.tutorial_modal.scroll;
  state = await click(state, 'TutorialBackButton');
  assert(!state.tutorial_modal.visible);
  state = await click(state, 'BattleTutorialButton');
  assert.equal(state.tutorial_modal.scroll, scroll);
  await page.mouse.click(10, 10);
  state = await command();
  assert(!state.tutorial_modal.visible, 'Backdrop did not close tutorial');
  state = await click(state, 'OpenSettingsButton');
  state = await click(state, 'LanguageOptionButton');
  const language = state.controls.find(item => item.name === 'LanguageOptionButton');
  const canvas = await page.locator('#canvas').boundingBox(), [x, y, w, h] = language.rect;
  await page.mouse.click(canvas.x + (x + w / 2) * canvas.width / state.viewport[0], canvas.y + (y + h + 26) * canvas.height / state.viewport[1]);
  await page.waitForTimeout(220);
  state = await command();
  assert.equal(state.settings_modal.language, 'en');
  state = await click(state, 'SettingsCloseButton');
  state = await click(state, 'BattleTutorialButton');
  assert.notEqual(state.tutorial_modal.content_instance, content);
  assert(state.controls.some(item => item.name === 'TutorialBackButton' && item.text === 'Close'));
  await page.screenshot({ path: resolve(output, 'en-desktop.png') });
  state = await click(state, 'TutorialStart_battle_basics');
  assert.equal(state.screen, 'Battle');
  assert(!state.tutorial_modal.visible && state.tutorial.paused);
  state = await command('tutorial_exit');
  assert.equal(state.screen, 'Hub');
  assert(state.tutorial_modal.visible);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(220);
  state = await command();
  assert(state.tutorial_modal.horizontal_overflow <= 1);
  await page.screenshot({ path: resolve(output, 'en-390x844.png') });
  assert.deepEqual(errors, []);
  console.log('WEB_TUTORIAL_MODAL_OK', JSON.stringify({ cases, checks: 'same-scene/all-lessons/cache/scroll/focus/close/Escape/backdrop/locale/start/return', errors }));
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close();
  app.server.closeAllConnections();
  await new Promise(done => app.server.close(done));
}
