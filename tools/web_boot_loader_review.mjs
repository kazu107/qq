import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright')
  : require('playwright');
const output = resolve('tools/.local/web-boot-loader');
await mkdir(output, { recursive: true });
const app = createQqServer();
await new Promise(done => app.server.listen(0, '127.0.0.1', done));
const url = `http://127.0.0.1:${app.server.address().port}/?pack=local`;
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const report = { cases: [] };

async function appearance(page) {
  return page.evaluate(() => {
    const overlay = document.querySelector('#status');
    const bar = document.querySelector('#status-progress');
    const logo = document.querySelector('#status-splash');
    const panel = document.querySelector('#status-loading');
    const rect = element => {
      const { x, y, width, height } = element.getBoundingClientRect();
      return { x, y, width, height };
    };
    return {
      background: getComputedStyle(overlay).backgroundImage,
      logo: rect(logo),
      bar: rect(bar),
      panel: rect(panel),
    };
  });
}

async function reviewRealBoot() {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
  });
  await page.addInitScript(() => {
    window.bootReview = { phases: [], progress: [], replaced: false, removedBeforeHub: false };
    let firstOverlay = null;
    let sawRemoval = false;
    new MutationObserver(() => {
      const overlay = document.getElementById('status');
      if (overlay) {
        if (firstOverlay && overlay !== firstOverlay) window.bootReview.replaced = true;
        firstOverlay ||= overlay;
        const phase = overlay.dataset.phase;
        if (phase !== window.bootReview.phases.at(-1)) window.bootReview.phases.push(phase);
        const bar = document.getElementById('status-progress');
        if (bar?.hasAttribute('value')) window.bootReview.progress.push(bar.value);
      } else if (firstOverlay && !sawRemoval) {
        sawRemoval = true;
        window.bootReview.removedBeforeHub = !window.qqLoadMetrics?.some(entry =>
          entry.event === 'scene_transition' && entry.details.screen === 'Hub');
      }
    }).observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ['data-phase', 'value'] });
  });
  await page.route('**/index.pck', async route => {
    await new Promise(done => setTimeout(done, 1500));
    await route.continue();
  });
  try {
    await page.goto(url, { waitUntil: 'commit' });
    await page.waitForFunction(() => window.qqBootLoader && document.querySelector('#status')?.dataset.phase === 'download');
    await page.locator('#status-splash').evaluate(image => image.decode());
    assert.equal(await page.title(), 'QueueQuest');
    const logoSource = await page.locator('#status-splash').getAttribute('src');
    assert.equal(logoSource, 'queuequest-logo.svg', 'The loader did not use the standalone SVG logo');
    assert.match(await page.locator('#status-percent').textContent(), /^\d+%$/);
    const downloadAppearance = await appearance(page);
    await page.screenshot({ path: resolve(output, 'download.png') });
    await page.waitForFunction(() => document.querySelector('#status')?.dataset.phase === 'preparing', undefined, { timeout: 90000 });
    const preparingAppearance = await appearance(page);
    assert.deepEqual(preparingAppearance, downloadAppearance, 'Loading layout changed between download and preparation');
    const progressSnapshot = await page.evaluate(() => ({
      text: document.getElementById('status-percent').textContent,
      value: document.getElementById('status-progress').value,
    }));
    assert.equal(progressSnapshot.text, `${Math.floor(progressSnapshot.value * 100)}%`);
    assert((await page.locator('#status-transfer').textContent()).length > 0);
    await page.screenshot({ path: resolve(output, 'preparing.png') });
    await page.waitForFunction(() => window.qqLoadMetrics?.some(entry =>
      entry.event === 'scene_transition' && entry.details.screen === 'Hub'), undefined, { timeout: 90000 });
    await page.waitForFunction(() => document.querySelector('#status')?.dataset.phase === 'ready');
    assert.equal(await page.locator('#status-percent').textContent(), '100%');
    assert.equal(await page.locator('#status-detail').textContent(), '読み込み完了');
    await page.waitForFunction(() => {
      const opacity = Number(getComputedStyle(document.getElementById('status')).opacity);
      return opacity > 0.1 && opacity < 0.9;
    });
    const fadeOpacity = await page.locator('#status').evaluate(overlay => Number(getComputedStyle(overlay).opacity));
    assert.equal(await page.locator('#status').evaluate(overlay => getComputedStyle(overlay).pointerEvents), 'auto', 'Completion must block clicks until the Hub is revealed');
    await page.screenshot({ path: resolve(output, 'completion-fade.png') });
    await page.waitForSelector('#status', { state: 'detached' });
    await page.screenshot({ path: resolve(output, 'hub.png') });
    const evidence = await page.evaluate(() => window.bootReview);
    assert(!evidence.replaced && !evidence.removedBeforeHub, 'Loading screen was replaced or removed before the Hub');
    for (const phase of ['download', 'initializing', 'preparing', 'ready']) {
      assert(evidence.phases.includes(phase), `Missing loading phase: ${phase}`);
    }
    assert(evidence.progress.at(-1) === 1, 'Loading did not reach completion');
    assert(evidence.progress.every((value, index, values) => index === 0 || value >= values[index - 1]), 'Loading bar went backwards');
    assert.deepEqual(errors, []);
    report.real_boot = { ...evidence, appearance: preparingAppearance, fade_opacity: fadeOpacity };
    report.cases.push('real_download_preparation_hub');
  } catch (error) {
    await page.screenshot({ path: resolve(output, 'failure.png') });
    throw error;
  } finally {
    await page.close();
  }
}

