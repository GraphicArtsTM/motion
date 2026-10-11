/* ЮЛДУЗ — раскадровка. Каждый план: [начало, конец, функция(t — локальное время, T — глобальное)].
   AT — когда звучит каждая реплика (секунды от начала). Губы двигаются по огибающей голоса (voice_data.js).
   SFX — звуковые события для audio.py; SECTIONS — музыкальные части. */
'use strict';

/* ---------- реплики ---------- */
const AT = {
  p1: 1.2, p2: 5.3,
  a1: 13.7, a2: 21.8, a3: 31.3, a4: 39.85, a5: 42.15, a6: 44.7,
  b1: 47.9, b2: 51.45, b3: 53.25, b4: 55.75, b5: 60.75, b6: 63.15, b7: 67.7,
  c1: 72.2, c2: 82.9, c3: 90.3, c4: 93.5, c5: 103.7, c6: 110.6,
  d1: 118.7, d2: 122.15, d3: 124.75, d4: 130.3, d5: 132.45, d6: 135.25, d7: 141.9, d8: 145.2, d9: 153.2, d10: 158.1,
  e1: 170.5, e2: 176.3, e3: 179.7, e4: 182.2, e5: 184.8, e6: 187.9,
};
const VD = window.VOICE || {};
/* раскрытие рта для реплики id в момент T (на «двойках», как в аниме) */
function lip(id, T) {
  const v = VD[id];
  if (!v) return 0;
  const k = Math.floor((on2(T) - AT[id]) * FPS);
  if (k < 0 || k >= v.env.length) return 0;
  const e = v.env[k];
  return e < .12 ? 0 : clamp(.25 + e * .9);
}
function lineOn(id, T) { const v = VD[id]; return v && T >= AT[id] && T < AT[id] + v.dur; }
/* моргание раз в ~3 с */
function blinkAt(T, seed = 0) {
  const per = 3.1 + (seed % 3) * .7, ph = (T + seed * 1.37) % per;
  return ph < .05 ? ph / .05 : ph < .11 ? 1 - (ph - .05) / .06 : 0;
}

/* ---------- субтитры ---------- */
function subtitleAt(T) {
  for (const id in AT) {
    const v = VD[id];
    if (!v) continue;
    if (T >= AT[id] - .05 && T < AT[id] + v.dur + .25) {
      const sp = (window.SPEAKERS || {})[v.who] || { name: '', color: '#fff' };
      const big = id === 'd10';
      return `<span class="who" style="color:${sp.color}">${sp.name}${v.who === 'jasurVO' ? ' · мысли' : ''}</span><span style="${big ? 'font-size:64px;color:#FFE7A0' : ''}${v.who === 'jasurVO' ? ';font-style:italic' : ''}">${v.sub}</span>`;
    }
  }
  return '';
}

/* ---------- хелперы планов ---------- */
const C = (who, x, y, s, o, extra) => g(bust(who, o), tr(x, y, s), extra);
const cam = (inner, s = 1, cx = W / 2, cy = H / 2, dx = 0, dy = 0, r = 0) =>
  g(inner, `translate(${f2(cx + dx)} ${f2(cy + dy)}) rotate(${f2(r)}) scale(${f2(s)}) translate(${f2(-cx)} ${f2(-cy)})`);
const shakeAt = (T, amp, freq = 30) => [noise1(T * freq) * amp, noise1(T * freq + 50) * amp];
const fadeBlack = op => op > 0.001 ? rect(-50, -50, W + 100, H + 100, '#000', `opacity="${f2(op)}"`) : '';
const fadeWhite = op => op > 0.001 ? rect(-50, -50, W + 100, H + 100, '#FFF8E8', `opacity="${f2(op)}"`) : '';
const blurG = (inner, id) => g(inner, '', `filter="url(#${id})"`);
const bokeh = (t, seed, cols, n = 18) => {
  const r = rng(seed); let s = '';
  for (let i = 0; i < n; i++) {
    const x = r() * W, y = r() * H + Math.sin(t * .6 + i) * 20 - t * 10 * r(), R = 30 + r() * 90;
    s += circle(x, ((y % (H + 200)) + H + 200) % (H + 200) - 100, R, cols[i % cols.length], `opacity="${f2(.12 + r() * .2)}"`);
  }
  return g(s, '', 'filter="url(#blur8)"');
};
const mangaBg = (t, c1, c2) => {
  let s = rect(-100, -100, W + 200, H + 200, c1);
  let d = '';
  for (let i = -30; i < 60; i++) d += `M${i * 60 - (t * 80) % 60} -100l-600 1300h18l600 -1300z`;
  s += path(d, c2, 'opacity=".35"');
  return s;
};
const moon = (x, y, R, col, glow) => g(circle(x, y, R * 1.6, col, 'opacity=".25"'), '', 'filter="url(#blur30)"') +
  circle(x, y, R, col) + circle(x - R * .3, y - R * .2, R * .18, 'rgba(0,0,0,.08)') + circle(x + R * .25, y + R * .3, R * .12, 'rgba(0,0,0,.08)');
function pigeons(t, seed, n = 8) {
  const r = rng(seed); let s = '';
  for (let i = 0; i < n; i++) {
    const x = (r() * 2400 + t * (120 + r() * 80)) % 2400 - 240, y = 120 + r() * 300 - t * 10, fl = Math.sin(t * 14 + i * 2) * 10;
    s += strokeP(`M${f2(x - 16)} ${f2(y + fl)}Q${f2(x - 8)} ${f2(y - 4)} ${f2(x)} ${f2(y)}Q${f2(x + 8)} ${f2(y - 4)} ${f2(x + 16)} ${f2(y + fl)}`, '#3A3A48', 3);
  }
  return s;
}
function meteors(t, n, seed) {
  const r = rng(seed); let s = '';
  for (let i = 0; i < n; i++) {
    const per = 1.2 + r() * 1.6, ph = r() * per, k = ((t + ph) % per) / per;
    const x0 = r() * 2600 - 200, y0 = -100 + r() * 300, L = 300 + r() * 400;
    const x = x0 - k * 900, y = y0 + k * 600;
    const id = uid('mt');
    s += lg(id, [[0, '#FFFFFF', 0], [1, '#FFF6D0', 1]], 1, 0, 0, 0);
    s += path(`M${f2(x)} ${f2(y)}L${f2(x + L * .83)} ${f2(y - L * .55)}L${f2(x + L * .83)} ${f2(y - L * .55 + 3)}Z`, `url(#${id})`, `stroke="url(#${id})" stroke-width="3" opacity="${f2(Math.sin(k * Math.PI))}"`);
    s += circle(x, y, 4, '#FFFFFF', `opacity="${f2(Math.sin(k * Math.PI))}" filter="url(#glow)"`);
  }
  return s;
}
function leafField(t, seed, n = 26, o = {}) { return particles(t, Object.assign({ kind: 'leaf', n, seed, vy: 80, vx: -40, sway: 50 }, o)); }
/* «глаза в тени» — тёмная полоса поперёк лица (аниме-приём) */
const eyeShadow = (x, y, s, op) => g(rect(-140, -40, 280, 110, '#0A0418', `opacity="${f2(op)}"`), tr(x, y, s));

