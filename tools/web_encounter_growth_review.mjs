import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/encounter-growth/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [];
let sequence = 0;

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|ERROR:/.test(message.text())) errors.push(message.text()); });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 90000 });
  await page.waitForSelector('#status', { state: 'detached' });
  async function command(action, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function click(state, rect) {
    const [x, y, w, h] = rect;
    const box = await page.locator('#canvas').boundingBox();
    await page.mouse.click(box.x + (x + w / 2) * box.width / state.viewport[0], box.y + (y + h / 2) * box.height / state.viewport[1]);
  }
  async function button(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing ${name}`);
    await click(state, control.rect);
  }
  async function waitFor(predicate) {
    for (let i = 0; i < 100; i++) {
      const state = await command('inspect');
      if (predicate(state)) return state;
      await page.waitForTimeout(100);
    }
    throw new Error('Encounter transition timed out');
  }
  for (const size of [{ width: 1440, height: 900 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(size);
    for (const fixture of [
      { step: 15, infinite: false, type: 'normal_battle', count: 2 },
      { step: 29, infinite: true, type: 'normal_battle', count: 3 },
      { step: 31, infinite: true, type: 'hazard', count: 4 },
      { step: 38, infinite: true, type: 'hazard', count: 5 },
    ]) {
      await command('screen', { screen: 'hub' });
      let state = await command('encounter_growth_fixture', fixture);
      const node = state.map.nodes.find(item => item.type === fixture.type && !item.disabled);
      assert(node, `No selectable ${fixture.type} on step ${fixture.step}`);
      await click(state, node.rect);
      state = await waitFor(item => Boolean(item.encounter));
      assert.equal(state.encounter.total, fixture.count);
      for (let wave = 1; wave <= fixture.count; wave++) {
        assert.equal(state.encounter.index, wave);
        assert.equal(state.encounter.total, fixture.count);
        assert.equal(state.encounter_progress.step, fixture.step - 1);
        const [x, y, w, h] = state.encounter.rect;
        assert(x >= 0 && y >= 0 && x + w <= state.viewport[0] + 1 && y + h <= state.viewport[1] + 1, 'Enemy window clipped');
        if (wave === 1 || wave === fixture.count) await page.screenshot({ path: resolve(output, `${size.width}-step${fixture.step}-wave${wave}.png`) });
        await button(state, 'EnemyEncounterStart');
        await waitFor(item => item.screen === 'Battle');
        await command('encounter_win');
        state = await waitFor(item => item.screen === 'Reward');
        await button(state, 'RewardSkipButton');
        state = await waitFor(item => wave < fixture.count ? Boolean(item.encounter) : item.screen === 'Map' && !item.encounter);
      }
      assert.equal(state.encounter_progress.step, fixture.step);
      cases.push(`${size.width}x${size.height} step ${fixture.step}: ${fixture.count} previews/battles/rewards and one step advance`);
    }
  }
  assert.deepEqual(errors, []);
  console.log('WEB_ENCOUNTER_GROWTH_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ errors, cases }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