async function mockPage(startBody = 'window.mockEngineStarted = true;', options = {}) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, ...options });
  await page.route('**/index.js', route => route.fulfill({
    contentType: 'application/javascript',
    body: `window.Engine = class {
      constructor(config) { this.config = config; window.mockEngineConfig = config; }
      static getMissingFeatures() { return []; }
      async init() {}
      async preloadFile() { this.config.onProgress(100, 100); }
      async start() { ${startBody} }
    };`,
  }));
  await page.goto(url);
  return page;
}

try {
  await reviewRealBoot();
  const modern = await mockPage();
  await modern.waitForFunction(() => window.mockEngineStarted);
  assert(await modern.locator('#status').isVisible(), 'Engine startup removed the overlay before preparation');
  assert.equal(await modern.locator('#status-percent').textContent(), '65%');
  assert.equal(await modern.locator('#status-transfer').textContent(), 'ゲームエンジンを初期化しています');
  await modern.evaluate(() => window.mockEngineConfig.onProgress(50 * 1024 * 1024, 100 * 1024 * 1024));
  assert.equal(await modern.locator('#status-transfer').textContent(), '50.0 / 100.0 MB');
  await modern.evaluate(() => window.qqBootLoader.update('Preparing...', 0.5));
  const progress = await modern.locator('#status-progress').evaluate(bar => bar.value);
  assert(progress > 0.65 && progress < 1);
  await modern.evaluate(() => window.mockEngineConfig.onProgress(20, 100));
  assert.equal(await modern.locator('#status-progress').evaluate(bar => bar.value), progress, 'A late download callback reset preparation');
  assert.equal(await modern.locator('#status-detail').textContent(), 'Preparing...');
  await modern.setViewportSize({ width: 390, height: 844 });
  const mobileAppearance = await appearance(modern);
  assert(mobileAppearance.bar.x >= 0 && mobileAppearance.bar.x + mobileAppearance.bar.width <= 390);
  await modern.screenshot({ path: resolve(output, 'mobile-preparing.png') });
  await modern.setViewportSize({ width: 844, height: 390 });
  const landscapeAppearance = await appearance(modern);
  assert(landscapeAppearance.logo.y + landscapeAppearance.logo.height <= landscapeAppearance.panel.y, 'Landscape logo overlapped the loading panel');
  await modern.screenshot({ path: resolve(output, 'landscape-preparing.png') });
  await modern.evaluate(() => window.qqBootLoader.update('Prepared', 1));
  assert.equal(await modern.locator('#status-percent').textContent(), '99%', '100% must be reserved for a rendered Hub');
  await modern.evaluate(() => window.qqBootLoader.finish());
  assert.equal(await modern.locator('#status-percent').textContent(), '100%');
  await modern.waitForSelector('#status', { state: 'detached' });
  await modern.close();
  report.cases.push('progress_text_and_transfer_size', 'bridge_and_late_download_callback', 'mobile_layout', 'completion_fade');

  const reduced = await mockPage(undefined, { reducedMotion: 'reduce' });
  await reduced.waitForFunction(() => window.mockEngineStarted);
  assert.equal(await reduced.locator('#status').evaluate(overlay => getComputedStyle(overlay).transitionDuration), '0s');
  await reduced.evaluate(() => window.qqBootLoader.finish());
  await reduced.waitForSelector('#status', { state: 'detached' });
  await reduced.close();
  report.cases.push('reduced_motion');

  const legacy = await mockPage();
  await legacy.evaluate(() => { window.qqLoadMetrics = [{ event: 'boot_ready', details: {} }]; });
  assert(await legacy.locator('#status').isVisible(), 'Legacy pack finished before its Hub');
  await legacy.evaluate(() => window.qqLoadMetrics.push({ event: 'scene_transition', details: { screen: 'Hub' } }));
  await legacy.waitForSelector('#status', { state: 'detached' });
  await legacy.close();
  report.cases.push('previous_r2_pack');

  const failure = await mockPage("throw new Error('BOOT_FAILURE');");
  await failure.waitForFunction(() => document.querySelector('#status')?.dataset.phase === 'failed');
  assert((await failure.locator('#status-notice').textContent()).includes('BOOT_FAILURE'));
  await failure.evaluate(() => { window.qqBootLoader.update('Late progress', 1); window.qqBootLoader.finish(); });
  assert(await failure.locator('#status-notice').isVisible(), 'A late callback hid the startup failure');
  await failure.close();
  report.cases.push('startup_failure');

  const missingEngine = await browser.newPage();
  await missingEngine.route('**/index.js', route => route.abort());
  await missingEngine.goto(url);
  await missingEngine.waitForFunction(() => document.querySelector('#status')?.dataset.phase === 'failed');
  assert(await missingEngine.locator('#status-notice').isVisible());
  await missingEngine.close();
  report.cases.push('missing_engine_script');

  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(`WEB_BOOT_LOADER_OK ${JSON.stringify({ cases: report.cases, phases: report.real_boot.phases })}`);
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