/* ---------- титр ---------- */
function titleCard(t, o = {}) {
  let s = '';
  const k = E.outX(P(t, 0, .6));
  s += g(girihCircle(t, 420 * (0.6 + .4 * k), { op: k * .9, spin: 14 }), tr(960, 470));
  s += g(starfield(8, 160, { t }), '', `opacity="${f2(k)}"`);
  const sc = lerp(1.5, 1, E.outB(P(t, .05, .5)));
  const id = uid('tg');
  s += lg(id, [[0, '#FFF3C4'], [.5, '#FFC93C'], [1, '#C77A10']]);
  // мазок кисти за титром
  s += g(path('M-560 40C-400 -60 -100 -90 200 -70C400 -60 520 -20 600 30C400 10 200 30 -20 50C-240 70 -420 90 -560 40Z', '#B0102A', `opacity="${f2(k * .9)}"`), tr(960, 470, 1 + .05 * t));
  s += g(`<text x="0" y="0" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="230" letter-spacing="10" fill="url(#${id})" stroke="#2A0A10" stroke-width="10" paint-order="stroke">ЮЛДУЗ</text>`, `translate(960 560) scale(${f2(sc)})`, `opacity="${f2(P(t, .05, .2))}" filter="url(#glow)"`);
  s += `<text x="960" y="660" text-anchor="middle" font-family="Unbounded" font-weight="600" font-size="44" letter-spacing="18" fill="#7FF3E8" opacity="${f2(P(t, .5, .5))}">СВЕТ САМАРКАНДА</text>`;
  s += `<text x="960" y="720" text-anchor="middle" font-family="Rubik" font-weight="700" font-size="26" letter-spacing="12" fill="#F4EBD6" opacity="${f2(P(t, .8, .5) * .8)}">${o.sub || 'YULDUZ · SAMARQAND NURI'}</text>`;
  return s;
}

/* =================== ПЛАНЫ =================== */
const SHOTS = [];
const shot = (a, b, f, name) => SHOTS.push({ a, b, f, name });

/* ---- ПРОЛОГ ---- */
shot(0, 5, (t, T) => {
  const pan = samarkandPanorama(T, { mood: 'red' });
  let s = sky('red', T) + moon(1380, 300, 120, '#FFB59A') ;
  s += g(starfield(31, 60, { t: T }), '', 'opacity=".4"');
  s += cam(g(pan.far, '', 'filter="url(#gradeRedDark)"'), 1 + t * .01);
  s += cam(g(pan.mid + pan.near, '', 'filter="url(#gradeRedDark)"'), 1 + t * .02, 960, 700);
  s += particles(T, { kind: 'ember', n: 50, seed: 3, vy: -60, vx: 20, color: '#FF7A3A' });
  s += g(rect(-200, 600, W + 400, 500, '#2A0408', 'opacity=".5"'), '', 'filter="url(#blur60)"');
  s += fadeBlack(1 - P(t, 0, 1.6));
  return s;
}, 'Красное небо над Самаркандом');

shot(5, 9, (t, T) => {
  let s = sky('red', T);
  s += moon(985, 330, 250, '#FFC4A8');
  // тучи
  for (let i = 0; i < 5; i++) s += g(ell(((i * 520 - T * 120) % 2600 + 2600) % 2600 - 300, 200 + i * 70, 420, 40, '#2A0408', 'opacity=".7"'), '', 'filter="url(#blur16)"');
  const tilt = kf(t, [[0, 160], [4, -20, E.ioS]]);
  const m = minaret(960, 1500, 180, 700, { cap: false });
  s += cam(g(m, '', 'filter="url(#gradeRedDark)"') + g(heroFigure({ t: T, pose: 'stand', rimCol: '#FF7A4A', wind: 1.3 }), tr(960, 657, .95)), 1.05, 960, 540, 0, tilt);
  s += particles(T, { kind: 'ember', n: 40, seed: 9, vy: -80, vx: 30 });
  return s;
}, 'Силуэт героя на минарете');

shot(9, 13, (t, T) => {
  let s = rect(-50, -50, W + 100, H + 100, '#06020C');
  s += titleCard(t);
  s += particles(T, { kind: 'star', n: 30, seed: 4, vy: -30, op: .8 });
  s += fadeWhite(1 - P(t, 0, .25)) + fadeWhite(P(t, 3.6, .4));
  return s;
}, 'Титр');

/* ---- АКТ I ---- */
shot(13, 21.5, (t, T) => {
  const pan = samarkandPanorama(T, {});
  const px = -t * 14;
  let s = sky('day', T);
  s += g(circle(260, 120, 90, '#FFF6D0') + circle(260, 120, 200, '#FFF6D0', 'opacity=".25"'), '', 'filter="url(#blur16)"');
  s += g(pan.far, `translate(${f2(px * .3)} 0)`) + g(pan.mid, `translate(${f2(px * .6)} 0)`) + g(pan.near, `translate(${f2(px)} 0)`);
  s += pigeons(T, 5, 9);
  s += leafField(T, 7, 22);
  s += godRays(260, 120, T, { n: 10, spread: 1.2, a0: .1, op: .18 });
  s += `<text x="80" y="110" font-family="Unbounded" font-weight="700" font-size="34" fill="#FFFFFF" letter-spacing="6" opacity="${f2(P(t, .6, .6) * (1 - P(t, 6, 1)))}" stroke="#1E4FA3" stroke-width="2" paint-order="stroke">САМАРКАНД</text>`;
  s += fadeWhite(1 - P(t, 0, .5));
  return s;
}, 'Утро в Самарканде');

shot(21.5, 25.2, (t, T) => {
  const sc = T * 260;
  let bg = sky('morning', T);
  let far = '', near = '';
  for (let k = -1; k < 4; k++) far += g(dome(400, 760, 300, 240, {}) + minaret(800, 900, 60, 560) + house(1000, 900, 400, 200), `translate(${f2(k * 1400 - (sc * .3) % 1400)} 0)`);
  for (let k = -1; k < 4; k++) near += g(chinar(200, 1100, 160, T, { autumn: true }) + house(500, 1080, 600, 340, {}) + chinar(1200, 1100, 180, T, { autumn: true }), `translate(${f2(k * 1500 - sc % 1500)} 0)`);
  bg += far + blurG(near, 'blur2') + rect(-200, 1000, W + 400, 200, '#C9A97E');
  const bob = Math.abs(Math.sin(T * Math.PI * 2)) * -10;
  let s = bg;
  s += C('jasur', 900, 470 + bob, 1.45, { t: T, look: [.5, -.3], blink: blinkAt(T, 1), mouthShape: 'neutral', wind: .3 });
  // ремень сумки
  s += strokeP(`M${900 - 230} ${740 + bob}L${900 + 250} ${1100 + bob}`, '#5A3A20', 26) + strokeP(`M${900 - 230} ${740 + bob}L${900 + 250} ${1100 + bob}`, '#8A5A30', 8);
  s += leafField(T, 8, 14, { size: 1.8 });
  return s;
}, 'Жасур идёт в школу');

