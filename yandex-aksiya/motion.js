/* Yandex Go taksopark — «Brend ruxsatnoma aksiyada», Instagram Reels 1080×1920, 30 с.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Тайминги привязаны к словам озвучки, разложенной по сценам с паузами (voice.py),
   разметка слов — Whisper, см. README. */
'use strict';

const W = 1080, H = 1920;
/* Вставка «галереи брендирования» после сцены с ценой: основной таймлайн (старое время)
   идёт до TA, затем G секунд галерея, затем основной таймлайн продолжается с RESUME. */
const TA = 8.3, G = 6.5, RESUME = 8.6, SH = TA + G - RESUME, DUR = 30 + SH;   // 36,2 с
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
  inOutQuart: x => x < .5 ? 8 * x * x * x * x : 1 - Math.pow(-2 * x + 2, 4) / 2,
  outQuint: x => 1 - Math.pow(1 - x, 5),
  outExpo: x => x >= 1 ? 1 : 1 - Math.pow(2, -10 * x),
  inExpo: x => x <= 0 ? 0 : Math.pow(2, 10 * x - 10),
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
/* затухающее колебание после удара в момент h */
const wob = (t, h, amp, freq = 18, damp = 7) => t < h ? 0 : amp * Math.exp(-(t - h) * damp) * Math.sin((t - h) * freq);

function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}

/* ---------- трансформ элемента: (x, y) — центр элемента на кадре ---------- */
function S(el, o) {
  let tr = 'translate(-50%,-50%) translate(' + (o.x || 0).toFixed(2) + 'px,' + (o.y || 0).toFixed(2) + 'px)';
  if (o.r) tr += ' rotate(' + o.r.toFixed(3) + 'deg)';
  if (o.sk) tr += ' skewX(' + o.sk.toFixed(3) + 'deg)';
  const sx = o.sx != null ? o.sx : o.s != null ? o.s : 1, sy = o.sy != null ? o.sy : o.s != null ? o.s : 1;
  if (sx !== 1 || sy !== 1) tr += ' scale(' + sx.toFixed(4) + ',' + sy.toFixed(4) + ')';
  el.style.transform = tr;
  const op = o.o == null ? 1 : clamp(o.o);
  el.style.opacity = op;
  el.style.visibility = op <= 0.001 ? 'hidden' : 'visible';
  el.style.filter = o.b > .05 ? 'blur(' + o.b.toFixed(2) + 'px)' : 'none';
}
/* трансформ для вложенных элементов (буквы, частицы) */
function T(el, tr, op) {
  el.style.transform = tr;
  if (op != null) { el.style.opacity = clamp(op); el.style.visibility = op <= 0.001 ? 'hidden' : 'visible'; }
}

/* ---------- сборка ---------- */
const R = {};

function splitChars(el) {
  const txt = el.textContent;
  el.textContent = '';
  const out = [];
  for (const c of txt) {
    const s = document.createElement('span');
    if (c === ' ') { s.className = 'sp'; el.appendChild(s); continue; }
    s.className = 'ch'; s.textContent = c; el.appendChild(s); out.push(s);
  }
  return out;
}

function fit(el, maxW) {
  let fs = parseFloat(getComputedStyle(el).fontSize);
  while (el.scrollWidth > maxW && fs > 10) { fs -= 1; el.style.fontSize = fs + 'px'; }
}

const WATCH = `<svg viewBox="0 0 280 310">
  <rect x="122" y="6" width="36" height="26" rx="6" fill="#FFD80D"/><rect x="132" y="28" width="16" height="20" fill="#FFD80D"/>
  <g transform="rotate(42 140 170)"><rect x="128" y="22" width="24" height="18" rx="5" fill="#FFD80D"/></g>
  <circle cx="140" cy="170" r="128" fill="#1b1b1b" stroke="#FFD80D" stroke-width="10"/>
  <circle cx="140" cy="170" r="104" fill="none" stroke="#333" stroke-width="20"/>
  <circle class="prog" cx="140" cy="170" r="104" fill="none" stroke="#FFD80D" stroke-width="20" stroke-linecap="round" transform="rotate(-90 140 170)"/>
  <g class="ticks"></g>
  <g class="hand"><path d="M140 170 L140 86" stroke="#fff" stroke-width="9" stroke-linecap="round"/></g>
  <circle cx="140" cy="170" r="13" fill="#FFD80D" stroke="#111" stroke-width="4"/>
</svg>`;

