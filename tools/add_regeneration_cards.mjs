import fs from 'node:fs';
import assert from 'node:assert/strict';
const rows = [
  ['regen_patch','Nano Regeneration','ナノ再生','common',2,2.4,18,[2,2,3,3,4,4],[12,15,12,15,12,15],0,0],
  ['regen_salve','First Aid Gel','応急ジェル','common',2,2.4,18,[1,1,2,2,3,3],[9,12,9,12,9,12],4,1],
  ['regen_barrier','Regenerative Barrier','再生バリア','rare',3,4.8,24,[2,2,3,3,4,4],[15,18,15,18,15,18],6,1],
  ['regen_emergency','Emergency Nanites','緊急ナノ修復','rare',3,2.4,22,[2,2,3,3,4,4],[12,15,12,15,12,15],0,0],
  ['regen_bloodwrap','Blood Wrap','吸血包帯','rare',3,4.2,22,[1,1,2,2,3,3],[12,15,12,15,12,15],6,2],
  ['regen_burst','Focused Renewal','集中再生','epic',3,3,22,[5,6,7,8,9,10],[6,6,6,6,6,6],0,0],
  ['regen_spring','Cleansing Spring','浄化の泉','rare',3,3.6,24,[2,2,3,3,4,4],[12,15,12,15,12,15],0,0],
  ['regen_tank','Regeneration Tank','再生タンク','epic',4,6,32,[1,1,1,2,2,2],[24,27,30,24,27,30],0,0],
];
const cards=JSON.parse(fs.readFileSync('data/cards.json','utf8'));
const ja=JSON.parse(fs.readFileSync('data/localization/ja.json','utf8'));
let progression=fs.readFileSync('data/content_progression.json','utf8').replaceAll('\r\n','\n');
const p=JSON.parse(progression);
for(const [id,name,jp,rarity,cost,cast,recast,power,duration,extra,step] of rows){
  assert(!cards.some(c=>c.id===id),`Already authored ${id}`);
  const effects=[];
  if(id==='regen_salve')effects.push({type:'heal',amount:extra,target:'self'});
  if(id==='regen_barrier')effects.push({type:'gain_shield',amount:extra,target:'self'});
  if(id==='regen_bloodwrap')effects.push({type:'deal_damage',amount:extra,target:'enemy'});
  if(id==='regen_spring')effects.push({type:'remove_status',status:'bleed',target:'self'});
  const ri=effects.length;
  const regen={type:'apply_status',status:'regen',duration:duration[0],regen_power:power[0],target:'self'};
  if(id==='regen_emergency')Object.assign(regen,{bonus_if_hp_below_ratio:.4,bonus_power:2});
  if(id==='regen_tank')regen.regen_max_hp_ratio=.01;
  effects.push(regen);
  const grades={};
  for(let g=1;g<=5;g++){
    const eff={ [ri]:{duration:duration[g],regen_power:power[g]} };
    if(extra)eff[0]={amount:extra+step*g};
    if(id==='regen_emergency')eff[ri].bonus_power=[2,2,3,3,4,4][g];
    if(id==='regen_tank')eff[ri].regen_max_hp_ratio=Number((.01+.001*g).toFixed(3));
    grades[g]={effects:eff};
  }
  cards.push({id,name,description:'Apply independently timed healing regeneration; up to three layers.',rarity,tags:[...(id==='regen_bloodwrap'?['attack']:['support']),'heal','regen',...(id==='regen_barrier'?['shield']:[])],loadout_cost:cost,cast_time:cast,recast_time:recast,active_slot_cost:id==='regen_barrier'||id==='regen_bloodwrap'?2:1,priority_modifier:0,interruptible:true,target_type:id==='regen_bloodwrap'?'enemy':'self',effects,upgrade_profile:{cast_time:[0,-.06,-.12,-.18,-.24,-.3],recast_time:[0,-1,-2,-3,-4,-5]},grade_overrides:grades});
  ja[`card.${id}.name`]=jp;ja[`card.${id}.description`]='HPリジェネを付与する。各層の回復量と残り時間は個別に管理する。';
  if(rarity!=='common')p.stages[id==='regen_burst'||id==='regen_tank'?3:id==='regen_bloodwrap'||id==='regen_spring'?2:1].cards.push(id);
}
let index=0;progression=progression.replace(/("cards": )\[[^\]]*\]/g,(_,prefix)=>prefix+'['+p.stages[index++].cards.map(x=>JSON.stringify(x)).join(', ')+']');
Object.assign(ja,{
  'tag.regen':'リジェネ','status.regen':'HPリジェネ',
  'effect.apply_regen':'{target}にHPリジェネを{duration}秒付与。3秒ごとにHPを{power}回復（最大3層）',
  'effect.regen.low':'HPが{percent}%以下なら回復量＋{bonus}（付与時に確定）',
  'effect.regen.applied':'低HP補正を適用済み',
  'effect.regen.included':'（表示値に含む）',
  'effect.regen.max_hp':'回復量に対象の最大HPの{percent}%を加算（切り捨て・付与時に確定）',
  'status.regen.total':'3秒ごとにHPを合計{power}回復。{stacks}/3層。満HPでは回復せず、戦闘不能から復活しない。',
  'status.regen.next':'次の回復まで{seconds}秒',
  'status.regen.layer':'層{index}: 回復{power} / 残り{seconds}秒',
  'regen.dev.apply':'自分にリジェネ3層を追加','regen.dev.clear':'両者のリジェネを解除',
});
fs.writeFileSync('data/cards.json',JSON.stringify(cards,null,2)+'\n');
fs.writeFileSync('data/localization/ja.json',JSON.stringify(ja,null,2)+'\n');
fs.writeFileSync('data/content_progression.json',progression);
console.log('REGEN_CONTENT_OK',rows.length);