shot(25.2, 28.5, (t, T) => {
  let s = rect(-100, -100, W + 200, H + 200, '#E9DCC4');
  // тетрадь: страница в клетку со звёздной картой
  const pg = `<g transform="translate(960 560) rotate(-4)">` + rect(-700, -420, 1400, 840, '#FBF8EE', 'stroke="#C9B48A" stroke-width="4"') +
    path(Array.from({ length: 44 }, (_, i) => `M${-700 + i * 32} -420V420`).join('') + Array.from({ length: 27 }, (_, i) => `M-700 ${-420 + i * 32}H700`).join(''), 'none', 'stroke="#BFD4EA" stroke-width="1.5"') +
    strokeP('M0 -420V420', '#E8A0A0', 3) + '</g>';
  s += pg;
  // созвездия
  const pts = [[-500, -200], [-420, -120], [-330, -170], [-260, -60], [-380, 20], [-520, -40]];
  let d = '', dots = '';
  pts.forEach((p, i) => { d += (i ? 'L' : 'M') + (p[0] + 960) + ' ' + (p[1] + 560); dots += g(path(starPath(14, 5, 4), '#1E3A8A'), tr(p[0] + 960, p[1] + 560)); });
  s += strokeP(d, '#1E3A8A', 2.4, 'stroke-dasharray="8 8"') + dots;
  // секстант и подпись
  s += strokeP('M1150 820A260 260 0 0 1 1450 440', '#1E3A8A', 4) + strokeP('M1150 820L1450 820M1150 820L1450 440', '#1E3A8A', 2);
  s += `<text x="1080" y="300" font-family="Rubik" font-weight="500" font-size="40" fill="#1E3A8A" transform="rotate(-4 1080 300)">Zij-i Ko'ragoniy — 1018 yulduz</text>`;
  // рисуемая звезда
  const k = E.io(P(t, .2, 2.4));
  const sp = star8(150, 62).map(p => [p[0] + 760, p[1] + 760]);
  const per = sp.length;
  const n = Math.max(1, Math.floor(k * per));
  let sd = `M${sp[0][0]} ${sp[0][1]}`;
  for (let i = 1; i <= n; i++) sd += `L${sp[i % per][0]} ${sp[i % per][1]}`;
  s += strokeP(sd, '#16224A', 5);
  const tip = sp[n % per];
  s += g(hand('hold') + g(pencil(300), 'rotate(-140) translate(-20 0)'), `translate(${f2(tip[0] + 150)} ${f2(tip[1] + 110)}) scale(1.4)`);
  s = cam(s, 1 + t * .02);
  s += g(rect(-100, -100, W + 200, H + 200, '#FFE6B0', 'opacity=".12"'), '');
  return s;
}, 'Тетрадь со звёздами');

shot(28.5, 31, (t, T) => cam(schoolExterior(T), 1 + t * .02, 960, 500), 'Школа №17');

shot(31, 35.6, (t, T) => {
  let s = classroom(T);
  s = blurG(s, 'blur2');
  s += C('nilufar', 1180, 460, 1.55, { t: T, turn: -.45, look: [-.6, -.05], blink: blinkAt(T, 2), wind: .25, mouthShape: 'neutral' });
  s += godRays(400, -100, T, { n: 8, spread: .6, a0: .9, op: .22 });
  s += particles(T, { kind: 'dust', n: 50, seed: 2, vy: -8, vx: 6, color: '#FFF6D0', op: 1.5 });
  return cam(s, 1 + t * .015, 1180, 460);
}, 'Нилуфар у окна');

shot(35.6, 39.6, (t, T) => {
  let s = blurG(classroom(T), 'blur8');
  s += C('jasur', 760, 470, 1.6, { t: T, turn: .3, look: [.7, -.1], blink: blinkAt(T, 3), blush: .7, mouthShape: 'neutral' });
  // затылок Нилуфар на переднем плане
  s += blurG(g(path('M-300 -300C-100 -420 200 -400 320 -200C400 0 420 400 380 800L-300 800Z', '#2B1B22'), tr(1700, 500, 1.2)), 'blur8');
  s += bokeh(T, 4, ['#FFE6B0', '#FFC8D8'], 10);
  return cam(s, 1.02 + t * .01);
}, 'Жасур смотрит на неё');

shot(39.6, 42, (t, T) => {
  let s = blurG(classroom(T), 'blur8');
  const turn = kf(t, [[0, -.7], [.4, 0, E.outC]]);
  s += C('nilufar', 960, 470 + kf(t, [[0, 10], [.4, 0]]), 2.0, { t: T, turn, look: [0, 0], blink: blinkAt(T + 1, 2), mouth: lip('a4', T), mouthShape: 'neutral', wind: kf(t, [[0, 1.2], [.8, .2]]) });
  s += particles(T, { kind: 'star', n: 12, seed: 8, vy: -10, color: '#FFF2C8', op: .7, size: .7 });
  return s;
}, 'Нилуфар оборачивается');

shot(42, 44.4, (t, T) => {
  let s = mangaBg(T, '#FFD6E0', '#FF9AB8');
  const sh = lineOn('a5', T) && t < .9 ? shakeAt(T, 6) : [0, 0];
  s += C('jasur', 960 + sh[0], 480 + sh[1], 2.0, { t: T, eyes: 'wide', brows: 'surprised', blush: 1, sweat: 1, mouth: lip('a5', T), look: [0, .1] });
  return s;
}, 'Жасур смущён');

shot(44.4, 47.6, (t, T) => {
  let s = rect(-100, -100, W + 200, H + 200, '#FFF0E6');
  s += bokeh(T, 9, ['#FFC8D8', '#FFE6A0', '#C8F0FF', '#FFFFFF'], 26);
  s += particles(T, { kind: 'star', n: 26, seed: 11, vy: -20, color: '#FFD978', size: 1.2 });
  // цветы хлопка (пахта) — символ Узбекистана
  const r = rng(12);
  for (let i = 0; i < 9; i++) {
    const x = r() * W, y = (r() * H + T * 30) % (H + 200) - 100;
    s += g(circle(-14, 0, 18, '#FFFFFF') + circle(14, 0, 18, '#FFFFFF') + circle(0, -14, 18, '#FFFFFF') + circle(0, 12, 16, '#F4F4F4') + path('M-24 16L0 34L24 16L0 24Z', '#7A5A30'), tr(x, y, .8 + r() * .6, T * 20 + i * 40), 'opacity=".75"');
  }
  const smile = lineOn('a6', T) || t > 1.2;
  s += C('nilufar', 960, 470, 2.0, { t: T, eyes: smile ? 'smile' : undefined, mouthShape: 'smile', mouth: lip('a6', T) * .8, blush: .6, wind: .4 });
  return cam(s, 1 + t * .02);
}, '«Спасибо!»');

shot(47.6, 51.4, (t, T) => {
  let s = cam(courtyard(T), 1.15, 960, 540, 0, 80, -4);
  s = g(s, '', 'filter="url(#gradeDusk)"');
  s += C('sardor', 420, 520, 1.15, { t: T, mouthShape: 'smirk', blink: blinkAt(T, 4) });
  s += C('rustam', 1500, 540, 1.2, { t: T, mouthShape: 'smirk', mean: true, blink: blinkAt(T, 5) });
  // тетрадь в руке Баходира
  s += g(rect(-120, -160, 240, 320, '#2A4A8A', 'stroke="#111" stroke-width="4" rx="6"') + g(path(starPath(40, 16, 8), '#E9B44C'), tr(0, -20)), tr(1270, 760, 1, 12));
  s += C('bahodir', 960, 470, 1.75, { t: T, mouthShape: 'smirk', mouth: lip('b1', T), brows: 'angry', blink: blinkAt(T, 6) });
  s += g(rect(-100, -100, W + 200, 300, '#000', 'opacity=".35"'), '', 'filter="url(#blur30)"');
  return cam(s, 1 + t * .015, 960, 300);
}, 'Баходир с подпевалами');

