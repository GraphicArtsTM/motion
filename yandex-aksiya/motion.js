/* Yandex Go taksopark — «Brend ruxsatnoma aksiyada», 1080×1920, 18,5 с.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Тайминги привязаны к озвучке (audio/voice.mp3 стартует с задержкой VO = 0,4 с),
   слова — по разметке Whisper, см. README. */
'use strict';

const W = 1080, H = 1920, DUR = 18.5;
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

function carSVG(id) {
  const spokes = cx => [0, 72, 144, 216, 288].map(a => `<rect x="${cx - 4}" y="${164 - 24}" width="8" height="24" rx="3" fill="#8d8d8d" transform="rotate(${a} ${cx} 164)"/>`).join('');
  const wheel = cx => `<g class="wh" data-cx="${cx}"><circle cx="${cx}" cy="164" r="44" fill="#111"/><circle cx="${cx}" cy="164" r="27" fill="#dcdcdc"/>${spokes(cx)}<circle cx="${cx}" cy="164" r="8" fill="#111"/></g>`;
  return `<svg viewBox="0 0 600 220">
  <defs><pattern id="chk${id}" width="28" height="28" patternUnits="userSpaceOnUse"><rect width="28" height="28" fill="#fff"/><rect width="14" height="14" fill="#111"/><rect x="14" y="14" width="14" height="14" fill="#111"/></pattern></defs>
  <ellipse class="shadow" cx="300" cy="210" rx="275" ry="11" fill="rgba(0,0,0,.45)"/>
  <g class="body">
    <circle cx="150" cy="164" r="54" fill="#111"/><circle cx="462" cy="164" r="54" fill="#111"/>
    <path d="M28 150 L28 118 Q30 96 62 90 L148 80 L206 36 Q216 28 236 28 L384 28 Q402 28 414 38 L474 80 L546 92 Q576 98 578 122 L578 150 Q578 160 568 160 L520 160 A58 58 0 0 0 404 160 L208 160 A58 58 0 0 0 92 160 L40 160 Q28 160 28 150 Z" fill="#fff" stroke="#111" stroke-width="6" stroke-linejoin="round"/>
    <path d="M164 80 L214 42 Q220 38 228 38 L296 38 L296 80 Z" fill="#111"/>
    <path d="M310 38 L380 38 Q394 38 402 46 L452 80 L310 80 Z" fill="#111"/>
    <path d="M236 44 L258 44 L228 76 L206 76 Z" fill="rgba(255,255,255,.28)"/>
    <path d="M334 44 L352 44 L324 76 L306 76 Z" fill="rgba(255,255,255,.24)"/>
    <rect x="96" y="104" width="420" height="28" fill="url(#chk${id})"/>
    <path d="M303 84 V158 M200 86 V158 M410 86 V158" stroke="#111" stroke-width="3" opacity=".3"/>
    <rect x="252" y="90" width="28" height="7" rx="3.5" fill="#111"/><rect x="354" y="90" width="28" height="7" rx="3.5" fill="#111"/>
    <path d="M552 100 L577 106 L577 120 L556 118 Z" fill="#FFD80D" stroke="#111" stroke-width="3" stroke-linejoin="round"/>
    <rect x="29" y="100" width="12" height="20" rx="2" fill="#E53935"/>
    <rect x="512" y="142" width="70" height="14" rx="7" fill="#111"/><rect x="24" y="142" width="62" height="14" rx="7" fill="#111"/>
    <g transform="translate(300 13)"><rect x="-58" y="-15" width="116" height="31" rx="8" fill="#FFD80D" stroke="#111" stroke-width="5"/>
      <text x="0" y="9" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="20" fill="#111">TAXI</text></g>
  </g>
  ${wheel(150)}${wheel(462)}
</svg>`;
}

const DOC = `<div class="dh">RUXSATNOMA</div><div class="db"><div class="ph"></div>
  <div><div class="ln d"></div><div class="ln"></div><div class="ln s"></div><div class="ln"></div></div>
  <div class="rows"><div class="ln"></div><div class="ln s"></div></div>
  <div class="ft"><div class="qr"></div><svg class="sig" viewBox="0 0 170 60"><path d="M6 44 C 26 6, 36 60, 52 30 S 78 8, 86 38 S 112 52, 122 22 S 150 30, 164 18" fill="none" stroke="#1d3fa8" stroke-width="4" stroke-linecap="round"/></svg></div></div>`;

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
    out.push({ el, a: r() * Math.PI * 2, v: 700 + r() * 1500, spin: (r() - .5) * 1400, life: .9 + r() * .6, sz });
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

