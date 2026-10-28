import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const out = resolve('tools/.local/battle-biomes/browser');
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
    await page.waitForFunction(value => JSON.parse(window.qqLayoutState || '{}').sequence === value, seq, { timeout: 45000 });
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  let state = await command('screen', { screen: 'battle' });
  assert.equal(state.environment.id, 'clock_ruins');
  const fields = ['clock_ruins','brass_foundry','rift_gallery','forgotten_sanctuary','timekeeper_engine','paradox_reactor','axiom_altar','eternity_temple'];
  for (const id of fields) {
    for (const infinite of [false, true]) {
      state = await command('environment_fixture', { id, infinite });
      assert.equal(state.environment.id, id); assert.equal(state.environment.infinite, infinite);
      await page.waitForTimeout(160);
      await page.screenshot({ path: resolve(out, `${id}${infinite ? '-infinite' : ''}.png`) });
      cases.push({ id, infinite, ...state.environment });
    }
  }
  state = await command('environment_fixture', { id: 'clock_ruins' });
  const cached = state.environment.cached_instances;
  await command('screen', { screen: 'hub' });
  state = await command('screen', { screen: 'battle' });
  assert.equal(state.environment.id, 'clock_ruins');
  assert.equal(state.environment.cached_instances, cached, 'Scene transition discarded field instances');
  for (const [region, id] of fields.slice(0,4).entries()) {
    for (const facility of ['shop','forge','heal']) {
      state = await command('environment_facility_fixture', { region, facility });
      assert.equal(state.background, `res://assets/backgrounds/biomes/${id}_${facility}.png`);
      await page.screenshot({ path: resolve(out, `${id}-${facility}-ui.png`) });
      cases.push({ region, facility, background: state.background });
    }
  }
  await page.setViewportSize({ width: 960, height: 720 });
  await command('screen', { screen: 'battle' });
  state = await command('environment_fixture', { id: 'eternity_temple', infinite: true });
  await page.screenshot({ path: resolve(out, 'narrow-battle.png') });
  assert.equal(state.environment.id, 'eternity_temple');
  await page.setViewportSize({ width: 1440, height: 900 });
  state = await command('environment_lab_fixture');
  assert(state.controls.some(control => control.name === 'BattleEnvironmentSelect'));
  assert(state.controls.some(control => control.name === 'BattleEnvironmentInfinite'));
  await page.screenshot({ path: resolve(out, 'developer-field-selector.png') });
  assert.deepEqual(errors, []);
  await writeFile(resolve(out, 'results.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_BATTLE_BIOMES_REVIEW_OK: 16 battle appearances, 12 facility screens, scene cache and narrow viewport, developer selector');
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
