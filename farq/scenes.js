/* Мультсцены для каждого термина. Каждая сцена — полноэкранный SVG 1080×1920 с камерой;
   события привязаны к моментам ключевых слов k[0..2] (секунды от начала сцены). */
'use strict';

const outBounce = x => {
  const a = 7.5625, d = 2.75;
  if (x < 1 / d) return a * x * x;
  if (x < 2 / d) return a * (x -= 1.5 / d) * x + .75;
  if (x < 2.5 / d) return a * (x -= 2.25 / d) * x + .9375;
  return a * (x -= 2.625 / d) * x + .984375;
};
const pop = (lt, t0, d = .45) => E.outBackS(P(lt, t0, d));
const io = E.inOutCubic;
/* камера: keys [[t, x, y, s], ...] — точка (x, y) в центре экрана с масштабом s */
function camSet(g, lt, keys, punch = 0, shake = 0, t = 0) {
  const x = kf(lt, keys.map(k => [k[0], k[1], io])), y = kf(lt, keys.map(k => [k[0], k[2], io]));
  const s = kf(lt, keys.map(k => [k[0], k[3], io])) * (1 + punch);
  const r = rng(Math.floor(t * 60) + 7);
  const sx = (r() - .5) * shake, sy = (r() - .5) * shake;
  g.setAttribute('transform', `translate(${n1(540 + sx)} ${n1(960 + sy)}) scale(${s.toFixed(4)}) translate(${n1(-x)} ${n1(-y)})`);
}
const punches = (lt, ts, a = .06) => ts.reduce((s, t) => s + pulse(lt, t, .04, .4) * a, 0);
/* ходьба из x0 в x1 за [t0, t1]; фаза шага для рига */
function walkX(lt, t0, t1, x0, x1, speed = 9) {
  if (lt <= t0) return { x: x0, walk: 0 };
  if (lt >= t1) return { x: x1, walk: 0 };
  return { x: lerp(x0, x1, (lt - t0) / (t1 - t0)), walk: (lt - t0) * speed + .001 };
}
function arcPt(u, x0, y0, x1, y1, h) { return [lerp(x0, x1, u), lerp(y0, y1, u) - Math.sin(Math.PI * u) * h]; }
/* пучок лучей */
const RAYS = (c, n = 16, r = 1400) => Array.from({ length: n }, (_, i) => { const a = i / n * Math.PI * 2, b = a + Math.PI / n * .55; return `<path d="M0 0 L${n1(Math.cos(a) * r)} ${n1(Math.sin(a) * r)} L${n1(Math.cos(b) * r)} ${n1(Math.sin(b) * r)}Z" fill="${c}"/>`; }).join('');
function sparkBurst(p, n, c) {
  const g = sv('g', null, p);
  const s = Array.from({ length: n }, (_, i) => svh(PROP.sparkle(i % 2 ? c : '#fff'), g));
  return { g, s, draw(lt, t0, x, y, R = 160) {
    const u = P(lt, t0, .9);
    s.forEach((e, i) => { const a = i / n * 6.283 + .3; at(e, x + Math.cos(a) * R * E.outCubic(u), y + Math.sin(a) * R * E.outCubic(u), (1 - u) * 1.2, u * 160, u > 0 && u < 1 ? 1 : 0); });
  } };
}

const SCENES = {};

