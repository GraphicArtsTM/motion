// Рендер ЮЛДУЗ: Chromium (Playwright) рисует кадры index.html, ffmpeg собирает видео 1920×1080.
//   node render.mjs                          — полный рендер в out/frames.mp4 (без звука), параллельно в --jobs страницах
//   node render.mjs --stills 3.2,40,101.5    — стоп-кадры в out/stills/*.png
//   node render.mjs --cues                   — тайминги реплик и звуковых событий в out/cues.json (для audio.py)
//   node render.mjs --from 100 --to 110 --out out/part.mp4
import { createRequire } from 'node:module';
import { spawn, execSync } from 'node:child_process';
import { mkdirSync, writeFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); }
catch { ({ chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'))); }

const dir = path.dirname(fileURLToPath(import.meta.url));
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const has = k => process.argv.includes('--' + k);
const fps = +arg('fps', 24);
const out = path.join(dir, 'out');
mkdirSync(out, { recursive: true });
const W = 1920, H = 1080;

const browser = await chromium.launch({ args: ['--allow-file-access-from-files', '--force-color-profile=srgb', '--font-render-hinting=none'] });
async function openPage() {
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  page.on('pageerror', e => console.error('page error:', e.message));
  page.on('console', m => { if (m.type() === 'error') console.error('console:', m.text()); });
  await page.goto(pathToFileURL(path.join(dir, 'index.html')).href + '?t=0');
  await page.evaluate(() => window.ready);
  return page;
}

const page = await openPage();
const DUR = await page.evaluate(() => window.DURATION);

if (has('cues')) {
  const cues = await page.evaluate(() => window.CUES());
  writeFileSync(path.join(out, 'cues.json'), JSON.stringify({ duration: DUR, ...cues }, null, 1));
  console.log('out/cues.json', 'длительность', DUR);
  await browser.close();
  process.exit(0);
}

const stills = arg('stills');
if (stills) {
  mkdirSync(path.join(out, 'stills'), { recursive: true });
  for (const s of stills.split(',')) {
    const t = +s;
    await page.evaluate(t => window.renderAt(t), t);
    const file = path.join(out, 'stills', 't' + t.toFixed(2).padStart(6, '0') + '.png');
    await page.screenshot({ path: file, type: 'png' });
    console.log(file);
  }
  await browser.close();
  process.exit(0);
}

async function renderRange(pg, from, to, file, label) {
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '14', '-pix_fmt', 'yuv420p', '-r', String(fps), file],
    { stdio: ['pipe', 'inherit', 'inherit'] });
  const cdp = await pg.context().newCDPSession(pg);
  const f0 = Math.round(from * fps), f1 = Math.round(to * fps);
  const t0 = Date.now();
  for (let f = f0; f < f1; f++) {
    const t = f / fps;
    await pg.evaluate(t => window.renderAt(t), t);
    const { data } = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 95, optimizeForSpeed: false });
    if (!ff.stdin.write(Buffer.from(data, 'base64'))) await new Promise(r => ff.stdin.once('drain', r));
    if ((f - f0) % (fps * 5) === 0) console.log(`[${label}] ${t.toFixed(1)}s (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
}

const from = +arg('from', 0), to = +arg('to', DUR);
const file = arg('out', path.join(out, 'frames.mp4'));
const jobs = Math.max(1, +arg('jobs', 4));
if (jobs === 1) {
  await renderRange(page, from, to, file, 'all');
} else {
  const pages = [page];
  for (let i = 1; i < jobs; i++) pages.push(await openPage());
  const step = (to - from) / jobs;
  const parts = [];
  await Promise.all(pages.map((pg, i) => {
    const a = from + i * step, b = i === jobs - 1 ? to : from + (i + 1) * step;
    const fa = Math.round(a * fps) / fps, fb = Math.round(b * fps) / fps;
    const pf = path.join(out, `part${i}.mp4`);
    parts.push(pf);
    return renderRange(pg, fa, fb, pf, 'job' + i);
  }));
  const list = path.join(out, 'parts.txt');
  writeFileSync(list, parts.map(p => `file '${p}'`).join('\n'));
  execSync(`ffmpeg -y -loglevel error -f concat -safe 0 -i "${list}" -c copy "${file}"`);
  for (const p of parts) unlinkSync(p);
  unlinkSync(list);
}
await browser.close();
console.log('готово:', file);