shot(51.4, 53, (t, T) => {
  let s = mangaBg(T, '#F6E3A6', '#E8B84A');
  const hop = Math.abs(Math.sin(T * 10)) * -10;
  s += C('rustam', 1350, 520 + hop, 1.3, { t: T, eyes: 'smile', mouthShape: 'laugh', mouth: lip('b2', T) * .9 + .2 });
  s += C('sardor', 760, 470 - hop, 1.7, { t: T, eyes: 'smile', mouthShape: 'laugh', mouth: lip('b2', T) });
  return s;
}, 'Ха-ха!');

shot(53, 55.6, (t, T) => {
  let s = blurG(courtyard(T), 'blur4');
  s += C('jasur', 960, 470, 1.8, { t: T, brows: 'determined', mouth: lip('b3', T), look: [0, -.2], blink: blinkAt(T, 7) });
  return cam(s, 1.02 + t * .02, 960, 400);
}, '«Отдай тетрадь»');

shot(55.6, 59, (t, T) => {
  let s = blurG(courtyard(T), 'blur16');
  s = g(s, '', 'filter="url(#gradeDusk)"');
  const tear = P(t, 2.0, .3), fly = Math.max(0, t - 2.2);
  const page = (side) => {
    const dx = side * (tear * 30 + fly * 260), dy = fly * fly * 60, rot = side * (tear * 6 + fly * 30);
    let pg = rect(side < 0 ? -380 : 0, -270, 380, 540, '#FBF8EE', 'stroke="#C9B48A" stroke-width="3"');
    pg += g(path(starPath(90, 36, 8), 'none', 'stroke="#1E3A8A" stroke-width="4"'), tr(side * 150, 0));
    pg += strokeP(side < 0 ? 'M-300 -150L-200 -60L-260 60' : 'M80 -180L200 -100L260 40', '#1E3A8A', 2.4, 'stroke-dasharray="8 6"');
    return g(pg, `translate(${f2(960 + dx)} ${f2(540 + dy)}) rotate(${f2(rot)})`);
  };
  s += page(-1) + page(1);
  // руки
  const pull = tear * 40 + fly * 260;
  s += g(hand('fist', { skin: SKIN_TAN, sleeve: '#1C1A1E' }), `translate(${f2(560 - pull)} ${f2(320 + fly * fly * 60)}) rotate(-70) scale(1.4)`);
  s += g(hand('fist', { skin: SKIN_TAN, sleeve: '#1C1A1E' }), `translate(${f2(1360 + pull)} ${f2(320 + fly * fly * 60)}) rotate(70) scale(-1.4 1.4)`);
  if (fly > 0) s += particles(fly, { kind: 'dust', n: 30, seed: 6, vy: 120, color: '#FBF8EE', size: 3, op: 2 });
  s += strokeP(`M960 270L940 330L975 390L945 450L970 520L950 600L960 810`, '#C9B48A', tear > 0 ? 3 : 0);
  return cam(s, 1 + t * .03);
}, 'Рвёт страницу');

shot(59, 60.6, (t, T) => {
  let s = blurG(courtyard(T), 'blur8');
  const k = E.outC(P(t, 0, .5));
  s += g(bust('jasur', { t: T, eyes: 'wide', brows: 'sad', mouth: .5, look: [0, -.5] }), `translate(${f2(960 - k * 120)} ${f2(480 + k * 160)}) rotate(${f2(-k * 14)}) scale(1.7)`);
  s += dashLines(T, { n: 50, ang: -30, op: .5 * (1 - P(t, .4, .6)), speed: 5000 });
  s += particles(T, { kind: 'dust', n: 20, seed: 13, vy: -40, color: '#D6C09A', size: 3, op: P(t, .3, .2) });
  return s;
}, 'Толчок');

shot(60.6, 63, (t, T) => {
  let s = blurG(cam(courtyard(T), 1.3, 1400, 600), 'blur4');
  s += C('nilufar', 960, 470, 1.8, { t: T, brows: 'angry', mouth: lip('b5', T), mouthShape: 'neutral', wind: .4, look: [-.4, 0] });
  s += speedLines(960, 470, T, { n: 70, r0: 520, color: '#FFFFFF', op: .35 });
  return s;
}, '«Оставь его!»');

shot(63, 67, (t, T) => {
  let s = blurG(courtyard(T), 'blur4');
  const turn = kf(t, [[0, 0], [2.6, .55]]), walk = P(t, 2.9, 1.2);
  s += C('bahodir', 960 + walk * 700, 470, 1.75, { t: T, turn, mouthShape: 'smirk', mouth: lip('b6', T), brows: 'angry', blink: blinkAt(T, 6) });
  // тетрадь падает
  const f = P(t, 2.4, 1.0);
  if (f > 0) s += g(rect(-120, -160, 240, 320, '#2A4A8A', 'stroke="#111" stroke-width="4" rx="6"'), `translate(${f2(1250 - f * 100)} ${f2(760 + E.inQ(f) * 500)}) rotate(${f2(12 + f * 80)})`);
  return s;
}, 'Баходир уходит');

shot(67, 71.5, (t, T) => {
  let s = g(courtyard(T), '', 'filter="url(#gradeGray)"');
  s = blurG(s, 'blur4');
  s += g(C('jasur', 960, 520, 1.9, { t: T, look: [0, .6], mouthShape: 'grit', brows: 'sad', tear: P(t, 1.5, 1), eyeShade: .75 }), '', 'filter="url(#gradeGray)"');
  // обрывки карты на земле
  const r = rng(31);
  for (let i = 0; i < 8; i++) s += g(rect(-60, -40, 120, 80, '#FBF8EE', 'stroke="#C9B48A" stroke-width="2"') + strokeP('M-40 0L40 -10', '#1E3A8A', 2), tr(200 + r() * 1500, 980 + r() * 60, 1, r() * 60 - 30));
  s += leafField(T, 14, 12, { size: 1.6 });
  return cam(s, 1.04 - t * .01, 960, 520);
}, '«Если бы я был сильнее...»');

/* ---- АКТ II ---- */
shot(71.5, 78, (t, T) => {
  const k = P(t, 0, 6);
  let s = observatory(T, { dusk: true });
  s += g(observatory(T, {}), '', `opacity="${f2(k)}"`);
  // Жасур сидит на краю секстанта
  s += g(heroFigure({ t: T, pose: 'stand', col: '#0A0A18', rimCol: '#7FA0FF', wind: .2, scarf: false, robe: false, eyes: false }), tr(1120, 935, .62));
  return cam(s, 1.32 + t * .015, 1050, 880);
}, 'Обсерватория Улугбека');

shot(78, 82, (t, T) => {
  let s = sky('night', T) + g(path('M-200 700C300 400 900 200 2200 -100L2200 100C1000 360 400 560 -200 900Z', '#9AA8FF', 'opacity=".16"'), '', 'filter="url(#blur30)"');
  s += meteors(T, 14, 21);
  const gl = P(t, 2.4, 1.5);
  s += g(circle(960, 1200, 500 + gl * 300, '#7FF3E8', `opacity="${f2(.2 + gl * .4)}"`), '', 'filter="url(#blur60)"');
  s += g(C('jasur', 960, 560, 1.7, { t: T, look: [0, -1], eyes: 'wide', brows: 'surprised', mouth: .25, wind: .2, blink: 0 }), '', 'filter="url(#gradeNightChar)"');
  s += g(rect(-100, 700, W + 200, 500, '#7FF3E8', `opacity="${f2(gl * .25)}"`), '', 'style="mix-blend-mode:screen" filter="url(#blur30)"');
  return cam(s, 1 + t * .02, 960, 500);
}, 'Звездопад');

