import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/ascended-enemies/browser');
await mkdir(output, { recursive: true });
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
  async function clickRect(state, rect) {
    const canvas = await page.locator('#canvas').boundingBox(), [x,y,w,h] = rect;
    await page.mouse.click(canvas.x+(x+w/2)*canvas.width/state.viewport[0], canvas.y+(y+h/2)*canvas.height/state.viewport[1]);
    await page.waitForTimeout(150);
    return command();
  }
  async function until(predicate) {
    for (let index = 0; index < 80; index++) {
      const state = await command();
      if (predicate(state)) return state;
      await page.waitForTimeout(100);
    }
    throw new Error('Infinite variant scene transition timed out');
  }
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  for (const fixture of [{enemy:'scout',cycle:1},{enemy:'scout',cycle:2},{enemy:'guardian',cycle:2},{enemy:'boss_timekeeper',cycle:2},{enemy:'boss_eternity_zero',cycle:2},{enemy:'boss_eternity_zero',cycle:2,language:'en'}]) {
    let state = await command('ascended_fixture', fixture);
    const first = state.map.nodes.find(item => !item.disabled);
    assert(first, 'No available Infinite map node');
    state = await clickRect(state, first.rect);
    assert(state.encounter, 'Enemy intel did not open');
    const expected = fixture.enemy + (fixture.cycle >= 2 ? '_ascended' : '');
    assert.equal(state.encounter.enemy, expected);
    assert.equal(state.encounter.model_id, expected);
    assert(state.encounter.model_ready && state.encounter.cards.every(item => item.tooltip.length > 20));
    await page.screenshot({ path:resolve(output, `intel-${fixture.enemy}-${fixture.cycle}${fixture.language ? '-'+fixture.language : ''}.png`) });
    const previewHp = state.encounter.hp, previewAttack = state.encounter.attack;
    state = await clickRect(state, state.controls.find(item => item.name === 'EnemyEncounterStart').rect);
    state = await until(value => value.screen === 'Battle');
    assert.equal(state.screen, 'Battle');
    const enemy = state.infinite_enemy;
    assert.equal(enemy.id, expected);
    assert.equal(enemy.hp, previewHp);
    assert.equal(enemy.attack, previewAttack);
    assert.equal(enemy.variant, fixture.cycle >= 2);
    assert.equal(enemy.model, `res://assets/models/battle/${fixture.enemy}.glb`);
    assert.equal(enemy.grade, fixture.cycle);
    assert(fixture.cycle < 2 ? enemy.colors.length === 0 : enemy.colors.length >= 5, 'Palette overrides missing/leaking');
    if (fixture.enemy !== 'scout' && fixture.cycle >= 2) assert(enemy.cards.some(id => id.startsWith('ascendant_')));
    await page.waitForTimeout(350);
    await page.screenshot({ path:resolve(output, `battle-${fixture.enemy}-${fixture.cycle}${fixture.language ? '-'+fixture.language : ''}.png`) });
    cases.push({ ...fixture, enemy });
  }
  assert.deepEqual(errors, []);
  console.log('WEB_INFINITE_ENEMY_VARIANTS_OK', JSON.stringify({cases,errors}));
} finally {
  await writeFile(resolve(output,'report.json'), JSON.stringify({cases,errors},null,2));
  await browser.close(); app.server.closeAllConnections(); await new Promise(done => app.server.close(done));
}
