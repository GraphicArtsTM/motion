/* Maxway — KLABJON 1+1. Моушн-ролик 1080×1920 (9:16), 30 с.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Темп музыки 120 BPM: доля = 0,5 с, такт = 2 с. Склейки и удары стоят на сетке долей. */
'use strict';

const W = 1080, H = 1920, DUR = 30;
const $ = s => document.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
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
  outBounce: x => { const n = 7.5625, d = 2.75;
    if (x < 1 / d) return n * x * x; if (x < 2 / d) return n * (x -= 1.5 / d) * x + .75;
    if (x < 2.5 / d) return n * (x -= 2.25 / d) * x + .9375; return n * (x -= 2.625 / d) * x + .984375; },
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
/* появление «с пружиной» и затухание */
const pop = (t, t0, d = .38) => E.outBackS(P(t, t0, d));
const env = (t, a, b, fi = .15, fo = .2) => Math.min(P(t, a, fi), 1 - P(t, b - fo, fo));
/* затухающее покачивание после удара */
const wob = (t, t0, f = 9, k = 6) => t < t0 ? 0 : Math.sin((t - t0) * f) * Math.exp(-(t - t0) * k);

function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}

/* ---------- трансформ элемента: (x, y) — центр элемента на кадре ---------- */
function S(el, o) {
  let tr = 'translate(-50%,-50%) translate3d(' + (o.x || 0).toFixed(2) + 'px,' + (o.y || 0).toFixed(2) + 'px,' + (o.z || 0).toFixed(2) + 'px)';
  if (o.rx) tr += ' rotateX(' + o.rx.toFixed(3) + 'deg)';
  if (o.ry) tr += ' rotateY(' + o.ry.toFixed(3) + 'deg)';
  if (o.r) tr += ' rotate(' + o.r.toFixed(3) + 'deg)';
  if (o.sk) tr += ' skewX(' + o.sk.toFixed(3) + 'deg)';
  const sx = o.sx != null ? o.sx : o.s != null ? o.s : 1, sy = o.sy != null ? o.sy : o.s != null ? o.s : 1;
  if (sx !== 1 || sy !== 1) tr += ' scale(' + sx.toFixed(4) + ',' + sy.toFixed(4) + ')';
  el.style.transform = tr;
  const op = o.o == null ? 1 : clamp(o.o);
  el.style.opacity = op;
  el.style.visibility = op <= 0.001 || (sx === 0 && sy === 0) ? 'hidden' : 'visible';
  let f = '';
  if (o.b > .05) f += 'blur(' + o.b.toFixed(2) + 'px) ';
  if (o.f) f += o.f;
  el.style.filter = f || 'none';
  if (window.__rec) window.__rec(el, o);
}
const hide = el => { el.style.visibility = 'hidden'; el.style.opacity = 0; if (window.__rec) window.__rec(el, { o: 0 }); };

/* ---------- иконки интерфейса (линейные, как в приложении) ---------- */
const I = {
  chev: '<path d="m7 10 5 5 5-5"/>',
  srch: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.6-3.6"/>',
  filt: '<path d="M4 5h16l-6 7.5V19l-4 1.5v-8Z" fill="currentColor"/>',
  home: '<path d="M4 10.5 12 4l8 6.5V20H4Z" fill="currentColor" stroke="none"/>',
  bag: '<path d="M5 8h14l-1 12H6Z"/><path d="M9 8V6.5a3 3 0 0 1 6 0V8"/>',
  ord: '<rect x="5" y="3.5" width="14" height="17" rx="2"/><path d="M8.5 8h7M8.5 12h7M8.5 16h4"/>',
  usr: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="10" r="3"/><path d="M6.6 18c1.4-2 3.2-3 5.4-3s4 1 5.4 3"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  trash: '<path d="M5 7h14M10 7V5h4v2M7 7l1 13h8l1-13" fill="currentColor"/>',
  gift: '<rect x="3.5" y="9" width="17" height="11.5" rx="1.5"/><path d="M3 9h18M12 9v11.5"/><path d="M12 9c-1.5-4-6-4.5-6-2s3.5 2 6 2c2.5 0 6 .5 6-2s-4.5-2-6 2Z"/>',
};
const svg = (p, w) => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + (w || 1.8) + '" stroke-linecap="round" stroke-linejoin="round">' + p + '</svg>';

const BOW = id => '<svg viewBox="0 0 200 140"><defs>' +
  '<linearGradient id="' + id + 'a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF5B55"/><stop offset=".55" stop-color="#D51F2A"/><stop offset="1" stop-color="#8E0B16"/></linearGradient>' +
  '<linearGradient id="' + id + 'b" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E8303A"/><stop offset="1" stop-color="#7A0812"/></linearGradient></defs>' +
  '<path d="M94 76 L58 136 L74 128 L84 141 L108 82Z" fill="url(#' + id + 'b)"/>' +
  '<path d="M106 76 L142 136 L126 128 L116 141 L92 82Z" fill="url(#' + id + 'b)"/>' +
  '<path d="M100 70 C 62 16, 6 18, 16 58 C 24 96, 72 92, 100 70 Z" fill="url(#' + id + 'a)"/>' +
  '<path d="M100 70 C 138 16, 194 18, 184 58 C 176 96, 128 92, 100 70 Z" fill="url(#' + id + 'a)"/>' +
  '<path d="M90 66 C 66 40, 34 34, 30 52" fill="none" stroke="rgba(255,190,190,.55)" stroke-width="5" stroke-linecap="round"/>' +
  '<path d="M110 66 C 134 40, 166 34, 170 52" fill="none" stroke="rgba(255,190,190,.55)" stroke-width="5" stroke-linecap="round"/>' +
  '<rect x="86" y="56" width="28" height="30" rx="10" fill="#C3141F"/><rect x="90" y="60" width="9" height="20" rx="4" fill="rgba(255,160,160,.5)"/></svg>';

/* ---------- текст: разбивка на буквы и подгонка ширины ---------- */
function splitChars(el) {
  const out = [];
  [...el.childNodes].forEach(n => {
    if (n.nodeType !== 3) { out.push(n); n.classList.add('ch'); return; }
    const frag = document.createDocumentFragment();
    for (const c of n.textContent) {
      const s = document.createElement('span'); s.className = 'ch'; s.textContent = c === ' ' ? ' ' : c;
      frag.appendChild(s); out.push(s);
    }
    n.replaceWith(frag);
  });
  return out;
}
const fitS = (el, w, max = 9) => Math.min(max, w / el.offsetWidth);

/* ---------- бегущая лента ---------- */
function buildTape(el, txt) {
  const tt = document.createElement('div'); tt.className = 'tt';
  tt.innerHTML = Array(14).fill('<span>' + txt + '</span>').join('');
  el.appendChild(tt); el._tt = tt; el._unit = 0;
}
function tape(el, o, scroll) {
  S(el, o);
  if (!el._unit) el._unit = el._tt.firstChild.offsetWidth;
  el._tt.style.transform = 'translateX(' + (-(((scroll % el._unit) + el._unit) % el._unit) - el._unit).toFixed(1) + 'px)';
}

