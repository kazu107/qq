import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

const manifestPath = 'art_src/blender/cards/echo_cast.manifest.json';
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const sha = async path => createHash('sha256').update(await readFile(path)).digest('hex');
const generators = {};
for (const path of [manifest.generator, 'tools/blender/build_art_vertical_slice.py', 'tools/blender/card_action_scenes.py']) generators[path] = await sha(path);
assert.equal(await sha(manifest.source_path), manifest.source_sha256);
const path = 'data/art_provenance.json';
let text = (await readFile(path, 'utf8')).replaceAll('\r\n', '\n');
const data = JSON.parse(text);
const block = entry => JSON.stringify(entry, null, 2).split('\n').map(line => '    ' + line).join('\n');
for (const asset of manifest.assets) {
  const entry = { ...asset, source_path: manifest.source_path, generator: manifest.generator,
    export_sha256: await sha(asset.runtime_path), source_sha256: manifest.source_sha256,
    generator_sha256: generators, manifest_path: manifestPath, tool: manifest.tool,
    replacement_status: 'implemented', batch_id: 'blender_echo_card_09', author: 'QQ project', license: 'project-original', third_party_inputs: [] };
  const index = data.assets.findIndex(old => old.runtime_path === asset.runtime_path);
  if (index >= 0) {
    assert.equal(data.assets[index].generator, manifest.generator, 'Refusing to replace another generator owner');
    const original = block(data.assets[index]); assert(text.includes(original));
    text = text.replace(original, block(entry)); data.assets[index] = entry;
  } else {
    const end = text.lastIndexOf('\n  ],\n  "batch_ids"'); assert(end > 0);
    text = text.slice(0, end) + ',\n' + block(entry) + text.slice(end); data.assets.push(entry);
  }
}
if (!data.batch_ids.includes('blender_echo_card_09')) {
  const last = '    ' + JSON.stringify(data.batch_ids.at(-1));
  assert(text.includes(last)); text = text.replace(last, last + ',\n    "blender_echo_card_09"');
}
text = text.replace(/"updated_at": "[^"]+"/, '"updated_at": "2026-10-25"');
JSON.parse(text);
await writeFile(path, text);
const coveragePath = 'data/art_coverage.json', coverage = JSON.parse(await readFile(coveragePath, 'utf8'));
coverage.updated_at = '2026-10-25'; coverage.registered_assets = data.assets.length;
coverage.coverage.Cards.done = coverage.coverage.Cards.total = JSON.parse(await readFile('data/cards.json', 'utf8')).length;
coverage.coverage.Status.done = coverage.coverage.Status.total = data.assets.filter(entry => entry.category === 'status').length;
await writeFile(coveragePath, JSON.stringify(coverage, null, 2) + '\n');
console.log('ECHO_ART_REGISTERED', manifest.assets.map(entry => entry.runtime_path));
