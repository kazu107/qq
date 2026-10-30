import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {mkdir,writeFile} from 'node:fs/promises';
const require=createRequire(import.meta.url),{createQqServer}=require('../server/server');
const {chromium}=process.env.QQ_NODE_MODULES?createRequire(resolve(process.env.QQ_NODE_MODULES,'../package.json'))('playwright'):require('playwright');
const out=resolve('tools/.local/sandbox/network-ui');await mkdir(out,{recursive:true});
const app=createQqServer({env:{},publicDir:resolve('build/web-layout-review'),iceServers:[]});await new Promise(done=>app.server.listen(0,'127.0.0.1',done));
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--disable-background-timer-throttling','--disable-renderer-backgrounding']});
const pages=[],errors=[];let sequence=0;
async function command(page,action='inspect',extra={}){const seq=++sequence;await page.evaluate(p=>window.qqLayoutCommand(JSON.stringify(p)),{action,...extra,sequence:seq});await page.waitForFunction(s=>JSON.parse(window.qqLayoutState||'{}').sequence===s,seq);return page.evaluate(()=>JSON.parse(window.qqLayoutState));}
async function wait(page,test){for(let i=0;i<150;i++){const s=await command(page);if(test(s))return s;await page.waitForTimeout(100);}throw Error('UI timeout: '+JSON.stringify(await command(page)));}
async function click(page,name){const s=await command(page),c=s.controls.find(c=>c.name===name);assert(c,name);const box=await page.locator('#canvas').boundingBox(),[x,y,w,h]=c.rect;await page.mouse.click(box.x+(x+w/2)*box.width/s.viewport[0],box.y+(y+h/2)*box.height/s.viewport[1]);await page.waitForTimeout(120);return command(page);}
async function type(page,name,text){await click(page,name);await page.keyboard.press('Control+A');await page.keyboard.type(text);return command(page);}
try{
  for(let i=0;i<2;i++){
    const ctx=await browser.newContext({viewport:{width:1440,height:900}}),page=await ctx.newPage();pages.push(page);
    page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|^ERROR:/m.test(m.text()))errors.push(m.text());});
    await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`,{waitUntil:'commit'});
    await page.waitForFunction(()=>window.qqLayoutCommand&&window.qqLoadMetrics?.some(m=>m.event==='scene_transition'&&m.details.screen==='Hub'),undefined,{timeout:180000});await page.waitForSelector('#status',{state:'detached'});
    await command(page,'sandbox_fixture');
  }
  const [host,guest]=pages,baseline=await Promise.all(pages.map(async p=>(await command(p)).sandbox_progress_hash));
  await command(host,'network_connect',{host:true,room:'SBUI01'});await wait(host,s=>s.network.connected);
  await command(guest,'network_connect',{room:'SBUI01'});await wait(host,s=>s.network.players.length===2);
  await click(host,'OnlineGameMode');await host.keyboard.press('Home');await host.keyboard.press('ArrowDown');await host.keyboard.press('ArrowDown');await host.keyboard.press('Enter');
  await wait(guest,s=>s.network.mode==='sandbox');
  await host.screenshot({path:resolve(out,'lobby.png')});
  await click(host,'LanReadyButton');await click(guest,'LanReadyButton');await wait(host,s=>s.network.players.every(p=>p.ready));await click(host,'LanStartMatchButton');
  for(const page of pages)await wait(page,s=>s.screen==='NetworkSandboxSetup');
  let s=await type(guest,'SandboxStat_player_attack','21');
  await wait(host,s=>Object.values(s.network.sandbox.configs).some(c=>c.attack===21));
  await wait(guest,s=>s.sandbox_setup.data.player.attack===21);
  await host.screenshot({path:resolve(out,'host-setup.png')});await guest.screenshot({path:resolve(out,'guest-setup.png')});
  s=await command(guest);assert(s.controls.find(c=>c.name==='SandboxTemplate_enemy').disabled,'opponent controls enabled');
  for(const size of [{width:960,height:600},{width:900,height:1200}]){await guest.setViewportSize(size);await guest.waitForTimeout(200);s=await command(guest);assert(s.sandbox_setup.horizontal_overflow<=1);await guest.screenshot({path:resolve(out,`setup-${size.width}.png`)});}
  await guest.setViewportSize({width:1440,height:900});
  await click(host,'SandboxStart');await click(guest,'SandboxStart');for(const p of pages)await wait(p,s=>s.screen==='Battle');
  for(const p of pages)await click(p,'BattleStartButton');
  await wait(host,s=>s.network.time>.5);
  await click(host,'NetworkSandboxToggle');await click(host,'NetworkSandboxPause');await wait(guest,s=>s.network.control.paused);
  const frozen=(await command(guest)).network.time;await guest.waitForTimeout(250);assert.equal((await command(guest)).network.time,frozen);
  await click(host,'NetworkSandboxStepSmall');await wait(guest,s=>s.network.time>frozen);
  await host.screenshot({path:resolve(out,'battle-host.png')});await guest.screenshot({path:resolve(out,'battle-guest.png')});
  await click(guest,'NetworkSandboxToggle');await click(guest,'NetworkSandboxStatistics');await wait(guest,s=>s.outcome.details);
  await guest.screenshot({path:resolve(out,'statistics.png')});
  await click(guest,'BattleDetailsClose');
  await click(host,'NetworkSandboxEditSetup');
  for(const p of pages)await wait(p,s=>s.screen==='NetworkSandboxSetup'&&s.network.phase==='preparation');
  for(let i=0;i<pages.length;i++)assert.equal((await command(pages[i])).sandbox_progress_hash,baseline[i]);
  assert.deepEqual(errors,[]);console.log('WEB_NETWORK_SANDBOX_UI_OK actual lobby/mode/editor/readiness/countdown/host controls/guest statistics/960+portrait/isolated saves');
}finally{
  await writeFile(resolve(out,'report.json'),JSON.stringify({errors,states:await Promise.all(pages.map(p=>command(p).catch(()=>null)))},null,2));
  await browser.close();app.server.closeAllConnections();await new Promise(done=>app.server.close(done));
}
