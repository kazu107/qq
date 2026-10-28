import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const out = resolve('tools/.local/meta-modal/browser');
await mkdir(out, { recursive: true });
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
    const control = state.controls.find(control => control.name === name); assert(control, name);
    const box = await page.locator('#canvas').boundingBox(), [x,y,w,h] = control.rect;
    await page.mouse.click(box.x + (x+w/2)*box.width/state.viewport[0], box.y + (y+h/2)*box.height/state.viewport[1]);
    await page.waitForTimeout(150); return command();
  }
  async function ready() {
    for (let index = 0; index < 100; index++) {
      const state = await command();
      if (state.meta_modal?.visible && state.meta_modal.ready) return state;
      await page.waitForTimeout(60);
    }
    throw new Error('meta_not_ready');
  }
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  let state = await command('meta_modal_fixture');
  const hub = state.screen_instance;
  state = await click(state, 'HubMetaProgressButton'); state = await ready();
  assert.equal(state.screen_instance, hub); assert.equal(state.meta_modal.hint, 'hub'); assert.equal(state.meta_modal.rows.length, 30);
  const cached = state.meta_modal.content_instance, rows = state.meta_modal.rows;
  assert.equal(state.meta_modal.columns, 2);
  assert.equal(state.meta_modal.summary_columns, 4);
  assert.equal(state.meta_modal.summary_metrics.length, 8);
  assert.equal(state.meta_modal.achievement_icon_size, 104);
  const [sx,sy,sw,sh] = state.meta_modal.summary_rect;
  const [dx,dy,dw] = state.meta_modal.details_rect;
  assert(sy + sh <= dy && Math.abs(sx - dx) <= 1 && Math.abs(sw - dw) <= 1, 'Summary must span the full width above the details');
  assert(state.meta_modal.grid_rect[2] >= dw - 64, 'Details did not reclaim the old sidebar width');
  const pinnedSummary = state.meta_modal.summary_rect;
  assert.equal(state.meta_modal.starters.length, 7);
  for (const starter of state.meta_modal.starters) {
    assert.equal(starter.texture, `res://assets/portraits/${starter.id}.png`);
    assert.deepEqual(starter.frame_size, [96, 96]);
  }
  state = await command('meta_modal_focus', { name: 'MetaStarterFrame_balanced' });
  await page.screenshot({ path: resolve(out, 'starter-icons-ja.png') });
  state = await command('meta_modal_focus', { name: 'MetaStarterFrame_turret' });
  assert.deepEqual(state.meta_modal.summary_rect, pinnedSummary, 'Summary scrolled away with the list');
  await page.screenshot({ path: resolve(out, 'starter-icons-later-ja.png') });
  state = await command('meta_top');
  assert.equal(state.meta_modal.scroll, 0);
  await page.screenshot({ path: resolve(out, 'ja-desktop.png') });
  state = await command('meta_modal_focus', { name: 'ClaimAchievement_big_spender' });
  await page.screenshot({ path: resolve(out, 'before-claim.png') });
  await writeFile(resolve(out, 'before-claim.json'), JSON.stringify({ modal: state.meta_modal, viewport: state.viewport, button: state.controls.find(control => control.name === 'ClaimAchievement_big_spender') }, null, 2));
  state = await click(state, 'ClaimAchievement_big_spender');
  assert.equal(state.meta_modal.claims.big_spender, 1); assert.equal(state.meta_modal.points, 101);
  state = await command('meta_modal_focus', { name: 'BuyMetaStatUpgrade_max_hp' });
  state = await click(state, 'BuyMetaStatUpgrade_max_hp');
  assert.equal(state.meta_modal.levels.max_hp, 1); assert.equal(state.meta_modal.points, 99);
  state = await click(state, 'MetaCloseButton');
  assert(!state.meta_modal.visible); assert.equal(state.screen_instance, hub); assert(state.captions.includes('99'));
  state = await click(state, 'HubMetaProgressButton'); state = await ready();
  assert.equal(state.meta_modal.content_instance, cached); assert.deepEqual(state.meta_modal.rows, rows);
  for (let index = 0; index < 12; index++) { await page.keyboard.press(index < 6 ? 'Tab' : 'Shift+Tab'); state = await command(); assert(state.meta_modal.focus_inside); }
  for (const size of [{ width: 1440, height: 900 }, { width: 1280, height: 720 }, { width: 960, height: 600 }, { width: 900, height: 1200 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(size); await page.waitForTimeout(250); state = await command();
    const [x,y,w,h] = state.meta_modal.rect;
    assert(x >= 0 && y >= 0 && x+w <= state.viewport[0]+1 && y+h <= state.viewport[1]+1);
    assert(state.meta_modal.horizontal_overflow <= 1, 'horizontal overflow');
    await page.screenshot({ path: resolve(out, `ja-${size.width}x${size.height}.png`) });
    cases.push(`${size.width}x${size.height}: fits, no horizontal overflow`);
  }
  await page.keyboard.press('Escape'); await page.waitForTimeout(120); state = await command(); assert(!state.meta_modal.visible);
  await page.setViewportSize({ width: 1440, height: 900 }); await page.waitForTimeout(200);
  state = await click(await command(), 'HubMetaProgressButton'); state = await ready();
  await page.mouse.click(10,10); await page.waitForTimeout(120); state = await command(); assert(!state.meta_modal.visible);
  state = await click(state, 'OpenSettingsButton'); state = await click(state, 'LanguageOptionButton');
  const language = state.controls.find(control => control.name === 'LanguageOptionButton');
  const box = await page.locator('#canvas').boundingBox(), [x,y,w,h] = language.rect;
  await page.mouse.click(box.x+(x+w/2)*box.width/state.viewport[0], box.y+(y+h+26)*box.height/state.viewport[1]);
  await page.waitForTimeout(250); state = await command(); assert.equal(state.settings_modal.language, 'en');
  state = await click(state, 'SettingsCloseButton'); state = await click(state, 'HubMetaProgressButton'); state = await ready();
  assert.notEqual(state.meta_modal.content_instance, cached); assert.equal(state.meta_modal.levels.max_hp, 1); assert.equal(state.meta_modal.points, 99);
  assert(state.controls.some(control => control.name === 'MetaBackButton' && control.text === 'Close'));
  await page.screenshot({ path: resolve(out, 'en-desktop.png') });
  state = await command('meta_modal_focus', { name: 'MetaOpenLibraryButton' }); state = await click(state, 'MetaOpenLibraryButton');
  assert.equal(state.screen, 'CardLibrary'); assert(!state.meta_modal.visible);
  const library = state.screen_instance, libraryCache = state.meta_modal.content_instance;
  state = await click(state, 'LibraryOpenMetaButton'); state = await ready();
  assert.equal(state.screen_instance, library); assert.equal(state.meta_modal.hint, 'library'); assert.equal(state.meta_modal.content_instance, libraryCache);
  state = await click(state, 'MetaCloseButton'); assert.equal(state.screen_instance, library);
  state = await click(state, 'LibraryReturnHubButton');
  const reopenedHub = state.screen_instance;
  state = await click(state, 'HubMetaProgressButton'); state = await ready();
  assert.equal(state.screen_instance, reopenedHub); assert.equal(state.meta_modal.content_instance, libraryCache);
  state = await command('meta_modal_focus', { name: 'ClaimAchievement_big_spender' });
  state = await click(state, 'ClaimAchievement_big_spender'); assert.equal(state.meta_modal.claims.big_spender, 2);
  state = await command('meta_modal_focus', { name: 'UnlockStarter_tempo' });
  const tempoBefore = state.meta_modal.starters.find(item => item.id === 'tempo');
  assert(!tempoBefore.unlocked && !tempoBefore.button_disabled);
  state = await click(state, 'UnlockStarter_tempo');
  const tempoAfter = state.meta_modal.starters.find(item => item.id === 'tempo');
  assert(tempoAfter.unlocked && tempoAfter.button_disabled);
  assert.equal(tempoAfter.icon_instance, tempoBefore.icon_instance);
  await page.screenshot({ path: resolve(out, 'starter-unlocked-en.png') });
  assert.deepEqual(errors, []);
  console.log('WEB_META_MODAL_OK', JSON.stringify({ cases, checks: 'same-scene/claim/upgrade/hub-points/cache/tab/Escape/backdrop/locale/library', errors }));
} finally {
  await writeFile(resolve(out, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close(); app.server.closeAllConnections(); await new Promise(done => app.server.close(done));
}