/* ---------- частицы ---------- */
const CONF_COL = ['#FFD502', '#ffffff', '#7669AF', '#E0312B', '#2DB14B', '#F7923A'];
function makeConf(host, n, seed) {
  const r = rng(seed), arr = [];
  for (let i = 0; i < n; i++) {
    const d = document.createElement('div'); d.className = 'conf';
    d.style.background = CONF_COL[i % CONF_COL.length];
    if (r() < .35) { d.style.width = d.style.height = '20px'; d.style.borderRadius = '50%'; }
    host.appendChild(d);
    const a = -Math.PI / 2 + (r() - .5) * 2.6;
    arr.push({ el: d, vx: Math.cos(a) * (500 + r() * 900), vy: Math.sin(a) * (700 + r() * 1100), spin: (r() - .5) * 1400, flip: 4 + r() * 10, life: 1.1 + r() * .7 });
  }
  return arr;
}
function conf(t, parts, t0, cx, cy) {
  for (const p of parts) {
    const u = t - t0;
    if (u < 0 || u > p.life) { hide(p.el); continue; }
    S(p.el, { x: cx + p.vx * u * .9, y: cy + p.vy * u + 1900 * u * u, r: p.spin * u, sy: Math.cos(u * p.flip), o: 1 - P(u, p.life - .25, .25) });
  }
}
function makeRings(host, n) {
  const a = [];
  for (let i = 0; i < n; i++) { const d = document.createElement('div'); d.className = 'ring'; host.appendChild(d); a.push(d); }
  return a;
}
function rings(t, arr, t0, cx, cy, s1, gap = .08, life = .8) {
  arr.forEach((el, i) => {
    const u = (t - t0 - i * gap) / life;
    if (u < 0 || u > 1) return hide(el);
    S(el, { x: cx, y: cy, s: lerp(.4, s1, E.outCubic(u)), o: (1 - u) * .9 });
  });
}

/* ============================================================
   СЦЕНЫ
   ============================================================ */
const SC = [];
const scene = (id, a, b, fn) => SC.push({ el: $('#' + id), a, b, fn });
let R = {};          // ссылки на элементы, созданные при сборке

/* 1. Хук 0–2 с: КУПИ / ОДИН / ПОЛУЧИ / ДВА — по слову на долю, с контурными эхо */
const W1 = ['КУПИ', 'ОДИН', 'ПОЛУЧИ', 'ДВА'];
function s1(t) {
  const i = Math.min(3, Math.floor(t / .5)), u = t - i * .5;
  const m = R.w1;
  if (m.textContent !== W1[i]) { m.textContent = W1[i]; R.echo.forEach(e => e.textContent = W1[i]); }
  const fs = R.w1fit[i] * (i === 3 ? 1 : 1);
  const s = fs * kf(u, [[0, 1.7], [.17, 1, E.outBack]]) * (i === 3 ? 1 + .08 * P(t, 1.6, .4) : 1);
  const rot = (i % 2 ? 3 : -3) * (1 - E.outExpo(P(u, 0, .35))) + (i === 3 ? wob(t, 1.5, 40, 4) * 1.5 : 0);
  m.style.color = i === 3 ? '#FFD502' : '#fff';
  S(m, { x: 540, y: 960, s, r: rot });
  const spread = kf(u, [[0, .15], [.3, 1]]);
  R.echo.forEach((e, j) => {
    const k = (j >> 1) + 1, dir = j % 2 ? 1 : -1;
    S(e, { x: 540, y: 960 + dir * k * 196 * fs * spread, s, r: rot, o: (1 - k * .26) * P(u, 0, .06), f: i === 3 ? 'url(#olY)' : 'url(#ol)' });
  });
}

/* 2. 1+1 — 2–4 с */
function s2(t) {
  const out = E.inExpo(P(t, 3.55, .45));
  const ps = pop(t, 2.0, .36) * (1 + 7 * out) * (1 + .03 * Math.sin(t * 9) * (1 - out));
  S(R.pill, { x: 540, y: 820 - 120 * out, s: ps, r: -6 + 2 * Math.sin(t * 3) + wob(t, 2.5, 30, 6) * 3, b: out * 18 });
  R.pc.forEach((c, k) => {
    const t0 = 2.0 + k * .25;
    if (k === 1) c.style.transform = 'rotate(' + (180 * (1 - E.outBack(P(t, t0, .3)))).toFixed(1) + 'deg) scale(' + E.outBackS(P(t, t0, .3)).toFixed(3) + ')';
    else c.style.transform = 'translateY(' + kf(t, [[t0, -520], [t0 + .28, 0, E.outBack]]).toFixed(1) + 'px)';
    c.style.opacity = t >= t0 ? 1 : 0;
  });
  [[R.s2a, 2.75, 1230], [R.s2b, 3.0, 1320]].forEach(([el, t0, y]) =>
    S(el, { x: 540, y: y + 80 * (1 - E.outExpo(P(t, t0, .4))) - 300 * out, o: P(t, t0, .12) * (1 - out * 1.5), s: R.fit[el.id] }));
}