shot(82, 90, (t, T) => {
  let s = observatory(T, { glow: 1 });
  const k = E.outB(P(t, .3, 1.2)), pulse = lip('c2', T) + lip('c4', T);
  s += g(rect(900, -100, 120, 1100, '#BFFFF6', `opacity="${f2(.5 * (1 - P(t, 1.5, 1)))}"`), '', 'filter="url(#blur30)"');
  s += g(circle(0, 0, 340, '#FFE7A0', `opacity="${f2(.18 + pulse * .15)}"`), tr(960, 480), 'filter="url(#blur60)"');
  s += g(humo(T, { open: k, flap: .8 }), tr(960, 470 - Math.sin(T * 1.5) * 14, .55 + k * .55));
  s += particles(T, { kind: 'star', n: 40, seed: 17, vy: -40, color: '#FFE7A0' });
  s += fadeWhite(1 - P(t, 0, .5));
  return cam(s, 1.02 + t * .01, 960, 520);
}, 'Птица Хумо');

shot(90, 93.2, (t, T) => {
  let s = blurG(observatory(T, { glow: 1 }), 'blur8');
  s += g(circle(1500, 200, 400, '#FFE7A0', 'opacity=".35"'), '', 'filter="url(#blur60)"');
  s += g(C('jasur', 960, 480, 1.9, { t: T, eyes: 'wide', brows: 'surprised', mouth: lip('c3', T), look: [.6, -.6], wind: .3 }), '', 'filter="url(#gradeNightChar)"');
  s += g(rect(1000, -100, 1100, 1300, '#FFD978', 'opacity=".25"'), '', 'style="mix-blend-mode:screen" filter="url(#blur60)"');
  return s;
}, '«Птица Хумо?..»');

shot(93.2, 100.4, (t, T) => {
  let s = observatory(T, { glow: 1 });
  s = g(s, '', 'opacity=".75"');
  const k = E.outC(P(t, .5, 2.5));
  s += g(g(girihCircle(T, 520, { op: k, spin: 25 }), 'scale(1 .32)'), tr(960, 930));
  s += g(rect(-60, -1100, 120, 1100, '#BFFFF6', `opacity="${f2(k * .35)}"`), tr(960, 930), 'filter="url(#blur16)"');
  s += g(C('jasur', 960, 560, 1.3, { t: T, look: [0, -.8], eyes: 'wide', brows: 'surprised', wind: .5 + k, hairLift: k * .3 }), '', 'filter="url(#gradeNightChar)"');
  s += g(humo(T, { flap: 1 }), tr(1460, 300 + Math.sin(T * 1.5) * 10, .4 + lip('c4', T) * .03), `opacity=".95"`);
  s += particles(T, { kind: 'star', n: 30, seed: 19, vy: -90, color: '#7FF3E8', op: k });
  return cam(s, 1 + t * .01, 960, 600);
}, 'Магический круг-гирих');

shot(100.4, 106, (t, T) => {
  const flash = t > 2.2;
  let s = rect(-100, -100, W + 200, H + 200, '#061226');
  s += g(girihCircle(T, 560, { spin: 60, op: .9 }), tr(960, 470));
  s += godRays(960, 470, T, { n: 24, color: '#BFFFF6', op: .35 });
  s += particles(T, { kind: 'star', n: 60, seed: 23, vy: -260, color: '#FFE7A0' });
  const lift = E.outC(P(t, .3, 1.8));
  if (!flash) {
    s += C('jasur', 960, 480, 1.9, { t: T, hairLift: lift, wind: 1.5, eyes: t > 1.2 ? 'glow' : 'wide', brows: 'determined', mouth: 0, look: [0, 0] });
  } else {
    s += C('hero', 960, 480, 1.9, { t: T, mask: false, hairLift: 1, wind: 1.6, eyes: 'glow', brows: 'determined', mouth: lip('c5', T), glowCol: '#FFC93C' });
    // ладонь со звездой
    const hk = E.outB(P(t, 3, .5));
    if (hk > 0) s += g(hand('open') + g(path(starPath(40, 16, 8), '#FFF6C8'), 'translate(10 30)', 'filter="url(#glowL)"'), `translate(${f2(1480)} ${f2(1160 - hk * 420)}) scale(1.6)`);
  }
  s += speedLines(960, 470, T, { n: 80, r0: 560, color: '#BFFFF6', op: .45 });
  const imp = (t > 2.2 && t < 2.32) || (t > 2.42 && t < 2.5);
  return { svg: s, filter: imp ? 'invert(1) grayscale(1) contrast(2.5)' : '', shake: shakeAt(T, 8 * (1 - P(t, 2.2, 1.5))) };
}, 'Превращение');

shot(106, 110, (t, T) => {
  const rk = P(t, .5, 2.5);
  let s = sky('night', T) + g(sky('red', T), '', `opacity="${f2(rk)}"`);
  s += g(registanClose(T, { night: true }), '', `filter="url(#${rk > .5 ? 'gradeRedDark' : 'gradeNightDark'})"`);
  s += cracks(41, 960, 960, 900, E.outC(P(t, .8, 2)), '#FF6A2A');
  // рога Дева показываются за медресе
  const hy = kf(t, [[2.4, 900], [4, 560]]);
  s += g(path('M-180 -200C-260 -300 -300 -420 -250 -520C-240 -430 -200 -330 -120 -250Z', '#1A0A0A', 'stroke="#FF5A2A" stroke-width="5"') + path('M180 -200C260 -300 300 -420 250 -520C240 -430 200 -330 120 -250Z', '#1A0A0A', 'stroke="#FF5A2A" stroke-width="5"'), tr(960, hy + 400, 1));
  s = g(s, '');
  s += particles(T, { kind: 'dust', n: 40, seed: 29, vy: 200, color: '#8A6A5A', size: 2 });
  return { svg: s, shake: shakeAt(T, 4 + 10 * P(t, .5, 3)) };
}, 'Землетрясение');

shot(110, 118.5, (t, T) => {
  let s = sky('red', T);
  const rise = E.outC(P(t, 0, 3));
  const roar = lip('c6', T);
  s += g(devHead(T, { roar }), tr(960, lerp(1100, 420, rise), 1.25));
  s += g(registanClose(T, { night: true }), 'translate(0 120)', 'filter="url(#gradeRedDark)"');
  s += particles(T, { kind: 'ember', n: 70, seed: 37, vy: -120, vx: 40, size: 1.5 });
  s += g(rect(-200, 800, W + 400, 400, '#FF3A1A', 'opacity=".25"'), '', 'filter="url(#blur60)"');
  return { svg: cam(s, 1 + t * .01, 960, 300), shake: shakeAt(T, 3 + roar * 10) };
}, 'Дев');