function makeParts(box, n, seed, colors) {
  const r = rng(seed), out = [];
  for (let i = 0; i < n; i++) {
    const el = document.createElement('div');
    el.className = 'pt';
    const sz = 14 + r() * 30, kind = r();
    el.style.width = sz + 'px';
    el.style.height = (kind < .35 ? sz * .45 : sz) + 'px';
    el.style.borderRadius = kind > .7 ? '50%' : '4px';
    el.style.background = colors[Math.floor(r() * colors.length)];
    box.appendChild(el);
    out.push({ el, a: r() * Math.PI * 2, v: 500 + r() * 1000, spin: (r() - .5) * 900, life: 1.1 + r() * .7, sz });
  }
  return out;
}
function drawParts(ps, t, t0, cx, cy, grav = 1600) {
  const k = t - t0;
  for (const p of ps) {
    if (k < 0 || k > p.life) { T(p.el, 'translate(-999px,-999px)', 0); continue; }
    const d = p.v * (1 - Math.exp(-k * 3.2)) / 3.2;
    const x = cx + Math.cos(p.a) * d, y = cy + Math.sin(p.a) * d + grav * k * k * .5;
    T(p.el, `translate(${(x - p.sz / 2).toFixed(1)}px,${(y - p.sz / 2).toFixed(1)}px) rotate(${(p.spin * k).toFixed(1)}deg)`, 1 - Math.pow(k / p.life, 3));
  }
}
function makeRays(box, n, color) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const el = document.createElement('div'); el.className = 'ray'; el.style.background = color;
    box.appendChild(el); out.push({ el, a: i / n * 360 + (i % 2) * 6, len: i % 2 ? .7 : 1 });
  }
  return out;
}
function drawRays(rs, t, t0, r0 = 150) {
  const k = P(t, t0, .45);
  for (const r of rs) {
    const on = t >= t0 && k < 1;
    const d = r0 + 220 * E.outCubic(k), sc = (1 - k) * r.len;
    T(r.el, `translate(-6px,-110px) rotate(${r.a}deg) translateY(${-d}px) scaleY(${sc.toFixed(3)})`, on ? 1 : 0);
  }
}
function makeSpeed(box, n, seed, color) {
  const r = rng(seed), out = [];
  for (let i = 0; i < n; i++) {
    const el = document.createElement('div');
    el.className = 'pt';
    const w = 160 + r() * 260;
    el.style.cssText += `width:${w}px;height:${6 + r() * 6}px;border-radius:6px;background:${color}`;
    box.appendChild(el); out.push({ el, y: r() * 240, ph: r(), w, sp: 1 + r() * .8 });
  }
  return out;
}
function drawSpeed(ls, t, cx, cy, amt) {
  for (const l of ls) {
    const x = cx - 300 - ((t * 2400 * l.sp + l.ph * 900) % 900);
    T(l.el, `translate(${x.toFixed(1)}px,${(cy - 120 + l.y).toFixed(1)}px)`, amt * clamp((x - cx + 1100) / 300));
  }
}

/* ---------- брендированная машина (фото-вырезка) ---------- */
function drawCar(el, t, x, y, tilt, sc = 1) {
  const bob = Math.sin(t * 31) * 1.2 + Math.sin(t * 17) * .8;
  S(el, { x, y: y + bob, r: tilt, s: sc });
}

/* ---------- сцены ---------- */
const scenes = [];
function scene(id, t0, t1, fn) { scenes.push({ el: $('#' + id), t0, t1, fn }); }

/* Безопасная зона Reels: сверху ~220 px (шапка приложения), снизу ~420 px (подпись, кнопки),
   справа ~120 px на высоте 1050–1700 (лайк/коммент/репост). Весь текст — в y 300…1450,
   а то, что ниже y 1050, центрируется по CX2 и не шире 860 px. */
const CX = 540, CX2 = 520;

/* удары камеры: [момент, сила] — мягкие, только на ключевых акцентах */
const HITS = [[2.3, 8], [5.78, 11], [6.32, 5], [10.3, 6], [16.72, 8], [18.45, 8], [19.48, 10], [22.85, 6], [26.85, 8]];
const FLASH = [[2.3, .18], [5.78, .28], [18.45, .25], [26.85, .18]];

/* удары галереи — в реальном времени */
const HITS_G = [[TA + 1.1, 5], [TA + 2.15, 5], [TA + 3.2, 5], [TA + 4.25, 5], [TA + 5.3, 5]];

function camera(t, to) {
  let x = 0, y = 0, r = 0;
  const hits = to == null ? HITS_G : HITS;
  if (to != null) t = to;
  for (const [h, a] of hits) {
    if (t < h || t > h + .8) continue;
    const e = Math.exp(-(t - h) * 8) * a;
    x += Math.sin((t - h) * 55 + h) * e; y += Math.cos((t - h) * 47 + h * 2) * e; r += Math.sin((t - h) * 35) * e * .02;
  }
  const zoom = 1 + .01 * Math.sin(t * .7);
  R.cam.style.transform = `translate(${x.toFixed(2)}px,${y.toFixed(2)}px) rotate(${r.toFixed(3)}deg) scale(${zoom.toFixed(4)})`;
  let f = 0;
  if (to != null) for (const [h, a] of FLASH) if (t >= h) f = Math.max(f, a * Math.exp(-(t - h) * 10));
  R.flash.style.opacity = f.toFixed(3);
}

