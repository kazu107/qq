import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const output = resolve('tools/.local/ui-copy/browser');
await mkdir(output, { recursive: true });
const app = createQqServer({ env: {}, publicDir: resolve('build/web-layout-review') });
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const origin = `http://127.0.0.1:${app.server.address().port}`;
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [], checks = [];
const ja = JSON.parse(await readFile('data/localization/ja.json', 'utf8'));
const forbidden = [
  ['hub.tagline', 'Every card has its moment. Make yours count.'],
  ['hub.mode.normal_detail', 'Choose a route, gather cards and relics, and challenge the boss.'],
  ['settings.page_hint', 'Changes are saved automatically and used throughout the game.'],
  ['meta.page_hint', 'Achievements and automatic unlocks. Manage seals in the Card & Relic Library.'],
  ['run_setup.subtitle', 'Compare each frame, inspect its opening hand, then choose your combat loadout.'],
  ['run_setup.deck_list_hint', 'Select a deck to compare its frame and opening cards.'],
  ['run_setup.preview_hint', 'The battle-ready stance and equipped frame are previewed in real time.'],
  ['tutorial.catalog.subtitle', 'Choose a lesson. More tutorials can be added to this list later.'],
  ['reward.choose_one', 'Choose one card. Hover to inspect details.'],
  ['result.eyebrow', 'OPERATION REPORT'],
];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (/SCRIPT ERROR|Parse Error|^ERROR:/.test(message.text())) errors.push(message.text()); });
  await page.goto(`${origin}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  let sequence = 0;
  async function command(action, extra = {}) {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action, ...extra, sequence: expected });
    await page.waitForFunction(seq => JSON.parse(window.qqLayoutState || '{}').sequence === seq, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  async function click(state, name) {
    const control = state.controls.find(item => item.name === name);
    assert(control, `Missing ${name}`);
    const [x, y, w, h] = control.rect, box = await page.locator('#canvas').boundingBox();
    await page.mouse.click(box.x + (x + w / 2) * box.width / state.viewport[0], box.y + (y + h / 2) * box.height / state.viewport[1]);
    return command('inspect');
  }
  for (const language of ['ja', 'en']) {
    for (const screen of ['hub', 'setup', 'settings', 'meta', 'tutorials', 'reward', 'result', 'balance', 'arena']) {
      const state = await command('content_fixture', { language, screen });
      for (const [key, english] of forbidden) {
        assert(!state.captions.includes(language === 'ja' ? ja[key] : english), `Redundant ${screen} caption: ${key}`);
      }
      assert(!state.captions.includes('LIVE 3D'));
      if (['hub', 'setup', 'meta', 'reward', 'balance'].includes(screen)) await page.screenshot({ path: resolve(output, `${screen}-${language}.png`) });
      checks.push(`${language}:${screen}`);
    }
    let state = await command('content_fixture', { language, screen: 'hub' });
    state = await click(state, 'VersionHistoryButton');
    assert(state.history.open && state.history.bbcode.includes('[table=2]'));
    assert(!state.history.bbcode.includes('  [color=#c9d7e2]- '));
    for (const size of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
      await page.setViewportSize(size);
      state = await command('inspect');
      const overflow = state.controls.filter(item => !item.scroll && item.rect[2] > 1 && item.rect[3] > 1 &&
        (item.rect[0] < -2 || item.rect[1] < -2 || item.rect[0] + item.rect[2] > state.viewport[0] + 2 || item.rect[1] + item.rect[3] > state.viewport[1] + 2));
      assert.deepEqual(overflow, [], `History overflow ${language}:${size.width}`);
      await page.screenshot({ path: resolve(output, `history-${language}-${size.width}.png`) });
      checks.push(`${language}:history:${size.width}`);
    }
    await page.setViewportSize({ width: 1440, height: 900 });
  }
  const servicePage = await browser.newPage();
  servicePage.on('pageerror', error => errors.push(String(error)));
  for (const language of ['ja', 'en']) {
    await servicePage.goto(`${origin}/account?lang=${language}`);
    await servicePage.waitForFunction(() => !document.querySelector('#message').textContent.includes('...'));
    assert.equal(await servicePage.locator('#subtitle, #eyebrow').count(), 0);
    assert(await servicePage.locator('#privacy-note').textContent());
    assert(await servicePage.locator('#username-hint').textContent());
    await servicePage.goto(`${origin}/rankings?lang=${language}`);
    assert.equal(await servicePage.locator('section > p.muted').count(), 0);
    assert((await servicePage.locator('#season').getAttribute('title')).includes(language === 'ja' ? '月替わり' : 'Calendar'));
    checks.push(`${language}:service-pages`);
  }
  assert.deepEqual(errors, []);
  console.log('WEB_UI_COPY_REVIEW_OK', checks);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ checks, errors }, null, 2));
  await browser.close();
  await new Promise(done => app.server.close(done));
}
