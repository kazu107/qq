import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

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
    assert.equal(await page.title(), 'QueueQuest');
    assert.equal(await page.locator('#status-logo-svg').evaluate(svg => svg.namespaceURI), 'http://www.w3.org/2000/svg');
    assert.equal(await page.locator('#status-logo-svg title').textContent(), 'QueueQuest');
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
    const contentHash = await page.evaluate(() => window.qqLoadMetrics.find(item => item.event === 'boot_ready').details.network_hash);
    if (process.env.QQ_EXPECTED_CONTENT_HASH) assert.equal(contentHash, process.env.QQ_EXPECTED_CONTENT_HASH);
    assert(!evidence.replaced && !evidence.removedBeforeHub, 'Loading screen was replaced or removed before the Hub');
    for (const phase of ['download', 'initializing', 'preparing', 'ready']) {
      assert(evidence.phases.includes(phase), `Missing loading phase: ${phase}`);
    }
    assert(evidence.progress.at(-1) === 1, 'Loading did not reach completion');
    assert(evidence.progress.every((value, index, values) => index === 0 || value >= values[index - 1]), 'Loading bar went backwards');
    assert.deepEqual(errors, []);
    report.real_boot = { ...evidence, content_hash: contentHash, appearance: preparingAppearance, fade_opacity: fadeOpacity };
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

async function reviewLogoMotion() {
  const page = await mockPage(undefined, { viewport: { width: 960, height: 600 } });
  await page.waitForFunction(() => window.mockEngineStarted);
  const intro = await page.evaluate(() => {
    const cards = ['back', 'middle', 'front'].map(part => document.getElementById(`logo-card-${part}`));
    return cards.map(card => {
      const animation = card.getAnimations()[0];
      const timing = animation.effect.getTiming();
      animation.pause();
      animation.currentTime = 180;
      return { name: animation.animationName, duration: timing.duration, delay: timing.delay };
    });
  });
  assert.deepEqual(intro.map(animation => animation.delay), [0, 120, 240]);
  assert(intro.every(animation => animation.name === 'logo-card-enter' && animation.duration === 360));
  await page.screenshot({ path: resolve(output, 'logo-enter.png') });
  const movement = await page.evaluate(() => {
    for (const card of document.querySelectorAll('#status-logo-svg [id^="logo-card-"]')) {
      const animation = card.getAnimations()[0];
      animation.currentTime = 600;
    }
    const light = document.getElementById('logo-timeline-light');
    const animation = light.getAnimations()[0];
    animation.pause();
    animation.currentTime = 1100;
    const firstX = new DOMMatrixReadOnly(getComputedStyle(light).transform).m41;
    animation.currentTime = 2100;
    const secondX = new DOMMatrixReadOnly(getComputedStyle(light).transform).m41;
    return { firstX, secondX, duration: animation.effect.getTiming().duration,
      wordAnimations: [...document.querySelectorAll('#logo-word-queue, #logo-word-quest')]
        .flatMap(word => word.getAnimations({ subtree: true })).length };
  });
  assert(Math.abs(movement.firstX + 46) < 0.1 && Math.abs(movement.secondX + 138) < 0.1, 'The timeline light did not move uniformly right to left');
  assert.equal(movement.duration, 2000);
  assert.equal(movement.wordAnimations, 0, 'Logo lettering must remain stationary');
  await page.screenshot({ path: resolve(output, 'logo-waiting.png') });
  await page.evaluate(() => window.qqBootLoader.finish());
  const completion = await page.evaluate(() => {
    const front = document.getElementById('logo-card-front');
    const animation = front.getAnimations()[0];
    animation.pause();
    animation.currentTime = 180;
    const frame = front.querySelector('rect');
    const glow = frame.getAnimations()[0];
    glow.pause();
    glow.currentTime = 180;
    return { name: animation.animationName, y: new DOMMatrixReadOnly(getComputedStyle(front).transform).m42,
      stroke: getComputedStyle(frame).stroke, lightAnimations: document.getElementById('logo-timeline-light').getAnimations().length };
  });
  assert.equal(completion.name, 'logo-card-resolve');
  assert.equal(completion.y, -6);
  assert.equal(completion.stroke, 'rgb(255, 240, 190)');
  assert.equal(completion.lightAnimations, 0);
  await page.screenshot({ path: resolve(output, 'logo-resolve.png') });
  await page.waitForSelector('#status', { state: 'detached' });
  await page.close();
  report.logo_motion = { intro, movement, completion };
  report.cases.push('logo_entry_loop_completion');

  const fast = await mockPage();
  await fast.evaluate(() => window.qqBootLoader.finish());
  assert.equal(await fast.locator('#logo-card-middle').evaluate(card => getComputedStyle(card).opacity), '1');
  assert.equal(await fast.locator('#logo-card-front').evaluate(card => card.getAnimations()[0].animationName), 'logo-card-resolve');
  await fast.waitForSelector('#status', { state: 'detached' });
  await fast.close();
  report.cases.push('fast_completion_interrupts_entry');
}

async function createLogoPreview() {
  const hubImage = (await readFile(resolve(output, 'hub.png'))).toString('base64');
  const page = await mockPage(`
    window.mockEngineStarted = true;
    const canvas = document.getElementById('canvas');
    canvas.style.width = '100vw';
    canvas.style.height = '100vh';
    canvas.style.background = 'center / cover url(data:image/png;base64,${hubImage})';
  `, { viewport: { width: 960, height: 600 }, recordVideo: { dir: output, size: { width: 960, height: 600 } } });
  const video = page.video();
  await page.waitForFunction(() => window.mockEngineStarted);
  await page.evaluate(() => window.qqBootLoader.update('画像・音声・画面を準備中...', 0.5));
  await page.waitForTimeout(2900);
  await page.evaluate(() => window.qqBootLoader.finish());
  await page.waitForSelector('#status', { state: 'detached' });
  await page.close();
  await video.saveAs(resolve(output, 'logo-animation-preview.webm'));
}

try {
  await reviewLogoMotion();
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
  assert.equal(await reduced.locator('#status-logo-svg').evaluate(svg => svg.getAnimations({ subtree: true }).length), 0, 'Reduced motion did not stop the SVG animation');
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
  assert.equal(await failure.locator('#status-logo-svg').evaluate(svg => svg.getAnimations({ subtree: true }).length), 0, 'The logo kept animating after startup failure');
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

  await createLogoPreview();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(`WEB_BOOT_LOADER_OK ${JSON.stringify({ cases: report.cases, phases: report.real_boot.phases })}`);
} finally {
  await browser.close();
  await new Promise(done => app.server.close(done));
}
