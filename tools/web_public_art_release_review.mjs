import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const expectedCommit = process.env.QQ_RELEASE_COMMIT;
assert(expectedCommit, 'Set QQ_RELEASE_COMMIT to the pushed commit');
const publicUrl = new URL('https://masterqueue.kazu107.xyz/');
publicUrl.searchParams.set('release_review', expectedCommit);
const manifest = await fetch(`https://qq.kazu107.xyz/releases/current.json?release_review=${expectedCommit}`).then(response => {
  assert.equal(response.status, 200);
  return response.json();
});
assert.equal(manifest.game_version, process.env.QQ_RELEASE_VERSION || 'QQ-0.32.1');
assert.equal(manifest.commit, expectedCommit);
const output = resolve('tools/.local/blender-public-review');
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
const packs = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
  });
  page.on('response', response => {
    if (response.url().endsWith('.pck')) packs.push({ url: response.url(), status: response.status() });
  });
  await page.goto(publicUrl.toString(), { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  await page.waitForTimeout(300);
  const canvas = await page.locator('#canvas').boundingBox();
  assert.equal(canvas.width, 1440);
  assert.equal(canvas.height, 900);
  assert(packs.some(pack => pack.url === manifest.pck.url && pack.status === 200), 'New R2 pack was not fetched');
  assert.deepEqual(errors, []);
  await page.screenshot({ path: resolve(output, 'hub.png') });
  const metrics = await page.evaluate(() => window.qqLoadMetrics);
  if (process.env.QQ_EXPECTED_CONTENT_HASH) {
    assert.equal(metrics.find(item => item.event === 'boot_ready').details.network_hash, process.env.QQ_EXPECTED_CONTENT_HASH);
  }
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ manifest, packs, canvas, metrics, errors }, null, 2));
  console.log('PUBLIC_BLENDER_ART_RELEASE_OK', JSON.stringify({ version: manifest.game_version, commit: manifest.commit, packs, errors }));
} finally {
  await browser.close();
}
