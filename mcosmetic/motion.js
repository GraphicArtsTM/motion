/* M Cosmetic — «Mega chegirma», ролик 1080×1920 (9:16), 16 с.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Голос стоит с отметки VO = 1,0 с. Музыка 120 BPM, доли на 0,1 + 0,5k,
   такты на 0,1 + 2n — так ключевые слова диктора попадают в сетку:
   «25» 1,6 · «26» 2,6 · «M Cosmetic» 4,1 · «ellik foiz» 8,1 · «Taklif» 10,1. */
'use strict';

const W = 1080, H = 1920, DUR = 16;
const $ = s => document.querySelector(s);
const clamp = (x, a = 0, b = 1) => x < a ? a : x > b ? b : x;
const lerp = (a, b, k) => a + (b - a) * k;

/* ---------- изинги ---------- */
const E = {
  lin: x => x,
  inQuad: x => x * x,
  outQuad: x => 1 - (1 - x) * (1 - x),
  inCubic: x => x * x * x,
  outCubic: x => 1 - Math.pow(1 - x, 3),
  inOutCubic: x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2,
  outQuint: x => 1 - Math.pow(1 - x, 5),
  inExpo: x => x <= 0 ? 0 : Math.pow(2, 10 * x - 10),
  outExpo: x => x >= 1 ? 1 : 1 - Math.pow(2, -10 * x),
  inOutExpo: x => x <= 0 ? 0 : x >= 1 ? 1 : x < .5 ? Math.pow(2, 20 * x - 10) / 2 : (2 - Math.pow(2, -20 * x + 10)) / 2,
  outBack: x => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outBackS: x => { const c1 = 2.6, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outElastic: x => x <= 0 ? 0 : x >= 1 ? 1 : Math.pow(2, -10 * x) * Math.sin((x * 10 - .75) * (2 * Math.PI) / 3) + 1,
};
const P = (t, t0, d) => clamp((t - t0) / d);
const tw = (t, t0, d, a, b, e = E.outExpo) => lerp(a, b, e(P(t, t0, d)));
/* ключевые кадры: [[t, v], [t, v, ease], ...] */
function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, e] = keys[i], [t0, v0] = keys[i - 1];
    if (t <= t1) return lerp(v0, v1, (e || E.outExpo)(P(t, t0, t1 - t0)));
  }
  return keys[keys.length - 1][1];
}
/* затухающая «пружинка» после удара: 0 → колебание → 0 */
const bump = (t, t0, amp = 1, f = 9, k = 7) => t < t0 ? 0 : amp * Math.sin((t - t0) * f) * Math.exp(-(t - t0) * k);
/* пульс на каждую долю */
const beatPulse = (t, k = 10) => { const b = (t - 0.1) / 0.5; const ph = b - Math.floor(b); return Math.exp(-ph * 0.5 * k); };

/* ---------- детерминированный рандом ---------- */
function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}

/* ---------- трансформ элемента: (x, y) — центр элемента на кадре ---------- */
function S(el, o) {
  let tr = 'translate(-50%,-50%) translate3d(' + (o.x || 0).toFixed(2) + 'px,' + (o.y || 0).toFixed(2) + 'px,0)';
  if (o.rx) tr += ' perspective(1400px) rotateX(' + o.rx.toFixed(3) + 'deg)';
  if (o.ry) tr += ' perspective(1400px) rotateY(' + o.ry.toFixed(3) + 'deg)';
  if (o.r) tr += ' rotate(' + o.r.toFixed(3) + 'deg)';
  const sx = o.sx != null ? o.sx : o.s != null ? o.s : 1, sy = o.sy != null ? o.sy : o.s != null ? o.s : 1;
  if (sx !== 1 || sy !== 1) tr += ' scale(' + sx.toFixed(4) + ',' + sy.toFixed(4) + ')';
  el.style.transform = tr;
  const op = o.o == null ? 1 : clamp(o.o);
  el.style.opacity = op;
  el.style.visibility = op <= 0.001 ? 'hidden' : 'visible';
  let f = '';
  if (o.b > .05) f += 'blur(' + o.b.toFixed(2) + 'px) ';
  if (o.br != null && o.br !== 1) f += 'brightness(' + o.br.toFixed(3) + ') ';
  if (o.f) f += o.f;
  if (f || el.dataset.f) { el.style.filter = f || ''; el.dataset.f = f ? 1 : ''; }
}
const so = (el, v) => el.style.setProperty('--so', v.toFixed(1) + 'px');
const show = (el, on, disp = 'block') => { el.style.display = on ? disp : 'none'; };