/* ---------- машина ---------- */
function drawCar(c, t, x, y, dist, tilt) {
  S(c.el, { x, y });
  const ang = dist / (44 * 1.4) * 57.2958;
  c.wh.forEach(g => g.setAttribute('transform', `rotate(${ang.toFixed(2)} ${g.dataset.cx} 164)`));
  const bob = Math.sin(t * 31) * 1.2 + Math.sin(t * 17) * .8;
  c.body.setAttribute('transform', `translate(0 ${bob.toFixed(2)}) rotate(${tilt.toFixed(3)} 300 160)`);
}

/* ---------- сцены ---------- */
const scenes = [];
function scene(id, t0, t1, fn) { scenes.push({ el: $('#' + id), t0, t1, fn }); }

/* удары камеры: [момент, сила] */
const HITS = [[0.4, 10], [2.26, 26], [3.9, 30], [4.48, 12], [6.1, 10], [8.62, 18], [9.3, 22], [10.16, 26], [10.92, 14], [12.28, 14], [13.6, 10], [15.02, 10], [16.0, 20]];
const FLASH = [[0.4, .35], [2.26, .45], [3.9, .55], [9.3, .6], [10.16, .3], [16.0, .35]];

function camera(t) {
  let x = 0, y = 0, r = 0;
  for (const [h, a] of HITS) {
    if (t < h || t > h + .7) continue;
    const e = Math.exp(-(t - h) * 9) * a;
    x += Math.sin((t - h) * 71 + h) * e; y += Math.cos((t - h) * 59 + h * 2) * e; r += Math.sin((t - h) * 43) * e * .03;
  }
  // лёгкий «живой» дрейф камеры
  const zoom = 1 + .012 * Math.sin(t * .9);
  R.cam.style.transform = `translate(${x.toFixed(2)}px,${y.toFixed(2)}px) rotate(${r.toFixed(3)}deg) scale(${zoom.toFixed(4)})`;
  let f = 0;
  for (const [h, a] of FLASH) if (t >= h) f = Math.max(f, a * Math.exp(-(t - h) * 13));
  R.flash.style.opacity = f.toFixed(3);
}

/* шторка-переход: две косые полосы проходят справа налево, смена сцены под первой */
function slab(t, tc, colA, colB) {
  const G = kf(t, [[tc - .2, 1500], [tc, -560, E.inQuad], [tc + .34, -4700, E.outQuad]]);
  const on = t > tc - .2 && t < tc + .34;
  R.slab.style.display = on ? 'block' : 'none';
  if (!on) return;
  R.slabA.style.background = colA; R.slabB.style.background = colB;
  R.slabA.style.transform = `translateX(${G.toFixed(1)}px) skewX(-18deg)`;
  R.slabB.style.transform = `translateX(${(G + 2000).toFixed(1)}px) skewX(-18deg)`;
}

/* буквы: появление снизу с поворотом */
function lettersUp(chs, t, t0, st = .035, d = .45, dy = 160) {
  chs.forEach((c, i) => {
    const k = P(t, t0 + i * st, d);
    const e = E.outBackS(k);
    T(c, `translateY(${((1 - e) * dy).toFixed(1)}px) rotate(${((1 - e) * 14 * (i % 2 ? 1 : -1)).toFixed(2)}deg) scale(${lerp(.4, 1, E.outCubic(k)).toFixed(3)})`, clamp(k * 3));
  });
}

