/* ЮЛДУЗ — персонажи. Японская аниме-рисовка: крупные глаза с бликами, острый подбородок,
   «целл»-тени, пряди с острыми кончиками. Узбекские детали: хан-атлас, икат, доппи, чапан.
   Голова в локальных координатах: центр лица (0,0), ширина ~180, подбородок y≈130, плечи y≈200. */
'use strict';

const SKIN = { base: '#F7D9C6', sh: '#E6AF97', sh2: '#D49680', line: '#5A3030', blush: '#FF8C8C' };
const SKIN_TAN = { base: '#EDC3A2', sh: '#D69D7D', sh2: '#C08466', line: '#4A2820', blush: '#F08070' };
const INK = '#1E1418';

/* ---------- лицо ---------- */
function faceKit(o) {
  const turn = o.turn || 0, fem = o.sex === 'f', big = o.sex === 'big';
  const X = x => x + turn * 24 * (1 - Math.min(1, (x / 105) ** 2));
  const sk = o.skin || SKIN;
  const chin = fem ? 124 : big ? 136 : 132, jawW = big ? 1.12 : 1;
  const jx = x => X(x * jawW);
  const face = fem
    ? `M${X(-88)} -60C${X(-90)} 0 ${X(-86)} 42 ${X(-70)} 74C${X(-52)} 102 ${X(-22)} 118 ${X(0)} ${chin}C${X(22)} 118 ${X(52)} 102 ${X(70)} 74C${X(86)} 42 ${X(90)} 0 ${X(88)} -60C${X(86)} -128 ${X(46)} -156 ${X(0)} -156C${X(-46)} -156 ${X(-86)} -128 ${X(-88)} -60Z`
    : `M${jx(-90)} -60C${jx(-92)} 0 ${jx(-88)} 40 ${jx(-72)} 72C${jx(-56)} 100 ${X(-24)} 124 ${X(0)} ${chin}C${X(24)} 124 ${jx(56)} 100 ${jx(72)} 72C${jx(88)} 40 ${jx(92)} 0 ${jx(90)} -60C${jx(88)} -130 ${X(48)} -158 ${X(0)} -158C${X(-48)} -158 ${jx(-88)} -130 ${jx(-90)} -60Z`;
  return { X, face, chin, sk, fem, turn };
}

function neckOnly(k) {
  const { X, sk } = k;
  return path(`M${X(-27)} 80L-30 190Q0 200 30 190L${X(27)} 80Z`, sk.base) + path(`M-30 92L30 92L30 150Q0 170 -30 150Z`, sk.sh);
}
function neckAndFace(o, k) {
  const { X, face, sk } = k;
  let s = '';
  // шея — рисуется до тела (neckOnly)
  // уши
  const earL = `M${X(-86)} -6C${X(-104)} -14 ${X(-110)} 20 ${X(-96)} 40C${X(-92)} 46 ${X(-86)} 44 ${X(-82)} 36Z`;
  const earR = `M${X(86)} -6C${X(104)} -14 ${X(110)} 20 ${X(96)} 40C${X(92)} 46 ${X(86)} 44 ${X(82)} 36Z`;
  if (k.turn < 0.45) s += path(earR, sk.base, `stroke="${sk.line}" stroke-width="1.6"`) + strokeP(`M${X(96)} 4Q${X(100)} 18 ${X(92)} 30`, sk.sh2, 2);
  if (k.turn > -0.45) s += path(earL, sk.base, `stroke="${sk.line}" stroke-width="1.6"`) + strokeP(`M${X(-96)} 4Q${X(-100)} 18 ${X(-92)} 30`, sk.sh2, 2);
  // лицо
  s += path(face, sk.base, `stroke="${sk.line}" stroke-width="2.2"`);
  // тень на щеке (свет слева сверху)
  const sh = k.fem
    ? `M${X(88)} -60C${X(90)} 0 ${X(86)} 42 ${X(70)} 74C${X(52)} 102 ${X(22)} 118 ${X(0)} ${k.chin}C${X(30)} 108 ${X(56)} 84 ${X(66)} 46C${X(74)} 10 ${X(76)} -30 ${X(74)} -60Z`
    : `M${X(90)} -60C${X(92)} 0 ${X(88)} 40 ${X(72)} 72C${X(56)} 100 ${X(24)} 124 ${X(0)} ${k.chin}C${X(32)} 112 ${X(58)} 84 ${X(68)} 46C${X(76)} 10 ${X(78)} -30 ${X(76)} -60Z`;
  s += path(sh, sk.sh, 'opacity=".55"');
  return s;
}

/* бровь: тонкий клин */
function brow(cx, cy, side, mood, col, fem, lift = 0) {
  let ix = cx - side * 22, iy = cy - 30, ox = cx + side * 26, oy = cy - 30, mx = cx + side * 2, my = cy - 40;
  if (fem) { iy += 2; oy += 4; my += 1; }
  if (mood === 'angry') { iy += 12; ix += side * 4; my += 2; oy -= 4; }
  if (mood === 'sad') { iy -= 8; oy += 6; my -= 2; }
  if (mood === 'surprised') { iy -= 12; oy -= 10; my -= 14; }
  if (mood === 'determined') { iy += 7; oy -= 2; }
  iy -= lift; oy -= lift; my -= lift;
  const N = 10, top = [], bot = [];
  for (let i = 0; i <= N; i++) {
    const u = i / N;
    const x = (1 - u) * (1 - u) * ix + 2 * (1 - u) * u * mx + u * u * ox;
    const y = (1 - u) * (1 - u) * iy + 2 * (1 - u) * u * my + u * u * oy;
    const w = lerp(fem ? 3.2 : 4.6, 0.8, u);
    top.push([x, y - w]); bot.push([x, y + w * .6]);
  }
  return poly(top.concat(bot.reverse()), col);
}

/* глаз */
function eye(cx, cy, side, o) {
  const fem = o.sex === 'f', mean = o.mean;
  const open = clamp(1 - (o.blink || 0)) * (o.eyeOpen == null ? 1 : o.eyeOpen);
  const wide = o.eyes === 'wide' ? 1 : 0;
  const ix = cx - side * (fem ? 22 : 22), ox = cx + side * (fem ? 30 : 27);
  const hUp = (fem ? 28 : mean ? 12 : 23) + wide * 7, hDn = (fem ? 19 : mean ? 10 : 15) + wide * 4;
  const lid = lerp(cy + 6, cy - hUp, open);
  const inkW = fem ? 6.5 : 5.4;
  const lc = o.lineCol || INK;
  if (o.eyes === 'smile') {
    return strokeP(`M${f2(ox)} ${f2(cy + 8)}Q${f2(cx)} ${f2(cy - 14)} ${f2(ix)} ${f2(cy + 6)}`, lc, inkW);
  }
  if (open < 0.14) {
    return strokeP(`M${f2(ox)} ${f2(cy + 4)}Q${f2(cx)} ${f2(cy + 12)} ${f2(ix)} ${f2(cy + 4)}`, lc, inkW - 1) +
      (fem ? strokeP(`M${f2(ox)} ${f2(cy + 4)}l${f2(side * 9)} -4`, lc, 3) : '');
  }
  const up = `M${f2(ox)} ${f2(cy + 2)}C${f2(cx + side * 16)} ${f2(lid - 2)} ${f2(cx - side * 10)} ${f2(lid + 2)} ${f2(ix)} ${f2(cy + 3)}`;
  const shape = up + `C${f2(cx - side * 8)} ${f2(cy + hDn)} ${f2(cx + side * 14)} ${f2(cy + hDn + 1)} ${f2(ox)} ${f2(cy + 4)}Z`;
  const id = uid('eye');
  const lx = (o.look ? o.look[0] : 0) * 9, ly = (o.look ? o.look[1] : 0) * 6;
  const icx = cx + lx + side * 1, icy = cy + 1 + ly + (fem ? 1 : 0);
  const rx = (fem ? 17.5 : mean ? 10 : 15.5) * (wide ? .78 : 1), ry = (fem ? 23 : mean ? 12 : 20.5) * (wide ? .78 : 1);
  const gid = uid('ir');
  const glow = o.eyes === 'glow';
  const irT = glow ? '#FFF6C8' : (o.iris || ['#2B1A14', '#8A5530'])[0], irB = glow ? (o.glowCol || '#FFC93C') : (o.iris || ['#2B1A14', '#8A5530'])[1];
  let s = `<clipPath id="${id}"><path d="${shape}"/></clipPath>`;
  s += lg(gid, [[0, irT], [0.55, glow ? irB : lerpCol(irT, irB, .45)], [1, irB]]);
  s += path(shape, glow ? '#FFFBEA' : '#FFFFFF');
  let inner = '';
  inner += path(up + `L${f2(ix)} ${f2(cy + 10)}L${f2(ox)} ${f2(cy + 10)}Z`, glow ? 'rgba(255,220,120,.25)' : 'rgba(120,130,170,.28)', `transform="translate(0 4)"`);
  inner += ell(icx, icy, rx, ry, `url(#${gid})`, `stroke="${glow ? '#B86A00' : '#1A0E0C'}" stroke-width="1.6"`);
  if (!glow) {
    inner += ell(icx, icy - ry * .05, rx * .46, ry * .5, '#120A08');
    inner += path(`M${f2(icx - rx)} ${f2(icy - ry * .2)}Q${f2(icx)} ${f2(icy - ry * 1.15)} ${f2(icx + rx)} ${f2(icy - ry * .2)}Z`, 'rgba(0,0,0,.35)');
    inner += ell(icx, icy + ry * .55, rx * .6, ry * .25, 'rgba(255,220,180,.35)');
  } else {
    inner += path(starPath(ry * .55, ry * .18, 4), '#FFFFFF', `transform="translate(${f2(icx)} ${f2(icy)})"`);
  }
  inner += circle(icx - rx * .38, icy - ry * .38, fem ? 6 : 4.4, '#FFFFFF');
  inner += circle(icx + rx * .42, icy + ry * .42, fem ? 2.8 : 2, '#FFFFFF', 'opacity=".9"');
  if (fem) inner += circle(icx + rx * .1, icy - ry * .55, 1.6, '#FFFFFF');
  s += g(inner, '', `clip-path="url(#${id})"`);
  // веко и ресницы
  s += path(up, 'none', `stroke="${lc}" stroke-width="${inkW}" stroke-linecap="round"`);
  s += path(`M${f2(ox)} ${f2(cy + 2)}l${f2(side * (fem ? 11 : 7))} ${f2(fem ? -9 : -5)}l${f2(-side * 6)} ${f2(fem ? 2 : 1)}Z`, lc);
  if (fem) {
    // густые ресницы: утолщение внешней трети века
    s += path(`M${f2(ox)} ${f2(cy + 2)}C${f2(cx + side * 22)} ${f2(lid + 4)} ${f2(cx + side * 10)} ${f2(lid - 1)} ${f2(cx + side * 2)} ${f2(lid - 2)}L${f2(cx + side * 6)} ${f2(lid - 6)}C${f2(cx + side * 16)} ${f2(lid - 6)} ${f2(cx + side * 26)} ${f2(lid - 2)} ${f2(ox + side * 4)} ${f2(cy - 2)}Z`, lc);
  }
  // складка века
  s += strokeP(`M${f2(cx + side * 22)} ${f2(lid - 4)}Q${f2(cx)} ${f2(lid - 10)} ${f2(cx - side * 12)} ${f2(lid - 4)}`, o.skin ? o.skin.sh2 : SKIN.sh2, 1.6, 'opacity=".8"');
  // нижнее веко
  s += strokeP(`M${f2(ox)} ${f2(cy + 5)}C${f2(cx + side * 14)} ${f2(cy + hDn + 1)} ${f2(cx)} ${f2(cy + hDn + 1)} ${f2(cx - side * 6)} ${f2(cy + hDn - 1)}`, o.skin ? o.skin.line : '#6A3A38', 1.5, 'opacity=".7"');
  if (glow) s = g(s, '', 'filter="url(#glow)"');
  return s;
}
function lerpCol(a, b, k) {
  const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
  const r = Math.round(lerp(pa >> 16, pb >> 16, k)), gg = Math.round(lerp(pa >> 8 & 255, pb >> 8 & 255, k)), bb = Math.round(lerp(pa & 255, pb & 255, k));
  return '#' + ((1 << 24) + (r << 16) + (gg << 8) + bb).toString(16).slice(1);
}