/* ---- АКТ III ---- */
shot(118.5, 122, (t, T) => {
  let s = sky('red', T) + g(samarkandPanorama(T, {}).mid, 'translate(0 260)', 'filter="url(#gradeRedDark)"');
  s = blurG(s, 'blur4');
  const md = kf(t, [[2.3, 150], [2.8, 0, E.outB]]);
  s += g(C('hero', 960, 480, 1.9, { t: T, mask: t > 2.3, maskDrop: md, eyes: t > 2.8 ? 'glow' : undefined, brows: 'determined', mouth: lip('d1', T), wind: .8, hairLift: .15 }), '', 'filter="url(#gradeRedChar)"');
  if (t > 2.8) s += g(circle(870, 504, 30, '#FFE07A', `opacity="${f2(1 - P(t, 2.8, .5))}"`) + circle(1050, 504, 30, '#FFE07A', `opacity="${f2(1 - P(t, 2.8, .5))}"`), '', 'filter="url(#glowL)"');
  s += particles(T, { kind: 'ember', n: 30, seed: 43, vy: -60 });
  return s;
}, 'Маска');

shot(122, 124.5, (t, T) => {
  let s = sky('red', T) + moon(1500, 260, 110, '#FFC4A8');
  s += g(rooftops(T, t * 1800), '', 'filter="url(#gradeRedDark)"');
  s += dashLines(T, { n: 40, ang: 0, op: .35, speed: 6000, color: '#FFB08A' });
  const y = 520 - Math.sin(P(t, 0, 2.5) * Math.PI) * 180;
  s += g(heroFigure({ t: T, pose: t < .5 ? 'run' : 'leap', rimCol: '#FFB08A', wind: 1.5 }), tr(860, y + 300, 1.1));
  return { svg: s, shake: shakeAt(T, 3) };
}, 'Прыжок по крышам');

shot(124.5, 128, (t, T) => {
  let s = g(bazaar(T), '', 'filter="url(#gradeRedChar)"');
  // падающая балка
  const f = E.inQ(P(t, 1.0, 2.6));
  s += g(rect(-700, -40, 1400, 80, '#5A3A20', 'stroke="#1A0A04" stroke-width="5"') + rect(-700, -40, 1400, 14, PAL.tq), `translate(960 ${f2(lerp(120, 420, f))}) rotate(${f2(lerp(-8, -16, f))})`);
  s += particles(T, { kind: 'dust', n: 40, seed: 47, vy: 260, color: '#9A7A5A', size: 2.5 });
  s += C('rustam', 1380, 760, 1.05, { t: T, eyes: 'wide', brows: 'surprised', sweat: 1, mouth: .6, mean: false }, 'filter="url(#gradeRedChar)"');
  s += C('sardor', 560, 760, 1.05, { t: T, eyes: 'wide', brows: 'surprised', sweat: 1, mouth: .5 }, 'filter="url(#gradeRedChar)"');
  s += C('bahodir', 960, 700, 1.3, { t: T, eyes: 'wide', brows: 'surprised', mean: false, sweat: 1, mouth: lip('d3', T) || .2 }, 'filter="url(#gradeRedChar)"');
  return { svg: s, shake: shakeAt(T, 6) };
}, 'Базар рушится');

shot(128, 130, (t, T) => {
  let s = rect(-100, -100, W + 200, H + 200, '#1A0408');
  s += speedLines(960, 600, T, { n: 100, r0: 300, color: '#FFB08A', op: .55 });
  s += g(rect(-900, -50, 1800, 100, '#5A3A20', 'stroke="#1A0A04" stroke-width="6"') + rect(-900, -50, 1800, 16, PAL.tq), tr(960, 470, 1, -4));
  s += g(heroFigure({ t: T, pose: 'brace', rimCol: '#7FF3E8' }), tr(960, 1000, 1.45));
  s += shockRing(960, 520, P(t, 0, .7), 900, '#FFE7A0');
  s += particles(T, { kind: 'dust', n: 50, seed: 53, vy: -100, color: '#9A7A5A', size: 3 });
  const imp = t < .08 || (t > .16 && t < .22);
  return { svg: s, filter: imp ? 'invert(1) grayscale(1) contrast(3)' : '', shake: shakeAt(T, 14 * (1 - P(t, 0, 1))) };
}, 'Ловит балку');

shot(130, 132.2, (t, T) => {
  let s = blurG(g(bazaar(T), '', 'filter="url(#gradeRedChar)"'), 'blur8');
  s += C('bahodir', 960, 480, 1.85, { t: T, eyes: 'wide', brows: 'surprised', mean: false, sweat: 1, mouth: lip('d4', T), look: [0, -.6] }, 'filter="url(#gradeRedChar)"');
  s += particles(T, { kind: 'dust', n: 30, seed: 57, vy: 40, color: '#C9A98A', size: 2 });
  return s;
}, '«Кто ты такой?»');

shot(132.2, 135, (t, T) => {
  let s = blurG(g(bazaar(T), '', 'filter="url(#gradeRedChar)"'), 'blur8');
  const go = E.inC(P(t, 2.2, .5));
  const env = lip('d5', T);
  s += g(C('hero', 960 + go * 1400, 480 - env * 3, 1.85, { t: T, turn: -.25, look: [-.6, 0], brows: 'determined', wind: .6 }), '', 'filter="url(#gradeRedChar)"');
  if (go > 0) s += dashLines(T, { n: 40, op: .6 * go, speed: 8000, color: '#7FF3E8' });
  return s;
}, '«Просто звезда»');

shot(135, 137.6, (t, T) => {
  let s = sky('red', T) + g(registanClose(T, { night: true }), 'translate(0 260) scale(1)', 'filter="url(#gradeRedDark)"');
  s += g(devHead(T, { roar: .2 }), tr(1500, 300, .7), 'opacity=".9"');
  s = blurG(s, 'blur4');
  const fall = E.inQ(P(t, 1.6, 1.0));
  const ey = 480 + fall * 900;
  s += C('nilufar', 900, ey, 1.75, { t: T, mouth: lip('d6', T), eyes: t > 1.4 ? 'wide' : undefined, brows: t > 1.4 ? 'surprised' : 'determined', look: [.5, -.2], wind: .6 + fall }, 'filter="url(#gradeRedChar)"');
  s += g(hand('hold') + g(phone(true), 'translate(10 -110)'), tr(1260, ey + 240 - fall * 200, 1.2, -10), 'filter="url(#gradeRedChar)"');
  s += cracks(61, 900, 1000, 500, P(t, 1.2, .5), '#FF8A3A');
  return { svg: s, shake: shakeAt(T, 6 * P(t, 1.2, .3)) };
}, 'Нилуфар снимает');

shot(137.6, 141.5, (t, T) => {
  let s = sky('red', T);
  s += moon(960, 500, 380, '#FFE2C4');
  s += g(registanClose(T, { night: true }), 'translate(0 330)', 'filter="url(#gradeRedDark)"');
  const y = lerp(380, 560, E.outC(P(t, 0, 3.6)));
  s += g(heroFigure({ t: T * .5, pose: 'carry', rimCol: '#FFE2C4', wind: .8 }), tr(960, y + 330, 1.3));
  s += particles(T * .5, { kind: 'star', n: 40, seed: 67, vy: -30, color: '#FFE7A0' });
  s += leafField(T * .4, 69, 16, { size: 1.4 });
  return cam(s, 1.08 - t * .015, 960, 500);
}, 'На руках у героя');

