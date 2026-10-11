/* ЮЛДУЗ — базовая библиотека: математика, изинги, рандом, SVG-хелперы, эффекты.
   Всё детерминировано: кадр зависит только от времени t. */
'use strict';

const W = 1920, H = 1080, FPS = 24;
const clamp = (x, a = 0, b = 1) => x < a ? a : x > b ? b : x;
const lerp = (a, b, k) => a + (b - a) * k;
const P = (t, t0, d) => clamp((t - t0) / d);
const f2 = v => (Math.round(v * 100) / 100).toString();

const E = {
  lin: x => x,
  inQ: x => x * x,
  outQ: x => 1 - (1 - x) * (1 - x),
  inC: x => x * x * x,
  outC: x => 1 - Math.pow(1 - x, 3),
  io: x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2,
  ioS: x => -(Math.cos(Math.PI * x) - 1) / 2,
  outX: x => x >= 1 ? 1 : 1 - Math.pow(2, -10 * x),
  inX: x => x <= 0 ? 0 : Math.pow(2, 10 * x - 10),
  outB: x => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outEl: x => x <= 0 ? 0 : x >= 1 ? 1 : Math.pow(2, -10 * x) * Math.sin((x * 10 - .75) * (2 * Math.PI) / 3) + 1,
};
const tw = (t, t0, d, a, b, e = E.io) => lerp(a, b, e(P(t, t0, d)));
/* ключи: [[t, v], [t, v, ease], ...] */
function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, e] = keys[i], [t0, v0] = keys[i - 1];
    if (t <= t1) return lerp(v0, v1, (e || E.io)(P(t, t0, t1 - t0)));
  }
  return keys[keys.length - 1][1];
}

function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}
/* хэш-шум для дрожания и «рисованного» движения */
const hash = (n) => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };
function noise1(x) { const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f); return lerp(hash(i), hash(i + 1), u) * 2 - 1; }
/* аниме-движение «на двойках»: время квантуется до 12 кадров в секунду */
const on2 = t => Math.floor(t * 12) / 12;
const on3 = t => Math.floor(t * 8) / 8;

/* уникальные id внутри кадра */
let _uid = 0;
const uid = p => (p || 'u') + (_uid++);
function resetUid() { _uid = 0; }

/* ---------- SVG-хелперы ---------- */
const g = (inner, tr, extra) => `<g${tr ? ` transform="${tr}"` : ''}${extra ? ' ' + extra : ''}>${inner}</g>`;
const tr = (x, y, s = 1, r = 0, sy) => `translate(${f2(x)} ${f2(y)})${r ? ` rotate(${f2(r)})` : ''}${s !== 1 || sy != null ? ` scale(${f2(s)} ${f2(sy != null ? sy : s)})` : ''}`;
const path = (d, fill, extra) => `<path d="${d}" fill="${fill || 'none'}"${extra ? ' ' + extra : ''}/>`;
const strokeP = (d, color, w, extra) => `<path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"${extra ? ' ' + extra : ''}/>`;
const circle = (x, y, r, fill, extra) => `<circle cx="${f2(x)}" cy="${f2(y)}" r="${f2(r)}" fill="${fill}"${extra ? ' ' + extra : ''}/>`;
const ell = (x, y, rx, ry, fill, extra) => `<ellipse cx="${f2(x)}" cy="${f2(y)}" rx="${f2(rx)}" ry="${f2(ry)}" fill="${fill}"${extra ? ' ' + extra : ''}/>`;
const rect = (x, y, w, h, fill, extra) => `<rect x="${f2(x)}" y="${f2(y)}" width="${f2(w)}" height="${f2(h)}" fill="${fill}"${extra ? ' ' + extra : ''}/>`;
const poly = (pts, fill, extra) => `<polygon points="${pts.map(p => f2(p[0]) + ',' + f2(p[1])).join(' ')}" fill="${fill}"${extra ? ' ' + extra : ''}/>`;
const lg = (id, stops, x1 = 0, y1 = 0, x2 = 0, y2 = 1, extra = '') =>
  `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" ${extra}>${stops.map(([o, c, a]) => `<stop offset="${o}" stop-color="${c}"${a != null ? ` stop-opacity="${a}"` : ''}/>`).join('')}</linearGradient>`;