/* шторка-переход: две косые полосы проходят справа налево, смена сцены под первой */
function slab(t, tc, colA, colB) {
  if (t <= tc - .34 || t >= tc + .5) return false;
  const G = kf(t, [[tc - .34, 1500], [tc, -560, E.inCubic], [tc + .5, -4700, E.outCubic]]);
  R.slab.style.display = 'block';
  R.slabA.style.background = colA; R.slabB.style.background = colB;
  R.slabA.style.transform = `translateX(${G.toFixed(1)}px) skewX(-18deg)`;
  R.slabB.style.transform = `translateX(${(G + 2000).toFixed(1)}px) skewX(-18deg)`;
  return true;
}

/* буквы: появление снизу с лёгким поворотом */
function lettersUp(chs, t, t0, st = .045, d = .6, dy = 140) {
  chs.forEach((c, i) => {
    const k = P(t, t0 + i * st, d);
    const e = E.outBack(k);
    T(c, `translateY(${((1 - e) * dy).toFixed(1)}px) rotate(${((1 - E.outCubic(k)) * 10 * (i % 2 ? 1 : -1)).toFixed(2)}deg)`, clamp(k * 2.5));
  });
}
/* «дыхание» удерживаемого кадра */
const fl = (t, ph = 0, a = 4, f = 1.8) => Math.sin(t * f + ph) * a;
/* выход группы элементов вверх с затуханием */
const leave = (t, t0, d = .45) => { const k = E.inCubic(P(t, t0, d)); return { dy: -220 * k, o: 1 - k }; };

/* 1. ENDI BREND RUXSATNOMA BIZDA AKSIYADA (0 – 4,62) */
function s1(t) {
  S(R.s1chk, { x: 540 - (t * 160 % 120), y: 1235, r: -9, o: tw(t, 0, .6, 0, 1) });
  const ke = P(t, .4, .5);
  S(R.s1endi, { x: CX, y: 400 + fl(t, 0, 3), s: E.outBack(ke), r: -3, o: clamp(ke * 3) });
  S(R.s1brend, { x: CX, y: 560 + fl(t, .5, 3) });
  R.s1brendCh.forEach((c, i) => {
    const k = P(t, .62 + i * .06, .55), e = E.outBack(k);
    T(c, `translateY(${((1 - e) * -180).toFixed(1)}px)`, clamp(k * 3));
  });
  S(R.s1rux, { x: CX, y: 720 + fl(t, 1, 3) });
  R.s1ruxCh.forEach((c, i) => {
    const k = P(t, .9 + i * .045, .6), e = E.outExpo(k);
    T(c, `translateX(${((1 - e) * 160).toFixed(1)}px)`, clamp(k * 2.5));
  });
  const kb = P(t, 1.88, .4);
  R.s1bizdaBox.style.transformOrigin = '0 50%';
  S(R.s1bizdaBox, { x: CX, y: 865 + fl(t, 1.5, 3), sx: E.outExpo(kb), r: -3, o: kb > 0 ? 1 : 0 });
  const kt = P(t, 1.98, .45);
  S(R.s1bizda, { x: CX, y: 869 + fl(t, 1.5, 3) + (1 - E.outBack(kt)) * 40, r: -3, o: kt * 2 });
  const ka = P(t, 2.3, .55);
  S(R.s1aks, { x: CX, y: 1040 + fl(t, 2, 4), s: lerp(1.7, 1, E.outBack(ka)), r: lerp(-14, -5, E.outCubic(ka)) + wob(t, 2.6, 1.2, 14, 4), o: clamp(ka * 4) });
  drawRays(R.s1rays, t, 2.38, 320);
  S(R.s1raysBox, { x: CX, y: 1040 });
  drawParts(R.s1parts, t, 2.35, CX, 1040, 1400);

  const x = kf(t, [[0, -520], [1.3, 540, E.outCubic], [4.12, 540], [4.62, 1900, E.inCubic]]);
  const tilt = t < 4.1 ? -wob(t, 1.0, 2.5, 10, 4) : -kf(t, [[4.1, 0], [4.25, 2.5, E.outCubic]]);
  R.s1dash.style.transform = `translateX(${(-(t * 900) % 140).toFixed(1)}px)`;
  drawCar(R.s1car, t, x, 1500, tilt);
  drawSpeed(R.s1speed, t, x, 1500, t < 1.3 ? 1 - P(t, .4, .9) * .6 : t > 4.1 ? 1 : .4);
}

