import { readFile, writeFile } from 'node:fs/promises';
const ja=JSON.parse(await readFile('data/localization/ja.json','utf8'));
const catalog={};
for(const [kind,file] of [['card','cards'],['relic','relics'],['starter','starters']]) {
  const entries=JSON.parse(await readFile(`data/${file}.json`,'utf8'));
  catalog[kind]=Object.fromEntries(entries.map(entry=>[entry.id,{en:entry.name,ja:ja[`${kind}.${entry.id}.name`] || entry.name}]));
}
await writeFile('server/ranking/catalog.json',JSON.stringify(catalog,null,2)+'\n');
console.log('RANKING_CATALOG_GENERATED');