const rg = (id, stops, cx = .5, cy = .5, r = .5, extra = '') =>
  `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}" ${extra}>${stops.map(([o, c, a]) => `<stop offset="${o}" stop-color="${c}"${a != null ? ` stop-opacity="${a}"` : ''}/>`).join('')}</radialGradient>`;
const defs = s => `<defs>${s}</defs>`;
const svgWrap = (inner, extra = '') => `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" ${extra}>${inner}</svg>`;
const fullRect = (fill, extra) => rect(-400, -400, W + 800, H + 800, fill, extra);

/* гладкий замкнутый контур через точки (Catmull-Rom → Безье) */
function smoothPath(pts, closed = true, k = 1) {
  const n = pts.length;
  if (n < 2) return '';
  const P_ = i => closed ? pts[(i + n) % n] : pts[clamp(i, 0, n - 1)];
  let d = `M${f2(pts[0][0])} ${f2(pts[0][1])}`;
  const last = closed ? n : n - 1;
  for (let i = 0; i < last; i++) {
    const p0 = P_(i - 1), p1 = P_(i), p2 = P_(i + 1), p3 = P_(i + 2);
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6 * k, p1[1] + (p2[1] - p0[1]) / 6 * k];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6 * k, p2[1] - (p3[1] - p1[1]) / 6 * k];
    d += `C${f2(c1[0])} ${f2(c1[1])} ${f2(c2[0])} ${f2(c2[1])} ${f2(p2[0])} ${f2(p2[1])}`;
  }
  return d + (closed ? 'Z' : '');
}
/* «прядь»: остроконечный клин от основания (a,b) к кончику tip с изгибом bend */
function lock(ax, ay, bx, by, tx, ty, bend = 0) {
  const mx = (ax + bx) / 2, my = (ay + by) / 2;
  const nx = -(ty - my), ny = tx - mx, l = Math.hypot(nx, ny) || 1;
  const cx = (mx + tx) / 2 + nx / l * bend, cy = (my + ty) / 2 + ny / l * bend;
  return `M${f2(ax)} ${f2(ay)}Q${f2(lerp(ax, cx, .7))} ${f2(lerp(ay, cy, .7))} ${f2(tx)} ${f2(ty)}Q${f2(lerp(bx, cx, .7))} ${f2(lerp(by, cy, .7))} ${f2(bx)} ${f2(by)}Z`;
}
/* зубчатый контур чёлки: попеременно впадины и кончики, кончики острые */
function spikyPath(points) {
  // points: [[x,y,'v'|'t'], ...] — от левого края к правому
  let d = `M${f2(points[0][0])} ${f2(points[0][1])}`;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1], b = points[i];
    const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
    // кривизна: к кончику — выпукло, от кончика — вогнуто
    const bulge = (b[2] === 't' ? 1 : -1) * 0.18;
    const cx = mx - (b[1] - a[1]) * bulge, cy = my + (b[0] - a[0]) * bulge;
    d += `Q${f2(cx)} ${f2(cy)} ${f2(b[0])} ${f2(b[1])}`;
  }
  return d;
}

