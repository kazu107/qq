import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = path => JSON.parse(fs.readFileSync(root + path, 'utf8'));
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const referenceFixtures = ['published_balance.json', 'grade_balance_0_52_2.json', 'balance_0_55_1.json'];
const tuned = new Set(referenceFixtures.flatMap(name => read('tests/fixtures/' + name).changes.map(item => item.id)));
const recent = id => /^(reserve_|regen_)/.test(id) || ['echo_cast','life_conversion','barrier_conversion'].includes(id);
const cards = read('data/cards.json');
const round = value => Math.round(value * 100) / 100;
const integerStep = (base, factor, minimum = 1) => Math.max(minimum, Math.round(base * factor));

export function gradeValues(card, grade) {
  const legendary = card.rarity === 'legendary';
  const recastStep = card.recast_time <= 16 ? 0.4 : card.recast_time <= 28 ? 0.6 : card.recast_time <= 40 ? 1 : 1.2;
  const castStep = card.cast_time < 3 ? 0.1 : card.cast_time < 6 ? 0.2 : card.cast_time < 12 ? 0.3 : 0.6;
  const values = { cast_time: round(Math.max(0.6, card.cast_time - castStep * grade)), recast_time: round(Math.max(4, card.recast_time - recastStep * grade)), effects: {} };
  card.effects.forEach((effect, index) => {
    const fields = {};
    switch (effect.type) {
      case 'deal_damage':
        fields.amount = effect.amount + integerStep(effect.amount, legendary ? 0.18 : 0.3) * grade;
        if (effect.bonus_amount !== undefined) fields.bonus_amount = effect.bonus_amount + integerStep(effect.bonus_amount, 0.25) * grade;
        break;
      case 'gain_shield': fields.amount = effect.amount + integerStep(effect.amount, legendary ? 0.18 : 0.28, 2) * grade; break;
      case 'heal': fields.amount = effect.amount + integerStep(effect.amount, legendary ? 0.18 : 0.3) * grade; break;
      case 'apply_status':
        fields.duration = round(effect.duration + Math.min(effect.status === 'bleed' ? 2 : 3, effect.duration * (effect.status === 'bleed' ? 0.05 : 0.1)) * grade);
        if (effect.status === 'bleed') fields.bleed_power = (effect.bleed_power || 1) + (card.upgrade_profile?.bleed_power?.[grade] || 0);
        break;
      case 'delay_enemy_active_card': fields.amount = round(effect.amount + (effect.scope === 'all' ? 0.4 : 0.7) * grade); break;
      case 'haste_own_active_card': fields.amount = round(effect.amount + (effect.scope === 'all' ? 0.3 : 0.5) * grade); break;
      case 'reduce_recast': fields.amount = round(effect.amount + (effect.scope === 'all' ? 0.4 : Math.max(0.6, effect.amount * 0.15)) * grade); break;
      case 'timeline_flow': fields.duration = round(effect.duration + Math.min(0.5, effect.duration * 0.1) * grade); break;
      case 'empower_card': {
        // Preserve the sign: faster cast/recast is a negative permanent modifier.
        const step = Math.abs(effect.amount) * (effect.scope === 'all_own' || effect.scope === 'other_own' ? 0.1 : 0.2);
        fields.amount = round(effect.amount + Math.sign(effect.amount) * step * grade);
        break;
      }
      case 'modify_attack': case 'modify_speed': fields.amount = effect.amount + Math.sign(effect.amount) * Math.floor((grade + 1) / 2); break;
    }
    if (Object.keys(fields).length) values.effects[index] = fields;
  });
  // Automatic queue counts, spacing, recursion caps, shield costs and targets do not scale.
  return values;
}

const targets = cards.filter(card => !tuned.has(card.id) && !recent(card.id));
if (targets.length !== 70) throw new Error('unexpected_tuning_scope');
const fixturePath = 'tests/fixtures/remaining_grades_0_56_0.json';
const prior = fs.existsSync(root + fixturePath) ? read(fixturePath) : null;
const audit = {
  version: 'QQ-0.56.0', references: referenceFixtures,
  protected_cards: Object.fromEntries(cards.filter(card => tuned.has(card.id) || recent(card.id)).map(card => [card.id, hash(card)])),
  cards: targets.map(card => {
    const original = prior?.cards.find(entry => entry.id === card.id)?.before || structuredClone(card);
    return { id: card.id, before: original, grades: Object.fromEntries([1,2,3,4,5].map(grade => [grade, gradeValues(original, grade)])) };
  }),
};
for (const entry of audit.cards) cards.find(card => card.id === entry.id).grade_overrides = entry.grades;
if (process.argv.includes('--check')) {
  if (!prior || JSON.stringify(audit) !== JSON.stringify(prior) || JSON.stringify(cards) !== JSON.stringify(read('data/cards.json'))) throw new Error('grade_publication_drift');
  console.log('REMAINING_GRADES_REPRODUCIBLE_OK cards=70 protected=52 grades=1..5 base-preserved');
} else {
  fs.writeFileSync(root + 'data/cards.json', JSON.stringify(cards, null, 2) + '\n');
  fs.writeFileSync(root + fixturePath, JSON.stringify(audit, null, 2) + '\n');
  console.log('REMAINING_GRADES_GENERATED cards=70 protected=52 grades=1..5');
}