/* ============ KOMMUNIZM: пирамида классов рушится, все на равных ============ */
SCENES.equal = (svg, col) => {
  const W = sv('g', null, svg);
  sky(W, '#2B0D2A', '#FF8A5C');
  const rays = svh(RAYS('rgba(255,214,140,.10)', 18), W);
  const sun = sunEl(W, 540, 1170, 120, '#FFD27A');
  cloud(W, 160, 640, 1.1, '#FFB08A', .35); cloud(W, 900, 560, .9, '#FFB08A', .3);
  skyline(W, 1195, '#6E1F3C', 7, 110, 330, '#FFC98A');
  ground(W, 1185, '#4A1426', '#14070F');
  // фабрика (появится на «xususiy mulk»)
  const fac = factoryEl(W, 820, 1190, .5, '#A8566A');
  const fsign = svh(`<rect x="-120" y="-40" width="240" height="70" rx="12" fill="#2A0F1F" stroke="#FFD27A" stroke-width="5"/>`, fac.g);
  const fsTxt = sv('text', { x: 0, y: 8, 'text-anchor': 'middle', 'font-family': 'Unbounded', 'font-weight': 900, 'font-size': 34, fill: '#FFD27A' }, fsign);
  fsTxt.textContent = 'XUSUSIY';
  at(fsign, -60, -330);
  const lock = svh(PROP.padlock, fac.g); at(lock, 180, -80, .9);
  const shackle = lock.querySelector('.shackle');
  const glow = sv('ellipse', { cx: 180, cy: -60, rx: 120, ry: 90, fill: rad([[0, '#FFE6A0', .9], [1, '#FFE6A0', 0]]) }, fac.g);
  // пирамида
  const plat1 = prop(W, `<rect x="-400" y="-18" width="800" height="36" rx="12" fill="#D9A05B"/><rect x="-400" y="8" width="800" height="12" rx="6" fill="#000" opacity=".25"/>`);
  const plat2 = prop(W, `<rect x="-220" y="-18" width="440" height="36" rx="12" fill="#E9B949"/><rect x="-220" y="8" width="440" height="12" rx="6" fill="#000" opacity=".25"/>`);
  const coins = Array.from({ length: 6 }, () => prop(W, PROP.coin(22)));
  const mk = o => Char(W, o);
  const workers = [0, 1, 2, 3].map(i => mk({ outfit: 'overalls', top: '#EDEFF4', pants: ['#2F6BD8', '#3A9A5B', '#2F6BD8', '#C2563A'][i], hat: 'hardhat', skin: SKINS[[2, 0, 3, 1][i]], seed: i + 1, hairStyle: 'short' }));
  const clerks = [0, 1, 2].map(i => mk({ outfit: 'suit', top: ['#5B6683', '#6B5B83', '#4F6E7A'][i], tie: '#3E7BE0', glasses: i === 1, skin: SKINS[[0, 4, 1][i]], hair: HAIRS[i + 1], hairStyle: i === 2 ? 'bun' : 'side', female: i === 2, seed: i + 7 }));
  const rich = mk({ outfit: 'suit', top: '#1F1B2E', hat: 'tophat', beard: 'mustache', fat: 1, skin: SKINS[0], hair: '#3A2A20', tie: '#C8243D', seed: 11 });
  const sack = prop(W, `<path d="M-60 0 Q-80 -60 -34 -96 L-40 -118 Q0 -108 40 -118 L34 -96 Q80 -60 60 0 Q0 14 -60 0Z" fill="#D9B77A"/><text y="-30" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="54" fill="#8E6A2E">$</text>`);
  const hatFly = prop(W, `<rect x="-62" y="-6" width="124" height="14" rx="7" fill="#15151B"/><path d="M-40 -4 L-36 -90 Q0 -98 36 -90 L40 -4Z" fill="#1E1E26"/><rect x="-39" y="-26" width="78" height="14" fill="#9E1B2F"/>`);
  const eq = prop(W, `<circle r="74" fill="${col}"/><circle r="74" fill="none" stroke="#fff" stroke-width="8"/><path d="M-34 -16h68M-34 16h68" stroke="#fff" stroke-width="16" stroke-linecap="round"/>`);
  const burst = sparkBurst(W, 12, '#FFD27A');
  const order = [workers[0], clerks[0], workers[1], rich, clerks[1], workers[2], clerks[2], workers[3]];
  const fin = i => 112 + i * 122;
  return { update(lt, k, D, t) {
    const c0 = k[0];
    const fall = P(lt, c0, .7);
    // платформы падают
    const g1 = P(lt, c0 + .02, .8), g2 = P(lt, c0, .8);
    at(plat1, 540 - g1 * 60, 1200 + 900 * g1 * g1, 1, -g1 * 25, 1 - g1);
    at(plat2, 540 + g2 * 80, 930 + 1100 * g2 * g2, 1, g2 * 32, 1 - g2);
    // рабочие держат платформу
    const strain = Math.sin(t * 9) * 2;
    workers.forEach((w, i) => {
      const x0 = 230 + i * 207, fi = order.indexOf(w);
      const wk = walkX(lt, c0 + .1, c0 + 1.0, x0, fin(fi), 10);
      const hold = lt < c0 + .05;
      const hands = lt > c0 + 1.1;
      const cheer = P(lt, k[2], .3) > 0 ? Math.max(0, Math.sin((lt - k[2]) * 7 + i)) : 0;
      w.draw({ x: wk.x, y: 1470, s: lerp(.62, .56, fall), t, walk: wk.walk, em: hold ? 'angry' : 'grin', look: hold ? (i < 2 ? .4 : -.4) : 0, lookY: hold ? -1 : 0,
        armL: hold ? [-168, 4 + strain] : cheer > 0 ? [-160, 10] : hands ? [-38, 4 + Math.sin(t * 3) * 6] : null,
        armR: hold ? [168, -4 - strain] : cheer > 0 ? [160, -10] : hands ? [38, -4 + Math.sin(t * 3) * 6] : null,
        jump: cheer * 60, squash: hold ? 4 : 0 });
    });
    // клерки
    clerks.forEach((c, i) => {
      const x0 = 360 + i * 180, fi = order.indexOf(c);
      const dy = lt < c0 + .08 ? 1182 : lerp(1182, 1470, outBounce(P(lt, c0 + .08, .6)));
      const wk = walkX(lt, c0 + .7, c0 + 1.1, x0, fin(fi), 10);
      const hold = lt < c0 + .05, hands = lt > c0 + 1.1;
      const cheer = P(lt, k[2], .3) > 0 ? Math.max(0, Math.sin((lt - k[2]) * 7 + i + 2)) : 0;
      c.draw({ x: wk.x, y: dy, s: lerp(.58, .56, fall), t, walk: wk.walk, em: hold ? 'sad' : lt < c0 + .7 ? 'shock' : 'grin', lookY: hold ? -1 : 0,
        armL: hold ? [-165, 0] : cheer > 0 ? [-160, 10] : hands ? [-38, 4] : lt > c0 ? [-140, 30] : null,
        armR: hold ? [165, 0] : cheer > 0 ? [160, -10] : hands ? [38, -4] : lt > c0 ? [140, -30] : null, jump: cheer * 60 });
    });
    // богач на вершине
    const ry = lt < c0 + .15 ? 912 : lerp(912, 1470, outBounce(P(lt, c0 + .15, .7)));
    const rwk = walkX(lt, c0 + .85, c0 + 1.15, 540, fin(3), 10);
    const rich0 = lt < c0;
    const cheerR = P(lt, k[2], .3) > 0 ? Math.max(0, Math.sin((lt - k[2]) * 7 + 5)) : 0;
    rich.draw({ x: rwk.x, y: ry, s: lerp(.66, .56, fall), t, walk: rwk.walk, em: rich0 ? 'grin' : lt < c0 + 1 ? 'shock' : 'smile', talk: rich0 && lt > .4,
      armL: rich0 ? [-30, -40] : lt < c0 + 1.1 ? [-150, 20] : cheerR > 0 ? [-160, 10] : [-38, 4], armR: rich0 ? [60 + Math.sin(t * 4) * 15, 70] : lt < c0 + 1.1 ? [150, -20] : cheerR > 0 ? [160, -10] : [38, -4], jump: cheerR * 60 });
    if (rich.hat) rich.hat.setAttribute('opacity', lt < c0 + .2 ? 1 : 0);
    const hu = P(lt, c0 + .2, 1.4);
    at(hatFly, 540 + hu * 420, 650 - Math.sin(hu * Math.PI * .8) * 380 + hu * hu * 700, .66, hu * 720, hu > 0 && hu < 1 ? 1 : 0);
    at(sack, 450, 912, .8, 0, 1 - P(lt, c0, .3));
    coins.forEach((cn, i) => {
      const ph = (t * .9 + i / 6) % 1;
      const on = lt < c0;
      at(cn, 600 + Math.sin(i * 2) * 50, 760 + ph * 150, .9, ph * 300, on ? Math.sin(ph * Math.PI) : 0);
    });
    // равенство
    const ep = pop(lt, c0 + 1.05, .5);
    at(eq, 540, 1000 - Math.sin(t * 2) * 8, ep * (1 + .08 * pulse(lt, k[2], .05, .4)), (1 - ep) * -90, ep);
    burst.draw(lt, c0 + 1.05, 540, 1000, 220);
    // фабрика: частная → общая
    const fp = E.outCubic(P(lt, k[1] - .5, .6));
    at(fac.g, 820, 1190 + (1 - fp) * 260, .5, 0, fp);
    fac.smoke.forEach((s, i) => { const ph = (t * .4 + i / 5) % 1; at(s, 178 + ph * 60, -440 - ph * 260, .5 + ph * 1.3, 0, (1 - ph) * .7); });
    const open = P(lt, k[1] + .55, .4);
    shackle.setAttribute('transform', `translate(${n1(open * 20)} ${n1(-open * 24)}) rotate(${n1(open * 30)})`);
    const lf = P(lt, k[1] + .75, .6);
    at(lock, 180 + lf * 40, -80 + lf * lf * 260, .9, lf * 120, 1 - lf);
    const flip = P(lt, k[1] + .7, .3);
    fsTxt.textContent = flip > .5 ? 'UMUMIY' : 'XUSUSIY';
    fsTxt.setAttribute('fill', flip > .5 ? '#7CF0A0' : '#FFD27A');
    at(fsign, -60, -330, [1, Math.abs(Math.cos(flip * Math.PI))]);
    const go = E.outCubic(P(lt, k[1] + .9, .5));
    setA(fac.gateL, { transform: `translate(128 0) scale(${(1 - go).toFixed(3)} 1) translate(-128 0)` });
    setA(fac.gateR, { transform: `translate(232 0) scale(${(1 - go).toFixed(3)} 1) translate(-232 0)` });
    glow.setAttribute('opacity', go.toFixed(3));
    // солнце-цель
    const sr = E.inOutCubic(P(lt, k[2] - .2, 1.2));
    at(sun, 540, 1170 - sr * 300, 1 + sr * .5);
    at(rays, 540, 1170 - sr * 300, 1 + sr * .3, t * (6 + sr * 20), .6 + sr * .4);
    camSet(W, lt, [[0, 540, 990, 1.0], [c0 - .1, 540, 970, 1.03], [c0 + .9, 540, 1035, 1.1], [k[1] - .2, 540, 1035, 1.1], [k[1] + .4, 690, 1130, 1.25], [k[2] - .1, 690, 1130, 1.25], [k[2] + .7, 540, 1000, .98]],
      punches(lt, [c0, c0 + .6, k[1] + .6, k[2]]), pulse(lt, c0 + .5, .02, .5) * 22, t);
  } };
};