/* 3. Раскрытие KLABJON — 4–8 с */
const CALL = [ // точка на фото (px исходника 652×531), подпись, сторона, y подписи, время
  [200, 90, 'Тостер-хлеб', -1, 700, 5.0],
  [520, 205, 'Сыр', 1, 780, 5.25],
  [80, 210, 'Огурчики', -1, 930, 5.5],
  [600, 140, 'Айсберг', 1, 960, 5.75],
  [200, 335, 'Шницель', -1, 1150, 6.0],
  [580, 320, 'Томаты', 1, 1180, 6.25],
  [180, 400, 'Соус клаб', -1, 1360, 6.5],
];
const SAND = { x: 540, y: 1040, w: 600 };
function s3(t) {
  const out = E.inCubic(P(t, 7.55, .45));
  // заголовок по буквам
  R.kch.forEach((c, k) => {
    const t0 = 4.0 + k * .05;
    c.style.transform = 'translateY(' + kf(t, [[t0, -420], [t0 + .34, 0, E.outBack]]).toFixed(1) + 'px) rotate(' + (-18 * (1 - E.outExpo(P(t, t0, .4)))).toFixed(1) + 'deg)';
    c.style.opacity = t >= t0 ? 1 : 0;
  });
  R.kL.style.transform = 'translateX(' + kf(t, [[4.38, 700], [4.75, 0, E.outBack]]).toFixed(1) + 'px) rotate(' + kf(t, [[4.38, 400], [4.8, 0]]).toFixed(1) + 'deg)';
  R.kL.style.opacity = t >= 4.38 ? 1 : 0;
  S(R.kTitle, { x: 540, y: 330 - 500 * out, s: R.fit.kTitle });
  // сэндвич
  const k = E.outBack(P(t, 4.5, .55));
  const fl = Math.sin(t * 2.4) * 10;
  const sy = SAND.y + lerp(1300, 0, k) + fl - 60 * out;
  S(R.kSand, { x: SAND.x, y: sy, r: lerp(28, -2, k) + Math.sin(t * 1.7) * 1.2 + 25 * out, s: lerp(.55, 1, k) * (1 - .9 * out), b: 10 * out });
  S(R.kShadow, { x: SAND.x, y: SAND.y + 255, s: k * (1 - out) * (1 - fl / 120), o: k * .9 });
  // подписи ингредиентов
  const sc = SAND.w / 652;
  CALL.forEach((c, i) => {
    const [px, py, , side, ly, t0] = c, el = R.calls[i], ln = R.lines[i], dot = R.cdots[i];
    const ax = SAND.x + (px - 326) * sc, ay = SAND.y + (py - 265) * sc + fl;
    const lx = side < 0 ? 215 : 865, ex = side < 0 ? lx + el.offsetWidth / 2 - 10 : lx - el.offsetWidth / 2 + 10;
    const tOut = 7.5 - (6 - i) * .03;
    const pin = E.outBack(P(t, t0, .3)) * (1 - E.inCubic(P(t, tOut, .2)));
    const draw = E.outCubic(P(t, t0, .22)) * (1 - P(t, tOut, .15));
    dot.setAttribute('cx', ax); dot.setAttribute('cy', ay); dot.setAttribute('r', (10 * pin).toFixed(1));
    ln.setAttribute('x1', ax); ln.setAttribute('y1', ay);
    ln.setAttribute('x2', lerp(ax, ex, draw)); ln.setAttribute('y2', lerp(ay, ly, draw));
    ln.style.opacity = draw > .01 ? 1 : 0;
    S(el, { x: lx, y: ly + wob(t, t0, 18, 7) * 6, s: E.outBackS(P(t, t0 + .06, .32)) * (1 - E.inCubic(P(t, tOut, .2))), r: side * 2 });
  });
  S(R.kStamp, { x: 890, y: 560, s: pop(t, 6.75, .35) * (1 - out), r: -12 + t * 14 });
  S(R.kRate, { x: 200, y: 560, s: pop(t, 6.85, .35) * (1 - out), r: -5 });
  S(R.kNew, { x: 540, y: 1660 + 60 * (1 - E.outExpo(P(t, 4.75, .4))) + 300 * out, o: P(t, 4.75, .12), s: R.fit.kNew });
}

/* 4. «КЛАБ-СЭНДВИЧ?» зачёркнуто → KLABJON — 8–10 с */
function s4(t) {
  const fall = E.inQuad(P(t, 8.75, .6));
  const lineIn = (t0) => 1 - E.outExpo(P(t, t0, .4));
  S(R.cl0, { x: 540, y: 640 + 40 * lineIn(8.0) + 1300 * fall, o: P(t, 8.0, .1) * (t < 9.45), r: -6 * fall });
  S(R.cl1, { x: 540, y: 820 + 120 * lineIn(8.02) + 1250 * fall, s: R.fit.cl1, o: P(t, 8.02, .1) * (1 - fall * .4) * (t < 9.45), r: 12 * fall });
  S(R.cl2, { x: 540, y: 1000 + 120 * lineIn(8.08) + 1350 * fall, s: R.fit.cl2, o: P(t, 8.08, .1) * (1 - fall * .4) * (t < 9.45), r: -9 * fall });
  const w1 = R.cl1.offsetWidth * R.fit.cl1 + 60, w2 = R.cl2.offsetWidth * R.fit.cl2 + 60;
  R.stk1.style.width = (w1 * E.outCubic(P(t, 8.5, .14))).toFixed(1) + 'px';
  R.stk2.style.width = (w2 * E.outCubic(P(t, 8.62, .14))).toFixed(1) + 'px';
  S(R.stk1, { x: 540 - w1 / 2 * (1 - E.outCubic(P(t, 8.5, .14))), y: 830 + 1250 * fall, r: -3 + 12 * fall, o: t >= 8.5 && t < 9.45 ? 1 : 0 });
  S(R.stk2, { x: 540 - w2 / 2 * (1 - E.outCubic(P(t, 8.62, .14))), y: 1005 + 1350 * fall, r: 2.5 - 9 * fall, o: t >= 8.62 && t < 9.45 ? 1 : 0 });
  const out = E.inExpo(P(t, 9.7, .3));
  const ks = R.fit.kj * kf(t, [[9.0, 2.6], [9.22, 1, E.outBack]]) * (1 + out * 4);
  S(R.kj, { x: 540, y: 900, s: t < 9 ? 0 : ks, r: wob(t, 9.0, 30, 6) * 3, b: out * 14 });
  S(R.alt, { x: 540, y: 1080, s: pop(t, 9.2, .35) * (1 - out), r: -3 });
  S(R.alt2, { x: 540, y: 1200 + 40 * (1 - E.outExpo(P(t, 9.35, .3))), o: P(t, 9.35, .12) * (1 - out) });
}

/* телефон: координаты экрана (логические 390×844) → кадр */
const PH = { x: 540, y: 1010, s: 1.45 };
const ph2f = (lx, ly) => [PH.x + (lx - 195) * PH.s, PH.y + (ly - 422) * PH.s];
function touch(t, keys, taps) {
  // keys: [[t, lx, ly], ...]; taps: [t, ...]
  const x = kf(t, keys.map(k => [k[0], k[1], E.inOutCubic])), y = kf(t, keys.map(k => [k[0], k[2], E.inOutCubic]));
  const vis = env(t, keys[0][0] - .15, keys[keys.length - 1][0] + .5, .15, .2);
  let press = 1, rs = 1, ro = 0;
  for (const tp of taps) {
    if (t >= tp - .08 && t < tp + .5) {
      press = Math.min(press, 1 - .25 * Math.sin(Math.PI * P(t, tp - .08, .22)));
      rs = lerp(.6, 2.6, E.outCubic(P(t, tp, .45))); ro = 1 - P(t, tp, .45);
    }
  }
  R.touch.style.opacity = vis;
  R.touch.style.transform = 'translate(' + x.toFixed(1) + 'px,' + y.toFixed(1) + 'px) scale(' + press.toFixed(3) + ')';
  R.touch.style.setProperty('--rs', rs.toFixed(3)); R.touch.style.setProperty('--ro', ro.toFixed(3));
}

