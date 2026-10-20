// Рендер баннера: Chromium (Playwright) снимает index.html в PNG.
//   node render.mjs            — out/uwed-ozbek-tili-1920x1080.png и out/uwed-ozbek-tili-3840x2160.png
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); }
catch { ({ chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'))); }

const dir = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(dir, 'out');
mkdirSync(out, { recursive: true });

const browser = await chromium.launch({ args: ['--allow-file-access-from-files', '--force-color-profile=srgb', '--font-render-hinting=none'] });
for (const scale of [1, 2]) {
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: scale });
  page.on('pageerror', e => console.error('page error:', e.message));
  await page.goto(pathToFileURL(path.join(dir, 'index.html')).href);
  await page.evaluate(() => document.fonts.ready);
  const file = path.join(out, `uwed-ozbek-tili-${1920 * scale}x${1080 * scale}.png`);
  await page.screenshot({ path: file, type: 'png' });
  console.log(file);
  await page.close();
}
await browser.close();