/* ============ SOTSIALIZM: общий склад, ресурсы — школе, больнице, людям ============ */
SCENES.share = (svg, col) => {
  const W = sv('g', null, svg);
  sky(W, '#3FA2EA', '#D2EEFF');
  sunEl(W, 860, 560, 80, '#FFE38A');
  const cls = [cloud(W, 200, 520, 1.2), cloud(W, 760, 700, .8), cloud(W, 480, 400, .7, '#fff', .7)];
  hills(W, 1170, '#A8DC8E', 70, 1); hills(W, 1210, '#86C96E', 50, 3);
  houseEl(W, 90, 1200, .45, '#F7E7CF', '#D2553F'); houseEl(W, 1000, 1195, .42, '#E9F1F7', '#3E7BE0');
  ground(W, 1215, '#84C765', '#2C6B37');
  const school = schoolEl(W, 175, 1310, .62), hosp = hospitalEl(W, 905, 1310, .62);
  const wins = [...school.querySelectorAll('.win'), ...hosp.querySelectorAll('.win')];
  const wh = warehouseEl(W, 540, 1225, .8, '#C2603F');
  wh.inside.innerHTML = [[-80, -40, 'sack'], [-20, -40, 'sack'], [50, -40, 'crate'], [-50, -120, 'crate'], [30, -115, 'sack'], [90, -100, 'coin']].map(([x, y, kd]) => `<g transform="translate(${x} ${y})">${kd === 'coin' ? PROP.coin(26) : PROP[kd]}</g>`).join('');
  const whLbl = svh(`<rect x="-110" y="-36" width="220" height="62" rx="12" fill="#F3E2C7"/><text y="10" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="32" fill="#8E3E26">OMBOR</text>`, wh.g); at(whLbl, 0, -300);
  const gear = prop(W, PROP.gear(70, col));
  const arrows = [[540, 1150, 220, 1170], [540, 1150, 880, 1170]].map(([x0, y0, x1, y1]) => sv('path', { d: `M${x0} ${y0 - 60} Q${(x0 + x1) / 2} ${y0 - 300} ${x1} ${y1 - 120}`, fill: 'none', stroke: '#fff', 'stroke-width': 10, 'stroke-dasharray': '24 20', 'stroke-linecap': 'round', opacity: 0 }, W));
  const items = Array.from({ length: 12 }, (_, i) => prop(W, i % 3 === 2 ? PROP.coin(26) : PROP[i % 3 ? 'crate' : 'sack']));
  const people = [0, 1, 2, 3].map(i => Char(W, { outfit: i === 1 ? 'dress' : i === 3 ? 'overalls' : 'shirt', female: i === 1, hairStyle: i === 1 ? 'long' : i === 2 ? 'curly' : 'short', top: ['#E5484D', '#B45CFF', '#2BB3A3', '#F4F4F4'][i], pants: i === 3 ? '#2F6BD8' : '#2B3046', skin: SKINS[[1, 0, 3, 2][i]], hair: HAIRS[i], seed: i + 3, kid: i === 2 }));
  const hearts = Array.from({ length: 8 }, () => prop(W, PROP.heart));
  const boss = Char(W, { outfit: 'shirt', top: col, hat: 'hardhat', skin: SKINS[1], seed: 9 });
  svh(PROP.clipboard, boss.hold).setAttribute('transform', 'scale(.8) rotate(90)');
  const stand = prop(W, `<rect x="-90" y="0" width="180" height="60" rx="10" fill="#6B4630"/><rect x="-90" y="0" width="180" height="16" rx="8" fill="#8E5A35"/>`);
  const px = [150, 360, 720, 930];
  return { update(lt, k, D, t) {
    cls.forEach((c, i) => c.setAttribute('transform', `translate(${n1(((i * 400 + t * 18) % 1500) - 200)} ${[520, 700, 400][i]}) scale(${[1.2, .8, .7][i]})`));
    const op = E.inOutCubic(P(lt, k[0] - .25, .6));
    wh.doorL.setAttribute('transform', `translate(-130 0) scale(${(1 - op * .92).toFixed(3)} 1) translate(130 0)`);
    wh.doorR.setAttribute('transform', `translate(130 0) scale(${(1 - op * .92).toFixed(3)} 1) translate(-130 0)`);
    // ресурсы разлетаются
    const tg = [[190, 1190], [880, 1190], ...px.map(x => [x, 1390])];
    items.forEach((it, i) => {
      const per = 1.8, ph = (lt - k[0] - i * .22) / per;
      const on = lt > k[0] + i * .22;
      const u = ((ph % 1) + 1) % 1;
      const [tx, ty] = tg[i % tg.length];
      const [x, y] = arcPt(E.inOutCubic(u), 540, 1140, tx, ty, 260);
      at(it, x, y, .8 - .25 * u, u * 200 * (i % 2 ? 1 : -1), on ? Math.min(1, Math.sin(Math.PI * u) * 3) : 0);
    });
    // люди
    people.forEach((p, i) => {
      const side = i < 2 ? -1 : 1;
      const wk = walkX(lt, .1 + i * .15, 1.1 + i * .15, px[i] + side * 400, px[i]);
      const ch = lt > k[1] ? Math.max(0, Math.sin((lt - k[1]) * 6 + i * 1.3)) : 0;
      p.draw({ x: wk.x, y: 1500, s: .56, t, walk: wk.walk, flip: side > 0, em: lt > k[1] ? 'grin' : 'smile', look: side > 0 ? 1 : -1,
        armL: ch > .3 ? [-160, 15] : lt > k[0] + .6 ? [-40, -90] : null, armR: ch > .3 ? [160, -15] : lt > k[0] + .6 ? [40, 90] : null, jump: ch * 40 });
    });
    const lit = P(lt, k[1], .4);
    wins.forEach((w, i) => w.setAttribute('fill', P(lt, k[1] + i * .05, .2) > .5 ? '#FFE27A' : '#BFE3FF'));
    hearts.forEach((h, i) => {
      const ph = ((lt - k[1]) * .6 + i / 8) % 1;
      const src = i < 4 ? [px[i], 1260] : [i % 2 ? 175 : 905, 1080];
      at(h, src[0] + Math.sin(ph * 6 + i) * 30, src[1] - ph * 280, .7 + ph * .3, 0, lt > k[1] + (i % 4) * .1 ? Math.sin(ph * Math.PI) * lit : 0);
    });
    // управляющий
    const bp = pop(lt, k[2] - .25, .5);
    at(stand, 540, 1480, bp, 0, bp);
    const pt = Math.floor((lt - k[2]) / .7) % 2;
    boss.draw({ x: 540, y: 1480, s: .6 * bp, t, op: bp, em: 'smile', talk: lt > k[2], look: lt > k[2] ? (pt ? 1 : -1) : 0,
      armL: lt > k[2] && !pt ? [-110, -10] : [-20, -60], armR: lt > k[2] && pt ? [110, 10] : [30, 70] });
    const gp = pop(lt, k[2], .5);
    at(gear, 540, 860, gp * .9, t * 50, gp);
    arrows.forEach(a => { a.setAttribute('opacity', (P(lt, k[2] + .2, .3) * .8).toFixed(3)); a.setAttribute('stroke-dashoffset', n1(-t * 80)); });
    camSet(W, lt, [[0, 540, 1040, 1.0], [k[0] - .1, 540, 1030, 1.08], [k[1] - .1, 540, 1060, 1.12], [k[2] - .2, 540, 1060, 1.12], [k[2] + .5, 540, 1040, 1.02]], punches(lt, [k[0], k[1], k[2]]), 0, t);
  } };
};

/* ============ DEMOKRATIYA: народ голосует, избранные — в парламенте ============ */
SCENES.ballot = (svg, col) => {
  const W = sv('g', null, svg);
  sky(W, '#2F6FE0', '#C4E2FF');
  const cls = [cloud(W, 200, 520, 1.1), cloud(W, 820, 620, .9), cloud(W, 520, 380, .6, '#fff', .7)];
  tree(W, 140, 1160, 1.1, '#3FA65A'); tree(W, 950, 1160, 1.2, '#2F9550');
  const parl = parliamentEl(W, 540, 1160, .62, '#EFE8DA', col);
  ground(W, 1150, '#DCE3EE', '#5D6B8C');
  svh(Array.from({ length: 9 }, (_, i) => `<path d="M540 1150 L${-900 + i * 360} 2200" stroke="#fff" stroke-width="3" opacity=".25"/>`).join('') + [1230, 1330, 1470, 1650].map(y => `<path d="M-300 ${y}H1400" stroke="#fff" stroke-width="3" opacity=".22"/>`).join(''), W);
  const reps = [0, 1, 2].map(i => Char(W, { outfit: 'suit', top: ['#2E3550', '#5B3550', '#2E5550'][i], female: i === 1, hairStyle: i === 1 ? 'bun' : 'side', skin: SKINS[i + 1], seed: 20 + i, tie: col }));
  const beams = [0, 1, 2].map(() => sv('path', { fill: 'none', stroke: '#FFE38A', 'stroke-width': 8, 'stroke-dasharray': '18 16', 'stroke-linecap': 'round' }, W));
  const voters = [0, 1, 2, 3, 4].map(i => Char(W, { outfit: ['shirt', 'dress', 'chapan', 'overalls', 'suit'][i], female: i === 1, hairStyle: ['short', 'long', 'short', 'curly', 'side'][i], hat: i === 2 ? 'doppi' : i === 3 ? 'cap' : null,
    top: ['#E5484D', '#F5A524', '#1F6FB5', '#EDEFF4', '#4A4F6A'][i], pants: i === 3 ? '#3A9A5B' : '#2B3046', skin: SKINS[i], hair: HAIRS[i], beard: i === 2 ? 'full' : null, seed: 30 + i }));
  voters.forEach(v => svh(PROP.ballot(col), v.hold).setAttribute('transform', 'scale(.6)'));
  const vb = voters.map(v => v.hold.firstChild);
  const flyB = voters.map(() => prop(W, PROP.ballot(col)));
  const table = prop(W, PROP.table, 540, 1430);
  const stack = sv('g', null, W);
  const sheets = Array.from({ length: 5 }, (_, i) => sv('rect', { x: -70, y: -14 - i * 18, width: 140, height: 16, rx: 4, fill: '#fff', stroke: '#D5DAE6', 'stroke-width': 2 }, stack));
  at(stack, 540, 1414);
  const box = prop(W, PROP.box(col), 540, 1418, .95);
  const crowd = [0, 1, 2, 3].map(i => Char(W, { outfit: i % 2 ? 'dress' : 'shirt', female: i % 2 === 1, hairStyle: i % 2 ? 'long' : 'short', top: ['#7CC24B', '#E5484D', '#F5A524', '#B45CFF'][i], skin: SKINS[(i + 2) % 5], hair: HAIRS[(i + 1) % 5], seed: 40 + i }));
  const ok = prop(W, PROP.check('#2BD46B'));
  const burst = sparkBurst(W, 10, '#FFE38A');
  return { update(lt, k, D, t) {
    cls.forEach((c, i) => c.setAttribute('transform', `translate(${n1(((i * 420 + t * 16) % 1500) - 200)} ${[520, 620, 380][i]}) scale(${[1.1, .9, .6][i]})`));
    waveFlag(parl.flag, parl.fx, parl.fy, 120, 74, t, 10);
    let dropped = 0;
    const span = Math.max(4.5, D - 1.5);
    const gap = span / 5.4;
    voters.forEach((v, i) => {
      const x = 120 + (lt - i * gap) * 210;
      const near = x > 330 && x < 470;
      const thrown = x >= 450;
      if (x > 480) dropped++;
      const u = P(x, 450, 60);
      v.draw({ x, y: 1395, s: .58, t, walk: lt * 9 + i, op: x > -150 && x < 1250 ? 1 : 0, em: 'smile', look: 1, armR: near ? [150, 20] : thrown && x < 620 ? [120, 30] : null });
      vb[i].style.display = thrown ? 'none' : '';
      const [bx, by] = arcPt(E.inQuad(u), 470, 1150, 540, 1270, 60);
      at(flyB[i], bx, by, .7, u * 90, u > 0 && u < 1 ? 1 : 0);
    });
    sheets.forEach((s, i) => s.setAttribute('opacity', i < dropped ? 1 : 0));
    // народ
    crowd.forEach((c, i) => {
      const p = pop(lt, k[0] - .2 + i * .08);
      const ch = Math.max(0, Math.sin((lt - k[0]) * 7 + i));
      c.draw({ x: [80, 200, 880, 1000][i], y: 1470, s: .5 * p, op: p, t, em: 'grin', look: i < 2 ? 1 : -1, armL: [-150 - ch * 20, 10], armR: [150 + ch * 20, -10], jump: ch * 30 * P(lt, k[0], .2) });
    });
    // избранные
    reps.forEach((r, i) => {
      const p = pop(lt, k[1] + i * .12);
      r.draw({ x: 440 + i * 100, y: 1135, s: .3 * p, op: p, t, em: 'grin', armR: [140 + Math.sin(t * 6 + i) * 20, 20] });
      const bp = P(lt, k[1] - .1 + i * .1, .5);
      beams[i].setAttribute('d', `M540 1270 Q${490 + i * 50} 1180 ${440 + i * 100} ${1135 - 135}`);
      beams[i].setAttribute('opacity', (bp * .9).toFixed(3));
      beams[i].setAttribute('stroke-dashoffset', n1(-t * 60));
    });
    const op = pop(lt, k[2] - .1, .5);
    at(ok, 850, 820 + Math.sin(t * 2) * 6, op * .9, (1 - op) * -60, op);
    burst.draw(lt, k[2], 850, 820, 200);
    camSet(W, lt, [[0, 540, 1000, 1.08], [k[0] - .1, 540, 1000, 1.08], [k[0] + .3, 540, 1010, 1.02], [k[1] - .3, 540, 1010, 1.02], [k[1] + .4, 540, 950, 1.18], [k[2] - .2, 540, 950, 1.18], [k[2] + .5, 600, 930, 1.02]],
      punches(lt, [k[0], k[1], k[2]]), 0, t);
  } };
};