/* 2. ATIGI 440 MING SO'M (4,62 – 9,1) */
function s2(t) {
  S(R.s2rays, { x: CX, y: 760, r: t * 8, o: tw(t, 4.65, .8, 0, 1) });
  S(R.s2glow, { x: CX, y: 760, s: 1 + .06 * Math.sin(t * 3) + wob(t, 5.78, .2, 8, 4), o: tw(t, 4.7, .8, 0, 1) });
  const k0 = P(t, 4.9, .65);
  S(R.s2atigi, { x: lerp(-300, CX, E.outExpo(k0)), y: 470 + fl(t, 0, 3), r: -4, o: k0 > 0 ? 1 : 0, sk: (1 - E.outExpo(k0)) * -14 });
  const kn = P(t, 4.85, .5);
  const zoomOut = tw(t, 8.6, .5, 1, 1.4, E.inCubic);
  S(R.s2num, { x: CX, y: 760, s: lerp(.75, 1, E.outBack(kn)) * (1 + wob(t, 5.78, .08, 16, 6) + (t > 6.4 ? .015 * Math.sin(t * 3.5) : 0)) * zoomOut, o: kn * 2.5 });
  R.reels.forEach((rl, i) => {
    const stop = [5.4, 5.58, 5.78][i], st = 4.95;
    const pos = t => {
      const k = P(t, st, stop - st);
      return rl.fin * E.outCubic(k) + (t > stop ? -.12 * Math.exp(-(t - stop) * 10) * Math.sin((t - stop) * 28) : 0);
    };
    const p = pos(t), v = Math.abs(pos(t + .008) - p) / .008;
    rl.strip.style.transform = `translateY(${(-p * R.cellH).toFixed(1)}px)`;
    rl.strip.style.filter = v > 2 ? `blur(${Math.min(8, v * .22).toFixed(1)}px)` : 'none';
  });
  drawParts(R.s2parts, t, 5.78, CX, 760, 1100);
  const km = P(t, 6.1, .55), ks = P(t, 6.3, .5);
  S(R.s2ming, { x: R.mingX, y: 1065 + fl(t, 1, 3) + (1 - E.outBack(km)) * -110, o: km * 3 });
  S(R.s2som, { x: R.somX, y: 1065 + fl(t, 1, 3), s: lerp(1.7, 1, E.outBack(ks)), r: lerp(8, 0, E.outCubic(ks)), o: ks * 4 });
  const ku = P(t, 6.45, .55);
  R.s2under.style.transformOrigin = '0 50%';
  S(R.s2under, { x: CX, y: 1170, sx: E.outExpo(ku), o: ku > 0 ? 1 : 0 });
  const kt = P(t, 6.42, .5);
  S(R.s2tol, { x: CX, y: 1290 + fl(t, 1.6, 3), s: lerp(1.7, 1, E.outBack(kt)), r: lerp(-10, -3, E.outCubic(kt)), o: kt * 4 });
  const kf2 = P(t, 6.95, .6);
  S(R.s2for, { x: CX, y: 1415 + (1 - E.outCubic(kf2)) * 40, o: kf2 * .9 });
}

/* 3. QOLGAN SUMMANI BIZ — TAKSOPARK — TO'LAB BERAMIZ + оплата (8,45 – 14,05) */
function s3(t) {
  const sc = R.s3;
  const kp = P(t, 13.5, .55);
  sc.style.clipPath = 'none';   // вход в сцену — шторкой из галереи
  sc.style.transform = `translateY(${(-H * E.inOutQuart(kp)).toFixed(1)}px)`;
  const pv = Math.sin(Math.PI * kp);
  sc.style.filter = pv > .05 ? `blur(${(pv * 8).toFixed(1)}px)` : 'none';

  S(R.s3chk, { x: 540 - (t * 120 % 120), y: 1720, r: -5, o: tw(t, 9.2, .8, 0, 1) });
  S(R.s3blob, { x: 920 + Math.sin(t * 1.1) * 20, y: 330, s: tw(t, 8.6, .8, .2, 1, E.outBack) });
  S(R.s3l1, { x: CX, y: 420 + fl(t, 0, 3) }); lettersUp(R.s3l1Ch, t, 8.84);
  S(R.s3l2, { x: CX, y: 555 + fl(t, .6, 3) }); lettersUp(R.s3l2Ch, t, 9.14);
  const k3 = P(t, 10.3, .5);
  S(R.s3l3, { x: CX, y: 715 + fl(t, 1.2, 3), s: lerp(1.6, 1, E.outBack(k3)), r: lerp(-12, -4, E.outCubic(k3)), o: k3 * 4 });
  const c1 = P(t, 11.15, .7);
  S(R.s3c1, { x: lerp(-700, CX2, E.outExpo(c1)), y: 965 + fl(t, 2, 4), r: (1 - E.outExpo(c1)) * -6, o: c1 > 0 ? 1 : 0 });
  const kpl = P(t, 11.65, .5);
  S(R.s3plus, { x: CX2, y: 1115, s: E.outBack(kpl), r: (1 - E.outCubic(kpl)) * 180, o: kpl > 0 ? 1 : 0 });
  const c2 = P(t, 11.9, .7);
  S(R.s3c2, { x: lerp(1700, CX2, E.outExpo(c2)), y: 1265 + fl(t, 3, 4), r: (1 - E.outExpo(c2)) * 6, o: c2 > 0 ? 1 : 0, s: 1 + wob(t, 12.25, .03, 12, 4) });
  const ko = P(t, 12.55, .5);
  S(R.s3only, { x: CX2, y: 1430, s: E.outBack(ko), o: ko > 0 ? 1 : 0 });
}