/* ---------- графика: цветок с постера, блик ---------- */
let gid = 0;
function flowerSVG(kind) {
  const id = 'fg' + (gid++);
  const c = kind === 1 ? ['#FFE3F4', '#F05BA6', '#B0125A'] : kind === 2 ? ['#FFFFFF', '#F7B9DD', '#D9579F'] : ['#FFD0EA', '#E8197A', '#8C0F43'];
  const petal = 'M50 50 C34 40 30 16 47 6 C49 5 51 5 53 6 C70 16 66 40 50 50 Z';
  let p = '';
  for (let i = 0; i < 4; i++) p += '<path d="' + petal + '" transform="rotate(' + (45 + i * 90) + ' 50 50)" fill="url(#' + id + ')" stroke="rgba(255,225,242,.55)" stroke-width="1.2"/>';
  return '<svg viewBox="0 0 100 100" width="100%" height="100%" style="overflow:visible"><defs>' +
    '<radialGradient id="' + id + '" cx="50%" cy="50%" r="55%"><stop offset="0" stop-color="' + c[0] + '"/><stop offset=".45" stop-color="' + c[1] + '"/><stop offset="1" stop-color="' + c[2] + '"/></radialGradient>' +
    '<radialGradient id="' + id + 'g"><stop offset="0" stop-color="rgba(255,255,255,.95)"/><stop offset="1" stop-color="rgba(255,255,255,0)"/></radialGradient></defs>' +
    p + '<circle cx="50" cy="50" r="15" fill="url(#' + id + 'g)"/></svg>';
}
const GLINT = '<svg viewBox="0 0 100 100" width="100%" height="100%" style="overflow:visible"><defs><radialGradient id="glg"><stop offset="0" stop-color="rgba(255,255,255,.9)"/><stop offset="1" stop-color="rgba(255,255,255,0)"/></radialGradient></defs>' +
  '<circle cx="50" cy="50" r="30" fill="url(#glg)"/><path d="M50 0 C53 40 60 47 100 50 C60 53 53 60 50 100 C47 60 40 53 0 50 C40 47 47 40 50 0Z" fill="#fff"/></svg>';

/* ---------- сборка DOM ---------- */
const el = {};
for (const id of ['root', 'cam', 'rays', 'raysGlow', 'magenta', 'magRays', 'logoCard', 's2', 's3', 's4', 's5', 's6', 's7',
  'cal25', 'cal26', 'blk', 'hl', 'hlMega', 'hlCheg', 'bIcon', 'bWord', 'wSizga', 'wMaxsus', 'wNarx', 'wChek', 'wAssort',
  'big', 'pct', 'wCheg', 'disc', 'shelf', 'oLogo', 'oShine', 'tap', 'oMega', 'oDates', 'oSticker', 'oSite', 'fine',
  'fx', 'revRing', 'bgFlowers', 'flash', 'dark', 'grain', 'vig']) el[id] = document.getElementById(id);

function splitChars(node) {
  const txt = node.textContent; node.textContent = '';
  return [...txt].map(c => { const s = document.createElement('span'); s.className = c === ' ' ? 'sp' : 'ch'; s.textContent = c === ' ' ? '' : c; node.appendChild(s); return s; });
}
const chMega = splitChars(el.hlMega), chCheg = splitChars(el.hlCheg);

/* блик, пробегающий по карточке после удара */
const GL = {};
for (const id of ['logoCard', 'hl', 'blk', 'wMaxsus', 'wNarx', 'wChek', 'wAssort', 'big', 'wCheg', 'disc', 'oMega']) {
  const g = document.createElement('div'); g.className = 'gl'; el[id].appendChild(g); GL[id] = g;
}
function gloss(id, t, t0, d = .7) {
  const p = P(t, t0, d), g = GL[id];
  g.style.opacity = p > 0 && p < 1 ? 1 : 0;
  g.style.backgroundPosition = lerp(135, -35, E.inOutCubic(p)).toFixed(1) + '% 0';
}

const PRODS = ['pLip', 'pPump', 'pPerf', 'pTube', 'pSerum', 'pBrush', 'pDryer'].map(id => document.getElementById(id));
const PH = [400, 430, 330, 380, 380, 380, 360];          // высоты из CSS
const BDG = [0, 1, 2, 3, 4, 5, 6].map(i => document.getElementById('bdg' + i));

/* фоновые цветы (за контентом) */
const AMB = [];
{
  const r = rng(11);
  const spots = [[90, 260, 230, 0], [1000, 420, 180, 1], [120, 1520, 200, 1], [980, 1700, 260, 0], [860, 1120, 120, 2], [230, 880, 110, 2], [600, 1820, 150, 0], [520, 120, 120, 1]];
  for (const [x, y, s, k] of spots) {
    const d = document.createElement('div'); d.className = 'a flw'; d.innerHTML = flowerSVG(k);
    d.style.width = d.style.height = s + 'px'; el.bgFlowers.appendChild(d);
    AMB.push({ d, x, y, s, ph: r() * 6.28, sp: .4 + r() * .5, rot: r() * 90, vr: (r() - .5) * 30, blur: s > 200 ? 3 : 0 });
  }
}
/* всплески цветов на ударах (за надписями) */
const BURSTS = [
  { t: 0.6, x: 540, y: 820, n: 8, v: 1700 }, { t: 1.6, x: 540, y: 1300, n: 5, v: 1200 }, { t: 2.6, x: 760, y: 1300, n: 5, v: 1200 },
  { t: 3.6, x: 540, y: 1040, n: 6, v: 1500 }, { t: 4.1, x: 540, y: 720, n: 7, v: 1500 }, { t: 8.1, x: 540, y: 900, n: 10, v: 2200 },
  { t: 9.04, x: 540, y: 1330, n: 5, v: 1300 }, { t: 12.6, x: 540, y: 700, n: 8, v: 1800 }];