/* 1. ENDI BREND RUXSATNOMA BIZDA AKSIYADA (0 – 2,85) */
function s1(t) {
  const sc = R.s1;
  const ir = tw(t, 0.02, .4, 0, 1300, E.outCubic);
  sc.style.clipPath = t < .42 ? `circle(${ir.toFixed(1)}px at 540px 980px)` : 'none';

  S(R.s1chk, { x: 540 - (t * 260 % 120), y: 1235, r: -9, o: tw(t, .2, .4, 0, 1) });
  // ENDI
  const ke = P(t, .38, .35);
  S(R.s1endi, { x: 540, y: 370, s: E.outBackS(ke), r: lerp(-20, -3, E.outCubic(ke)) + wob(t, .7, 2), o: clamp(ke * 4) });
  // BREND
  S(R.s1brend, { x: 540, y: 560 });
  R.s1brendCh.forEach((c, i) => {
    const k = P(t, .74 + i * .045, .38), e = E.outBackS(k);
    T(c, `translateY(${((1 - e) * -260).toFixed(1)}px) scale(${lerp(1.8, 1, E.outCubic(k)).toFixed(3)})`, clamp(k * 3));
  });
  // RUXSATNOMA
  S(R.s1rux, { x: 540, y: 735 });
  R.s1ruxCh.forEach((c, i) => {
    const k = P(t, 1.0 + i * .032, .42), e = E.outExpo(k);
    T(c, `translateX(${((1 - e) * 260).toFixed(1)}px) skewX(${((1 - e) * -25).toFixed(1)}deg)`, clamp(k * 3));
  });
  // BIZDA — чёрная плашка разворачивается слева
  const kb = P(t, 1.82, .22);
  R.s1bizdaBox.style.transformOrigin = '0 50%';
  S(R.s1bizdaBox, { x: 540, y: 880, sx: E.outExpo(kb), r: -3, o: kb > 0 ? 1 : 0 });
  const kt = P(t, 1.9, .3);
  S(R.s1bizda, { x: 540, y: 884 + (1 - E.outBack(kt)) * 50, r: -3, o: kt * 2 });
  // AKSIYADA! — штамп
  const ka = P(t, 2.24, .22);
  S(R.s1aks, { x: 540, y: 1070, s: lerp(2.6, 1, E.outExpo(ka)) * (1 + wob(t, 2.46, .04, 30, 9)), r: lerp(-18, -5, E.outExpo(ka)) + wob(t, 2.46, 2, 26, 8), o: clamp(ka * 5) });
  drawRays(R.s1rays, t, 2.3, 300);
  S(R.s1raysBox, { x: 540, y: 1070 });
  drawParts(R.s1parts, t, 2.28, 540, 1070, 1800);

  // машина: въезжает слева, едет «на месте» (летит дорога), уезжает вправо
  const x = kf(t, [[0, -520], [.9, 540, E.outExpo], [2.52, 540], [2.95, 1900, E.inCubic]]);
  const tilt = (t < 2.5 ? -wob(t, .62, 3.2, 13, 5) : -kf(t, [[2.5, 0], [2.62, 2.5, E.outCubic]]));
  R.s1dash.style.transform = `translateX(${(-(t * 1100) % 140).toFixed(1)}px)`;
  drawCar(R.s1car, t, x, 1553, t * 1100 + x, tilt);
  const spd = t < .9 ? 1 - P(t, .3, .6) * .6 : t > 2.5 ? 1 : .4;
  drawSpeed(R.s1speed, t, x, 1500, spd);
}

/* 2. ATIGI 440 MING SO'M (2,85 – 5,2) */
function s2(t) {
  S(R.s2rays, { x: 540, y: 860, r: t * 14, o: tw(t, 2.9, .5, 0, 1) });
  S(R.s2glow, { x: 540, y: 860, s: 1 + .08 * Math.sin(t * 6) + wob(t, 3.9, .25, 10, 5), o: tw(t, 3.0, .6, 0, 1) });
  // ATIGI
  const k0 = P(t, 2.9, .4);
  S(R.s2atigi, { x: lerp(-300, 540, E.outExpo(k0)), y: 540, r: -4 + wob(t, 3.2, 3), o: k0 > 0 ? 1 : 0, sk: (1 - E.outExpo(k0)) * -20 });
  // барабаны 4-4-0
  const kn = P(t, 3.05, .3);
  const zoomOut = tw(t, 4.78, .4, 1, 1.5, E.inCubic);
  S(R.s2num, { x: 540, y: 860, s: lerp(.7, 1, E.outBack(kn)) * (1 + wob(t, 3.9, .12, 22, 8)) * zoomOut, o: kn * 3 });
  const cellH = R.cellH;
  R.reels.forEach((rl, i) => {
    const stop = [3.6, 3.75, 3.9][i], st = 3.1;
    const pos = t => {
      const k = P(t, st, stop - st);
      return rl.fin * E.outCubic(k) + (t > stop ? -.14 * Math.exp(-(t - stop) * 12) * Math.sin((t - stop) * 34) : 0);
    };
    const p = pos(t), v = Math.abs(pos(t + .008) - p) / .008;
    rl.strip.style.transform = `translateY(${(-p * cellH).toFixed(1)}px)`;
    rl.strip.style.filter = v > 2 ? `blur(${Math.min(9, v * .25).toFixed(1)}px)` : 'none';
  });
  drawParts(R.s2parts, t, 3.9, 540, 860, 1500);
  // MING SO'M
  const km = P(t, 4.24, .28), ks = P(t, 4.46, .22);
  S(R.s2ming, { x: R.mingX, y: 1180 + (1 - E.outBackS(km)) * -120, o: km * 4 });
  S(R.s2som, { x: R.somX, y: 1180, s: lerp(2.2, 1, E.outExpo(ks)), r: lerp(10, 0, E.outExpo(ks)), o: ks * 5 });
  const ku = P(t, 4.5, .3);
  R.s2under.style.transformOrigin = '0 50%';
  S(R.s2under, { x: 540, y: 1290, sx: E.outExpo(ku), o: ku > 0 ? 1 : 0 });
  const kf2 = P(t, 4.58, .35);
  S(R.s2for, { x: 540, y: 1400 + (1 - E.outCubic(kf2)) * 40, o: kf2 * .85 });
}

