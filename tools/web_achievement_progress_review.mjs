import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const newDefinitions = require('../data/achievements.json').filter(entry => entry.tracking_version === 1);
const newStats = Object.fromEntries(newDefinitions.map(entry => [entry.condition.stat, entry.condition.value]));
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/achievement-tests/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const cases = [], errors = [];
let sequence = 0;
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
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
  function bounds(state) {
    assert.equal(state.achievements.cards.length, 48);
    for (const card of state.achievements.cards) {
      const [left, top, width, height] = card.rect;
      for (const [key, [x, y, w, h]] of Object.entries(card.parts)) {
        assert(x >= left - 1 && y >= top - 1 && x + w <= left + width + 1 && y + h <= top + height + 1, `${card.id}/${key} overflows its frame`);
      }
      assert(card.parts.progress[1] + card.parts.progress[3] <= card.parts.progress_bar[1] + 1, 'Progress number is not above its bar');
      assert.equal(card.icon_path, `res://assets/icons/achievements/${card.id}.png`, 'Wrong/missing achievement image');
      const icon = card.parts.icon;
      assert.equal(icon[2], icon[3], 'Achievement image is not square');
      assert(icon[0] + icon[2] < card.parts.name[0], 'Icon must be left of upper text');
      assert(Math.abs(icon[1] - card.parts.name[1]) < 1, 'Icon must align with upper text');
      assert(icon[1] + icon[3] <= card.parts.progress_bar[1], 'Icon overlaps the lower progress bar');
    }
  }
  async function clickClaim(state, id) {
    const card = state.achievements.cards.find(card => card.id === id);
    const [x, y, w, h] = card.parts.button;
    const canvas = await page.locator('#canvas').boundingBox();
    assert(y >= 0 && y + h <= state.viewport[1] + 1, 'Claim button outside viewport');
    const point = [canvas.x + (x + w / 2) * canvas.width / state.viewport[0], canvas.y + (y + h / 2) * canvas.height / state.viewport[1]];
    await page.mouse.move(...point);
    await page.waitForTimeout(50);
    await page.mouse.click(...point);
    return command('inspect');
  }
  for (const language of ['ja', 'en']) for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    await command('screen', { screen: 'hub' });
    let state = await command('achievement_fixture', { language,
      stats: { ...newStats, infinite_score_total: 1100, timeline_delay_ms: 10125, timeline_advance_ms: 9875, cards_interrupted: 2, victories: 250, gold_spent: 20000 },
      claims: { victory_milestones: 6, big_spender: 8 } });
    for (let attempt = 0; state.achievements.cards.length < 48 && attempt < 40; attempt++) state = await command('inspect');
    bounds(state);
    const instances = state.achievements.cards.map(card => card.instance);
    assert.equal(state.achievement_progress.victory_milestones.tiers, 14);
    assert.equal(state.achievement_progress.victory_milestones.target, 250);
    assert.equal(state.achievement_progress.big_spender.tiers, 14);
    assert.equal(state.achievement_progress.big_spender.target, 20000);
    assert(state.achievement_progress.timeline_accelerator.disabled);
    assert(state.achievement_progress.timeline_delayer.progress.includes('10.1'));
    assert(!state.achievement_progress.timeline_delayer.progress.includes('10125'));
    for (const id of ['infinite_score_collector', 'timeline_delayer', 'timeline_accelerator', 'cast_breaker', 'victory_milestones', 'big_spender', ...newDefinitions.map(entry => entry.id)]) {
      state = await command('achievement_focus', { id });
      bounds(state);
      const before = state.achievement_progress[id];
      assert(newDefinitions.some(entry => entry.id === id) ? before.tiers >= 3 : before.tiers >= 10);
      await page.screenshot({ path: resolve(output, `${id}-${language}-${viewport.width}x${viewport.height}.png`) });
      if (before.disabled) continue;
      state = await clickClaim(state, id);
      assert.equal(state.achievement_progress[id].count, before.count + 1, 'Claim did not advance to next stage');
      assert(state.achievement_progress[id].points > before.points, 'Claim reward missing');
      assert.deepEqual(state.achievements.cards.map(card => card.instance), instances, 'Claim rebuilt the entire achievement grid');
      assert(state.achievement_progress[id].disabled, 'Unreached next tier was enabled');
    }
    cases.push(`${language} ${viewport.width}x${viewport.height}: 48 groups, fractional seconds, progress above bars, all 18 tactical claims and cached widgets`);
  }
  for (const viewport of [{ width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    await command('screen', { screen: 'hub' });
    let state = await command('achievement_fixture', { language: 'ja',
      stats: { infinite_score_total: 10000000, timeline_delay_ms: 1000000000, timeline_advance_ms: 1000000000, cards_interrupted: 25000 },
      claims: { infinite_score_collector: 11, timeline_delayer: 11, timeline_accelerator: 11, cast_breaker: 11 } });
    for (const id of ['infinite_score_collector', 'timeline_delayer', 'timeline_accelerator', 'cast_breaker']) {
      state = await command('achievement_focus', { id });
      bounds(state);
      assert.equal(state.achievement_progress[id].count, 11);
      await page.screenshot({ path: resolve(output, `final-${id}-${viewport.width}x${viewport.height}.png`) });
      state = await clickClaim(state, id);
      assert.equal(state.achievement_progress[id].count, 12);
      assert(state.achievement_progress[id].disabled);
    }
    cases.push(`${viewport.width}x${viewport.height}: long final-tier values fit and all twelfth-stage rewards complete`);
  }
  let state = await command('screen', { screen: 'battle' });
  assert.equal(state.battle_control.receipt.length, 32, 'Web battle receipt generator failed');
  const before = state.battle_control.stats;
  state = await command('battle_simulate');
  for (let attempt = 0; !state.outcome?.visible && attempt < 100; attempt++) {
    await page.waitForTimeout(100);
    state = await command('inspect');
  }
  assert(state.outcome?.visible, 'Actual Web battle did not finish');
  const metrics = state.battle_control.metrics.player;
  for (const metric of ['delay', 'advance']) {
    assert.equal(state.battle_control.stats[`timeline_${metric}_ms`], before[`timeline_${metric}_ms`] + Math.round(metrics[`${metric}_seconds`] * 1000), 'Actual Web battle progress was not persisted');
  }
  assert.equal(state.battle_control.stats.cards_interrupted, before.cards_interrupted + metrics.interrupts);
  cases.push('Actual Web battle: secure receipt ID, simulation to result and exact lifetime metric credit');
  assert.deepEqual(errors, []);
  console.log('WEB_ACHIEVEMENT_PROGRESS_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
