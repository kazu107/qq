import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
process.chdir(fileURLToPath(new URL('../', import.meta.url)));
const source = await readFile('src/core/battle/RelicBattleController.gd', 'utf8');
const consumers = {};
for (const match of source.matchAll(/_pi?\([^,\n]+,\s*"([a-z0-9_]+)",\s*"([a-z0-9_.%]+)"/g)) {
  const [, id, key] = match;
  (consumers[id] ||= []).push(key === 'thresholds.%d' ? 'thresholds' : key);
}
for (const relic of JSON.parse(await readFile('data/relics.json', 'utf8'))) {
  if (relic.effects?.some(effect => typeof effect.internal_cooldown === 'number')) (consumers[relic.id] ||= []).push('internal_cooldown');
}
for (const id of Object.keys(consumers)) consumers[id] = [...new Set(consumers[id])].sort();
await writeFile('data/balance_lab_consumers.json', JSON.stringify(consumers, null, 2) + '\n');
console.log('BALANCE_LAB_CONSUMERS_GENERATED', Object.keys(consumers).length);