const PARTS = [];
{
  const r = rng(5);
  for (const b of BURSTS) for (let i = 0; i < b.n; i++) {
    const d = document.createElement('div'); d.className = 'a flw'; d.innerHTML = flowerSVG(i % 3);
    const s = 60 + r() * 80; d.style.width = d.style.height = s + 'px'; el.bgFlowers.appendChild(d);
    PARTS.push({ d, b, a: (i / b.n) * Math.PI * 2 + r() * .5, v: b.v * (.55 + r() * .6), vr: (r() - .5) * 600, life: 1.2 + r() * .6, s0: .7 + r() * .5 });
  }
}
/* конфетти на дропе и в финале */
const CONF = [];
{
  const r = rng(23), cols = ['#FFFFFF', '#FFC2E2', '#C77BCB', '#8C0F43', '#FFE38A', '#EE1766'];
  for (let i = 0; i < 90; i++) {
    const d = document.createElement('div'); d.className = 'a conf'; d.style.background = cols[i % cols.length];
    if (i % 4 === 0) { d.style.borderRadius = '50%'; d.style.height = '22px'; }
    el.fx.appendChild(d);
    const rain = i >= 55;
    CONF.push({ d, t0: rain ? 12.6 + r() * .5 : 8.1, rain, a: r() * Math.PI * 2, v: 900 + r() * 1500, x0: r() * W, vr: (r() - .5) * 900, fl: 4 + r() * 6, ph: r() * 6, sw: 30 + r() * 60 });
  }
}
/* ударные волны */
const SHOCKS = [[0.6, 540, 820, 1], [3.6, 540, 1040, .8], [8.1, 540, 900, 1.3], [9.04, 540, 1330, .6], [12.65, 540, 690, 1]].map(([t, x, y, k]) => {
  const d = document.createElement('div'); d.className = 'a shock'; el.fx.appendChild(d); return { d, t, x, y, k };
});
/* блики-звёздочки */
const GLINTS = [[4.45, 300, 600, 120], [4.62, 830, 830, 90], [4.85, 700, 520, 70], [5.75, 860, 1350, 80], [8.42, 900, 700, 120], [8.58, 160, 1080, 90],
  [9.3, 850, 1290, 80], [10.9, 880, 470, 90], [11.5, 170, 1000, 80], [13.15, 930, 620, 110], [13.45, 140, 760, 80], [14.1, 610, 600, 70], [14.8, 880, 1250, 90], [15.4, 300, 640, 80]].map(([t, x, y, s]) => {
  const d = document.createElement('div'); d.className = 'a glint'; d.innerHTML = GLINT; d.style.width = d.style.height = s + 'px'; el.fx.appendChild(d);
  return { d, t, x, y };
});

/* зерно */
{
  const c = document.createElement('canvas'); c.width = c.height = 256;
  const g = c.getContext('2d'), im = g.createImageData(256, 256), r = rng(99);
  for (let i = 0; i < im.data.length; i += 4) { const v = r() * 255; im.data[i] = im.data[i + 1] = im.data[i + 2] = v; im.data[i + 3] = 255; }
  g.putImageData(im, 0, 0); el.grain.style.backgroundImage = 'url(' + c.toDataURL() + ')';
}

/* ---------- камера: тряска и «пинок» на ударах ---------- */
const HITS = [[0.6, 26], [0.85, 16], [1.6, 12], [2.6, 12], [3.6, 18], [4.1, 14], [8.1, 38], [9.04, 18], [12.65, 22]];
function camAt(t) {
  let x = 0, y = 0, r = 0, s = 1;
  HITS.forEach(([h, a], i) => {
    if (t < h) return;
    const d = t - h, e = Math.exp(-d * 9);
    x += a * e * Math.sin(d * 61 + i * 1.7); y += a * e * Math.sin(d * 47 + i * 2.9); r += a * .02 * e * Math.sin(d * 39 + i);
    s += a * .0016 * Math.exp(-d * 10);
  });
  // нарастание тряски на билде 6,9–8,1
  const bu = P(t, 6.9, 1.2) * (t < 8.1 ? 1 : 0);
  x += 9 * bu * bu * Math.sin(t * 83); y += 9 * bu * bu * Math.sin(t * 71 + 1);
  s += .07 * E.inQuad(bu);
  // плавный дрейф
  s += .012 * Math.sin(t * .7);
  return { x, y, r, s };
}

/* скорость вращения лучей (град/с) и угол — численный интеграл */
function raySpeed(t) {
  let v = 7;
  if (t < 0.6) v = 7 + 60 * (1 - t / 0.6);
  v += 80 * E.inQuad(P(t, 6.9, 1.2)) * (t < 8.1 ? 1 : 0);
  if (t >= 8.1) v += 110 * Math.exp(-(t - 8.1) * 2.2);
  if (t >= 12.6) v += 40 * Math.exp(-(t - 12.6) * 2.5);
  return v;
}
const RAY_ANG = [];
{ let a = 0; for (let i = 0; i <= DUR * 240 + 2; i++) { RAY_ANG.push(a); a += raySpeed(i / 240) / 240; } }
const rayAng = t => RAY_ANG[clamp(Math.round(t * 240), 0, RAY_ANG.length - 1)];

