import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const rules = require('../server/ranking/rules.json');
const catalog = require('../server/ranking/catalog.json');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/ranking-seasons/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], cases = [];
try {
  for (const language of ['ja', 'en']) for (const size of [{ width: 1100, height: 850 }, { width: 390, height: 844 }]) {
    const page = await browser.newPage({ viewport: size });
    page.on('pageerror', error => errors.push(String(error)));
    const first = { id: 'season-1', number: 1, startsAt: '2026-10-24T00:00:00Z', endsAt: null };
    let current = first, seasons = [first], lastQuery;
    await page.route('**/api/ranked/**', async route => {
      const url = new URL(route.request().url());
      if (url.pathname.endsWith('/history')) return route.fulfill({ json: { runs: [{ season_id: 'season-1', status: 'verified', starter_id: 'balanced', result: { total_score: 12000 } }] } });
      lastQuery = url.searchParams;
      const selected = url.searchParams.get('season') || current.id;
      const entry = { id: 'fixture', rank: 1, username: 'SeasonReview', season_id: selected,
        starter_id: 'balanced', finished_at: '2026-10-24T00:00:00Z', result: { total_score: 12000, reached_step: 12, reached_cycle: 1, cards: ['strike'], relics: [], battle_count: 9 } };
      const entries = selected === 'season-1' ? [entry] : [];
      return route.fulfill({ json: { season: current, seasons, selection: { season_id: selected }, rules: { starters: rules.starters }, catalog, entries, self: entries[0] || null } });
    });
    async function ready() {
      await page.waitForFunction(() => !document.getElementById('refresh').disabled && document.querySelector('#season option'));
    }
    async function refresh() { await page.locator('#refresh').click(); await ready(); }
    await page.goto(`http://127.0.0.1:${app.server.address().port}/rankings?lang=${language}`);
    await ready();
    assert.equal(await page.locator('#season option').count(), 1);
    assert.equal(await page.locator('#ruleset').count(), 0);
    assert.equal(await page.locator('#season').inputValue(), 'season-1');
    assert.equal(await page.locator('#season option:checked').innerText(), language === 'ja' ? 'シーズン1（開催中）' : 'Season 1 (active)');
    await page.locator('#entries button').click();
    assert((await page.locator('#detail-body').innerText()).startsWith(language === 'ja' ? 'シーズン1' : 'Season 1'));
    await page.locator('#close').click();
    await page.locator('#starter').selectOption('tempo'); await ready();
    assert.equal(lastQuery.get('starter'), 'tempo');
    assert.equal(lastQuery.has('ruleset'), false);
    await refresh();
    assert.equal(await page.locator('#season option').count(), 1, 'Refresh/month passage must not create a UI season');
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({ path: resolve(output, `${language}-${size.width}-season1.png`), fullPage: true });
    first.endsAt = '2026-12-03T00:00:00Z';
    current = { id: 'season-2', number: 2, startsAt: first.endsAt, endsAt: null };
    seasons = [current, first];
    await refresh();
    assert.equal(await page.locator('#season').inputValue(), 'season-2');
    assert.equal(await page.locator('#entries button').count(), 0, 'New gameplay season must start empty');
    await page.locator('#season').selectOption('season-1'); await ready();
    assert.equal(await page.locator('#entries button').count(), 1, 'Completed season records remain available');
    await refresh();
    assert.equal(await page.locator('#season').inputValue(), 'season-1');
    assert(!(await page.locator('#history').innerText()).includes('infinite-'));
    cases.push(`${language} ${size.width}: one numbered season, no rules filter, next season auto-follow, archived scores`);
    await page.close();
  }
  assert.deepEqual(errors, []);
  console.log('WEB_RANKING_SEASONS_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ errors, cases }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
