/* ЮЛДУЗ — фоны: Самарканд (Регистан, купола, минареты, махалля), школа №17, класс, двор с арыком,
   руины обсерватории Улугбека, Сиабский базар. Каждый фон — функция, возвращающая SVG-разметку
   в координатах кадра 1920×1080. Ночь и красное небо — те же постройки через цветовые фильтры. */
'use strict';

const PAL = {
  brick: '#D9B27C', brickSh: '#B48552', brickDk: '#8E6438', tq: '#25AFC0', tqHi: '#86E6E8', tqDk: '#14707E',
  cobalt: '#1E4FA3', cobaltDk: '#132F6B', gold: '#E8B54A', cream: '#F4EBD6', ink: '#2A1A14',
};

const SCENE_PATTERNS = `
<pattern id="pGirih" width="40" height="40" patternUnits="userSpaceOnUse">
  <rect width="40" height="40" fill="${PAL.cobalt}"/>
  <path d="M20 4L24 16L36 20L24 24L20 36L16 24L4 20L16 16Z" fill="#F4EBD6"/>
  <path d="M20 10L22 18L30 20L22 22L20 30L18 22L10 20L18 18Z" fill="${PAL.tq}"/>
  <path d="M0 0L6 0L0 6ZM40 0L34 0L40 6ZM0 40L6 40L0 34ZM40 40L34 40L40 34Z" fill="${PAL.gold}"/>
</pattern>
<pattern id="pBanna" width="36" height="36" patternUnits="userSpaceOnUse">
  <rect width="36" height="36" fill="${PAL.brick}"/>
  <path d="M0 9h36M0 18h36M0 27h36" stroke="${PAL.brickSh}" stroke-width="1"/>
  <path d="M18 2L26 10L18 18L10 10Z" fill="${PAL.tq}"/><path d="M0 20L8 28L0 36ZM36 20L28 28L36 36Z" fill="${PAL.cobalt}"/>
  <path d="M18 6L22 10L18 14L14 10Z" fill="${PAL.cream}"/>
</pattern>
<pattern id="pMosaic" width="48" height="48" patternUnits="userSpaceOnUse">
  <rect width="48" height="48" fill="${PAL.tq}"/>
  <circle cx="24" cy="24" r="13" fill="${PAL.cobalt}"/>
  <path d="M24 13C28 19 28 29 24 35C20 29 20 19 24 13Z" fill="${PAL.gold}"/>
  <path d="M13 24C19 20 29 20 35 24C29 28 19 28 13 24Z" fill="${PAL.cream}"/>
  <circle cx="24" cy="24" r="3" fill="${PAL.tqDk}"/>
  <path d="M0 0Q12 6 0 12ZM48 0Q36 6 48 12ZM0 36Q12 42 0 48ZM48 36Q36 42 48 48Z" fill="${PAL.cobaltDk}"/>
</pattern>
<pattern id="pRib" width="22" height="200" patternUnits="userSpaceOnUse">
  <rect width="22" height="200" fill="${PAL.tq}"/><rect width="7" height="200" fill="${PAL.tqHi}" opacity=".35"/><rect x="18" width="4" height="200" fill="${PAL.tqDk}" opacity=".6"/>
</pattern>
<pattern id="pBrickWall" width="60" height="24" patternUnits="userSpaceOnUse">
  <rect width="60" height="24" fill="#D6B58C"/><path d="M0 12h60M0 24h60M15 0v12M45 0v12M0 12v12M30 12v12" stroke="#B99368" stroke-width="2"/>
</pattern>
<pattern id="pCalli" width="80" height="30" patternUnits="userSpaceOnUse">
  <rect width="80" height="30" fill="${PAL.cobaltDk}"/>
  <path d="M4 22C10 6 14 6 16 22M20 22V6M26 22C30 14 38 14 40 22C34 26 28 26 26 22M46 22V8M52 22C56 10 64 10 66 22M70 22l6 -14" stroke="${PAL.cream}" stroke-width="2.4" fill="none" stroke-linecap="round"/>
</pattern>
<pattern id="pMaj" width="56" height="56" patternUnits="userSpaceOnUse">
  <rect width="56" height="56" fill="#F5F0E6"/>
  <path d="M28 4L34 22L52 28L34 34L28 52L22 34L4 28L22 22Z" fill="${PAL.cobalt}"/>
  <path d="M28 14L31 25L42 28L31 31L28 42L25 31L14 28L25 25Z" fill="${PAL.tq}"/>
  <circle cx="28" cy="28" r="3" fill="${PAL.gold}"/>
</pattern>
<linearGradient id="gDome" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#6FE0E4"/><stop offset=".45" stop-color="${PAL.tq}"/><stop offset="1" stop-color="#0E5A68"/></linearGradient>
<linearGradient id="gDomeCob" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#4E86D8"/><stop offset=".45" stop-color="${PAL.cobalt}"/><stop offset="1" stop-color="#0C2252"/></linearGradient>
<linearGradient id="gNiche" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E3A5C"/><stop offset="1" stop-color="#1E5A7A"/></linearGradient>
`;