/* 3. AKSIYADAN FOYDALANIB QOLING + оплата (4,85 – 6,7) */
function s3(t) {
  const sc = R.s3;
  const ir = tw(t, 4.85, .4, 0, 2300, E.inOutCubic);
  const push = -H * E.inOutQuart(P(t, 6.33, .34));
  sc.style.clipPath = t < 5.25 ? `circle(${ir.toFixed(1)}px at 540px 860px)` : 'none';
  sc.style.transform = `translateY(${push.toFixed(1)}px)`;
  const pv = Math.sin(Math.PI * P(t, 6.33, .34));
  sc.style.filter = pv > .05 ? `blur(${(pv * 10).toFixed(1)}px)` : 'none';

  S(R.s3blob, { x: 920 + Math.sin(t * 1.3) * 20, y: 300, s: tw(t, 4.95, .6, .2, 1, E.outBack) });
  S(R.s3l1, { x: 540, y: 365 }); lettersUp(R.s3l1Ch, t, 4.98, .03, .42);
  S(R.s3l2, { x: 540, y: 500 }); lettersUp(R.s3l2Ch, t, 5.48, .03, .42);
  const k3 = P(t, 6.08, .22);
  S(R.s3l3, { x: 540, y: 655, s: lerp(2.2, 1, E.outExpo(k3)), r: lerp(-14, -4, E.outExpo(k3)) + wob(t, 6.3, 1.5, 24), o: k3 * 5 });

  const c1 = P(t, 5.1, .5);
  S(R.s3c1, { x: lerp(-700, 540, E.outExpo(c1)), y: 975, r: (1 - E.outExpo(c1)) * -8, o: c1 > 0 ? 1 : 0 });
  const kp = P(t, 5.36, .35);
  S(R.s3plus, { x: 540, y: 1128, s: E.outBackS(kp), r: (1 - kp) * 180, o: kp > 0 ? 1 : 0 });
  const c2 = P(t, 5.52, .5);
  S(R.s3c2, { x: lerp(1700, 540, E.outExpo(c2)), y: 1282, r: (1 - E.outExpo(c2)) * 8, o: c2 > 0 ? 1 : 0 });
  const ko = P(t, 5.85, .3);
  S(R.s3only, { x: 540, y: 1500, s: E.outBackS(ko), o: ko > 0 ? 1 : 0 });
}

