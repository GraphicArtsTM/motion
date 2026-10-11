// Сборка готового видео одной командой: кадры (на видеокарте, в несколько потоков) → склейка → звук → mp4.
//   node make-video.mjs                    — 1920×1080, 30 fps, высокое качество
//   node make-video.mjs --fps 24 --jobs 3  — другая частота кадров / число потоков
//   node make-video.mjs --fast             — быстрый режим (без сглаживания), для проверки
//   node make-video.mjs --from 100 --to 120 — только кусок (для проверки)
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const dir = path.dirname(fileURLToPath(import.meta.url));
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
let FFMPEG = 'ffmpeg';
try { FFMPEG = require('ffmpeg-static') || 'ffmpeg'; } catch { }

const fps = +arg('fps', 30);
const fast = process.argv.includes('--fast');
const timeline = JSON.parse(readFileSync(path.join(dir, 'timeline.json'), 'utf8'));
const from = +arg('from', 0), to = +arg('to', timeline.duration + (timeline.intro || 0));
const jobs = Math.max(1, +arg('jobs', Math.min(3, Math.max(1, Math.floor(os.cpus().length / 4)))));
const outDir = path.join(dir, 'out'), parts = path.join(outDir, 'parts');
rmSync(parts, { recursive: true, force: true }); mkdirSync(parts, { recursive: true });
const final = path.join(outDir, arg('out', 'PAUK_NOVOGRADA_S01E01_1920x1080.mp4'));

const run = (cmd, args, opts = {}) => new Promise((res, rej) => {
  const p = spawn(cmd, args, { stdio: opts.stdio || 'inherit', cwd: dir });
  if (opts.onLine) {
    let buf = '';
    p.stdout.on('data', d => { buf += d; let i; while ((i = buf.indexOf('\n')) >= 0) { opts.onLine(buf.slice(0, i)); buf = buf.slice(i + 1); } });
    p.stderr.on('data', d => process.stderr.write(d));
  }
  p.on('close', c => c === 0 ? res() : rej(new Error(`${path.basename(cmd)} завершился с кодом ${c}`)));
});

console.log(`\n🕷  ПАУК НОВОГРАДА — серия 1: рендер ${from}–${to} с, ${fps} fps, ${fast ? 'быстрое' : 'высокое'} качество, потоков: ${jobs}\n`);
const t0 = Date.now();
const total = Math.round((to - from) * fps);
const done = new Array(jobs).fill(0);
let gpuShown = false;
const show = () => {
  const d = done.reduce((a, b) => a + b, 0), k = d / total, el = (Date.now() - t0) / 1000;
  const eta = k > .01 ? el / k * (1 - k) : 0;
  const bar = '█'.repeat(Math.round(k * 30)).padEnd(30, '░');
  process.stdout.write(`\r  ${bar} ${(k * 100).toFixed(1)}%  кадр ${d}/${total}  прошло ${fmt(el)}  осталось ~${fmt(eta)}   `);
};
const fmt = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

const step = (to - from) / jobs;
await Promise.all(Array.from({ length: jobs }, (_, i) => {
  const a = Math.round((from + i * step) * fps) / fps, b = Math.round((from + (i + 1) * step) * fps) / fps;
  return run(process.execPath, ['render.mjs', '--gpu', '--progress', '--fps', String(fps), '--from', String(a), '--to', String(b),
    '--crf', '16', '--q', (fast ? '' : '&q=high') + '&fps=' + fps, '--out', path.join(parts, `p${i}.mp4`)], {
    stdio: ['ignore', 'pipe', 'pipe'],
    onLine: l => {
      if (l.startsWith('PROGRESS')) { done[i] = +l.split(' ')[1]; show(); }
      else if (l.startsWith('GPU') && !gpuShown) {
        gpuShown = true; console.log('  видеокарта: ' + l.slice(4));
        if (/swiftshader|llvmpipe|software/i.test(l)) console.log('  ⚠ видеокарта не используется — рендер будет медленным (обновите драйверы видеокарты)');
      }
    },
  });
}));
console.log('\n\n  склеиваю части и добавляю звук…');
writeFileSync(path.join(parts, 'list.txt'), Array.from({ length: jobs }, (_, i) => `file 'p${i}.mp4'`).join('\n'));
const sound = ['soundtrack.m4a', 'soundtrack.wav'].map(f => path.join(dir, 'assets', f)).find(existsSync);
await run(FFMPEG, ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', path.join(parts, 'list.txt'),
  ...(sound ? ['-ss', String(from), '-i', sound, '-map', '0:v', '-map', '1:a', '-c:a', 'aac', '-b:a', '256k', '-shortest'] : []),
  '-c:v', 'copy', '-movflags', '+faststart', final]);
console.log(`\n  ✅ готово за ${fmt((Date.now() - t0) / 1000)}: ${final}\n`);
