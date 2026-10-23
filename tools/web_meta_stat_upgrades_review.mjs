import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/stat-upgrade-tests/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const cases = [], errors = [];
let sequence = 0;
const ids = ['max_hp', 'attack', 'speed', 'loadout_limit'];
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
  async function fixture(extra) {
    await command('screen', { screen: 'hub' });
    return command('stat_upgrade_fixture', extra);
  }
  function bounds(state) {
    assert.equal(state.stat_upgrades.cards.length, 4);
    const [width, height] = state.viewport;
    for (const card of state.stat_upgrades.cards) {
      const [x, y, w, h] = card.frame_rect;
      assert(x >= 0 && y >= 0 && x + w <= width + 1 && y + h <= height + 1, 'Upgrade card outside viewport');
      for (const part of ['level', 'total', 'bar', 'button']) {
        const [left, top, pw, ph] = card[`${part}_rect`];
        assert(left >= x - 1 && top >= y - 1 && left + pw <= x + w + 1 && top + ph <= y + h + 1, `${card.id}/${part} overflow`);
      }
      assert.equal(card.disabled, !card.can_buy);
      if (!card.complete) assert(new RegExp(`^${card.cost}   (強化|Upgrade)\\+${card.amount}$`).test(card.text), 'Button must group icon/cost, separate the action and show its next bonus');
      assert(!card.level_text.includes('購入補正'), 'Redundant purchased bonus text remains');
    }
    assert.equal(state.stat_upgrades.gold_spent, 0, 'Meta Point purchases counted as gold spending');
  }
  async function buy(state, id) {
    const card = state.stat_upgrades.cards.find(item => item.id === id);
    const [x, y, w, h] = card.button_rect;
    const canvas = await page.locator('#canvas').boundingBox();
    const point = [canvas.x + (x + w / 2) * canvas.width / state.viewport[0], canvas.y + (y + h / 2) * canvas.height / state.viewport[1]];
    await page.mouse.move(...point);
    await page.waitForTimeout(50);
    await page.mouse.click(...point);
    return command('inspect');
  }
  for (const language of ['ja', 'en']) for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    let state = await fixture({ language, points: 0 });
    bounds(state);
    assert(state.stat_upgrades.cards.every(card => card.disabled && card.level === 0));
    await page.screenshot({ path: resolve(output, `empty-${language}-${viewport.width}x${viewport.height}.png`) });
    state = await fixture({ language, points: 6 });
    const identities = state.stat_upgrades.cards.map(card => card.instance);
    state = await buy(state, 'max_hp');
    assert.equal(state.stat_upgrades.points, 4);
    assert.equal(state.stat_upgrades.cards[0].current_bonus, 5);
    assert.equal(state.stat_upgrades.cards[0].cost, 4);
    state = await buy(state, 'max_hp');
    assert.equal(state.stat_upgrades.points, 0);
    assert.equal(state.stat_upgrades.cards[0].level, 2);
    assert(state.stat_upgrades.cards[0].disabled);
    assert.deepEqual(state.stat_upgrades.cards.map(card => card.instance), identities, 'Purchase rebuilt upgrade widgets');
    bounds(state);
    await page.screenshot({ path: resolve(output, `purchased-${language}-${viewport.width}x${viewport.height}.png`) });
    await command('screen', { screen: 'hub' });
    state = await command('screen', { screen: 'meta' });
    assert.equal(state.stat_upgrades.cards[0].level, 2, 'Scene transition lost upgrades');
    assert.deepEqual(state.stat_upgrades.cards.map(card => card.instance), identities, 'Scene transition dropped cached upgrade cards');
    state = await fixture({ language, points: 50, levels: { max_hp: 5, attack: 3, speed: 6, loadout_limit: 4 }, awards: { max_hp: 5 } });
    bounds(state);
    assert.deepEqual(state.stat_upgrades.cards.map(card => card.cost), [23, 22, 52, 60]);
    assert.equal(state.stat_upgrades.cards[0].total_bonus, 30);
    await page.screenshot({ path: resolve(output, `mid-${language}-${viewport.width}x${viewport.height}.png`) });
    state = await fixture({ language, points: 1000, levels: { max_hp: 10, attack: 8, speed: 8, loadout_limit: 5 } });
    bounds(state);
    assert(state.stat_upgrades.cards.every(card => card.complete && card.disabled && card.current_bonus === card.next_bonus));
    assert.deepEqual(state.stat_upgrades.cards.map(card => card.current_bonus), [50, 8, 8, 5]);
    await page.screenshot({ path: resolve(output, `max-${language}-${viewport.width}x${viewport.height}.png`) });
    cases.push(`${language} ${viewport.width}x${viewport.height}: 4 tracks, pointer purchases, next costs, insufficient funds, max levels, claim effects and scene cache`);
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  let state = await fixture({ language: 'ja', points: 1000 });
  for (const id of ids) {
    for (let attempt = 0; attempt < 10 && !state.stat_upgrades.cards.find(card => card.id === id).complete; attempt++) {
      const level = state.stat_upgrades.cards.find(card => card.id === id).level;
      state = await buy(state, id);
      assert.equal(state.stat_upgrades.cards.find(card => card.id === id).level, level + 1, 'Pointer purchase did not advance one stage');
    }
    assert(state.stat_upgrades.cards.find(card => card.id === id).complete);
  }
  assert.equal(state.stat_upgrades.points, 58, 'All 31 levels must cost exactly 942 Meta Points');
  assert(state.stat_upgrades.cards.every(card => card.complete));
  assert.deepEqual(errors, []);
  console.log('WEB_META_STAT_UPGRADE_REVIEW_OK', cases, 'all 31 actual purchases: 942 points');
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