/* 4. HUJJATLARINGIZNI TEZ VA OSON RASMIYLASHTIRING + SHARTI (6,33 – 9,3) */
function s4(t) {
  const sc = R.s4;
  const push = H - H * E.inOutQuart(P(t, 6.33, .34));
  const pv = Math.sin(Math.PI * P(t, 6.33, .34));
  // глитч-выход перед 9,3
  let gx = 0, gsk = 0;
  if (t > 9.16) { const r = rng(Math.floor(t * 60)); gx = (r() - .5) * 90; gsk = (r() - .5) * 14; }
  sc.style.transform = `translate(${gx.toFixed(1)}px,${push.toFixed(1)}px) skewX(${gsk.toFixed(2)}deg)`;
  sc.style.filter = pv > .05 ? `blur(${(pv * 10).toFixed(1)}px)` : t > 9.16 ? 'contrast(1.4) saturate(1.6)' : 'none';

  S(R.s4h, { x: 540, y: 330 });
  R.s4hCh.forEach((c, i) => {
    const k = P(t, 6.48 + i * .022, .4), e = E.outBackS(k);
    const wave = t > 6.9 ? Math.sin(t * 5 - i * .5) * 4 : 0;
    T(c, `translateY(${((1 - e) * 140 + wave).toFixed(1)}px)`, clamp(k * 3));
  });
  // документы веером
  [[R.s4d3, 6.52, -9, -70, 20], [R.s4d2, 6.64, 8, 70, 10], [R.s4d1, 6.76, -2, 0, 0]].forEach(([el, t0, r, dx, dy], i) => {
    const k = P(t, t0, .55), e = E.outExpo(k);
    const fl = Math.sin(t * 2.2 + i) * 6;
    S(el, { x: 540 + dx * e, y: lerp(1900, 760 + dy, e) + fl, r: lerp(r + 35 * (i % 2 ? 1 : -1), r, e) + wob(t, 8.62, i === 2 ? 1.2 : .6, 20), o: k > 0 ? 1 : 0,
      s: 1 + (i === 2 ? wob(t, 8.62, .04, 26, 9) : 0) });
  });
  // штамп
  const ks = P(t, 8.6, .16);
  S(R.s4stamp, { x: 590, y: 880 + Math.sin(t * 2.2 + 2) * 6, s: lerp(3.2, 1, E.outExpo(ks)), r: -14, o: ks * 6 });
  // чипы
  const kz = P(t, 7.46, .38), ko = P(t, 8.0, .38);
  const gap = 36, tot = R.tezW + gap + R.osonW, x0 = 540 - tot / 2;
  S(R.s4tez, { x: x0 + R.tezW / 2, y: 1160, s: E.outBackS(kz), r: (1 - kz) * -20 + wob(t, 7.5, 3), o: kz > 0 ? 1 : 0 });
  S(R.s4oson, { x: x0 + R.tezW + gap + R.osonW / 2, y: 1160, s: E.outBackS(ko), r: (1 - ko) * 20 + wob(t, 8.04, 3), o: ko > 0 ? 1 : 0 });
  const kr = P(t, 8.42, .3);
  S(R.s4ras, { x: lerp(1500, 540, E.outExpo(kr)), y: 1310, r: -2, sk: (1 - E.outExpo(kr)) * -25, o: kr > 0 ? 1 : 0 });
  const kc = P(t, 6.95, .5);
  S(R.s4cond, { x: 540, y: lerp(1800, 1500, E.outExpo(kc)), o: kc * 3 });
}

/* 5. AKSIYA MUDDATI CHEKLANGAN (9,3 – 10,95) */
function s5(t) {
  const punch = tw(t, 9.3, .35, 1.12, 1, E.outCubic);
  R.s5.style.transform = `scale(${punch.toFixed(4)})`;
  S(R.s5glow, { x: 540, y: 740, s: 1 + .1 * Math.sin(t * 13), o: .8 });
  S(R.s5w1, { x: 540 - (t * 300 % 141), y: 250, r: -7 });
  S(R.s5w2, { x: 540 + (t * 300 % 141) - 141, y: 1660, r: 5 });
  const kw = P(t, 9.3, .45);
  const tick = Math.floor((t - 9.3) / .235), tk = (t - 9.3) % .235;
  S(R.s5watch, { x: 540, y: 735, s: lerp(.5, 1, E.outBackS(kw)) * (1 + (t > 9.3 ? .03 * Math.exp(-tk * 30) : 0)) + wob(t, 10.16, .06, 30, 8),
    r: (1 - E.outCubic(kw)) * -30 + wob(t, 10.16, 4, 34, 8), o: kw * 3 });
  const prog = 1 - .92 * E.inOutCubic(P(t, 9.35, 1.55));
  R.prog.style.strokeDashoffset = (R.circ * (1 - prog)).toFixed(1);
  R.hand.setAttribute('transform', `rotate(${(tick * 30 + 30 * E.outBackS(clamp(tk / .1))).toFixed(2)} 140 170)`);
  const k1 = P(t, 9.3, .4), k2 = P(t, 9.76, .4), k3 = P(t, 10.14, .2);
  S(R.s5l1, { x: lerp(-500, 540, E.outExpo(k1)), y: 1140, sk: (1 - E.outExpo(k1)) * 30, o: k1 > 0 ? 1 : 0 });
  S(R.s5l2, { x: lerp(1600, 540, E.outExpo(k2)), y: 1280, sk: (1 - E.outExpo(k2)) * -30, o: k2 > 0 ? 1 : 0 });
  const blink = t > 10.14 && t < 10.4 && Math.floor(t * 30) % 2 === 0;
  R.s5l3.style.background = blink ? '#fff' : '';
  S(R.s5l3, { x: 540, y: 1440, s: lerp(2.4, 1, E.outExpo(k3)) * (1 + wob(t, 10.34, .05, 30, 8)), r: lerp(-12, -3, E.outExpo(k3)) + wob(t, 10.34, 2, 30, 8), o: k3 * 5 });
}