/* 5. Приложение: главная, «Добавить» — 10–14 с */
function s5(t) {
  R.mq.forEach((r, i) => {
    const dir = i % 2 ? 1 : -1;
    r.style.transform = 'translateX(' + ((dir * (t - 10) * 160 - (i % 2 ? 0 : 400)) % r._unit - r._unit).toFixed(1) + 'px)';
  });
  const hs = (t0) => 1 - E.outExpo(P(t, t0, .4));
  const out = E.inExpo(P(t, 13.65, .35));
  S(R.h5a, { x: 540, y: 170 + 90 * hs(10.15) - 400 * out, s: R.fit.h5a, o: P(t, 10.15, .1) });
  S(R.h5b, { x: 540, y: 300 + 90 * hs(10.25) - 400 * out, s: R.fit.h5b, o: P(t, 10.25, .1) });
}
function phoneScene(t) {
  // въезд, лёгкое парение, переход к корзине и выезд
  const inK = E.outExpo(P(t, 10.0, .75));
  let y = lerp(2500, 1060, inK), rx = lerp(38, 0, inK), r = lerp(-16, 0, E.outBack(P(t, 10.0, .9)));
  let s = 1.45;
  let z5 = E.inExpo(P(t, 13.6, .4));               // наезд в конце 5-й сцены
  if (t < 14) { s *= 1 + z5 * 1.6; y -= z5 * 300; }
  else {
    z5 = 0;
    const k = E.outExpo(P(t, 14.0, .5));
    s = lerp(2.4, 1.45, k); y = lerp(1500, 1140, k); rx = 0; r = lerp(8, 0, k);
    const out = E.inExpo(P(t, 17.55, .45));
    y += out * 1600; r += out * 14;
  }
  PH.x = 540; PH.y = y; PH.s = s;
  S(R.phone, { x: 540, y, s, rx: rx + Math.sin(t * 1.1) * 2.5, ry: Math.sin(t * 1.3) * 6, r, b: z5 * 8 });

  // домашний экран — элементы по очереди
  R.hp.forEach((el, i) => {
    const t0 = 10.35 + i * .06;
    el.style.transform = 'translateY(' + (40 * (1 - E.outExpo(P(t, t0, .45)))).toFixed(1) + 'px)';
    el.style.opacity = P(t, t0, .15);
  });
  // нажатие «Акция», затем «Добавить»
  touch(t, [[10.85, 92, 300], [11.0, 92, 283], [11.4, 92, 283], [11.85, 100, 662], [12.0, 100, 662], [12.6, 160, 560]], [11.0, 12.0]);
  if (t >= 14) R.touch.style.opacity = 0;
  const chip = 1 + .12 * Math.sin(Math.PI * P(t, 10.95, .25));
  R.chipA.style.transform = 'scale(' + chip.toFixed(3) + ')';
  const added = P(t, 12.05, .18);
  R.addTxt.style.opacity = 1 - added;
  R.stepper.style.opacity = added;
  R.addBtn.style.transform = 'scale(' + (1 - .08 * Math.sin(Math.PI * P(t, 11.95, .2))).toFixed(3) + ')';
  // полёт товара в корзину по дуге
  const fk = P(t, 12.05, .45), fe = E.inOutCubic(fk);
  if (fk > 0 && fk < 1) {
    const x = lerp(46, 120, fe), y2 = lerp(380, 742, fe) - Math.sin(Math.PI * fk) * 160;
    R.fly.style.opacity = 1;
    R.fly.style.transform = 'translate(' + x.toFixed(1) + 'px,' + y2.toFixed(1) + 'px) scale(' + lerp(1, .3, fe).toFixed(3) + ') rotate(' + (fk * 220).toFixed(1) + 'deg)';
  } else R.fly.style.opacity = 0;
  // бейдж корзины: 1, затем 2 (подарок)
  R.badge.textContent = t >= 13.0 ? '2' : '1';
  const bp = t < 13 ? pop(t, 12.5, .3) : 1 + .35 * Math.sin(Math.PI * P(t, 13.0, .25));
  R.badge.style.opacity = t >= 12.5 ? 1 : 0;
  R.badge.style.transform = 'scale(' + bp.toFixed(3) + ')';

  // корзина
  const sh = E.outExpo(P(t, 14.05, .5));
  R.dim.style.opacity = t >= 14 ? sh : 0;
  R.sheet.style.transform = 'translateY(' + (t >= 14 ? lerp(760, 0, sh) : 760).toFixed(1) + 'px)';
  [[R.r1, 14.3], [R.r2, 14.55]].forEach(([el, t0]) => {
    el.style.opacity = P(t, t0, .12);
    el.style.transform = 'translateX(' + (60 * (1 - E.outExpo(P(t, t0, .4)))).toFixed(1) + 'px)';
  });
  R.r3.style.opacity = P(t, 15.0, .08);
  R.r3.style.transform = 'translateY(' + kf(t, [[15.0, -70], [15.45, 0, E.outBounce]]).toFixed(1) + 'px) scale(' + (1 + .06 * Math.sin(Math.PI * P(t, 15.9, .3))).toFixed(3) + ')';
  R.r3.style.background = 'rgba(255,213,2,' + (.28 * env(t, 15.0, 17.6, .2, .4)).toFixed(3) + ')';
  R.gps.style.transform = 'scaleX(' + (E.outCubic(P(t, 15.25, .2)) * (1 - P(t, 15.5, .1))).toFixed(3) + ')';
  const v = Math.round(lerp(40000, 0, E.inOutCubic(P(t, 15.5, .4))) / 1000) * 1000;
  R.gpv.textContent = (v ? (v / 1000) + ' 000' : '0') + ' сум';
  R.gpv.style.color = t >= 15.9 ? '#2DB14B' : '';
  touch2(t);
  const pay = 1 - .05 * Math.sin(Math.PI * P(t, 16.7, .2));
  R.payBtn.style.transform = 'scale(' + pay.toFixed(3) + ')';
  R.payBtn.style.filter = 'brightness(' + (1 - .15 * Math.sin(Math.PI * P(t, 16.7, .25))).toFixed(3) + ')';
  const okk = P(t, 17.0, .3);
  R.ok.style.opacity = t >= 17 ? Math.min(1, okk * 3) : 0;
  R.ok.style.background = 'rgba(30,20,60,' + (.55 * okk).toFixed(3) + ')';
  R.okc.style.transform = 'scale(' + E.outBackS(okk).toFixed(3) + ')';
}
function touch2(t) {
  if (t < 16.2) return;
  touch(t, [[16.35, 260, 720], [16.75, 250, 793], [17.1, 250, 793]], [16.75]);
}

/* 6. Корзина: подарок за 0 сум — 14–18 с */
function s6(t) {
  const [gx, gy] = ph2f(195, 120 + 340);
  const c = E.inOutCubic(P(t, 15.45, .55));
  S(R.orCirc, { x: gx, y: gy, s: c * 24, o: t >= 15.45 ? 1 : 0 });
  const out = E.inExpo(P(t, 17.55, .4));
  S(R.z1, { x: 540, y: 200 - 300 * out + 60 * (1 - E.outExpo(P(t, 15.55, .4))), s: R.fit.z1, o: P(t, 15.55, .1) });
  const zs = R.fit.z2 * kf(t, [[15.9, 2.2], [16.1, 1, E.outBack]]);
  S(R.z2, { x: 540, y: 380 - 300 * out, s: t < 15.9 ? 0 : zs, r: -3 + wob(t, 15.9, 30, 6) * 3 });
}