/* рот: m — раскрытие по огибающей голоса */
function mouth(k, o) {
  const X = k.X, y = k.fem ? 92 : 96, lc = (o.skin || SKIN).line;
  const m = clamp(o.mouth || 0), shape = o.mouthShape || 'neutral';
  if (shape === 'shout') {
    const w = 30, h = 34;
    return path(`M${X(-w)} ${y - 8}L${X(w)} ${y - 8}L${X(w * .7)} ${y + h - 6}Q${X(0)} ${y + h + 4} ${X(-w * .7)} ${y + h - 6}Z`, '#5A1420', `stroke="${lc}" stroke-width="2.4"`) +
      path(`M${X(-w + 3)} ${y - 7}L${X(w - 3)} ${y - 7}L${X(w - 6)} ${y - 1}L${X(-w + 6)} ${y - 1}Z`, '#fff') +
      ell(X(0), y + h - 6, 14, 6, '#D0606A');
  }
  if (m < 0.08) {
    if (shape === 'smile') return strokeP(`M${X(-17)} ${y - 4}Q${X(0)} ${y + 8} ${X(17)} ${y - 4}`, lc, 2.4);
    if (shape === 'frown') return strokeP(`M${X(-13)} ${y + 3}Q${X(0)} ${y - 4} ${X(13)} ${y + 3}`, lc, 2.4);
    if (shape === 'smirk') return strokeP(`M${X(-14)} ${y + 2}Q${X(4)} ${y + 3} ${X(18)} ${y - 6}`, lc, 2.6);
    if (shape === 'o') return ell(X(0), y + 2, 6, 7, '#6B1E28', `stroke="${lc}" stroke-width="2"`);
    if (shape === 'grit') return path(`M${X(-18)} ${y - 4}L${X(18)} ${y - 4}L${X(15)} ${y + 6}L${X(-15)} ${y + 6}Z`, '#fff', `stroke="${lc}" stroke-width="2.2"`) + strokeP(`M${X(-16)} ${y + 1}L${X(16)} ${y + 1}`, lc, 1.2);
    return strokeP(`M${X(-11)} ${y}Q${X(0)} ${y + 2} ${X(11)} ${y - 1}`, lc, 2.2);
  }
  const sm = shape === 'smile' || shape === 'laugh';
  const w = (sm ? 16 : 10) + 5 * m, h = 3 + (sm ? 17 : 14) * m;
  const top = sm ? y - 4 : y - 1;
  let s = path(`M${X(-w)} ${top}Q${X(0)} ${top - (sm ? -3 : 3)} ${X(w)} ${top}Q${X(0)} ${top + h * 2.1} ${X(-w)} ${top}Z`, '#6B1E28', `stroke="${lc}" stroke-width="2"`);
  s += ell(X(0), top + h * 1.05, w * .5, h * .38, '#E0707A');
  if (m > .45 || sm) s += path(`M${X(-w * .82)} ${top + .5}Q${X(0)} ${top + (sm ? 2.5 : -1.5)} ${X(w * .82)} ${top + .5}L${X(w * .7)} ${top + 3.5}Q${X(0)} ${top + 5} ${X(-w * .7)} ${top + 3.5}Z`, '#FFFFFF');
  return s;
}

function faceFeatures(o, k) {
  const X = k.X, fem = k.fem;
  const cy = fem ? 22 : 24, ex = fem ? 46 : 43;
  const sk = o.skin || SKIN;
  let s = '';
  // румянец
  if (o.blush) {
    const b = o.blush;
    s += g(ell(X(-56), 62, 22, 8, sk.blush) + ell(X(56), 62, 22, 8, sk.blush), '', `opacity="${f2(.55 * b)}" filter="url(#blur2)"`);
    for (const sx of [-1, 1]) for (let i = 0; i < 3; i++) s += strokeP(`M${X(sx * 56 - 12 + i * 9)} 68l7 -12`, '#E2506A', 1.6, `opacity="${f2(.8 * b)}"`);
  }
  // глаза
  s += eye(X(-ex), cy, -1, Object.assign({}, o, { skin: sk }));
  s += eye(X(ex), cy, 1, Object.assign({}, o, { skin: sk }));
  // брови
  const bc = o.browCol || '#24161A';
  s += brow(X(-ex), cy, -1, o.brows, bc, fem, o.browLift || 0) + brow(X(ex), cy, 1, o.brows, bc, fem, o.browLift || 0);
  if (o.scar) s += strokeP(`M${X(-56)} ${cy - 50}l18 30`, '#B86A5A', 3) + strokeP(`M${X(-52)} ${cy - 44}l8 -3M${X(-46)} ${cy - 34}l8 -3`, '#B86A5A', 1.6);
  // нос
  s += fem ? strokeP(`M${X(4)} 62Q${X(7)} 67 ${X(2)} 69`, sk.sh2, 2)
    : strokeP(`M${X(6)} 54Q${X(11)} 66 ${X(2)} 70`, sk.sh2, 2.2) + path(`M${X(2)} 70L${X(10)} 66L${X(8)} 71Z`, sk.sh, 'opacity=".8"');
  // рот
  if (!o.mask) s += mouth(k, o);
  // пот
  if (o.sweat) s += g(path('M0 -14C6 -4 10 4 10 9C10 15 5 19 0 19C-5 19 -10 15 -10 9C-10 4 -6 -4 0 -14Z', '#BFE8FF', 'stroke="#4A90C0" stroke-width="2"') + ell(-3, 8, 2.5, 4, '#fff'), `translate(${X(96)} -46) scale(${f2(o.sweat)})`);
  // слёзы
  if (o.tear) s += path(`M${X(-ex + 6)} ${cy + 18}Q${X(-ex + 10)} ${cy + 40} ${X(-ex + 4)} ${cy + 58}`, 'none', `stroke="#CFF0FF" stroke-width="4" opacity="${f2(o.tear)}"`);
  return s;
}

