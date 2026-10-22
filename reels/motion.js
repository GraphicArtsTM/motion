/* M Cosmetic — Reels «старое видео / моё видео», 1080×1920, узбекская версия.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Темп — 120 BPM нового видео: его доли приходятся на 0,122 + 0,5·n с от начала,
   а само видео стартует на 6,378 с, поэтому доли ролика лежат ровно на 0, 0,5, 1, …
   (сильные доли — на нечётных секундах). Все события стоят на этой сетке. */
'use strict';

const W = 1080, H = 1920;
const HANDLE = 'mcosmetic_uz';            // отметка бренда в заголовке и финале
const TAKE_FPS = 60000 / 1001;          // дубль с телефона, 59,94 к/с
const TAKE_N = 1183, OLD_N = 353, NEW_N = 960;

/* ---------- монтаж (секунды ролика) ---------- */
const HOLO_OLD = 1.5;     // голограмма со старым видео над левой ладонью
const STAMP = 4.0;        // «G‘ALATI»
const SHATTER = 5.0;      // экран разлетается
const WHIP = 5.5;         // вайп к правой руке (0,5 с)
const HOLO_NEW = 6.0;     // голограмма с новым видео над правой ладонью
const N0 = 6.378;         // старт нового видео — его доли совпадают с сеткой ролика
const BADGE = 7.5;
const FLY = 8.0;          // экран отрывается от ладони и летит в камеру
const LAND = 9.0;         // новое видео на весь экран (сильная доля)
const NEW_END = N0 + 16;  // 22,378 — новое видео закончилось
const OUT = 22.4;         // финал «1 или 2?»
const WIN = 25.0;         // карточка «2» выходит вперёд (сильная доля)
const FINAL = 27.0;       // последний удар, дальше — затемнение
const DUR = 29.0;

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
/* затухающий удар: 1 в момент t0, дальше экспонента */
const hit = (t, t0, k = 9) => t < t0 ? 0 : Math.exp(-(t - t0) * k);

/* ---------- детерминированный рандом ---------- */
function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}
const hash = n => rng(n * 7919 + 13)();

/* ---------- трансформ элемента: (x, y) — центр элемента на кадре ---------- */
function S(el, o) {
  let tr = 'translate(-50%,-50%) translate3d(' + (o.x || 0).toFixed(2) + 'px,' + (o.y || 0).toFixed(2) + 'px,' + (o.z || 0).toFixed(2) + 'px)';
  if (o.rx) tr += ' rotateX(' + o.rx.toFixed(3) + 'deg)';
  if (o.ry) tr += ' rotateY(' + o.ry.toFixed(3) + 'deg)';
  if (o.r) tr += ' rotate(' + o.r.toFixed(3) + 'deg)';
  const s = o.s == null ? 1 : o.s;
  if (s !== 1) tr += ' scale(' + s.toFixed(4) + ')';
  el.style.transform = tr;
  const op = o.o == null ? 1 : clamp(o.o);
  el.style.opacity = op;
  el.style.visibility = op <= 0.001 ? 'hidden' : 'visible';
  let f = '';
  if (o.b > .05) f += 'blur(' + o.b.toFixed(2) + 'px) ';
  if (o.br != null && o.br !== 1) f += 'brightness(' + o.br.toFixed(3) + ') ';
  el.style.filter = f || 'none';
}

/* ---------- кадры исходников ---------- */
const pad = i => String(i).padStart(4, '0');
const takeSrc = s => 'frames/take/' + pad(clamp(Math.round(s * TAKE_FPS), 0, TAKE_N - 1)) + '.jpg';
const oldSrc = u => 'frames/old/' + pad(clamp(Math.floor(u * 30), 0, OLD_N - 1)) + '.jpg';
const newSrc = u => 'frames/new/' + pad(clamp(Math.floor(u * 60 + 1e-6), 0, NEW_N - 1)) + '.jpg';
let pending = [];
function img(el, src) {
  if (el.getAttribute('src') !== src) { el.setAttribute('src', src); pending.push(el.decode().catch(() => {})); }
}

/* время дубля для момента ролика: живой дубль, вайп со сжатием 4,8×, замедленный финал */
function takeTime(t) {
  if (t < WHIP) return 1.0 + t;
  if (t < HOLO_NEW) return lerp(9.0, 11.4, E.inOutCubic(P(t, WHIP, HOLO_NEW - WHIP)));
  if (t < OUT) return 11.4 + (t - HOLO_NEW);
  return 17.2 + (t - OUT) * 0.38;
}
/* ладонь по трекингу: [x, y, размер кисти, верх пальцев] */
const hand = s => window.HANDS[clamp(Math.round(s * TAKE_FPS), 0, window.HANDS.length - 1)];

/* прямоугольник голограммы над ладонью */
const SW = 300, SH = 533;
function holoRect(t, s, side) {
  const [cx, cy, sz, tip] = hand(s);
  const x = side === 'old' ? clamp(cx + 20, SW / 2 + 40, W - SW / 2 - 30) : clamp(cx, SW / 2 + 40, W - SW / 2 - 40);
  const bottom = tip - 34 + 7 * Math.sin(t * 2.4);
  return { x: x - SW / 2, y: bottom - SH, w: SW, h: SH, cx, cy, sz, tip };
}

/* ---------- построение DOM ---------- */
const scrOld = $('#scrOld'), scrNew = $('#scrNew'), shardsBox = $('#shards');
const oldImg = scrOld.querySelector('.body img'), newImg = scrNew.querySelector('.body img');
document.querySelectorAll('.handle').forEach(e => e.textContent = HANDLE);

