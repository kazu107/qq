import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const out = resolve('tools/.local/sandbox/browser');
await mkdir(out, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [];
let page, sequence = 0;
async function command(action = 'inspect', extra = {}) {
  const seq = ++sequence;
  await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: seq });
  await page.waitForFunction(value => JSON.parse(window.qqLayoutState || '{}').sequence === value, seq);
  return page.evaluate(() => JSON.parse(window.qqLayoutState));
}
async function rectClick(state, rect) {
  const box = await page.locator('#canvas').boundingBox(), [x,y,w,h] = rect;
  await page.mouse.click(box.x+(x+w/2)*box.width/state.viewport[0], box.y+(y+h/2)*box.height/state.viewport[1]);
  await page.waitForTimeout(100);
  return command();
}
async function click(state, name) {
  const control = state.controls.find(item => item.name === name); assert(control, name);
  return rectClick(state, control.rect);
}
async function type(state, name, text) {
  await click(state, name); await page.keyboard.press('Control+A'); await page.keyboard.type(text);
  await page.waitForTimeout(60); return command();
}
async function option(state, name, index) {
  await click(state, name); await page.keyboard.press('Home');
  for (let i=0; i<=index; i++) await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter'); return command();
}
async function boot() {
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout:180000 });
  await page.waitForSelector('#status', { state:'detached' });
}
try {
  page = await browser.newPage({ viewport:{width:1440,height:900} });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text())) errors.push(message.text()); });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`, {waitUntil:'commit'}); await boot();
  let state = await command('sandbox_fixture'), original = state.sandbox_progress_hash;
  assert.equal(state.developer,false);
  state = await click(state,'SandboxModeButton');
  assert.equal(state.sandbox_setup.models,2); assert.equal(state.sandbox_setup.columns,2);
  assert(state.sandbox_setup.cards_available>=133 && state.sandbox_setup.relics_available===86);
  state = await click(state,'SandboxExample_dummy');
  state = await type(state,'SandboxStat_player_attack','17');
  assert.equal(state.sandbox_setup.data.player.attack,17,'typing must update without Enter');
  state = await click(state,'SandboxAddCard_player');
  state = await type(state,'SandboxCatalogSearch','quick_slash');
  state = await click(state,'SandboxPick_quick_slash'); state = await click(state,'SandboxCatalogClose');
  const last = state.sandbox_setup.data.player.cards.length-1;
  state = await command('sandbox_focus',{name:`SandboxGrade_player_${last}`});
  state = await option(state,`SandboxGrade_player_${last}`,5);
  assert.equal(state.sandbox_setup.data.player.cards[last].tier,5);
  state = await click(state,'SandboxAddRelic_enemy');
  state = await type(state,'SandboxCatalogSearch','fourth_reserve_rack');
  state = await click(state,'SandboxPick_fourth_reserve_rack'); state = await click(state,'SandboxCatalogClose');
  assert(state.sandbox_setup.data.enemy.relics.includes('fourth_reserve_rack'));
  state = await type(state,'SandboxPresetName','browser test');
  state = await click(state,'SandboxSavePreset'); assert(state.sandbox_presets.includes('browser test'));
  state = await click(state,'SandboxExample_regen'); state = await click(state,'SandboxLoadPreset');
  assert.equal(state.sandbox_setup.data.player.attack,17);
  assert.equal(state.sandbox_progress_hash,original);
  for (const size of [{width:1440,height:900},{width:960,height:600},{width:900,height:1200},{width:390,height:844}]) {
    await page.setViewportSize(size); await page.waitForTimeout(200); state=await command();
    assert(state.sandbox_setup.horizontal_overflow<=1,`overflow ${size.width}`);
    await page.screenshot({path:resolve(out,`setup-ja-${size.width}.png`)});
    cases.push(`JA ${size.width}x${size.height}: setup fits`);
  }
  await page.setViewportSize({width:1440,height:900}); await page.waitForTimeout(150); state=await command();
  state=await click(state,'SandboxExample_echo');
  state=await type(state,'SandboxStat_player_attack','999');
  state=await command('sandbox_focus',{name:'SandboxStat_enemy_hp'});
  state=await type(state,'SandboxStat_enemy_hp','20');
  state=await click(state,'SandboxStart');
  assert(state.sandbox_battle.active && !state.sandbox_battle.eligible);
  assert.equal(state.sandbox_progress_hash,original);
  state=await click(state,'SandboxDockToggle'); state=await click(state,'SandboxPause');
  const pausedTime=state.sandbox_battle.time;
  await page.waitForTimeout(300); state=await command(); assert.equal(state.sandbox_battle.time,pausedTime);
  state=await click(state,'SandboxQueueEnemy'); assert.equal(state.sandbox_battle.instances,1);
  state=await click(state,'SandboxStep_0_1'); assert(Math.abs(state.sandbox_battle.time-pausedTime-.1)<.001);
  state=await click(state,'SandboxStatistics'); assert(state.sandbox_battle.paused && state.outcome.details);
  state=await click(state,'BattleDetailsClose'); assert(!state.outcome.details);
  await page.screenshot({path:resolve(out,'battle-ja.png')});
  state=await click(state,'SandboxDockToggle');
  const quick=state.echo.hand.find(item=>item.id==='quick_slash'); assert(quick);
  state=await rectClick(state,quick.rect);
  state=await click(state,'SandboxDockToggle');
  for(let i=0;i<5 && !state.sandbox_battle.winner;i++) state=await click(state,'SandboxStep_1_0');
  assert.equal(state.sandbox_battle.winner,'player');
  await page.waitForFunction(()=>JSON.parse(window.qqLayoutState||'{}').outcome?.visible===true,undefined,{timeout:1000}).catch(()=>{});
  for(let i=0;i<50;i++) { state=await command(); if(state.controls.some(item=>item.name==='BattleReplayButton')) break; await page.waitForTimeout(100); }
  await page.screenshot({path:resolve(out,'result-ja.png')});
  state=await click(state,'BattleReplayButton'); assert.equal(state.sandbox_battle.time,0);
  state=await click(state,'SandboxDockToggle'); state=await click(state,'SandboxBattleBack');
  assert.equal(state.sandbox_setup.data.player.attack,999);
  state=await click(state,'SandboxBack'); assert.equal(state.screen,'Hub'); assert.equal(state.sandbox_progress_hash,original);
  await page.reload({waitUntil:'commit'}); await boot(); state=await command();
  assert(state.sandbox_presets.includes('browser test'),'preset did not survive browser reload');
  state=await click(state,'OpenSettingsButton'); state=await option(state,'LanguageOptionButton',0);
  assert.equal(state.settings_modal.language,'en');
  state=await click(state,'SettingsCloseButton'); state=await click(state,'SandboxModeButton');
  assert(state.controls.some(item=>item.name==='SandboxStart' && item.text==='Start Battle'));
  await page.screenshot({path:resolve(out,'setup-en.png')});
  state=await click(state,'SandboxDeletePreset'); assert(!state.sandbox_presets.includes('browser test'));
  assert.deepEqual(errors,[]);
  console.log('WEB_SANDBOX_OK',JSON.stringify({cases,checks:'public entry/models/live edit/catalog/grade/relic/presets/reload/pause/step/enemy/statistics/victory/restart/isolation/locale',errors}));
} finally {
  if(page) await page.screenshot({path:resolve(out,'last.png')}).catch(()=>{});
  await writeFile(resolve(out,'report.json'),JSON.stringify({cases,errors,state:page ? await page.evaluate(()=>window.qqLayoutState).catch(()=>null) : null},null,2));
  await browser.close(); app.server.closeAllConnections(); await new Promise(done=>app.server.close(done));
}