/* ---------- волосы ---------- */
/* блик-«кольцо ангела»: дуга с рваным нижним краем */
function hairShine(X, y0, curve, col, seed) {
  const r = rng(seed);
  const top = [], bot = [];
  for (let x = -116; x <= 116; x += 8) {
    const yb = y0 + (x / 116) ** 2 * curve;
    top.push([X(x), yb - 6 - 4 * (1 - (x / 116) ** 2)]);
    const deep = (Math.round((x + 116) / 8) % 3 === 0) ? 14 + r() * 16 : 4 + r() * 6;
    bot.push([X(x), yb + deep]);
  }
  let s = poly(top.concat(bot.reverse()), col, 'opacity=".75"');
  s += strokeP(`M${X(-70)} ${y0 + 4}Q${X(-30)} ${y0 - 6} ${X(10)} ${y0 - 4}`, '#FFFFFF', 2.4, 'opacity=".35"');
  return s;
}
function jasurHair(o, X) {
  const t = o.t || 0, wind = o.wind || 0, lift = o.hairLift || 0;
  const sw = (i, a = 1) => wind * a * (Math.sin(t * 7 + i * 1.7) * 6 + 6);
  const up = (y, i) => y - lift * (40 + 18 * Math.sin(t * 10 + i));
  const col = o.hairCol || '#1D2034', hi = o.hairHi || '#43507F', shc = o.hairSh || '#0E0F1C';
  const back = [[-96, 70, 't'], [-110, 10, 'v'], [-140 - sw(1), up(-22, 1), 't'], [-122, -70, 'v'], [-152 - sw(2), up(-122, 2), 't'], [-108, -140, 'v'],
    [-112 - sw(3, .5), up(-200, 3), 't'], [-60, -180, 'v'], [-28, up(-226, 4), 't'], [0, -192, 'v'], [54 + sw(5, .5), up(-222, 5), 't'], [64, -182, 'v'],
    [126 + sw(6), up(-184, 6), 't'], [112, -136, 'v'], [158 + sw(7), up(-112, 7), 't'], [124, -74, 'v'], [148 + sw(8), up(-20, 8), 't'], [112, 8, 'v'], [100, 70, 't']];
  const backD = spikyPath(back.map(p => [X(p[0]), p[1], p[2]])) + `L${X(60)} 40L${X(-60)} 40Z`;
  const fr = [[-120, -84, 'v'], [-106 - sw(9, .4), up(54, 9) + lift * 20, 't'], [-86, -30, 'v'], [-76, up(14, 10), 't'], [-60, -54, 'v'], [-44, up(8, 11), 't'], [-28, -52, 'v'],
    [-8, up(24, 12), 't'], [8, -58, 'v'], [26, up(4, 13), 't'], [40, -58, 'v'], [58, up(14, 14), 't'], [70, -50, 'v'], [86, up(-14, 15), 't'], [96, -62, 'v'],
    [108 + sw(16, .4), up(52, 16) + lift * 20, 't'], [122, -84, 'v']];
  const frD = spikyPath(fr.map(p => [X(p[0]), p[1], p[2]])) + `C${X(128)} -150 ${X(64)} -198 ${X(0)} -200C${X(-64)} -198 ${X(-128)} -150 ${X(-120)} -84Z`;
  const cid = uid('hc');
  let front = `<clipPath id="${cid}"><path d="${frD}"/></clipPath>`;
  front += path(frD, col, `stroke="${INK}" stroke-width="2.4" stroke-linejoin="round"`);
  // пряди-штрихи и тени у корней
  let inner = '';
  for (const p of fr) if (p[2] === 't') inner += strokeP(`M${X(p[0] * .5)} -150Q${X(p[0] * .8)} ${(p[1] - 150) / 2} ${X(p[0])} ${p[1] - 10}`, shc, 3, 'opacity=".8"');
  // блик-кольцо
  inner += hairShine(X, -138, 30, hi, 7);
  front += g(inner, '', `clip-path="url(#${cid})"`);
  // ахоге
  const ah = Math.sin(t * 5) * 4 * (1 + wind);
  front += path(`M${X(2)} -196C${X(8 + ah)} -238 ${X(40 + ah)} -252 ${X(54 + ah)} -228C${X(40 + ah)} -240 ${X(22)} -228 ${X(16)} -196Z`, col, `stroke="${INK}" stroke-width="2"`);
  // тень чёлки на лбу
  const shadow = spikyPath(fr.map(p => [X(p[0]) + 4, p[1] + 14, p[2]])) + `L${X(122)} -160L${X(-120)} -160Z`;
  return { back: path(backD, col, `stroke="${INK}" stroke-width="2.4" stroke-linejoin="round"`), front, shadow };
}

function nilufarHair(o, X) {
  const t = o.t || 0, wind = o.wind || 0;
  const sw = (i, a = 1) => wind * a * (Math.sin(t * 3 + i * 1.3) * 12 + 10);
  const col = '#2B1B22', hi = '#7A4A5C', shc = '#160C12';
  // длинные волосы за спиной
  const back = smoothPath([[X(-128), -110], [X(-70), -190], [X(30), -196], [X(124), -146], [X(146) + sw(1, .3), -20], [140 + sw(2), 160], [150 + sw(3, 1.4), 420],
    [120 + sw(4, 1.6), 600], [-120 + sw(5, 1.6), 600], [-150 + sw(6, 1.4), 420], [-150 + sw(7), 160], [X(-146) + sw(8, .3), -20]]);
  // чёлка: мягкие кончики, косой пробор
  const fr = [[-124, -80, 'v'], [-112, 40, 't'], [-96, -24, 'v'], [-82, 6, 't'], [-66, -50, 'v'], [-42, 14, 't'], [-30, -60, 'v'], [-6, 6, 't'],
    [10, -66, 'v'], [32, 10, 't'], [46, -60, 'v'], [66, 2, 't'], [80, -44, 'v'], [100, 30, 't'], [124, -80, 'v']];
  const frD = spikyPath(fr.map(p => [X(p[0]), p[1], p[2]])) + `C${X(130)} -150 ${X(60)} -196 ${X(-10)} -196C${X(-70)} -192 ${X(-130)} -150 ${X(-124)} -80Z`;
  const cid = uid('hc');
  let front = `<clipPath id="${cid}"><path d="${frD}"/></clipPath>`;
  front += path(frD, col, `stroke="${INK}" stroke-width="2.2"`);
  let inner = '';
  for (const p of fr) if (p[2] === 't') inner += strokeP(`M${X(p[0] * .4)} -160Q${X(p[0] * .9)} ${(p[1] - 150) / 2} ${X(p[0])} ${p[1] - 8}`, shc, 2.6, 'opacity=".7"');
  inner += hairShine(X, -134, 28, hi, 5);
  front += g(inner, '', `clip-path="url(#${cid})"`);
  // боковые пряди до груди
  const sideL = `M${X(-118)} -60C${X(-132)} 40 ${-128 + sw(9, .5)} 160 ${-112 + sw(9, .8)} 270C${-100 + sw(9, .8)} 230 ${X(-100)} 120 ${X(-96)} -20Z`;
  const sideR = `M${X(118)} -60C${X(132)} 40 ${128 + sw(10, .5)} 160 ${112 + sw(10, .8)} 270C${100 + sw(10, .8)} 230 ${X(100)} 120 ${X(96)} -20Z`;
  front += path(sideL, col, `stroke="${INK}" stroke-width="2"`) + path(sideR, col, `stroke="${INK}" stroke-width="2"`);
  // тонкие косички-кокиль
  for (const sx of [-1, 1]) {
    let bd = '';
    for (let i = 0; i < 14; i++) {
      const u = i / 13, bx = X(sx * 92) + sx * 8 * Math.sin(u * 3) + sw(11 + sx, .5) * u, by = 10 + u * 250;
      const rot = i % 2 ? 28 : -28, sz = 1 - u * .3;
      bd += g(path('M0 -16C7 -10 8 6 0 16C-8 6 -7 -10 0 -16Z', col, `stroke="${INK}" stroke-width="1.5"`) + strokeP('M-2 -8Q1 0 -1 8', hi, 1.6, 'opacity=".8"'),
        `translate(${f2(bx)} ${f2(by)}) rotate(${rot}) scale(${f2(sz)})`);
    }
    const ex = X(sx * 92) + sx * 8 * Math.sin(3) + sw(11 + sx, .5), ey = 262;
    bd += g(path(starPath(10, 4.5, 8), '#E9B44C', `stroke="#8A5A10" stroke-width="1.2"`) + circle(0, 0, 3, '#2FB6C0'), `translate(${f2(ex)} ${f2(ey)})`);
    front += bd;
  }
  // заколка-розетка
  const cl = g(path(starPath(22, 12, 8), '#F2C25A', 'stroke="#8A5A10" stroke-width="1.6"') + circle(0, 0, 9, '#2FB6C0', 'stroke="#0E6A70" stroke-width="1.5"') + circle(-3, -3, 3, '#BFF6F2') +
    path(starPath(14, 7, 8), 'none', 'stroke="#FFF1C4" stroke-width="1" opacity=".7"'), `translate(${X(78)} -118) rotate(${f2(10 + t * 2)})`);
  front += cl;
  const shadow = spikyPath(fr.map(p => [X(p[0]) + 4, p[1] + 12, p[2]])) + `L${X(124)} -160L${X(-124)} -160Z`;
  return { back: path(back, col, `stroke="${INK}" stroke-width="2.2"`) + path(back, 'none', `stroke="${hi}" stroke-width="3" opacity=".15"`), front, shadow };
}