/* полосы глитча поверх старого экрана */
const SLICES = [];
for (let i = 0; i < 7; i++) {
  const d = document.createElement('div');
  d.className = 'slice';
  d.innerHTML = '<img alt="">';
  scrOld.querySelector('.body').appendChild(d);
  SLICES.push(d);
}

/* осколки: сетка с дрожащими узлами, каждая ячейка — два треугольника */
const SHARDS = [];
{
  const r = rng(42), C = 4, R = 7, pts = [];
  for (let j = 0; j <= R; j++) for (let i = 0; i <= C; i++) {
    const edge = i === 0 || j === 0 || i === C || j === R;
    pts.push([i / C * 100 + (edge && (i === 0 || i === C) ? 0 : (r() - .5) * 16), j / R * 100 + (edge && (j === 0 || j === R) ? 0 : (r() - .5) * 9)]);
  }
  const p = (i, j) => pts[j * (C + 1) + i];
  for (let j = 0; j < R; j++) for (let i = 0; i < C; i++) {
    const a = p(i, j), b = p(i + 1, j), c = p(i + 1, j + 1), d = p(i, j + 1);
    const tris = r() < .5 ? [[a, b, c], [a, c, d]] : [[a, b, d], [b, c, d]];
    for (const tri of tris) {
      const el = document.createElement('div');
      el.className = 'shard';
      el.style.width = el.style.height = '100%';
      el.style.clipPath = 'polygon(' + tri.map(q => q[0].toFixed(2) + '% ' + q[1].toFixed(2) + '%').join(',') + ')';
      const cx = (tri[0][0] + tri[1][0] + tri[2][0]) / 3, cy = (tri[0][1] + tri[1][1] + tri[2][1]) / 3;
      el.style.transformOrigin = cx.toFixed(2) + '% ' + cy.toFixed(2) + '%';
      el.innerHTML = '<img alt="">';
      shardsBox.appendChild(el);
      SHARDS.push({ el, im: el.firstChild, cx, cy, sp: 500 + r() * 900, vz: 250 + r() * 1100,
        ax: [r() - .5, r() - .5, r() - .5], w: 260 + r() * 620, up: 200 + r() * 500 });
    }
  }
}

/* зерно плёнки */
{
  const c = document.createElement('canvas'); c.width = c.height = 256;
  const g = c.getContext('2d'), d = g.createImageData(256, 256), r = rng(9);
  for (let i = 0; i < d.data.length; i += 4) { const v = r() * 255; d.data[i] = d.data[i + 1] = d.data[i + 2] = v; d.data[i + 3] = 255; }
  g.putImageData(d, 0, 0);
  $('#grain').style.backgroundImage = 'url(' + c.toDataURL() + ')';
}

const gB = $('#fxBack').getContext('2d'), gF = $('#fxFront').getContext('2d'), gT = $('#fxTop').getContext('2d');

/* ---------- голограмма: экран в 3D ---------- */
function placeScreen(el, rc, o) {
  el.style.display = 'block';
  el.style.left = rc.x.toFixed(2) + 'px'; el.style.top = rc.y.toFixed(2) + 'px';
  el.style.width = rc.w.toFixed(2) + 'px'; el.style.height = rc.h.toFixed(2) + 'px';
  el.style.borderRadius = (o.rad == null ? 26 : o.rad).toFixed(2) + 'px';
  el.style.transformOrigin = '50% ' + (o.oy == null ? 100 : o.oy) + '%';
  el.style.transform = 'rotateX(' + (o.rx || 0).toFixed(3) + 'deg) rotateY(' + (o.ry || 0).toFixed(3) + 'deg) rotateZ(' + (o.rz || 0).toFixed(3) + 'deg) scale(' + (o.sx == null ? 1 : o.sx).toFixed(4) + ',' + (o.sy == null ? 1 : o.sy).toFixed(4) + ')';
  el.style.opacity = o.o == null ? 1 : clamp(o.o);
  el.style.filter = o.f || 'none';
}

/* включение голограммы: тонкая линия → раскрытие вверх, вспышка яркости */
function powerOn(t, t0) {
  const a = P(t, t0, 0.16), b = P(t, t0 + 0.12, 0.38);
  return { sx: E.outExpo(a), sy: lerp(0.012, 1, E.outBackS(b)), br: 1 + 2.4 * hit(t, t0 + 0.12, 7), on: a > 0 };
}

/* луч от ладони к экрану и излучатель-кольцо на ладони */
function drawBeam(g, rc, col, k, t) {
  if (k <= 0.001) return;
  const px = rc.cx, py = rc.cy - rc.sz * 0.25, s = rc.sz;
  const by = lerp(py, rc.tip, 0.4);                     // луч выходит из-за пальцев
  g.save();
  g.globalCompositeOperation = 'lighter';
  // конус
  const gr = g.createLinearGradient(0, py, 0, rc.y + rc.h);
  gr.addColorStop(0, `rgba(${col},${0.55 * k})`);
  gr.addColorStop(1, `rgba(${col},${0.10 * k})`);
  g.fillStyle = gr;
  g.beginPath();
  g.moveTo(px - s * 0.42, by);
  g.lineTo(rc.x + 10, rc.y + rc.h);
  g.lineTo(rc.x + rc.w - 10, rc.y + rc.h);
  g.lineTo(px + s * 0.42, by);
  g.closePath();
  g.fill();
  // светящиеся нити внутри конуса
  for (let i = 0; i < 7; i++) {
    const u = (i + 0.5) / 7, fl = 0.5 + 0.5 * Math.sin(t * 9 + i * 2.1);
    g.strokeStyle = `rgba(${col},${0.22 * k * fl})`;
    g.lineWidth = 2;
    g.beginPath();
    g.moveTo(px + (u - .5) * s * 0.8, by);
    g.lineTo(rc.x + 10 + u * (rc.w - 20), rc.y + rc.h);
    g.stroke();
  }
  // свет на ладони
  const rg = g.createRadialGradient(px, py, 0, px, py, s * 1.6);
  rg.addColorStop(0, `rgba(${col},${0.55 * k})`);
  rg.addColorStop(1, `rgba(${col},0)`);
  g.fillStyle = rg;
  g.fillRect(px - s * 2, py - s * 2, s * 4, s * 4);
  // кольцо-излучатель в перспективе
  for (let ring = 0; ring < 2; ring++) {
    const R = s * (0.95 + ring * 0.32), rot = t * (ring ? -2.2 : 3.1);
    g.strokeStyle = `rgba(255,255,255,${(0.75 - ring * 0.3) * k})`;
    g.shadowColor = `rgba(${col},1)`; g.shadowBlur = 18;
    g.lineWidth = ring ? 2.5 : 4;
    for (let d = 0; d < 6; d++) {
      g.beginPath();
      g.ellipse(px, py, R, R * 0.28, 0, rot + d * Math.PI / 3, rot + d * Math.PI / 3 + Math.PI / 5);
      g.stroke();
    }
  }
  g.restore();
}