/* 4. YAGONA SHARTIMIZ — BIZNING TAKSOPARKDA ISHLASHINGIZ KIFOYA (13,5 – 18,45) */
function s4(t) {
  const sc = R.s4;
  const kp = P(t, 13.5, .55);
  const pv = Math.sin(Math.PI * kp);
  let gx = 0, gsk = 0;
  if (t > 18.33) { const r = rng(Math.floor(t * 60)); gx = (r() - .5) * 50; gsk = (r() - .5) * 8; }
  sc.style.transform = `translate(${gx.toFixed(1)}px,${(H - H * E.inOutQuart(kp)).toFixed(1)}px) skewX(${gsk.toFixed(2)}deg)`;
  sc.style.filter = pv > .05 ? `blur(${(pv * 8).toFixed(1)}px)` : t > 18.33 ? 'contrast(1.3) saturate(1.4)' : 'none';

  S(R.s4chk, { x: 540 + (t * 120 % 120) - 120, y: 1720, r: 4 });
  const k1 = P(t, 14.15, .55), k2 = P(t, 15.1, .6), k4 = P(t, 16.72, .55), k5 = P(t, 17.05, .5);
  S(R.s4sh, { x: CX, y: 470 + fl(t, 0, 3), s: E.outBack(k1), r: -3, o: k1 > 0 ? 1 : 0 });
  S(R.s4b1, { x: CX, y: 640 + fl(t, .5, 3) + (1 - E.outCubic(k2)) * 60, o: k2 * 2 });
  S(R.s4b2, { x: CX, y: 800 + fl(t, 1, 3) });
  lettersUp(R.s4b2Ch, t, 16.12, .04, .55, 160);
  S(R.s4b3, { x: CX, y: 990 + fl(t, 1.5, 4), s: lerp(1.6, 1, E.outBack(k4)), r: lerp(-10, -4, E.outCubic(k4)), o: k4 * 4 });
  S(R.s4ok, { x: CX2, y: 1220 + fl(t, 2, 5), s: E.outBack(k5) * (1 + .03 * Math.sin(t * 4)), r: (1 - E.outCubic(k5)) * -90, o: k5 > 0 ? 1 : 0 });
}

/* 5. AKSIYA MUDDATI CHEKLANGAN (18,45 – 21,32) */
function s5(t) {
  R.s5.style.transform = `scale(${tw(t, 18.45, .6, 1.08, 1, E.outCubic).toFixed(4)})`;
  S(R.s5glow, { x: CX, y: 680, s: 1 + .06 * Math.sin(t * 6), o: .8 });
  S(R.s5w1, { x: 540 - (t * 160 % 141), y: 330, r: -7 });
  S(R.s5w2, { x: 540 + (t * 160 % 141) - 141, y: 1580, r: 5 });
  const kw = P(t, 18.45, .6);
  const tick = Math.max(0, Math.floor((t - 18.45) / .5)), tk = Math.max(0, (t - 18.45) % .5);
  S(R.s5watch, { x: CX, y: 690, s: lerp(.5, .9, E.outBack(kw)) * (1 + (t > 18.45 ? .025 * Math.exp(-tk * 18) : 0)),
    r: (1 - E.outCubic(kw)) * -24 + wob(t, 19.48, 3, 20, 5), o: kw * 3 });
  R.prog.style.strokeDashoffset = (R.circ * .92 * E.inOutCubic(P(t, 18.5, 2.7))).toFixed(1);
  R.hand.setAttribute('transform', `rotate(${(tick * 30 + 30 * E.outBack(clamp(tk / .14))).toFixed(2)} 140 170)`);
  const k1 = P(t, 18.7, .55), k2 = P(t, 19.1, .55), k3 = P(t, 19.48, .5);
  S(R.s5l1, { x: lerp(-500, CX, E.outExpo(k1)), y: 1030 + fl(t, 0, 3), sk: (1 - E.outExpo(k1)) * 20, o: k1 > 0 ? 1 : 0 });
  S(R.s5l2, { x: lerp(1600, CX, E.outExpo(k2)), y: 1165 + fl(t, .6, 3), sk: (1 - E.outExpo(k2)) * -20, o: k2 > 0 ? 1 : 0 });
  const blink = t > 19.5 && t < 19.8 && Math.floor(t * 14) % 2 === 0;
  R.s5l3.style.background = blink ? '#fff' : '';
  S(R.s5l3, { x: CX2, y: 1320 + fl(t, 1.2, 4), s: lerp(1.7, 1, E.outBack(k3)), r: lerp(-10, -3, E.outCubic(k3)), o: k3 * 4 });
}