/* ---------- архитектурные примитивы ---------- */
function dome(cx, base, w, h, o = {}) {
  const x0 = cx - w / 2, x1 = cx + w / 2;
  const d = `M${x0} ${base}C${x0 - w * .06} ${base - h * .55} ${cx - w * .3} ${base - h * .98} ${cx} ${base - h}C${cx + w * .3} ${base - h * .98} ${x1 + w * .06} ${base - h * .55} ${x1} ${base}Z`;
  let s = '';
  // барабан
  const dh = h * (o.drum || .42), dw = w * .9;
  s += rect(cx - dw / 2, base, dw, dh, 'url(#pBanna)', `stroke="${PAL.brickDk}" stroke-width="2"`);
  s += rect(cx - dw / 2, base + dh * .18, dw, dh * .38, 'url(#pCalli)');
  s += rect(cx - dw / 2, base, dw, 6, PAL.gold);
  s += rect(cx + dw * .15, base, dw * .35, dh, 'rgba(60,30,10,.25)');
  // купол
  s += path(d, o.cob ? 'url(#gDomeCob)' : 'url(#gDome)', `stroke="${PAL.tqDk}" stroke-width="2"`);
  let ribs = '';
  const n = o.ribs || 14;
  for (let i = 1; i < n; i++) {
    const u = i / n, xx = lerp(x0, x1, u);
    ribs += `M${f2(xx)} ${base}C${f2(lerp(xx, cx, .2))} ${f2(base - h * .6)} ${f2(lerp(xx, cx, .75))} ${f2(base - h * .97)} ${cx} ${base - h}`;
  }
  s += path(ribs, 'none', `stroke="${o.cob ? '#0C2252' : PAL.tqDk}" stroke-width="2.4" opacity=".7"`);
  s += path(`M${x0 + w * .1} ${base - h * .3}C${x0 + w * .12} ${base - h * .7} ${cx - w * .22} ${base - h * .92} ${cx - w * .05} ${base - h * .95}`, 'none', 'stroke="#FFFFFF" stroke-width="5" opacity=".35" stroke-linecap="round"');
  // шпиль
  s += rect(cx - 2.5, base - h - h * .18, 5, h * .18, PAL.gold) + circle(cx, base - h - h * .08, 6, PAL.gold) + circle(cx, base - h - h * .15, 4, PAL.gold);
  return s;
}

function minaret(cx, base, w, h, o = {}) {
  const top = base - h, wt = w * .78;
  let s = '';
  s += path(`M${cx - w / 2} ${base}L${cx - wt / 2} ${top}L${cx + wt / 2} ${top}L${cx + w / 2} ${base}Z`, 'url(#pBanna)', `stroke="${PAL.brickDk}" stroke-width="2"`);
  // пояса
  for (const k of [.18, .5, .78]) {
    const y = base - h * k, ww = lerp(w, wt, k);
    s += rect(cx - ww / 2, y - 10, ww, 20, 'url(#pGirih)');
  }
  s += path(`M${cx + w * .12} ${base}L${cx + wt * .12} ${top}L${cx + wt / 2} ${top}L${cx + w / 2} ${base}Z`, 'rgba(70,35,10,.28)');
  // фонарь-галерея
  const gw = wt * 1.35, gh = w * .55;
  s += path(`M${cx - wt / 2} ${top}L${cx - gw / 2} ${top - gh * .4}L${cx + gw / 2} ${top - gh * .4}L${cx + wt / 2} ${top}Z`, PAL.tq, `stroke="${PAL.tqDk}" stroke-width="2"`);
  s += rect(cx - gw / 2, top - gh * 1.2, gw, gh * .8, PAL.cream, `stroke="${PAL.brickDk}" stroke-width="2"`);
  let arch = '';
  const na = 5;
  for (let i = 0; i < na; i++) { const ax = cx - gw / 2 + gw * (i + .5) / na, aw = gw / na * .55; arch += `M${f2(ax - aw / 2)} ${f2(top - gh * .45)}V${f2(top - gh * .9)}Q${f2(ax)} ${f2(top - gh * 1.15)} ${f2(ax + aw / 2)} ${f2(top - gh * .9)}V${f2(top - gh * .45)}Z`; }
  s += path(arch, '#1A3A55');
  s += path(`M${cx - gw / 2 - 6} ${top - gh * 1.2}L${cx + gw / 2 + 6} ${top - gh * 1.2}L${cx + gw * .3} ${top - gh * 1.45}L${cx - gw * .3} ${top - gh * 1.45}Z`, PAL.tq, `stroke="${PAL.tqDk}" stroke-width="2"`);
  if (o.cap !== false) s += dome(cx, top - gh * 1.45, gw * .55, gw * .45, { drum: .01, ribs: 6 });
  return s;
}