/* искры, поднимающиеся по лучу */
function drawMotes(g, rc, col, k, t, seed) {
  if (k <= 0.001) return;
  const r = rng(seed), px = rc.cx, py = rc.cy - rc.sz * 0.25;
  g.save();
  g.globalCompositeOperation = 'lighter';
  for (let i = 0; i < 46; i++) {
    const ph = r(), sp = 0.55 + r() * 0.9, u = r(), sz = 1.5 + r() * 3.5;
    const q = (t * sp + ph) % 1;                       // 0 — ладонь, 1 — экран
    const x = lerp(px + (u - .5) * rc.sz * 0.8, rc.x + 10 + u * (rc.w - 20), q) + Math.sin(t * 3 + i) * 6;
    const y = lerp(py, rc.y + rc.h * (1 - 0.6 * r()), q);
    const a = k * Math.sin(Math.PI * q) * (0.5 + 0.5 * Math.sin(t * 13 + i * 3));
    g.fillStyle = `rgba(255,255,255,${a})`;
    g.shadowColor = `rgba(${col},1)`; g.shadowBlur = 12;
    g.beginPath(); g.arc(x, y, sz, 0, Math.PI * 2); g.fill();
  }
  g.restore();
}

/* четырёхлучевая звёздочка */
function star(g, x, y, R, a, col) {
  if (a <= 0.003) return;
  g.save();
  g.globalCompositeOperation = 'lighter';
  g.translate(x, y);
  g.fillStyle = `rgba(255,255,255,${a})`;
  g.shadowColor = col; g.shadowBlur = R * 1.6;
  g.beginPath();
  for (let i = 0; i < 8; i++) {
    const ang = i * Math.PI / 4, rr = i % 2 ? R * 0.18 : R;
    g.lineTo(Math.cos(ang) * rr, Math.sin(ang) * rr);
  }
  g.closePath(); g.fill();
  g.restore();
}

/* блёстки вокруг прямоугольника */
function sparkles(g, rc, k, t, seed, n = 18) {
  if (k <= 0.001) return;
  const r = rng(seed);
  for (let i = 0; i < n; i++) {
    const side = r(), u = r(), ph = r(), pr = 0.9 + r() * 1.4;
    let x, y;
    if (side < .5) { x = rc.x + u * rc.w; y = side < .25 ? rc.y - 30 - r() * 60 : rc.y + rc.h + 20 + r() * 50; }
    else { y = rc.y + u * rc.h; x = side < .75 ? rc.x - 30 - r() * 60 : rc.x + rc.w + 30 + r() * 60; }
    const tw_ = Math.max(0, Math.sin((t / pr + ph) * Math.PI * 2));
    star(g, x, y, 10 + r() * 18, k * tw_ * tw_, i % 3 ? 'rgba(255,60,160,1)' : 'rgba(255,210,122,1)');
  }
}

/* взрыв частиц из точки */
function burst(g, x, y, t, t0, seed, n, col, spd = 900, life = 0.8) {
  const dt = t - t0;
  if (dt < 0 || dt > life) return;
  const r = rng(seed), k = 1 - dt / life;
  g.save();
  g.globalCompositeOperation = 'lighter';
  for (let i = 0; i < n; i++) {
    const a = r() * Math.PI * 2, v = spd * (0.35 + r() * 0.65), sz = 2 + r() * 4;
    const d = v * (1 - Math.exp(-dt * 4)) / 4 * 3;
    const px = x + Math.cos(a) * d, py = y + Math.sin(a) * d + 300 * dt * dt;
    g.fillStyle = i % 4 ? `rgba(255,255,255,${k})` : `rgba(${col},${k})`;
    g.shadowColor = `rgba(${col},1)`; g.shadowBlur = 10;
    g.beginPath(); g.arc(px, py, sz * k + 0.5, 0, Math.PI * 2); g.fill();
  }
  g.restore();
}

/* ударная волна */
function shock(g, x, y, t, t0, maxR, col, life = 0.55, lw = 26) {
  const dt = t - t0;
  if (dt < 0 || dt > life) return;
  const q = E.outCubic(dt / life), k = 1 - dt / life;
  g.save();
  g.globalCompositeOperation = 'lighter';
  g.strokeStyle = `rgba(${col},${0.8 * k})`;
  g.lineWidth = lw * k + 1;
  g.shadowColor = `rgba(${col},1)`; g.shadowBlur = 40;
  g.beginPath(); g.arc(x, y, maxR * q, 0, Math.PI * 2); g.stroke();
  g.restore();
}