/* 6. BATAFSIL MA'LUMOT — HOZIROQ MUROJAAT QILING — контакты, финал (21,32 – 30) */
function s6(t) {
  // «BATAFSIL / MA'LUMOT UCHUN»: сначала крупно в центре, затем уезжает наверх
  const mv = E.inOutCubic(P(t, 22.55, .5));
  S(R.s6b1, { x: CX, y: lerp(780, 375, mv), s: lerp(1, .42, mv) });
  lettersUp(R.s6b1Ch, t, 21.6, .045, .55, 160);
  const k2 = P(t, 22.1, .45);
  S(R.s6b2, { x: CX, y: lerp(960, 455, mv), s: lerp(1.5, 1, E.outBack(k2)) * lerp(1, .6, mv), r: lerp(-10, -3, E.outCubic(k2)), o: k2 * 4 });
  S(R.s6hoz, { x: CX, y: 610 + fl(t, 0, 3) });
  R.s6hozCh.forEach((c, i) => {
    const k = P(t, 22.85 + i * .05, .55), e = E.outBack(k);
    T(c, `translateY(${((1 - e) * 120).toFixed(1)}px) scale(${lerp(.5, 1, E.outCubic(k)).toFixed(3)})`, clamp(k * 3));
  });
  const km = P(t, 23.36, .5);
  S(R.s6mur, { x: CX, y: 775 + fl(t, .8, 3), s: lerp(1.6, 1, E.outBack(km)), r: lerp(-10, -3, E.outCubic(km)), o: km * 4 });
  // Telegram + тап
  const kt = P(t, 24.35, .7), press = 1 - .05 * Math.sin(Math.PI * P(t, 25.0, .25));
  S(R.s6tg, { x: lerp(-700, CX2, E.outExpo(kt)), y: 975 + fl(t, 1.5, 3), s: press, r: (1 - E.outExpo(kt)) * -5, o: kt > 0 ? 1 : 0 });
  const kh = P(t, 24.7, .35), kh2 = P(t, 25.4, .4);
  S(R.s6tap, { x: lerp(980, 790, E.outCubic(kh)) + E.inCubic(kh2) * 300, y: lerp(1180, 1030, E.outCubic(kh)) + E.inCubic(kh2) * 180,
    s: 1 - .14 * Math.sin(Math.PI * P(t, 24.98, .25)), r: -12, o: (kh - kh2) * 2 });
  // телефон + звонок
  const kp = P(t, 25.72, .7);
  S(R.s6ph, { x: lerp(1700, CX2, E.outExpo(kp)), y: 1170 + fl(t, 2.2, 3), r: (1 - E.outExpo(kp)) * 5, o: kp > 0 ? 1 : 0 });
  const ring = t > 25.95 && t < 27.2 ? Math.sin(t * 50) * 12 * Math.min(1, (27.2 - t) * 2) : 0;
  R.s6phIco.style.transform = `rotate(${ring.toFixed(1)}deg)`;
  R.s6rings.forEach((rg, i) => {
    const isTg = i < 2, t0 = (isTg ? 25.0 : 25.95) + (i % 2) * .3, k = P(t, t0, .9);
    const cx = CX2 - 430 + 22 + 60, cy = isTg ? 975 : 1170;
    T(rg, `translate(${(cx - 60).toFixed(1)}px,${(cy - 60).toFixed(1)}px) scale(${(1 + k * 1.2).toFixed(3)})`, t >= t0 && k < 1 ? (1 - k) * .7 : 0);
  });
  const sh = (el, t0) => t >= t0 && t <= t0 + .7 ? `translateX(${lerp(-200, 1000, E.inOutCubic(P(t, t0, .7))).toFixed(0)}px) skewX(-20deg)` : null;
  R.s6tgShine.style.transform = sh(0, 27.8) || sh(0, 29.0) || 'translateX(-300px)';
  R.s6phShine.style.transform = sh(0, 28.0) || sh(0, 29.2) || 'translateX(-300px)';
  // FAQAT BIZDA! + такси
  const ko = P(t, 26.85, .5);
  S(R.s6only, { x: CX2, y: 1335, s: lerp(1.7, 1, E.outBack(ko)) * (1 + .02 * Math.sin(t * 4)), r: wob(t, 27.2, 2, 12, 4), o: ko * 4 });
  const kr = P(t, 21.5, .7);
  R.s6road.style.transform = `translateY(${((1 - E.outExpo(kr)) * 320).toFixed(1)}px)`;
  R.s6dash.style.transform = `translateX(${(-(t * 900) % 140).toFixed(1)}px)`;
  const x = kf(t, [[26.8, -560], [27.9, 540, E.outCubic]]);
  drawCar(R.s6car, t, x, 1592 + (1 - E.outExpo(kr)) * 320, -wob(t, 27.6, 2.5, 10, 4), .78);
  drawSpeed(R.s6speed, t, x, 1520, t < 27.9 ? 1 : .4);
}