/* ============ RESPUBLIKA: корона по наследству — нет, лидера выбирают ============ */
SCENES.crown = (svg, col) => {
  const root = sv('g', null, svg);
  // — дворец —
  const IN = sv('g', null, root);
  sv('rect', { x: -400, y: -400, width: 1880, height: 2800, fill: lin([[0, '#3A0D1A'], [1, '#6A1A2C']]) }, IN);
  svh(Array.from({ length: 8 }, (_, i) => `<rect x="${-100 + i * 180}" y="200" width="20" height="1200" fill="#7A2236" opacity=".6"/>`).join(''), IN);
  svh(`<path d="M-200 300 Q100 700 60 1500 L-200 1500Z" fill="#9E1B2F"/><path d="M1280 300 Q980 700 1020 1500 L1280 1500Z" fill="#9E1B2F"/><path d="M-200 280 H1280 V360 Q540 420 -200 360Z" fill="#C8243D"/>`, IN);
  ground(IN, 1340, '#7A1426', '#2A0610');
  sv('path', { d: 'M380 1340 L700 1340 L900 2000 L180 2000Z', fill: '#C8243D' }, IN);
  const throne = prop(IN, PROP.throne, 540, 1345, 1.05);
  const king = Char(IN, { outfit: 'king', hat: 'crown', beard: 'full', hair: '#D8D2C8', skin: SKINS[0], seed: 50, fat: .6 });
  const prince = Char(IN, { outfit: 'king', kid: true, hairStyle: 'short', hair: HAIRS[1], skin: SKINS[0], seed: 51 });
  const crownF = prop(IN, `<g transform="translate(0 130)">${'<path d="M-46 -104 L-54 -168 L-26 -134 L0 -180 L26 -134 L54 -168 L46 -104Z" fill="#F4C542" stroke="#B98516" stroke-width="4" stroke-linejoin="round"/><circle cx="0" cy="-122" r="8" fill="#D8343E"/>'}</g>`);
  const arcP = sv('path', { d: 'M540 960 Q680 760 800 1040', fill: 'none', stroke: '#FFE38A', 'stroke-width': 9, 'stroke-dasharray': '20 18', 'stroke-linecap': 'round' }, IN);
  const meros = prop(IN, `<rect x="-120" y="-40" width="240" height="72" rx="36" fill="#FFE38A"/><text y="12" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="34" fill="#5A1626">MEROS</text>`);
  const X = prop(IN, PROP.bigx);
  const halves = [prop(IN, '<path d="M-46 -26 L-54 -90 L-26 -56 L0 -102 L4 -26Z" fill="#F4C542" stroke="#B98516" stroke-width="4"/>'), prop(IN, '<path d="M4 -26 L0 -102 L26 -56 L54 -90 L46 -26Z" fill="#F4C542" stroke="#B98516" stroke-width="4"/>')];
  // — площадь —
  const OUT = sv('g', null, root);
  sky(OUT, '#138A80', '#BFF5EA');
  const cls = [cloud(OUT, 240, 560, 1.1), cloud(OUT, 860, 680, .8)];
  const parl = parliamentEl(OUT, 540, 1160, .6, '#F2ECE0', col);
  tree(OUT, 120, 1170, 1.1); tree(OUT, 960, 1170, 1.1, '#2F9550');
  ground(OUT, 1160, '#D9F2EA', '#4D7C78');
  const bar = svh(`<rect x="-200" y="-22" width="400" height="44" rx="22" fill="rgba(0,0,0,.25)"/><rect class="fill" x="-196" y="-18" width="0" height="36" rx="18" fill="#FFE38A"/><text y="-36" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="30" fill="#fff">SAYLOV</text>`, OUT);
  const fillR = bar.querySelector('.fill');
  const cand = Char(OUT, { outfit: 'suit', top: '#23324F', tie: col, skin: SKINS[1], hair: HAIRS[0], hairStyle: 'side', seed: 52 });
  const cand2 = Char(OUT, { outfit: 'suit', top: '#23324F', tie: col, skin: SKINS[1], hair: HAIRS[0], hairStyle: 'side', seed: 52, sash: col });
  const pod = prop(OUT, PROP.podium(col), 540, 1470, .95);
  const cits = [0, 1, 2, 3].map(i => Char(OUT, { outfit: ['dress', 'chapan', 'shirt', 'overalls'][i], female: i === 0, hairStyle: i === 0 ? 'long' : 'short', hat: i === 1 ? 'doppi' : i === 3 ? 'cap' : null, top: ['#E5484D', '#7A2BB5', '#F5A524', '#EDEFF4'][i], pants: i === 3 ? '#2F6BD8' : '#2B3046', skin: SKINS[(i + 1) % 5], hair: HAIRS[i], seed: 53 + i }));
  cits.forEach(c => svh(PROP.ballot(col), c.hold).setAttribute('transform', 'scale(.55)'));
  const flyB = Array.from({ length: 10 }, () => prop(OUT, PROP.ballot(col)));
  const conf = Array.from({ length: 30 }, (_, i) => sv('rect', { width: 14, height: 22, rx: 3, fill: ['#FFE38A', col, '#FF5C8A', '#fff', '#3D8BFF'][i % 5] }, OUT));
  return { update(lt, k, D, t) {
    const sw = E.inOutCubic(P(lt, k[0] + .9, .6));
    at(IN, 0, -sw * 1920, 1, 0, sw < 1 ? 1 : 0);
    at(OUT, 0, (1 - sw) * 1920, 1, 0, sw > .001 ? 1 : 0);
    if (sw < 1) {
      const shock = lt > k[0];
      king.draw({ x: 540, y: 1300, s: .72, t, sit: true, em: shock ? 'shock' : 'smile', talk: !shock && lt > .3, look: .6, armL: [-30, -50], armR: lt < 1.2 ? [70, 40] : [40, 50] });
      if (king.hat) king.hat.setAttribute('opacity', lt < .45 ? 1 : 0);
      prince.draw({ x: 800, y: 1360, s: .72, t, em: shock ? 'sad' : 'grin', look: -.7, lookY: -1 });
      const cu = E.inOutCubic(P(lt, .45, 1.2));
      const [cx, cy] = cu < 1 ? (() => { const a = 1 - cu; return [a * a * 540 + 2 * a * cu * 680 + cu * cu * 800, a * a * 960 + 2 * a * cu * 760 + cu * cu * 1050]; })() : [800, 1050 + Math.sin(t * 3) * 6];
      const broken = lt > k[0] + .25;
      at(crownF, cx, cy, .72, 0, broken ? 0 : 1);
      const fu = P(lt, k[0] + .25, .9);
      halves.forEach((h, i) => at(h, 800 + (i ? 1 : -1) * fu * 80, 1060 + fu * fu * 420, .72, (i ? 1 : -1) * fu * 70, broken && fu < 1 ? 1 : 0));
      arcP.setAttribute('stroke-dashoffset', n1(-t * 60));
      arcP.setAttribute('opacity', (P(lt, .4, .3) * (1 - P(lt, k[0] + .2, .3))).toFixed(3));
      const mp = pop(lt, .9);
      at(meros, 680, 760, mp, 0, mp);
      const xp = P(lt, k[0], .3);
      at(X, 680, 860, lerp(2.2, 1, E.outBack(xp)), 0, xp);
    }
    if (sw > 0) {
      cls.forEach((c, i) => c.setAttribute('transform', `translate(${n1(((i * 520 + t * 16) % 1500) - 200)} ${[560, 680][i]}) scale(${[1.1, .8][i]})`));
      waveFlag(parl.flag, parl.fx, parl.fy, 120, 74, t, 10);
      const pr = E.outCubic(P(lt, k[2] - .3, .8));
      at(parl.g, 540, 1160 + (1 - pr) * 700, .6, 0, pr);
      const vstart = Math.max(k[1] - .3, k[0] + 1.2);
      const vote = P(lt, vstart, Math.max(1.2, k[2] - vstart - .2));
      fillR.setAttribute('width', n1(392 * vote));
      at(bar, 540, 860, pop(lt, vstart - .3), 0, 1 - P(lt, k[2] + .6, .3));
      const won = lt > vstart + Math.max(1.2, k[2] - vstart - .2);
      [cand, cand2].forEach((c, i) => c.draw({ x: 540, y: 1440, s: .62, t, op: (i ? won : !won) ? 1 : 0, em: won ? 'grin' : 'smile', talk: !won && lt > k[0] + 1.4,
        armR: won ? [150 + Math.sin(t * 7) * 15, 20] : [60, 60], armL: won ? [-150, -10] : [-40, -40] }));
      cits.forEach((c, i) => {
        const x = [140, 290, 790, 940][i];
        const ph = ((lt - vstart) * 1.1 + i * .25) % 1;
        const throwing = lt > vstart && lt < vstart + 2.4;
        c.draw({ x, y: 1500, s: .55, t, em: 'grin', look: i < 2 ? 1 : -1, armR: throwing && ph < .5 ? [i < 2 ? 140 : -140, 20] : null, flip: i >= 2, jump: won ? Math.max(0, Math.sin(lt * 8 + i)) * 40 : 0 });
        c.hold.style.display = throwing && ph < .5 ? '' : 'none';
      });
      flyB.forEach((b, j) => {
        const i = j % 4, ph = ((lt - vstart) * 1.1 + i * .25 - Math.floor(j / 4) * .5);
        const u = P(ph % 1, .45, .5);
        const on = lt > vstart && lt < vstart + 2.6 && ph > 0;
        const x0 = [140, 290, 790, 940][i];
        const [x, y] = arcPt(u, x0, 1250, 540, 1180, 200);
        at(b, x, y, .55, u * 200, on && u > 0 && u < 1 ? 1 : 0);
      });
      conf.forEach((c, i) => {
        const u = P(lt, (won ? 0 : 99) + vstart + Math.max(1.2, k[2] - vstart - .2), 2.2);
        const a = i * 2.4;
        c.setAttribute('transform', `translate(${n1(540 + Math.cos(a) * 520 * E.outCubic(u))} ${n1(1000 - Math.sin(a) * 300 * E.outCubic(u) + u * u * 700)}) rotate(${n1(u * 720 + i * 30)})`);
        c.setAttribute('opacity', u > 0 && u < 1 ? 1 : 0);
      });
    }
    const inside = sw < .5;
    camSet(root, lt, inside ? [[0, 560, 1000, 1.1], [k[0] - .2, 640, 980, 1.18], [k[0] + .5, 640, 990, 1.1]] : [[0, 540, 1050, 1.05], [k[1], 540, 1060, 1.08], [k[2] - .2, 540, 1060, 1.08], [k[2] + .6, 540, 1000, .95]],
      punches(lt, [k[0], k[1], k[2]]), pulse(lt, k[0] + .05, .02, .45) * 26, t);
  } };
};