/* 7. Один + один в подарок — 18–22 с */
function s7(t) {
  const hero = t >= 20.0;
  const outPair = E.inExpo(P(t, 20.0, .25));
  // первый сэндвич падает, потом расходятся на два
  const drop = E.outBounce(P(t, 18.0, .45));
  const split = E.outExpo(P(t, 18.5, .4));
  const ax = lerp(540, 300, split) - 900 * outPair, bx = lerp(540, 780, split) + 900 * outPair;
  const sy = lerp(-500, 1000, drop) + Math.sin(t * 2.3) * 8;
  const ss = lerp(1, .74, split);
  const squash = 1 - .12 * Math.sin(Math.PI * P(t, 18.38, .16));
  S(R.sA, { x: ax, y: sy, sx: ss / squash, sy: ss * squash, r: -3 * split + 20 * outPair, o: t >= 18 ? 1 : 0, b: outPair * 12 });
  S(R.sB, { x: bx, y: sy, s: ss, r: 3 * split - 20 * outPair, o: t >= 18.5 ? 1 : 0, b: outPair * 12 });
  [R.g1, R.g2, R.g3].forEach((g, i) => {
    const lag = (i + 1) * .035, k = E.outExpo(P(t - lag, 18.5, .4));
    S(g, { x: lerp(540, 780, k), y: sy, s: ss, o: t >= 18.5 && k < .995 && !hero ? .35 - i * .1 : 0 });
  });
  S(R.sh7a, { x: ax, y: 1220, s: drop * ss * (1 - outPair), o: .8 });
  S(R.sh7b, { x: bx, y: 1220, s: split * ss * (1 - outPair), o: .8 });
  // бант падает на второй
  const bk = E.outBounce(P(t, 19.0, .5));
  S(R.bow, { x: bx, y: lerp(-300, sy - 165, bk), r: 6 + wob(t, 19.35, 14, 5) * 8, s: (1 + .15 * wob(t, 19.35, 20, 8)) * (t >= 19 ? 1 : 0) });
  const sw = wob(t, 19.25, 7, 2.2);
  S(R.tag, { x: bx + 60, y: sy + 150, r: -8 + sw * 18, s: pop(t, 19.25, .3) * (1 - outPair) });
  S(R.n1, { x: ax, y: 1360, s: R.fit.n * pop(t, 18.55, .3) * (1 - outPair) });
  S(R.n2, { x: bx, y: 1360, s: R.fit.n * pop(t, 18.7, .3) * (1 - outPair) });
  // текст сверху
  const tOut = E.inExpo(P(t, 19.85, .2));
  S(R.t7a, { x: 540, y: 300 + 80 * (1 - E.outExpo(P(t, 19.5, .35))) - 800 * tOut, s: R.fit.t7a * kf(t, [[19.5, 1.5], [19.7, 1, E.outBack]]), o: P(t, 19.5, .08) });
  S(R.t7b, { x: 540, y: 460 + 80 * (1 - E.outExpo(P(t, 19.75, .35))) - 800 * tOut, s: R.fit.t7b * kf(t, [[19.75, 1.5], [19.95, 1, E.outBack]]), o: P(t, 19.75, .08) });
  // ключевой визуал с баннера
  const out = E.inExpo(P(t, 21.55, .45));
  const hk = E.outExpo(P(t, 20.0, .5));
  const hy = 1150 + Math.sin(t * 2) * 8;
  S(R.hero, { x: 540, y: hy + 900 * out, s: hero ? lerp(1.7, 1, hk) : 0, o: P(t, 20.0, .08), r: 6 * out });
  S(R.heroPill, { x: 540 + (208 - 564.5) * .8, y: hy + (985 - 570) * .8 + 900 * out, s: pop(t, 20.3, .35), r: wob(t, 20.3, 20, 5) * 6 });
  S(R.h7, { x: 540, y: 330 - 500 * out + 100 * (1 - E.outExpo(P(t, 20.1, .4))), s: R.fit.h7, o: P(t, 20.1, .1) });
  S(R.h7s, { x: 540, y: 520 - 500 * out + 80 * (1 - E.outExpo(P(t, 20.35, .4))), o: P(t, 20.35, .12) });
}

/* 8. Доставка 40 минут — 22–25 с */
const ROUTE = 'M150 940 H390 V700 H650 V440 H880 V230';
function s8(t) {
  const out = E.inExpo(P(t, 24.6, .4));
  const k = E.outExpo(P(t, 22.0, .6));
  const mx = 540, my = 1190;
  S(R.map, { x: mx, y: my + lerp(900, 0, k) - 100 * out, s: lerp(.8, 1, k) * (1 + 2.5 * out), r: lerp(10, -4, k) + Math.sin(t) * .6, b: out * 10 });
  // маршрут
  const L = R.routeLen, d = E.inOutCubic(P(t, 22.7, 1.0));
  R.route.style.strokeDashoffset = (L * (1 - d)).toFixed(1);
  R.routeBg.style.strokeDashoffset = (L * (1 - d)).toFixed(1);
  const p = R.routeEl.getPointAtLength(L * d);
  R.courier.style.transform = 'translate(' + p.x.toFixed(1) + 'px,' + p.y.toFixed(1) + 'px) translate(-50%,-50%) scale(' + (E.outBackS(P(t, 22.6, .3)) * (1 - P(t, 23.75, .15))).toFixed(3) + ')';
  // пины
  const pinH = (t0) => kf(t, [[t0, -420], [t0 + .45, 0, E.outBounce]]);
  R.pinStore.style.transform = 'translate(150px,' + (940 + pinH(22.35)).toFixed(1) + 'px) translate(-50%,-50%)';
  R.pinStore.style.opacity = t >= 22.35 ? 1 : 0;
  R.pinHome.style.transform = 'translate(880px,' + (230 + pinH(22.5)).toFixed(1) + 'px) translate(-50%,-100%) scale(' + (1 + .15 * Math.sin(Math.PI * P(t, 23.7, .3))).toFixed(3) + ')';
  R.pinHome.style.opacity = t >= 22.5 ? 1 : 0;
  R.bubble.style.transform = 'translate(700px,110px) translate(-50%,-50%) scale(' + E.outBackS(P(t, 23.75, .35)).toFixed(3) + ')';
  rings(t, R.mapRings, 23.7, 880, 230, 1.6, .1, .8);
  // счётчик
  const n = Math.round(lerp(0, 40, E.outCubic(P(t, 22.4, .9))));
  R.m40.textContent = n + ' МИН';
  S(R.m40, { x: 540, y: 300 - 400 * out + 80 * (1 - E.outExpo(P(t, 22.3, .4))), s: R.fit.m40 * (1 + .08 * Math.sin(Math.PI * P(t, 23.3, .25))), o: P(t, 22.3, .1) });
  S(R.m40s, { x: 540, y: 470 - 400 * out + 60 * (1 - E.outExpo(P(t, 22.6, .4))), o: P(t, 22.6, .12) });
}

