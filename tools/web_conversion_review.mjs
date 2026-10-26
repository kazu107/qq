import assert from 'node:assert/strict';
import {createRequire} from 'node:module';import {resolve} from 'node:path';import {mkdir,writeFile} from 'node:fs/promises';
const require=createRequire(import.meta.url);const {createQqServer}=require('../server/server');
const {chromium}=createRequire(resolve(process.env.QQ_NODE_MODULES,'../package.json'))('playwright');
const output=resolve('tools/.local/conversion/browser');await mkdir(output,{recursive:true});
const app=createQqServer({env:{},publicDir:resolve('build/web-layout-review')});await new Promise(r=>app.server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:'chrome',headless:true});const errors=[],checks=[];
try{
 const page=await browser.newPage({viewport:{width:1440,height:900}});page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|^ERROR:/.test(m.text()))errors.push(m.text());});
 await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);await page.waitForFunction(()=>window.qqLoadMetrics?.some(x=>x.event==='scene_transition'&&x.details.screen==='Hub'),undefined,{timeout:180000});await page.waitForSelector('#status',{state:'detached'});
 let sequence=0;
 async function command(action,extra={}){const n=++sequence;await page.evaluate(p=>window.qqLayoutCommand(JSON.stringify(p)),{action,...extra,sequence:n});await page.waitForFunction(n=>JSON.parse(window.qqLayoutState||'{}').sequence===n,n);return page.evaluate(()=>JSON.parse(window.qqLayoutState));}
 async function until(predicate){for(let i=0;i<150;i++){const s=await command('inspect');if(predicate(s))return s;await page.waitForTimeout(100);}throw Error('Conversion view timed out');}
 async function point(s,x,y,click=true){const b=await page.locator('#canvas').boundingBox();const px=b.x+x*b.width/s.viewport[0],py=b.y+y*b.height/s.viewport[1];if(click)await page.mouse.click(px,py);else await page.mouse.move(px,py);return command('inspect');}
 async function button(s,id){for(let i=0;i<12;i++){const c=s.controls.find(c=>c.name===id);assert(c,id);const p=s.controls.find(c=>c.name==='DeveloperPanel');if(id==='DeveloperPanelToggle'||!p||c.rect[1]>=p.rect[1]+60&&c.rect[1]+c.rect[3]<=p.rect[1]+p.rect[3]-18)return point(s,c.rect[0]+c.rect[2]/2,c.rect[1]+c.rect[3]/2);await point(s,p.rect[0]+p.rect[2]/2,p.rect[1]+p.rect[3]-70,false);await page.mouse.wheel(0,c.rect[1]<p.rect[1]+60?-100:100);await page.waitForTimeout(100);s=await command('inspect');}throw Error('Developer scroll '+id);}
 for(const language of ['ja','en'])for(const mode of ['life_conversion','barrier_conversion']){
  await command('conversion_fixture',{language});let s=await until(s=>s.screen==='Battle'&&s.echo?.hand.length===4);
  s=await command('echo_control',{setup:true,player_hp:20});const c=s.echo.hand.find(c=>c.id===mode);s=await point(s,c.rect[0]+c.rect[2]/2,c.rect[1]+c.rect[3]/2);
  s=await command('echo_control',{seconds:1.2});assert.equal(s.echo.conversion.ratio,.25);assert.equal(s.echo.conversion.duration,4);
  s=await command('conversion_attack');const prevented=s.echo.prevented;assert(prevented>0);const gained=Math.floor(prevented*.25);
  assert.equal(s.echo.player_hp,20+(mode==='life_conversion'?gained:0));assert.equal(s.echo.shield,mode==='barrier_conversion'?gained:0);
  s=await until(s=>s.echo.numbers.includes('+'+gained));await page.screenshot({path:resolve(output,`hit-${language}-${mode}.png`)});
  s=await button(s,'DeveloperPanelToggle');
  for(const size of [{width:1440,height:900},{width:960,height:600},{width:900,height:1200}]){
   await page.setViewportSize(size);s=await command('inspect');const points=s.echo.status_regions.find(r=>r.id==='damage_conversion').points;
   s=await point(s,points.reduce((n,p)=>n+p[0],0)/points.length,points.reduce((n,p)=>n+p[1],0)/points.length,false);s=await until(s=>s.echo.tooltip.includes('25%'));
   assert(s.echo.tooltip.toLowerCase().includes(language==='ja'?'疲労':'fatigue'));
   const p=s.controls.find(c=>c.name==='WorldStatusTooltip');assert(p);const[x,y,w,h]=p.rect;assert(x>=0&&y>=0&&x+w<=s.viewport[0]+1&&y+h<=s.viewport[1]+1,'Conversion tooltip clipped');
   await page.screenshot({path:resolve(output,`status-${language}-${mode}-${size.width}.png`)});
  }
  await page.setViewportSize({width:1440,height:900});s=await command('inspect');const hp=s.echo.player_hp;
  s=await command('conversion_fatigue');assert(s.echo.player_hp<hp);assert.equal(s.echo.prevented,prevented);assert(s.echo.conversion.duration>0,'Fatigue test must occur while protected');
  s=await command('echo_control',{seconds:s.echo.conversion.duration+.001});assert.deepEqual(s.echo.conversion,{});assert(s.echo.conversion_lockout.duration>0);
  s=await button(s,'DeveloperPanelToggle');s=await button(s,'DevConversionLife');assert.equal(s.echo.conversion.ratio,.5);assert.equal(s.echo.conversion.mode,'heal');
  s=await button(s,'DevConversionShield');assert.equal(s.echo.conversion.mode,'shield');s=await button(s,'DevConversionClear');assert.deepEqual(s.echo.conversion,{});assert.deepEqual(s.echo.conversion_lockout,{});
  checks.push(`${language}:${mode}:real_card_incoming_hit_fatigue_bypass_3_sizes_tooltip_expiry_developer`);
 }
 assert.deepEqual(errors,[]);console.log('WEB_CONVERSION_REVIEW_OK',checks);
}finally{await writeFile(resolve(output,'report.json'),JSON.stringify({checks,errors},null,2));await browser.close();await new Promise(r=>app.server.close(r));}
