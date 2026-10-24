import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
process.chdir(fileURLToPath(new URL('../', import.meta.url)));
for (const file of ['data/cards.json', 'data/boss_cards.json']) {
  const cards = JSON.parse(await readFile(file, 'utf8'));
  for (const card of cards) {
    card.upgrade_profile ||= {};
    if (card.id === 'timekeeper_amplify') card.upgrade_profile.recast_time ||= [0, 0, 0, 0, -0.8, -1.6];
    if (card.id === 'timekeeper_time_mark') card.upgrade_profile.duration ||= [0, 0, 0, 0, 3, 6];
    for (const values of Object.values(card.upgrade_profile)) {
      if (values.length < 4) throw new Error(`Missing published grades: ${card.id}`);
      const step = values[3] - values[2];
      while (values.length < 6) values.push(Number((values.at(-1) + step).toFixed(3)));
    }
  }
  await writeFile(file, JSON.stringify(cards, null, 2) + '\n');
  console.log('CARD_GRADES_EXTENDED', file, cards.length);
}