function bahodirHair(o, X) {
  const col = '#151316', hi = '#4A4652';
  // фейд по бокам + объёмный чуб сверху
  const fade = `M${X(-100)} -10C${X(-108)} -80 ${X(-100)} -130 ${X(-60)} -150L${X(60)} -150C${X(100)} -130 ${X(108)} -80 ${X(100)} -10L${X(90)} -12C${X(92)} -60 ${X(86)} -86 ${X(70)} -98Q${X(0)} -104 ${X(-70)} -98C${X(-86)} -86 ${X(-92)} -60 ${X(-90)} -12Z`;
  let front = path(fade, '#3A363E', `stroke="${INK}" stroke-width="2"`);
  front += path(fade, 'url(#fadeGrad)');
  const top = [[-96, -96, 'v'], [-118, -140, 't'], [-80, -146, 'v'], [-92, -200, 't'], [-44, -178, 'v'], [-26, -226, 't'], [6, -186, 'v'],
    [40, -224, 't'], [58, -182, 'v'], [100, -200, 't'], [92, -148, 'v'], [124, -132, 't'], [96, -96, 'v']];
  const d = spikyPath(top.map(p => [X(p[0]), p[1], p[2]])) + `Q${X(40)} -110 ${X(0)} -92Q${X(-40)} -110 ${X(-96)} -96Z`;
  front += path(d, col, `stroke="${INK}" stroke-width="2.4"`);
  front += path(`M${X(-70)} -170Q${X(0)} -196 ${X(76)} -172L${X(66)} -158Q${X(0)} -178 ${X(-60)} -156Z`, hi, 'opacity=".8"');
  front += strokeP(`M${X(-40)} -120L${X(-60)} -180M${X(10)} -110L${X(0)} -180M${X(50)} -116L${X(60)} -176`, '#000', 2.4, 'opacity=".6"');
  return { back: '', front, shadow: `M${X(-104)} -90Q${X(0)} -80 ${X(104)} -90L${X(104)} -160L${X(-104)} -160Z` };
}

function sardorHair(o, X) {
  // кепка козырьком назад
  let front = path(`M${X(-104)} -50C${X(-110)} -150 ${X(-50)} -196 ${X(10)} -196C${X(80)} -196 ${X(112)} -140 ${X(106)} -50Q${X(0)} -84 ${X(-104)} -50Z`, '#2E7D6E', `stroke="${INK}" stroke-width="2.4"`);
  front += path(`M${X(-104)} -50Q${X(0)} -84 ${X(106)} -50L${X(108)} -36Q${X(0)} -70 ${X(-106)} -36Z`, '#1E5A4E', `stroke="${INK}" stroke-width="2"`);
  front += circle(X(0), -190, 6, '#1E5A4E');
  front += strokeP(`M${X(-80)} -40L${X(-74)} -16M${X(-62)} -40L${X(-56)} -12M${X(-46)} -40L${X(-42)} -20`, '#3a2a20', 4);
  front += strokeP(`M${X(-60)} -150Q${X(0)} -176 ${X(60)} -150`, '#5FC4B0', 3, 'opacity=".6"');
  return { back: path(`M${X(80)} -150L${X(170)} -136L${X(160)} -118L${X(96)} -110Z`, '#1E5A4E', `stroke="${INK}" stroke-width="2"`), front, shadow: `M${X(-104)} -50Q${X(0)} -84 ${X(106)} -50L${X(106)} -28Q${X(0)} -60 ${X(-104)} -28Z` };
}

/* доппи — узбекская тюбетейка (чустская: чёрная с белыми «перцами») */
function doppi(X) {
  let s = path(`M${X(-100)} -96L${X(-92)} -176Q${X(0)} -206 ${X(92)} -176L${X(100)} -96Q${X(0)} -118 ${X(-100)} -96Z`, '#121216', `stroke="${INK}" stroke-width="2.4"`);
  s += path(`M${X(-100)} -96Q${X(0)} -118 ${X(100)} -96L${X(100)} -112Q${X(0)} -134 ${X(-100)} -112Z`, '#121216', 'stroke="#ddd" stroke-width="1.4"');
  for (const x of [-60, 0, 60]) {
    s += g(path('M0 -22C12 -18 14 0 0 22C-14 0 -12 -18 0 -22Z', '#F4F1E8') + path('M0 -12C5 -8 5 4 0 12C-5 4 -5 -8 0 -12Z', '#121216'), `translate(${X(x)} -148) scale(${x ? .85 : 1}) rotate(${x * .25})`);
  }
  return s;
}

/* ---------- тела (бюст) ---------- */
function bodySchool(o) {
  const jk = o.jacket || '#262B4A', jkSh = '#161A30', jkHi = '#3A4170';
  let s = '';
  s += path('M-44 168L44 168L34 620L-34 620Z', '#EEF1F7');
  s += path('M-44 168Q0 210 44 168L40 232Q0 250 -40 232Z', '#C9CEDC', 'opacity=".8"');
  s += strokeP('M0 214L0 300', '#B8BED0', 2) + circle(0, 236, 3.5, '#DDE2EE', 'stroke="#99A" stroke-width="1"') + circle(0, 270, 3.5, '#DDE2EE', 'stroke="#99A" stroke-width="1"');
  // воротник рубашки
  s += path('M-40 160L-70 214L-20 244L-6 192Z', '#F8F9FC', `stroke="${INK}" stroke-width="2"`) + path('M40 160L70 214L20 244L6 192Z', '#F8F9FC', `stroke="${INK}" stroke-width="2"`);
  // куртка
  const L = 'M-44 166C-96 178 -156 186 -190 216C-222 248 -232 330 -236 430L-242 620L-36 620C-40 470 -50 300 -46 166Z';
  const R = 'M44 166C96 178 156 186 190 216C222 248 232 330 236 430L242 620L36 620C40 470 50 300 46 166Z';
  s += path(L, jk, `stroke="${INK}" stroke-width="2.4"`) + path(R, jk, `stroke="${INK}" stroke-width="2.4"`);
  s += path('M150 196C190 214 214 260 220 340L230 620L170 620C176 480 170 300 150 196Z', jkSh, 'opacity=".75"');
  s += path('M-150 200C-176 216 -196 250 -204 300L-180 300C-176 260 -168 230 -150 200Z', jkHi, 'opacity=".6"');
  // окантовка молнии
  s += strokeP('M-44 172C-48 300 -40 470 -38 620', '#C9CFE6', 3) + strokeP('M44 172C48 300 40 470 38 620', '#C9CFE6', 3);
  // полосы на рукавах
  s += strokeP('M-196 230C-218 280 -226 380 -232 620', '#C9CFE6', 4) + strokeP('M-184 232C-204 284 -212 380 -218 620', '#C9CFE6', 2);
  s += strokeP('M196 230C218 280 226 380 232 620', '#9EA6C8', 4) + strokeP('M184 232C204 284 212 380 218 620', '#9EA6C8', 2);
  // стойка воротника
  s += path('M-46 160C-70 156 -80 176 -68 204L-52 212C-56 192 -52 178 -40 172Z', jk, `stroke="${INK}" stroke-width="2"`);
  s += path('M46 160C70 156 80 176 68 204L52 212C56 192 52 178 40 172Z', jk, `stroke="${INK}" stroke-width="2"`);
  // нашивка школы №17 со звездой
  s += g(path(starPath(13, 6, 8), '#E9B44C') + `<text x="20" y="7" font-family="Unbounded" font-weight="700" font-size="20" fill="#E8ECF8">17</text>`, 'translate(96 290)');
  if (o.bandage) s += '';
  return s;
}

function bodyHero(o) {
  const t = o.t || 0;
  let s = '';
  // чапан: индиго с золотой вышивкой, подкладка-икат
  s += path('M-46 166L46 166L40 620L-40 620Z', 'url(#ikatPat)');
  const L = 'M-46 162C-100 172 -164 184 -198 216C-232 250 -240 334 -244 440L-250 620L-34 620C-30 470 -44 300 -48 162Z';
  const R = 'M46 162C100 172 164 184 198 216C232 250 240 334 244 440L250 620L34 620C30 470 44 300 48 162Z';
  s += path(L, '#1B2A6E', `stroke="${INK}" stroke-width="2.4"`) + path(R, '#1B2A6E', `stroke="${INK}" stroke-width="2.4"`);
  s += path('M156 196C196 214 220 264 226 344L236 620L176 620C182 480 176 300 156 196Z', '#0F1848', 'opacity=".8"');
  // золотая кайма
  for (const sx of [-1, 1]) {
    s += strokeP(`M${sx * 48} 166C${sx * 46} 300 ${sx * 34} 470 ${sx * 36} 620`, '#E9B44C', 14);
    let dots = '';
    for (let i = 0; i < 14; i++) { const u = i / 13; dots += g(path(starPath(6, 2.6, 4), '#7A3E00'), `translate(${f2(sx * lerp(47, 35, u))} ${f2(lerp(176, 610, u))})`); }
    s += dots;
  }
  // светящаяся звезда-гирих на груди
  const pulse = 0.7 + 0.3 * Math.sin(t * 6);
  s += g(path(starPath(26, 11, 8), '#FFE7A0') + path(starPath(14, 6, 8), '#FFFFFF'), `translate(-120 300) rotate(${f2(t * 30)})`, `filter="url(#glow)" opacity="${f2(pulse)}"`);
  return s;
}

