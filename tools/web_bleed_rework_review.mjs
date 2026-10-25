import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/bleed-rework/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], checks = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/.test(message.text())) errors.push(message.text()); });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  let sequence = 0;
  async function command(action, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function until(predicate) {
    let last;
    for (let i = 0; i < 120; i++) {
      last = await command('inspect');
      if (predicate(last)) return last;
      await page.waitForTimeout(100);
    }
    await writeFile(resolve(output, 'timeout.json'), JSON.stringify(last, null, 2));
    await page.screenshot({ path: resolve(output, 'timeout.png') });
    throw new Error('Bleed UI did not reach its expected state');
  }
  async function point(state, x, y, click = true) {
    const box = await page.locator('#canvas').boundingBox();
    const px = box.x + x * box.width / state.viewport[0], py = box.y + y * box.height / state.viewport[1];
    if (click) await page.mouse.click(px, py); else await page.mouse.move(px, py);
    return command('inspect');
  }
  async function button(state, name) {
    const item = state.controls.find(control => control.name === name);
    assert(item, `Missing ${name}`);
    return point(state, item.rect[0] + item.rect[2] / 2, item.rect[1] + item.rect[3] / 2);
  }
  async function type(state, name, text) {
    const item = state.controls.find(control => control.name === name); assert(item);
    await point(state, item.rect[0] + item.rect[2] * 0.35, item.rect[1] + item.rect[3] / 2);
    await page.keyboard.press('Control+A'); await page.waitForTimeout(30);
    await page.keyboard.type(text, { delay: 40 });
    return command('inspect');
  }
  for (const language of ['ja', 'en']) {
    await command('content_fixture', { language, screen: 'balance' });
    let state = await until(state => state.balance?.ready);
    await type(state, 'BalanceSearch', 'bleed_cut');
    state = await until(state => state.balance.selected === 'bleed_cut');
    const tab = state.balance.grade_tabs[3].rect;
    state = await point(state, tab[0] + tab[2] / 2, tab[1] + tab[3] / 2);
    assert.equal(state.balance.fields['grade_overrides.3.effects.1.bleed_power'].value, 2);
    state = await type(state, 'BalanceAttack', '12');
    assert(state.balance.grade_previews['3'].includes(language === 'ja' ? 'HPへ5ダメージ' : '5 HP damage'));
    assert(state.balance.grade_previews['5'].includes(language === 'ja' ? 'HPへ7ダメージ' : '7 HP damage'));
    await page.screenshot({ path: resolve(output, `lab-power-${language}.png`) });
    await command('bleed_fixture', { language });
    state = await until(state => state.screen === 'Battle' && state.controls.some(control => control.name === 'DevBleedEnemy'));
    state = await button(state, 'DevBleedEnemy');
    assert.equal(state.bleed.badge, 'x3');
    assert.equal(state.bleed.state.damage, 12);
    assert.deepEqual(state.bleed.state.layers.map(layer => layer.power), [2, 4, 6]);
    for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
      await page.setViewportSize(size); state = await command('inspect');
      const points = state.bleed.regions[0].points;
      state = await point(state, points.reduce((n, p) => n + p[0], 0) / points.length, points.reduce((n, p) => n + p[1], 0) / points.length, false);
      state = await until(state => state.bleed.tooltip !== '');
      assert(state.bleed.tooltip.includes(language === 'ja' ? '合計12ダメージ' : '12 damage'));
      assert(state.bleed.tooltip.includes(language === 'ja' ? '3層目' : 'Layer 3'));
      const popups = state.controls.filter(control => control.name === 'WorldStatusTooltip');
      assert.equal(popups.length, 1);
      const [x, y, w, h] = popups[0].rect;
      assert(x >= 0 && y >= 0 && x + w <= state.viewport[0] + 1 && y + h <= state.viewport[1] + 1, 'Tooltip clipped');
      await page.screenshot({ path: resolve(output, `tooltip-${language}-${size.width}.png`) });
    }
    state = await command('bleed_advance', { seconds: 6, keep_alive: true });
    assert.equal(state.bleed.enemy_hp, 488);
    state = await command('bleed_advance', { seconds: 6 });
    assert.equal(state.bleed.enemy_hp, 476);
    assert.equal(state.bleed.badge, 'x2');
    assert.equal(state.bleed.state.damage, 10);
    state = await button(state, 'DevBleedClear');
    assert.deepEqual(state.bleed.state, {});
    checks.push(`${language}:grade_power_3_sizes_actual_hover_aggregate_tick_independent_expiry_developer_cleanse`);
    await page.setViewportSize({ width: 1440, height: 900 });
  }
  assert.deepEqual(errors, []);
  console.log('WEB_BLEED_REWORK_REVIEW_OK', checks);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ checks, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
