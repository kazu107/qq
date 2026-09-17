import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright')
  : require('playwright');
const app = createQqServer();
await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const output = resolve('tools/.local/web-visual');
await mkdir(output, { recursive: true });
const errors = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:/.test(message.text())) errors.push(message.text());
  });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForTimeout(20000);
  await page.screenshot({ path: resolve(output, 'hub.png') });
  const production = await page.evaluate(() => ({
    testBridgePresent: typeof window.qqCommand !== 'undefined',
    canvasCount: document.querySelectorAll('canvas').length,
    statusText: document.getElementById('status-notice')?.textContent || '',
  }));
  await writeFile(resolve(output, 'report.json'), JSON.stringify({ errors, ...production }, null, 2));
  if (errors.length || production.testBridgePresent || production.canvasCount !== 1) throw new Error(JSON.stringify({ errors, production }));
  console.log('WEB_VISUAL_REVIEW_CAPTURED', production);
} finally {
  await browser.close();
  await new Promise(resolve => app.server.close(resolve));
}