/* шарф-маска из иката (закрывает нос и рот) */
function scarfMask(o, X) {
  const t = o.t || 0, wv = Math.sin(t * 8);
  let s = path(`M${X(-104)} 46C${X(-60)} 34 ${X(60)} 34 ${X(104)} 46L${X(98)} 120C${X(60)} 168 ${X(-60)} 168 ${X(-98)} 120Z`, 'url(#ikatPat)', `stroke="${INK}" stroke-width="2.4"`);
  s += path(`M${X(-104)} 46C${X(-60)} 34 ${X(60)} 34 ${X(104)} 46L${X(102)} 60C${X(60)} 50 ${X(-60)} 50 ${X(-102)} 60Z`, 'rgba(0,0,0,.25)');
  s += strokeP(`M${X(-90)} 100Q${X(0)} 118 ${X(90)} 100`, 'rgba(0,0,0,.3)', 3);
  s += path(`M${X(-98)} 120C${X(-60)} 168 ${X(60)} 168 ${X(98)} 120L${X(110)} 170C${X(60)} 214 ${X(-60)} 214 ${X(-110)} 170Z`, 'url(#ikatPat)', `stroke="${INK}" stroke-width="2.2"`);
  // хвост шарфа
  if (o.scarfTail !== false) s += path(`M${X(96)} 130C180 ${130 + wv * 10} 260 ${90 - wv * 20} 360 ${110 + wv * 30}L350 ${150 + wv * 20}C260 ${150 - wv * 10} 190 ${180 + wv * 10} ${X(104)} 170Z`, 'url(#ikatPat)', `stroke="${INK}" stroke-width="2"`);
  return s;
}

function bodyNilufar(o) {
  let s = '';
  // блузка
  s += path('M-40 166C-90 176 -150 186 -180 214C-210 244 -220 320 -224 420L-228 620L228 620L224 420C220 320 210 244 180 214C150 186 90 176 40 166Z', '#F6F4F8', `stroke="${INK}" stroke-width="2.2"`);
  s += path('M140 200C176 216 200 260 206 340L214 620L170 620C172 480 166 300 140 200Z', '#D8D4E2', 'opacity=".8"');
  // круглый воротник
  s += path('M-42 162C-80 170 -96 200 -70 222C-50 236 -20 222 0 196C20 222 50 236 70 222C96 200 80 170 42 162Q0 186 -42 162Z', '#FFFFFF', `stroke="${INK}" stroke-width="2"`);
  // жилет из хан-атласа
  const vl = 'M-150 200C-120 260 -96 330 -84 420L-74 620L-226 620L-222 420C-218 320 -200 236 -150 200Z';
  const vr = 'M150 200C120 260 96 330 84 420L74 620L226 620L222 420C218 320 200 236 150 200Z';
  s += path(vl, 'url(#atlasPat)', `stroke="${INK}" stroke-width="2.4"`) + path(vr, 'url(#atlasPat)', `stroke="${INK}" stroke-width="2.4"`);
  s += path(vr, 'rgba(40,0,60,.28)');
  s += strokeP('M-150 200C-120 260 -96 330 -84 420L-74 620', '#E9B44C', 5) + strokeP('M150 200C120 260 96 330 84 420L74 620', '#E9B44C', 5);
  // серёжки
  return s;
}

function bodyBahodir(o) {
  let s = '';
  s += path('M-50 170L50 170L44 620L-44 620Z', '#B8262E');
  s += path('M-50 170Q0 214 50 170L46 186Q0 226 -46 186Z', '#8A1A22');
  // золотая цепь
  let ch = '';
  for (let i = 0; i < 18; i++) { const u = i / 17, x = lerp(-46, 46, u), y = 190 + Math.sin(u * Math.PI) * 80; ch += ell(x, y, 5, 3.5, 'none', `stroke="#E9B44C" stroke-width="2.4" transform="rotate(${f2(lerp(50, -50, u))} ${f2(x)} ${f2(y)})"`); }
  s += ch;
  const L = 'M-50 166C-110 176 -176 188 -212 220C-246 254 -254 340 -258 446L-264 620L-44 620C-40 470 -60 300 -54 166Z';
  const R = 'M50 166C110 176 176 188 212 220C246 254 254 340 258 446L264 620L44 620C40 470 60 300 54 166Z';
  s += path(L, '#1C1A1E', `stroke="${INK}" stroke-width="2.6"`) + path(R, '#1C1A1E', `stroke="${INK}" stroke-width="2.6"`);
  s += path('M-160 204C-190 224 -210 260 -218 320L-190 320C-184 270 -176 236 -160 204Z', '#3A3740', 'opacity=".8"');
  s += path('M-54 166C-80 172 -96 196 -90 230L-60 250C-66 214 -62 186 -44 176Z', '#2A282E', `stroke="${INK}" stroke-width="2"`);
  s += path('M54 166C80 172 96 196 90 230L60 250C66 214 62 186 44 176Z', '#2A282E', `stroke="${INK}" stroke-width="2"`);
  s += strokeP('M-210 240C-232 300 -240 400 -246 620', '#C9A24A', 3) + strokeP('M210 240C232 300 240 400 246 620', '#C9A24A', 3);
  return s;
}

function bodyPlain(col) {
  return path('M-40 166C-96 176 -156 186 -190 216C-222 248 -232 330 -236 430L-242 620L242 620L236 430C232 330 222 248 190 216C156 186 96 176 40 166Z', col, `stroke="${INK}" stroke-width="2.4"`) +
    path('M-36 166Q0 196 36 166L30 180Q0 210 -30 180Z', 'rgba(0,0,0,.25)');
}

/* ---------- сборка бюста ---------- */
const SHARED_PATTERNS = () => `
<linearGradient id="fadeGrad" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#151316" stop-opacity="0"/><stop offset="1" stop-color="#EDC3A2" stop-opacity=".55"/></linearGradient>
<pattern id="ikatPat" width="60" height="80" patternUnits="userSpaceOnUse">
  <rect width="60" height="80" fill="#1E3A8A"/>
  <path d="M0 0h12v80H0z" fill="#E9B44C"/><path d="M30 0h8v80h-8z" fill="#C2185B"/>
  <path d="M6 10l10 10-10 10-10-10zM6 50l10 10-10 10-10-10z" fill="#F5F0E1"/>
  <path d="M34 30l12 10-12 10-12-10z" fill="#2FB6C0"/><path d="M48 0h4v80h-4z" fill="#F5F0E1" opacity=".7"/>
</pattern>
<pattern id="atlasPat" width="72" height="120" patternUnits="userSpaceOnUse">
  <rect width="72" height="120" fill="#7A1E6C"/>
  <g filter="url(#ikatBlur)">
    <path d="M0 0h16v120H0z" fill="#F2C14E"/>
    <path d="M18 0c10 20 -6 40 4 60s-6 40 4 60h14c-10-20 6-40-4-60s10-40 4-60z" fill="#E33C8C"/>
    <path d="M40 0h8v120h-8z" fill="#1F9E8E"/>
    <path d="M50 0c8 30 -6 30 2 60s-6 30 2 60h20V0z" fill="#3B2A8C"/>
    <path d="M60 20l8 10-8 10-8-10zM60 80l8 10-8 10-8-10z" fill="#F7E7B0"/>
    <path d="M8 40l6 10-6 10-6-10zM8 100l6 10-6 10-6-10z" fill="#7A1E6C"/>
  </g>
</pattern>`;