/* ---------- раскладки товаров по сценам ---------- */
const mixO = (a, b, k) => ({ x: lerp(a.x, b.x, k), y: lerp(a.y, b.y, k), r: lerp(a.r, b.r, k), s: lerp(a.s, b.s, k), o: lerp(a.o, b.o, k) });
// S2: ряд товаров под блоком «HAR 25-26» (3,6–4,1), затем уходят вниз вместе с рывком камеры
const ROW2 = { 2: 0, 3: 1, 4: 2, 5: 3, 0: 4, 1: 5 };
// S3: товары обрамляют слова
const L3 = [[105, 1330, -12, .8], [975, 1320, 12, .8], [270, 1650, -8, .9], [810, 1660, 9, .88]];
const FROM3 = [[-260, 1100, -60], [1340, 1000, 60], [-260, 1900, -40], [1340, 1950, 50]];
// S6: полка
const SHELF = [1, 4, 0, 2, 3, 5, -1];   // слот для каждого товара (-1 — уходит)

function prodLayout(i, t) {
  const r = rng(100 + i);
  const ph = r() * 6.28;
  const bob = Math.sin(t * 2.1 + ph) * 14, sway = Math.sin(t * 1.6 + ph) * 3;
  const hid = { x: 540, y: 2400, r: 0, s: .6, o: 0 };
  let o = hid;
  // S2: ряд снизу
  if (t >= 3.5 && t < 4.1 && i in ROW2) {
    const slot = ROW2[i];
    const tgt = { x: 115 + slot * 170, y: 1470 - PH[i] * .58 / 2 + bob * .5, r: (slot - 2.5) * 3, s: .58, o: 1 };
    const k = E.outBackS(P(t, 3.6 + slot * .04, .45));
    o = mixO({ x: tgt.x, y: 2150, r: (slot - 2.5) * 12, s: .58, o: 1 }, tgt, k);
    if (t < 3.6 + slot * .04) o.o = 0;
  }
  // S3
  if (t >= 4.1 && i < 4) {
    const k = E.outBack(P(t, 4.5 + i * .09, .55)), f = FROM3[i];
    const tgt = { x: L3[i][0], y: L3[i][1] + bob, r: L3[i][2] + sway, s: L3[i][3], o: 1 };
    o = mixO({ x: f[0], y: f[1], r: f[2], s: tgt.s, o: 1 }, tgt, k);
    if (t < 4.5 + i * .09) o.o = 0;
  } else if (t >= 4.1) o = hid;
  // S4: карусель
  if (t >= 6.8) {
    const d = Math.max(0, t - 6.85);
    const scroll = 260 * d + 180 * d * d;
    const tgt = { x: 540 + (i - 3) * 330 + 380 - scroll, y: 1250 + Math.sin(t * 5 + i) * 10, r: Math.sin(t * 6 + i * 1.3) * 6, s: .9, o: 1 };
    const k = E.outExpo(P(t, 6.85 + i * .03, .45));
    const src = i < 4 ? o : { x: 1300 + i * 120, y: 1250, r: 20, s: .9, o: 1 };
    o = mixO(src, tgt, k);
    // имплозия к центру
    const im = E.inExpo(P(t, 7.82, .28));
    o.x = lerp(o.x, 540, im); o.y = lerp(o.y, 960, im); o.s *= 1 - .85 * im; o.r += 200 * im;
  }
  // S5: орбита вокруг −50% (за карточкой)
  if (t >= 8.1) {
    const d = t - 8.1;
    const th = i / 7 * Math.PI * 2 - Math.PI / 2 + d * .55 + .3;
    const ox = 540 + 500 * Math.cos(th), oy = 930 + 650 * Math.sin(th);
    const k = E.outExpo(P(t, 8.1, .7));
    o = { x: lerp(540, ox, k), y: lerp(960, oy, k), r: lerp(400, Math.sin(t * 3 + i) * 10, k), s: lerp(.1, .66 + .06 * Math.sin(th), k), o: 1 };
  }
  // S6: полка
  if (t >= 10.0) {
    const slot = SHELF[i];
    const sc = .66;
    const tgt = slot < 0 ? { x: 1400, y: 1500, r: 40, s: .6, o: 1 } : { x: 115 + slot * 170, y: 1612 - PH[i] * sc / 2 + Math.sin(t * 2 + i) * 3, r: 0, s: sc, o: 1 };
    const k = slot < 0 ? E.inOutCubic(P(t, 10.05, .5)) : E.outBack(P(t, 10.1 + slot * .05, .6));
    o = mixO(o, tgt, k);
  }
  // S7: две позиции по бокам, остальные уходят вниз
  if (t >= 12.4) {
    const keep = { 0: [118, 1240, -12, .78], 1: [968, 1215, 12, .78] }[i];
    if (keep) {
      const k = E.outExpo(P(t, 12.55 + i * .03, .7));
      o = mixO(o, { x: keep[0], y: keep[1] + bob * .6, r: keep[2] + sway, s: keep[3], o: 1 }, k);
    } else {
      const k2 = E.inCubic(P(t, 12.4 + i * .02, .3));
      o.y += 900 * k2; o.r += 40 * k2; o.o *= 1 - k2;
    }
  }
  return o;
}

