import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/advanced-tutorial/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [];
const ids = ['prepared_combos','hostile_reservations','regeneration','damage_conversion'];
const shots = new Set(['prepared_both','prepared_result','hostile_armed','hostile_result','regeneration_layers','regeneration_complete','conversion_life_result','conversion_barrier_result','conversion_exception_ready','conversion_complete']);
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
  async function point(state, rect, hover = false) {
    const box = await page.locator('#canvas').boundingBox(), [x,y,w,h] = rect;
    assert(w > 0 && h > 0);
    const px = box.x + (x+w/2)*box.width/state.viewport[0], py = box.y + (y+h/2)*box.height/state.viewport[1];
    if (hover) await page.mouse.move(px, py); else await page.mouse.click(px, py);
  }
  function checkBounds(state) {
    const callout = state.controls.find(item => item.name === 'TutorialCallout'); assert(callout, 'missing callout');
    const [x,y,w,h] = callout.rect;
    assert(x >= -1 && y >= 0 && x+w <= state.viewport[0]+1 && y+h <= state.viewport[1]+1, `Callout outside viewport: ${JSON.stringify(callout)}`);
    const focus = state.tutorial.focus;
    if (state.tutorial.step.target) assert(focus[2] > 0 && focus[3] > 0, 'Empty highlight target');
  }
  function validate(id, tutorial, observed) {
    const state = tutorial.state, resolved = state.battle_events.filter(event => event.event_type === 'resolve_card');
    if (id === 'prepared_combos') {
      assert.equal(observed.prepared_kept.player.card_reservations.length, 1);
      assert.equal(observed.prepared_both.player.repeat_charges, 1);
      const attack = resolved.filter(event => event.card_id === 'quick_slash'); assert.equal(attack.length, 1);
      assert.equal(attack[0].result.effect_repeats, 2); assert.equal(attack[0].result.effect_resolutions.length, 2);
      assert.equal(state.player.repeat_charges, 0); assert.equal(state.player.card_reservations.length, 0);
    } else if (id === 'hostile_reservations') {
      const attacks = resolved.filter(event => event.card_id === 'quick_slash'); assert.equal(attacks.length, 2);
      assert(attacks[0].result.metrics.damage < attacks[1].result.metrics.damage);
      assert.equal(observed.hostile_armed.enemy.card_reservations.length, 2);
      assert.equal(state.enemy.card_reservations.length, 0);
      assert(observed.hostile_result.enemy.runtime_states.some(runtime => runtime.card_id === 'quick_slash' && runtime.cooldown_remaining > 10));
    } else if (id === 'regeneration') {
      assert.equal(observed.regeneration_layers.player.statuses.regen.layers.length, 3);
      assert(state.battle_events.some(event => event.event_type === 'status_heal' && event.result.amount >= 3));
      assert(!state.player.statuses.regen); assert(state.player.hp > 20);
    } else if (id === 'damage_conversion') {
      const attacks = resolved.filter(event => event.card_id === 'quick_slash'); assert.equal(attacks.length, 2);
      assert(attacks[0].result.damage_prevented > 0 && attacks[0].hp_delta > 0);
      assert(attacks[1].result.damage_prevented > 0 && attacks[1].shield_delta > 0);
      const fatigue = state.battle_events.filter(event => event.event_type === 'fatigue_card'); assert.equal(fatigue.length, 1);
      assert(fatigue[0].result.player_before.statuses.damage_conversion);
      assert(fatigue[0].result.player_after.statuses.damage_conversion);
      assert(fatigue[0].result.player_after.hp < fatigue[0].result.player_before.hp);
    }
  }
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  for (const [language, viewport] of [['ja',{width:1440,height:900}],['en',{width:960,height:600}]]) {
    await page.setViewportSize(viewport);
    for (const id of ids) {
      let state;
      if (id === ids[0]) state = await command('tutorial_start', { tutorial:id, language });
      else {
        state = await command('tutorial_modal_focus', { name:`TutorialStart_${id}` });
        const startButton = state.controls.find(item => item.name === `TutorialStart_${id}`); assert(startButton);
        await point(state, startButton.rect); state = await command();
      }
      const seen = new Set(), observed = {}, start = Date.now(); let actions = 0;
      while (true) {
        const tutorial = state.tutorial, step = tutorial.step;
        assert(!tutorial.failed, `${id}: lesson entered retry at ${step.key}`);
        assert(Date.now() - start < 120000, `${id} stalled at ${step.key}`);
        checkBounds(state);
        if (!seen.has(step.key)) {
          seen.add(step.key); observed[step.key] = tutorial.state;
          if (shots.has(step.key)) {
            await page.mouse.move(10,100); await page.waitForTimeout(80);
            await page.screenshot({ path: resolve(output, `${language}-${step.key}.png`) });
          }
          if (step.key === 'regeneration_layers' || step.key === 'prepared_both' || step.key === 'hostile_armed' || step.key === 'conversion_life_armed') {
            const side = step.key === 'hostile_armed' ? 'enemy' : 'player';
            const region = tutorial.status_regions.find(region => region.side === side); assert(region, 'Missing live status icon');
            await point(state, region.rect, true); await page.waitForTimeout(180);
            state = await command(); assert(state.tutorial.status_tooltip.length > 0, `Status tooltip was not reachable at ${step.key}`);
          }
        }
        if (step.mode === 'complete') { validate(id, state.tutorial, observed); break; }
        if (step.mode === 'continue' || step.mode === 'queue_card') {
          const before = state.tutorial.state.battle_time;
          await page.waitForTimeout(140); state = await command();
          assert.equal(state.tutorial.state.battle_time, before, 'Reading a prompt advanced combat time');
          if (step.mode === 'continue') {
            const next = state.controls.find(item => item.name === 'TutorialContinueButton'); assert(next);
            await point(state, next.rect);
          } else {
            const card = state.tutorial.cards.find(card => card.id === step.card_id && card.ready); assert(card, `${id}: expected card not usable`);
            await point(state, card.rect);
          }
          actions++;
        } else await page.waitForTimeout(160);
        state = await command();
      }
      cases.push({id,language,viewport,steps:seen.size,actions,elapsedMs:Date.now()-start});
      console.log('TUTORIAL_PLAYTHROUGH_OK', JSON.stringify(cases.at(-1)));
      const finish = state.controls.find(item => item.name === 'TutorialContinueButton'); assert(finish);
      await point(state, finish.rect);
      assert((await command()).tutorial_modal.visible, 'Completion did not return to the tutorial window');
    }
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({cases,errors},null,2));
  console.log('WEB_ADVANCED_CARD_TUTORIAL_OK: eight real-time mouse-driven full playthroughs, live tooltips, pause guards and rendered outcomes');
} finally {
  await browser.close(); await new Promise(done => app.server.close(done));
}