/* перс: 'jasur' | 'hero' | 'nilufar' | 'bahodir' | 'sardor' | 'rustam' | 'kid' */
function bust(who, o) {
  o = Object.assign({ t: 0 }, o);
  const isHero = who === 'hero';
  const sex = who === 'nilufar' ? 'f' : who === 'bahodir' || who === 'rustam' ? 'big' : 'm';
  const skin = who === 'bahodir' || who === 'rustam' || who === 'kid' ? SKIN_TAN : SKIN;
  const fo = Object.assign({ sex, skin }, o);
  if (isHero) { fo.mask = o.mask !== false; fo.eyes = o.eyes || 'glow'; fo.brows = o.brows || 'determined'; }
  if (who === 'bahodir') { fo.mean = o.mean !== false; fo.iris = ['#1A0E08', '#5A3418']; fo.scar = true; }
  if (who === 'nilufar') { fo.iris = ['#3A2016', '#C08250']; }
  if (who === 'jasur' || isHero) { fo.iris = fo.iris || ['#20140F', '#7A4A2C']; }
  if (who === 'sardor' || who === 'rustam' || who === 'kid') fo.iris = ['#1E120C', '#6A4428'];
  const k = faceKit(fo);
  const X = k.X;
  let hair;
  if (who === 'jasur' || isHero) hair = jasurHair(o, X);
  else if (who === 'nilufar') hair = nilufarHair(o, X);
  else if (who === 'bahodir' || who === 'rustam') hair = bahodirHair(o, X);
  else if (who === 'sardor') hair = sardorHair(o, X);
  else hair = { back: '', front: doppi(X), shadow: `M${X(-100)} -96Q${X(0)} -118 ${X(100)} -96L${X(100)} -70Q${X(0)} -94 ${X(-100)} -70Z` };
  let s = '';
  s += hair.back;
  s += neckOnly(k);
  s += who === 'jasur' ? bodySchool(o) : isHero ? bodyHero(o) : who === 'nilufar' ? bodyNilufar(o) : who === 'bahodir' ? bodyBahodir(o)
    : who === 'sardor' ? bodyPlain('#3A5A8A') : who === 'rustam' ? bodyPlain('#5A4A3A') : bodyPlain('#4A6A5A');
  s += neckAndFace(fo, k);
  // тень от волос на лбу
  const fid = uid('fc');
  s += `<clipPath id="${fid}"><path d="${k.face}"/></clipPath>`;
  s += g(path(hair.shadow, skin.sh, 'opacity=".75"'), '', `clip-path="url(#${fid})"`);
  s += faceFeatures(fo, k);
  if (o.eyeShade) {
    const gid = uid('es');
    s += lg(gid, [[0, '#0A0418', .95], [.86, '#0A0418', .82], [1, '#0A0418', 0]]);
    s += g(rect(-140, -170, 280, 230, `url(#${gid})`, `opacity="${f2(o.eyeShade)}"`), '', `clip-path="url(#${fid})"`);
  }
  if ((isHero && fo.mask) || o.scarf) s += g(scarfMask(o, X), o.maskDrop ? `translate(0 ${f2(o.maskDrop)})` : '');
  s += hair.front;
  if (o.rim) s = g(s, '', `filter="url(#${o.rim})"`);
  return s;
}

/* ---------- полные фигуры: скелет → объёмный силуэт с контровым светом ---------- */
/* углы в градусах от вертикали вниз; + — вперёд (вправо) */
function capsule(x1, y1, x2, y2, w1, w2) {
  const a = Math.atan2(y2 - y1, x2 - x1), nx = -Math.sin(a), ny = Math.cos(a);
  const p1 = [x1 + nx * w1, y1 + ny * w1], p2 = [x2 + nx * w2, y2 + ny * w2], p3 = [x2 - nx * w2, y2 - ny * w2], p4 = [x1 - nx * w1, y1 - ny * w1];
  return `M${f2(p1[0])} ${f2(p1[1])}L${f2(p2[0])} ${f2(p2[1])}A${f2(w2)} ${f2(w2)} 0 0 0 ${f2(p3[0])} ${f2(p3[1])}L${f2(p4[0])} ${f2(p4[1])}A${f2(w1)} ${f2(w1)} 0 0 0 ${f2(p1[0])} ${f2(p1[1])}Z`;
}
const rad = d => d * Math.PI / 180;
const seg = (x, y, ang, L) => [x + Math.sin(rad(ang)) * L, y + Math.cos(rad(ang)) * L];
/* поза: { lean, head, uaL, faL, uaR, faR, thL, shL, thR, shR, front } — L дальняя, R ближняя рука/нога */
function rig(p, o = {}) {
  const fem = o.fem;
  const front = p.front ? 1 : 0;
  const hip = [0, 0];
  const sh = seg(0, 0, 180 + (p.lean || 0), 120);       // плечи над тазом
  const neck = seg(sh[0], sh[1], 180 + (p.lean || 0) + (p.head || 0), 16);
  const headC = seg(neck[0], neck[1], 180 + (p.lean || 0) + (p.head || 0), 28);
  const sw = front ? (fem ? 26 : 34) : 8, hw = front ? (fem ? 22 : 18) : 6;
  const shL = [sh[0] - sw, sh[1]], shR = [sh[0] + sw, sh[1]], hpL = [hip[0] - hw, hip[1]], hpR = [hip[0] + hw, hip[1]];
  const L = { ua: 62, fa: 58, th: 86, sh: 84 };
  const elL = seg(shL[0], shL[1], p.uaL || 0, L.ua), wrL = seg(elL[0], elL[1], (p.uaL || 0) + (p.faL || 0), L.fa);
  const elR = seg(shR[0], shR[1], p.uaR || 0, L.ua), wrR = seg(elR[0], elR[1], (p.uaR || 0) + (p.faR || 0), L.fa);
  const knL = seg(hpL[0], hpL[1], p.thL || 0, L.th), ftL = seg(knL[0], knL[1], (p.thL || 0) + (p.shL || 0), L.sh);
  const knR = seg(hpR[0], hpR[1], p.thR || 0, L.th), ftR = seg(knR[0], knR[1], (p.thR || 0) + (p.shR || 0), L.sh);
  return { hip, sh, neck, headC, shL, shR, hpL, hpR, elL, wrL, elR, wrR, knL, ftL, knR, ftR, lean: p.lean || 0 };
}
function figureShapes(r, o = {}) {
  const t = o.t || 0, wind = o.wind == null ? 1 : o.wind, dir = o.windDir || -1, fem = o.fem;
  const wv = Math.sin(t * 9), wv2 = Math.sin(t * 7 + 1);
  let back = '', body = '';
  const path = d => `<path d="${d}"/>`;
  const circle = (x, y, r_) => `<circle cx="${f2(x)}" cy="${f2(y)}" r="${f2(r_)}"/>`;
  const ell = (x, y, rx, ry) => `<ellipse cx="${f2(x)}" cy="${f2(y)}" rx="${f2(rx)}" ry="${f2(ry)}"/>`;
  const limb = (a, b, w1, w2) => capsule(a[0], a[1], b[0], b[1], w1, w2);
  const foot = (k, f, fw) => { const a = Math.atan2(f[1] - k[1], f[0] - k[0]); return capsule(f[0], f[1], f[0] + Math.cos(a - Math.PI / 2 * fw) * 22, f[1] + Math.sin(a - Math.PI / 2 * fw) * 22, 8, 6); };
  // дальние конечности
  body += path(limb(r.hpL, r.knL, 17, 13) + limb(r.knL, r.ftL, 13, 9) + foot(r.knL, r.ftL, -1));
  body += path(limb(r.shL, r.elL, 12, 10) + limb(r.elL, r.wrL, 10, 8)) + circle(r.wrL[0], r.wrL[1], 10, 'inherit');
  // торс
  const t1 = [r.shL[0] - 6, r.shL[1] - 4], t2 = [r.shR[0] + 6, r.shR[1] - 4], t3 = [r.hpR[0] + 12, r.hpR[1] + 6], t4 = [r.hpL[0] - 12, r.hpL[1] + 6];
  body += path(smoothPath([t1, [(t1[0] + t2[0]) / 2, t1[1] - 6], t2, [(t2[0] + t3[0]) / 2 + 6, (t2[1] + t3[1]) / 2], t3, [(t3[0] + t4[0]) / 2, t3[1] + 10], t4, [(t4[0] + t1[0]) / 2 - 6, (t4[1] + t1[1]) / 2]], true, .8));
  body += path(limb(r.sh, r.neck, 11, 10));
  // голова и волосы
  const hc = r.headC;
  body += ell(hc[0], hc[1], 25, 30);
  if (fem) {
    const hl = smoothPath([[hc[0] - 28, hc[1] - 10], [hc[0] - 10, hc[1] - 36], [hc[0] + 20, hc[1] - 32], [hc[0] + 30, hc[1]], [hc[0] + 26 + dir * 30 * wind, hc[1] + 70 + wv * 6], [hc[0] - 34 + dir * 40 * wind, hc[1] + 110 + wv2 * 10], [hc[0] - 30, hc[1] + 20]]);
    back += path(hl);
  } else {
    let hd = '';
    const sp = [[-30, 6], [-46 + dir * 10, -8], [-30, -16], [-42, -34], [-20, -30], [-16, -54], [0, -36], [16, -52], [20, -32], [40, -36], [30, -14], [42, 0], [28, 6]];
    sp.forEach((q, i) => { const k = (q[1] < -20 ? 1 : .6) * wind; hd += (i ? 'L' : 'M') + f2(hc[0] + q[0] + (i % 2 ? dir * 6 * k * (1 + wv * .3) : 0)) + ' ' + f2(hc[1] + q[1]); });
    body += path(hd + 'Z');
  }
  // ближние конечности
  body += path(limb(r.hpR, r.knR, 18, 13) + limb(r.knR, r.ftR, 13, 9) + foot(r.knR, r.ftR, -1));
  body += path(limb(r.shR, r.elR, 12.5, 10) + limb(r.elR, r.wrR, 10, 8)) + circle(r.wrR[0], r.wrR[1], 10.5, 'inherit');
  if (o.robe !== false && !fem) {
    // чапан: полы до колен, развеваются по ветру
    const hemY = Math.max(r.knL[1], r.knR[1]) + 20;
    const tailx = dir * (24 + 46 * wind);
    const robe = smoothPath([[r.shL[0] - 10, r.shL[1]], [r.shR[0] + 10, r.shR[1]], [r.hpR[0] + 30, r.hpR[1] + 10],
      [r.hpR[0] + 22 + tailx * .2, hemY - 30 + wv * 8], [r.hip[0] + tailx * .7, hemY - 6 + wv2 * 12], [r.hpL[0] - 20 + tailx * 1.2, hemY - 24 + wv * 14], [r.hpL[0] - 18 + tailx * .4, r.hpL[1] - 20]], true, .9);
    back += path(robe);
    // рукава-раструбы
    body += path(limb(r.shR, r.elR, 18, 16)) + path(limb(r.shL, r.elL, 17, 15));
  }
  if (fem) {
    const sk = smoothPath([[r.hpL[0] - 20, r.hpL[1] - 10], [r.hpR[0] + 20, r.hpR[1] - 10], [r.hpR[0] + 40 + dir * 20 * wind, r.hpR[1] + 70 + wv * 6], [r.hpL[0] - 40 + dir * 30 * wind, r.hpL[1] + 74 + wv2 * 6]], true, .8);
    body += path(sk);
  }
  // шарф
  let scarf = '';
  if (o.scarf !== false && !fem) {
    const nx = r.neck[0], ny = r.neck[1] + 4, L = 200 * (o.scarfLen || 1) * (0.6 + .4 * wind);
    scarf = path(`M${f2(nx - 12)} ${f2(ny - 6)}C${f2(nx + dir * L * .3)} ${f2(ny - 10 + wv * 14)} ${f2(nx + dir * L * .6)} ${f2(ny + 10 - wv2 * 22)} ${f2(nx + dir * L)} ${f2(ny - 10 + wv * 30)}L${f2(nx + dir * L * .92)} ${f2(ny + 22 + wv * 26)}C${f2(nx + dir * L * .55)} ${f2(ny + 30 - wv2 * 16)} ${f2(nx + dir * L * .3)} ${f2(ny + 24 + wv * 10)} ${f2(nx + 12)} ${f2(ny + 12)}Z`);
  }
  return { back, body, scarf, eyes: hc };
}
function drawFigure(r, o, extra = '') {
  const col = o.col || '#0B0A16', rim = o.rimCol || '#FF6A4A';
  const sh = figureShapes(r, o);
  const all = sh.back + sh.body + extra;
  let s = '';
  s += g(all, '', `fill="${rim}" stroke="${rim}" stroke-width="7" stroke-linejoin="round"`);
  s += g(all, '', `fill="${col}"`);
  if (sh.scarf) s += g(sh.scarf, '', `fill="#B0144E" stroke="${rim}" stroke-width="2.5"`);
  if (o.eyes !== false && !o.fem) {
    const hc = sh.eyes, fx = o.facing == null ? 0 : o.facing * 8;
    s += g(path(starPath(7, 2.4, 4), '#FFE9A0', `transform="translate(${f2(hc[0] - 9 + fx)} ${f2(hc[1] - 2)})"`) + path(starPath(7, 2.4, 4), '#FFE9A0', `transform="translate(${f2(hc[0] + 9 + fx)} ${f2(hc[1] - 2)})"`), '', 'filter="url(#glow)"');
  }
  return s;
}
const POSES = {
  stand: { front: 1, lean: 0, head: 0, uaL: -12, faL: 6, uaR: 12, faR: -6, thL: -9, shL: 3, thR: 9, shR: -3 },
  brace: { front: 1, lean: 0, head: 0, uaL: -150, faL: -20, uaR: 150, faR: 20, thL: -24, shL: 14, thR: 24, shR: -14 },
  carry: { front: 1, lean: 0, head: -8, uaL: -20, faL: 110, uaR: 20, faR: -110, thL: -8, shL: 2, thR: 8, shR: -2 },
  leap: { front: 0, lean: 24, head: -10, uaL: -60, faL: -40, uaR: 110, faR: 0, thL: -50, shL: -60, thR: 70, shR: -80 },
  punch: { front: 0, lean: 30, head: -20, uaL: -40, faL: -70, uaR: 95, faR: 0, thL: -40, shL: 50, thR: 60, shR: -90 },
};
function runPose(ph) {
  const s = Math.sin(ph), c = Math.cos(ph);
  return { front: 0, lean: 26, head: -16, uaL: -50 * s, faL: 70, uaR: 50 * s, faR: 70, thL: 45 * s + 10, shL: -60 + 40 * Math.max(0, -c), thR: -45 * s + 10, shR: -60 + 40 * Math.max(0, c) };
}
/* совместимость со старым API: pose 'stand' | 'run' | 'leap' | 'carry' | 'brace' | 'punch' */
function heroFigure(o) {
  const t = o.t || 0, pose = o.pose || 'stand';
  const p = pose === 'run' ? runPose(t * 14) : POSES[pose] || POSES.stand;
  const r = rig(p);
  let s = '';
  let her = '';
  if (pose === 'carry') {
    // Нилуфар на руках: лежит поперёк, голова у его плеча, волосы свисают, ноги согнуты — один общий силуэт с героем
    const hw = Math.sin(t * 3) * 8;
    const body = capsule(-60, -96, 60, -84, 24, 20) + capsule(60, -84, 124, -104, 15, 12) + capsule(124, -104, 140, -24, 11, 8) + capsule(54, -78, 112, -90, 14, 11) + capsule(112, -90, 124, -10, 10, 7) +
      capsule(-50, -108, -14, -140, 9, 8);
    const head = `M-128 -124C-132 -152 -106 -164 -86 -154C-68 -144 -66 -116 -82 -104C-100 -94 -124 -102 -128 -124Z`;
    const hair = `M-130 -130C-146 -100 ${f2(-160 + hw)} -30 ${f2(-156 + hw)} 50C${f2(-146 + hw)} 54 ${f2(-134 + hw * .6)} 20 -122 -20C-114 -50 -106 -90 -90 -108Z`;
    const skirt = `M30 -104C60 -116 96 -112 110 -100L${f2(118 + hw * .4)} -52C92 -42 58 -46 36 -58Z`;
    her = `<path d="${body}"/><path d="${head}"/><path d="${hair}"/><path d="${skirt}"/>` +
      `<path d="${capsule(r.shR[0], r.shR[1], r.elR[0], r.elR[1], 13, 11) + capsule(r.elR[0], r.elR[1], r.wrR[0], r.wrR[1], 10, 9)}"/>`;
  }
  s = drawFigure(r, Object.assign({}, o, { windDir: o.windDir || -1 }), her);
  // ступни на y=0
  const footY = Math.max(r.ftL[1], r.ftR[1]);
  return g(s, `translate(0 ${f2(-footY)})`);
}