/* 9. Финал — 25–30 с */
function s9(t) {
  const ls = kf(t, [[25.0, 3.2], [25.3, 1, E.outExpo]]) * (1 + .02 * Math.sin(t * 3));
  S(R.logo, { x: 540, y: 520, s: ls, b: 20 * (1 - E.outExpo(P(t, 25, .3))), r: wob(t, 25.3, 25, 6) * 2 });
  rings(t, R.rings9, 25.15, 540, 520, 9, .09, .9);
  R.fch.forEach((c, k) => {
    const t0 = 25.5 + k * .04;
    c.style.transform = 'translateY(' + kf(t, [[t0, 260], [t0 + .35, 0, E.outBack]]).toFixed(1) + 'px)';
    c.style.opacity = P(t, t0, .08);
  });
  R.fL.style.transform = 'scale(' + E.outBackS(P(t, 25.8, .35)).toFixed(3) + ') rotate(' + (360 * (1 - E.outExpo(P(t, 25.8, .5)))).toFixed(1) + 'deg)';
  S(R.fT, { x: 540, y: 900, s: R.fit.fT });
  S(R.fPill, { x: 540, y: 1075, s: pop(t, 25.9, .35), r: -5 + Math.sin(t * 2.4) * 2 });
  const sk = (t0) => E.outBack(P(t, t0, .45));
  const fy = 1365 + Math.sin(t * 2.2) * 8;
  S(R.fSa, { x: 375, y: lerp(2300, fy, sk(26.0)), r: -6 });
  S(R.fSb, { x: 705, y: lerp(2300, fy, sk(26.1)), r: 6 });
  S(R.fSh, { x: 540, y: 1530, s: sk(26.0), o: .5 });
  const bk = E.outBounce(P(t, 26.4, .5));
  S(R.fBow, { x: 715, y: lerp(-200, fy - 125, bk), s: .55 * (t >= 26.4 ? 1 : 0), r: 8 + wob(t, 26.75, 14, 5) * 8 });
  const press = 1 - .06 * Math.sin(Math.PI * P(t, 27.2, .22));
  S(R.cta, { x: 540, y: 1680, s: pop(t, 26.6, .4) * press * (1 + .015 * Math.sin(t * 6) * P(t, 27.6, .3)) });
  R.cta.style.background = t > 27.2 && t < 27.45 ? '#FFD502' : '#fff';
  S(R.url, { x: 540, y: 1800 + 40 * (1 - E.outExpo(P(t, 26.9, .4))), o: P(t, 26.9, .15) });
  S(R.note, { x: 540, y: 1856, o: P(t, 27.1, .2) * .9 });
}

/* ---------- фон, ленты, шторки, камера ---------- */
const BG = [[0, '#7669AF'], [2, '#ED6B2F'], [8, '#F7F5FC'], [10, '#FFD502'], [14, '#7669AF'], [18, '#ED6B2F'], [22, '#5D4F9E'], [25, '#7669AF']];
const DOTS = [[0, .16], [2, .14], [8, .5], [10, .22], [14, .14], [18, .14], [22, .12], [25, .14]];
function bgAt(t, arr) { let v = arr[0][1]; for (const [a, c] of arr) if (t >= a) v = c; return v; }

/* шторки-переходы: центр, цвета полос */
const WIPES = [[4.0, ['#7669AF', '#FFD502', '#fff']], [8.0, ['#7669AF', '#FFD502', '#ED6B2F']], [10.0, ['#ED6B2F', '#7669AF', '#fff']],
  [14.0, ['#FFD502', '#ED6B2F', '#fff']], [18.0, ['#FFD502', '#7669AF', '#fff']], [22.0, ['#7669AF', '#FFD502', '#ED6B2F']]];
function wipe(t) {
  let w = null;
  for (const x of WIPES) if (t > x[0] - .3 && t < x[0] + .3) w = x;
  if (!w) { R.wb.forEach(hide); return; }
  const k = (t - (w[0] - .26)) / .52;
  const base = lerp(-1300, 2900, E.inOutCubic(clamp(k)));
  R.wb.forEach((el, i) => {
    el.style.background = w[1][i];
    const off = i === 0 ? 0 : i === 1 ? -1100 : -1290;
    S(el, { x: base + off + (i ? 0 : 0), y: 960, r: 14, o: 1 });
  });
}

function background(t) {
  R.bg.style.background = bgAt(t, BG);
  const dark = t >= 8 && t < 10;
  R.dots.style.backgroundImage = 'radial-gradient(circle,' + (dark ? '#7669AF' : (t >= 10 && t < 14 ? '#ffffff' : '#ffffff')) + ' 2.6px,transparent 3.2px)';
  R.dots.style.opacity = bgAt(t, DOTS);
  R.dots.style.transform = 'translate(' + ((t * 18) % 60).toFixed(1) + 'px,' + ((t * 30) % 60).toFixed(1) + 'px)';
  // лучи: сцены 2, 7 и 9
  let ro = 0;
  if (t >= 2 && t < 4) ro = .9 * P(t, 2.0, .3);
  else if (t >= 18 && t < 22) ro = .7 * P(t, 18.0, .4);
  else if (t >= 25) ro = .45 * P(t, 25.0, .4);
  const ry = t < 4 ? 820 : t < 22 ? 1100 : 520;
  S(R.rays, { x: 540, y: ry, r: t * 14, o: ro });
  // ленты (текст меняем до расчёта прокрутки, чтобы кадр не зависел от предыдущих)
  if (t >= 24 && R.tapeB._txt !== 2) { R.tapeB._tt.innerHTML = Array(10).fill('<span>*Акция действует только на доставку ✦</span>').join(''); R.tapeB._unit = 0; R.tapeB._txt = 2; }
  if (t < 24 && R.tapeB._txt !== 1) { R.tapeB._tt.innerHTML = Array(14).fill('<span>KLABJON L ✦ ВТОРОЙ В ПОДАРОК ✦</span>').join(''); R.tapeB._unit = 0; R.tapeB._txt = 1; }
  if (t >= 2 && t < 4) {
    const k = E.outExpo(P(t, 2.0, .4)), o = 1 - E.inExpo(P(t, 3.6, .35));
    tape(R.tapeA, { x: 540 - 1600 * (1 - k) - 1600 * (1 - o), y: 300, r: -8, o: 1 }, t * 260);
    tape(R.tapeB, { x: 540 + 1600 * (1 - k) + 1600 * (1 - o), y: 1610, r: 6, o: 1 }, -t * 260);
  } else if (t >= 24 && t < 25) {
    const k = E.outExpo(P(t, 24.0, .4));
    hide(R.tapeA);
    tape(R.tapeB, { x: 540 + 1600 * (1 - k), y: 1780, r: -4, o: 1 }, t * 220);
  } else { hide(R.tapeA); hide(R.tapeB); }

  // вспышки на сильных ударах
  const FL = [[2.0, .55], [4.0, .35], [9.0, .3], [15.9, .25], [20.0, .45], [25.0, .7]];
  let f = 0;
  for (const [a, v] of FL) if (t >= a) f = Math.max(f, v * (1 - P(t, a, .25)));
  R.flash.style.opacity = f;
  // HUD
  const light = (t >= 8 && t < 14);
  R.hud.style.color = light ? '#2D245F' : '#fff';
  R.hud.style.opacity = env(t, .15, 25.0, .3, .3);
  R.hudT.textContent = '00:' + String(Math.floor(t)).padStart(2, '0');
}

