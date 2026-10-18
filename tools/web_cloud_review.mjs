import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {mkdir,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
const require=createRequire(import.meta.url);
const {chromium}=process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES,'../package.json'))('playwright') : require('playwright');
const {createQqServer}=require('../server/server');
const app=createQqServer({env:{},publicDir:resolve('build/web-layout-review')});
await new Promise(done=>app.server.listen(0,'127.0.0.1',done));
const origin=`http://127.0.0.1:${app.server.address().port}`;
const browser=await chromium.launch({channel:'chrome',headless:true});
const out=resolve('tools/.local/cloud-review'); await mkdir(out,{recursive:true});
const saves=new Map(),errors=[],checks=[],devices=[];
const transfers=new Map();
const ownerA='11111111-1111-4111-8111-111111111111',ownerB='22222222-2222-4222-8222-222222222222';
let serial=0;
async function device(owner='') {
 const context=await browser.newContext({viewport:{width:1440,height:900}});
 const state={context,owner,offline:false};
 devices.push(state);
 await context.route('**/api/account',route=>route.fulfill({json:{available:true,authenticated:!!state.owner,needsUsername:false,user:state.owner?{id:state.owner,username:state.owner===ownerA?'CloudA':'CloudB'}:null,csrfToken:'test-only',providers:[{id:'google',enabled:true},{id:'github',enabled:true}]}}));
 await context.route('**/api/account/logout',route=>{state.owner='';return route.fulfill({json:{authenticated:false,available:true}});});
 await context.route('**/api/cloud/**',route=>{
  const request=route.request(),path=new URL(request.url()).pathname.split('/').at(-1),writer=request.headers()['x-qq-writer'];
  const send=(json,status=200)=>route.fulfill({json,status});
  if(state.offline) return send({error:'network_error'},503);
  if(request.headers()['x-qq-account']!==state.owner||!state.owner) return send({error:'account_changed'},409);
  if(!saves.has(state.owner)) saves.set(state.owner,{revision:0,payload:null,writer:'',history:[]});
  const row=saves.get(state.owner),body=JSON.parse(request.postData()||'{}');
  const snapshot=()=>({...row,writer_active:!!row.writer,owns_lease:row.writer===writer,updated_at:new Date().toISOString()});
  const credential=body.guest_identity||body.guest_ticket;
  const guest=credential?transfers.get(credential.origin_id):null;
  if(path==='guest-status')return send(guest&&guest.ticket.secret===credential.secret?{status:guest.receipt?(guest.receipt.owner_id===state.owner?'claimed_here':'claimed_elsewhere'):'available',guest_receipt:guest.receipt}:{status:'unregistered',guest_receipt:null});
  if(path==='guest-ticket') {
   if(guest&&guest.ticket.secret!==credential.secret)return send({error:'guest_ticket_not_found'},404);
   const entry=guest||{ticket:{...credential,id:randomUUID()},receipt:null,imports:0};transfers.set(credential.origin_id,entry);return send({guest_ticket:entry.ticket,guest_receipt:entry.receipt});
  }
  if(path==='import-guest') {
   if(!guest||guest.ticket.id!==credential.id||guest.ticket.secret!==credential.secret)return send({error:'guest_ticket_not_found'},404);
   if(guest.receipt)return guest.receipt.owner_id===state.owner?send({...snapshot(),already_imported:true,guest_receipt:guest.receipt}):send({error:'guest_already_claimed',guest_receipt:guest.receipt},409);
   if(row.writer!==body.writer_id)return send({error:'lease_lost'},409);
   if(row.revision!==body.base_revision)return send({error:'revision_conflict'},409);
   row.payload=body.payload;row.revision++;row.request_id=body.request_id;guest.imports++;guest.receipt={id:guest.ticket.id,origin_id:credential.origin_id,owner_id:state.owner,revision:row.revision};
   if(state.dropImportReceipt){state.dropImportReceipt=false;return send({error:'network_error'},503);}
   return send({...snapshot(),already_imported:false,guest_receipt:guest.receipt});
  }
  if(path==='save'&&request.method()==='GET') return send(snapshot());
  if(path==='claim') {if(row.writer&&row.writer!==body.writer_id&&!body.takeover)return send({error:'device_busy'},409);row.writer=body.writer_id;return send(snapshot());}
  if(path==='lease'||path==='release') {if(row.writer!==body.writer_id)return send({error:'lease_lost'},409);if(path==='release')row.writer='';return send(snapshot());}
  if(path==='save'&&request.method()==='PUT') {
   if(row.writer!==body.writer_id)return send({error:'lease_lost'},409);
   if(row.revision!==body.base_revision)return send({error:'revision_conflict'},409);
   row.payload=body.payload;row.revision++;row.request_id=body.request_id;
   return send({revision:row.revision,request_id:row.request_id,updated_at:new Date().toISOString()});
  }
  if(path==='history')return send({history:[]});
  return send({error:'not_found'},404);
 });
 async function page() {
  const p=await context.newPage();state.page=p;
  p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(m.type()==='error'&&/SCRIPT ERROR|Parse Error|ERROR:/.test(m.text()))errors.push(m.text());});
  await p.goto(origin+'/?pack=local&cloud_review=1');
  await p.waitForFunction(()=>window.qqLayoutCommand&&window.qqLoadMetrics?.some(x=>x.event==='scene_transition'&&x.details.screen==='Hub'),undefined,{timeout:180000});
  await p.waitForSelector('#status',{state:'detached'});return p;
 }
 state.open=page;await page();return state;
}
async function wait(d,value) {await d.page.waitForFunction(v=>{const s=window.qqCloud.stateSnapshot();return s.state===v&&!s.busy;},value,{timeout:30000});}
async function inspect(d) {const sequence=++serial;await d.page.evaluate(sequence=>window.qqLayoutCommand(JSON.stringify({action:'inspect',sequence})),sequence);await d.page.waitForFunction(sequence=>JSON.parse(window.qqLayoutState||'{}').sequence===sequence,sequence);return d.page.evaluate(()=>JSON.parse(window.qqLayoutState));}
async function fixture(d,points,sync=false,run=false) {await d.page.evaluate(data=>window.qqLayoutCommand(JSON.stringify(data)),{action:'cloud_fixture',points,sync,run,sequence:++serial});}
async function action(d,id) {await d.page.evaluate(id=>window.qqCloud.action({id}),id);}
async function synced(d) {await d.page.waitForFunction(()=>{const s=window.qqCloud.stateSnapshot();return s.state==='ready'&&!s.busy&&!s.dirty&&s.revision>0;},undefined,{timeout:30000});}
async function guestSnapshot(d) {await d.page.evaluate(()=>window.qqLayoutCommand(JSON.stringify({action:'guest_snapshot'})));return d.page.evaluate(()=>JSON.parse(window.qqGuestSnapshot));}
try {
 const a=await device();await wait(a,'guest');await fixture(a,123,false,true);assert.equal((await inspect(a)).cloud_points,123,'guest fixture');const originalGuest=await guestSnapshot(a);
 a.owner=ownerA;await a.page.evaluate(()=>window.qqAccount.refresh());await wait(a,'import_choice');
 let frame=a.page.frameLocator('#qq-service-panel iframe[src^="/account"]');await frame.locator('[data-cloud-action=import]').click();await synced(a);
 assert.equal(saves.get(ownerA).payload.meta_progress.points,123);
 await a.page.screenshot({path:resolve(out,'import-complete.png')});
 await frame.locator('#logout').click();await wait(a,'guest');await frame.locator('#signed-in').waitFor({state:'hidden'});assert.equal((await inspect(a)).cloud_points,0);checks.push('guest_move_then_logout_starts_new_guest');
 a.owner=ownerB;await a.page.evaluate(()=>window.qqAccount.refresh());await wait(a,'import_choice');await frame.locator('[data-cloud-action=new]').click();await synced(a);assert.equal((await inspect(a)).cloud_points,0);
 await frame.locator('#logout').click();await wait(a,'guest');a.owner=ownerA;await a.page.evaluate(()=>window.qqAccount.refresh());await synced(a);assert.equal((await inspect(a)).cloud_points,123);checks.push('account_switch_and_return_preserves_separate_progress');
 const b=await device(ownerA);await wait(b,'device_busy');await action(b,'takeover');await synced(b);assert.equal((await inspect(b)).cloud_points,123);checks.push('second_device_loads_cloud_and_explicitly_takes_over');
 await fixture(a,222,true);await wait(a,'device_busy');assert.equal(saves.get(ownerA).payload.meta_progress.points,123);
 await action(a,'takeover');await a.page.waitForFunction(()=>['ready','conflict'].includes(window.qqCloud.stateSnapshot().state));if((await a.page.evaluate(()=>window.qqCloud.stateSnapshot().state))==='conflict')await action(a,'local');await synced(a);assert.equal(saves.get(ownerA).payload.meta_progress.points,222);checks.push('old_writer_rejected_and_unsent_progress_preserved');
 a.offline=true;await fixture(a,333,true);await wait(a,'offline');assert.equal((await inspect(a)).cloud_dirty,true);
 await action(b,'takeover');await synced(b);await fixture(b,444,true);await synced(b);assert.equal(saves.get(ownerA).payload.meta_progress.points,444);
 await a.page.waitForTimeout(1500);await a.page.close();a.offline=false;await a.open();frame=a.page.frameLocator('#qq-service-panel iframe[src^="/account"]');await wait(a,'conflict');assert.equal((await inspect(a)).cloud_points,333);
 await a.page.screenshot({path:resolve(out,'conflict.png')});await action(a,'cloud');await synced(a);assert.equal((await inspect(a)).cloud_points,444);checks.push('offline_restart_preserves_local_conflict_and_explicit_resolution');
 const backup=await a.page.evaluate(()=>window.qqCloud.stateSnapshot().local_backups[0]);assert(backup);await a.page.evaluate(filename=>window.qqCloud.action({id:'restore_local',filename}),backup);await synced(a);assert.equal((await inspect(a)).cloud_points,333);checks.push('discarded_local_conflict_can_be_restored');
 await a.page.setViewportSize({width:390,height:844});assert(await frame.locator('body').evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await a.page.screenshot({path:resolve(out,'account-mobile.png')});await a.page.setViewportSize({width:1440,height:900});checks.push('embedded_account_fits_mobile_viewport');
 await a.page.locator('#qq-service-close').click();await a.page.evaluate(()=>window.qqRanked.open('ja'));assert.equal(a.context.pages().length,1);await a.page.waitForSelector('#qq-service-panel iframe:not([hidden])');checks.push('account_and_rankings_embedded_without_new_windows');
 await a.page.locator('#qq-service-close').click();await a.page.evaluate(()=>window.qqAccount.open('ja'));await frame.locator('#logout').click();await wait(a,'guest');await frame.locator('#refresh').click();await frame.locator('#google[aria-disabled=false]').waitFor();
 await a.context.route('**/auth/google/start**',route=>{a.owner=ownerB;return route.fulfill({status:302,headers:{location:'/account?result=authenticated&lang=ja'}});});
 const authPromise=a.page.waitForEvent('popup');await frame.locator('#google').click();const auth=await authPromise;if(!auth.isClosed())await auth.waitForEvent('close');await synced(a);assert.equal(a.context.pages().length,1);assert.equal((await inspect(a)).cloud_profile,ownerB);checks.push('only_provider_auth_opens_a_window_and_returns_to_game');
 await frame.locator('#logout').click();await wait(a,'guest');const emptyOwner='33333333-3333-4333-8333-333333333333';saves.set(emptyOwner,{revision:0,payload:null,writer:'other-unfinished-device',history:[]});a.owner=emptyOwner;await a.page.evaluate(()=>window.qqAccount.refresh());await wait(a,'import_choice');await action(a,'new');await wait(a,'device_busy');await action(a,'takeover');await wait(a,'import_choice');await action(a,'new');await synced(a);checks.push('takeover_of_unfinished_first_save_returns_to_import_choice');
 await b.context.close();await a.context.close();
 const c=await device();await wait(c,'guest');await c.page.evaluate(snapshot=>window.qqLayoutCommand(JSON.stringify({action:'guest_restore_fixture',snapshot})),originalGuest);
 c.owner=ownerB;await c.page.evaluate(()=>window.qqAccount.refresh());await wait(c,'guest_claimed');assert.equal((await inspect(c)).cloud_points,0);assert.equal(transfers.get(originalGuest.settings._cloud_meta.guest_identity.origin_id).imports,1);await c.page.screenshot({path:resolve(out,'guest-already-claimed.png')});await action(c,'cloud');await synced(c);assert.equal((await inspect(c)).cloud_points,0);checks.push('copied_pre_issuance_guest_is_rejected_for_another_account');
 await action(c,'logout');await wait(c,'guest');await fixture(c,777);const pendingSource=await guestSnapshot(c);const receiptOwner='44444444-4444-4444-8444-444444444444';c.owner=receiptOwner;await c.page.evaluate(()=>window.qqAccount.refresh());await wait(c,'import_choice');c.dropImportReceipt=true;await action(c,'import');await wait(c,'guest_transfer_pending');assert.equal(saves.get(receiptOwner).payload.meta_progress.points,777);assert.equal((await inspect(c)).cloud_points,777);await c.page.waitForTimeout(1500);await c.page.close();await c.open();await c.page.waitForFunction(()=>{const s=window.qqCloud.stateSnapshot();return ['ready','device_busy'].includes(s.state)&&!s.busy;});if((await c.page.evaluate(()=>window.qqCloud.stateSnapshot().state))==='device_busy')await action(c,'takeover');await synced(c);assert.equal((await inspect(c)).cloud_points,777);assert.equal(transfers.get(pendingSource.settings._cloud_meta.guest_identity.origin_id).imports,1);checks.push('lost_transfer_receipt_recovers_after_restart_without_reimport');
 await c.page.evaluate(()=>window.qqLayoutCommand(JSON.stringify({action:'legacy_guest_pending_fixture'})));await synced(c);const legacyIdentity=await c.page.evaluate(()=>JSON.parse(window.qqLegacyGuest));assert.equal(transfers.get(legacyIdentity.origin_id).receipt.owner_id,receiptOwner);assert.equal(saves.get(receiptOwner).payload.meta_progress.points,777);assert.equal((await inspect(c)).cloud_points,777);checks.push('legacy_pending_transfer_binds_source_without_rolling_account_progress_back');
 assert.deepEqual(errors,[]);await writeFile(resolve(out,'report.json'),JSON.stringify({checks,errors},null,2));console.log('WEB_CLOUD_REVIEW_OK',JSON.stringify({checks,errors}));
} catch(error) {console.error('CLOUD_REVIEW_DIAGNOSTIC',JSON.stringify({checks,errors,devices:await Promise.all(devices.map(async d=>({owner:d.owner,state:await d.page.evaluate(()=>window.qqCloud.stateSnapshot()).catch(()=>null)}))),saves:[...saves].map(([owner,row])=>({owner,revision:row.revision,points:row.payload?.meta_progress?.points,writer:row.writer}))}));throw error;}
finally {await browser.close();app.server.closeAllConnections();await new Promise(done=>app.server.close(done));}
