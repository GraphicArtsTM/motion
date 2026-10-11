// Рендер серии: headless Chromium (Playwright) рисует каждый кадр index.html через WebGL, ffmpeg собирает видео.
//   node render.mjs                          — полный рендер в out/frames.mp4 (без звука)
//   node render.mjs --stills 3,41.5,120      — стоп-кадры в out/stills/*.png для проверки
//   node render.mjs --fps 30 --from 40 --to 60 --out out/part.mp4
//   node render.mjs --page test.html         — другой файл (для отладки)
import { createRequire } from 'node:module';
import { spawn, execSync } from 'node:child_process';
import { mkdirSync, readFileSync, existsSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); }
catch { ({ chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'))); }

const dir = path.dirname(fileURLToPath(import.meta.url));
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const fps = +arg('fps', 24);
const W = +arg('w', 1920), H = +arg('h', 1080);
const out = path.join(dir, 'out');
mkdirSync(out, { recursive: true });

// крошечный статический сервер: ES-модули и importmap не работают с file://
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.css': 'text/css', '.png': 'image/png', '.ttf': 'font/ttf', '.wav': 'audio/wav', '.mp3': 'audio/mpeg' };
const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(dir) || !existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': MIME[path.extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}/`;

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
  '--force-color-profile=srgb', '--font-render-hinting=none'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
page.on('pageerror', e => console.error('page error:', e.message));
page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') console.error('console:', m.text()); });
await page.goto(base + arg('page', 'index.html') + '?render=1' + arg('q', ''));
await page.waitForFunction(() => window.ready === true, null, { timeout: 120000 });
const DUR = await page.evaluate(() => window.DURATION);

if (arg('bench')) { for (const t of arg('bench').split(',')) console.log('bench', t, (await page.evaluate(t => window.bench(+t), +t)).toFixed(0) + 'ms'); await browser.close(); server.close(); process.exit(0); }
const stills = arg('stills');
if (stills) {
  mkdirSync(path.join(out, 'stills'), { recursive: true });
  for (const s of stills.split(',')) {
    const t = +s;
    const t0 = Date.now();
    await page.evaluate(t => window.renderAt(t), t);
    const file = path.join(out, 'stills', 't' + t.toFixed(2).padStart(6, '0') + '.png');
    await page.screenshot({ path: file, type: 'png' });
    console.log(file, (Date.now() - t0) + 'ms');
  }
  await browser.close(); server.close();
  process.exit(0);
}

const from = +arg('from', 0), to = +arg('to', DUR);
const file = arg('out', path.join(out, 'frames.mp4'));
const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '14', '-pix_fmt', 'yuv420p', '-r', String(fps), '-movflags', '+faststart', file],
  { stdio: ['pipe', 'inherit', 'inherit'] });
const cdp = await page.context().newCDPSession(page);
const n = Math.round((to - from) * fps);
const t0 = Date.now();
for (let i = 0; i < n; i++) {
  const t = from + i / fps;
  await page.evaluate(t => window.renderAt(t), t);
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 95, optimizeForSpeed: false });
  if (!ff.stdin.write(Buffer.from(data, 'base64'))) await new Promise(r => ff.stdin.once('drain', r));
  if (i % fps === 0) {
    const el = (Date.now() - t0) / 1000, eta = i ? el / i * (n - i) : 0;
    process.stdout.write(`\r${t.toFixed(1)}s / ${to}s   прошло ${el.toFixed(0)}s, осталось ~${eta.toFixed(0)}s   `);
  }
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close(); server.close();
console.log('\nготово:', file);
