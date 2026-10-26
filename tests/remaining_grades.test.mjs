import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
const read = path => JSON.parse(fs.readFileSync(new URL('../' + path, import.meta.url), 'utf8'));
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

test('70-card grade-only publication preserves all base definitions and 52 individually tuned cards', () => {
  const cards = read('data/cards.json');
  const audit = read('tests/fixtures/remaining_grades_0_56_0.json');
  assert.equal(audit.cards.length, 70); assert.equal(Object.keys(audit.protected_cards).length, 52);
  assert.equal(new Set([...audit.cards.map(card => card.id), ...Object.keys(audit.protected_cards)]).size, 122);
  for (const [id, expected] of Object.entries(audit.protected_cards)) assert.equal(hash(cards.find(card => card.id === id)), expected, id);
  for (const entry of audit.cards) {
    const published = structuredClone(cards.find(card => card.id === entry.id));
    assert.deepEqual(published.grade_overrides, entry.grades, entry.id);
    delete published.grade_overrides;
    const before = structuredClone(entry.before); delete before.grade_overrides;
    assert.deepEqual(published, before, entry.id + ' base/profile/mechanics changed');
    let previous = entry.before;
    for (const grade of [1,2,3,4,5]) {
      const values = entry.grades[grade];
      assert(values.cast_time > 0 && values.cast_time <= previous.cast_time);
      assert(values.recast_time >= 4 && values.recast_time <= previous.recast_time);
      for (const [index, fields] of Object.entries(values.effects)) {
        for (const field of Object.keys(fields)) assert(['amount','duration','bonus_amount','bleed_power'].includes(field));
        const effect = entry.before.effects[index];
        if (effect.type === 'empower_card' || effect.type.startsWith('modify_')) assert.equal(Math.sign(fields.amount), Math.sign(effect.amount), entry.id);
        if (effect.type === 'timeline_flow') assert(fields.duration <= effect.duration + 2.5);
      }
      previous = values;
    }
  }
});