function pointedArch(x, y, w, h) {
  // y — низ, h — высота до вершины
  return `M${f2(x - w / 2)} ${f2(y)}V${f2(y - h * .55)}C${f2(x - w / 2)} ${f2(y - h * .85)} ${f2(x - w * .12)} ${f2(y - h * .92)} ${f2(x)} ${f2(y - h)}C${f2(x + w * .12)} ${f2(y - h * .92)} ${f2(x + w / 2)} ${f2(y - h * .85)} ${f2(x + w / 2)} ${f2(y - h * .55)}V${f2(y)}Z`;
}

function portal(cx, base, w, h, o = {}) {
  let s = '';
  s += rect(cx - w / 2, base - h, w, h, 'url(#pMosaic)', `stroke="${PAL.brickDk}" stroke-width="3"`);
  s += rect(cx - w / 2, base - h, w, h * .09, 'url(#pCalli)');
  // рамки
  const fr = w * .07;
  s += path(`M${cx - w / 2} ${base}V${base - h}H${cx + w / 2}V${base}H${cx + w / 2 - fr}V${base - h + fr}H${cx - w / 2 + fr}V${base}Z`, 'url(#pGirih)');
  // ниша-айван
  const aw = w * .62, ah = h * .78;
  s += path(pointedArch(cx, base, aw + 24, ah + 22), PAL.gold);
  s += path(pointedArch(cx, base, aw, ah), 'url(#gNiche)');
  // сталактиты-мукарнас
  let mq = '';
  for (let r_ = 0; r_ < 3; r_++) for (let i = 0; i < 5 + r_; i++) {
    const xx = cx - aw * .32 + (aw * .64) * (i + .5) / (5 + r_), yy = base - ah * (.62 - r_ * .07);
    mq += `M${f2(xx - 9)} ${f2(yy)}Q${f2(xx)} ${f2(yy - 18)} ${f2(xx + 9)} ${f2(yy)}`;
  }
  s += path(mq, 'none', `stroke="${PAL.tqHi}" stroke-width="2" opacity=".55"`);
  // дверь и решётка
  s += path(pointedArch(cx, base, aw * .42, ah * .45), '#5A3418', `stroke="${PAL.gold}" stroke-width="3"`);
  s += rect(cx - 1.5, base - ah * .4, 3, ah * .4, PAL.gold);
  if (o.tiger) {
    // Шердор: тигры и солнце с лицом
    for (const sd of [-1, 1]) {
      const tx = cx + sd * w * .36, ty = base - h * .8;
      s += g(path('M-40 0C-30 -16 10 -18 30 -8L44 -14L40 0L30 4C10 12 -24 12 -40 0Z', '#F2A93B', 'stroke="#5A2A08" stroke-width="2"') +
        path('M-30 -4l6 8M-18 -8l6 10M-6 -8l6 10M6 -6l6 8', 'none', 'stroke="#2A1408" stroke-width="3"') + circle(38, -6, 8, '#FFE07A'), `translate(${f2(tx)} ${f2(ty)}) scale(${f2(sd * -w / 260)} ${f2(w / 260)})`);
    }
  }
  return s;
}

