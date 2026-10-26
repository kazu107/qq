import fs from 'node:fs';
import assert from 'node:assert/strict';
const specs=[['life_conversion','Life Conversion','生命転換','heal'],['barrier_conversion','Barrier Conversion','防壁転換','shield']];
const cards=JSON.parse(fs.readFileSync('data/cards.json','utf8'));
const ja=JSON.parse(fs.readFileSync('data/localization/ja.json','utf8'));
let progression=fs.readFileSync('data/content_progression.json','utf8').replaceAll('\r\n','\n');const stages=JSON.parse(progression).stages;
for(const[id,name,jp,mode]of specs){
  assert(!cards.some(c=>c.id===id),'Already authored '+id);
  const grades={};for(let g=1;g<=5;g++)grades[g]={effects:{0:{ratio:Number((.25+.1*g).toFixed(2))}}};
  cards.push({id,name,description:'Temporarily prevent combat damage and convert a portion. Fatigue and HP costs are excluded.',rarity:'epic',tags:['support','conversion',mode==='heal'?'heal':'shield'],loadout_cost:4,cast_time:1.2,recast_time:30,active_slot_cost:1,priority_modifier:.2,interruptible:true,target_type:'self',effects:[{type:'damage_conversion',mode,duration:4,ratio:.25,lockout_duration:4}],upgrade_profile:{cast_time:[0,0,0,0,0,0],recast_time:[0,0,0,0,0,0]},grade_overrides:grades});
  stages[3].cards.push(id);ja[`card.${id}.name`]=jp;ja[`card.${id}.description`]='一定時間、戦闘ダメージを無効化して変換する。疲労とHPの支払いは対象外。';
}
let index=0;progression=progression.replace(/("cards": )\[[^\]]*\]/g,(_,p)=>p+'['+stages[index++].cards.map(x=>JSON.stringify(x)).join(', ')+']');
Object.assign(ja,{
 'tag.conversion':'転換','status.damage_conversion':'ダメージ転換','status.conversion_lockout':'再展開待ち',
 'conversion.mode.heal':'HP','conversion.mode.shield':'シールド',
 'conversion.effect':'{duration}秒間、疲労以外の戦闘ダメージをシールド消費前に無効化し、防いだ量の{percent}%を{mode}に変換する。途中の再付与では延長せず、終了後{lockout}秒は再展開できない。HPの支払いは対象外。',
 'conversion.detail':'疲労以外の戦闘ダメージを無効化し、{percent}%を{mode}へ変換する。シールドを消費せず、端数は効果中に蓄積する。重ね掛けで延長せず、終了後は再展開待ちとなる。HPの支払いは対象外。',
 'conversion.lockout':'ダメージ転換の再展開を待っている。この間はダメージを通常通り受ける。',
 'conversion.generic':'疲労以外の戦闘ダメージをシールド消費前に無効化し、一部を変換する。端数は効果中に蓄積する。再付与で延長せず、終了後は再展開待ちとなる。HPの支払いは対象外。',
 'conversion.applied':'ダメージ転換を展開','conversion.wait':'ダメージ転換は再展開待ち',
 'conversion.dev.life':'生命転換を展開（50%）','conversion.dev.shield':'防壁転換を展開（50%）','conversion.dev.clear':'両者の転換と再展開待ちを解除',
 'battle.analysis.metric.prevented':'無効化ダメージ',
});
fs.writeFileSync('data/cards.json',JSON.stringify(cards,null,2)+'\n');fs.writeFileSync('data/localization/ja.json',JSON.stringify(ja,null,2)+'\n');fs.writeFileSync('data/content_progression.json',progression);
console.log('CONVERSION_CONTENT_OK',specs.length);
