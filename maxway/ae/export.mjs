// Экспорт ролика в проект After Effects.
// Chromium (Playwright) проигрывает index.html кадр за кадром, recorder.js записывает движение каждого элемента,
// здесь ключи прореживаются (Рамер–Дуглас–Пекер), элементы снимаются в PNG, и собирается скрипт
// MAXWAY_KLABJON_AE/build_maxway_klabjon.jsx, который строит проект в AE 2025.
//   node ae/export.mjs
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync, readFileSync, copyFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); }
catch { ({ chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'))); }

const here = path.dirname(fileURLToPath(import.meta.url));
const proj = path.join(here, '..');
const OUT = path.join(here, 'MAXWAY_KLABJON_AE');
const FPS = 60, NF = 30 * FPS;
rmSync(OUT, { recursive: true, force: true });
for (const d of ['footage', 'fonts', 'audio']) mkdirSync(path.join(OUT, d), { recursive: true });

const browser = await chromium.launch({ args: ['--allow-file-access-from-files', '--force-color-profile=srgb', '--font-render-hinting=none'] });
async function openPage() {
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 2 });
  page.on('pageerror', e => console.error('page error:', e.message));
  await page.goto(pathToFileURL(path.join(proj, 'index.html')).href);
  await page.evaluate(() => window.ready);
  await page.addScriptTag({ path: path.join(here, 'recorder.js') });
  return page;
}

/* ---------- 1. запись движения ---------- */
let page = await openPage();
const COMPS = await page.evaluate(() => window.__ae.COMPS);
const PREP = await page.evaluate(() => window.__ae.prep());
const SPECS = await page.evaluate(() => window.__ae.specs());
const REC = {};       // id → массив сэмплов по кадрам (undefined вне окна)
const CAM = [];
const t0 = Date.now();
for (let f = 0; f < NF; f++) {
  const r = await page.evaluate(([t, f]) => window.__ae.frame(t, f), [f / FPS, f]);
  for (const k in r) { if (k === 'cam') continue; (REC[k] = REC[k] || [])[f] = r[k]; }
  CAM[f] = r.cam;
  if (f % 300 === 0) process.stdout.write(`\rзапись ${(f / FPS).toFixed(0)} с (${((Date.now() - t0) / 1000).toFixed(0)} с)`);
}
console.log('\nзапись готова');
await page.close();

/* ---------- 2. прореживание ключей ---------- */
// samples: [[t, [v...]]], tol: допуск на компоненту. Возвращает индексы опорных точек.
function rdp(samples, tol) {
  const n = samples.length;
  if (n <= 2) return samples.map((_, i) => i);
  const keep = new Uint8Array(n); keep[0] = keep[n - 1] = 1;
  const stack = [[0, n - 1]];
  while (stack.length) {
    const [a, b] = stack.pop();
    let worst = -1, wi = -1;
    const [ta, va] = samples[a], [tb, vb] = samples[b];
    for (let i = a + 1; i < b; i++) {
      const [ti, vi] = samples[i], k = (ti - ta) / (tb - ta);
      let e = 0;
      for (let c = 0; c < vi.length; c++) e = Math.max(e, Math.abs(vi[c] - (va[c] + (vb[c] - va[c]) * k)) / tol[c]);
      if (e > worst) { worst = e; wi = i; }
    }
    if (worst > 1) { keep[wi] = 1; stack.push([a, wi], [wi, b]); }
  }
  const out = []; for (let i = 0; i < n; i++) if (keep[i]) out.push(i);
  return out;
}
const R3 = x => Math.round(x * 1000) / 1000;
// трек: постоянное значение или {t:[], v:[]}
function track(frames, get, tol, tOff) {
  const s = frames.map(f => [f / FPS - tOff, [].concat(get(f))]);
  const same = s.every(x => x[1].every((v, c) => Math.abs(v - s[0][1][c]) <= tol[c] * .25));
  const val = v => v.length === 1 ? R3(v[0]) : v.map(R3);
  if (same) return val(s[0][1]);
  const idx = rdp(s, tol);
  return { t: idx.map(i => R3(s[i][0])), v: idx.map(i => val(s[i][1])) };
}

/* ---------- 3. сборка описаний слоёв ---------- */
const CAPS = [];         // заявки на PNG: {id, variant, file, dsf}
const LAYERS = {};       // comp → [слои снизу вверх]
const LBL = { text: 8, png: 5, img: 6, shape: 2, solid: 1, comp: 10, line: 2, route: 2 };
const translit = s => s.toLowerCase().replace(/[а-яё]/g, c => ({ а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'e', ж: 'zh', з: 'z', и: 'i', й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'h', ц: 'c', ч: 'ch', ш: 'sh', щ: 'sch', ъ: '', ы: 'y', ь: '', э: 'e', ю: 'yu', я: 'ya' })[c] || c)
  .replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 40);
