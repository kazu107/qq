import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
const require=createRequire(import.meta.url);
const {createQqServer}=require('../server/server');
const {chromium}=process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES,'../package.json'))('playwright') : require('playwright');
const out=resolve('tools/.local/sandbox/network-browser');await mkdir(out,{recursive:true});
const app=createQqServer({env:{},publicDir:resolve('build/web-validation'),iceServers:[]});
await new Promise(done=>app.server.listen(0,'127.0.0.1',done));
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--disable-background-timer-throttling','--disable-renderer-backgrounding']});
const pages=[],errors=[],cases=[],baselines=[];
const maximum=Number(process.env.QQ_SANDBOX_MAX_PLAYERS||4);
const state=page=>page.evaluate(()=>JSON.parse(window.qqState||'{}'));
const command=(page,action,data={})=>page.evaluate(payload=>window.qqCommand(JSON.stringify(payload)),{action,...data});
async function wait(page,test,timeout=30000){const start=Date.now();while(Date.now()-start<timeout){const s=await state(page);if(test(s))return s;await page.waitForTimeout(100);}throw Error(`Timeout ${JSON.stringify(await state(page))}`);}
try {
  for(let i=0;i<maximum+1;i++){
    const context=await browser.newContext({viewport:{width:960,height:600}}),page=await context.newPage();pages.push(page);
    page.on('pageerror',error=>errors.push(`${i}: ${error}`));page.on('console',message=>{if(/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text()))errors.push(`${i}: ${message.text()}`);});
    await page.goto(`http://127.0.0.1:${app.server.address().port}`,{waitUntil:'commit'});await wait(page,s=>s.ticks>2,90000);
  }
  for(const count of [2,4,6,8].filter(n=>n<=maximum)){
    console.log('Sandbox scenario',count);
    const players=pages.slice(0,count),host=players[0],watcher=pages[maximum],room=`SB000${count}`;
    const before=await Promise.all([...players,watcher].map(async page=>(await state(page)).progress_hash));
    baselines.push(await Promise.all([...players,watcher].map(async page=>(await state(page)).progress_state)));
    await command(host,'host',{room,players:count});await wait(host,s=>s.connected);
    for(let i=1;i<count;i++)await command(players[i],'join',{room,name:`P${i+1}`});
    await command(watcher,'join',{room,name:'Observer',spectator:true});await wait(host,s=>s.players.length===count+1);
    await command(host,'sandbox_mode');await wait(watcher,s=>s.sandbox.mode==='sandbox');
    for(const page of players)await command(page,'lobby_ready');await wait(host,s=>s.players.filter(p=>p.ready).length===count);
    await command(host,'prepare');for(const page of [...players,watcher])await wait(page,s=>s.phase==='preparation');
    for(let i=0;i<count;i++){
      const revision=(await state(host)).sandbox.revision;
      await command(players[i],'sandbox_setup',{side:{max_hp:1000,hp:500+i*10,attack:3+i,cards:[{id:'quick_slash',tier:0},{id:'quick_slash',tier:5}]},...(i===0?{rules:{fatigue:false,field:'rift_gallery'}}:{})});
      await wait(host,s=>s.sandbox.revision>revision);
      for(const page of [...players,watcher])await wait(page,s=>s.sandbox.revision>revision);
    }
    await command(players[1],'sandbox_stale');await wait(players[1],s=>s.sandbox_action.action==='set_ready'&&!s.sandbox_action.accepted);
    assert.equal((await state(host)).arena_ready,0,'stale readiness applied');
    for(let i=0;i<count;i++){
      await command(players[i],'sandbox_ready');
      await wait(host,s=>s.arena_ready>=i+1 || s.phase==='battle');
    }
    for(const page of [...players,watcher])await wait(page,s=>s.phase==='battle' && Object.values(s.sandbox_grades).includes(5));
    for(const page of players)await command(page,'start');
    for(const page of players)await wait(page,s=>s.battle_time>.1);
    for(const page of players)await command(page,'use_card',{index:1});
    await wait(host,s=>s.battle_time>2.5);
    const first=(await state(host)).matches.match_id;
    await command(host,'sandbox_control',{kind:'pause',value:1,match:first});
    let frozen=await wait(host,s=>s.sandbox_control.paused);const pausedTime=frozen.battle_time;
    await host.waitForTimeout(350);assert.equal((await state(host)).battle_time,pausedTime);
    await command(host,'sandbox_control',{kind:'step',value:.1,match:first});frozen=await wait(host,s=>s.battle_time>pausedTime);
    assert(Math.abs(frozen.battle_time-pausedTime-.1)<.00001,'step length drifted');
    await command(watcher,'sandbox_statistics');await wait(watcher,s=>s.sandbox_stats.sandbox && s.sandbox_stats.analysis.hp_history.length>1);
    const oldMatch=(await state(players[1])).matches.match_id;
    await command(players[1],'drop_transport');await wait(players[1],s=>s.reconnecting&&!s.connected);
    await wait(players[1],s=>s.connected&&!s.reconnecting && s.matches.match_id===oldMatch);
    if(count>2){
      const other=(await state(players[1])).matches.match_id;
      assert.notEqual(first,other);const t=(await state(players[1])).battle_time;
      await host.waitForTimeout(300);assert((await state(players[1])).battle_time>t,'other pairing paused too');
      await command(watcher,'sandbox_watch',{match:other});await wait(watcher,s=>s.matches.match_id===other);
      await command(watcher,'sandbox_watch',{match:first});await wait(watcher,s=>s.matches.match_id===first);
    }
    assert.deepEqual((await state(watcher)).run,{},'spectator acquired a player run');
    await command(host,'sandbox_control',{kind:'restart',match:first});
    const reset=await wait(host,s=>s.matches.match_id!==first && s.battle_time===0);assert(reset.sandbox_grades.player_1===5);
    for(const page of players)if((await state(page)).matches.match_id===reset.matches.match_id)await command(page,'start');
    await wait(host,s=>s.battle_time>.1);await command(host,'sandbox_control',{kind:'pause',value:1});await wait(host,s=>s.sandbox_control.paused);
    await command(host,'sandbox_old_command',{match:first});await host.waitForTimeout(200);assert.equal((await state(host)).active_count,0,'old battle command reached a new match');
    for(let i=0;i<count/2;i++)await command(host,'force_pair',{index:i,winner:i===0?'player':'enemy'});
    for(const page of [...players,watcher])await wait(page,s=>s.results.all_complete);
    for(const page of players){const run=(await state(page)).run;assert.equal(run.arena_wins,0);assert.equal(run.arena_losses,0);assert.equal(run.gold,0);}
    assert.equal((await state(watcher)).results.standings.length,count);
    for(const page of players)await command(page,'ack');
    for(const page of [...players,watcher])await wait(page,s=>s.phase==='preparation');
    const after=await Promise.all([...players,watcher].map(async page=>(await state(page)).progress_hash));assert.deepEqual(after,before,'real progress changed');
    cases.push(`${count} players + spectator: shared Grades/config, stale ready rejection, countdown, real cards, independent pause/step, same-seat reconnect, statistics, restart, result barrier, no rewards/achievements/save mutation`);
    await command(host,'leave');
    for(const page of [...players.slice(1),watcher]){await wait(page,s=>!s.connected);await command(page,'leave');await command(page,'clear_error');}
  }
  assert.deepEqual(errors,[]);console.log('WEB_NETWORK_SANDBOX_E2E_OK',JSON.stringify(cases));
}finally{
  await writeFile(resolve(out,'report.json'),JSON.stringify({cases,errors,baselines,states:await Promise.all(pages.map(state))},null,2));
  await browser.close();app.server.closeAllConnections();await new Promise(done=>app.server.close(done));
}
