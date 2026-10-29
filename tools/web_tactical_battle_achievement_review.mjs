import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir,writeFile } from 'node:fs/promises';
const require=createRequire(import.meta.url);
const {createQqServer}=require('../server/server');
const {chromium}=process.env.QQ_NODE_MODULES?createRequire(resolve(process.env.QQ_NODE_MODULES,'../package.json'))('playwright'):require('playwright');
const output=resolve('tools/.local/advanced-achievements/browser');await mkdir(output,{recursive:true});
const app=createQqServer({env:{},publicDir:resolve('build/web-layout-review')});await new Promise(done=>app.server.listen(0,'127.0.0.1',done));
const browser=await chromium.launch({channel:'chrome',headless:true});const errors=[];
try {
  const page=await browser.newPage({viewport:{width:1440,height:900}});
  page.on('pageerror',error=>errors.push(String(error)));page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|^ERROR:/m.test(m.text()))errors.push(m.text());});
  let sequence=0;
  async function command(action='inspect',extra={}){const seq=++sequence;await page.evaluate(p=>window.qqLayoutCommand(JSON.stringify(p)),{action,...extra,sequence:seq});await page.waitForFunction(n=>JSON.parse(window.qqLayoutState||'{}').sequence===n,seq);return page.evaluate(()=>JSON.parse(window.qqLayoutState));}
  async function click(state,rect){const box=await page.locator('#canvas').boundingBox(),[x,y,w,h]=rect;await page.mouse.click(box.x+(x+w/2)*box.width/state.viewport[0],box.y+(y+h/2)*box.height/state.viewport[1]);}
  async function waitFor(predicate){for(let i=0;i<160;i++){const s=await command();if(predicate(s))return s;await page.waitForTimeout(100);}throw new Error('Timed out waiting for real battle effect');}
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`,{waitUntil:'commit'});
  await page.waitForFunction(()=>window.qqLayoutCommand&&window.qqLoadMetrics?.some(i=>i.event==='scene_transition'&&i.details.screen==='Hub'),undefined,{timeout:180000});await page.waitForSelector('#status',{state:'detached'});
  await command('tactical_battle_fixture');let s=await command('tactical_battle_prepare');assert(s.tactical_battle.eligible);
  for(const id of ['reserve_focus','echo_cast','quick_slash']){
    const card=s.tactical_battle.cards.find(c=>c.id===id&&c.ready);assert(card,id);await click(s,card.rect);
    s=await waitFor(v=>id==='reserve_focus'?v.tactical_battle.reservations===1:id==='echo_cast'?v.tactical_battle.repeat===1:v.tactical_stats.echo_uses===1);
  }
  assert.equal(s.tactical_stats.echo_uses,1);assert.equal(s.tactical_stats.reservation_uses,1);
  assert.equal(s.tactical_stats.actual_damage_total,24);assert.equal(s.tactical_stats.max_hit_damage,15);
  await page.screenshot({path:resolve(output,'real-battle-victory.png')});
  s=await command('screen',{screen:'hub'});assert(s.achievement_notice.visible);
  await click(s,s.controls.find(c=>c.name==='HubMetaProgressButton').rect);
  await waitFor(v=>v.meta_modal?.ready&&v.meta_modal.visible);
  s=await command('meta_modal_focus',{name:'ClaimAchievement_echo_practitioner'});
  const claim=s.controls.find(c=>c.name==='ClaimAchievement_echo_practitioner');assert(claim);
  await page.screenshot({path:resolve(output,'earned-echo-achievement.png')});
  await click(s,claim.rect);s=await command();assert.equal(s.meta_modal.claims.echo_practitioner,1);
  await page.keyboard.press('Escape');await command();
  await command('screen',{screen:'library'});s=await command('screen',{screen:'hub'});
  assert.equal(s.tactical_stats.echo_uses,1);assert.deepEqual(errors,[]);
  await writeFile(resolve(output,'real-battle-report.json'),JSON.stringify({stats:s.tactical_stats,errors},null,2));
  console.log('WEB_TACTICAL_BATTLE_ACHIEVEMENT_OK: real card inputs, two effect resolutions, capped damage, result-to-hub notification and reward claim');
}finally{await browser.close();await new Promise(done=>app.server.close(done));}
