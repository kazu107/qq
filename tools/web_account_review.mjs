import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright') : require('playwright');
const { accountFixture, testDatabaseEnv, listen, close } = require('../tests/helpers/account_fixture');
const { createQqServer } = require('../server/server');
assert(testDatabaseEnv(), 'Set QQ_AUTH_TEST_DATABASE_URL to a disposable loopback qq_auth_tests database');
const output = resolve('tools/.local/account-tests/browser');
await mkdir(output, { recursive: true });
let fixture = await accountFixture({ publicDir: resolve('build/web-layout-review') });
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
const checks = [];
const context = await browser.newContext({ viewport: { width: 620, height: 900 } });
const attach = page => {
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
  });
};
context.on('page', attach);
let disabled;
try {
  const page = await context.newPage();
  await page.goto(`${fixture.origin}/account`);
  await page.waitForSelector('#google[href]');
  await page.screenshot({ path: resolve(output, 'account-guest-ja.png') });
  await page.locator('#google').click();
  await page.waitForSelector('#registration:not([hidden])');
  assert.equal(await page.locator('#username').inputValue(), '');
  await page.locator('#username').fill('<script>');
  await page.locator('#register').click();
  await page.waitForFunction(() => document.querySelector('#message').classList.contains('error'));
  await page.locator('#username').fill('冒険者_テスト');
  await page.locator('#register').click();
  await page.waitForSelector('#signed-in:not([hidden])');
  assert.equal(await page.locator('#username-display').textContent(), '冒険者_テスト');
  await page.screenshot({ path: resolve(output, 'account-registered-ja.png') });
  await page.locator('#logout').click();
  await page.waitForSelector('#google[href]');
  await page.locator('#google').click();
  await page.waitForSelector('#signed-in:not([hidden])');
  assert.equal(await page.locator('#username-display').textContent(), '冒険者_テスト');
  checks.push('real_browser_google_registration_logout_returning_login');

  const duplicateContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  duplicateContext.on('page', attach);
  const duplicate = await duplicateContext.newPage();
  await duplicate.goto(`${fixture.origin}/account?lang=en`);
  await duplicate.waitForSelector('#github[href]');
  await duplicate.locator('#github').click();
  await duplicate.waitForSelector('#registration:not([hidden])');
  await duplicate.locator('#username').fill('冒険者_テスト');
  await duplicate.locator('#register').click();
  await duplicate.waitForFunction(() => document.querySelector('#message').textContent.includes('already taken'));
  await duplicate.locator('#username').fill('GitHub_Adventurer');
  await duplicate.locator('#register').click();
  await duplicate.waitForSelector('#signed-in:not([hidden])');
  assert.equal(await duplicate.locator('html').getAttribute('lang'), 'en');
  assert(await duplicate.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await duplicate.screenshot({ path: resolve(output, 'account-github-mobile-en.png'), fullPage: true });
  checks.push('github_unique_username_mobile_layout_english');
  await duplicateContext.close();

  const accountId = await page.evaluate(async () => (await (await fetch('/api/account')).json()).user.id);
  await fixture.close();
  fixture = await accountFixture({ reset: false, publicDir: resolve('build/web-layout-review') });
  await page.goto(`${fixture.origin}/account`);
  await page.waitForSelector('#signed-in:not([hidden])');
  assert.equal(await page.evaluate(async () => (await (await fetch('/api/account')).json()).user.id), accountId);
  checks.push('database_identity_and_session_survive_server_restart');

  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(`${fixture.origin}/?pack=local`);
  await page.waitForFunction(() => window.qqLoadMetrics?.some(item => item.event === 'scene_transition' && item.details.screen === 'Hub'), undefined, { timeout: 180000 });
  await page.waitForSelector('#status', { state: 'detached' });
  await page.waitForFunction(() => window.qqLayoutCommand && window.qqAccount);
  const bridge = await page.evaluate(async () => {
    await window.qqAccount.refresh();
    let value;
    window.qqAccount.subscribe(raw => { value = JSON.parse(raw); });
    return value;
  });
  assert.equal(bridge.user.id, accountId);
  assert.equal('csrfToken' in bridge, false);
  let sequence = 0;
  async function inspect() {
    const expected = ++sequence;
    await page.evaluate(payload => window.qqLayoutCommand(JSON.stringify(payload)), { action: 'inspect', sequence: expected });
    await page.waitForFunction(value => JSON.parse(window.qqLayoutState || '{}').sequence === value, expected);
    return page.evaluate(() => JSON.parse(window.qqLayoutState));
  }
  for (const viewport of [{ width: 1440, height: 900 }, { width: 960, height: 600 }, { width: 900, height: 1200 }]) {
    await page.setViewportSize(viewport);
    await page.waitForTimeout(150);
    const state = await inspect();
    for (const name of ['HubAccountButton', 'VersionHistoryButton', 'OpenSettingsButton']) {
      const control = state.controls.find(item => item.name === name);
      assert(control, name);
      const [x, y, width, height] = control.rect;
      assert(x >= 0 && y >= 0 && x + width <= state.viewport[0] + 1 && y + height <= state.viewport[1] + 1, `${name} overflow`);
    }
    await page.screenshot({ path: resolve(output, `hub-${viewport.width}x${viewport.height}.png`) });
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  const state = await inspect();
  const [x, y, width, height] = state.controls.find(item => item.name === 'HubAccountButton').rect;
  const popupPromise = page.waitForEvent('popup');
  await page.mouse.click((x + width / 2) * 1440 / state.viewport[0], (y + height / 2) * 900 / state.viewport[1]);
  const popup = await popupPromise;
  await popup.waitForSelector('#signed-in:not([hidden])');
  assert.equal(await popup.locator('#username-display').textContent(), '冒険者_テスト');
  await popup.locator('#logout').click();
  await popup.waitForSelector('#google[href]');
  await page.waitForFunction(async () => { await window.qqAccount.refresh(); let current; window.qqAccount.subscribe(raw => { current = JSON.parse(raw); }); return !current.authenticated; });
  await popup.locator('#google').click();
  await popup.waitForSelector('#signed-in:not([hidden])');
  assert.equal(await popup.locator('#username-display').textContent(), '冒険者_テスト');
  assert.equal(await popup.evaluate(() => sessionStorage.getItem('qq-account-popup')), '1');
  const closed = popup.waitForEvent('close');
  await popup.locator('#return').click();
  await closed;
  assert.equal((await inspect()).screen, 'Hub');
  await page.waitForFunction(async () => { await window.qqAccount.refresh(); let current; window.qqAccount.subscribe(raw => { current = JSON.parse(raw); }); return current.authenticated; });
  checks.push('godot_hub_account_popup_bridge_logout_no_game_reload_responsive');

  disabled = createQqServer({ env: {} });
  const disabledOrigin = await listen(disabled.server);
  const disabledPage = await context.newPage();
  await disabledPage.goto(`${disabledOrigin}/account`);
  await disabledPage.waitForFunction(() => document.querySelector('#message').textContent.includes('準備中'));
  assert.equal(await disabledPage.locator('#google').getAttribute('aria-disabled'), 'true');
  assert.equal(await disabledPage.locator('#github').getAttribute('href'), null);
  await disabledPage.screenshot({ path: resolve(output, 'account-unconfigured-ja.png') });
  checks.push('production_safe_unconfigured_providers_disabled');
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ checks, errors }, null, 2));
  console.log('WEB_ACCOUNT_REVIEW_OK', JSON.stringify({ checks, errors }));
} finally {
  await browser.close();
  await fixture.close();
  if (disabled) await close(disabled.server);
}
