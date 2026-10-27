import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require=createRequire(import.meta.url);
const {createQqServer}=require('../server/server');
const {chromium}=process.env.QQ_NODE_MODULES?createRequire(resolve(process.env.QQ_NODE_MODULES,'../package.json'))('playwright'):require('playwright');
const out=resolve('tools/.local/smooth-scroll/browser'); await mkdir(out,{recursive:true});
const app=createQqServer({env:{},publicDir:resolve('build/web-layout-review')});
await new Promise(done=>app.server.listen(0,'127.0.0.1',done));
const origin=`http://127.0.0.1:${app.server.address().port}`;
const browser=await chromium.launch({channel:'chrome',headless:true});
const errors=[],cases=[];
try {
  const page=await browser.newPage({viewport:{width:1440,height:900}});
  page.on('pageerror',error=>errors.push(String(error)));
  page.on('console',message=>{if(/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text()))errors.push(message.text());});
  await page.goto(origin+'/?pack=local',{waitUntil:'commit'});
  await page.waitForFunction(()=>window.qqLayoutCommand&&window.qqLoadMetrics?.some(item=>item.event==='scene_transition'&&item.details.screen==='Hub'),undefined,{timeout:180000});
  await page.waitForSelector('#status',{state:'detached'});
  let sequence=0;
  async function command(action='inspect',extra={}) {
    const seq=++sequence;await page.evaluate(payload=>window.qqLayoutCommand(JSON.stringify(payload)),{action,...extra,sequence:seq});
    await page.waitForFunction(seq=>JSON.parse(window.qqLayoutState||'{}').sequence===seq,seq);
    return page.evaluate(()=>JSON.parse(window.qqLayoutState));
  }
  async function click(state,name) {
    const control=state.controls.find(c=>c.name===name);assert(control,name);
    const box=await page.locator('#canvas').boundingBox(),[x,y,w,h]=control.rect;
    await page.mouse.click(box.x+(x+w/2)*box.width/state.viewport[0],box.y+(y+h/2)*box.height/state.viewport[1]);
    await page.waitForTimeout(120);return command();
  }
  async function wheel(name,scope='') {
    const state=await command('wheel_watch',{name,scope});
    const before=await page.evaluate(()=>JSON.parse(window.qqWheelTrace));
    const box=await page.locator('#canvas').boundingBox(),[x,y,w,h]=before.rect;
    await page.mouse.move(box.x+(x+w*.72)*box.width/state.viewport[0],box.y+(y+h*.48)*box.height/state.viewport[1]);
    await page.mouse.wheel(0,120);await page.waitForTimeout(420);
    const trace=await page.evaluate(()=>JSON.parse(window.qqWheelTrace));
    const values=trace.samples.map(s=>s.value),start=values[0],end=trace.value;
    assert(end>start+1,`${name}: no movement: ${JSON.stringify(trace)}`);
    assert(values.some(v=>v>start+.01&&v<end-.01),`${name}: jumped without an intermediate frame`);
    assert.equal(trace.active,false,`${name}: animation did not settle`);
    cases.push({name,scope,start,end,intermediate:values.filter(v=>v>start+.01&&v<end-.01).length});
    await page.screenshot({path:resolve(out,`${scope||'main'}-${name||'library'}.png`)});
    return trace;
  }
  let state=await command();state=await click(state,'HubMetaProgressButton');
  await wheel('MetaWindowScroll','meta');
  await page.keyboard.press('Escape');state=await command();
  state=await click(state,'VersionHistoryButton');await wheel('VersionHistoryContent');
  await page.keyboard.press('Escape');
  await command('screen',{screen:'library'});await page.waitForTimeout(400);await wheel('','library');
  state=await click(await command(),'LibraryTypeFilter');await wheel('LibraryTypeFilter','option_popup');await page.keyboard.press('Escape');
  state=await command('screen',{screen:'hub_developer'});await page.waitForTimeout(350);
  await wheel('DeveloperActionsScroll');
  state=await command('wheel_fixture_focus',{name:'DebugCardSlot0'});state=await click(state,'DebugCardSlot0');
  await wheel('CardIconPickerScroll','popup');await page.keyboard.press('Escape');
  assert.deepEqual(errors,[]);
  console.log('GODOT_WEB_SMOOTH_SCROLL_OK',JSON.stringify(cases));

  const dom=await browser.newPage({viewport:{width:1100,height:800}});
  dom.on('pageerror',error=>errors.push(String(error)));
  await dom.goto(origin+'/account?lang=en');
  await dom.evaluate(()=>{
    const host=document.createElement('div');host.id='wheelFixture';host.style.cssText='position:fixed;left:20px;top:20px;width:700px;height:500px;z-index:99999;background:#123;padding:20px';
    const outer=document.createElement('div');outer.id='wheelOuter';outer.style.cssText='height:300px;width:600px;overflow:auto';
    const outerBody=document.createElement('div');outerBody.style.height='2000px';outer.append(outerBody);
    const inner=document.createElement('div');inner.id='wheelInner';inner.style.cssText='height:160px;width:400px;overflow:auto;background:#456';outerBody.append(inner);
    const innerBody=document.createElement('div');innerBody.style.cssText='height:1400px;width:800px';innerBody.textContent='Wheel target';inner.append(innerBody);host.append(outer);
    document.body.append(host);
    window.wheelEvents=[];document.addEventListener('wheel',event=>window.wheelEvents.push({target:event.target.id,shift:event.shiftKey,dx:event.deltaX,dy:event.deltaY,mode:event.deltaMode,prevented:event.defaultPrevented,inner:document.getElementById('wheelInner').scrollTop,outer:document.getElementById('wheelOuter').scrollTop}));
    window.domTrace=[];let frames=0;function sample(){window.domTrace.push(document.getElementById('wheelInner').scrollTop);if(++frames<120)requestAnimationFrame(sample);}requestAnimationFrame(sample);
  });
  await dom.locator('#wheelInner').hover();await dom.mouse.wheel(0,240);await dom.waitForTimeout(350);
  const data=await dom.evaluate(()=>({trace:window.domTrace,events:window.wheelEvents,value:document.getElementById('wheelInner').scrollTop,left:document.getElementById('wheelInner').scrollLeft,outer:document.getElementById('wheelOuter').scrollTop,hidden:document.hidden}));
  await writeFile(resolve(out,'dom-data.json'),JSON.stringify(data,null,2));
  assert.equal(data.events.at(-1).prevented,true);assert.equal(data.events.at(-1).inner,0);assert.equal(data.value,240);
  assert(data.trace.some(v=>v>0&&v<240),'DOM wheel jumped instantly');
  await dom.evaluate(()=>{const n=document.getElementById('wheelInner');n.scrollTop=n.scrollHeight-n.clientHeight;});
  await dom.mouse.wheel(0,180);await dom.waitForTimeout(250);
  assert((await dom.evaluate(()=>document.getElementById('wheelOuter').scrollTop))>0,'DOM edge did not chain');
  await dom.evaluate(()=>{const n=document.getElementById('wheelInner');n.scrollTop=0;n.dispatchEvent(new WheelEvent('wheel',{bubbles:true,cancelable:true,deltaY:200}));n.scrollTop=500;});
  await dom.waitForTimeout(250);assert.equal(await dom.evaluate(()=>document.getElementById('wheelInner').scrollTop),500);
  await dom.emulateMedia({reducedMotion:'reduce'});
  assert.equal(await dom.evaluate(()=>{const n=document.getElementById('wheelInner');const e=new WheelEvent('wheel',{bubbles:true,cancelable:true,deltaY:100});n.dispatchEvent(e);return e.defaultPrevented;}),false);
  await dom.close();
  assert.deepEqual(errors,[]);
  console.log('DOM_SMOOTH_SCROLL_OK interpolation/nesting/native-wheel/external-jump/reduced-motion');
}finally{await writeFile(resolve(out,'report.json'),JSON.stringify({cases,errors},null,2));await browser.close();app.server.closeAllConnections();await new Promise(done=>app.server.close(done));}