/* 3D-цветы M Cosmetic: пятилепестковые, кувыркаются в полёте (поворот по Y — сжатие по ширине) */
function flower(g, x, y, R, rot, flip, a) {
  if (a <= 0.003) return;
  g.save();
  g.translate(x, y);
  g.rotate(rot);
  g.scale(Math.max(0.08, Math.abs(Math.cos(flip))), 1);
  g.globalAlpha = a;
  const back = Math.cos(flip) < 0;            // изнанка лепестков темнее
  for (let i = 0; i < 5; i++) {
    g.rotate(Math.PI * 2 / 5);
    const gr = g.createLinearGradient(0, 0, 0, -R);
    gr.addColorStop(0, back ? '#B8125F' : '#FF3D9A');
    gr.addColorStop(1, back ? '#E05596' : '#FFC3E0');
    g.fillStyle = gr;
    g.beginPath();
    g.ellipse(0, -R * 0.52, R * 0.34, R * 0.5, 0, 0, Math.PI * 2);
    g.fill();
  }
  g.fillStyle = '#FFE7A8';
  g.beginPath(); g.arc(0, 0, R * 0.17, 0, Math.PI * 2); g.fill();
  g.restore();
}

/* разлёт цветов из точки: скорость, лёгкая гравитация, парение */
function flowers(g, x, y, t, t0, seed, n, spd = 700, life = 2.2, sx = 0, sy = 0) {
  const dt = t - t0;
  if (dt < 0 || dt > life) return;
  const r = rng(seed);
  for (let i = 0; i < n; i++) {
    const a = r() * Math.PI * 2, v = spd * (0.3 + r() * 0.7), R = 14 + r() * 22;
    const ox = (r() - .5) * sx, oy = (r() - .5) * sy;
    const d = v * (1 - Math.exp(-dt * 2.6)) / 2.6;
    const px = x + ox + Math.cos(a) * d + Math.sin(dt * (2 + r() * 2) + i) * 26;
    const py = y + oy + Math.sin(a) * d * 0.8 + 160 * dt * dt;
    const k = Math.min(1, dt * 8) * (1 - P(dt, life * 0.65, life * 0.35));
    flower(g, px, py, R, r() * 6 + dt * (r() - .5) * 5, r() * 6 + dt * (3 + r() * 5), k);
  }
}

/* анаморфный блик: тонкая горизонтальная полоса света */
function flare(g, x, y, t, t0, col, w = 1100, life = 0.45) {
  const dt = t - t0;
  if (dt < 0 || dt > life) return;
  const k = Math.pow(1 - dt / life, 1.6);
  g.save();
  g.globalCompositeOperation = 'lighter';
  for (const [hh, a] of [[60, 0.25], [14, 0.6], [4, 1]]) {
    const gr = g.createLinearGradient(x - w, 0, x + w, 0);
    gr.addColorStop(0, `rgba(${col},0)`);
    gr.addColorStop(0.5, `rgba(${col},${a * k})`);
    gr.addColorStop(1, `rgba(${col},0)`);
    g.fillStyle = gr;
    g.beginPath(); g.ellipse(x, y, w * (0.6 + 0.4 * dt / life), hh * k + 1, 0, 0, Math.PI * 2); g.fill();
  }
  g.restore();
}

const ICE = '175,210,240', PINK = '255,46,147', GOLD = '255,210,122';

