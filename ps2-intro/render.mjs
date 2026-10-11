// Рендер интро: браузер (Chrome / Edge / Chromium через Playwright) рисует каждый кадр index.html,
// ffmpeg собирает видео вместе со звуком audio/soundtrack.wav.
//   node render.mjs                      — Director's Cut, 1920×1080, 60 fps → out/
//   node render.mjs --version remake     — ремейк, близкий к оригиналу
//   node render.mjs --scale 2            — 4K (3840×2160)
//   node render.mjs --fps 30             — 30 кадров/с (вдвое быстрее)
//   node render.mjs --fast               — кадры в JPEG вместо PNG (быстрее, чуть хуже градиенты)
//   node render.mjs --stills 2,9,15      — стоп-кадры в out/stills/
//   node render.mjs --preview            — открыть превью со звуком в браузере
import { createRequire } from 'node:module';
import { spawn, execSync } from 'node:child_process';
import { mkdirSync, existsSync, createReadStream, statSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const dir = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const has = k => argv.includes('--' + k);
const arg = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : d; };

/* ---------- локальный сервер (ES-модули не грузятся с file://) ---------- */
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2', '.wav': 'audio/wav', '.png': 'image/png', '.json': 'application/json', '.css': 'text/css' };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const file = path.join(dir, url === '/' ? 'index.html' : url);
  if (!file.startsWith(dir) || !existsSync(file) || statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  const size = statSync(file).size, type = MIME[path.extname(file)] || 'application/octet-stream';
  const range = req.headers.range && /bytes=(\d*)-(\d*)/.exec(req.headers.range);
  if (range) {
    const a = range[1] ? +range[1] : 0, b = range[2] ? +range[2] : size - 1;
    res.writeHead(206, { 'Content-Type': type, 'Content-Range': `bytes ${a}-${b}/${size}`, 'Accept-Ranges': 'bytes', 'Content-Length': b - a + 1 });
    createReadStream(file, { start: a, end: b }).pipe(res);
  } else {
    res.writeHead(200, { 'Content-Type': type, 'Content-Length': size, 'Accept-Ranges': 'bytes' });
    createReadStream(file).pipe(res);
  }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}/`;

if (has('preview')) {
  const url = base + '?v=' + (arg('version', 'pro') === 'remake' ? 'remake' : 'pro');
  const cmd = process.platform === 'win32' ? `start "" "${url}"` : process.platform === 'darwin' ? `open "${url}"` : `xdg-open "${url}"`;
  execSync(cmd);
  console.log('Превью открыто: ' + url + '\nКликните по странице, чтобы запустить со звуком. Закройте это окно, чтобы остановить сервер.');
  await new Promise(() => {});
}

/* ---------- ffmpeg ---------- */
let ffmpeg = 'ffmpeg';
try { const p = require('ffmpeg-static'); if (p && existsSync(p)) ffmpeg = p; } catch {}

/* ---------- браузер ---------- */
let chromium;
try { ({ chromium } = require('playwright')); }
catch { ({ chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'))); }

const gpuArgs = ['--ignore-gpu-blocklist', '--enable-gpu', '--enable-gpu-rasterization', '--enable-zero-copy',
  '--disable-gpu-vsync', '--disable-frame-rate-limit', '--force-color-profile=srgb', '--font-render-hinting=none',
  '--autoplay-policy=no-user-gesture-required', '--disable-background-timer-throttling', '--disable-renderer-backgrounding'];
if (process.platform === 'win32') gpuArgs.push('--use-angle=d3d11');
else if (process.platform === 'darwin') gpuArgs.push('--use-angle=metal');
else gpuArgs.push('--use-angle=gl');

async function launch(headless) {
  const tries = [{ channel: 'chrome' }, { channel: 'msedge' }, {}];
  const forced = arg('browser');
  const list = forced ? [{ channel: forced === 'chromium' ? undefined : forced }] : tries;
  const args = headless ? gpuArgs : [...gpuArgs, '--window-position=0,0', '--window-size=1000,620'];
  for (const o of list) {
    try { const b = await chromium.launch({ ...o, headless, args }); return [b, o.channel || 'chromium']; } catch {}
  }
  console.log('Chrome/Edge не найдены — скачиваю Chromium для Playwright (один раз)...');
  execSync('npx playwright install chromium', { stdio: 'inherit', cwd: dir });
  return [await chromium.launch({ headless, args }), 'chromium'];
}
const isSoft = g => /swiftshader|llvmpipe|software|basic render/i.test(g);

const scale = +arg('scale', 1), fps = +arg('fps', 60), fast = has('fast');
const version = arg('version', 'pro') === 'remake' ? 'remake' : 'pro';
const out = path.join(dir, 'out');
mkdirSync(out, { recursive: true });

async function open(headless) {
  const [browser, which] = await launch(headless);
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: scale });
  await page.addInitScript(() => { window.__RENDER__ = true; });
  page.on('pageerror', e => console.error('ошибка страницы:', e.message));
  page.on('console', m => { if (m.type() === 'error' && !/404/.test(m.text())) console.error('console:', m.text()); });
  await page.goto(base + 'index.html?q=' + scale + '&v=' + version + (arg('dbg') ? '&dbg=1' : ''));
  await page.evaluate(() => window.ready);
  return { browser, which, page, gpu: await page.evaluate(() => window.GPU) };
}
let { browser, which, page, gpu } = await open(!has('headed'));
if (isSoft(gpu) && !has('headed') && !has('cpu')) {
  /* в фоновом режиме браузер не взял видеокарту — пробуем с окном (так GPU включается почти всегда) */
  const alt = await open(false).catch(() => null);
  if (alt && !isSoft(alt.gpu)) { await browser.close(); ({ browser, which, page, gpu } = alt); console.log('Рендер в отдельном окне браузера (так быстрее) — не закрывайте его.'); }
  else if (alt) await alt.browser.close();
}
const DUR = await page.evaluate(() => window.DURATION);
console.log(`Версия: ${version === 'pro' ? "Director's Cut" : 'Remake'} | браузер: ${which} | видеокарта: ${gpu}`);
if (isSoft(gpu)) console.log('  (!) рендер идёт на процессоре — будет медленнее. Обновите драйвер видеокарты или установите Google Chrome.');

const cdp = await page.context().newCDPSession(page);
const shot = async () => (await cdp.send('Page.captureScreenshot', fast
  ? { format: 'jpeg', quality: 95, optimizeForSpeed: true }
  : { format: 'png', optimizeForSpeed: true })).data;

const stills = arg('stills');
if (stills) {
  mkdirSync(path.join(out, 'stills'), { recursive: true });
  for (const s of stills.split(',')) {
    const t = +s;
    await page.evaluate(([t, f]) => window.renderAt(t, f), [t, Math.round(t * fps)]);
    const file = path.join(out, 'stills', version + '_t' + t.toFixed(2).padStart(5, '0') + '.png');
    await page.screenshot({ path: file, type: 'png' });
    console.log(file);
  }
  await browser.close(); server.close(); process.exit(0);
}

const from = +arg('from', 0), to = +arg('to', DUR);
const res = scale >= 2 ? '4K' : scale >= 1.4 ? '1440p' : scale < 1 ? Math.round(1080 * scale) + 'p' : '1080p';
const name = version === 'pro' ? 'PS2_Intro_DirectorsCut' : 'PS2_Intro_Remake';
const file = arg('out', path.join(out, `${name}_${res}${fps}.mp4`));
const audio = path.join(dir, 'audio', version === 'pro' ? 'soundtrack_pro.wav' : 'soundtrack.wav');
const ffArgs = ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', fast ? 'mjpeg' : 'png', '-i', '-'];
if (existsSync(audio)) ffArgs.push('-ss', String(from), '-t', String(to - from), '-i', audio, '-map', '0:v', '-map', '1:a', '-c:a', 'aac', '-b:a', '320k', '-ar', '48000');
ffArgs.push('-c:v', 'libx264', '-preset', arg('preset', 'slow'), '-crf', arg('crf', '14'), '-pix_fmt', 'yuv420p',
  '-profile:v', 'high', '-tune', 'grain', '-r', String(fps), '-movflags', '+faststart', '-shortest', file);
const ff = spawn(ffmpeg, ffArgs, { stdio: ['pipe', 'inherit', 'inherit'] });
ff.on('error', e => { console.error('Не удалось запустить ffmpeg (' + ffmpeg + '):', e.message, '\nПереустановите библиотеки: удалите папку node_modules и запустите скрипт снова.'); process.exit(1); });

const n = Math.round((to - from) * fps), t0 = Date.now();
console.log(`Рендер ${n} кадров (${(1920 * scale) | 0}×${(1080 * scale) | 0}, ${fps} fps) → ${path.relative(dir, file)}`);
for (let i = 0; i < n; i++) {
  const t = from + i / fps;
  await page.evaluate(([t, f]) => window.renderAt(t, f), [t, Math.round(t * fps)]);
  const buf = Buffer.from(await shot(), 'base64');
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (i % 10 === 0 || i === n - 1) {
    const el = (Date.now() - t0) / 1000, eta = el / (i + 1) * (n - i - 1);
    const bar = '█'.repeat(Math.round((i + 1) / n * 30)).padEnd(30, '░');
    process.stdout.write(`\r  ${bar} ${String(Math.round((i + 1) / n * 100)).padStart(3)}%  кадр ${i + 1}/${n}  осталось ~${Math.ceil(eta)} с   `);
  }
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close(); server.close();
console.log(`\n\nГотово за ${((Date.now() - t0) / 60000).toFixed(1)} мин: ${file}`);