const push = (c, l) => (LAYERS[c] = LAYERS[c] || []).push(l);

for (const s of SPECS) {
  const C = COMPS[s.comp], u = C.u, cs = C.start;
  const rec = REC[s.id] || [];
  const prep = PREP[s.id] || {};
  const lbl = LBL[s.kind];

  if (s.kind === 'bgsolids') {
    let seg = null;
    const segs = [];
    for (let f = 0; f < NF; f++) { const c = rec[f].color; if (!seg || seg.c !== c) { seg = { c, a: f, b: f }; segs.push(seg); } seg.b = f; }
    segs.forEach((g, i) => {
      const m = g.c.match(/[\d.]+/g).map(Number);
      push('MAIN', { c: 'MAIN', k: 'solid', n: 'Фон ' + (i + 1), solid: { color: m.slice(0, 3).map(v => R3(v / 255)), w: 1080, h: 1920 },
        in: R3(g.a / FPS), out: R3((g.b + 1) / FPS), an: [540, 960], tr: { x: 540, y: 960, s: [100, 100], r: 0, o: 100 }, lbl: 1 });
    });
    continue;
  }
  if (s.kind === 'adj') {
    push('MAIN', { c: 'MAIN', k: 'adj', n: s.name, in: 0, out: 30, an: [540, 960], tr: { x: 540, y: 960, s: [100, 100], r: 0, o: 100 }, lbl: 1 });
    continue;
  }
  if (s.kind === 'comp' && !s.hasEl) {   // сцены: прекомп во весь кадр под камерой
    const ch = COMPS[s.src];
    push('MAIN', { c: 'MAIN', k: 'comp', n: ch.name, src: s.src, st: ch.start, in: ch.start, out: ch.start + ch.dur, cam: 1,
      an: [540, 960], tr: { x: 0, y: 0, s: [100, 100], r: 0, o: 100 }, lbl });
    continue;
  }

  const frames = [];
  for (let f = 0; f < NF; f++) if (rec[f]) frames.push(f);
  if (!frames.length) { console.warn('нет кадров для', s.name); continue; }

  // сегменты: по тексту/цвету для split, иначе один
  let segs = [];
  if (s.split) {
    let g = null;
    for (const f of frames) { const key = s.split === 'text' ? rec[f].text : rec[f].key; if (!g || g.key !== key) { g = { key, fr: [] }; segs.push(g); } g.fr.push(f); }
  } else segs = [{ key: null, fr: frames }];

  segs.forEach((g, si) => {
    // обрезаем по видимости
    const vis = g.fr.filter(f => (rec[f].o == null ? 1 : rec[f].o) > .001);
    if (!vis.length) return;
    const a = vis[0], b = vis[vis.length - 1];
    const fr = g.fr.filter(f => f >= a && f <= b);
    const tOff = cs;
    const name = s.name + (s.split === 'text' ? ' · ' + g.key : s.split === 'bg' ? ' · ' + (si + 1) : '');
    const L = { c: s.comp, k: s.kind, n: name, in: R3(a / FPS - tOff), out: R3((b + 1) / FPS - tOff), lbl };
    if (s.cam) L.cam = 1;
    const ox = s.cam ? 540 : 0, oy = s.cam ? 960 : 0;

    // базовый масштаб и опорная точка
    let k = 100, lpx = u;
    if (s.kind === 'png') {
      const dsf = s.dsf || 2;
      const file = s.dedupe ? `${s.dedupe}_${translit(g.key)}.png` : `${String(s.id).padStart(3, '0')}_${s.comp.toLowerCase()}_${translit(name)}.png`;
      const variant = s.split === 'text' ? { text: g.key, filter: g.key === 'ДВА' ? 'url(#olY)' : 'url(#ol)' } : null;
      const have = CAPS.find(c => c.file === file);
      if (have) have.layers.push(L); else CAPS.push({ id: s.id, variant, file, dsf, layers: [L] });
      L.src = 'footage/' + file; k = u / dsf * 100; lpx = dsf;
    } else if (s.kind === 'img') {
      const file = path.basename(s.src);
      L.src = 'footage/' + file;
      const cssW = prep.rest.w;
      k = u * cssW / s.nat[0] * 100; lpx = s.nat[0] / cssW;
      L.an = [s.nat[0] / 2, s.nat[1] / 2];
      if (!CAPS.find(c => c.copy === file)) CAPS.push({ copy: file, from: path.join(proj, s.src) });
    } else if (s.kind === 'text') {
      const T = prep;
      const col0 = (rec[fr[0]].color || T.color);
      L.text = { str: s.split === 'text' ? g.key : T.str, font: T.font, size: R3(T.size * u), tracking: T.tracking, just: T.just,
        leading: T.leading ? R3(T.leading * u) : null, color: col0.slice(0, 3).map(v => R3(v / 255)),
        ranges: T.ranges.map(r => [r[0], r[1], r[2].slice(0, 3).map(v => R3(v / 255))]) };
      if (T.shadow) L.sh = { color: T.shadow.color.map(v => R3(v / 255)), alpha: T.shadow.alpha, dist: R3(T.shadow.dist * u), soft: T.shadow.soft * u, dir: 180 };
      L.an = T.anchor.map(v => R3(v * u));
      if (s.dyn) {
        const keys = [];
        let prev = '';
        for (const f of fr) {
          const r = rec[f], col = (r.color || T.color).slice(0, 3);
          const id = r.text + '|' + col.join();
          if (id !== prev) { keys.push([R3(f / FPS - tOff), r.text, col.map(v => R3(v / 255))]); prev = id; }
        }
        L.text.dyn = keys;
        L.text.str = keys[0][1]; L.text.color = keys[0][2];
      }
    } else if (s.kind === 'solid') {
      const w = (s.size ? s.size[0] : prep.rest.w) * u, h = (s.size ? s.size[1] : prep.rest.h) * u;
      const col = s.split === 'bg' ? g.key.match(/[\d.]+/g).map(Number).slice(0, 3) : s.color || [255, 255, 255];
      L.solid = { color: col.map(v => R3(v / 255)), w: Math.round(w), h: Math.round(h) };
      L.an = [Math.round(w) / 2, Math.round(h) / 2];
    } else if (s.kind === 'shape') {
      const sh = JSON.parse(JSON.stringify(s.shape));
      sh.size = sh.size.map(v => v * u);
      if (sh.round) sh.round *= u;
      if (sh.stroke) sh.stroke.w *= u;
      ['fill'].forEach(kk => { if (sh[kk]) sh[kk] = sh[kk].slice(0, 3).map(v => R3(v / 255)); });
      if (sh.stroke) sh.stroke.color = sh.stroke.color.slice(0, 3).map(v => R3(v / 255));
      if (s.special === 'strike') sh.size = track(fr, f => [rec[f].w * u, 34 * u], [.5, .5], tOff);
      if (s.special === 'dot') sh.size = track(fr, f => [rec[f].d * u, rec[f].d * u], [.3, .3], tOff);
      L.shape = sh; L.an = [0, 0];
    } else if (s.kind === 'comp') {
      const ch = COMPS[s.src];
      L.src = s.src; L.st = R3(ch.start - cs);
      k = u / ch.u * 100; lpx = ch.u;
      L.an = [ch.w / 2, ch.h / 2];
      if (s.threeD) L.d3 = 1;
    } else if (s.kind === 'line') {
      L.k = 'shape'; L.an = [0, 0];
      L.shape = { type: 'path', path: track(fr, f => rec[f].p.map(v => v * u), [.4, .4, .4, .4], tOff), closed: false,
        stroke: { color: [1, 1, 1], w: 4 * u, cap: 2 } };
      L.tr = { x: 0, y: 0, s: [100, 100], r: 0, o: track(fr, f => rec[f].o * 100, [.5], tOff) };
    } else if (s.kind === 'route') {
      L.k = 'shape'; L.an = [0, 0];
      const pts = [];
      let x = 0, y = 0;
      for (const m of prep.d.matchAll(/([MHV])\s*([-\d.]+)(?:\s+([-\d.]+))?/g)) {
        if (m[1] === 'M') { x = +m[2]; y = +m[3]; } else if (m[1] === 'H') x = +m[2]; else y = +m[2];
        pts.push([x * u, y * u]);
      }
      L.shape = { type: 'path', path: pts.flat(), closed: false, stroke: { color: s.stroke.color.slice(0, 3).map(v => R3(v / 255)), w: s.stroke.w * u, cap: 2, join: 2 },
        trim: track(fr, f => rec[f].trim, [.2], tOff) };
      L.tr = { x: 0, y: 0, s: [100, 100], r: 0, o: 100 };
    }
    if (s.shadow) L.sh = { color: s.shadow.color.map(v => R3(v / 255)), alpha: s.shadow.alpha, dist: s.shadow.dist * (s.kind === 'comp' ? COMPS[s.src].u : 1), soft: s.shadow.soft * (s.kind === 'comp' ? COMPS[s.src].u : 1), dir: 180 };
    if (s.kind === 'png' && !L.an) L.an = null;   // заполняется после снимка

    // трансформ
    if (!L.tr) {
      const get = (f, key, d) => rec[f][key] == null ? d : rec[f][key];
      const tr = {
        x: track(fr, f => (get(f, 'x', 0) - ox) * u, [.35], tOff),
        y: track(fr, f => (get(f, 'y', 0) - oy) * u, [.35], tOff),
        s: track(fr, f => [get(f, 'sx', 1) * k, get(f, 'sy', 1) * k], [.12, .12], tOff),
        r: track(fr, f => get(f, 'r', 0), [.05], tOff),
        o: track(fr, f => get(f, 'o', 1) * 100, [.4], tOff),
      };
      const bl = track(fr, f => get(f, 'b', 0) * lpx * 2, [.3], tOff);
      if (bl !== 0) tr.b = bl;
      if (s.threeD) { tr.rx = track(fr, f => get(f, 'rx', 0), [.05], tOff); tr.ry = track(fr, f => get(f, 'ry', 0), [.05], tOff); }
      L.tr = tr;
    }
    if (s.special === 'line' || s.special === 'route') { /* трансформ задан выше */ }
    push(s.comp, L);
  });
}