function arcadeWing(x0, x1, base, h, o = {}) {
  let s = rect(x0, base - h, x1 - x0, h, 'url(#pBanna)', `stroke="${PAL.brickDk}" stroke-width="2"`);
  s += rect(x0, base - h, x1 - x0, 12, 'url(#pGirih)');
  const n = Math.max(2, Math.round((x1 - x0) / (h * .42)));
  const cw = (x1 - x0) / n;
  for (let row = 0; row < 2; row++) for (let i = 0; i < n; i++) {
    const ax = x0 + cw * (i + .5), ay = base - h * (row ? .52 : .04);
    s += path(pointedArch(ax, ay, cw * .6, h * .4), '#F1E2C4');
    s += path(pointedArch(ax, ay - 4, cw * .48, h * .34), row ? '#1E4A66' : '#2A5A70');
  }
  if (o.shade) s += rect(x0, base - h, x1 - x0, h, 'rgba(60,30,10,.18)');
  return s;
}

/* медресе: крылья-аркады + портал + угловые минареты (+ купол) */
function madrasah(cx, base, sc, o = {}) {
  let s = '';
  const W_ = 520 * sc, Hw = 150 * sc, Hp = 300 * sc, Wp = 240 * sc;
  if (o.dome) s += dome(cx + (o.domeDx || 0) * sc, base - Hw - 10 * sc, 190 * sc, 170 * sc, { cob: o.cob });
  s += arcadeWing(cx - W_ / 2, cx - Wp / 2, base, Hw);
  s += arcadeWing(cx + Wp / 2, cx + W_ / 2, base, Hw, { shade: true });
  s += portal(cx, base, Wp, Hp, { tiger: o.tiger });
  if (o.minarets !== false) {
    s += minaret(cx - W_ / 2, base, 46 * sc, 330 * sc);
    s += minaret(cx + W_ / 2, base, 46 * sc, 330 * sc);
  }
  return s;
}

function house(x, base, w, h, o = {}) {
  const c = o.col || '#E3C9A0';
  let s = rect(x, base - h, w, h, c, `stroke="${PAL.brickDk}" stroke-width="1.5"`);
  s += rect(x - 4, base - h - 6, w + 8, 8, '#C7A57A');
  s += rect(x + w * .55, base - h, w * .45, h, 'rgba(80,40,10,.18)');
  const nw = Math.max(1, Math.floor(w / 42));
  for (let i = 0; i < nw; i++) {
    const wx = x + (i + .5) * w / nw - 9;
    s += rect(wx, base - h * .7, 18, 24, o.lit ? '#FFD27A' : '#5A7A90', `stroke="${PAL.brickDk}" stroke-width="1.5"`);
    s += rect(wx, base - h * .7, 18, 5, PAL.tq);
  }
  return s;
}
function poplar(x, base, h, col) {
  const c = col || '#4E8A3A';
  return rect(x - 3, base - h * .25, 6, h * .25, '#5A3A20') + path(`M${x} ${base - h}C${x + h * .1} ${base - h * .7} ${x + h * .09} ${base - h * .3} ${x} ${base - h * .18}C${x - h * .09} ${base - h * .3} ${x - h * .1} ${base - h * .7} ${x} ${base - h}Z`, c, 'stroke="rgba(0,0,0,.25)" stroke-width="1.5"');
}
function chinar(x, base, r, t, o = {}) {
  const sw = Math.sin((t || 0) * 1.2 + x) * 4;
  const cols = o.autumn ? ['#E8A93A', '#F2C14E', '#C9711F', '#FFE08A'] : ['#5E9A3A', '#7AB84A', '#3E7A2A', '#9AD060'];
  let s = path(`M${x - 10} ${base}L${x - 6} ${base - r * 1.1}L${x - 40} ${base - r * 1.6}M${x + 8} ${base}L${x + 6} ${base - r * 1.2}L${x + 50} ${base - r * 1.7}`, 'none', 'stroke="#6A5040" stroke-width="12" stroke-linecap="round"');
  s += rect(x - 12, base - r * 1.1, 24, r * 1.1, '#7A5E4A');
  const rr = rng(Math.round(x));
  for (let i = 0; i < 14; i++) {
    const a = rr() * Math.PI * 2, d = rr() * r * .7;
    s += circle(x + Math.cos(a) * d * 1.3 + sw * (i % 3), base - r * 1.7 + Math.sin(a) * d * .8, r * (.35 + rr() * .3), cols[i % 4], 'stroke="rgba(80,40,0,.25)" stroke-width="2"');
  }
  return s;
}