/* 6. BATAFSIL MA'LUMOT — HOZIROQ MUROJAAT QILING — контакты, финал (10,92 – 18,5) */
function s6(t) {
  // «BATAFSIL MA'LUMOT UCHUN»: сначала крупно, потом уходит вверх в строку-подводку
  const out = P(t, 12.02, .3), eo = E.inCubic(out);
  S(R.s6b1, { x: 540, y: 800 - eo * 500, o: 1 - out });
  lettersUp(R.s6b1Ch, t, 10.98, .035, .42, 200);
  const k2 = P(t, 11.5, .3);
  S(R.s6b2, { x: 540, y: 990 - eo * 500, s: lerp(2, 1, E.outExpo(k2)), r: lerp(-12, -3, E.outExpo(k2)) + wob(t, 11.7, 1.5, 24), o: Math.min(k2 * 5, 1 - out) });
  const kb = P(t, 12.12, .35);
  S(R.s6top, { x: 540, y: 330 + (1 - E.outExpo(kb)) * 80, o: kb * 2 });
  // HOZIROQ
  S(R.s6hoz, { x: 540, y: 500 });
  R.s6hozCh.forEach((c, i) => {
    const k = P(t, 12.24 + i * .04, .4), e = E.outBackS(k);
    T(c, `scale(${e.toFixed(3)}) rotate(${((1 - k) * (i % 2 ? 40 : -40)).toFixed(1)}deg)`, clamp(k * 4));
  });
  const km = P(t, 12.78, .24);
  S(R.s6mur, { x: 540, y: 680, s: lerp(2.2, 1, E.outExpo(km)), r: lerp(-12, -3, E.outExpo(km)) + wob(t, 13, 1.5, 24), o: km * 5 });
  // Telegram
  const kt = P(t, 13.56, .5), press = 1 - .05 * Math.sin(Math.PI * P(t, 14.24, .2));
  S(R.s6tg, { x: lerp(-700, 540, E.outExpo(kt)), y: 930, s: press, r: (1 - E.outExpo(kt)) * -6, o: kt > 0 ? 1 : 0 });
  const kh = P(t, 13.95, .3), kh2 = P(t, 14.5, .35);
  S(R.s6tap, { x: lerp(1000, 820, E.outCubic(kh)) + kh2 * 300, y: lerp(1150, 990, E.outCubic(kh)) + kh2 * 160,
    s: 1 - .12 * Math.sin(Math.PI * P(t, 14.22, .2)), r: -12, o: (kh - kh2) * 2 });
  // Телефон
  const kp = P(t, 14.98, .5);
  S(R.s6ph, { x: lerp(1700, 540, E.outExpo(kp)), y: 1135, r: (1 - E.outExpo(kp)) * 6, o: kp > 0 ? 1 : 0 });
  const ring = t > 15.15 && t < 16.4 ? Math.sin(t * 60) * 14 * Math.min(1, (16.4 - t) * 3) : 0;
  R.s6phIco.style.transform = `rotate(${ring.toFixed(1)}deg)`;
  // волны вокруг иконок
  R.s6rings.forEach((rg, i) => {
    const isTg = i < 2;
    const t0 = (isTg ? 14.26 : 15.2) + (i % 2) * .22;
    const k = P(t, t0, .7);
    const cx = (isTg ? 540 : 540) - 480 + 22 + 64, cy = isTg ? 930 : 1135;
    rg.style.borderColor = '#111';
    T(rg, `translate(${(cx - 64).toFixed(1)}px,${(cy - 64).toFixed(1)}px) scale(${(1 + k * 1.3).toFixed(3)})`, t >= t0 && k < 1 ? (1 - k) * .7 : 0);
  });
  // блики на кнопках
  [[R.s6tgShine, 16.5], [R.s6phShine, 16.7], [R.s6tgShine, 17.6], [R.s6phShine, 17.8]].forEach(([el, t0]) => {
    if (t >= t0 && t <= t0 + .6) el.style.transform = `translateX(${lerp(-200, 1100, E.inOutCubic(P(t, t0, .6))).toFixed(0)}px) skewX(-20deg)`;
  });
  if (t < 16.5) { R.s6tgShine.style.transform = R.s6phShine.style.transform = 'translateX(-300px)'; }
  // FAQAT BIZDA!
  const ko = P(t, 15.96, .24);
  S(R.s6only, { x: 540, y: 1345, s: lerp(2.4, 1, E.outExpo(ko)) * (1 + .025 * Math.sin(t * 8)), r: wob(t, 16.2, 3, 26), o: ko * 5 });
  // дорога и машина
  const kr = P(t, 15.8, .4);
  R.s6road.style.transform = `translateY(${((1 - E.outExpo(kr)) * 300).toFixed(1)}px)`;
  R.s6dash.style.transform = `translateX(${(-(t * 1100) % 140).toFixed(1)}px)`;
  const x = kf(t, [[15.95, -560], [16.75, 540, E.outExpo]]);
  drawCar(R.s6car, t, x, 1573 + (1 - E.outExpo(kr)) * 300, t * 1100 + x, -wob(t, 16.45, 3.2, 13, 5));
  drawSpeed(R.s6speed, t, x, 1520, t < 16.75 ? 1 : .4);
}