// камера-нуль (покачивания и удары)
const camTr = {
  x: track([...Array(NF).keys()], f => 540 + CAM[f].x, [.3], 0),
  y: track([...Array(NF).keys()], f => 960 + CAM[f].y, [.3], 0),
  s: track([...Array(NF).keys()], f => [CAM[f].s * 100, CAM[f].s * 100], [.05, .05], 0),
  r: track([...Array(NF).keys()], f => CAM[f].r, [.03], 0),
};

/* ---------- 4. снимки PNG и копии ассетов ---------- */
page = await openPage();
await page.evaluate(() => window.__ae.prep());
let nCap = 0;
for (const c of CAPS) {
  if (c.copy) { copyFileSync(c.from, path.join(OUT, 'footage', c.copy)); continue; }
  const info = await page.evaluate(([id, v]) => window.__ae.capBegin(id, v), [c.id, c.variant]);
  const { clip } = info;
  await page.setViewportSize({ width: Math.max(1080, clip.x + clip.w + 10), height: Math.max(1920, clip.y + clip.h + 10) });
  await page.screenshot({ path: path.join(OUT, 'footage', c.file), clip: { x: clip.x, y: clip.y, width: clip.w, height: clip.h },
    omitBackground: true, scale: c.dsf === 1 ? 'css' : 'device' });
  await page.evaluate(() => window.__ae.capEnd());
  for (const l of c.layers) l.an = info.anchor.map(v => R3(v * c.dsf));
  nCap++;
}
await browser.close();
console.log('PNG:', nCap);

