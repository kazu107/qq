import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/achievement-notification/browser');
await mkdir(output, { recursive:true });
const app = createQqServer({env:{},publicDir:resolve('build/web-layout-review')});
await new Promise(done => app.server.listen(0,'127.0.0.1',done));
const browser = await chromium.launch({channel:'chrome',headless:true});
const errors=[], cases=[];
try {
  const page=await browser.newPage({viewport:{width:1440,height:900}});
  page.on('pageerror',error=>errors.push(String(error)));
  page.on('console',message=>{if(/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text()))errors.push(message.text());});
  let sequence=0;
  async function command(action='inspect',extra={}) {
    const seq=++sequence;
    await page.evaluate(payload=>window.qqLayoutCommand(JSON.stringify(payload)),{action,...extra,sequence:seq});
    await page.waitForFunction(value=>JSON.parse(window.qqLayoutState||'{}').sequence===value,seq);
    return page.evaluate(()=>JSON.parse(window.qqLayoutState));
  }
  async function clickRect(state,rect) {
    const box=await page.locator('#canvas').boundingBox(), [x,y,w,h]=rect;
    await page.mouse.click(box.x+(x+w/2)*box.width/state.viewport[0],box.y+(y+h/2)*box.height/state.viewport[1]);
    return command();
  }
  async function click(state,name) {
    const control=state.controls.find(control=>control.name===name);assert(control,name);
    return clickRect(state,control.rect);
  }
  async function ready() {
    for(let index=0;index<80;index++) {const s=await command();if(s.meta_modal?.visible&&s.meta_modal.ready)return s;await page.waitForTimeout(50);}
    throw new Error('meta_not_ready');
  }
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`,{waitUntil:'commit'});
  await page.waitForFunction(()=>window.qqLayoutCommand&&window.qqLoadMetrics?.some(item=>item.event==='scene_transition'&&item.details.screen==='Hub'),undefined,{timeout:180000});
  await page.waitForSelector('#status',{state:'detached'});
  let state=await command('achievement_notice_fixture');
  assert.equal(state.achievement_notice.visible,false);
  const original=state.achievement_notice.button_rect;
  state=await command('achievement_notice_fixture',{stats:{gold_spent:25}});
  assert.equal(state.achievement_notice.visible,true);assert.equal(state.achievement_notice.count,1);
  assert.deepEqual(state.achievement_notice.button_rect,original);
  assert.equal(state.achievement_notice.input,2);
  for(const viewport of [{width:1440,height:900},{width:960,height:600},{width:900,height:1200}]) {
    await page.setViewportSize(viewport);state=await command();
    const n=state.achievement_notice,[x,y,w,h]=n.rect,[bx,by,bw]=n.button_rect;
    assert.equal(w,22);assert.equal(h,22);assert(x>bx+bw*.8&&x+w<=bx+bw&&y<by&&y+h>by);
    await page.screenshot({path:resolve(output,`badge-${viewport.width}x${viewport.height}.png`)});
    cases.push({viewport,...n});
  }
  // The badge itself must not steal clicks from the underlying button.
  state=await clickRect(state,state.achievement_notice.rect);state=await ready();
  assert(state.achievement_notice.visible);
  await page.keyboard.press('Escape');state=await command();assert(state.achievement_notice.visible);
  state=await click(state,'HubMetaProgressButton');await ready();
  state=await command('meta_modal_focus',{name:'ClaimAchievement_big_spender'});
  state=await click(state,'ClaimAchievement_big_spender');assert.equal(state.achievement_notice.visible,false);
  await page.keyboard.press('Escape');await command();
  state=await command('achievement_notice_fixture',{stats:{victories:3}});assert(state.achievement_notice.visible);
  state=await click(state,'HubMetaProgressButton');await ready();
  state=await command('meta_modal_focus',{name:'ClaimAchievement_victory_milestones'});
  state=await click(state,'ClaimAchievement_victory_milestones');assert(state.achievement_notice.visible,'Next earned tier should remain pending');
  state=await click(state,'ClaimAchievement_victory_milestones');assert(!state.achievement_notice.visible);
  await page.keyboard.press('Escape');await command();
  await command('screen',{screen:'library'});state=await command('screen',{screen:'hub'});assert(!state.achievement_notice.visible);
  state=await command('achievement_notice_fixture',{stats:{gold_spent:25,victories:1}});assert.equal(state.achievement_notice.count,2);
  state=await command('achievement_notice_fixture');assert(!state.achievement_notice.visible);
  assert.deepEqual(errors,[]);
  await writeFile(resolve(output,'report.json'),JSON.stringify({cases,errors},null,2));
  console.log('WEB_ACHIEVEMENT_NOTIFICATION_OK: three viewport sizes, badge click-through, real claims, pending tiers, reentry and reset');
} finally {await browser.close();await new Promise(done=>app.server.close(done));}