/* ============ MILLATCHILIK: флаг, культура, щит над родным городом ============ */
SCENES.shield = (svg, col) => {
  const W = sv('g', null, svg);
  sky(W, '#2E5FA8', '#FFC59A');
  sunEl(W, 760, 1000, 110, '#FFE2A0');
  mountains(W, 1130, '#7C8FC0', '#F2F4FA');
  hills(W, 1190, '#8FB98A', 40, 2);
  const mad = madrasaEl(W, 560, 1215, .56);
  tree(W, 60, 1230, 1.0, '#3E8E4E'); tree(W, 1010, 1230, 1.0, '#3E8E4E');
  ground(W, 1210, '#A6D27A', '#3B7639');
  const storms = [prop(W, PROP.stormcloud), prop(W, PROP.stormcloud)];
  const flashes = [0, 1].map(() => prop(W, `<circle r="70" fill="#fff" opacity=".9"/>`));
  sv('rect', { x: 196, y: 880, width: 14, height: 600, rx: 7, fill: '#E9EDF3' }, W);
  sv('circle', { cx: 203, cy: 876, r: 14, fill: '#F2C044' }, W);
  const flag = sv('path', { fill: col }, W), flagS = sv('path', { fill: '#fff', opacity: .95 }, W), flagS2 = sv('path', { fill: shade(col, .3) }, W);
  const items = ['lagan', 'non', 'atlas', 'dutar'].map(n => prop(W, PROP[n]));
  const ppl = [
    Char(W, { outfit: 'chapan', top: '#1F6FB5', hat: 'doppi', beard: 'full', hair: '#D8D2C8', skin: SKINS[1], seed: 60 }),
    Char(W, { outfit: 'dress', top: '#7A2BB5', female: true, hat: 'scarf', scarfColor: '#E9B949', skin: SKINS[0], hair: HAIRS[0], seed: 61 }),
    Char(W, { outfit: 'shirt', top: '#F4F4F4', kid: true, hat: 'doppi', skin: SKINS[1], seed: 62 }),
    Char(W, { outfit: 'chapan', top: '#2E9A6B', hat: 'doppi', beard: 'mustache', skin: SKINS[2], hair: HAIRS[0], seed: 63 }),
  ];
  svh(PROP.dutar, ppl[3].hold).setAttribute('transform', 'rotate(-120) scale(.7) translate(0 -40)');
  const dome = prop(W, PROP.dome(col));
  const burst = sparkBurst(W, 12, '#FFE38A');
  const burst2 = sparkBurst(W, 10, '#fff');
  const px = [400, 580, 740, 900];
  return { update(lt, k, D, t) {
    const up = E.inOutCubic(P(lt, .2, Math.max(1, k[1] - .2)));
    const big = E.outBack(P(lt, k[1], .6));
    const fw = 200 + 80 * big, fh = 124 + 50 * big, fy = lerp(1340, 900, up);
    waveFlag(flag, 210, fy, fw, fh, t, 12 + 6 * big);
    waveFlag(flagS, 210, fy + fh * .4, fw, fh * .2, t, 12 + 6 * big);
    waveFlag(flagS2, 210, fy + fh * .82, fw, fh * .18, t, 12 + 6 * big);
    burst.draw(lt, k[1], 320, fy + 60, 200);
    ppl.forEach((p, i) => {
      const ch = lt > k[1] ? Math.max(0, Math.sin((lt - k[1]) * 6 + i)) : 0;
      const strum = i === 3 && lt < k[1] + .1;
      p.draw({ x: px[i], y: 1490, s: .58, t, em: lt > k[1] ? 'grin' : 'smile', look: -.6, lookY: lt > .3 && lt < k[1] + 1 ? -1 : 0,
        armL: ch > .2 ? [-160, 10] : strum ? [-20, -100 + Math.sin(t * 18) * 14] : null, armR: ch > .2 ? [160, -10] : strum ? [60, 60] : null, jump: ch * 36 });
      if (i === 3) p.hold.style.display = ch > .2 ? 'none' : '';
    });
    items.forEach((it, i) => {
      const p = pop(lt, k[0] - .1 + i * .14);
      const a = Math.PI * (1.15 + i * .23);
      at(it, 600 + Math.cos(a) * 330 + 0, 1110 + Math.sin(a) * 170 + Math.sin(t * 2 + i) * 8, p * (i === 3 ? .55 : .85), Math.sin(t * 1.5 + i) * 6, p);
    });
    burst2.draw(lt, k[0], 600, 960, 220);
    const dp = E.outBack(P(lt, k[2] - .1, .8));
    at(dome, 560, 1460, [dp, dp], 0, dp > .001 ? 1 : 0);
    storms.forEach((s, i) => {
      const side = i ? 1 : -1;
      const u = P(lt, k[2] + .2, 1.6);
      const hit = .45;
      const d = u < hit ? E.inQuad(u / hit) : 1 - E.outCubic((u - hit) / (1 - hit)) * .7;
      at(s, 540 + side * lerp(820, 470, d), 940 + i * 50, .9, 0, u > .001 ? 1 : 0);
      at(flashes[i], 540 + side * 430, 960 + i * 50, 1 + pulse(u, hit, .02, .25), 0, pulse(u, hit, .02, .25));
    });
    camSet(W, lt, [[0, 560, 1020, 1.05], [k[0] - .2, 600, 1010, 1.12], [k[1] - .3, 600, 1010, 1.12], [k[1] + .3, 430, 1000, 1.15], [k[2] - .3, 430, 1000, 1.15], [k[2] + .5, 560, 1000, .92]],
      punches(lt, [k[0], k[1], k[2] + .2]), pulse(lt, k[2] + .2 + .72, .02, .4) * 18, t);
  } };
};