/* ---------- общие фильтры (живут в постоянном <defs>) ---------- */
const GLOBAL_DEFS = `
<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="glowL" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="22" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="blur2" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2"/></filter>
<filter id="blur4" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter>
<filter id="blur8" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="8"/></filter>
<filter id="blur16" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="16"/></filter>
<filter id="blur30" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="30"/></filter>
<filter id="blur60" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="60"/></filter>
<filter id="ikatBlur" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.02 0.25" numOctaves="2" seed="4"/><feDisplacementMap in="SourceGraphic" scale="9" xChannelSelector="R" yChannelSelector="G"/></filter>
<filter id="gradeNight" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0.42 0.05 0.08 0 0.02  0.06 0.42 0.12 0 0.03  0.10 0.12 0.72 0 0.09  0 0 0 1 0"/></filter>
<filter id="gradeRed" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0.70 0.20 0.10 0 0.10  0.10 0.32 0.05 0 0.0  0.12 0.10 0.40 0 0.04  0 0 0 1 0"/></filter>
<filter id="gradeDusk" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0.80 0.12 0.05 0 0.06  0.06 0.62 0.10 0 0.02  0.10 0.12 0.75 0 0.05  0 0 0 1 0"/></filter>
<filter id="gradeWarm" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="1.04 0.04 0 0 0.02  0.02 0.98 0 0 0.01  0 0 0.9 0 0  0 0 0 1 0"/></filter>
<filter id="gradeRedDark" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0.36 0.10 0.06 0 0.05  0.05 0.10 0.04 0 0.0  0.08 0.06 0.16 0 0.03  0 0 0 1 0"/></filter>
<filter id="gradeNightDark" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0.20 0.04 0.06 0 0.01  0.04 0.24 0.08 0 0.02  0.08 0.10 0.46 0 0.06  0 0 0 1 0"/></filter>
<filter id="gradeRedChar" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0.86 0.14 0.06 0 0.06  0.08 0.46 0.04 0 0.0  0.08 0.06 0.50 0 0.02  0 0 0 1 0"/></filter>
<filter id="gradeNightChar" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0.52 0.06 0.08 0 0.02  0.06 0.56 0.12 0 0.03  0.10 0.14 0.86 0 0.08  0 0 0 1 0"/></filter>
<filter id="gradeDawnChar" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="1.0 0.1 0.02 0 0.04  0.04 0.86 0.04 0 0.02  0.02 0.06 0.78 0 0.02  0 0 0 1 0"/></filter>
<filter id="gradeGray" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0.35"/></filter>
<filter id="silh" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0 0 0 0.05  0 0 0 0 0.02  0 0 0 0 0.08  0 0 0 1 0"/></filter>
<filter id="smoke" x="-20%" y="-20%" width="140%" height="140%"><feTurbulence type="fractalNoise" baseFrequency="0.012" numOctaves="3" seed="2" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="70" xChannelSelector="R" yChannelSelector="G"/></filter>
`;