/* ---------- Хумо: птица из золотого и бирюзового пламени ---------- */
function humo(t, o = {}) {
  const flap = Math.sin(t * (o.flapSpeed || 3)) * (o.flap == null ? 1 : o.flap);
  const open = o.open == null ? 1 : o.open;
  let s = '';
  const fid = uid('hm');
  s += lg(fid, [[0, '#FFF6D0'], [0.35, '#FFD25A'], [0.7, '#F08A24'], [1, '#2FD6D0']], 0, 0, 1, 0);
  const fid2 = uid('hm');
  s += lg(fid2, [[0, '#FFFFFF'], [0.5, '#9FF6EC'], [1, '#1E9EB8']], 0, 0, 0, 1);
  // хвост: длинные перья-орнамент
  for (let i = 0; i < 7; i++) {
    const a = (i - 3) * 9 + Math.sin(t * 2 + i) * 4;
    const L = 360 + (3 - Math.abs(i - 3)) * 60;
    s += g(path(`M0 0C40 ${L * .3} -30 ${L * .6} 10 ${L}C30 ${L * .7} 60 ${L * .4} 0 0Z`, `url(#${fid2})`, 'opacity=".85"') +
      g(path(starPath(16, 6, 8), '#FFE48A') + circle(0, 0, 5, '#1E9EB8'), `translate(18 ${L * .92})`), `translate(0 60) rotate(${f2(a)})`);
  }
  // крылья
  for (const sd of [-1, 1]) {
    let w = '';
    for (let i = 0; i < 9; i++) {
      const L = 220 + i * 26;
      const a = sd * (60 + i * 10 - flap * 18) * open + (1 - open) * sd * 160;
      w += g(path(`M0 0C${L * .25} -24 ${L * .7} -30 ${L} 0C${L * .7} 18 ${L * .25} 16 0 0Z`, `url(#${fid})`, `stroke="#FFF2B0" stroke-width="1.5" opacity="${f2(.9 - i * .04)}"`), `rotate(${f2(sd > 0 ? -a : 180 + a)})`);
    }
    s += g(w, `translate(${sd * 20} -10)`);
  }
  // тело и голова
  s += path('M-34 -40C-40 30 -20 90 0 120C20 90 40 30 34 -40C20 -70 -20 -70 -34 -40Z', `url(#${fid2})`, 'stroke="#FFFFFF" stroke-width="2"');
  s += path('M-22 -70C-30 -110 -10 -136 10 -132C30 -126 34 -96 20 -70Z', '#FFE7A0', 'stroke="#FFFFFF" stroke-width="2"');
  s += path('M14 -116L54 -104L16 -98Z', '#F0A020');
  // хохолок-пламя
  for (let i = 0; i < 5; i++) s += path(`M${-10 + i * 6} -128C${-30 + i * 4} ${-170 - i * 8} ${-10 + i * 10 + Math.sin(t * 6 + i) * 6} -${f2(190 + i * 6)} ${4 + i * 8} -${f2(150 + i * 4)}Z`, i % 2 ? '#FFD25A' : '#2FD6D0', 'opacity=".9"');
  // глаз
  s += ell(10, -110, 6, 7, '#1A2A60') + circle(8, -112, 2.4, '#fff');
  return g(s, '', 'filter="url(#glow)"');
}