/* ---------- небо ---------- */
function sky(kind, t) {
  const id = uid('sky');
  const P_ = {
    day: [['#5DB4EE', 0], ['#9AD4F6', .55], ['#E6F4FA', 1]],
    morning: [['#6AAEE6', 0], ['#B9DDF2', .5], ['#FCE3C0', 1]],
    dusk: [['#2A2560', 0], ['#B0507A', .5], ['#FFB070', .85], ['#FFE0A0', 1]],
    night: [['#050A1E', 0], ['#0E1A40', .6], ['#24305E', 1]],
    red: [['#1A0208', 0], ['#5A0814', .35], ['#B01A1A', .7], ['#FF6A2A', 1]],
    dawn: [['#2A3A7A', 0], ['#E07AA0', .45], ['#FFC27A', .75], ['#FFF2C8', 1]],
  }[kind];
  let s = lg(id, P_.map(([c, o]) => [o, c]));
  s += rect(-400, -400, W + 800, H + 800, `url(#${id})`);
  if (kind === 'day' || kind === 'morning') {
    // облака
    const r = rng(4);
    for (let i = 0; i < 7; i++) {
      const cx = ((r() * 2600 + (t || 0) * 12 * (0.5 + r())) % 2600) - 340, cy = 80 + r() * 300, sc = .6 + r() * .9;
      s += g(path('M-160 40C-170 0 -120 -20 -90 -6C-80 -50 -10 -60 10 -20C30 -50 100 -46 110 -4C150 -14 180 20 160 40Z', '#FFFFFF', 'opacity=".9"') +
        path('M-160 40C-120 30 100 30 160 40C120 52 -120 52 -160 40Z', '#D6E6F4', 'opacity=".9"'), `translate(${f2(cx)} ${f2(cy)}) scale(${f2(sc)})`);
    }
  }
  if (kind === 'night' || kind === 'dusk') s += starfield(21, kind === 'night' ? 260 : 80, { t });
  return s;
}

/* ---------- панорама Самарканда ---------- */
function samarkandPanorama(t, o = {}) {
  const mood = o.mood || 'day';
  let far = '', mid = '', near = '';
  // горы Зарафшана
  far += path('M-200 640L100 520L260 580L480 470L700 560L900 500L1120 570L1320 480L1560 560L1760 500L2100 590L2100 700L-200 700Z', mood === 'day' ? '#A9C4D8' : '#6A7AA0', 'opacity=".8"');
  // дальние кварталы
  const r = rng(77);
  for (let i = 0; i < 40; i++) { const x = -100 + i * 55 + r() * 20, h = 30 + r() * 50; mid += house(x, 720, 50 + r() * 30, h, { col: '#D8C0A0', lit: mood !== 'day' && r() > .5 }); }
  for (let i = 0; i < 16; i++) mid += poplar(-50 + i * 130 + r() * 40, 724, 110 + r() * 60, mood === 'day' ? '#5E8A40' : '#2A3A30');
  // Регистан
  mid += madrasah(560, 760, .62, {});
  mid += madrasah(1360, 760, .62, { tiger: true });
  mid += madrasah(960, 740, .66, { dome: true, domeDx: 220, minarets: false });
  // Гур-Эмир справа, Биби-Ханум слева
  mid += dome(1780, 650, 150, 150, { ribs: 18 }) + minaret(1680, 760, 26, 260) + minaret(1880, 760, 26, 260);
  mid += dome(150, 640, 170, 120, { cob: true });
  // ближние дома и деревья
  for (let i = 0; i < 14; i++) { const x = -60 + i * 150 + r() * 30; near += house(x, 900, 120 + r() * 40, 90 + r() * 60, { lit: mood !== 'day' && r() > .4 }); }
  for (let i = 0; i < 9; i++) near += chinar(40 + i * 230 + r() * 60, 930, 60 + r() * 30, t, { autumn: true });
  near += rect(-200, 900, W + 400, 300, mood === 'day' ? '#C9A97E' : '#3A2A30');
  return { far, mid, near };
}