/* ---------- кадр ---------- */
async function renderAt(t) {
  pending = [];
  gB.clearRect(0, 0, W, H); gF.clearRect(0, 0, W, H); gT.clearRect(0, 0, W, H);
  const s = takeTime(t);

  /* фон: дубль */
  const bg = $('#bg');
  img(bg, takeSrc(s));

  /* камера: удары на долях, тряска, вайп, наезд при вылете экрана */
  let cs = 1 + 0.05 * hit(t, 0) + 0.035 * hit(t, 1.0) + 0.05 * hit(t, STAMP) + 0.07 * hit(t, SHATTER, 7)
    + 0.03 * hit(t, HOLO_NEW) + 0.02 * hit(t, BADGE);
  const shake = 26 * hit(t, STAMP, 8) + 34 * hit(t, SHATTER, 7);
  let cx = shake * Math.sin(t * 87), cy = shake * Math.cos(t * 71);
  // вайп: уезжаем влево, приезжаем справа
  cx += t < WHIP + 0.25 ? -280 * E.inCubic(P(t, WHIP - 0.1, 0.35)) : 280 * (1 - E.outCubic(P(t, WHIP + 0.25, 0.32)));
  const whipBlur = 90 * Math.exp(-Math.pow((t - (WHIP + 0.25)) / 0.13, 2));
  let bgZoom = { k: 0, ox: W / 2, oy: H / 2 };
  let fk = t < FLY ? 0 : kf(t, [[FLY, 0], [FLY + 0.28, -0.07, E.outCubic], [LAND, 1, E.inCubic]]);
  const fkp = Math.max(0, fk);

  /* ---- голограмма «старое» ---- */
  const oldOn = t >= HOLO_OLD && t < SHATTER;
  let rcOld = null;
  if (t >= HOLO_OLD && t < WHIP + 0.1) rcOld = holoRect(t, s, 'old');
  if (oldOn) {
    const pw = powerOn(t, HOLO_OLD);
    const u = t - HOLO_OLD + 0.45;                  // без белого вступления старого ролика
    img(oldImg, oldSrc(u));
    const gl = t >= STAMP ? Math.min(1, 0.35 + 0.65 * (t - STAMP)) : 0;      // сила глитча
    const fr = Math.floor(t * 15), rr = rng(fr * 31 + 5);
    const burstOn = gl > 0 && rr() < 0.25 + 0.6 * gl;
    const desat = 0.85 * P(t, STAMP, 0.6);
    placeScreen(scrOld, rcOld, {
      sx: pw.sx, sy: pw.sy, ry: -17 + 3 * Math.sin(t * 1.3), rx: 4 + 2 * Math.sin(t * 1.7), rz: burstOn ? (rr() - .5) * 3 : 0,
      o: 0.94 - 0.12 * (burstOn ? rr() : 0),
      f: `brightness(${(pw.br * (1 - 0.15 * desat)).toFixed(3)}) saturate(${(0.9 - desat * 0.7).toFixed(3)})` + (gl ? ' url(#rgb)' : ''),
    });
    scrOld.querySelector('.rim').style.borderColor = `rgba(${ICE},.9)`;
    scrOld.style.boxShadow = `0 0 40px 6px rgba(${ICE},.45)`;
    $('#rgbR').setAttribute('dx', burstOn ? (8 + 18 * gl * rr()).toFixed(1) : '0');
    $('#rgbB').setAttribute('dx', burstOn ? (-8 - 18 * gl * rr()).toFixed(1) : '0');
    SLICES.forEach((sl, i) => {
      if (!burstOn || rr() < 0.45) { sl.style.display = 'none'; return; }
      sl.style.display = 'block';
      const y0 = rr() * 90, hh = 3 + rr() * 12;
      sl.style.clipPath = `inset(${y0.toFixed(1)}% 0 ${(100 - y0 - hh).toFixed(1)}% 0)`;
      sl.style.transform = `translateX(${((rr() - .5) * 90 * gl).toFixed(1)}px)`;
      img(sl.firstChild, oldSrc(u - 0.1 * rr()));
    });
    drawBeam(gB, rcOld, ICE, pw.on ? Math.min(1, P(t, HOLO_OLD, 0.3)) * (burstOn ? 0.5 : 1) : 0, t);
    drawMotes(gF, rcOld, ICE, P(t, HOLO_OLD + 0.3, 0.4), t, 3);
    flare(gF, rcOld.x + rcOld.w / 2, rcOld.y + rcOld.h, t, HOLO_OLD + 0.12, ICE, 700);
  } else scrOld.style.display = 'none';

  /* осколки */
  if (t >= SHATTER && t < SHATTER + 0.95) {
    const rc = holoRect(SHATTER, takeTime(SHATTER), 'old'), dt = t - SHATTER;
    placeScreen(shardsBox, rc, { ry: -17, rx: 4, oy: 50 });
    shardsBox.style.overflow = 'visible';
    const src = oldSrc(SHATTER - HOLO_OLD + 0.45);
    for (const sh of SHARDS) {
      sh.el.style.display = 'block';
      img(sh.im, src);
      const dx = sh.cx - 50, dy = (sh.cy - 50) * 1.78, len = Math.hypot(dx, dy) + 1e-3;
      const d = sh.sp * (1 - Math.exp(-dt * 3)) / 3 * 2.2;
      const x = dx / len * d, y = dy / len * d - sh.up * dt + 1500 * dt * dt, z = sh.vz * dt;
      const ang = sh.w * dt;
      sh.el.style.transform = `translate3d(${x.toFixed(1)}px,${y.toFixed(1)}px,${z.toFixed(1)}px) rotate3d(${sh.ax[0].toFixed(3)},${sh.ax[1].toFixed(3)},${sh.ax[2].toFixed(3)},${ang.toFixed(1)}deg)`;
      sh.el.style.opacity = 1 - P(dt, 0.4, 0.5);
      sh.el.style.filter = `grayscale(.35) brightness(${(1.1 + 2.2 * hit(dt, 0, 10)).toFixed(3)})`;
    }
    burst(gF, rc.x + rc.w / 2, rc.y + rc.h / 2, t, SHATTER, 77, 60, ICE, 1300, 0.7);
    shock(gF, rc.x + rc.w / 2, rc.y + rc.h / 2, t, SHATTER, 520, ICE, 0.45, 18);
  } else shardsBox.style.display = 'none';

  /* подпись «1 · ESKISI» и линия-выноска к экрану */
  if (rcOld && t < SHATTER + 0.2) {
    const k = E.outBackS(P(t, 2.0, 0.4)), out = P(t, SHATTER - 0.05, 0.2);
    const x = rcOld.x - 185, y = rcOld.y + 140;
    S($('#chipOld'), { x, y: y + 30 * (1 - k), s: (0.6 + 0.4 * k) * (1 - 0.4 * out), o: P(t, 2.0, 0.12) * (1 - out), r: -3 + 3 * k });
    const a = P(t, 2.15, 0.3) * (1 - out);
    if (a > 0) {
      gF.save();
      gF.strokeStyle = `rgba(255,255,255,${0.85 * a})`; gF.lineWidth = 3; gF.setLineDash([10, 8]);
      gF.beginPath(); gF.moveTo(x + 150, y); gF.lineTo(lerp(x + 150, rcOld.x + 14, a), y); gF.stroke();
      gF.setLineDash([]); gF.fillStyle = `rgba(255,255,255,${a})`;
      gF.beginPath(); gF.arc(rcOld.x + 14, y, 7 * a, 0, Math.PI * 2); gF.fill();
      gF.restore();
    }
  } else S($('#chipOld'), { o: 0 });

  /* штамп «G‘ALATI» */
  if (rcOld && t >= STAMP && t < SHATTER + 0.2) {
    const k = P(t, STAMP, 0.16), out = P(t, SHATTER, 0.15);
    S($('#stamp'), { x: Math.min(rcOld.x + rcOld.w / 2, 790) + 6 * Math.sin(t * 60) * hit(t, STAMP, 10), y: rcOld.y + rcOld.h * 0.46,
      s: lerp(3.2, 0.82, E.outExpo(k)) * (1 + 0.5 * out), r: -14, o: Math.min(1, k * 3) * (1 - out), b: 10 * (1 - k) });
    burst(gF, Math.min(rcOld.x + rcOld.w / 2, 790), rcOld.y + rcOld.h * 0.46, t, STAMP + 0.08, 12, 26, '255,59,59', 700, 0.5);
  } else S($('#stamp'), { o: 0 });

  /* ---- голограмма «новое» ---- */
  const newOn = t >= HOLO_NEW && t < LAND;
  if (newOn) {
    const pw = powerOn(t, HOLO_NEW);
    img(newImg, newSrc(t - N0));
    const live = holoRect(t, s, 'new');
    const rc = {
      x: lerp(live.x, 0, fkp), y: lerp(live.y, 0, fkp), w: lerp(live.w, W, fkp), h: lerp(live.h, H, fkp),
      cx: live.cx, cy: live.cy, sz: live.sz, tip: live.tip,
    };
    const pull = Math.min(0, fk);                       // замах перед вылетом
    const ry0 = 16 + 3 * Math.sin(t * 1.2);
    placeScreen(scrNew, rc, {
      sx: pw.sx * (1 + pull * 0.6), sy: pw.sy * (1 + pull * 0.6), oy: lerp(100, 50, fkp),
      ry: lerp(ry0, 0, E.outCubic(fkp)) + 22 * Math.sin(Math.PI * fkp), rx: lerp(-3, 0, fkp) - 40 * pull,
      rz: -6 * Math.sin(Math.PI * fkp), rad: lerp(26, 0, fkp),
      f: `brightness(${pw.br.toFixed(3)})`,
    });
    scrNew.querySelector('.rim').style.borderColor = `rgba(255,255,255,${(0.95 * (1 - fkp)).toFixed(3)})`;
    scrNew.querySelector('.scan').style.opacity = 1 - fkp;
    scrNew.querySelector('.glass').style.opacity = 1 - fkp * 0.7;
    scrNew.style.boxShadow = `0 0 ${(60 * (1 - fkp)).toFixed(1)}px ${(10 * (1 - fkp)).toFixed(1)}px rgba(${PINK},.75), 0 0 0 ${(6 * (1 - fkp)).toFixed(1)}px rgba(${PINK},.55)`;
    const beamK = Math.min(1, P(t, HOLO_NEW, 0.3)) * (1 - P(t, FLY + 0.1, 0.3));
    drawBeam(gB, live, PINK, beamK, t);
    drawMotes(gF, live, GOLD, P(t, HOLO_NEW + 0.3, 0.4) * (1 - P(t, FLY, 0.3)), t, 5);
    flare(gF, live.x + live.w / 2, live.y + live.h, t, HOLO_NEW + 0.12, PINK, 800);
    flowers(gF, live.x + live.w / 2, live.y + live.h * 0.5, t, N0 + 0.12, 53, 10, 520, 1.7, live.w, live.h * 0.6);
    sparkles(gF, live, P(t, N0, 0.5) * (1 - P(t, FLY, 0.3)), t, 11, 22);

    /* подпись «2 · YANGISI» */
    const k = E.outBackS(P(t, 6.5, 0.4)), out = P(t, FLY, 0.25);
    S($('#chipNew'), { x: live.x + live.w + 185, y: live.y + live.h - 70 + 30 * (1 - k), s: (0.6 + 0.4 * k) * (1 - 0.3 * out),
      o: P(t, 6.5, 0.12) * (1 - out), r: 3 - 3 * k, b: 12 * out });
    /* золотая галочка */
    const bk = E.outBackS(P(t, BADGE, 0.45));
    S($('#badge'), { x: live.x + live.w - 10, y: live.y + 10, s: bk * (1 - out) + 0.001, r: lerp(-40, 0, bk), o: P(t, BADGE, 0.05) * (1 - out) });
    burst(gF, live.x + live.w - 10, live.y + 10, t, BADGE, 21, 40, GOLD, 900, 0.8);
    shock(gF, live.x + live.w - 10, live.y + 10, t, BADGE, 260, GOLD, 0.5, 14);
    // фон уезжает в глубину вслед за экраном
    bgZoom = { k: fkp, ox: live.x + live.w / 2, oy: live.y + live.h / 2 };
  } else {
    scrNew.style.display = 'none';
    S($('#chipNew'), { o: 0 }); S($('#badge'), { o: 0 });
  }
  $('#stage').style.perspectiveOrigin = '50% 40%';

  const camEl = $('#cam');
  camEl.style.transform = `translate(${cx.toFixed(2)}px,${cy.toFixed(2)}px) scale(${cs.toFixed(4)})`;
  $('#mblurG').setAttribute('stdDeviation', whipBlur.toFixed(1) + ' 0');
  camEl.style.filter = whipBlur > 0.6 ? 'url(#mblur)' : 'none';
  bg.style.filter = `contrast(1.07) saturate(1.12) brightness(1.03)` + (bgZoom.k > 0 ? ` blur(${(14 * bgZoom.k).toFixed(2)}px)` : '');
  bg.style.transformOrigin = `${bgZoom.ox.toFixed(1)}px ${bgZoom.oy.toFixed(1)}px`;
  bg.style.transform = `scale(${(1 + 0.45 * bgZoom.k * bgZoom.k).toFixed(4)})`;
  camEl.style.display = t < LAND ? 'block' : 'none';

  /* ---- новое видео на весь экран ---- */
  const full = $('#full');
  if (t >= LAND && t < OUT) {
    full.style.display = 'block';
    img(full, newSrc(t - N0));
    const k = hit(t, LAND, 7);
    full.style.transform = `scale(${(1 + 0.06 * k).toFixed(4)})`;
    $('#rgbR').setAttribute('dx', (22 * k).toFixed(1)); $('#rgbB').setAttribute('dx', (-22 * k).toFixed(1));
    full.style.filter = k > 0.04 ? 'url(#rgb)' : 'none';
    shock(gT, W / 2, H / 2, t, LAND, 1300, '255,255,255', 0.6, 40);
    burst(gT, W / 2, H / 2, t, LAND, 31, 90, GOLD, 2400, 1.0);
    flare(gT, W / 2, H / 2, t, LAND, '255,235,245', 1300, 0.6);
    flowers(gT, W / 2, H / 2, t, LAND, 61, 26, 1500, 1.6);
  } else full.style.display = 'none';
  /* плашка «YANGISI ✓» в первые секунды полного кадра — понятно, чьё это видео */
  {
    const k = E.outBackS(P(t, LAND + 0.3, 0.45)), out = E.inCubic(P(t, LAND + 2.6, 0.35));
    S($('#fullTag'), { x: lerp(-200, 215, k) - 420 * out, y: 225, s: 1, r: -3, o: t >= LAND && t < OUT ? P(t, LAND + 0.3, 0.1) : 0 });
  }

  /* ---- финал «1 или 2?» ---- */
  const outro = $('#outro');
  if (t >= OUT) {
    outro.style.display = 'block';
    const ob = $('#obg');
    img(ob, takeSrc(s));
    ob.style.filter = `blur(${tw(t, OUT, 0.6, 0, 14).toFixed(2)}px) saturate(1.1)`;
    ob.style.transform = `scale(${(1.04 + 0.03 * (t - OUT) / 3).toFixed(4)})`;
    $('#oshade').style.opacity = tw(t, OUT, 0.5, 0, 1);

    // карточка 2: новое видео съезжается из полного кадра в карточку
    const c2 = $('#card2'), k2 = E.inOutExpo(P(t, OUT, 0.55));
    const T2 = { x: 600, y: 650, w: 360, h: 640 };
    c2.style.left = lerp(0, T2.x, k2) + 'px'; c2.style.top = lerp(0, T2.y, k2) + 'px';
    c2.style.width = lerp(W, T2.w, k2) + 'px'; c2.style.height = lerp(H, T2.h, k2) + 'px';
    const bob2 = Math.sin(t * 2.2) * 8 * k2;
    const win = E.outBackS(P(t, WIN, 0.5));
    const pulse = 0.05 * hit(t, FINAL, 6);
    c2.style.transform = `translateX(${(-40 * win).toFixed(2)}px) translateY(${bob2.toFixed(2)}px) rotateY(${(-10 * k2 + 3 * Math.sin(t * 1.4) * k2 + 6 * win).toFixed(2)}deg) rotateX(${(4 * k2).toFixed(2)}deg) scale(${(1 + 0.1 * win + pulse).toFixed(4)})`;
    c2.querySelector('.body').style.borderRadius = c2.style.borderRadius = (30 * k2).toFixed(1) + 'px';
    c2.querySelector('.body').style.borderWidth = (5 * k2).toFixed(2) + 'px';
    img(c2.querySelector('img'), t < OUT + 0.55 ? newSrc(t - N0) : newSrc(2.6 + ((t - OUT - 0.55) % 12)));
    const m2 = E.outBackS(P(t, 24.0, 0.4));
    c2.querySelector('.num').style.opacity = P(t, OUT + 0.5, 0.15);
    c2.querySelector('.mark').style.transform = `translateZ(40px) scale(${(m2 + 0.001).toFixed(3)}) rotate(${lerp(-60, 0, m2).toFixed(1)}deg)`;

    // карточка 1: старое видео прилетает из глубины слева
    const c1 = $('#card1'), k1 = E.outBack(P(t, 22.7, 0.6));
    c1.style.left = '120px'; c1.style.top = '700px';
    const bob1 = Math.sin(t * 2.0 + 1.3) * 8;
    const back = E.outCubic(P(t, WIN, 0.6));          // старое уходит в тень
    c1.style.transform = `translate3d(${(lerp(-700, 0, k1) - 30 * back).toFixed(1)}px,${bob1.toFixed(1)}px,${(lerp(-900, -120, k1) - 200 * back).toFixed(1)}px) rotateY(${(lerp(70, 14, k1) + 8 * back).toFixed(2)}deg) rotateZ(${(-2 * k1).toFixed(2)}deg)`;
    c1.style.opacity = P(t, 22.7, 0.15);
    const x1 = P(t, 23.5, 0.3);
    c1.style.filter = `grayscale(${(0.85 * x1).toFixed(3)}) brightness(${(1 - 0.25 * x1 - 0.2 * back).toFixed(3)})`;
    img(c1.querySelector('img'), oldSrc(1.0 + ((t - 22.7) % 10)));
    const m1 = E.outBackS(P(t, 23.5, 0.35));
    c1.querySelector('.mark').style.transform = `translateZ(40px) scale(${(m1 + 0.001).toFixed(3)}) rotate(${lerp(60, 0, m1).toFixed(1)}deg)`;

    S($('#otag'), { x: 540, y: 300, s: E.outBackS(P(t, 22.9, 0.4)) + 0.001, o: P(t, 22.9, 0.1) });
    const kq = P(t, 23.0, 0.35);
    S($('#oq'), { x: 540, y: 470 + 6 * Math.sin(t * 2.6), s: lerp(1.9, 1, E.outExpo(kq)), o: Math.min(1, kq * 4), b: 14 * (1 - E.outExpo(kq)) });
    // подписи под карточками
    const l1 = E.outBackS(P(t, 23.25, 0.4)), l2 = E.outBackS(P(t, 23.4, 0.4));
    S($('#lab1'), { x: 300 - 30 * back, y: 1385 + 30 * (1 - l1), s: (0.6 + 0.4 * l1) * (1 - 0.12 * back), o: P(t, 23.25, 0.1) * (1 - 0.35 * back) });
    S($('#lab2'), { x: 780 - 40 * win, y: 1370 + 30 * (1 - l2) + 36 * win, s: (0.6 + 0.4 * l2) * (1 + 0.08 * win + pulse), o: P(t, 23.4, 0.1) });
    const kc = E.outBackS(P(t, 24.5, 0.45));
    S($('#oc'), { x: 540, y: 1520 + 40 * (1 - kc), s: (0.7 + 0.3 * kc) * (1 + 0.08 * hit(t, FINAL, 5)), o: P(t, 24.5, 0.12) });
    $('#outro').style.transform = `scale(${(1 + 0.035 * E.inOutCubic(P(t, FINAL, DUR - FINAL))).toFixed(4)})`;

    sparkles(gT, { x: 600, y: 650, w: 360, h: 640 }, P(t, 24.0, 0.4), t, 17, 20);
    flowers(gT, 960, 640, t, 24.0, 67, 14, 650, 1.5);
    burst(gT, 960, 640, t, 24.0, 41, 40, GOLD, 900, 0.8);
    shock(gT, 960, 640, t, 24.0, 300, GOLD, 0.5, 14);
    burst(gT, 470, 690, t, 23.5, 43, 22, '255,59,59', 600, 0.6);
    // победитель: дождь цветов, волна и блик
    flowers(gT, 540, -60, t, WIN, 71, 26, 500, 2.6, 1100, 80);
    shock(gT, 740, 970, t, WIN, 520, PINK, 0.6, 18);
    flare(gT, 740, 970, t, WIN, '255,200,230', 900, 0.5);
    flowers(gT, 740, 970, t, FINAL, 73, 20, 1100, 1.8);
    burst(gT, 740, 970, t, FINAL, 79, 50, GOLD, 1400, 0.9);
  } else outro.style.display = 'none';

  /* ---- заголовок ---- */
  {
    const dock = E.inOutCubic(P(t, HOLO_OLD - 0.1, 0.5));
    const exit = E.inCubic(P(t, FLY, 0.4));
    const on = t < LAND;
    S($('#title'), { x: 540, y: lerp(430, 296, dock) - 260 * exit + 4 * Math.sin(t * 2.1), s: lerp(1, 0.64, dock),
      o: on ? 1 - exit : 0, b: 16 * exit });
    const ka = E.outBackS(P(t, 0, 0.42));
    S2($('#tagWrap'), `scale(${(ka + 0.001).toFixed(3)}) rotate(${lerp(-12, 0, ka).toFixed(2)}deg)`, P(t, 0, 0.06));
    const k1 = E.outExpo(P(t, 0.5, 0.35));
    S2($('#l1 .w'), `translateY(${lerp(-120, 0, k1).toFixed(1)}px) scale(${lerp(1.7, 1, k1).toFixed(3)})`, Math.min(1, k1 * 3), 12 * (1 - k1));
    const k2 = E.outExpo(P(t, 1.0, 0.3));
    S2($('#l2a'), `translateX(${lerp(-180, 0, k2).toFixed(1)}px)`, Math.min(1, k2 * 3), 10 * (1 - k2));
    const k3 = E.outBackS(P(t, 1.06, 0.4));
    S2($('#l2b'), `scale(${lerp(2.6, 1, P(t, 1.06, 0.2) ** 0.5).toFixed(3)}) rotate(${lerp(10, -3, k3).toFixed(2)}deg)`, P(t, 1.06, 0.08));
  }

  /* ---- пост ---- */
  /* цветы разлетаются из «KO‘RDINGIZMI?» */
  flowers(gT, 540, 520, t, 1.06, 47, 22, 900, 1.9, 600, 60);

  const flash = 0.85 * hit(t, 0, 14) + 0.5 * hit(t, 1.06, 16) + 0.9 * hit(t, SHATTER, 18) + 0.6 * hit(t, HOLO_NEW + 0.12, 12)
    + 1.0 * hit(t, LAND, 10) + 0.5 * hit(t, OUT + 0.55, 14) + 0.25 * hit(t, WIN, 12) + 0.35 * hit(t, FINAL, 10);
  $('#flash').style.opacity = clamp(flash);
  $('#leak').style.opacity = clamp(0.9 * Math.exp(-Math.pow((t - (WHIP + 0.3)) / 0.35, 2)) + 0.7 * hit(t, LAND, 3) + 0.4 * hit(t, 22.9, 3));
  const fr = Math.floor(t * 30);
  $('#grain').style.backgroundPosition = `${Math.floor(hash(fr) * 256)}px ${Math.floor(hash(fr + 99) * 256)}px`;
  $('#fade').style.opacity = E.inOutCubic(P(t, DUR - 0.8, 0.8));      // плавное затемнение в конце

  await Promise.all(pending);
}

/* трансформ вложенного элемента: строка transform, прозрачность, блюр */
function S2(el, tr, op, b) {
  el.style.transform = tr;
  el.style.opacity = clamp(op);
  el.style.filter = b > 0.05 ? `blur(${b.toFixed(2)}px)` : 'none';
}

window.DURATION = DUR;
window.renderAt = renderAt;
window.ready = document.fonts.ready.then(() => renderAt(0));

/* предпросмотр: index.html?t=12.5 — стоп-кадр, без параметра — по кругу */
const q = new URLSearchParams(location.search);
if (!navigator.webdriver) {
  if (q.has('t')) window.ready.then(() => renderAt(+q.get('t')));
  else window.ready.then(() => {
    const t0 = performance.now();
    const loop = async () => { await renderAt(((performance.now() - t0) / 1000) % DUR); requestAnimationFrame(loop); };
    loop();
  });
}
