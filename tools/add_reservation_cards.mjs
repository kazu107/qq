import fs from 'node:fs';
import assert from 'node:assert/strict';

const specs = [
  ['focus', 'Focused Command', '集中指令', 'common', 2, 1.8, 16, [8,10,12,14,16,18], '次の攻撃：ダメージ＋{amount}。'],
  ['shield', 'Barrier Booster', '防壁ブースター', 'rare', 2, 2.4, 20, [1.5,1.6,1.7,1.8,1.9,2], '次のシールドカード：付与量を{amount}倍にする。'],
  ['siphon', 'Siphon Load', '吸収弾の装填', 'epic', 3, 3, 24, [.5,.55,.6,.65,.7,.75], '次の攻撃：実際に与えたHPダメージの{percent}%を回復する。'],
  ['reload', 'Reload Reservation', '再装填予約', 'rare', 3, 2.4, 24, [.5,.47,.44,.41,.38,.35], '次のカード：再使用時間を{amount}倍にする。'],
  ['status', 'Status Booster', '状態ブースター', 'rare', 2, 2.4, 20, [6,7,8,9,10,11], '次の状態付与カード：持続時間＋{amount}秒、出血威力＋{secondary}。', [2,2,3,3,4,5]],
  ['chain', 'Chain Command', '連鎖指令', 'epic', 3, 3.6, 26, [1,1,1,1,1,1], '次のカード発動後：ガードを1枚自動投入する。'],
  ['growth', 'Growth Mark', '成長の刻印', 'epic', 3, 3, 26, [2,2,3,3,4,4], '次の攻撃・シールドカード発動後：そのカードのダメージ・シールド量を戦闘中＋{amount}。'],
  ['tempo', 'Tempo Theft', 'テンポ奪取', 'rare', 3, 2.4, 22, [1.5,1.7,1.9,2.1,2.3,2.5], '次のカード発動後：敵の全タイムラインカードを{amount}秒遅らせる。'],
  ['weaken', 'Weakening Tag', '脱力タグ', 'common', 2, 1.8, 18, [.6,.55,.5,.45,.4,.35], '敵の次の攻撃：ダメージを{amount}倍にする。'],
  ['shield_jam', 'Shield Interference', 'シールド妨害', 'common', 2, 1.8, 18, [.5,.45,.4,.35,.3,.25], '敵の次のシールドカード：付与量を{amount}倍にする。'],
  ['heal_jam', 'Healing Corruption', '回復汚染', 'rare', 2, 2.4, 22, [.5,.45,.4,.35,.3,.25], '敵の次の回復カード：回復量を{amount}倍にし、自分はHPを{secondary}回復する。', [4,5,6,7,8,9]],
  ['recast_jam', 'Recast Jammer', '再使用ジャマー', 'rare', 3, 2.4, 22, [6,7,8,9,10,11], '敵の次のカード：再使用時間＋{amount}秒。'],
  ['recoil', 'Recoil Tag', '反動タグ', 'common', 2, 2.4, 18, [6,8,10,12,14,16], '敵の次のカード発動後：敵に固定{amount}ダメージ（シールドで防げる）。'],
  ['time_mine', 'Time Mine', '時間地雷', 'rare', 3, 3, 24, [2,2.2,2.4,2.6,2.8,3], '敵の次のカード発動後：敵の残りのタイムラインカードを{amount}秒遅らせる。'],
  ['wear', 'Card Wear', 'カード摩耗', 'epic', 3, 3.6, 26, [1,1.2,1.4,1.6,1.8,2], '敵の次のカード発動後：そのカードの再使用時間を戦闘中＋{amount}秒。'],
  ['mirror', 'Mirror Intercept', 'ミラー傍受', 'epic', 3, 3, 24, [.5,.55,.6,.65,.7,.75], '敵の次のカードで実際に得たシールド・回復量の{percent}%を自分も得る。'],
  ['swift_commit', 'Express Cast', '速達詠唱', 'rare', 3, 2.4, 24, [.5,.47,.44,.41,.38,.35], '次に手動登録するカード：詠唱時間を{amount}倍にする。'],
  ['heavy_commit', 'Slot Jammer', 'スロット妨害', 'rare', 3, 2.4, 22, [1,1,1,1,1,1], '敵が次に手動登録するカード：使用スロット＋{amount}（スロット上限まで）。'],
];
const hostile = new Set(['weaken','shield_jam','heal_jam','recast_jam','recoil','time_mine','wear','mirror','heavy_commit']);
const cards = JSON.parse(fs.readFileSync('data/cards.json', 'utf8'));
const jaPath = 'data/localization/ja.json';
const ja = JSON.parse(fs.readFileSync(jaPath, 'utf8'));
const progression = JSON.parse(fs.readFileSync('data/content_progression.json', 'utf8'));
const manifest = [];
for (let index = 0; index < specs.length; index++) {
  const [kind, name, jp, rarity, cost, cast, recast, amounts, description, secondary] = specs[index];
  const id = `reserve_${kind}`;
  assert(!cards.some(card => card.id === id), `Already authored: ${id}`);
  const effect = { type: 'reserve_next_card', reservation: kind, amount: amounts[0], target: hostile.has(kind) ? 'enemy' : 'self' };
  if (secondary) effect.secondary = secondary[0];
  const overrides = {};
  for (let grade = 1; grade <= 5; grade++) {
    overrides[grade] = { effects: { 0: { amount: amounts[grade], ...(secondary ? { secondary: secondary[grade] } : {}) } } };
  }
  cards.push({ id, name, description: `Reserve ${name} for one eligible manual card.`, rarity, tags: ['support', 'reservation', ...(hostile.has(kind) ? ['control'] : ['combo'])], loadout_cost: cost, cast_time: cast, recast_time: recast, active_slot_cost: 1, priority_modifier: 0.1, interruptible: true, target_type: effect.target, effects: [effect], upgrade_profile: { cast_time: [0,-.06,-.12,-.18,-.24,-.3], recast_time: [0,-1,-2,-3,-4,-5] }, grade_overrides: overrides });
  ja[`card.${id}.name`] = jp;
  ja[`card.${id}.description`] = '条件に合う次の手動カード1枚に予約効果を付与する。既に詠唱中も対象。登録時の効果は次の登録から適用。';
  ja[`reservation.name.${kind}`] = jp;
  ja[`reservation.effect.${kind}`] = description;
  const groups = [[], ['shield','reload','status','swift_commit'], ['recast_jam','tempo','heavy_commit'], ['siphon','chain','heal_jam','time_mine'], ['growth','wear','mirror']];
  if (rarity !== 'common') progression.stages[groups.findIndex(group => group.includes(kind))].cards.push(id);
  manifest.push({ id, kind, name, jp, hostile: hostile.has(kind), rarity, amounts, secondary: secondary || [], cast, recast });
}
Object.assign(ja, {
  'tag.reservation': '予約', 'status.reservation_boost': '強化予約', 'status.reservation_hex': '妨害予約',
  'reservation.rules': '同種は最大3枚分・合計8件。1枚につき同種を1件ずつ消費。自動投入・疲労・予約付与カードは対象外。中断では発動予約を消費しない。',
  'reservation.dev.self': '自分に予約を追加', 'reservation.dev.enemy': '敵に予約を追加', 'reservation.dev.clear': '両者の予約を解除',
});
fs.writeFileSync('data/cards.json', JSON.stringify(cards, null, 2) + '\n');
fs.writeFileSync(jaPath, JSON.stringify(ja, null, 2) + '\n');
fs.writeFileSync('data/content_progression.json', JSON.stringify(progression, null, 2) + '\n');
fs.mkdirSync('tools/.local/reservations', { recursive: true });
fs.writeFileSync('tools/.local/reservations/catalog.json', JSON.stringify(manifest, null, 2) + '\n');
console.log('RESERVATION_CONTENT_OK', manifest.length);
