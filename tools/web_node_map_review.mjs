import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/node-map-browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
const consoleLog = [];
const cases = [];
let sequence = 0;
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    consoleLog.push(message.text());
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
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
  async function click(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing ${name}`);
    await page.mouse.click(...await point(state, control.rect));
    return command('inspect');
  }
  function bounds(state) {
    const [width, height] = state.viewport;
    const overflow = state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && w > 1 && h > 1 && (x < -2 || y < -2 || x + w > width + 2 || y + h > height + 2);
    });
    assert.deepEqual(overflow, [], 'Map/modal viewport overflow');
  }
  for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    let state = await command('screen', { screen: 'map_extended' });
    bounds(state);
    assert.equal(state.map.nodes.length, 26);
    assert(state.map.edges > 14);
    assert.equal(state.map.nodes.filter(node => !node.disabled).length, 3);
    for (const a of state.map.nodes) for (const b of state.map.nodes) {
      if (a.id >= b.id || Math.abs(a.rect[1] - b.rect[1]) > 2) continue;
      assert(a.rect[0] + a.rect[2] <= b.rect[0] + 2 || b.rect[0] + b.rect[2] <= a.rect[0] + 2, 'Map node hitboxes overlap');
    }
    await page.screenshot({ path: resolve(output, `start-${viewport.width}x${viewport.height}.png`) });
    await writeFile(resolve(output, `state-${viewport.width}x${viewport.height}.json`), JSON.stringify(state, null, 2));
    const firstAvailable = state.map.nodes.find(node => !node.disabled).rect;
    const view = state.map.scroll_rect;
    assert(firstAvailable[1] >= view[1] - 2 && firstAvailable[1] + firstAvailable[3] <= view[1] + view[3] + 2, 'Entrance choices were not visible');
    state = await click(state, 'MapHistoryButton');
    assert(state.map.history);
    bounds(state);
    state = await click(state, 'MapHistoryClose');
    assert(!state.map.history);
    if (state.map.drawer) {
      state = await click(state, 'MapLoadoutButton');
      assert(state.map.loadout_open);
      bounds(state);
      assert(state.loadout.rows.length > 0 && !state.loadout.horizontal_bar);
      await page.screenshot({ path: resolve(output, `loadout-${viewport.width}x${viewport.height}.png`) });
      state = await click(state, 'MapLoadoutClose');
    } else {
      assert(state.loadout.rows.length > 0 && !state.loadout.horizontal_bar);
    }
    state = await click(state, 'MapNextChapter');
    assert.equal(state.map.chapter, 7);
    assert.equal(state.map.nodes.filter(node => !node.disabled).length, 0);
    state = await click(state, 'MapPreviousChapter');
    assert.equal(state.map.chapter, 0);
    const chosen = state.map.nodes.find(node => !node.disabled);
    state = await command('map_advance');
    assert.equal(state.map.step, 1);
    assert.equal(state.map.current, chosen.id);
    const available = state.map.nodes.filter(node => !node.disabled).map(node => node.id);
    assert.deepEqual(available.sort(), [...chosen.next].sort(), 'UI offered an unconnected node');
    bounds(state);
    await page.screenshot({ path: resolve(output, `branch-${viewport.width}x${viewport.height}.png`) });
    for (let step = 1; step < 7; step++) state = await command('map_advance');
    assert.equal(state.map.step, 7);
    assert.equal(state.map.chapter, 7, 'Did not enter the next seven-step chapter');
    assert.equal(state.map.nodes.filter(node => !node.disabled).length, 3);
    bounds(state);
    for (const side of ['left', 'right']) {
      state = await command('screen', { screen: 'map_extended' });
      for (let step = 0; step < 6; step++) {
        const choices = state.map.nodes.filter(node => !node.disabled).sort((a, b) => a.rect[0] - b.rect[0]);
        assert(choices.length >= 2, `${side} route became a single-choice corridor at ${step}`);
        const choice = side === 'left' ? choices[0] : choices.at(-1);
        state = await command('map_advance', { node_id: choice.id });
        assert.equal(state.map.current, choice.id);
        assert.deepEqual(state.map.nodes.filter(node => !node.disabled).map(node => node.id).sort(), [...choice.next].sort());
        bounds(state);
      }
      await page.screenshot({ path: resolve(output, `${side}-route-${viewport.width}x${viewport.height}.png`) });
    }
    cases.push(`${viewport.width}x${viewport.height}: routes, initial focus, history, responsive loadout, chapter navigation, connected options, boss gate`);
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  for (const viewport of [{ width: 1440, height: 900 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    for (const screen of ['event_later', 'event_saved_empty', 'event_fallback']) {
      let state = await command('screen', { screen });
      assert.equal(state.screen, 'Facility');
      assert.equal(state.facility.area, 4, 'Did not reproduce the second-chapter event');
      const buttons = state.controls.filter(item => item.name.startsWith('EventChoiceButton_'));
      const fallback = screen === 'event_fallback';
      assert.equal(buttons.length, fallback ? 1 : 3, 'Event choices are missing');
      for (const button of buttons) {
        const [x, y, w, h] = button.rect;
        assert(x >= -2 && x + w <= state.viewport[0] + 2 && y >= -2 && y + h <= state.viewport[1] + 2, 'Event option is outside the viewport');
      }
      const initial = state.facility;
      state = await command('inspect');
      assert.deepEqual(state.facility, initial, 'Inspecting the event rerolled choices or applied rewards');
      await page.screenshot({ path: resolve(output, `${screen}-${viewport.width}x${viewport.height}.png`) });
      const choice = fallback ? 'leave_empty_event' : state.facility.choices.find(item => item.enabled).id;
      state = await click(state, `EventChoiceButton_${choice}`);
      assert.equal(state.screen, 'Map', 'Event choice did not return to the route');
      assert.equal(state.map.step, 9, 'Event choice did not advance exactly once');
      cases.push(`${screen} ${viewport.width}x${viewport.height}: displayed choices, no reroll, continue to map`);
    }
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  let state = await command('screen', { screen: 'map' });
  const node = state.map.nodes.find(item => !item.disabled);
  await page.mouse.click(...await point(state, node.rect));
  state = await command('inspect');
  assert(state.encounter, 'Battle node did not open Enemy Intel');
  state = await click(state, 'EnemyEncounterStart');
  for (let attempt = 0; attempt < 40; attempt++) {
    await page.waitForTimeout(100);
    state = await command('inspect');
    if (state.screen === 'Battle') break;
  }
  assert.equal(state.screen, 'Battle', 'Animated node selection did not enter battle');
  assert.deepEqual(errors, []);
  console.log('WEB_NODE_MAP_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors, consoleLog: consoleLog.slice(-100) }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