/* ---------- эффекты ---------- */
/* радиальные линии скорости (аниме-концентрация) — меняются каждые 2 кадра */
function speedLines(cx, cy, t, o = {}) {
  const n = o.n || 90, r0 = o.r0 || 380, col = o.color || '#fff', op = o.op == null ? .9 : o.op;
  const r = rng(Math.floor(t * 12) * 7 + (o.seed || 1));
  let d = '';
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 + r() * 0.06;
    const w = (0.004 + r() * 0.012) * (o.w || 1);
    const rin = r0 * (0.75 + r() * 0.6);
    const R = 2600;
    const x1 = cx + Math.cos(a - w) * R, y1 = cy + Math.sin(a - w) * R;
    const x2 = cx + Math.cos(a + w) * R, y2 = cy + Math.sin(a + w) * R;
    const x3 = cx + Math.cos(a) * rin, y3 = cy + Math.sin(a) * rin;
    d += `M${f2(x1)} ${f2(y1)}L${f2(x2)} ${f2(y2)}L${f2(x3)} ${f2(y3)}Z`;
  }
  return path(d, col, `opacity="${op}"`);
}
/* параллельные линии скорости под углом ang (градусы) */
function dashLines(t, o = {}) {
  const n = o.n || 40, ang = o.ang || 0, col = o.color || '#fff', op = o.op == null ? .6 : o.op, sp = o.speed || 4000;
  const r = rng(o.seed || 3);
  let d = '';
  for (let i = 0; i < n; i++) {
    const y = r() * (H + 400) - 200, len = 200 + r() * 700, th = 1 + r() * (o.th || 4);
    const x = ((r() * 3000 + t * sp * (0.6 + r() * 0.8)) % 3000) - 600;
    d += `M${f2(x)} ${f2(y)}h${f2(len)}l${f2(-len * .1)} ${f2(th)}h${f2(-len * .9)}Z`;
  }
  return g(path(d, col, `opacity="${op}"`), `rotate(${ang} ${W / 2} ${H / 2})`);
}
/* частицы: листья чинары, искры, звёздная пыль, угли */
function particles(t, o = {}) {
  const n = o.n || 40, kind = o.kind || 'dust', r = rng(o.seed || 11);
  let s = '';
  for (let i = 0; i < n; i++) {
    const x0 = r() * (W + 400) - 200, y0 = r() * (H + 400) - 200, sp = 0.4 + r() * 0.9, ph = r() * 100, sz = 0.5 + r();
    const vx = (o.vx || 0) * sp, vy = (o.vy == null ? 60 : o.vy) * sp;
    let x = x0 + vx * t + Math.sin(t * 1.3 * sp + ph) * (o.sway || 30);
    let y = y0 + vy * t;
    x = ((x + 200) % (W + 400) + (W + 400)) % (W + 400) - 200;
    y = ((y + 200) % (H + 400) + (H + 400)) % (H + 400) - 200;
    if (kind === 'leaf') {
      const rot = (t * 90 * sp + ph * 40) % 360, flip = Math.cos(t * 3 * sp + ph);
      const c = ['#E8A93A', '#F2C14E', '#D9822B', '#C9611F', '#F5D06B'][i % 5];
      s += g(path('M0 -14C8 -10 12 -2 9 6C6 12 2 14 0 18C-2 14 -6 12 -9 6C-12 -2 -8 -10 0 -14Z', c) + strokeP('M0 -12L0 16', 'rgba(120,60,10,.5)', 1.2),
        `translate(${f2(x)} ${f2(y)}) rotate(${f2(rot)}) scale(${f2(sz * (o.size || 1.3))} ${f2(sz * (o.size || 1.3) * Math.max(.15, Math.abs(flip)))})`);
    } else if (kind === 'ember') {
      const fl = 0.5 + 0.5 * Math.sin(t * 9 + ph);
      s += circle(x, y, (1.5 + sz * 2.5) * (o.size || 1), o.color || '#FF8A3C', `opacity="${f2((0.35 + 0.65 * fl) * (o.op || 1))}"`);
    } else if (kind === 'star') {
      const fl = 0.5 + 0.5 * Math.sin(t * 5 + ph);
      const R = (3 + sz * 5) * (o.size || 1);
      s += g(path(`M0 ${-R}L${R * .22} ${-R * .22}L${R} 0L${R * .22} ${R * .22}L0 ${R}L${-R * .22} ${R * .22}L${-R} 0L${-R * .22} ${-R * .22}Z`, o.color || '#FFF3C4'),
        `translate(${f2(x)} ${f2(y)}) rotate(${f2(t * 40 + ph)})`, `opacity="${f2((0.3 + 0.7 * fl) * (o.op || 1))}"`);
    } else {
      s += circle(x, y, (1 + sz * 2) * (o.size || 1), o.color || '#fff', `opacity="${f2((0.15 + 0.4 * r()) * (o.op || 1))}"`);
    }
  }
  return s;
}
/* звёздное небо */
function starfield(seed, n, o = {}) {
  const r = rng(seed);
  let s = '';
  for (let i = 0; i < n; i++) {
    const x = r() * (o.w || W), y = r() * (o.h || H * .7), m = r();
    const tw_ = o.t != null ? 0.6 + 0.4 * Math.sin(o.t * (2 + r() * 4) + i) : 1;
    const R = m > .985 ? 2.6 : m > .93 ? 1.7 : 0.9;
    s += circle(x, y, R, m > .97 ? '#FFF2C8' : '#DDE8FF', `opacity="${f2((0.35 + m * 0.65) * tw_)}"`);
    if (m > .985) s += path(`M${f2(x - 9)} ${f2(y)}L${f2(x + 9)} ${f2(y)}M${f2(x)} ${f2(y - 9)}L${f2(x)} ${f2(y + 9)}`, 'none', `stroke="#FFF6DA" stroke-width="1" opacity="${f2(.6 * tw_)}"`);
  }
  return s;
}
/* световые лучи из точки */
function godRays(cx, cy, t, o = {}) {
  const n = o.n || 14, col = o.color || '#FFF1C4', r = rng(o.seed || 5), op = o.op == null ? .25 : o.op;
  let s = '';
  for (let i = 0; i < n; i++) {
    const a = (o.a0 || 0) + (i / n) * (o.spread || Math.PI * 2) + Math.sin(t * .3 + i) * .03;
    const w = 0.02 + r() * 0.05, L = o.len || 2200;
    const p1 = [cx + Math.cos(a - w) * L, cy + Math.sin(a - w) * L], p2 = [cx + Math.cos(a + w) * L, cy + Math.sin(a + w) * L];
    s += poly([[cx, cy], p1, p2], col, `opacity="${f2(op * (0.4 + 0.6 * r()) * (0.7 + 0.3 * Math.sin(t * 1.5 + i * 2)))}"`);
  }
  return g(s, '', 'style="mix-blend-mode:screen" filter="url(#blur8)"');
}
/* восьмиконечная звезда-гирих */
function star8(R, r_) {
  let pts = [];
  for (let i = 0; i < 16; i++) { const a = i * Math.PI / 8 - Math.PI / 2, rr = i % 2 ? r_ : R; pts.push([Math.cos(a) * rr, Math.sin(a) * rr]); }
  return pts;
}
const starPath = (R, r_, n = 8) => {
  let d = '';
  for (let i = 0; i < n * 2; i++) { const a = i * Math.PI / n - Math.PI / 2, rr = i % 2 ? r_ : R; d += (i ? 'L' : 'M') + f2(Math.cos(a) * rr) + ' ' + f2(Math.sin(a) * rr); }
  return d + 'Z';
};
/* магический круг-гирих (узбекский орнамент) */
function girihCircle(t, R, o = {}) {
  const col = o.color || '#7FF3E8', col2 = o.color2 || '#FFD27A', op = o.op == null ? 1 : o.op;
  const rot = t * (o.spin || 20);
  let s = '';
  s += circle(0, 0, R, 'none', `stroke="${col}" stroke-width="${R * .012}"`);
  s += circle(0, 0, R * .93, 'none', `stroke="${col}" stroke-width="${R * .005}"`);
  s += circle(0, 0, R * .62, 'none', `stroke="${col2}" stroke-width="${R * .008}"`);
  // бегущая надпись — звёзды каталога Улугбека
  const id = uid('tp');
  s += `<path id="${id}" d="M0 ${-R * .965}A${R * .965} ${R * .965} 0 1 1 -0.1 ${-R * .965}" fill="none"/>`;
  s += g(`<text font-family="Unbounded" font-weight="600" font-size="${f2(R * .045)}" fill="${col}" letter-spacing="${f2(R * .012)}"><textPath href="#${id}">ZIJ-I KO'RAGONIY · 1018 YULDUZ · SAMARQAND · MIRZO ULUG'BEK · 1437 · ZIJ-I KO'RAGONIY · 1018 YULDUZ · SAMARQAND ·</textPath></text>`, `rotate(${f2(-rot * .5)})`);
  // звёзды гирих
  s += g(path(starPath(R * .9, R * .37, 8), 'none', `stroke="${col}" stroke-width="${R * .01}"`) +
    g(path(starPath(R * .9, R * .37, 8), 'none', `stroke="${col}" stroke-width="${R * .006}"`), 'rotate(22.5)'), `rotate(${f2(rot)})`);
  s += g(path(starPath(R * .58, R * .3, 8), 'none', `stroke="${col2}" stroke-width="${R * .01}"`) +
    path(starPath(R * .3, R * .12, 8), col2, `opacity=".25"`), `rotate(${f2(-rot * 1.4)})`);
  for (let i = 0; i < 8; i++) {
    const a = i * Math.PI / 4 + rot * Math.PI / 180;
    s += circle(Math.cos(a) * R * .76, Math.sin(a) * R * .76, R * .035, col2);
    s += g(path(starPath(R * .06, R * .025, 8), col), `translate(${f2(Math.cos(a + .39) * R * .76)} ${f2(Math.sin(a + .39) * R * .76)})`);
  }
  return g(s, '', `opacity="${f2(op)}" filter="url(#glow)"`);
}
/* растрескавшаяся земля / трещины */
function cracks(seed, cx, cy, R, prog, col) {
  const r = rng(seed);
  let d = '';
  for (let i = 0; i < 9; i++) {
    let a = r() * Math.PI * 2, x = cx, y = cy, L = R * (0.5 + r() * 0.5) * prog;
    d += `M${f2(x)} ${f2(y)}`;
    const steps = 7;
    for (let k = 0; k < steps; k++) {
      a += (r() - .5) * .9; x += Math.cos(a) * L / steps; y += Math.sin(a) * L / steps * .45;
      d += `L${f2(x)} ${f2(y)}`;
    }
  }
  return strokeP(d, col || '#FF5A2A', 4, 'filter="url(#glow)"');
}
/* вспышка-кольцо удара */
function shockRing(cx, cy, k, R, col) {
  if (k <= 0 || k >= 1) return '';
  return circle(cx, cy, R * E.outC(k), 'none', `stroke="${col || '#fff'}" stroke-width="${f2(40 * (1 - k))}" opacity="${f2(1 - k)}"`);
}