/* удары камеры: доли в грув-частях + отдельные «слэмы» */
const SLAMS = [[0, 1], [.5, 1], [1, 1], [1.5, 1.4], [2.0, 2.2], [4.0, 1.2], [9.0, 2], [12.0, .6], [15.9, 1.2], [18.36, 1.2], [19.35, .8], [20.0, 1.6], [22.85, .5], [25.0, 2.4], [25.3, 1]];
function camera(t, frame) {
  let s = 1, x = 0, y = 0, r = 0;
  const groove = (t >= 4 && t < 8) || (t >= 10 && t < 22) || (t >= 25.5 && t < 28);
  if (groove) { const u = (t % .5); s += .014 * Math.exp(-u * 12); }
  const rr = rng(frame * 7 + 3);
  for (const [a, amp] of SLAMS) {
    const u = t - a;
    if (u >= 0 && u < .4) {
      const e = Math.exp(-u * 11) * amp;
      s += .03 * e; x += (rr() - .5) * 26 * e; y += (rr() - .5) * 26 * e; r += (rr() - .5) * 1.2 * e;
    }
  }
  window.__cam = { x, y, r, s };   // для экспорта в After Effects (ae/export.mjs)
  R.cam.style.transform = 'translate(' + x.toFixed(2) + 'px,' + y.toFixed(2) + 'px) rotate(' + r.toFixed(3) + 'deg) scale(' + s.toFixed(4) + ')';
  R.grain.style.backgroundPosition = Math.floor(rr() * 256) + 'px ' + Math.floor(rr() * 256) + 'px';
}

function render(t, frame) {
  if (frame == null) frame = Math.round(t * 60);
  const phOn = t >= 10 && t < 18.1;
  R.phL.style.display = phOn ? 'block' : 'none';
  if (phOn) phoneScene(t);
  for (const s of SC) {
    const on = t >= s.a && t < s.b;
    s.el.style.display = on ? 'block' : 'none';
    if (on) s.fn(t);
  }
  ovl(t);
  background(t);
  wipe(t);
  camera(t, frame);
}

/* наклейки поверх телефона */
function ovl(t) {
  const o5 = 1 - E.inExpo(P(t, 13.6, .3));
  S(R.st40, { x: 215, y: 820, s: t < 14 ? pop(t, 11.55, .35) * o5 : 0, r: -9 + wob(t, 11.55, 16, 6) * 4 });
  S(R.stGift, { x: 820, y: 1380, s: t < 14 ? pop(t, 13.0, .35) * o5 : 0, r: 7 + wob(t, 13.0, 16, 6) * 4 });
  const o6 = 1 - E.inExpo(P(t, 17.5, .3));
  S(R.stSave, { x: 600, y: 650, s: t >= 14 && t < 18 ? pop(t, 16.1, .35) * o6 : 0, r: 6 + wob(t, 16.1, 16, 6) * 4 });
  const [gx, gy] = ph2f(195, 120 + 300);
  if (t >= 15 && t < 17) conf(t, R.conf, 15.05, gx, gy); else R.conf.forEach(p => hide(p.el));
  if (t >= 15.9 && t < 18) conf(t, R.conf2, 15.95, 540, 420); else R.conf2.forEach(p => hide(p.el));
}

/* ---------- сборка ---------- */
async function init() {
  const ids = ['bg', 'dots', 'rays', 'cam', 'w1', 'pill', 's2a', 's2b', 'kTitle', 'kSand', 'kShadow', 'kStamp', 'kRate', 'kNew', 'cl0', 'cl1', 'cl2', 'stk1', 'stk2', 'kj', 'alt', 'alt2',
    'h5a', 'h5b', 'orCirc', 'z1', 'z2', 't7a', 't7b', 'h7', 'h7s', 'hero', 'heroPill', 'sh7a', 'sh7b', 'g1', 'g2', 'g3', 'sA', 'sB', 'bow', 'tag', 'n1', 'n2',
    'm40', 'm40s', 'map', 'logo', 'fT', 'fPill', 'fSh', 'fSa', 'fSb', 'fBow', 'cta', 'url', 'note', 'phL', 'phone', 'touch', 'chipA', 'addBtn', 'addTxt', 'stepper',
    'fly', 'badge', 'dim', 'sheet', 'r1', 'r2', 'r3', 'gps', 'gpv', 'payBtn', 'ok', 'st40', 'stGift', 'stSave', 'tapeA', 'tapeB', 'flash', 'grain', 'hud', 'hudT'];
  ids.forEach(id => R[id] = $('#' + id));
  R.wb = $$('.wb'); R.okc = $('#ok .okc'); R.hp = $$('#home .hp');
  $$('.ic').forEach(el => { const k = [...el.classList].find(c => I[c]); if (k) el.innerHTML = svg(I[k], k === 'filt' || k === 'home' ? 1.4 : 1.8); });
  R.bow.innerHTML = BOW('b1'); R.fBow.innerHTML = BOW('b2');

  // эхо-слова хука
  R.echo = [];
  for (let j = 0; j < 6; j++) { const e = document.createElement('div'); e.className = 'a big outline'; $('#sc1').insertBefore(e, R.w1); R.echo.push(e); }
  R.pc = $$('#pill .pc');
  // буквы заголовков
  const lb = $('#kTitle .badgeL'); R.kL = lb; lb.textContent = 'L';
  R.kch = splitChars(R.kTitle).filter(c => c !== lb);
  const fl = $('#fT .badgeL'); R.fL = fl;
  R.fch = splitChars(R.fT).filter(c => c !== fl);
  // подписи и линии
  R.calls = []; R.lines = []; R.cdots = [];
  const NS = 'http://www.w3.org/2000/svg';
  CALL.forEach(c => {
    const d = document.createElement('div'); d.className = 'a call'; d.innerHTML = '<i></i>' + c[2]; $('#sc3').appendChild(d); R.calls.push(d);
    const ln = document.createElementNS(NS, 'line'); $('#kLines').appendChild(ln); R.lines.push(ln);
    const dt = document.createElementNS(NS, 'circle'); $('#kLines').appendChild(dt); R.cdots.push(dt);
  });
  // маркиза
  R.mq = [];
  for (let i = 0; i < 6; i++) {
    const r = document.createElement('div'); r.className = 'mrow'; r.style.top = (430 + i * 245) + 'px';
    r.innerHTML = Array(8).fill(i % 2 ? 'KLABJON ✦ ' : 'ЗАКАЖИ ✦ ').join('');
    $('#mq').appendChild(r); R.mq.push(r);
  }
  // ленты
  buildTape(R.tapeA, 'АКЦИЯ ✦ 1+1 ✦ KLABJON ✦'); buildTape(R.tapeB, 'KLABJON L ✦ ВТОРОЙ В ПОДАРОК ✦'); R.tapeB._txt = 1;
  // конфетти и кольца
  R.conf = makeConf($('#conf'), 46, 11); R.conf2 = makeConf($('#conf'), 40, 23);
  R.rings9 = makeRings($('#rings9'), 3);
  buildMap();

  // зерно плёнки
  const cv = document.createElement('canvas'); cv.width = cv.height = 256;
  const cx = cv.getContext('2d'), id = cx.createImageData(256, 256), r = rng(5);
  for (let i = 0; i < id.data.length; i += 4) { const v = r() * 255; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255; }
  cx.putImageData(id, 0, 0); R.grain.style.backgroundImage = 'url(' + cv.toDataURL() + ')';

  await document.fonts.ready;
  await Promise.all($$('img').map(i => i.decode().catch(() => {})));
  for (const s of SC) s.el.style.display = 'block';
  R.phL.style.display = 'block';
  R.mq.forEach(r => r._unit = r.scrollWidth / 8);
  // подгонка ширины крупного текста
  R.fit = {};
  const meas = document.createElement('div'); meas.className = 'a big'; meas.style.visibility = 'hidden'; document.body.appendChild(meas);
  R.w1fit = W1.map(w => { meas.textContent = w; return Math.min(1.5, 960 / meas.offsetWidth); });
  meas.textContent = '40 МИН'; R.fit.m40 = Math.min(1, 900 / meas.offsetWidth);
  meas.remove();
  const fit = (el, w, max = 9) => { R.fit[el.id] = fitS(el, w, max); };
  fit(R.s2a, 960, 1); fit(R.s2b, 960, 1); fit(R.kTitle, 960); fit(R.kNew, 960, 1);
  fit(R.cl1, 900); fit(R.cl2, 960); fit(R.kj, 960); fit(R.h5a, 940); fit(R.h5b, 960);
  fit(R.z1, 700); fit(R.z2, 940); fit(R.t7a, 900); fit(R.t7b, 960); fit(R.h7, 900); fit(R.fT, 860);
  R.fit.n = 1;
  for (const s of SC) s.el.style.display = 'none';
}