/* ---------- 5. шрифты, музыка, данные, скрипт ---------- */
for (const f of readdirSync(path.join(proj, 'fonts'))) copyFileSync(path.join(proj, 'fonts', f), path.join(OUT, 'fonts', f));
copyFileSync(path.join(proj, 'out', 'music.wav'), path.join(OUT, 'audio', 'music.wav'));

const ORDER = ['PHONE', 'MAP', 'TAPEA', 'TAPEB', 'TAPEN', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'MAIN'];
const DATA = {
  fps: FPS,
  comps: ORDER.map(id => ({ id, name: COMPS[id].name, w: COMPS[id].w, h: COMPS[id].h, dur: COMPS[id].dur, bg: COMPS[id].bg ? COMPS[id].bg.map(v => R3(v / 255)) : [0, 0, 0] })),
  layers: ORDER.flatMap(id => LAYERS[id] || []),
  cam: camTr,
  audio: 'audio/music.wav',
  camera: { poi: [540, 864], z: -2400, zoom: 2400 },
};
writeFileSync(path.join(here, 'data.json'), JSON.stringify(DATA));
const tpl = readFileSync(path.join(here, 'builder.jsx'), 'utf8');
const jsx = '﻿' + tpl.replace('/*__DATA__*/null', JSON.stringify(DATA));
writeFileSync(path.join(OUT, 'build_maxway_klabjon.jsx'), jsx);
copyFileSync(path.join(here, 'README_AE.txt'), path.join(OUT, 'README.txt'));
let nk = 0;
for (const l of DATA.layers) for (const k in l.tr || {}) if (l.tr[k] && l.tr[k].t) nk += l.tr[k].t.length;
console.log('слоёв:', DATA.layers.length, ' ключей трансформа:', nk, ' размер скрипта:', (jsx.length / 1e6).toFixed(2), 'МБ');