/* ============ SHOVINIZM: один на пьедестале, остальных принижает ============ */
SCENES.podium = (svg, col) => {
  const W = sv('g', null, svg);
  sky(W, '#140A26', '#5B2B7A');
  const clouds = [prop(W, PROP.stormcloud), prop(W, PROP.stormcloud), prop(W, PROP.stormcloud)];
  skyline(W, 1260, '#2A1640', 4, 100, 300, '#7A4DA8');
  ground(W, 1250, '#3A2350', '#0E0616');
  const spot = prop(W, PROP.spot('#F3E3FF'));
  const ped = prop(W, PROP.pedestal('#6A3D9A'));
  const others = [0, 1, 2, 3].map(i => Char(W, { outfit: ['shirt', 'dress', 'chapan', 'overalls'][i], female: i === 1, hairStyle: ['curly', 'long', 'short', 'short'][i], hat: i === 2 ? 'doppi' : i === 3 ? 'cap' : null, capColor: '#2BB3A3',
    top: ['#2BB3A3', '#F5A524', '#1F6FB5', '#EDEFF4'][i], pants: i === 3 ? '#C2563A' : '#2B3046', skin: SKINS[[3, 0, 1, 4][i]], hair: HAIRS[i], seed: 70 + i }));
  const hero = Char(W, { outfit: 'suit', top: '#8B2BD6', tie: '#F2C044', medal: true, skin: SKINS[0], hair: HAIRS[2], hairStyle: 'side', seed: 75 });
  svh(PROP.megaphone, hero.hold).setAttribute('transform', 'rotate(90) translate(10 0) scale(.9)');
  const waves = prop(W, PROP.waves('#F3E3FF'));
  const bubble = prop(W, PROP.bubble('MEN USTUNMAN!', '#fff', '#5B2B7A'));
  const arrows = [0, 1, 2, 3].map(() => prop(W, PROP.arrowDown()));
  const redTint = sv('rect', { x: -400, y: -400, width: 1880, height: 2800, fill: '#E5484D', opacity: 0 }, W);
  const stop = prop(W, PROP.stop);
  const ox = [150, 320, 760, 930];
  return { update(lt, k, D, t) {
    clouds.forEach((c, i) => at(c, ((i * 500 + t * 30) % 1600) - 300, 520 + i * 160, 1 + i * .2, 0, .9));
    const rise = E.outBack(P(lt, k[0] - .3, .9));
    const top = 1480 - 300 * rise;
    at(ped, 540, top + 2);
    at(spot, 540, top + 6, [1, 1], 0, rise);
    const shout = lt > k[0] + .7;
    const point = lt > k[1] - .1;
    hero.draw({ x: 540, y: top, s: .58 + .1 * rise, t, em: shout ? 'shout' : rise > .5 ? 'grin' : 'smile', talk: shout, look: point ? -.5 : 0, lean: shout ? -4 : 0,
      armR: shout ? [128, -30] : rise > .5 ? [40, 100] : null, armL: point ? [-60 + Math.sin(t * 8) * 6, 10] : rise > .5 ? [-40, -100] : null });
    hero.hold.style.display = shout ? '' : 'none';
    const wv = shout ? 1 : 0;
    at(waves, 700, top - 300, .9 + .15 * Math.sin(t * 14), 0, wv * (.5 + .5 * Math.abs(Math.sin(t * 7))));
    const bp = pop(lt, k[0] + .9, .4);
    at(bubble, 540, top - 470 + Math.sin(t * 3) * 6, bp * (1 + .05 * Math.sin(t * 12)), -3, bp * (1 - P(lt, k[1] + 1.2, .3)));
    const shrink = E.outCubic(P(lt, k[0] + 1.0, .7));
    others.forEach((c, i) => {
      const back = shrink * (i < 2 ? -40 : 40);
      const dn = point ? Math.sin(t * 8 + i) * .5 + .5 : 0;
      c.draw({ x: ox[i] + back, y: 1490, s: .58 - .12 * shrink, t, em: shrink > .3 ? 'sad' : lt > k[0] - .1 ? 'shock' : 'smile', look: i < 2 ? .6 : -.6, lookY: -1, lean: shrink * (i < 2 ? -6 : 6), tilt: shrink * (i < 2 ? -8 : 8), op: 1 - .35 * P(lt, k[1], .6) });
      at(arrows[i], ox[i] + back, 1150 + dn * 14, .9, 0, P(lt, k[1], .3) * (1 - P(lt, D - 1.4, .2)));
    });
    redTint.setAttribute('opacity', (P(lt, k[1], .5) * .14 + pulse(lt, D - 1.25, .02, .4) * .2).toFixed(3));
    const sp = P(lt, D - 1.3, .3);
    at(stop, 540, 1060, lerp(2.4, 1.15, E.outBack(sp)), -8 + sp * 8, sp);
    camSet(W, lt, [[0, 540, 1040, 1.05], [k[0] - .4, 540, 1040, 1.05], [k[0] + .4, 540, 960, 1.05], [k[1] - .3, 540, 980, 1.02], [k[1] + .3, 540, 1020, 1.0], [D, 540, 1020, 1.0]],
      punches(lt, [k[0], k[1], D - 1.25], .07), pulse(lt, D - 1.25, .02, .5) * 30 + (shout ? 3 : 0), t);
  } };
};