/* ---------- кадр ---------- */
function render(t) {
  for (const s of scenes) {
    const on = t >= s.t0 && t < s.t1;
    s.el.style.display = on ? 'block' : 'none';
    if (on) s.fn(t);
  }
  slab(t, 2.85, '#111', '#FFD80D');
  slab2(t);
  // шапка: появляется в начале, инвертируется на тёмных сценах
  const dark = (t >= 2.85 && t < 4.95) || (t >= 9.3 && t < 10.92);
  R.hdr.classList.toggle('inv', dark);
  const kh = P(t, .3, .45);
  S(R.hdr, { x: 540, y: lerp(-80, 140, E.outBack(kh)), o: kh > 0 ? 1 : 0 });
  camera(t);
  R.grain.style.backgroundPosition = `${Math.floor(t * 60) * 37 % 256}px ${Math.floor(t * 60) * 91 % 256}px`;
}
function slab2(t) { if (t > 10.5 && t < 11.4) slab(t, 10.92, '#FFD80D', '#111'); }

async function init() {
  await document.fonts.ready;
  await Promise.all([...document.fonts].map(f => f.load().catch(() => 0)));
  R.cam = $('#cam'); R.flash = $('#flash'); R.grain = $('#grain'); R.hdr = $('#hdr');
  R.slab = $('#slab'); R.slabA = $('#slabA'); R.slabB = $('#slabB');
  ['s1', 's2', 's3', 's4', 's5', 's6'].forEach(id => { R[id] = $('#' + id); R[id].style.display = 'block'; });

  $$('[data-fit]').forEach(el => fit(el, +el.dataset.fit));
  $$('[data-split]').forEach(el => { R[el.id + 'Ch'] = splitChars(el); });
  $$('.a[id]').forEach(el => { if (!R[el.id]) R[el.id] = el; });

  // S1
  R.s1raysBox = $('#s1rays'); R.s1rays = makeRays(R.s1raysBox, 18, '#111');
  R.s1parts = makeParts($('#s1parts'), 40, 11, ['#111', '#fff', '#111', '#FFD80D']);
  R.s1dash = $('#s1road .dash');
  const car = (id, sp) => { const el = $('#' + id); el.innerHTML = carSVG(id); return { el, wh: $$('.wh', el), body: $('.body', el) }; };
  R.s1car = car('s1car'); R.s6car = car('s6car');
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
  ['#s4d1', '#s4d2', '#s4d3'].forEach(s => { $(s).innerHTML = DOC; });
  R.tezW = $('#s4tez').offsetWidth; R.osonW = $('#s4oson').offsetWidth;
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

  scene('s1', 0, 2.85, s1);
  scene('s2', 2.85, 5.25, s2);
  scene('s3', 4.85, 6.68, s3);
  scene('s4', 6.33, 9.3, s4);
  scene('s5', 9.3, 10.92, s5);
  scene('s6', 10.92, DUR + .01, s6);
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