/* ---------- галерея: «MASHINANGIZ SHUNDAY BRENDLANADI!» (реальное время TA … TA+G) ---------- */
const CARDS = [
  { src: 'img/mockup-side.jpg', tag: 'NAMUNA', r: -3 },
  { src: 'img/photo-labo-side.jpg', tag: 'HAQIQIY FOTO', r: 2.5 },
  { src: 'img/photo-labo-tent.jpg', tag: 'HAQIQIY FOTO', r: -2 },
  { src: 'img/photo-labo-box.jpg', tag: 'HAQIQIY FOTO', r: 3 },
  { src: 'img/photo-cargo-side.jpg', tag: 'HAQIQIY FOTO', r: -1.5 },
];
function sg(t) {
  const g = t - TA;
  S(R.sgchk, { x: 540 - (t * 120 % 120), y: 1720, r: -5 });
  S(R.sgh, { x: CX, y: 390 + fl(t, 0, 3) });
  lettersUp(R.sghCh, t, TA + .3, .04, .55, 140);
  const kt = P(g, .85, .5);
  S(R.sgtape, { x: CX, y: 530 + fl(t, .7, 3), s: lerp(1.6, 1, E.outBack(kt)), r: lerp(-10, -3, E.outCubic(kt)), o: kt * 4 });
  // карточки: каждая влетает справа и ложится сверху стопки, предыдущие уходят назад
  const t0s = CARDS.map((_, i) => 1.1 + i * 1.05);
  R.sgCards.forEach((el, i) => {
    const k = P(g, t0s[i], .7), e = E.outExpo(k);
    const depth = t0s.reduce((n, tt, j) => n + (j > i ? E.inOutCubic(P(g, tt, .5)) : 0), 0);
    const c = CARDS[i];
    S(el, { x: lerp(1500, CX2 + 10, e) - depth * 26, y: 930 + fl(t, i, 4, 1.4) - depth * 34,
      r: lerp(14, c.r, e) - depth * 2.5, s: 1 - depth * .06, o: k > 0 ? clamp(1.6 - depth * .5) : 0 });
    el.style.zIndex = 10 + i;
    el.style.filter = depth > .05 ? `brightness(${(1 - depth * .12).toFixed(3)})` : 'none';
  });
  const kb = P(g, 1.7, .6);
  S(R.sgprice, { x: CX2, y: 1335 + fl(t, 2, 3) + (1 - E.outCubic(kb)) * 60, r: -2, o: kb * 2 });
}

/* ---------- кадр ---------- */
function render(t) {
  const inG = t >= TA && t < TA + G;
  const to = t < TA ? t : t - SH;                  // время основного таймлайна
  for (const s of scenes) {
    const on = !inG && to >= s.t0 && to < s.t1;
    s.el.style.display = on ? 'block' : 'none';
    if (on) s.fn(to);
  }
  R.sg.style.display = inG ? 'block' : 'none';
  if (inG) sg(t);
  if (!slab(t, 4.62, '#111', '#FFD80D') && !slab(t, TA, '#FFD80D', '#111') && !slab(t, TA + G, '#111', '#FFD80D')
      && !slab(to, 21.32, '#FFD80D', '#111')) R.slab.style.display = 'none';
  // шапка: появляется сразу, инвертируется на тёмных сценах
  const dark = !inG && ((to >= 4.62 && to < 8.75) || (to >= 18.45 && to < 21.32));
  R.hdr.classList.toggle('inv', dark);
  const kh = P(t, .05, .5);
  S(R.hdr, { x: CX, y: lerp(60, 230, E.outBack(kh)), o: clamp(kh * 3) });
  camera(t, inG ? null : to);
  R.grain.style.backgroundPosition = `${Math.floor(t * 30) * 37 % 256}px ${Math.floor(t * 30) * 91 % 256}px`;
}