/* крупный план Регистана для дневных и ночных сцен */
function registanClose(t, o = {}) {
  let s = '';
  s += madrasah(260, 860, 1.05, {});
  s += madrasah(1660, 860, 1.05, { tiger: true });
  s += madrasah(960, 820, 1.1, { dome: true, domeDx: 300, minarets: false });
  // площадь
  s += path('M-200 860L2120 860L2120 1200L-200 1200Z', o.night ? '#2A1A22' : '#D8C09A');
  let tiles = '';
  for (let i = -20; i < 20; i++) tiles += `M${960 + i * 140} 860L${960 + i * 420} 1200`;
  for (let j = 0; j < 6; j++) { const y = 860 + j * j * 12 + j * 8; tiles += `M-200 ${y}H2120`; }
  s += path(tiles, 'none', `stroke="${o.night ? '#1A0E14' : '#B89C76'}" stroke-width="2"`);
  return s;
}

/* ---------- школа №17 ---------- */
function schoolExterior(t, o = {}) {
  let s = sky('morning', t);
  s += path('M-200 760L2120 760L2120 1200L-200 1200Z', '#CDB596');
  // здание
  s += rect(260, 300, 1400, 470, '#EFE6D6', `stroke="${PAL.brickDk}" stroke-width="3"`);
  s += rect(260, 300, 1400, 40, 'url(#pMaj)');
  s += rect(260, 540, 1400, 22, 'url(#pGirih)');
  for (let row = 0; row < 2; row++) for (let i = 0; i < 12; i++) {
    if (i >= 5 && i <= 6) continue;
    const x = 310 + i * 112, y = row ? 590 : 370;
    s += path(pointedArch(x + 34, y + 130, 64, 130), '#3E7EA8', `stroke="${PAL.cream}" stroke-width="6"`);
    s += path(`M${x + 34} ${y + 6}V${y + 130}M${x + 2} ${y + 70}H${x + 66}`, 'none', `stroke="${PAL.cream}" stroke-width="3"`);
    s += path(pointedArch(x + 24, y + 128, 20, 100), '#9FD8F0', 'opacity=".35"');
  }
  // центральный портал
  s += portal(960, 770, 300, 520, {});
  // вывеска
  s += rect(780, 214, 360, 70, PAL.cobalt, `stroke="${PAL.gold}" stroke-width="5" rx="8"`);
  s += `<text x="960" y="262" text-anchor="middle" font-family="Unbounded" font-weight="700" font-size="34" fill="#F4EBD6">17-MAKTAB</text>`;
  s += `<text x="960" y="204" text-anchor="middle" font-family="Rubik" font-weight="700" font-size="22" fill="${PAL.cobaltDk}">MIRZO ULUG'BEK NOMIDAGI</text>`;
  s += chinar(160, 800, 120, t, { autumn: true }) + chinar(1780, 800, 130, t, { autumn: true });
  // флагшток
  s += rect(1600, 420, 6, 380, '#8A8A90');
  const fw = Math.sin(t * 4) * 6;
  s += path(`M1606 420C1660 ${410 + fw} 1700 ${430 - fw} 1750 ${420 + fw}L1750 468C1700 ${478 - fw} 1660 ${458 + fw} 1606 468Z`, '#1EB5E8');
  s += path(`M1606 452C1660 ${442 + fw} 1700 ${462 - fw} 1750 ${452 + fw}L1750 468C1700 ${478 - fw} 1660 ${458 + fw} 1606 468Z`, '#1EB25A');
  s += path(`M1606 449C1660 ${439 + fw} 1700 ${459 - fw} 1750 ${449 + fw}L1750 455C1700 ${465 - fw} 1660 ${445 + fw} 1606 455Z`, '#E8332A');
  s += path(`M1606 436C1660 ${426 + fw} 1700 ${446 - fw} 1750 ${436 + fw}L1750 449C1700 ${459 - fw} 1660 ${439 + fw} 1606 449Z`, '#FFFFFF');
  // ученики-силуэты идут к школе
  for (let i = 0; i < 9; i++) {
    const x = ((i * 230 + t * 60 * (i % 2 ? 1 : -1)) % 2200 + 2200) % 2200 - 140, y = 900 + (i % 3) * 40;
    s += g(path('M-18 -120C-18 -150 18 -150 18 -120C18 -100 -18 -100 -18 -120ZM-26 -96L26 -96L30 -20L-30 -20Z', i % 2 ? '#2A3054' : '#F4F4F8', 'stroke="#2A1A14" stroke-width="2"') +
      path('M-22 -20L-18 30L-6 30L-2 -20ZM2 -20L6 30L18 30L22 -20Z', '#2A3054') + (i % 3 === 0 ? path('M-20 -136Q0 -150 20 -136L18 -126Q0 -136 -18 -126Z', '#121216') : ''), tr(x, y, 1.1 + (i % 3) * .15));
  }
  return s;
}

