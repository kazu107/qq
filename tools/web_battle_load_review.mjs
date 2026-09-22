import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { mkdir } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { createQqServer } = require('../server/server.js');
const { chromium } = process.env.QQ_NODE_MODULES
  ? createRequire(resolve(process.env.QQ_NODE_MODULES, '../package.json'))('playwright')
  : require('playwright');
const app = createQqServer();
await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const output = resolve('tools/.local/web-battle-load');
await mkdir(output, { recursive: true });
const errors = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
  });
  await page.goto(`http://127.0.0.1:${app.server.address().port}/?pack=local`);
  await page.waitForTimeout(17000);
  await page.mouse.click(720, 498);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: resolve(output, 'tutorial-list.png') });
  await page.mouse.click(1290, 264);
  await page.waitForTimeout(4500);
  await page.screenshot({ path: resolve(output, 'first-battle.png') });
  await page.mouse.click(1360, 74);
  await page.waitForTimeout(1600);
  await page.screenshot({ path: resolve(output, 'returned-list.png') });
  await page.mouse.click(1290, 264);
  await page.waitForTimeout(2800);
  await page.screenshot({ path: resolve(output, 'second-battle.png') });
  if (errors.length) throw new Error(JSON.stringify(errors));
  console.log('WEB_BATTLE_LOAD_REVIEW_OK first and second battle rendered without errors');
} finally {
  await browser.close();
  await new Promise(resolve => app.server.close(resolve));
}
