import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { accountFixture } = require('../tests/helpers/account_fixture');
const { RankingStore, rules } = require('../server/ranking/store');
const { startSeason, pause } = require('../server/ranking/lifecycle');
const { chromium } = process.env.QQ_NODE_MODULES ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const out = resolve('tools/.local/ranking-preparing/browser');
await mkdir(out, { recursive: true });
const fixture = await accountFixture({ rankingState: 'preparing', publicDir: resolve('build/web-layout-review') });
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
try {
  for (const lang of ['ja','en']) for (const size of [{ width: 1440, height: 900 }, { width: 390, height: 844 }]) {
    const page = await browser.newPage({ viewport: size });
    page.on('pageerror', error => errors.push(String(error)));
    await page.goto(fixture.origin + '/rankings?lang=' + lang);
    await page.waitForFunction(() => document.getElementById('notice').textContent.includes(document.documentElement.lang === 'ja' ? '準備中' : 'being prepared'));
    assert.equal(await page.locator('#season option').count(), 0);
    assert.equal(await page.locator('#season').isDisabled(), true);
    assert.equal(await page.locator('.ranking-scroll').isVisible(), false);
    assert.equal(await page.locator('.ranking-history').isVisible(), false);
    await page.locator('#refresh').click();
    await page.waitForFunction(() => !document.getElementById('refresh').disabled);
    assert.equal(await new RankingStore(fixture.store.pool).ensureSeason(), null);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({ path: resolve(out, `preparing-${lang}-${size.width}.png`), fullPage: true });
    await page.close();
  }
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/m.test(message.text())) errors.push(message.text()); });
  await page.goto(fixture.origin + '/?pack=local', { waitUntil: 'commit' });
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  await page.waitForTimeout(600);
  await page.evaluate(() => window.qqLayoutCommand(JSON.stringify({ action: 'inspect', sequence: 123 })));
  await page.waitForFunction(() => JSON.parse(window.qqLayoutState || '{}').sequence === 123);
  const state = await page.evaluate(() => JSON.parse(window.qqLayoutState));
  const start = state.controls.find(control => control.name === 'HubRankedStartButton');
  assert(start); assert.match(start.text, /準備中|Preparing/); assert.equal(start.disabled, true);
  await page.screenshot({ path: resolve(out, 'hub-preparing.png') });
  await page.evaluate(() => window.qqRanked.open('ja'));
  const panel = page.frameLocator('iframe[src^="/rankings"]');
  await panel.locator('#notice').filter({ hasText: '準備中' }).waitFor();
  assert.equal(browser.contexts().flatMap(context => context.pages()).length, 1);
  await page.screenshot({ path: resolve(out, 'embedded-preparing.png') });
  // Only the isolated test DB is started, to verify a later explicit start restores the same view.
  const generation = (await new RankingStore(fixture.store.pool).availability()).generation;
  await startSeason(fixture.store.pool, rules.ruleset, generation);
  await panel.locator('#refresh').click();
  await panel.locator('#season option').waitFor({ state: 'attached' });
  assert.equal(await panel.locator('#season').inputValue(), 'season-1');
  assert.equal(await panel.locator('.ranking-scroll').isVisible(), true);
  await pause(fixture.store.pool);
  assert.deepEqual(errors, []);
  console.log('WEB_RANKING_PREPARING_OK real-test-DB ja/en desktop/mobile embedded/Hub no-auto-start explicit-start errors=0');
} finally { await browser.close(); await fixture.close(); }