/* класс: окно с видом на купол, лучи, парты */
function classroom(t, o = {}) {
  let s = rect(-200, -200, W + 400, H + 400, '#E9DCC4');
  s += rect(-200, 760, W + 400, 600, '#A97C55');
  s += rect(-200, 740, W + 400, 26, '#7A5536');
  // окна
  for (let i = 0; i < 3; i++) {
    const x = -60 + i * 700, cid = uid('win');
    s += `<clipPath id="${cid}"><rect x="${x}" y="140" width="520" height="520"/></clipPath>`;
    s += g(g(sky('day', t) + dome(500, 760, 520, 420, {}) + minaret(1000, 1000, 80, 760) + chinar(140, 1080, 200, t, { autumn: true }) + rect(-200, 1000, 2400, 200, '#C9A97E'), `translate(${x} 140) scale(.48)`), '', `clip-path="url(#${cid})"`);
    s += rect(x, 140, 520, 520, 'none', 'stroke="#C9AE86" stroke-width="12"');
    s += path(`M${x + 260} 140V660M${x} 400H${x + 520}`, 'none', 'stroke="#C9AE86" stroke-width="10"');
  }
  // лучи солнца
  s += g(poly([[300, 140], [820, 140], [1500, 1200], [700, 1200]], '#FFF2C8', 'opacity=".22"') + poly([[1000, 140], [1520, 140], [2200, 1200], [1400, 1200]], '#FFF2C8', 'opacity=".18"'), '', 'filter="url(#blur16)"');
  return s;
}

/* двор у арыка: кирпичная стена с панно, тутовник */
function courtyard(t, o = {}) {
  let s = sky('day', t);
  s += rect(-200, 330, W + 400, 520, 'url(#pBrickWall)');
  s += rect(-200, 330, W + 400, 30, 'url(#pGirih)');
  s += rect(640, 400, 640, 300, 'url(#pMaj)', `stroke="${PAL.gold}" stroke-width="8"`);
  s += g(path(starPath(110, 46, 8), PAL.cobalt, `stroke="${PAL.gold}" stroke-width="6"`) + path(starPath(60, 26, 8), PAL.tq), 'translate(960 550)');
  s += rect(-200, 850, W + 400, 400, '#CDB58E');
  // арык
  s += path('M-200 930C400 910 1200 950 2120 920L2120 990C1200 1020 400 980 -200 1000Z', '#4AA3B8');
  const sh = (t * 120) % 200;
  let wav = '';
  for (let i = -2; i < 14; i++) wav += `M${i * 200 + sh} 955q30 -8 60 0`;
  s += path(wav, 'none', 'stroke="#BFF0F8" stroke-width="3" opacity=".7"');
  s += chinar(1700, 870, 150, t, { autumn: true }) + chinar(160, 880, 120, t, { autumn: false });
  return s;
}