/* ============ KAPITALIZM: частный завод, рынок, конкуренция ============ */
SCENES.market = (svg, col) => {
  const W = sv('g', null, svg);
  sky(W, '#4AA8F5', '#E6F5FF');
  const cls = [cloud(W, 260, 520, 1.0), cloud(W, 840, 640, .8)];
  skyline(W, 1195, '#A9C2DE', 9, 200, 520, '#E8F3FF');
  skyline(W, 1205, '#8BA6C8', 13, 120, 330, '#F5FAFF');
  ground(W, 1200, '#A7AFBF', '#3D4456');
  sv('rect', { x: -400, y: 1200, width: 1880, height: 40, fill: '#C7CDD8' }, W);
  const fac = factoryEl(W, 300, 1240, .55, '#6F7E99');
  const xs = svh(`<rect x="-130" y="-40" width="260" height="72" rx="12" fill="${col}"/><text y="10" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="34" fill="#2A2000">XUSUSIY</text>`, fac.g); at(xs, -50, -330);
  const coins = Array.from({ length: 8 }, () => prop(W, PROP.coin(24)));
  const owner = Char(W, { outfit: 'suit', top: '#232A3D', tie: col, skin: SKINS[1], hair: HAIRS[0], hairStyle: 'side', glasses: true, seed: 80 });
  const key = svh(PROP.key, owner.hold); key.setAttribute('transform', 'rotate(-90) scale(.8)');
  const sellers = [0, 1].map(i => Char(W, { outfit: 'shirt', top: i ? '#3D8BFF' : '#E5484D', hat: 'cap', capColor: i ? '#1F5FC0' : '#B8323A', skin: SKINS[i ? 3 : 0], seed: 81 + i }));
  const stalls = [stallEl(W, 680, 1440, .56, '#E5484D'), stallEl(W, 925, 1440, .56, '#3D8BFF')];
  const shoppers = [0, 1, 2].map(i => Char(W, { outfit: i === 1 ? 'dress' : 'shirt', female: i === 1, hairStyle: ['short', 'bun', 'curly'][i], top: ['#7CC24B', '#FF5C8A', '#F5A524'][i], skin: SKINS[(i + 2) % 5], hair: HAIRS[i + 1], seed: 85 + i }));
  shoppers.forEach(s => svh(`<rect x="-20" y="0" width="40" height="44" rx="6" fill="#F3E2C7"/><path d="M-10 0 Q0 -18 10 0" stroke="#8E5A35" stroke-width="4" fill="none"/>`, s.hold));
  const chart = prop(W, `<rect x="-170" y="-140" width="340" height="250" rx="20" fill="#fff"/><path d="M-140 80 H140 M-140 80 V-110" stroke="#C5CBDA" stroke-width="6" stroke-linecap="round"/>`);
  const lA = sv('path', { fill: 'none', stroke: '#E5484D', 'stroke-width': 9, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, chart);
  const lB = sv('path', { fill: 'none', stroke: '#3D8BFF', 'stroke-width': 9, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, chart);
  const PRICES = [[10, 10], [10, 9], [8, 9], [8, 7], [6, 7], [6, 5]];
  return { update(lt, k, D, t) {
    cls.forEach((c, i) => c.setAttribute('transform', `translate(${n1(((i * 560 + t * 18) % 1500) - 200)} ${[520, 640][i]}) scale(${[1, .8][i]})`));
    fac.smoke.forEach((s, i) => { const ph = (t * .4 + i / 5) % 1; at(s, 178 + ph * 60, -440 - ph * 260, .5 + ph * 1.3, 0, (1 - ph) * .7); });
    const kp = lt > k[0] - .2;
    owner.draw({ x: 330, y: 1460, s: .62, t, em: kp ? 'grin' : 'smile', look: .4, talk: lt > .3 && lt < k[0], armR: kp ? [150, 20 + Math.sin(t * 9) * 10] : [40, 60], armL: [-40, -60] });
    key.style.display = kp ? '' : 'none';
    at(xs, -50, -330, 1 + .12 * pulse(lt, k[0] + .1, .05, .4));
    coins.forEach((c, i) => {
      const u = P(lt, k[0] + i * .12, .9);
      const [x, y] = arcPt(u, 300, 1080, 220 + i * 30, 1330, 260);
      at(c, x, y, .9, u * 360, u > 0 && u < 1 ? 1 : 0);
    });
    const sp = E.outBack(P(lt, k[1] - .2, .6));
    stalls.forEach((s, i) => {
      at(s.g, i ? 925 : 680, 1440 + (1 - sp) * 500, .56, 0, sp > .001 ? 1 : 0);
      const stage = Math.max(0, Math.min(PRICES.length - 1, Math.floor((lt - k[2]) / .55) + 1));
      const pr = lt < k[2] ? PRICES[0] : PRICES[stage];
      s.price.textContent = pr[i] + '$';
      const fl = lt > k[2] ? (((lt - k[2]) / .55) % 1) : 1;
      const changed = stage > 0 && PRICES[stage][i] !== PRICES[stage - 1][i];
      at(s.tag, 0, -380, [1, changed ? Math.abs(Math.cos(Math.min(1, fl / .3) * Math.PI)) : 1], changed ? Math.sin(fl * 20) * 6 * (1 - fl) : 0);
    });
    sellers.forEach((c, i) => {
      const loud = lt > k[2] && (Math.floor((lt - k[2]) / .55) % 2 === (i ? 0 : 1));
      c.draw({ x: i ? 925 : 680, y: 1440 + (1 - sp) * 500 - 70, s: .48, t, op: sp > .001 ? 1 : 0, em: loud ? 'shout' : 'smile', talk: loud, armR: loud ? [140, -20] : null, look: i ? -.4 : .4 });
    });
    shoppers.forEach((s, i) => {
      const x = -150 + ((lt - k[1] + .3) * 190 + i * 430) % 1500;
      s.draw({ x, y: 1530, s: .55, t, walk: lt * 9 + i, op: lt > k[1] - .3 ? 1 : 0, em: 'smile', look: 1 });
    });
    const cp = pop(lt, k[2] + .1);
    at(chart, 800, 840, cp * .95, 0, cp);
    const u = P(lt, k[2] + .2, Math.max(1.5, D - k[2] - .6));
    const line = (ph) => { let d = ''; for (let i = 0; i <= 20; i++) { const x = i / 20; if (x > u) break; d += (i ? 'L' : 'M') + n1(-130 + x * 260) + ' ' + n1(60 - x * 150 - Math.sin(x * 9 + ph) * 22); } return d || 'M0 0'; };
    lA.setAttribute('d', line(0)); lB.setAttribute('d', line(2.2));
    camSet(W, lt, [[0, 540, 1060, 1.05], [k[0] - .3, 380, 1060, 1.2], [k[1] - .3, 380, 1060, 1.2], [k[1] + .3, 640, 1080, 1.08], [k[2] - .2, 640, 1080, 1.08], [k[2] + .4, 620, 1040, 1.0]],
      punches(lt, [k[0], k[1], k[2]]), 0, t);
  } };
};

/* ============ SOTSIALIZM (2): общее благо, коллективный труд, государство ============ */
SCENES.gear = (svg, col) => {
  const W = sv('g', null, svg);
  sky(W, '#3B2A6B', '#FFB0C4');
  sunEl(W, 220, 900, 90, '#FFE0B0');
  const cls = [cloud(W, 700, 560, 1.0, '#FFD3E0', .6), cloud(W, 260, 680, .7, '#FFD3E0', .5)];
  hills(W, 1190, '#B48BC9', 60, 4);
  const glowB = sv('ellipse', { cx: 540, cy: 1000, rx: 520, ry: 340, fill: rad([[0, '#FFE38A', .7], [1, '#FFE38A', 0]]), opacity: 0 }, W);
  const gov = parliamentEl(W, 540, 1170, .55, '#F3E8F0', col);
  const bigGear = prop(W, PROP.gear(78, col));
  ground(W, 1170, '#D9C8E6', '#4E3D66');
  const school = schoolEl(W, 160, 1300, .56), hosp = hospitalEl(W, 920, 1300, .56);
  const kid = Char(W, { outfit: 'shirt', kid: true, top: '#F5A524', hairStyle: 'curly', skin: SKINS[3], seed: 90 });
  svh(`<rect x="-26" y="-30" width="52" height="60" rx="12" fill="#3D8BFF"/>`, kid.hold);
  const nurse = Char(W, { outfit: 'dress', top: '#fff', female: true, hat: 'nurse', hairStyle: 'bun', skin: SKINS[0], hair: HAIRS[1], seed: 91 });
  const roll = prop(W, PROP.gear(110, '#9AA3B5'));
  const team = [0, 1, 2, 3].map(i => Char(W, { outfit: 'overalls', top: ['#EDEFF4', '#F5E6C8', '#EDEFF4', '#F5E6C8'][i], pants: ['#2F6BD8', '#3A9A5B', '#C2563A', '#7A2BB5'][i], hat: 'hardhat', skin: SKINS[i], female: i === 2, hairStyle: i === 2 ? 'bun' : 'short', seed: 92 + i }));
  const offi = Char(W, { outfit: 'suit', top: '#3A2A55', tie: col, skin: SKINS[1], hair: HAIRS[0], hairStyle: 'side', seed: 96 });
  const cits = [0, 1, 2].map(i => Char(W, { outfit: ['dress', 'chapan', 'shirt'][i], female: i === 0, hairStyle: i === 0 ? 'long' : 'short', hat: i === 1 ? 'doppi' : null, top: ['#2BB3A3', '#1F6FB5', '#E5484D'][i], skin: SKINS[(i + 2) % 5], hair: HAIRS[i], seed: 97 + i }));
  const crates = Array.from({ length: 6 }, () => prop(W, PROP.crate));
  return { update(lt, k, D, t) {
    cls.forEach((c, i) => c.setAttribute('transform', `translate(${n1(((i * 600 + t * 15) % 1500) - 200)} ${[560, 680][i]}) scale(${[1, .7][i]})`));
    waveFlag(gov.flag, gov.fx, gov.fy, 120, 74, t, 10);
    const gp = pop(lt, .1, .6);
    at(bigGear, 540, 930, gp * .85, t * 40, gp);
    const bp = E.outBack(P(lt, k[0] - .3, .7));
    at(school, 160, 1300 + (1 - bp) * 500, .56, 0, bp > .001 ? 1 : 0);
    at(hosp, 920, 1300 + (1 - bp) * 500, .56, 0, bp > .001 ? 1 : 0);
    const kw = walkX(lt, k[0] + .3, k[0] + 2.2, 420, 190);
    kid.draw({ x: kw.x, y: 1330, s: .62, t, walk: kw.walk, flip: true, op: bp * (1 - P(lt, k[0] + 2.1, .2)), em: 'grin', armR: [10, 40] });
    nurse.draw({ x: 820, y: 1330, s: .5, t, op: bp, em: 'smile', armR: [150 + Math.sin(t * 7) * 18, 10], look: -.5 });
    // коллективный труд
    const ru = P(lt, k[1] - .4, Math.max(2.2, k[2] - k[1] + .6));
    const gx = lerp(-260, 1350, ru);
    at(roll, gx, 1330, 1, ru * 900, ru > 0 && ru < 1 ? 1 : 0);
    team.forEach((c, i) => c.draw({ x: gx - 170 - i * 105, y: 1450, s: .5, t, walk: lt * 11 + i, lean: 14, em: 'grin', armL: [100, -10], armR: [110, -10], op: ru > 0 && ru < 1 ? 1 : 0 }));
    // государство раздаёт
    const sp = P(lt, k[2] - .3, .5);
    glowB.setAttribute('opacity', (sp * (.7 + .3 * Math.sin(t * 4))).toFixed(3));
    const op = pop(lt, k[2] - .3);
    offi.draw({ x: 540, y: 1300, s: .5 * op, op, t, em: 'smile', talk: lt > k[2], armR: [100 + Math.sin(t * 5) * 20, 10], armL: [-100 - Math.sin(t * 5) * 20, -10] });
    cits.forEach((c, i) => {
      const p = pop(lt, k[2] - .1 + i * .1);
      const got = lt > k[2] + .5 + i * .35;
      c.draw({ x: [260, 540, 820][i], y: 1490, s: .54 * p, op: p, t, em: got ? 'grin' : 'smile', look: [.6, 0, -.6][i], lookY: -1, armL: got ? [-120, -40] : null, armR: got ? [120, 40] : null, jump: got ? Math.max(0, Math.sin(lt * 7 + i)) * 24 : 0 });
    });
    crates.forEach((c, j) => {
      const i = j % 3, u = P(lt, k[2] + .1 + i * .35 + Math.floor(j / 3) * 1.1, .55);
      const [x, y] = arcPt(E.inOutCubic(u), 540, 1200, [260, 540, 820][i], 1290, 220);
      at(c, x, y, .55, u * 180, u > 0 && u < 1 ? 1 : 0);
    });
    camSet(W, lt, [[0, 540, 1000, 1.0], [k[0] - .3, 540, 1020, 1.05], [k[1] - .4, 540, 1040, 1.05], [k[1] + .4, 480, 1060, 1.1], [k[2] - .4, 480, 1060, 1.1], [k[2] + .3, 540, 1030, 1.02]],
      punches(lt, [k[0], k[1], k[2]]), 0, t);
  } };
};

/* ============ ИНТРО: люди путаются в словах ============ */
SCENES.intro = (svg) => {
  const W = sv('g', null, svg);
  sky(W, '#120B2E', '#5A2A6E');
  skyline(W, 1350, '#24154A', 5, 160, 520, '#FFC86B');
  skyline(W, 1370, '#311C5C', 8, 100, 300, '#FFD98A');
  ground(W, 1360, '#2A1A48', '#0B0618');
  const ppl = [0, 1, 2, 3, 4].map(i => Char(W, { outfit: ['suit', 'dress', 'chapan', 'overalls', 'shirt'][i], female: i === 1, hairStyle: ['side', 'long', 'short', 'short', 'curly'][i], hat: i === 2 ? 'doppi' : i === 3 ? 'hardhat' : null,
    top: ['#3A4566', '#FF5C8A', '#1F6FB5', '#EDEFF4', '#F5A524'][i], pants: i === 3 ? '#2F6BD8' : '#2B3046', skin: SKINS[[0, 1, 2, 3, 4][i]], hair: HAIRS[i], beard: i === 2 ? 'mustache' : null, glasses: i === 0, seed: 100 + i }));
  const qs = ppl.map(() => prop(W, PROP.qmark));
  const words = ['Kommunizm?', 'Respublika?', 'Shovinizm?', 'Sotsializm?', 'Demokratiya?'];
  const bubbles = words.map((w, i) => prop(W, `<rect x="-${w.length * 13 + 24}" y="-40" width="${w.length * 26 + 48}" height="72" rx="36" fill="#fff"/><path d="M-10 30 L0 54 L14 30Z" fill="#fff"/><text y="10" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="30" fill="${['#FF4D5E', '#1FD1B2', '#B45CFF', '#FFB020', '#3D8BFF'][i]}">${w}</text>`));
  const px = [120, 330, 540, 750, 960];
  return { update(lt, k, D, t) {
    ppl.forEach((p, i) => {
      const pp = pop(lt, .2 + i * .1);
      const conf = lt > 1;
      p.draw({ x: px[i], y: 1360, s: .58 * pp, op: pp, t, em: conf ? (i % 2 ? 'shock' : 'sad') : 'smile', look: Math.sin(t * 1.5 + i * 2), tilt: conf ? Math.sin(t * 2 + i) * 8 : 0,
        armR: conf && i % 2 === 0 ? [170, 40 + Math.sin(t * 12 + i) * 15] : null, armL: conf && i % 2 ? [-60, -60] : null });
      const qp = pop(lt, 1.1 + i * .15);
      at(qs[i], px[i] + Math.sin(t * 2 + i) * 10, 1050 - Math.abs(Math.sin(t * 3 + i)) * 20, qp * .8, Math.sin(t * 2 + i) * 12, qp * (1 - P(lt, D - .5, .3)));
    });
    bubbles.forEach((b, i) => {
      const t0 = 1.6 + i * .55, p = pop(lt, t0, .35), out = P(lt, t0 + 1.2, .2);
      at(b, Math.min(860, Math.max(220, px[i])), 1010 - (i % 2) * 60, p * (1 - out) * .95, (i % 2 ? 4 : -4), p * (1 - out));
    });
    camSet(W, lt, [[0, 540, 975, 1.1], [D, 540, 1000, 1.16]], 0, 0, t);
  } };
};

/* ============ ФИНАЛ: машут на прощание ============ */
SCENES.outro = (svg) => {
  const W = sv('g', null, svg);
  sky(W, '#0C0A1E', '#2A1650');
  svh(RAYS('rgba(255,255,255,.035)', 20), W).setAttribute('transform', 'translate(540 1900)');
  const ppl = [0, 1, 2, 3, 4].map(i => Char(W, { outfit: ['overalls', 'dress', 'chapan', 'suit', 'shirt'][i], female: i === 1, hairStyle: ['short', 'long', 'short', 'side', 'curly'][i], hat: ['hardhat', null, 'doppi', null, 'cap'][i],
    top: ['#EDEFF4', '#FF5C8A', '#1F6FB5', '#3A4566', '#2BB3A3'][i], pants: i === 0 ? '#2F6BD8' : '#2B3046', skin: SKINS[i], hair: HAIRS[i], seed: 110 + i }));
  return { update(lt, k, D, t) {
    ppl.forEach((p, i) => {
      const pp = pop(lt, .3 + i * .1, .5);
      p.draw({ x: 140 + i * 200, y: 1890 + (1 - pp) * 300, s: .62, t, em: 'grin', look: (2 - i) * .3, armR: [150 + Math.sin(t * 8 + i) * 22, 20], jump: Math.max(0, Math.sin(t * 5 + i)) * 20 });
    });
  } };
};