async function init() {
  await document.fonts.ready;
  await Promise.all([...document.fonts].map(f => f.load().catch(() => 0)));
  R.cam = $('#cam'); R.flash = $('#flash'); R.grain = $('#grain'); R.hdr = $('#hdr');
  R.slab = $('#slab'); R.slabA = $('#slabA'); R.slabB = $('#slabB');
  // галерея фото брендирования
  R.sgCards = CARDS.map(c => {
    const d = document.createElement('div'); d.className = 'a photo';
    d.innerHTML = `<img src="${c.src}"><b>${c.tag}</b>`; $('#sgcards').appendChild(d); return d;
  });
  await Promise.all($$('img').map(im => im.decode().catch(() => 0)));
  ['s1', 's2', 's3', 's4', 's5', 's6', 'sg'].forEach(id => { R[id] = $('#' + id); R[id].style.display = 'block'; });

  $$('[data-fit]').forEach(el => fit(el, +el.dataset.fit));
  $$('[data-split]').forEach(el => { R[el.id + 'Ch'] = splitChars(el); });
  $$('.a[id]').forEach(el => { if (!R[el.id]) R[el.id] = el; });

  // S1
  R.s1raysBox = $('#s1rays'); R.s1rays = makeRays(R.s1raysBox, 18, '#111');
  R.s1parts = makeParts($('#s1parts'), 40, 11, ['#111', '#fff', '#111', '#FFD80D']);
  R.s1dash = $('#s1road .dash');
  R.s1speed = makeSpeed($('#s1speed'), 9, 3, '#111');
  R.s6speed = makeSpeed($('#s6speed'), 9, 5, '#111');

  // S2: барабаны
  const num = $('#s2num');
  R.reels = [4, 4, 0].map((d, i) => {
    const reel = document.createElement('div'); reel.className = 'reel';
    const strip = document.createElement('div'); strip.className = 'strip';
    for (let k = 0; k < 40; k++) { const c = document.createElement('div'); c.textContent = k % 10; strip.appendChild(c); }
    reel.appendChild(strip); num.appendChild(reel);
    return { strip, fin: 20 + i * 10 + d - (i === 2 ? 10 : 0) };
  });
  R.cellH = num.querySelector('.strip div').offsetHeight;
  R.s2parts = makeParts($('#s2parts'), 50, 22, ['#FFD80D', '#FFD80D', '#fff', '#F2C200']);
  const mw = $('#s2ming').offsetWidth, sw = $('#s2som').offsetWidth, g = 50;
  R.mingX = 540 - (mw + g + sw) / 2 + mw / 2; R.somX = 540 + (mw + g + sw) / 2 - sw / 2;

  // S3
  $('#s3c1').style.display = 'flex';
  // S4
  // S5
  $('#s5watch').innerHTML = WATCH;
  R.prog = $('#s5watch .prog'); R.hand = $('#s5watch .hand');
  R.circ = 2 * Math.PI * 104; R.prog.style.strokeDasharray = R.circ.toFixed(1);
  $('#s5watch .ticks').innerHTML = [...Array(12)].map((_, i) => `<rect x="138" y="${170 - 84}" width="4" height="12" rx="2" fill="#666" transform="rotate(${i * 30} 140 170)"/>`).join('');
  // S6
  const rb = $('#s6rings');
  R.s6rings = [0, 1, 2, 3].map(() => { const d = document.createElement('div'); d.className = 'ring'; d.style.width = d.style.height = '128px'; rb.appendChild(d); return d; });
  R.s6tgShine = $('#s6tg .shine'); R.s6phShine = $('#s6ph .shine'); R.s6phIco = $('#s6phIco');
  R.s6road = $('#s6road'); R.s6dash = $('#s6road .dash');

  // зерно плёнки
  const cv = document.createElement('canvas'); cv.width = cv.height = 256;
  const cx = cv.getContext('2d'), id = cx.createImageData(256, 256), r = rng(4242);
  for (let i = 0; i < id.data.length; i += 4) { const v = r() * 255; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255; }
  cx.putImageData(id, 0, 0);
  R.grain.style.backgroundImage = 'url(' + cv.toDataURL() + ')';

  scene('s1', 0, 4.62, s1);
  scene('s2', 4.62, 9.1, s2);
  scene('s3', 8.45, 14.05, s3);
  scene('s4', 13.5, 18.45, s4);
  scene('s5', 18.45, 21.32, s5);
  scene('s6', 21.32, 30.01, s6);
}

window.DURATION = DUR;
window.ready = init().then(() => { render(0); return true; });
window.renderAt = t => { render(t); return true; };

/* предпросмотр в браузере: ?t=12.5 — стоп-кадр, без параметра — проигрывание по кругу */
window.ready.then(() => {
  if (navigator.webdriver) return;
  const q = new URLSearchParams(location.search);
  if (q.has('t')) { render(parseFloat(q.get('t'))); return; }
  const start = performance.now();
  (function loop(now) { render(((now - start) / 1000) % DUR); requestAnimationFrame(loop); })(start);
});