/* ---------- руины обсерватории Улугбека ---------- */
function observatory(t, o = {}) {
  const glow = o.glow || 0;
  let s = sky(o.dusk ? 'dusk' : 'night', t);
  // Млечный путь
  if (!o.dusk) s += g(path('M-200 700C300 400 900 200 2200 -100L2200 100C1000 360 400 560 -200 900Z', '#9AA8FF', 'opacity=".16"'), '', 'filter="url(#blur30)"') + g(starfield(55, 220, { t, h: H * .6 }), '', 'opacity=".9"');
  // холмы и огни города
  s += path('M-200 740C300 690 700 720 1100 700C1500 680 1800 720 2120 700L2120 1200L-200 1200Z', '#141A30');
  const r = rng(3);
  for (let i = 0; i < 90; i++) s += circle(r() * W, 712 + r() * 30, 1.5 + r() * 2, r() > .3 ? '#FFD27A' : '#9FD8FF', `opacity="${f2(.5 + r() * .5)}"`);
  s += path('M-200 820C400 780 1300 800 2120 790L2120 1200L-200 1200Z', '#1E2238');
  // секстант: мраморная дуга, уходящая под землю
  const gc = glow > 0 ? `rgba(127,243,232,${f2(.35 + glow * .65)})` : '#B8BCC8';
  s += path('M560 1200C620 1000 760 860 960 820C1160 860 1300 1000 1360 1200Z', '#2A2E46', 'stroke="#0E1020" stroke-width="3"');
  s += path('M640 1200C690 1030 800 910 960 880C1120 910 1230 1030 1280 1200Z', '#0E1226');
  s += path('M700 1200C744 1050 840 950 960 925M1220 1200C1176 1050 1080 950 960 925', 'none', `stroke="${gc}" stroke-width="${glow > 0 ? 10 : 6}" ${glow > 0 ? 'filter="url(#glow)"' : ''}`);
  let ticks = '';
  for (let i = 0; i < 18; i++) { const u = i / 17, a = lerp(Math.PI * .98, Math.PI * .52, u); ticks += `M${f2(960 + Math.cos(a) * 300)} ${f2(1220 - Math.sin(a) * 300)}l${f2(Math.cos(a) * 18)} ${f2(-Math.sin(a) * 18)}`; }
  s += path(ticks, 'none', `stroke="${gc}" stroke-width="3"`);
  // руины стен
  s += path('M200 820L200 700L240 690L260 720L300 700L320 830Z', '#2A2E46') + path('M1560 830L1580 680L1640 700L1660 670L1700 700L1720 840Z', '#2A2E46');
  if (glow > 0) s += g(circle(960, 925, 160 + glow * 220, '#7FF3E8', `opacity="${f2(.15 * glow)}"`), '', 'filter="url(#blur60)"');
  return s;
}

/* ---------- Сиабский базар ---------- */
function bazaar(t, o = {}) {
  let s = rect(-200, -200, W + 400, H + 400, '#3A1418');
  // свод крытого базара (бирюзовые арки)
  for (let i = 0; i < 5; i++) {
    const x = -100 + i * 520;
    s += path(`M${x} 700V300Q${x + 260} 60 ${x + 520} 300V700`, 'none', `stroke="${PAL.tq}" stroke-width="40"`);
    s += path(`M${x} 700V300Q${x + 260} 60 ${x + 520} 300V700`, 'none', `stroke="${PAL.tqDk}" stroke-width="8"`);
  }
  // прилавки: дыни, лепёшки-нон, специи
  s += rect(-200, 700, W + 400, 500, '#4A2A20');
  for (let i = 0; i < 7; i++) {
    const x = -40 + i * 300;
    s += rect(x, 640, 240, 90, '#7A4A2A', 'stroke="#2A140C" stroke-width="3"');
    if (i % 3 === 0) for (let k = 0; k < 4; k++) s += ell(x + 40 + k * 52, 630, 26, 18, '#E8C860', 'stroke="#8A6A10" stroke-width="2"') + path(`M${x + 20 + k * 52} 630q20 -8 40 0`, 'none', 'stroke="#A88A20" stroke-width="2"');
    if (i % 3 === 1) for (let k = 0; k < 3; k++) s += circle(x + 50 + k * 70, 628, 30, '#D89A4A', 'stroke="#7A4A1A" stroke-width="2"') + circle(x + 50 + k * 70, 628, 14, '#E8B870') + path(`M${x + 40 + k * 70} 620l20 16M${x + 60 + k * 70} 620l-20 16`, 'none', 'stroke="#9A6A2A" stroke-width="2"');
    if (i % 3 === 2) for (let k = 0; k < 4; k++) s += path(`M${x + 20 + k * 56} 640l22 -40l22 40Z`, ['#E84A2A', '#F2C14E', '#8A3A1A', '#4AAA4A'][k]);
  }
  return s;
}

/* ---------- крыши со сценой бега ---------- */
function rooftops(t, scroll) {
  let s = '';
  const x0 = -((scroll || 0) % 1600);
  for (let k = 0; k < 3; k++) {
    const bx = x0 + k * 1600;
    s += rect(bx - 20, 820, 640, 400, '#2A1A26') + dome(bx + 300, 820, 360, 260, {});
    s += rect(bx + 700, 760, 520, 500, '#2A1A26') + rect(bx + 700, 760, 520, 20, 'url(#pGirih)');
    s += minaret(bx + 1360, 1100, 70, 600, {});
  }
  return s;
}