/* круговое раскрытие пурпурного фона с белой кромкой */
function reveal(t, t0) {
  const rr = tw(t, t0, .5, 0, 1650, E.outCubic);
  return { rr, clip: 'circle(' + rr.toFixed(1) + 'px at 540px 760px)' };
}

/* ---------- кадр ---------- */
function renderAt(t) {
  /* фон */
  const ra = rayAng(t);
  const rayC = { x: 540, y: kf(t, [[0, 1010], [1.1, 1010], [1.5, 1080], [3.5, 1080], [3.8, 1040], [8.0, 960], [8.1, 900], [10.1, 900], [10.6, 1300]]) };
  const bloom = kf(t, [[0, .7], [0.6, 1, E.outExpo]]);
  S(el.rays, { x: rayC.x, y: rayC.y, r: ra, s: bloom });
  S(el.raysGlow, { x: rayC.x, y: rayC.y, s: 1 + .06 * beatPulse(t, 8) * (t > 8.1 && t < 12.6 ? 1 : .3) });

  // пурпурный фон бренда: сцена 3 (круг из центра → уезжает вверх) и финал
  let magO = 0, clip = 'none', magY = 0, ring = null;
  if (t >= 3.9 && t < 7.2) {
    magO = 1;
    const rv = reveal(t, 3.9); clip = rv.clip; ring = { rr: rv.rr, k: P(t, 3.9, .5) };
    magY = -1980 * E.inOutExpo(P(t, 6.82, .4));
  }
  if (t >= 12.5) {
    magO = 1;
    const rv = reveal(t, 12.5); clip = rv.clip; ring = { rr: rv.rr, k: P(t, 12.5, .5) };
  }
  el.magenta.style.opacity = magO; el.magenta.style.clipPath = clip;
  el.magenta.style.transform = 'translateY(' + magY.toFixed(1) + 'px)';
  S(el.magRays, { x: 540, y: 760, r: -ra * .6 });
  if (ring && ring.k < 1) {
    const d = 2 * ring.rr + 30;
    el.revRing.style.width = el.revRing.style.height = d.toFixed(0) + 'px';
    S(el.revRing, { x: 540, y: 760, o: 1 - E.inQuad(ring.k) });
  } else el.revRing.style.visibility = 'hidden';

  /* камера */
  const c = camAt(t);
  // переход 3,85–4,1: рывок камеры вперёд в «пурпурный» круг
  const zoomOut = t < 4.1 ? E.inExpo(P(t, 3.85, .25)) : 0;
  el.cam.style.transform = 'translate(' + c.x.toFixed(2) + 'px,' + c.y.toFixed(2) + 'px) rotate(' + c.r.toFixed(3) + 'deg) scale(' + (c.s + 1.6 * zoomOut).toFixed(4) + ')';
  el.cam.style.filter = zoomOut > .05 ? 'blur(' + (zoomOut * 14).toFixed(1) + 'px)' : '';

  /* плашка логотипа (сцены 1–2) */
  const on1 = t < 4.1;
  show(el.logoCard, on1, 'flex');
  if (on1) {
    const k = E.outBackS(P(t, 0.0, .5));
    S(el.logoCard, { x: 540, y: lerp(250, 330, k), r: lerp(-6, -2, k) + bump(t, 0.6, 2, 18, 8), s: lerp(.86, 1, k) });
    so(el.logoCard, 18 * E.outExpo(P(t, 0.2, .4)));
    gloss('logoCard', t, 0.35, .8);
  }

  /* ---------- сцена 2 ---------- */
  const on2 = t >= 0.5 && t < 4.1;
  show(el.s2, on2);
  if (on2) {
    // MEGA CHEGIRMA: удар, потом уезжает наверх
    const k1 = E.outExpo(P(t, 0.6, .35));
    const up = E.inOutCubic(P(t, 1.1, .45));
    S(el.hl, { x: 540, y: lerp(820, 660, up), r: -3 + bump(t, 0.6, 4, 16, 7) + bump(t, 0.85, -2, 16, 7), s: lerp(1, .8, up) * lerp(2.4, 1, k1) * (1 + .035 * bump(t, 3.6, 1, 22, 9)), o: P(t, 0.6, .06), b: 20 * (1 - k1) });
    so(el.hl, 22 * E.outBack(P(t, 0.7, .35)));
    gloss('hl', t, 1.0, .7);
    chMega.forEach((ch, i) => { const k = E.outBackS(P(t, 0.6 + i * .035, .4)); ch.style.transform = 'translateY(' + lerp(120, 0, k).toFixed(1) + 'px) scale(' + lerp(.2, 1, Math.min(1, k)).toFixed(3) + ')'; ch.style.opacity = P(t, .6 + i * .035, .08); });
    chCheg.forEach((ch, i) => { const k = E.outBackS(P(t, 0.85 + i * .028, .4)); ch.style.transform = 'translateY(' + lerp(120, 0, k).toFixed(1) + 'px) scale(' + lerp(.2, 1, Math.min(1, k)).toFixed(3) + ')'; ch.style.opacity = P(t, .85 + i * .028, .08); });

    // календари «25» и «26»: перелистываются, потом сжимаются в плашку «25-26»
    const merge = E.inOutExpo(P(t, 3.35, .3));
    const c25in = E.outBack(P(t, 1.6, .5)), c26in = E.outBack(P(t, 2.6, .5));
    const spread = E.outExpo(P(t, 2.6, .5));
    S(el.cal25, {
      x: lerp(lerp(540, 325, spread), 455, merge), y: lerp(lerp(1600, 1300, c25in), 985, merge) + Math.sin(t * 3) * 6,
      rx: lerp(-95, 0, Math.min(1, c25in)), r: lerp(0, -7, spread) + bump(t, 1.6, 4, 14, 6),
      s: lerp(1.12, .22, merge), o: P(t, 1.6, .08) * (1 - P(t, 3.55, .08)),
    });
    S(el.cal26, {
      x: lerp(760, 495, merge), y: lerp(lerp(1600, 1300, c26in), 985, merge) + Math.sin(t * 3 + 1) * 6,
      rx: lerp(-95, 0, Math.min(1, c26in)), r: 7 + bump(t, 2.6, -4, 14, 6),
      s: lerp(1.12, .22, merge), o: P(t, 2.6, .08) * (1 - P(t, 3.55, .08)),
    });
    so(el.cal25, 16); so(el.cal26, 16);

    // блок HAR 25-26 KUNLARI
    const kb = E.outBackS(P(t, 3.55, .45));
    S(el.blk, { x: 540, y: 1040, r: lerp(10, -2, kb), s: lerp(.3, 1, kb), o: P(t, 3.55, .06) });
    so(el.blk, 20 * E.outExpo(P(t, 3.7, .3)));
    gloss('blk', t, 3.7, .6);
  }

  /* ---------- сцена 3: бренд ---------- */
  const on3 = t >= 4.0 && t < 7.2;
  show(el.s3, on3);
  if (on3) {
    const oy = -1980 * E.inOutExpo(P(t, 6.82, .4));
    const ki = E.outBackS(P(t, 4.05, .5));
    S(el.bIcon, { x: 540, y: 600 + oy, r: lerp(-200, 0, E.outExpo(P(t, 4.05, .55))), s: lerp(.15, 1, ki) * (1 + .05 * bump(t, 5.6, 1, 20, 8)), o: P(t, 4.05, .04) });
    const kw = E.outExpo(P(t, 4.15, .5));
    el.bWord.style.clipPath = 'inset(0 ' + (100 * (1 - kw)).toFixed(2) + '% 0 0)';
    S(el.bWord, { x: lerp(500, 540, kw), y: 845 + oy, o: P(t, 4.15, .05) });
    // слова: SIZGA → MAXSUS → NARXLAR
    const w = (node, t0, y, from, rEnd) => {
      const k = E.outBackS(P(t, t0, .42));
      S(node, { x: lerp(from, 540, E.outExpo(P(t, t0, .4))), y: y + oy, r: lerp(from > 540 ? 12 : -12, rEnd, k), s: lerp(.4, 1, k) * (1 + .03 * bump(t, t0 + .5, 1, 20, 6)), o: P(t, t0, .06) });
      if (node !== el.wSizga) so(node, 16 * E.outExpo(P(t, t0 + .1, .3)));
    };
    w(el.wSizga, 4.96, 1035, 540, 0);
    w(el.wMaxsus, 5.32, 1180, -400, -2);
    w(el.wNarx, 5.64, 1345, 1480, 2);
    gloss('wMaxsus', t, 5.5, .6); gloss('wNarx', t, 5.85, .6);
  }

  /* ---------- сцена 4: cheklangan assortimentga ---------- */
  const on4 = t >= 6.85 && t < 8.15;
  show(el.s4, on4);
  if (on4) {
    const im = E.inExpo(P(t, 7.82, .28));
    const k1 = E.outBackS(P(t, 6.94, .45)), k2 = E.outBackS(P(t, 7.56, .42));
    const jit = 1 + .03 * E.inQuad(P(t, 7.3, .6)) * Math.sin(t * 90);
    S(el.wChek, { x: 540, y: lerp(lerp(460, 660, k1), 960, im), r: lerp(-14, -3, k1), s: lerp(.3, 1, k1) * (1 - .9 * im) * jit, o: P(t, 6.94, .06) });
    S(el.wAssort, { x: lerp(lerp(1500, 540, E.outExpo(P(t, 7.56, .4))), 540, im), y: lerp(825, 960, im), r: lerp(10, 2, k2), s: lerp(.4, 1, k2) * (1 - .9 * im) * jit, o: P(t, 7.56, .06) });
    so(el.wChek, 16 * E.outExpo(P(t, 7.0, .3))); so(el.wAssort, 16 * E.outExpo(P(t, 7.62, .3)));
    gloss('wChek', t, 7.1, .6); gloss('wAssort', t, 7.68, .5);
  }

  /* ---------- сцена 5: −50% (карточка остаётся и в сцене 6) ---------- */
  const on5 = t >= 8.05 && t < 12.7;
  show(el.s5, on5);
  if (on5) {
    const k = E.outExpo(P(t, 8.1, .3));
    const shrink = E.inOutCubic(P(t, 10.1, .5));
    const outro = E.inExpo(P(t, 12.28, .26));
    const pulse = t < 10.1 ? .025 * beatPulse(t, 10) : 0;
    S(el.big, {
      x: 540, y: lerp(900, 600, shrink) - 700 * outro, r: lerp(-4, -3, shrink) + bump(t, 8.1, 6, 18, 6),
      s: lerp(3.2, 1, k) * lerp(1, .78, shrink) * (1 + pulse), o: P(t, 8.08, .05), b: 24 * (1 - k),
    });
    so(el.big, 26 * E.outBack(P(t, 8.2, .35)));
    gloss('big', t, 8.5, .7);
    // счётчик 10 → 50 (две цифры — ширина не прыгает)
    el.pct.textContent = Math.round(10 + 40 * E.outExpo(P(t, 8.1, .42))) + '%';
    // CHEGIRMALAR!
    const kc = E.outBackS(P(t, 9.04, .42)), oc = E.inExpo(P(t, 9.95, .25));
    S(el.wCheg, { x: 540, y: lerp(1500, 1330, kc) + 600 * oc, r: lerp(12, -3, kc) + bump(t, 9.04, 3, 18, 6), s: lerp(.3, 1, kc) * (1 + .03 * beatPulse(t, 12) * (t > 9.4 ? 1 : 0)), o: P(t, 9.04, .06) * (1 - oc) });
    so(el.wCheg, 18 * E.outExpo(P(t, 9.12, .3)));
    gloss('wCheg', t, 9.3, .6);
  }

  /* ---------- сцена 6: условия ---------- */
  const on6 = t >= 10.05 && t < 12.7;
  show(el.s6, on6);
  if (on6) {
    const outro = E.inExpo(P(t, 12.28, .26));
    const kd = E.outBackS(P(t, 10.3, .5));
    S(el.disc, { x: lerp(-600, 540, E.outExpo(P(t, 10.3, .5))), y: 1010 - 1400 * outro, r: lerp(-10, -2, kd) + bump(t, 10.6, 1.5, 14, 5), s: lerp(.6, 1, kd), o: 1 - outro });
    so(el.disc, 18 * E.outExpo(P(t, 10.4, .35)));
    gloss('disc', t, 10.75, .8);
    S(el.shelf, { x: 540, y: 1632 + 600 * outro, sx: E.outExpo(P(t, 10.05, .5)) });
  }

  /* ---------- товары и стикеры «%» ---------- */
  PRODS.forEach((p, i) => {
    const o = prodLayout(i, t);
    S(p, o);
    // стикер «%» над товаром в карусели
    const bin = E.outBackS(P(t, 7.0 + i * .06, .35)), bout = E.inExpo(P(t, 7.82, .2));
    const bo = t >= 7.0 && t < 8.1 ? 1 - bout : 0;
    S(BDG[i], { x: o.x + 80, y: o.y - PH[i] * o.s / 2 - 6, r: -12 + Math.sin(t * 9 + i) * 10, s: bin * (1 - .8 * bout), o: bo * P(t, 7.0 + i * .06, .04) });
  });

  /* ---------- сцена 7: финал ---------- */
  const on7 = t >= 12.55;
  show(el.s7, on7);
  if (on7) {
    const kl = E.outBackS(P(t, 12.58, .6));
    const breathe = 1 + .012 * Math.sin((t - 12.6) * 2.2);
    S(el.oLogo, { x: 540, y: 690, s: lerp(.3, 1, kl) * breathe, o: P(t, 12.58, .08) });
    // блик по логотипу
    const shP = Math.max(P(t, 13.3, .8) * (t < 14.1 ? 1 : 0), P(t, 14.9, .8));
    S(el.oShine, { x: 540, y: 690, s: breathe, o: shP > 0 && shP < 1 ? 1 : 0 });
    el.oShine.style.backgroundPosition = lerp(130, -30, E.inOutCubic(shP)).toFixed(1) + '% 0';
    const km = E.outBackS(P(t, 12.95, .45));
    S(el.oMega, { x: 540, y: 885, r: lerp(-12, -2, km) + 1.2 * Math.sin((t - 13) * 2.6), s: lerp(.3, 1, km), o: P(t, 12.95, .06) });
    so(el.oMega, 16 * E.outExpo(P(t, 13.05, .3)));
    gloss('oMega', t, 13.25, .7);
    const kd = E.outExpo(P(t, 13.25, .5));
    S(el.oDates, { x: 540, y: lerp(1110, 1050, kd), o: kd });
    const kst = E.outBackS(P(t, 13.55, .5));
    S(el.oSticker, { x: 870, y: 470, r: lerp(-120, 14, E.outExpo(P(t, 13.55, .6))) + 4 * Math.sin(t * 2.4), s: kst * (1 + .05 * beatPulse(t, 10) * (t > 14 ? 1 : 0)), o: P(t, 13.55, .05) });
    // кнопка сайта: появление, затем «нажатие» с кольцом
    const kss = E.outBackS(P(t, 13.85, .5));
    const press = t > 14.9 ? -.07 * Math.exp(-(t - 14.9) * 8) * Math.sin((t - 14.9) * 20) : 0;
    S(el.oSite, { x: 540, y: lerp(1400, 1290, kss), s: lerp(.5, 1, kss) + press + .015 * Math.sin((t - 14) * 3) * (t > 14.4 ? 1 : 0), o: P(t, 13.85, .08) });
    const tp = P(t, 14.88, .6);
    S(el.tap, { x: 540, y: 1290, s: lerp(.4, 3.2, E.outCubic(tp)), o: tp > 0 && tp < 1 ? (1 - tp) * .9 : 0 });
    S(el.fine, { x: 540, y: 1590, o: .9 * P(t, 14.0, .5) });
  }

  /* ---------- частицы ---------- */
  AMB.forEach((a, i) => {
    const vis = t < 4.0 || (t >= 6.9 && t < 12.6);
    const x = a.x + Math.sin(t * a.sp + a.ph) * 30, y = a.y + Math.cos(t * a.sp * .8 + a.ph) * 40 - t * 12;
    S(a.d, { x, y, r: a.rot + a.vr * t, s: kf(t, [[0, .55], [0.6 + i * .05, 1, E.outBack]]), o: vis ? .9 : 0, b: a.blur });
  });
  PARTS.forEach(p => {
    const d = t - p.b.t;
    if (d < 0 || d > p.life) { p.d.style.visibility = 'hidden'; return; }
    const f = (1 - Math.exp(-d * 3.2)) / 3.2;
    const x = p.b.x + Math.cos(p.a) * p.v * f, y = p.b.y + Math.sin(p.a) * p.v * f + 180 * d * d;
    const s = p.s0 * E.outBack(clamp(d / .2)) * (1 - E.inCubic(clamp((d - p.life + .4) / .4)));
    S(p.d, { x, y, r: p.vr * d, s });
  });
  CONF.forEach(c => {
    const d = t - c.t0;
    if (d < 0 || d > 3.2) { c.d.style.visibility = 'hidden'; return; }
    let x, y;
    if (c.rain) { x = c.x0 + Math.sin(d * 3 + c.ph) * c.sw; y = -60 + d * (380 + c.v * .2); }
    else {
      const f = (1 - Math.exp(-d * 2.6)) / 2.6;
      x = 540 + Math.cos(c.a) * c.v * f + Math.sin(d * 4 + c.ph) * c.sw * .5; y = 900 + Math.sin(c.a) * c.v * f + 420 * d * d;
    }
    c.d.style.visibility = 'visible';
    c.d.style.opacity = clamp((3.2 - d) / .5);
    c.d.style.transform = 'translate(-50%,-50%) translate3d(' + x.toFixed(1) + 'px,' + y.toFixed(1) + 'px,0) rotate(' + (c.vr * d).toFixed(1) + 'deg) scaleY(' + Math.cos(d * c.fl + c.ph).toFixed(3) + ')';
  });
  SHOCKS.forEach(s => {
    const d = t - s.t;
    if (d < 0 || d > .55) { s.d.style.visibility = 'hidden'; return; }
    const k = d / .55;
    S(s.d, { x: s.x, y: s.y, s: s.k * lerp(.2, 3.4, E.outCubic(k)), o: (1 - k) * .85 });
  });
  GLINTS.forEach(g => {
    const d = t - g.t;
    if (d < 0 || d > .6) { g.d.style.visibility = 'hidden'; return; }
    const s = Math.sin(Math.PI * d / .6);
    S(g.d, { x: g.x, y: g.y, r: d * 160, s: s * 1.1, o: s });
  });

  /* оверлеи: вспышки, затемнение перед дропом */
  let fl = 0;
  for (const [h, a] of [[0.6, .75], [3.6, .35], [4.08, .3], [8.1, .95], [12.62, .35]]) if (t >= h) fl = Math.max(fl, a * Math.exp(-(t - h) * 9));
  el.flash.style.opacity = fl.toFixed(3);
  el.dark.style.opacity = (.55 * E.inQuad(P(t, 7.8, .3)) * (t < 8.1 ? 1 : 0)).toFixed(3);
  el.grain.style.backgroundPosition = ((t * 997) % 256 | 0) + 'px ' + ((t * 613) % 256 | 0) + 'px';
}

window.W = W; window.H = H; window.DURATION = DUR; window.renderAt = renderAt;
window.ready = document.fonts.ready.then(() => Promise.all([...document.images].map(i => i.decode().catch(() => 0)))).then(() => { renderAt(0); return true; });

/* предпросмотр: index.html?t=8.2 — стоп-кадр, без параметра — проигрывание по кругу */
if (!navigator.webdriver) {
  const q = new URLSearchParams(location.search);
  window.ready.then(() => {
    if (q.has('t')) { renderAt(+q.get('t')); return; }
    const t0 = performance.now();
    const loop = () => { renderAt(((performance.now() - t0) / 1000) % DUR); requestAnimationFrame(loop); };
    loop();
  });
}
