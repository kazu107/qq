import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir,writeFile } from 'node:fs/promises';
const require=createRequire(import.meta.url);
const {createQqServer}=require('../server/server');
const {chromium}=process.env.QQ_NODE_MODULES?createRequire(resolve(process.env.QQ_NODE_MODULES,'../package.json'))('playwright'):require('playwright');
const out=resolve('tools/.local/language-flash/browser');await mkdir(out,{recursive:true});
const app=createQqServer({env:{},publicDir:resolve('build/web-layout-review')});await new Promise(done=>app.server.listen(0,'127.0.0.1',done));
const browser=await chromium.launch({channel:'chrome',headless:true});
const errors=[],checks=[];let frames=[];
try{
  const page=await browser.newPage({viewport:{width:1440,height:900}});
  page.on('pageerror',error=>errors.push(String(error)));
  page.on('console',message=>{if(/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text()))errors.push(message.text());});
  let seq=0;
  async function command(action='inspect',extra={}){const n=++seq;await page.evaluate(payload=>window.qqLayoutCommand(JSON.stringify(payload)),{action,...extra,sequence:n});await page.waitForFunction(n=>JSON.parse(window.qqLayoutState||'{}').sequence===n,n);return page.evaluate(()=>JSON.parse(window.qqLayoutState));}
  async function click(state,name){const item=state.controls.find(c=>c.name===name);assert(item,name);const box=await page.locator('#canvas').boundingBox(),[x,y,w,h]=item.rect;await page.mouse.click(box.x+(x+w/2)*box.width/state.viewport[0],box.y+(y+h/2)*box.height/state.viewport[1]);await page.waitForTimeout(160);return command();}
  async function service(kind,language){await page.evaluate(({kind,language})=>window.qqServices.open(kind,language),{kind,language});const selector=`iframe[src^="/${kind}?"]`;await page.waitForFunction(selector=>{const frame=document.querySelector(selector);return frame&&!frame.hidden&&frame.dataset.ready==='1';},selector);const lang=await page.locator(selector).evaluate(f=>f.contentDocument.documentElement.lang);assert.equal(lang,language);await page.locator('#qq-service-close').click();}
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`,{waitUntil:'commit'});
  await page.waitForFunction(()=>window.qqLayoutCommand&&window.qqLoadMetrics?.some(x=>x.event==='scene_transition'&&x.details.screen==='Hub'),undefined,{timeout:180000});await page.waitForSelector('#status',{state:'detached'});
  await command('locale_watch');
  let state=await command();state=await click(state,'HubCardLibraryButton');await page.waitForTimeout(250);state=await click(await command(),'LibraryReturnHubButton');
  state=await click(state,'HubMetaProgressButton');await page.waitForTimeout(200);state=await click(await command(),'MetaCloseButton');
  await service('account','ja');await service('rankings','ja');
  for(const language of ['en','ja']){
    state=await click(await command(),'OpenSettingsButton');state=await click(state,'LanguageOptionButton');
    const option=state.controls.find(c=>c.name==='LanguageOptionButton'),box=await page.locator('#canvas').boundingBox(),[x,y,w,h]=option.rect;
    await page.mouse.click(box.x+(x+w/2)*box.width/state.viewport[0],box.y+(y+h+(language==='en'?26:64))*box.height/state.viewport[1]);await page.waitForTimeout(250);
    state=await command();assert.equal(state.settings_modal.language,language);assert.equal(await page.locator('html').getAttribute('lang'),language);
    state=await click(state,'SettingsCloseButton');
    for(const [open,back,screen] of [['HubCardLibraryButton','LibraryReturnHubButton','CardLibrary'],['RunStartButton','RunSetupBackButton','RunSetup']]){
      state=await click(state,open);assert.equal(state.screen,screen);await page.waitForTimeout(180);state=await click(await command(),back);
    }
    state=await click(state,'HubMetaProgressButton');await page.waitForTimeout(180);state=await click(await command(),'MetaCloseButton');
    for(const kind of ['account','rankings']){
      let release,arrived;const gate=new Promise(resolve=>release=resolve),incoming=new Promise(resolve=>arrived=resolve);
      const pattern=`**/${kind}?lang=${language}&embedded=1`;
      await page.route(pattern,async route=>{const response=await route.fetch();arrived();await gate;await route.fulfill({response});});
      await page.evaluate(({kind,language})=>window.qqServices.open(kind,language),{kind,language});await incoming;
      const selector=`iframe[src^="/${kind}?"]`;
      assert.equal(await page.locator(selector).isVisible(),false,'Old document visible while replacement is pending');
      assert.equal(await page.locator('#qq-service-loading').innerText(),language==='en'?'Loading...':'読み込み中...');
      await page.waitForTimeout(120);assert.equal(await page.locator(selector).isVisible(),false);
      await page.screenshot({path:resolve(out,`${kind}-${language}-waiting.png`)});release();
      await page.waitForFunction(selector=>{const f=document.querySelector(selector);return f&&!f.hidden&&f.dataset.ready==='1';},selector);
      assert.equal(await page.locator(selector).evaluate(f=>f.contentDocument.documentElement.lang),language);
      await page.screenshot({path:resolve(out,`${kind}-${language}-loaded.png`)});
      await page.locator('#qq-service-close').click();await page.unroute(pattern);await service(kind,language);
      checks.push(`${kind} ${language}: slow load hides old language, same-language cache reopens`);
    }
    checks.push(`${language}: settings/library/setup/meta first-painted headings`);
  }
  await command('locale_watch',{enabled:false});frames=await page.evaluate(()=>JSON.parse(window.qqLocaleFrames||'[]'));
  const ja=new Set(['設定','メタ進行','カード・遺物図鑑','開始ロードアウトを選択']);
  const en=new Set(['Settings','Meta Progress','Card & Relic Library','Select Starter Loadout']);
  const painted=frames.filter(f=>!f.covered);
  assert(painted.length>12,'Not enough first-painted states sampled');
  for(const language of ['en','ja'])for(const scene of ['CardLibrary.tscn','RunSetup.tscn'])assert(painted.some(f=>f.language===language&&f.scene===scene),`Missing ${language} ${scene} first paint`);
  for(const frame of painted){assert(frame.valid,`Stale language/generation: ${JSON.stringify(frame)}`);for(const title of frame.titles)assert(!(frame.language==='en'?ja:en).has(title),`Old heading painted: ${JSON.stringify(frame)}`);}
  assert.deepEqual(errors,[]);console.log('WEB_LANGUAGE_TRANSITION_OK',JSON.stringify({checks,paintedFrames:painted.length,errors}));
}finally{await writeFile(resolve(out,'report.json'),JSON.stringify({checks,frames,errors},null,2));await browser.close();app.server.closeAllConnections();await new Promise(done=>app.server.close(done));}
