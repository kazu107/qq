import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
const require=createRequire(import.meta.url);
const {createQqServer}=require('../server/server');
const {chromium}=createRequire(resolve(process.env.QQ_NODE_MODULES,'../package.json'))('playwright');
const output=resolve('tools/.local/regeneration/browser');await mkdir(output,{recursive:true});
const app=createQqServer({env:{},publicDir:resolve('build/web-layout-review')});
await new Promise(done=>app.server.listen(0,'127.0.0.1',done));
const browser=await chromium.launch({channel:'chrome',headless:true});
const errors=[],checks=[];
try{
  const page=await browser.newPage({viewport:{width:1440,height:900}});
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|^ERROR:/.test(m.text()))errors.push(m.text());});
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForFunction(()=>window.qqLoadMetrics?.some(x=>x.event==='scene_transition'&&x.details.screen==='Hub'),undefined,{timeout:180000});
  await page.waitForSelector('#status',{state:'detached'});
  let seq=0;
  async function command(action,extra={}){const sequence=++seq;await page.evaluate(p=>window.qqLayoutCommand(JSON.stringify(p)),{action,...extra,sequence});await page.waitForFunction(n=>JSON.parse(window.qqLayoutState||'{}').sequence===n,sequence);return page.evaluate(()=>JSON.parse(window.qqLayoutState));}
  async function until(predicate){for(let i=0;i<150;i++){const s=await command('inspect');if(predicate(s))return s;await page.waitForTimeout(100);}throw Error('Regen view timed out');}
  async function point(s,x,y,click=true){const b=await page.locator('#canvas').boundingBox();const px=b.x+x*b.width/s.viewport[0],py=b.y+y*b.height/s.viewport[1];if(click)await page.mouse.click(px,py);else await page.mouse.move(px,py);return command('inspect');}
  async function button(s,id){
    for(let i=0;i<6;i++){
      const c=s.controls.find(c=>c.name===id);assert(c,id);
      const panel=s.controls.find(c=>c.name==='DeveloperPanel');
      if(id==='DeveloperPanelToggle'||!panel||c.rect[1]+c.rect[3]<=panel.rect[1]+panel.rect[3]-18)return point(s,c.rect[0]+c.rect[2]/2,c.rect[1]+c.rect[3]/2);
      await point(s,panel.rect[0]+panel.rect[2]/2,panel.rect[1]+panel.rect[3]-60,false);await page.mouse.wheel(0,160);await page.waitForTimeout(100);s=await command('inspect');
    }
    throw Error('Developer button could not scroll into view: '+id);
  }
  for(const language of ['ja','en']){
    await command('regen_fixture',{language});let state=await until(s=>s.screen==='Battle'&&s.echo?.hand.length===8);
    state=await command('echo_control',{setup:true,player_hp:20});
    const card=state.echo.hand.find(c=>c.id==='regen_patch');state=await point(state,card.rect[0]+card.rect[2]/2,card.rect[1]+card.rect[3]/2);
    state=await command('echo_control',{seconds:2.4});assert.equal(state.echo.regen.power,2);assert.equal(state.echo.player_hp,20);
    state=await command('echo_control',{seconds:3});assert.equal(state.echo.player_hp,22);
    state=await until(s=>s.echo.numbers.includes('+2'));await page.screenshot({path:resolve(output,`tick-${language}.png`)});
    state=await button(state,'DeveloperPanelToggle');
    for(const size of [{width:1440,height:900},{width:960,height:600},{width:900,height:1200}]){
      await page.setViewportSize(size);state=await command('inspect');
      const points=state.echo.status_regions.find(r=>r.id==='regen').points;
      state=await point(state,points.reduce((n,p)=>n+p[0],0)/points.length,points.reduce((n,p)=>n+p[1],0)/points.length,false);
      state=await until(s=>s.echo.tooltip.includes(language==='ja'?'次の回復':'Next heal'));
      const p=state.controls.find(c=>c.name==='WorldStatusTooltip');assert(p);const[x,y,w,h]=p.rect;
      assert(x>=0&&y>=0&&x+w<=state.viewport[0]+1&&y+h<=state.viewport[1]+1,'Regen tooltip clipped');
      assert(state.echo.tooltip.includes('1/3'));await page.screenshot({path:resolve(output,`status-${language}-${size.width}.png`)});
    }
    state=await command('echo_control',{seconds:1});assert.equal(state.echo.player_hp,22);assert(state.echo.tooltip.includes('2.0'));
    await page.setViewportSize({width:1440,height:900});state=await command('inspect');
    state=await button(state,'DeveloperPanelToggle');state=await button(state,'DevRegenApply');assert.equal(state.echo.regen.stacks,3);assert.equal(state.echo.regen.power,9);
    state=await button(state,'DevRegenClear');assert.deepEqual(state.echo.regen,{});
    checks.push(`${language}:8_card_icons_real_click_3s_tick_number_live_tooltip_3_sizes_developer`);
  }
  assert.deepEqual(errors,[]);console.log('WEB_REGENERATION_REVIEW_OK',checks);
}finally{await writeFile(resolve(output,'report.json'),JSON.stringify({checks,errors},null,2));await browser.close();await new Promise(done=>app.server.close(done));}
