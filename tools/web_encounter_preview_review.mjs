import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/encounter-tests/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [], consoleLog = [];
let sequence = 0;
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    consoleLog.push(message.text());
    if (/SCRIPT ERROR|Parse Error|ERROR:/.test(message.text())) errors.push(message.text());
  });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 90000 });
  await page.waitForSelector('#status', { state: 'detached' });
  async function command(action, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function point(state, rect) {
    const canvas = await page.locator('#canvas').boundingBox();
    const [x, y, w, h] = rect;
    return [canvas.x + (x + w / 2) * canvas.width / state.viewport[0], canvas.y + (y + h / 2) * canvas.height / state.viewport[1]];
  }
  async function clickRect(state, rect) {
    const p = await point(state, rect);
    await page.mouse.move(...p);
    await page.waitForTimeout(60);
    await page.mouse.click(...p);
    return command('inspect');
  }
  async function click(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing ${name}`);
    return clickRect(state, control.rect);
  }
  async function waitState(predicate) {
    for (let i = 0; i < 80; i++) {
      const state = await command('inspect');
      if (predicate(state)) return state;
      await page.waitForTimeout(100);
    }
    throw new Error('Scene/modal transition timed out');
  }
  function bounds(state) {
    const frame = state.encounter.rect;
    const [x, y, w, h] = frame;
    assert(x >= 0 && y >= 0 && x + w <= state.viewport[0] + 1 && y + h <= state.viewport[1] + 1, 'Intel frame overflow');
    const model = state.encounter.model_rect;
    assert(model[2] > 180 && model[3] > 200, 'Enemy model was squeezed out');
    assert(state.encounter.model_ready && state.encounter.model_id === state.encounter.enemy, 'Wrong/missing animated model');
    for (const card of state.encounter.cards) {
      const density = state.viewport[0] / state.window[0];
      assert(card.rect[2] / density < 200 && card.rect[3] / density < 240, 'Card icon expanded to source texture size');
      assert(card.tooltip.length > 20, 'Card tooltip missing');
    }
  }
  for (const language of ['ja', 'en']) {
    for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
      await page.setViewportSize(viewport);
      await command('screen', { screen: 'hub' });
      let state = await command('encounter_fixture', { language });
      const node = state.map.nodes.find(item => !item.disabled);
      state = await clickRect(state, node.rect);
      state = await waitState(s => Boolean(s.encounter));
      assert.equal(state.encounter.index, 1);
      assert.equal(state.encounter.total, 2);
      assert.equal(state.encounter_progress.active, '', 'Viewing intel committed route selection');
      await page.screenshot({ path: resolve(output, `normal-${language}-${viewport.width}x${viewport.height}.png`) });
      await writeFile(resolve(output, `state-${language}-${viewport.width}x${viewport.height}.json`), JSON.stringify(state, null, 2));
      bounds(state);
      await page.mouse.move(...await point(state, state.encounter.cards[0].rect));
      await page.waitForTimeout(900);
      await page.screenshot({ path: resolve(output, `tooltip-${language}-${viewport.width}x${viewport.height}.png`) });
      state = await click(state, 'EnemyEncounterClose');
      assert(!state.encounter);
      assert.equal(state.encounter_progress.active, '');
      state = await clickRect(state, node.rect);
      state = await click(state, 'EnemyEncounterStart');
      state = await waitState(s => s.screen === 'Battle');
      assert.equal(state.encounter_progress.pending, 'scout');
      state = await command('encounter_win');
      state = await waitState(s => s.screen === 'Reward');
      state = await click(state, 'RewardSkipButton');
      state = await waitState(s => Boolean(s.encounter));
      assert.equal(state.encounter.index, 2);
      assert.equal(state.encounter.enemy, 'guardian');
      assert.equal(state.encounter_progress.step, 0);
      bounds(state);
      await page.screenshot({ path: resolve(output, `next-${language}-${viewport.width}x${viewport.height}.png`) });
      state = await click(state, 'EnemyEncounterClose');
      state = await click(state, 'MapEncounterButton');
      assert.equal(state.encounter.index, 2);
      state = await click(state, 'EnemyEncounterStart');
      state = await waitState(s => s.screen === 'Battle');
      assert.equal(state.encounter_progress.pending, 'guardian');
      await command('encounter_win');
      state = await waitState(s => s.screen === 'Reward');
      state = await click(state, 'RewardSkipButton');
      state = await waitState(s => s.screen === 'Map');
      assert(!state.encounter && state.encounter_progress.step === 1);
      cases.push(`${language} ${viewport.width}x${viewport.height}: view/cancel, model/cards/tooltip, confirm, rewards, next enemy, reopen, complete chain`);
    }
  }
  for (const viewport of [{ width: 1440, height: 900 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    let state = await command('encounter_fixture', { language: 'ja', hazard: true });
    state = await clickRect(state, state.map.nodes.find(item => !item.disabled).rect);
    state = await waitState(s => Boolean(s.encounter));
    assert.equal(state.screen, 'Facility');
    assert.equal(state.encounter.total, 3);
    for (let index = 1; index <= 3; index++) {
      assert.equal(state.encounter.index, index);
      bounds(state);
      await page.screenshot({ path: resolve(output, `hazard-${index}-${viewport.width}x${viewport.height}.png`) });
      if (index === 2) {
        state = await click(state, 'EnemyEncounterClose');
        state = await click(state, 'HazardChoiceButton_continue_hazard');
        assert.equal(state.encounter.index, 2);
      }
      state = await click(state, 'EnemyEncounterStart');
      await waitState(s => s.screen === 'Battle');
      await command('encounter_win');
      state = await waitState(s => s.screen === 'Reward');
      state = await click(state, 'RewardSkipButton');
      state = await waitState(s => index === 3 ? s.screen === 'Map' : Boolean(s.encounter));
    }
    assert(!state.encounter && state.encounter_progress.step === 1);
    cases.push(`${viewport.width}x${viewport.height}: hazard 1/3 to 3/3, per-wave reward and reopened intel`);
  }
  assert.deepEqual(errors, []);
  console.log('WEB_ENCOUNTER_PREVIEW_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors, consoleLog: consoleLog.slice(-150) }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
