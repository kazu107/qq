import { readFile, writeFile } from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
process.chdir(fileURLToPath(new URL('../',import.meta.url)));
const ja=JSON.parse(await readFile('data/localization/ja.json','utf8'));
const catalog={};
for(const [kind,file] of [['card','cards'],['relic','relics'],['starter','starters']]) {
  const entries=JSON.parse(await readFile(`data/${file}.json`,'utf8'));
  catalog[kind]=Object.fromEntries(entries.map(entry=>[entry.id,{en:entry.name,ja:ja[`${kind}.${entry.id}.name`] || entry.name}]));
}
await writeFile('server/ranking/catalog.json',JSON.stringify(catalog,null,2)+'\n');
const version=JSON.parse(await readFile('data/version_history.json','utf8')).current_version;
await writeFile('server/ranking/build.json',JSON.stringify({game_version:version})+'\n');
console.log('RANKING_CATALOG_GENERATED');
