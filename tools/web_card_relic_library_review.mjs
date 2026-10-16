import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/library-tabs-tests/browser');
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
  async function settled(predicate = data => data.library?.ready) {
    let last;
    for (let attempt = 0; attempt < 30; attempt++) {
      const data = await command('inspect');
      last = data;
      if (predicate(data)) return data;
    }
    await writeFile(resolve(output, 'failed-state.json'), JSON.stringify({ last, errors }, null, 2));
    await page.screenshot({ path: resolve(output, 'failed.png') });
    assert.fail('Library did not settle');
  }
  async function point(state, rect) {
    const canvas = await page.locator('#canvas').boundingBox();
    const [x, y, w, h] = rect;
    return [canvas.x + (x + w / 2) * canvas.width / state.viewport[0], canvas.y + (y + h / 2) * canvas.height / state.viewport[1]];
  }
  async function clickTab(state, index) {
    await page.mouse.click(...await point(state, state.library.tabs[index]));
    return settled(data => data.library?.active === index && data.library.ready);
  }
  async function clickControl(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing ${name}`);
    const position = await point(state, control.rect);
    await page.mouse.move(...position);
    await page.waitForTimeout(40);
    await page.mouse.click(...position);
    return command('inspect');
  }
  async function select(state, name, index) {
    const opened = await clickControl(state, name);
    const menu = opened.library.option_menu;
    assert.equal(menu?.name, name, `Option menu ${name} did not open`);
    const steps = menu.focus < 0 ? index + 1 : (index - menu.focus + menu.count) % menu.count;
    for (let i = 0; i < steps; i++) {
      await page.keyboard.press('ArrowDown');
      await page.waitForTimeout(25);
    }
    await page.keyboard.press('Enter');
    return settled();
  }
  async function search(state, text) {
    await clickControl(state, 'LibraryRelicSearch');
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    if (text) await page.keyboard.type(text, { delay: 10 });
    await page.waitForTimeout(300);
    return settled();
  }
  function bounds(state) {
    const [width, height] = state.viewport;
    assert.deepEqual(state.controls.filter(item => {
      const [x, y, w, h] = item.rect;
      return !item.scroll && w > 1 && h > 1 && (x < -2 || y < -2 || x + w > width + 2 || y + h > height + 2);
    }), [], 'Library toolbar or tabs overflow the viewport');
    assert(!state.library.relic_h_scroll, 'Relic tab has horizontal scrolling');
    for (const row of state.library.relics) {
      assert(row.icon[2] <= 120 && row.icon[3] <= 120, 'Relic art expanded to its source resolution');
      assert(row.tooltip.length > 0, 'Relic tooltip is empty');
    }
  }
  for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    for (const language of ['ja', 'en']) {
      console.log('Library case', viewport.width, viewport.height, language);
      await command('screen', { screen: 'hub' });
      let state = await command('content_fixture', { screen: 'library', xp: 125, language });
      state = await settled();
      assert.deepEqual(state.library.titles, language === 'ja' ? ['カード', '遺物'] : ['Cards', 'Relics']);
      assert.equal(state.library.relics.length, 0, 'Inactive relic tab loaded all its rows');
      state = await select(state, 'LibraryRarityFilter', 4);
      assert.equal(state.library.card_rarity, 'legendary');
      const cards = state.library.card_rows;
      await page.screenshot({ path: resolve(output, `cards-${language}-${viewport.width}x${viewport.height}.png`) });
      state = await clickTab(state, 1);
      bounds(state);
      assert(state.library.relics.length >= 12 && state.library.relics.length < 86, 'Initial relic page was not lazy');
      await page.screenshot({ path: resolve(output, `relics-${language}-${viewport.width}x${viewport.height}.png`) });
      if (language === 'ja' && viewport.width === 1440) {
        await page.mouse.move(...await point(state, state.library.relics.find(row => row.id === 'iron_plating').icon));
        await page.waitForTimeout(900);
        state = await settled(data => data.library.tooltip_visible);
        await page.screenshot({ path: resolve(output, 'relic-tooltip.png') });
      }
      const ironInstance = state.library.relics.find(row => row.id === 'iron_plating').instance;
      state = await clickControl(state, 'SealRelic_iron_plating');
      assert(state.content_progress.sealed_relics.includes('iron_plating'), 'Pointer seal did not persist');
      state = await clickControl(state, 'SealRelic_iron_plating');
      assert(!state.content_progress.sealed_relics.includes('iron_plating'), 'Pointer unseal failed');
      assert.equal(state.library.relics.find(row => row.id === 'iron_plating').instance, ironInstance, 'Seal rebuilt the relic row');
      state = await search(state, language === 'en' ? 'Iron Plating' : 'HP');
      assert(state.library.relic_matching > 0 && state.library.relic_matching < 86, 'Relic name/effect search failed');
      if (language === 'en') assert.deepEqual(state.library.relics.map(row => row.id), ['iron_plating']);
      state = await search(state, 'no_match_00000000');
      assert(state.library.relic_empty && state.library.relics.length === 0);
      state = await search(state, '');
      state = await select(state, 'LibraryRelicRarityFilter', 4);
      assert.equal(state.library.relics.length, 9);
      assert(state.library.relics.every(row => row.rarity === 'legendary'));
      const relics = state.library.relics;
      state = await clickTab(state, 0);
      assert.equal(state.library.card_rarity, 'legendary', 'Card filter was lost on tab switch');
      assert(cards.every(card => state.library.card_rows.find(other => other.id === card.id)?.instance === card.instance), 'Card tab was rebuilt');
      state = await clickTab(state, 1);
      assert.deepEqual(state.library.relics, relics, 'Relic filter or cached rows were lost');
      state = await select(state, 'LibraryRelicRarityFilter', 0);
      state = await select(state, 'LibraryRelicTypeFilter', 1);
      assert.equal(state.library.relic_tag, 'arena');
      assert(state.library.relics.length > 0 && state.library.relics.every(row => row.tags.includes('arena')));
      state = await select(state, 'LibraryRelicTypeFilter', 0);
      for (let attempt = 0; state.library.relics.length < 86 && attempt < 15; attempt++) {
        await page.mouse.move(...await point(state, state.library.relic_scroll));
        await page.mouse.wheel(0, 10000);
        state = await settled();
      }
      assert.equal(state.library.relics.length, 86, 'Scrolling did not load the full relic catalog');
      const fullIds = state.library.relics.map(row => row.instance);
      await command('screen', { screen: 'hub' });
      state = await command('screen', { screen: 'library' });
      assert.equal(state.library.active, 1, 'Scene revisit lost the selected tab');
      assert.deepEqual(state.library.relics.map(row => row.instance), fullIds, 'Scene revisit rebuilt the relic tab');
      cases.push({ viewport, language, initialCards: cards.length, relics: state.library.relics.length });
    }
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ cases, errors }, null, 2));
  console.log('WEB_CARD_RELIC_LIBRARY_OK', JSON.stringify({ cases: cases.length, errors }));
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