shot(141.5, 145, (t, T) => {
  let s = rect(-100, -100, W + 200, H + 200, '#2A0A18');
  s += bokeh(T, 71, ['#FF8A5A', '#FFD978', '#FF5A7A'], 22);
  s += C('nilufar', 960, 480, 2.0, { t: T, eyes: 'wide', blush: .9, mouth: lip('d7', T), look: [0, -.7], wind: .8, blink: t > 2.6 ? blinkAt(T, 1) : 0 }, 'filter="url(#gradeDawnChar)"');
  const fk = P(t, 2.1, 1.4);
  if (fk > 0) s += g(feather(T), tr(1300 - fk * 200, lerp(-100, 640, E.outC(fk)), .8, 30 + Math.sin(T * 3) * 15));
  if (t > 2.0 && t < 2.3) s += dashLines(T, { n: 30, op: .7, speed: 9000, color: '#FFE7A0' });
  return s;
}, '«Кто ты?»');

shot(145, 150.4, (t, T) => {
  let s = sky('red', T);
  const roar = lip('d8', T);
  s += g(devHead(T, { roar }), tr(960, 600, 1.9));
  const fist = E.inC(P(t, 4.4, 1.0));
  if (fist > 0) s += g(devFist(), tr(960, 600, .4 + fist * 2.6));
  s += particles(T, { kind: 'ember', n: 60, seed: 73, vy: -150, size: 1.6 });
  return { svg: s, shake: shakeAt(T, 4 + roar * 12 + fist * 10) };
}, 'Дев в ярости');

shot(150.4, 153, (t, T) => {
  let s = rect(-100, -100, W + 200, H + 200, '#1A0204');
  s += speedLines(960, 540, T, { n: 120, r0: 260, color: '#FFFFFF', op: .7 });
  s += g(devFist(), tr(1250, 540, 1.6));
  s += cracks(79, 1000, 540, 600, E.outC(P(t, .1, .6)), '#7FF3E8');
  s += g(heroFigure({ t: T, pose: 'punch', rimCol: '#7FF3E8', windDir: -1 }), tr(560, 820, 1.25, -10));
  s += shockRing(980, 540, P(t, .05, .8), 1100, '#BFFFF6') + shockRing(980, 540, P(t, .25, .8), 900, '#FFE7A0');
  const imp = t < .1 || (t > .18 && t < .26) || (t > .34 && t < .4);
  return { svg: s, filter: imp ? 'invert(1) grayscale(1) contrast(3)' : '', shake: shakeAt(T, 16 * (1 - P(t, 0, 1.5))) };
}, 'Столкновение');

shot(153, 157.8, (t, T) => {
  let s = sky('red', T);
  s += g(humo(T, { flap: .6 }), tr(960, 420, 1.1), `opacity="${f2(.35 + lip('d9', T) * .3)}"`);
  s += particles(T, { kind: 'star', n: 70, seed: 83, vy: 0, vx: 0, sway: 0, color: '#7FF3E8', op: .9 });
  s += g(C('hero', 960, 500, 1.6, { t: T, brows: 'angry', wind: 1.2, hairLift: .4 }), '', 'filter="url(#gradeRedChar)"');
  // три круга-гирих перед кулаком
  for (let i = 0; i < 3; i++) {
    const k = E.outB(P(t, .5 + i * .6, .6));
    s += g(g(girihCircle(T * (i % 2 ? -1 : 1), 260 - i * 50, { op: k, spin: 80 }), 'scale(.4 1)'), tr(1350 + i * 140, 620, 1));
  }
  return { svg: s, shake: shakeAt(T, 2 + P(t, 2, 2) * 4) };
}, 'Сила звёзд');

shot(157.8, 162, (t, T) => {
  let s = rect(-100, -100, W + 200, H + 200, '#0A0418');
  s += g(girihCircle(T, 600, { spin: 120, color: '#FFE7A0', color2: '#7FF3E8' }), tr(960, 520));
  s += speedLines(960, 520, T, { n: 120, r0: 380, color: '#FFE7A0', op: .6 });
  const thrust = E.outX(P(t, 1.9, .4));
  s += g(C('hero', 960, 480, 2.1 - thrust * .3, { t: T, brows: 'angry', wind: 1.8, hairLift: .6 }), '', '');
  // кулак со звездой летит в камеру
  s += g(hand('fist', { sleeve: '#1B2A6E' }) + g(path(starPath(44, 18, 8), '#FFF6C8'), 'translate(0 -10)', 'filter="url(#glowL)"'), tr(lerp(1500, 960, thrust), lerp(1000, 560, thrust), lerp(1.4, 5.5, thrust)));
  const imp = t > 2.3 && t < 2.4;
  return { svg: s, filter: imp ? 'invert(1) grayscale(1) contrast(3)' : '', shake: shakeAt(T, 4 + thrust * 18) };
}, '«Звезда Улугбека!»');

shot(162, 166, (t, T) => {
  const k = P(t, 0, 3.5);
  let s = sky('red', T);
  // небо трескается — за ним рассвет
  const cid = uid('crk');
  s += `<clipPath id="${cid}"><path d="M960 1080L700 600L860 560L560 200L900 260L960 -100L1060 240L1400 160L1100 560L1300 620L960 1080Z" transform="translate(960 540) scale(${f2(E.outC(k) * 2.2)}) translate(-960 -540)"/></clipPath>`;
  s += g(sky('dawn', T), '', `clip-path="url(#${cid})"`);
  s += g(devHead(T, { roar: 1, eyes: 1 - k }), tr(960, 400, 1.3), `opacity="${f2(1 - P(t, .5, 2))}"`);
  s += particles(T, { kind: 'ember', n: 120, seed: 89, vy: -200, vx: 60, size: 2, op: 1 - P(t, 2, 2) });
  // луч
  s += g(rect(-140, -2000, 280, 3000, '#FFFFFF') + rect(-260, -2000, 520, 3000, '#BFFFF6', 'opacity=".5"'), tr(960, 1080, 1 - P(t, .2, 2.5)), 'filter="url(#blur16)"');
  s += g(registanClose(T, { night: true }), 'translate(0 120)', 'filter="url(#gradeRedDark)"');
  s += fadeWhite(1 - P(t, 0, .8));
  return { svg: s, shake: shakeAt(T, 10 * (1 - k)) };
}, 'Удар — небо раскалывается');

shot(166, 170, (t, T) => {
  let s = sky('dawn', T);
  s += g(circle(960, 640, 140, '#FFF2C8') + circle(960, 640, 320, '#FFD27A', 'opacity=".4"'), '', 'filter="url(#blur16)"');
  s += godRays(960, 640, T, { n: 18, color: '#FFE7A0', op: .3 });
  const pan = samarkandPanorama(T, {});
  s += g(pan.far + pan.mid, 'translate(0 40)', 'filter="url(#gradeDusk)"');
  s += g(heroFigure({ t: T, pose: 'stand', col: '#140A18', rimCol: '#FFD27A', wind: .8 }), tr(960, 584, .42));
  s += pigeons(T, 91, 10);
  return cam(s, 1.05 - t * .01, 960, 600);
}, 'Рассвет');

/* ---- ЭПИЛОГ ---- */
shot(170, 176, (t, T) => {
  let s = blurG(courtyard(T), 'blur4');
  s += C('kid', 360, 600, 1.1, { t: T, look: [.6, 0], mouth: 0, blink: blinkAt(T, 8) });
  s += C('sardor', 1560, 600, 1.1, { t: T, look: [-.6, 0], eyes: 'wide', blink: blinkAt(T, 9) });
  const gest = Math.sin(T * 5) * 4;
  s += C('bahodir', 960, 470 + gest, 1.65, { t: T, eyes: 'wide', brows: 'surprised', mean: false, mouth: lip('e1', T), blink: blinkAt(T, 10) });
  // пластырь на щеке
  s += g(rect(-30, -12, 60, 24, '#F2D2B0', 'stroke="#B08A6A" stroke-width="2" rx="6"'), tr(960 + 70 * 1.65, 470 + gest + 60 * 1.65, 1.65, -20));
  return s;
}, 'Баходир рассказывает');