/* ---------- Дев: демон из красного дыма и камня ---------- */
function devHead(t, o = {}) {
  const roar = o.roar || 0, eyeGlow = o.eyes == null ? 1 : o.eyes;
  let s = '';
  const sm = uid('dv');
  s += rg(sm, [[0, '#7A1018'], [0.6, '#3A0610'], [1, '#12020A', 0]]);
  // дымная грива
  let smoke = '';
  const r = rng(9);
  for (let i = 0; i < 26; i++) {
    const a = r() * Math.PI * 2, d = 260 + r() * 160;
    smoke += circle(Math.cos(a) * d * .9 + Math.sin(t * .8 + i) * 20, Math.sin(a) * d * .7 - 40 + Math.cos(t * .7 + i) * 16, 120 + r() * 120, i % 3 ? '#4A0A14' : '#7A1A10', 'opacity=".55"');
  }
  s += g(smoke, '', 'filter="url(#blur30)"');
  // рога
  s += path('M-180 -200C-260 -300 -300 -420 -250 -520C-240 -430 -200 -330 -120 -250Z', '#2A1A18', 'stroke="#FF5A2A" stroke-width="4"');
  s += path('M180 -200C260 -300 300 -420 250 -520C240 -430 200 -330 120 -250Z', '#2A1A18', 'stroke="#FF5A2A" stroke-width="4"');
  // каменная голова
  const hd = 'M-230 -160C-260 -40 -230 120 -150 220C-90 290 90 290 150 220C230 120 260 -40 230 -160C180 -280 -180 -280 -230 -160Z';
  s += path(hd, '#3A1E1C', 'stroke="#140808" stroke-width="6"');
  s += path('M60 -250C180 -230 250 -120 220 40C200 140 160 200 120 240C170 120 190 -40 60 -250Z', '#1E0E0E', 'opacity=".7"');
  // светящиеся трещины
  s += strokeP('M-200 -120L-140 -60L-160 20L-110 80M150 -200L110 -120L160 -60L120 10M-40 -250L-20 -190L-60 -150M30 180L60 240', '#FF6A2A', 5, 'filter="url(#glow)"');
  // брови-надбровья и глаза
  s += path('M-200 -70L-40 -20L-60 10L-190 -30Z', '#1A0A0A');
  s += path('M200 -70L40 -20L60 10L190 -30Z', '#1A0A0A');
  s += g(path('M-170 -24L-60 6L-80 36L-160 14Z', '#FFE07A') + path('M170 -24L60 6L80 36L160 14Z', '#FFE07A'), '', `filter="url(#glowL)" opacity="${f2(eyeGlow)}"`);
  // пасть
  const mo = 40 + roar * 110;
  s += path(`M-130 110Q0 ${f2(80)} 130 110L110 ${f2(110 + mo)}Q0 ${f2(140 + mo)} -110 ${f2(110 + mo)}Z`, '#FF5A1A', 'filter="url(#glow)"');
  s += path(`M-120 112Q0 ${f2(90)} 120 112L100 ${f2(104 + mo)}Q0 ${f2(130 + mo)} -100 ${f2(104 + mo)}Z`, '#5A0808');
  let teeth = '';
  for (let i = 0; i < 8; i++) { const x = -105 + i * 30; teeth += `M${x} ${f2(100 + Math.abs(i - 3.5) * 3)}l12 34l12 -34Z`; teeth += `M${x + 6} ${f2(112 + mo)}l12 -30l12 30Z`; }
  s += path(teeth, '#F0E2C8');
  return s;
}

/* ---------- руки и предметы ---------- */
/* кисть: kind 'open' (ладонь к зрителю), 'fist', 'hold' (держит предмет), 'grab' */
function hand(kind, o = {}) {
  const sk = o.skin || SKIN, lc = sk.line;
  let s = '';
  if (kind === 'open') {
    s += path('M-60 120L-56 20C-58 0 -40 -10 -34 10L-30 -70C-30 -92 -6 -92 -6 -70L-4 -96C-4 -118 22 -118 22 -96L22 -74C24 -94 48 -92 48 -70L46 -30C50 -48 70 -44 70 -24L66 50C64 90 40 120 20 130Z', sk.base, `stroke="${lc}" stroke-width="3" stroke-linejoin="round"`);
    s += path('M-30 -10L-30 30M-6 -60L-4 20M22 -60L22 20M46 -20L44 30', 'none', `stroke="${sk.sh2}" stroke-width="2.4" opacity=".7"`);
    s += path('M20 130C40 120 64 90 66 50L66 30C50 80 30 110 -10 126Z', sk.sh, 'opacity=".7"');
  } else if (kind === 'fist') {
    s += path('M-70 -40C-70 -70 -40 -76 -20 -70C0 -82 30 -80 46 -64C70 -66 84 -44 78 -20C86 10 70 40 40 46L-40 50C-70 46 -80 10 -70 -40Z', sk.base, `stroke="${lc}" stroke-width="3"`);
    s += path('M-20 -70C-24 -50 -24 -30 -20 -14M14 -76C10 -56 10 -34 14 -16M46 -64C42 -46 42 -26 46 -10', 'none', `stroke="${lc}" stroke-width="2.4"`);
    s += path('M-74 0C-40 -6 -10 0 10 14C-10 20 -40 24 -70 20Z', sk.sh, 'opacity=".8"');
    s += path('M-40 50L-36 140L40 140L40 46Z', o.sleeve || '#262B4A', `stroke="${INK}" stroke-width="3"`);
  } else if (kind === 'hold') {
    s += path('M-50 60C-60 20 -50 -20 -20 -30L40 -34C60 -30 60 -10 40 -6L10 -4C40 0 56 14 40 26L-10 30C10 40 10 56 -10 60Z', sk.base, `stroke="${lc}" stroke-width="3"`);
  }
  return s;
}
function pencil(len = 260) {
  return path(`M0 0L${len} -14L${len} 14Z`, '#F2C14E', `stroke="${INK}" stroke-width="2"`) + path(`M0 0L34 -2L34 2Z`, '#3A2A20') +
    rect(len - 4, -16, 30, 32, '#E88AA0', `stroke="${INK}" stroke-width="2"`) + rect(len - 10, -15, 8, 30, '#C0C0C8');
}
function phone(rec) {
  return rect(-50, -90, 100, 180, '#1A1A24', `rx="14" stroke="${INK}" stroke-width="3"`) + rect(-42, -78, 84, 150, rec ? '#5A1018' : '#2A3A5A', 'rx="6"') +
    (rec ? circle(30, -66, 6, '#FF3A3A') : '') + rect(-12, -86, 24, 4, '#444', 'rx="2"');
}
function feather(t, o = {}) {
  const fid = uid('fth');
  let s = lg(fid, [[0, '#FFF6D0'], [0.5, '#FFD25A'], [1, '#2FD6D0']], 0, 0, 0, 1);
  s += path('M0 -160C50 -100 50 40 0 160C-50 40 -50 -100 0 -160Z', `url(#${fid})`, 'stroke="#FFFFFF" stroke-width="2"');
  let barbs = '';
  for (let i = -6; i <= 6; i++) barbs += `M0 ${i * 22}l${i % 2 ? 30 : -30} ${-14}`;
  s += path(barbs, 'none', 'stroke="#FFF6D0" stroke-width="2" opacity=".7"');
  s += strokeP('M0 -150L0 190', '#FFFFFF', 3);
  return g(s, '', `filter="url(#glow)" opacity="${f2(o.op == null ? 1 : o.op)}"`);
}
/* кулак Дева — каменная глыба */
function devFist() {
  let s = path('M-300 -160C-300 -260 -160 -300 -40 -280C80 -310 220 -280 280 -200C340 -100 320 80 240 160C140 250 -120 250 -240 170C-320 100 -320 -60 -300 -160Z', '#3A1E1C', 'stroke="#120606" stroke-width="8"');
  s += path('M-200 -220C-210 -120 -200 -40 -180 40M-40 -270C-50 -160 -50 -60 -30 30M110 -270C100 -160 100 -60 120 30', 'none', 'stroke="#120606" stroke-width="10"');
  s += strokeP('M-150 -100L-90 -40L-120 40M60 -200L20 -120L80 -40M200 -60L150 20', '#FF5A2A', 6, 'filter="url(#glow)"');
  return s;
}
