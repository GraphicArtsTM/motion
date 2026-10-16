// Рендер ролика: Chromium (Playwright) рисует каждый кадр index.html, ffmpeg собирает видео.
//   node render.mjs                         — полный рендер в out/frames.mp4 (без звука)
//   node render.mjs --stills 1.2,4.5,9      — стоп-кадры в out/stills/*.png для проверки
//   node render.mjs --fps 30 --from 8 --to 12
import { createRequire } from 'node:module';
import { spawn, execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); }
catch { ({ chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'))); }

const dir = path.dirname(fileURLToPath(import.meta.url));
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const fps = +arg('fps', 60);
const out = path.join(dir, 'out');
mkdirSync(out, { recursive: true });

const browser = await chromium.launch({ args: ['--allow-file-access-from-files', '--disable-gpu-vsync', '--force-color-profile=srgb', '--font-render-hinting=none'] });
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
page.on('pageerror', e => console.error('page error:', e.message));
page.on('console', m => { if (m.type() === 'error') console.error('console:', m.text()); });
await page.goto(pathToFileURL(path.join(dir, 'index.html')).href);
await page.evaluate(() => window.ready);
const DUR = await page.evaluate(() => window.DURATION);

const stills = arg('stills');
if (stills) {
  mkdirSync(path.join(out, 'stills'), { recursive: true });
  for (const s of stills.split(',')) {
    const t = +s;
    await page.evaluate(([t, f]) => window.renderAt(t, f), [t, Math.round(t * fps)]);
    const file = path.join(out, 'stills', 't' + t.toFixed(2).padStart(5, '0') + '.png');
    await page.screenshot({ path: file, type: 'png' });
    console.log(file);
  }
  await browser.close();
  process.exit(0);
}

const from = +arg('from', 0), to = +arg('to', DUR);
const file = arg('out', path.join(out, 'frames.mp4'));
const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-r', String(fps), '-movflags', '+faststart', file],
  { stdio: ['pipe', 'inherit', 'inherit'] });
const cdp = await page.context().newCDPSession(page);
const n = Math.round((to - from) * fps);
const t0 = Date.now();
for (let i = 0; i < n; i++) {
  const t = from + i / fps;
  await page.evaluate(([t, f]) => window.renderAt(t, f), [t, Math.round(t * fps)]);
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 96, optimizeForSpeed: false });
  if (!ff.stdin.write(Buffer.from(data, 'base64'))) await new Promise(r => ff.stdin.once('drain', r));
  if (i % fps === 0) process.stdout.write(`\r${(t).toFixed(1)}s / ${to}s  (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close();
console.log('\nготово:', file);