shot(176, 179.5, (t, T) => {
  let s = blurG(classroom(T), 'blur4');
  s += C('nilufar', 900, 470, 1.8, { t: T, turn: -.3, look: [-.6, -.3], mouth: lip('e2', T), blink: blinkAt(T, 3), wind: .2 });
  s += g(hand('hold') + g(feather(T), 'translate(30 -170) scale(.6)'), tr(1260, 800, 1.4, -10));
  return cam(s, 1 + t * .01);
}, 'Нилуфар и перо');

shot(179.5, 182.2, (t, T) => {
  let s = blurG(classroom(T), 'blur4');
  s += C('jasur', 560, 520, 1.45, { t: T, look: [.5, 0], blink: blinkAt(T, 4), mouthShape: 'neutral' });
  // забинтованная рука
  s += g(hand('fist') + rect(-74, -30, 150, 60, '#FFFFFF', 'stroke="#C8C8D0" stroke-width="2" opacity=".95"') + strokeP('M-70 -10L72 -14M-70 12L72 8', '#D8D8E0', 2), tr(760, 980, 1.2, -10));
  s += C('nilufar', 1380, 500, 1.45, { t: T, turn: -.5, look: [-.8, .4], mouth: lip('e3', T), brows: 'sad', blink: blinkAt(T, 5) });
  return s;
}, '«Что с рукой?»');

shot(182.2, 184.8, (t, T) => {
  let s = mangaBg(T, '#D6ECFF', '#9ACBF0');
  s += C('jasur', 960, 480, 1.95, { t: T, mouth: lip('e4', T), sweat: 1, blush: .6, look: [-.4, -.2], brows: 'sad' });
  return s;
}, '«Упал... со звёзд»');

shot(184.8, 187.6, (t, T) => {
  let s = rect(-100, -100, W + 200, H + 200, '#FFF0E6') + bokeh(T, 99, ['#FFC8D8', '#FFE6A0', '#FFFFFF'], 22);
  s += C('nilufar', 960, 480, 1.95, { t: T, eyes: 'smile', mouthShape: 'laugh', mouth: Math.max(.3, lip('e5', T)), blush: .7, wind: .3 });
  s += particles(T, { kind: 'star', n: 20, seed: 101, vy: -20, color: '#FFD978' });
  return s;
}, 'Она смеётся');

shot(187.6, 194, (t, T) => {
  const px = E.io(P(t, 2.5, 3.5));
  let s = classroom(T);
  s += C('jasur', 640, 520, 1.3, { t: T, mouthShape: 'smile', look: [.5, 0], blink: blinkAt(T, 6), blush: .4 });
  s += C('nilufar', 1280, 500, 1.3, { t: T, eyes: 'smile', mouthShape: 'smile', turn: -.4, wind: .2 });
  s += godRays(500, -100, T, { n: 10, spread: .7, a0: .9, op: .22 });
  // днём в окне мерцает звезда и пролетает Хумо
  s += g(path(starPath(30, 6, 4), '#FFFFFF'), tr(330, 260, .6 + .4 * Math.sin(T * 4)), 'filter="url(#glow)"');
  s += g(humo(T, { flap: 1.2, flapSpeed: 6 }), tr(lerp(-200, 900, P(t, 3, 3)), 280, .12), `opacity="${f2(P(t, 3, .5) * .8)}"`);
  return cam(s, 1 + px * .25, 400, 300);
}, 'Вместе');

shot(194, 200, (t, T) => {
  let s = rect(-50, -50, W + 100, H + 100, '#06020C');
  s += titleCard(t, { sub: 'ПРОДОЛЖЕНИЕ СЛЕДУЕТ...' });
  s += particles(T, { kind: 'star', n: 30, seed: 4, vy: -30, op: .8 });
  s += fadeBlack(P(t, 4.6, 1.4));
  return s;
}, 'Финальный титр');

const TIMELINE_END = 200;

/* ---------- кадр ---------- */
function renderFrame(T) {
  let sh = SHOTS[SHOTS.length - 1];
  for (const s of SHOTS) if (T >= s.a && T < s.b) { sh = s; break; }
  let r = sh.f(T - sh.a, T);
  if (typeof r === 'string') r = { svg: r };
  r.svg = svgWrap(r.svg);
  return r;
}

/* ---------- звук: события и музыкальные части для audio.py ---------- */
const SECTIONS = [
  ['prologue', 0, 13], ['morning', 13, 47.6], ['bully', 47.6, 71.5], ['night', 71.5, 100.4], ['transform', 100.4, 106],
  ['crisis', 106, 118.5], ['battle', 118.5, 162], ['dawn', 162, 170], ['epilogue', 170, 194], ['end', 194, 200],
];
const SFX = [
  [0.2, 'wind'], [5.0, 'whoosh'], [9.0, 'impact'], [9.0, 'gong'], [12.6, 'riser'],
  [13.0, 'birds'], [21.5, 'steps'], [25.4, 'pencil'], [28.6, 'bell'], [39.7, 'swish'], [42.2, 'boing'], [44.6, 'sparkle'], [45.2, 'heart'],
  [47.6, 'sting'], [51.4, 'swish'], [57.6, 'tear'], [59.1, 'thud'], [60.6, 'swish'], [66.0, 'paper'], [67.0, 'sad'],
  [71.5, 'crickets'], [80.4, 'swell'], [82.3, 'chime'], [93.6, 'magic'], [100.4, 'riser'], [102.6, 'impact'], [102.6, 'gong'], [104.6, 'sparkle'],
  [106.2, 'quake'], [108.5, 'rumble'], [109.5, 'roar'],
  [120.8, 'cloth'], [121.3, 'chime'], [122.1, 'whoosh'], [123.0, 'whoosh'], [125.5, 'crack'], [127.6, 'whoosh'], [128.0, 'impact'],
  [134.4, 'dash'], [136.4, 'crack'], [136.7, 'whoosh'], [137.6, 'swell'], [143.6, 'dash'], [143.8, 'chime'],
  [144.4, 'roar'], [149.4, 'whoosh'], [150.4, 'impact'], [150.4, 'gong'], [153.5, 'magic'], [154.1, 'chime'], [154.7, 'chime'], [155.3, 'chime'],
  [157.8, 'riser'], [159.7, 'whoosh'], [160.1, 'impact'], [162.0, 'boom'], [162.0, 'gong'], [163.0, 'glass'], [166.0, 'birds'],
  [170.0, 'bell'], [176.0, 'chime'], [184.8, 'sparkle'], [194.0, 'gong'],
];
function audioCues() {
  const lines = Object.keys(AT).filter(id => VD[id]).map(id => ({ id, t: AT[id], dur: VD[id].dur, who: VD[id].who }));
  return { lines, sfx: SFX.map(([t, type]) => ({ t, type })), sections: SECTIONS.map(([name, a, b]) => ({ name, a, b })),
    shots: SHOTS.map(s => ({ a: s.a, b: s.b, name: s.name })) };
}