function buildMap() {
  const r = rng(42), NS = 'http://www.w3.org/2000/svg';
  const VX = [150, 390, 650, 880], HY = [230, 440, 700, 940];
  let h = '<svg viewBox="0 0 1000 1100" width="1000" height="1100">';
  h += '<rect width="1000" height="1100" fill="#E4E0F0"/>';
  h += '<path d="M-40 640 C 200 560, 300 760, 520 600 S 860 520, 1040 380" fill="none" stroke="#C9DDF4" stroke-width="70"/>';
  // кварталы и дома
  const xs = [-60, ...VX, 1060], ys = [-60, ...HY, 1160];
  for (let i = 0; i < xs.length - 1; i++) for (let j = 0; j < ys.length - 1; j++) {
    const x0 = xs[i] + 30, x1 = xs[i + 1] - 30, y0 = ys[j] + 30, y1 = ys[j + 1] - 30;
    if (r() < .14) { h += '<rect x="' + x0 + '" y="' + y0 + '" width="' + (x1 - x0) + '" height="' + (y1 - y0) + '" rx="18" fill="#CFE7D3"/>'; continue; }
    const n = 2 + Math.floor(r() * 3);
    for (let k = 0; k < n; k++) {
      const w = 40 + r() * (x1 - x0 - 50) * .5, hh = 40 + r() * (y1 - y0 - 50) * .5;
      const x = x0 + r() * Math.max(1, x1 - x0 - w), y = y0 + r() * Math.max(1, y1 - y0 - hh);
      h += '<rect x="' + x.toFixed(0) + '" y="' + y.toFixed(0) + '" width="' + w.toFixed(0) + '" height="' + hh.toFixed(0) + '" rx="8" fill="#D2CCE6"/>';
    }
  }
  VX.forEach(x => h += '<rect x="' + (x - 17) + '" y="-20" width="34" height="1140" fill="#fff"/>');
  HY.forEach(y => h += '<rect x="-20" y="' + (y - 17) + '" width="1040" height="34" fill="#fff"/>');
  h += '<path d="M-40 1060 L 1040 120" stroke="#fff" stroke-width="44"/><path d="M-40 1060 L 1040 120" stroke="#F3E6B8" stroke-width="6" stroke-dasharray="24 22"/>';
  h += '<path id="routeBg" d="' + ROUTE + '" fill="none" stroke="#fff" stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/>';
  h += '<path id="route" d="' + ROUTE + '" fill="none" stroke="#7669AF" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"/>';
  h += '</svg>';
  h += '<div class="pin" id="pinStore" style="width:120px;height:120px;border-radius:50%;background:#7669AF;border:8px solid #fff;display:flex;align-items:center;justify-content:center;box-shadow:0 10px 20px rgba(40,20,80,.3)"><img src="assets/logo.png" style="width:78px"></div>';
  h += '<div class="pin" id="pinHome"><svg width="96" height="130" viewBox="0 0 60 80"><path d="M30 2C14.5 2 3 13.5 3 29c0 20 27 49 27 49s27-29 27-49C57 13.5 45.5 2 30 2Z" fill="#EF4B43"/><circle cx="30" cy="29" r="10" fill="#fff"/></svg></div>';
  h += '<div class="pin" id="courier" style="width:76px;height:76px;border-radius:50%;background:#FFD502;border:6px solid #fff;display:flex;align-items:center;justify-content:center;color:#3A1A0C;box-shadow:0 8px 16px rgba(40,20,80,.3)">' + svg(I.bag, 2.2).replace('<svg ', '<svg width="38" height="38" ') + '</div>';
  h += '<div class="bubble" id="bubble">Время доставки <b>40 мин</b></div>';
  h += '<div id="mapRings"></div>';
  R.map.innerHTML = h;
  R.route = $('#route'); R.routeBg = $('#routeBg'); R.routeEl = R.route;
  R.routeLen = R.route.getTotalLength();
  [R.route, R.routeBg].forEach(p => { p.style.strokeDasharray = R.routeLen; });
  R.pinStore = $('#pinStore'); R.pinHome = $('#pinHome'); R.courier = $('#courier'); R.bubble = $('#bubble');
  R.mapRings = makeRings($('#mapRings'), 2);
  R.mapRings.forEach(el => { el.style.borderColor = '#EF4B43'; el.style.borderWidth = '6px'; });
}

scene('sc1', 0, 2.0, s1);
scene('sc2', 2.0, 4.0, s2);
scene('sc3', 4.0, 8.0, s3);
scene('sc4', 8.0, 10.0, s4);
scene('sc5', 10.0, 14.0, s5);
scene('sc6', 14.0, 18.0, s6);
scene('sc7', 18.0, 22.0, s7);
scene('sc8', 22.0, 25.0, s8);
scene('sc9', 25.0, 30.01, s9);

window.DURATION = DUR;
window.renderAt = (t, f) => render(Math.min(t, DUR - 1e-4), f);
window.ready = init().then(() => {
  const q = new URLSearchParams(location.search);
  if (q.has('t')) { render(+q.get('t')); return; }
  if (navigator.webdriver) { render(0); return; }
  const start = performance.now();
  (function loop(now) { render(((now - start) / 1000) % DUR); requestAnimationFrame(loop); })(start);
});
