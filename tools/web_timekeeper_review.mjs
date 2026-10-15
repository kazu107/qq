import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/timekeeper-browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
const cases = [];
let sequence = 0;

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
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
  function verifyBounds(state) {
    const [width, height] = state.viewport;
    const overflow = state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && w > 1 && h > 1 && (x < -2 || y < -2 || x + w > width + 2 || y + h > height + 2);
    });
    assert.deepEqual(overflow, [], 'Timekeeper screen overflow');
    const [x, y, w, h] = state.timekeeper.forecast_rect;
    assert(x >= 0 && y >= 0 && x + w <= width + 2 && y + h <= height + 2);
  }
  for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    let state = await command('screen', { screen: 'timekeeper' });
    assert.equal(state.timekeeper.time, 0, 'Started during preparation');
    state = await command('timekeeper_advance', { seconds: 0 });
    assert(state.timekeeper.forecast_visible && /40\.0s.*31/.test(state.timekeeper.forecast));
    assert.equal(state.timekeeper.cards.length, 1);
    assert.equal(state.timekeeper.cards[0].id, 'timekeeper_final_strike');
    assert.equal(state.timekeeper.horizon, 8, 'Opening strike expanded the scale');
    assert.deepEqual(state.timekeeper.ticks, ['0s', '2s', '4s', '6s', '8s']);
    const openingScale = state.timekeeper.cards[0].scale;
    assert(openingScale > 0.35 && openingScale < 0.6, 'Opening strike was not miniaturized');
    verifyBounds(state);
    await page.screenshot({ path: resolve(output, `opening-overflow-${viewport.width}x${viewport.height}.png`) });
    const baselineTimeline = state.controls.find(item => item.name === 'TimelinePanel')?.rect;
    state = await command('timekeeper_advance', { seconds: 7 });
    assert.equal(state.timekeeper.cards.length, 2, 'Amplifier did not join the timeline');
    const support = state.timekeeper.cards.find(item => item.id === 'timekeeper_amplify');
    await page.mouse.move(...await point(state, support.rect));
    state = await command('inspect');
    assert.equal(state.timekeeper.cards.find(item => item.id === 'timekeeper_amplify').z, 999, 'Hovered card was not raised');
    await page.mouse.move(4, 4);
    state = await command('timekeeper_advance', { seconds: 9.2 });
    assert.equal(state.timekeeper.multiplier, 2);
    assert(/62.*2倍込み/.test(state.timekeeper.forecast));
    const charge = state.timekeeper.regions.find(item => item.id === 'attack_charge');
    assert(charge, 'No world-space charge icon');
    await page.mouse.move(...await point(state, charge.rect));
    state = await command('inspect');
    assert(state.status_icons.tooltip_visible, 'Charge hover failed');
    assert(/2/.test(state.status_icons.tooltip_text) && !/残り|remaining/i.test(state.status_icons.tooltip_text), 'Charge tooltip used a fake timer');
    verifyBounds(state);
    await page.screenshot({ path: resolve(output, `charge-${viewport.width}x${viewport.height}.png`) });
    await page.mouse.move(4, 4);
    state = await click(state, 'DevBossClearCharge');
    assert.equal(state.timekeeper.multiplier, 1);
    assert(/31/.test(state.timekeeper.forecast));
    state = await click(state, 'DevBossCharge');
    assert.equal(state.timekeeper.multiplier, 2);
    state = await click(state, 'DevBossCharge');
    assert.equal(state.timekeeper.multiplier, 4, 'Developer charge did not stack');
    state = await click(state, 'DevBossClearCharge');
    state = await click(state, 'DevBossCharge');
    state = await command('timekeeper_advance', { seconds: 20.3 });
    assert.equal(state.timekeeper.multiplier, 4);
    const midCard = state.timekeeper.cards.find(item => item.id === 'timekeeper_final_strike');
    assert(midCard.scale > openingScale && midCard.scale < 1, 'Overflow card did not grow');
    assert(/124.*4倍込み/.test(state.timekeeper.forecast));
    const stackedCharge = state.timekeeper.regions.find(item => item.id === 'attack_charge');
    await page.mouse.move(...await point(state, stackedCharge.rect));
    state = await command('inspect');
    assert(state.status_icons.tooltip_visible && /次攻撃4倍/.test(state.status_icons.tooltip_text), 'Stacked charge tooltip was stale');
    await page.screenshot({ path: resolve(output, `stacked-${viewport.width}x${viewport.height}.png`) });
    state = await command('timekeeper_advance', { seconds: 31.4 });
    assert(state.timekeeper.cards.find(item => item.id === 'timekeeper_final_strike').scale < 1);
    state = await command('timekeeper_advance', { seconds: 32.1 });
    const enteredCard = state.timekeeper.cards.find(item => item.id === 'timekeeper_final_strike');
    assert.equal(enteredCard.scale, 1, 'Card did not reach full size inside the scale');
    state = await command('timekeeper_advance', { seconds: 34.5 });
    assert.equal(state.timekeeper.multiplier, 8);
    assert(state.status_icons.tooltip_visible && /次攻撃8倍/.test(state.status_icons.tooltip_text), 'Hovered tooltip did not update from x4 to x8');
    assert(state.timekeeper.vulnerable && /251.*8倍込み/.test(state.timekeeper.forecast));
    assert(state.timekeeper.cards.find(item => item.id === 'timekeeper_final_strike').rect[0] < enteredCard.rect[0], 'In-range strike did not scroll left');
    assert.equal(state.timekeeper.horizon, 8, 'Growing card changed fixed ticks');
    verifyBounds(state);
    await page.screenshot({ path: resolve(output, `marked-${viewport.width}x${viewport.height}.png`) });
    state = await command('timekeeper_advance', { seconds: 40.2 });
    assert.equal(state.timekeeper.hp, 249);
    assert.equal(state.timekeeper.multiplier, 1);
    assert(!state.timekeeper.forecast_visible);
    if (baselineTimeline) assert.deepEqual(state.controls.find(item => item.name === 'TimelinePanel').rect, baselineTimeline, 'Timeline resized on resolution');
    state = await command('timekeeper_advance', { seconds: 48.3 });
    assert(state.timekeeper.forecast_visible && /31/.test(state.timekeeper.forecast));
    assert(state.timekeeper.art.every(path => path.startsWith('res://assets/icons/cards/timekeeper_')));
    state = await command('screen', { screen: 'timekeeper' });
    state = await command('timekeeper_advance', { seconds: 7 });
    state = await click(state, 'DevTimelineDelay');
    state = await command('timekeeper_advance', { seconds: 7.6 });
    const delayedSupport = state.timekeeper.cards.find(item => item.id === 'timekeeper_amplify');
    const delayedStrike = state.timekeeper.cards.find(item => item.id === 'timekeeper_final_strike');
    assert(delayedSupport.scale < 1 && parseFloat(delayedSupport.seconds) > 8, 'Delayed ordinary card did not shrink outside the scale');
    assert(delayedStrike.scale < openingScale, 'Additional delay did not reduce overflow size');
    assert.equal(state.timekeeper.horizon, 8, 'Developer delay changed the fixed scale');
    verifyBounds(state);
    await page.screenshot({ path: resolve(output, `delayed-overflow-${viewport.width}x${viewport.height}.png`) });
    cases.push(`${viewport.width}x${viewport.height}: fixed 8s scale, miniature opening, gradual growth, normal left scroll, generic delayed card, developer delay, x2/x4/x8, 251 damage`);
  }
  assert.deepEqual(errors, []);
  console.log('WEB_TIMEKEEPER_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
