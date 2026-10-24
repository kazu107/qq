import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { seasonAt, groupSeasons, selectBoard, rules } = require('../server/ranking/store');
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
    let current = seasonAt(new Date('2026-10-24T00:00:00Z'));
    const september = seasonAt(new Date('2026-09-24T00:00:00Z'));
    const rows = ['infinite-1', 'infinite-2', rules.ruleset].map(rule => ({ id: `${rule}:2026-10`, ruleset: rule, starts_at: current.startsAt }));
    rows.push(...['infinite-9', 'infinite-10'].map(rule => ({ id: `${rule}:2026-09`, ruleset: rule, starts_at: september.startsAt })));
    let lastSelection;
    await page.route('**/api/ranked/**', async route => {
      const url = new URL(route.request().url());
      if (url.pathname.endsWith('/history')) return route.fulfill({ json: { runs: [{ season_id: 'infinite-1:2026-10', ruleset: 'infinite-1', status: 'verified', starter_id: 'balanced', result: { total_score: 99000 } }] } });
      const seasons = groupSeasons(rows, current);
      const selection = selectBoard(seasons, url.searchParams.get('season'), url.searchParams.get('ruleset'), current);
      lastSelection = { ...selection, starter: url.searchParams.get('starter') };
      const entry = { id: 'fixture', rank: 1, username: 'SeasonReview', season_id: selection.season_id, ruleset: selection.ruleset,
        starter_id: 'balanced', finished_at: '2026-10-24T00:00:00Z', result: { total_score: selection.ruleset === 'infinite-1' ? 99000 : 12000, reached_step: 12, reached_cycle: 1, cards: ['strike'], relics: [], battle_count: 9 } };
      return route.fulfill({ json: { season: current, seasons, selection, rules: { ...rules, ruleset: current.ruleset }, catalog, entries: [entry], self: entry } });
    });
    async function ready() {
      await page.waitForFunction(() => !document.getElementById('refresh').disabled && document.querySelector('#entries button'));
    }
    async function select(id, value) {
      await page.locator('#' + id).selectOption(value);
      await ready();
    }
    async function refresh() {
      await page.locator('#refresh').click();
      await ready();
    }
    await page.goto(`http://127.0.0.1:${app.server.address().port}/rankings?lang=${language}`);
    await ready();
    assert.equal(await page.locator('#season option').count(), 2, 'Three legacy October buckets must render one October plus one September');
    assert.equal(await page.locator('#season option[value="2026-10"]').count(), 1);
    assert.equal(await page.locator('#season').inputValue(), '2026-10');
    assert.equal(await page.locator('#ruleset option').count(), 3);
    assert.equal(await page.locator('#ruleset').inputValue(), rules.ruleset);
    assert.equal(await page.locator('#season option:checked').innerText(), language === 'ja' ? '2026年10月' : '2026-10');
    await select('ruleset', 'infinite-1');
    assert((await page.locator('#entries').innerText()).includes('99,000'));
    await page.locator('#entries button').click();
    assert((await page.locator('#detail-body').innerText()).includes(language === 'ja' ? 'ルール1' : 'Rules 1'));
    await page.locator('#close').click();
    await select('starter', 'tempo');
    assert.equal(lastSelection.ruleset, 'infinite-1');
    assert.equal(lastSelection.starter, 'tempo');
    await select('season', '2026-09');
    assert.equal(await page.locator('#ruleset').inputValue(), 'infinite-10');
    await select('season', '2026-10');
    assert.equal(await page.locator('#ruleset').inputValue(), rules.ruleset);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Filters overflow at mobile width');
    await page.screenshot({ path: resolve(output, `${language}-${size.width}-october.png`), fullPage: true });
    current = { ...current, ruleset: 'infinite-4' };
    await refresh();
    assert.equal(await page.locator('#season option').count(), 2, 'Rule update must not add a season');
    assert.equal(await page.locator('#ruleset').inputValue(), 'infinite-4');
    current = { ...seasonAt(new Date('2026-11-01T00:00:00Z')), ruleset: 'infinite-4' };
    rows.push({ id: '2026-11', starts_at: current.startsAt, ruleset: 'infinite-4' });
    await refresh();
    assert.equal(await page.locator('#season').inputValue(), '2026-11', 'Current selection must follow JST month rollover');
    await select('season', '2026-10');
    await select('ruleset', 'infinite-1');
    await refresh();
    assert.equal(await page.locator('#season').inputValue(), '2026-10', 'Historical month selection must survive refresh');
    assert.equal(await page.locator('#ruleset').inputValue(), 'infinite-1');
    assert((await page.locator('#history').innerText()).includes(language === 'ja' ? '2026年10月 / ルール1' : '2026-10 / Rules 1'));
    cases.push(`${language} ${size.width}: grouped October, separate rules/history/details, filters, rule update and month rollover`);
    await page.close();
  }
  assert.deepEqual(errors, []);
  console.log('WEB_RANKING_SEASONS_REVIEW_OK', cases);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ errors, cases }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
