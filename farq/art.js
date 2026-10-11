/* Рисованная библиотека: персонажи-марионетки, здания, предметы, пейзажи (SVG).
   Всё создаётся один раз, а каждый кадр меняются только атрибуты. Координаты сцены 1080×1920. */
'use strict';

const NS = 'http://www.w3.org/2000/svg';
function sv(tag, a, p) {
  const e = document.createElementNS(NS, tag);
  if (a) for (const k in a) e.setAttribute(k, a[k]);
  if (p) p.appendChild(e);
  return e;
}
function setA(e, a) { for (const k in a) e.setAttribute(k, a[k]); }
/* кусок разметки в группу; возвращает группу */
function svh(html, p, a) {
  const g = sv('g', a, p);
  g.innerHTML = html;
  return g;
}
const n1 = v => (+v).toFixed(1);
/* положение группы */
function at(e, x, y, s = 1, r = 0, op) {
  const sx = Array.isArray(s) ? s[0] : s, sy = Array.isArray(s) ? s[1] : s;
  e.setAttribute('transform', `translate(${n1(x)} ${n1(y)}) rotate(${n1(r)}) scale(${sx.toFixed(4)} ${sy.toFixed(4)})`);
  if (op != null) {
    const o = Math.max(0, Math.min(1, op));
    e.setAttribute('opacity', o.toFixed(3));
    e.style.display = o <= 0.001 ? 'none' : '';
  }
}
let UID = 0;
const uid = p => p + (++UID);
/* градиенты в общий <defs> */
let DEFS;
function lin(stops, x1 = 0, y1 = 0, x2 = 0, y2 = 1) {
  const id = uid('g');
  DEFS.insertAdjacentHTML('beforeend', `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join('')}</linearGradient>`);
  return `url(#${id})`;
}
function rad(stops, cx = .5, cy = .5, r = .5) {
  const id = uid('r');
  DEFS.insertAdjacentHTML('beforeend', `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}">${stops.map(([o, c, a]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a == null ? 1 : a}"/>`).join('')}</radialGradient>`);
  return `url(#${id})`;
}
function pattern(w, h, body) {
  const id = uid('p');
  DEFS.insertAdjacentHTML('beforeend', `<pattern id="${id}" width="${w}" height="${h}" patternUnits="userSpaceOnUse">${body}</pattern>`);
  return `url(#${id})`;
}
function dmix(a, b, k) {
  const ha = a.match(/\w\w/g).map(x => parseInt(x, 16)), hb = b.match(/\w\w/g).map(x => parseInt(x, 16));
  return '#' + ha.map((v, i) => Math.round(v + (hb[i] - v) * k).toString(16).padStart(2, '0')).join('');
}
const shade = (c, k = .25) => dmix(c, '#000000', k);
const tint = (c, k = .25) => dmix(c, '#ffffff', k);
const D2R = Math.PI / 180;

/* =====================================================================
   ПЕРСОНАЖ: ступни в (0,0), рост ≈ 440. Позу задаёт draw(p) каждый кадр.
   ===================================================================== */
const SKINS = ['#F3CDA6', '#E4AE80', '#C98D60', '#9A6440', '#F6D9BC'];
const HAIRS = ['#2A1B12', '#5A3A22', '#141418', '#8A5A2B', '#C9C2B8'];

function Char(parent, opt) {
  const o = Object.assign({
    skin: SKINS[0], hair: HAIRS[0], hairStyle: 'short', top: '#3E7BE0', pants: '#2B3046', shoe: '#1B1B24',
    outfit: 'shirt', hat: null, beard: null, glasses: false, tie: '#D8343E', female: false, fat: 0, kid: false,
  }, opt);
  const g = sv('g', null, parent);
  const shadow = sv('ellipse', { rx: 66, ry: 12, fill: 'rgba(0,0,0,.28)' }, g);
  const limb = (c, w) => sv('path', { fill: 'none', stroke: c, 'stroke-width': w, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, g);
  const legW = o.female ? 24 : 30 + o.fat * 6;
  const legs = [limb(o.pants, legW), limb(o.pants, legW)];
  const shoes = [0, 1].map(() => sv('path', { fill: o.shoe }, g));
  const cape = sv('g', null, g);
  const armB = limb(o.top, 25 + o.fat * 4), handB = sv('circle', { r: 14, fill: o.skin }, g);
  const body = sv('g', null, g);
  const head = sv('g', null, g);
  const armF = limb(o.top, 25 + o.fat * 4), handF = sv('circle', { r: 14, fill: o.skin }, g);
  const hold = sv('g', null, g);
  const W = 44 + o.fat * 22;           // полуширина торса у плеч
  const sleeve = o.sleeve || (o.outfit === 'king' ? '#C8243D' : o.outfit === 'chapan' ? shade(o.top, .1) : o.top);
  armB.setAttribute('stroke', sleeve); armF.setAttribute('stroke', sleeve);
  const sk = shade(o.top, .18);

  // — торс (0,0 — таз, вверх отрицательно; плечи на −125) —
  let torso = '';
  const trunk = (c, w0 = W - 4, w1 = W) => `<path d="M${-w0} 6 L${-w1} -108 Q${-w1} -130 ${-w1 + 20} -132 L${w1 - 20} -132 Q${w1} -130 ${w1} -108 L${w0} 6 Q0 14 ${-w0} 6Z" fill="${c}"/>`;
  const side = `<path d="M${W - 18} -128 Q${W} -126 ${W} -108 L${W - 4} 6 Q${W / 2} 11 ${W / 2 - 6} 8 Q${W - 12} -50 ${W - 18} -128Z" fill="#000" opacity=".14"/>`;
  if (o.outfit === 'suit') {
    torso = trunk(o.top) + `<path d="M-15 -132 L0 -84 L15 -132Z" fill="#F4F4F6"/>` +
      (o.tie ? `<path d="M-6 -126 L6 -126 L9 -80 L0 -66 L-9 -80Z" fill="${o.tie}"/>` : '') +
      `<path d="M-15 -132 L-4 -78 L-26 -100Z M15 -132 L4 -78 L26 -100Z" fill="${sk}"/><circle cx="0" cy="-44" r="4" fill="${sk}"/><circle cx="0" cy="-22" r="4" fill="${sk}"/>` + side;
  } else if (o.outfit === 'overalls') {
    torso = trunk(o.top) + `<path d="M${-W + 10} 6 L${-W + 12} -70 L${W - 12} -70 L${W - 10} 6 Q0 14 ${-W + 10} 6Z" fill="${o.pants}"/>` +
      `<path d="M${-W + 14} -70 L${-W + 20} -130 M${W - 14} -70 L${W - 20} -130" stroke="${o.pants}" stroke-width="11"/>` +
      `<circle cx="${-W + 18}" cy="-66" r="5" fill="#E8C35A"/><circle cx="${W - 18}" cy="-66" r="5" fill="#E8C35A"/><rect x="-16" y="-50" width="32" height="22" rx="4" fill="${shade(o.pants, .15)}"/>` + side;
  } else if (o.outfit === 'dress') {
    torso = `<path d="M-30 -20 L-74 96 Q0 112 74 96 L30 -20Z" fill="${shade(o.top, .05)}"/>` + trunk(o.top, W - 12, W - 4) +
      `<path d="M-30 -24 Q0 -16 30 -24 L32 -12 Q0 -4 -32 -12Z" fill="${shade(o.top, .3)}"/>` + side;
  } else if (o.outfit === 'chapan') {
    const p = pattern(26, 26, `<rect width="26" height="26" fill="${o.top}"/><rect width="6" height="26" fill="${tint(o.top, .45)}"/><rect x="13" width="4" height="26" fill="#E9B949"/>`);
    torso = `<path d="M${-W - 2} 104 L${-W - 4} -108 Q${-W - 4} -132 ${-W + 18} -134 L${W - 18} -134 Q${W + 4} -132 ${W + 4} -108 L${W + 2} 104 Q0 112 ${-W - 2} 104Z" fill="${p}"/>` +
      `<path d="M-10 -134 L0 104 L10 -134Z" fill="#F2EEE2"/><path d="M${-W} -46 L${W} -46 L${W} -30 L${-W} -30Z" fill="#C8352F"/>` + side;
  } else if (o.outfit === 'king') {
    cape.innerHTML = `<path d="M-60 -128 Q-96 0 -92 108 Q0 124 92 108 Q96 0 60 -128Z" fill="#9E1B2F"/><path d="M-92 108 Q0 124 92 108 L92 96 Q0 112 -92 96Z" fill="#F3F0EA"/>`;
    torso = trunk('#C8243D') + `<path d="M-34 -136 Q0 -118 34 -136 L36 -116 Q0 -98 -36 -116Z" fill="#F6F2EA"/>` +
      [-20, -6, 8, 22].map(x => `<circle cx="${x}" cy="-118" r="3" fill="#1A1A1A"/>`).join('') +
      `<path d="M-6 -100 L6 -100 L6 6 L-6 6Z" fill="#E9B949"/>` + side;
  } else {
    torso = trunk(o.top) + `<path d="M-16 -132 Q0 -112 16 -132Z" fill="${shade(o.top, .25)}"/>` + side;
  }
  if (o.sash) torso += `<path d="M${-W + 6} -126 L${W - 4} -10 L${W - 12} 4 L${-W} -110Z" fill="${o.sash}"/>`;
  if (o.medal) torso += `<circle cx="-18" cy="-92" r="11" fill="#F2C044" stroke="#B98516" stroke-width="3"/><path d="M-24 -116 L-18 -102 L-12 -116Z" fill="#D8343E"/>`;
  body.innerHTML = torso;

  // — голова (0,0 — шея) —
  const hs = o.kid ? 1.12 : 1;
  let hb = '', hf = '';
  const hc = o.hair;
  if (o.hairStyle === 'long') hb = `<path d="M-52 -60 Q-60 -130 0 -118 Q60 -130 52 -60 L56 10 Q30 22 30 -10 L-30 -10 Q-30 22 -56 10Z" fill="${hc}"/>`;
  if (o.hairStyle === 'bun') hb = `<circle cx="0" cy="-118" r="24" fill="${hc}"/>`;
  const hairFront = {
    short: `<path d="M-49 -58 Q-54 -118 0 -116 Q54 -118 49 -58 Q44 -86 18 -90 Q-10 -80 -30 -88 Q-46 -80 -49 -58Z" fill="${hc}"/>`,
    side: `<path d="M-49 -56 Q-56 -120 4 -118 Q56 -116 49 -60 Q42 -92 -6 -94 Q-34 -92 -49 -56Z" fill="${hc}"/><path d="M-6 -94 Q-30 -96 -40 -72" stroke="${shade(hc, .3)}" stroke-width="4" fill="none"/>`,
    long: `<path d="M-50 -54 Q-56 -122 0 -118 Q56 -122 50 -54 Q36 -96 0 -98 Q-36 -96 -50 -54Z" fill="${hc}"/>`,
    bun: `<path d="M-49 -60 Q-52 -114 0 -112 Q52 -114 49 -60 Q30 -96 0 -98 Q-30 -96 -49 -60Z" fill="${hc}"/>`,
    curly: [[-34, -96], [-14, -108], [8, -110], [30, -100], [44, -80], [-46, -76]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="20" fill="${hc}"/>`).join(''),
    bald: `<path d="M-49 -50 Q-50 -66 -42 -74 M49 -50 Q50 -66 42 -74" stroke="${hc}" stroke-width="10" stroke-linecap="round" fill="none"/>`,
  }[o.hairStyle] || '';
  hf = hairFront;
  const hats = {
    tophat: `<rect x="-62" y="-112" width="124" height="14" rx="7" fill="#15151B"/><path d="M-40 -110 L-36 -196 Q0 -204 36 -196 L40 -110Z" fill="#1E1E26"/><rect x="-39" y="-132" width="78" height="14" fill="#9E1B2F"/>`,
    crown: `<path class="crn" d="M-46 -104 L-54 -168 L-26 -134 L0 -180 L26 -134 L54 -168 L46 -104Z" fill="#F4C542" stroke="#B98516" stroke-width="4" stroke-linejoin="round"/><circle cx="0" cy="-122" r="8" fill="#D8343E"/><circle cx="-30" cy="-118" r="6" fill="#3E7BE0"/><circle cx="30" cy="-118" r="6" fill="#3E7BE0"/>`,
    hardhat: `<path d="M-54 -84 Q-54 -146 0 -146 Q54 -146 54 -84Z" fill="#F4B728"/><rect x="-64" y="-90" width="128" height="14" rx="7" fill="#E09A12"/><rect x="-6" y="-146" width="12" height="58" rx="5" fill="#FFD25E"/>`,
    doppi: `<path d="M-50 -82 L-44 -134 Q0 -146 44 -134 L50 -82 Q0 -92 -50 -82Z" fill="#17171C"/>` +
      [[-26, -112], [0, -118], [26, -112]].map(([x, y]) => `<path d="M${x} ${y - 13} Q${x + 11} ${y} ${x} ${y + 12} Q${x - 11} ${y} ${x} ${y - 13}Z" fill="#F3F0E6"/>`).join(''),
    cap: `<path d="M-50 -80 Q-52 -136 0 -136 Q52 -136 50 -80Z" fill="${o.capColor || '#D8343E'}"/><path d="M10 -84 Q62 -92 78 -78 Q50 -70 10 -76Z" fill="${shade(o.capColor || '#D8343E', .25)}"/>`,
    scarf: `<path d="M-54 -50 Q-60 -132 0 -128 Q60 -132 54 -50 Q58 10 34 6 Q40 -40 36 -70 Q0 -104 -36 -70 Q-40 -40 -34 6 Q-58 10 -54 -50Z" fill="${o.scarfColor || '#C8352F'}"/>`,
    nurse: `<path d="M-40 -100 L-34 -132 L34 -132 L40 -100Z" fill="#fff"/><path d="M-6 -126h12v6h6v12h-6v6h-12v-6h-6v-12h6Z" fill="#E5484D"/>`,
  };
  const face = sv('g', null, head);
  face.innerHTML = `${hb}<rect x="-12" y="-16" width="24" height="22" fill="${shade(o.skin, .12)}"/>
    <circle cx="-46" cy="-50" r="11" fill="${shade(o.skin, .06)}"/><circle cx="46" cy="-50" r="11" fill="${shade(o.skin, .06)}"/>
    <ellipse cx="0" cy="-56" rx="47" ry="53" fill="${o.skin}"/>
    <path d="M18 -100 Q47 -90 47 -56 Q47 -16 10 -3 Q34 -30 32 -60 Q30 -88 18 -100Z" fill="#000" opacity=".07"/>`;
  const cheeks = sv('g', { opacity: .28 }, head);
  cheeks.innerHTML = `<ellipse cx="-28" cy="-36" rx="10" ry="6" fill="#FF5A6A"/><ellipse cx="28" cy="-36" rx="10" ry="6" fill="#FF5A6A"/>`;
  const eyes = [0, 1].map(() => {
    const e = sv('g', null, head);
    const w = sv('ellipse', { rx: 9.5, ry: 11.5, fill: '#fff' }, e);
    const pu = sv('circle', { r: 6, fill: '#1A1414' }, e);
    const gl = sv('circle', { r: 2, fill: '#fff' }, e);
    return { e, w, pu, gl };
  });
  const brows = [0, 1].map(() => sv('path', { stroke: shade(hc, .1), 'stroke-width': 5.5, 'stroke-linecap': 'round', fill: 'none' }, head));
  const nose = sv('path', { fill: shade(o.skin, .18) }, head);
  const mouth = sv('path', { fill: '#5A1E24', stroke: '#5A1E24', 'stroke-width': 4, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }, head);
  const teeth = sv('path', { fill: '#fff' }, head);
  if (o.beard === 'full') svh(`<path d="M-46 -48 Q-46 4 0 10 Q46 4 46 -48 Q36 -18 0 -20 Q-36 -18 -46 -48Z" fill="${o.hair}"/>`, head);
  const must = o.beard === 'mustache' || o.beard === 'full' ? sv('path', { fill: shade(o.hair, .05) }, head) : null;
  if (o.glasses) svh(`<g fill="none" stroke="#1E1E22" stroke-width="4"><circle cx="-18" cy="-58" r="14"/><circle cx="18" cy="-58" r="14"/><path d="M-4 -60h8"/></g>`, head);
  svh(hf, head);
  const hat = o.hat ? svh(hats[o.hat] || '', head) : null;

  let blinkSeed = (o.seed || 1) * 1.7;
  function draw(p) {
    const s = (p.s || 1) * (o.kid ? .72 : 1);
    const flip = p.flip ? -1 : 1;
    g.setAttribute('transform', `translate(${n1(p.x)} ${n1(p.y)}) scale(${(s * flip).toFixed(4)} ${s.toFixed(4)})`);
    if (p.op != null) { g.setAttribute('opacity', Math.max(0, Math.min(1, p.op)).toFixed(3)); g.style.display = p.op <= .001 ? 'none' : ''; }
    const t = p.t || 0;
    const jump = p.jump || 0;
    const wa = p.walk ? (p.wamp == null ? 1 : p.wamp) : 0, ph = (p.walk || 0);
    const breath = Math.sin(t * 2.2 + blinkSeed) * 2;
    const bob = wa ? -Math.abs(Math.cos(ph)) * 9 * wa : breath;
    const hipY = -172 - jump + bob + (p.squash || 0);
    shadow.setAttribute('rx', (66 * (1 - Math.min(.5, jump / 400))).toFixed(1));
    shadow.setAttribute('cy', (jump > 0 ? 0 : 0));
    // ноги
    for (let i = 0; i < 2; i++) {
      const lp = ph + i * Math.PI;
      let t1 = wa * .48 * Math.sin(lp), t2 = -wa * .75 * Math.max(0, Math.sin(lp + 1.3));
      if (p.legs) { t1 += p.legs[i][0] * D2R; t2 += p.legs[i][1] * D2R; }
      if (p.sit) { t1 = (i ? 82 : 78) * D2R; t2 = -86 * D2R; }
      const hx = i ? 17 : -17, L = 86;
      const kx = hx + L * Math.sin(t1), ky = hipY + L * Math.cos(t1);
      const ax = kx + L * Math.sin(t1 + t2), ay = ky + L * Math.cos(t1 + t2);
      legs[i].setAttribute('d', `M${n1(hx)} ${n1(hipY)}L${n1(kx)} ${n1(ky)}L${n1(ax)} ${n1(ay)}`);
      shoes[i].setAttribute('d', `M${n1(ax - 16)} ${n1(ay - 8)}Q${n1(ax + 4)} ${n1(ay - 18)} ${n1(ax + 26)} ${n1(ay + 2)}Q${n1(ax + 30)} ${n1(ay + 10)} ${n1(ax + 18)} ${n1(ay + 12)}L${n1(ax - 16)} ${n1(ay + 12)}Q${n1(ax - 22)} ${n1(ay + 2)} ${n1(ax - 16)} ${n1(ay - 8)}Z`);
    }
    const lean = p.lean || 0;
    const btr = `translate(0 ${n1(hipY)}) rotate(${n1(lean)})`;
    body.setAttribute('transform', btr);
    cape.setAttribute('transform', btr);
    const rot = (x, y) => { const a = lean * D2R; return [x * Math.cos(a) - y * Math.sin(a), hipY + x * Math.sin(a) + y * Math.cos(a)]; };
    // руки: углы от вертикали вниз, + — к +x
    const sway = wa ? Math.sin(ph) * 28 * wa : Math.sin(t * 1.6 + blinkSeed) * 3;
    const aL = p.armL || [-14 - sway, -8], aR = p.armR || [14 - sway, 8];
    const arm = (path, hand, side, a) => {
      const [sx, sy] = rot(side * (W - 6), -118);
      const a1 = (a[0] + lean) * D2R, a2 = a1 + a[1] * D2R;
      const ex = sx + 70 * Math.sin(a1), ey = sy + 70 * Math.cos(a1);
      const wx = ex + 66 * Math.sin(a2), wy = ey + 66 * Math.cos(a2);
      path.setAttribute('d', `M${n1(sx)} ${n1(sy)}L${n1(ex)} ${n1(ey)}L${n1(wx)} ${n1(wy)}`);
      hand.setAttribute('cx', n1(wx)); hand.setAttribute('cy', n1(wy));
      return [wx, wy, a2];
    };
    arm(armB, handB, -1, aL);
    const [wx, wy, wa2] = arm(armF, handF, 1, aR);
    hold.setAttribute('transform', `translate(${n1(wx)} ${n1(wy)}) rotate(${n1(p.holdR != null ? p.holdR : -wa2 / D2R + 0)})`);
    // голова
    const [nx, ny] = rot(0, -130);
    head.setAttribute('transform', `translate(${n1(nx)} ${n1(ny)}) rotate(${n1((p.tilt || 0) + lean * .3)}) scale(${hs})`);
    const lk = p.look == null ? 0 : p.look, lky = p.lookY || 0;
    // моргание: детерминированно по времени
    const bt = (t + blinkSeed * 3.1) % (2.8 + (blinkSeed % 1.3));
    const blink = p.closed ? 1 : bt < .12 ? Math.sin(bt / .12 * Math.PI) : 0;
    const em = p.em || 'smile';
    eyes.forEach((e, i) => {
      const ex = (i ? 18 : -18) + lk * 7, ey = -58;
      const ry = 11.5 * (1 - blink * .9) * (em === 'shock' ? 1.2 : 1);
      e.w.setAttribute('cx', n1(ex)); e.w.setAttribute('cy', ey); e.w.setAttribute('ry', n1(ry));
      e.pu.setAttribute('cx', n1(ex + lk * 3)); e.pu.setAttribute('cy', n1(ey + 1 + lky * 3)); e.pu.setAttribute('r', blink > .6 ? 0 : em === 'shock' ? 4.5 : 6);
      e.gl.setAttribute('cx', n1(ex + lk * 3 + 2)); e.gl.setAttribute('cy', n1(ey - 2)); e.gl.setAttribute('r', blink > .6 ? 0 : 2);
      const bx = ex, by = -80 - (em === 'shock' ? 8 : 0) - (p.brow || 0);
      const ang = em === 'angry' ? (i ? -1 : 1) * 9 : em === 'sad' ? (i ? 1 : -1) * 7 : 0;
      brows[i].setAttribute('d', `M${n1(bx - 11)} ${n1(by - ang * (i ? -1 : 1) * .5 + (em === 'angry' ? (i ? -4 : 4) : 0))}L${n1(bx + 11)} ${n1(by + ang * (i ? -1 : 1) * .5 + (em === 'angry' ? (i ? 4 : -4) : 0))}`);
    });
    nose.setAttribute('d', `M${n1(lk * 11 - 4)} -50 Q${n1(lk * 11 + 6 + lk * 4)} -40 ${n1(lk * 11 - 4)} -38Z`);
    const mx = lk * 9, my = -27;
    const talk = p.talk ? Math.abs(Math.sin(t * 15 + blinkSeed)) * .7 + Math.abs(Math.sin(t * 23)) * .3 : 0;
    let md, td = '';
    if (em === 'shout' || em === 'shock') {
      const ry = (em === 'shout' ? 13 : 9) + talk * 5;
      md = `M${n1(mx - 13)} ${my}Q${n1(mx)} ${n1(my - ry)} ${n1(mx + 13)} ${my}Q${n1(mx)} ${n1(my + ry * 1.3)} ${n1(mx - 13)} ${my}Z`;
    } else if (em === 'sad') {
      md = `M${n1(mx - 13)} ${my + 4}Q${n1(mx)} ${my - 7} ${n1(mx + 13)} ${my + 4}`;
      mouth.setAttribute('fill', 'none');
    } else if (em === 'angry') {
      md = `M${n1(mx - 13)} ${my + 2}Q${n1(mx)} ${n1(my - 3 - talk * 6)} ${n1(mx + 13)} ${my + 2}Q${n1(mx)} ${n1(my + 2 + talk * 10)} ${n1(mx - 13)} ${my + 2}Z`;
    } else if (em === 'grin' || talk > 0) {
      const op = em === 'grin' ? 12 : 3 + talk * 11;
      md = `M${n1(mx - 16)} ${my - 3}Q${n1(mx)} ${my} ${n1(mx + 16)} ${my - 3}Q${n1(mx)} ${n1(my + op * 1.4)} ${n1(mx - 16)} ${my - 3}Z`;
      td = `M${n1(mx - 13)} ${my - 2}Q${n1(mx)} ${my + 1} ${n1(mx + 13)} ${my - 2}L${n1(mx + 11)} ${my + 3}Q${n1(mx)} ${my + 5} ${n1(mx - 11)} ${my + 3}Z`;
    } else {
      md = `M${n1(mx - 13)} ${my - 2}Q${n1(mx)} ${my + 10} ${n1(mx + 13)} ${my - 2}`;
      mouth.setAttribute('fill', 'none');
    }
    if (md.endsWith('Z')) mouth.setAttribute('fill', '#5A1E24');
    mouth.setAttribute('d', md);
    teeth.setAttribute('d', td);
    if (must) must.setAttribute('d', `M${n1(mx - 22)} ${my - 6}Q${n1(mx - 10)} ${my - 16} ${n1(mx)} ${my - 10}Q${n1(mx + 10)} ${my - 16} ${n1(mx + 22)} ${my - 6}Q${n1(mx + 10)} ${my - 6} ${n1(mx)} ${my - 6}Q${n1(mx - 10)} ${my - 6} ${n1(mx - 22)} ${my - 6}Z`);
  }
  return { g, o, draw, hold, hat };
}

/* =====================================================================
   ПЕЙЗАЖ
   ===================================================================== */
function sky(p, top, bot, h = 1920) {
  return sv('rect', { x: -400, y: -400, width: 1880, height: h + 800, fill: lin([[0, top], [1, bot]]) }, p);
}
function sunEl(p, x, y, r, c) {
  const g = sv('g', null, p);
  sv('circle', { cx: 0, cy: 0, r: r * 3, fill: rad([[0, c, .55], [1, c, 0]]) }, g);
  sv('circle', { cx: 0, cy: 0, r, fill: tint(c, .3) }, g);
  at(g, x, y);
  return g;
}
function cloud(p, x, y, s = 1, c = '#fff', op = .9) {
  return svh(`<g fill="${c}" opacity="${op}"><ellipse cx="0" cy="0" rx="90" ry="34"/><circle cx="-36" cy="-18" r="34"/><circle cx="18" cy="-34" r="44"/><circle cx="62" cy="-10" r="30"/></g>`, p, { transform: `translate(${x} ${y}) scale(${s})` });
}
function skyline(p, y, c, seed = 1, hmin = 120, hmax = 380, lit = null) {
  let r = seed, out = '';
  const rnd = () => (r = (r * 9301 + 49297) % 233280) / 233280;
  for (let x = -200; x < 1300;) {
    const w = 70 + rnd() * 110, h = hmin + rnd() * (hmax - hmin);
    out += `<rect x="${n1(x)}" y="${n1(y - h)}" width="${n1(w)}" height="${n1(h + 600)}" fill="${c}"/>`;
    if (rnd() < .3) out += `<rect x="${n1(x + w / 2 - 3)}" y="${n1(y - h - 40)}" width="6" height="40" fill="${c}"/>`;
    if (lit) for (let wy = y - h + 22; wy < y - 10; wy += 34) for (let wx = x + 12; wx < x + w - 18; wx += 26) if (rnd() < .45) out += `<rect x="${n1(wx)}" y="${n1(wy)}" width="12" height="16" fill="${lit}" opacity="${(.4 + rnd() * .6).toFixed(2)}"/>`;
    x += w + 6;
  }
  return svh(out, p);
}
function hills(p, y, c, amp = 60, seed = 0) {
  let d = `M-300 ${y + 900}L-300 ${y}`;
  for (let x = -300; x <= 1400; x += 40) d += `L${x} ${n1(y - amp * (.5 + .5 * Math.sin(x / 170 + seed)) - amp * .4 * Math.sin(x / 63 + seed * 2))}`;
  return sv('path', { d: d + `L1400 ${y + 900}Z`, fill: c }, p);
}
function mountains(p, y, c, snow) {
  const pk = [[-200, 0], [-60, -260], [80, -120], [240, -380], [420, -150], [560, -300], [720, -110], [880, -340], [1060, -140], [1250, -280], [1400, 0]];
  let d = `M-300 ${y + 600}`;
  pk.forEach(([x, h]) => d += `L${x} ${y + h}`);
  const g = sv('g', null, p);
  sv('path', { d: d + `L1400 ${y + 600}Z`, fill: c }, g);
  if (snow) pk.filter(k => k[1] < -250).forEach(([x, h]) => sv('path', { d: `M${x} ${y + h}L${x - 46} ${y + h + 60}L${x - 16} ${y + h + 48}L${x} ${y + h + 66}L${x + 18} ${y + h + 46}L${x + 46} ${y + h + 60}Z`, fill: snow }, g));
  return g;
}
function ground(p, y, top, bot) {
  return sv('rect', { x: -400, y, width: 1880, height: 2400, fill: lin([[0, top], [1, bot]]) }, p);
}
function tree(p, x, y, s = 1, c = '#3FA65A') {
  return svh(`<rect x="-9" y="-80" width="18" height="84" rx="6" fill="#6B4630"/><circle cx="0" cy="-120" r="56" fill="${c}"/><circle cx="-36" cy="-90" r="38" fill="${shade(c, .1)}"/><circle cx="34" cy="-92" r="40" fill="${tint(c, .08)}"/><circle cx="14" cy="-140" r="26" fill="${tint(c, .2)}" opacity=".6"/>`, p, { transform: `translate(${x} ${y}) scale(${s})` });
}

/* =====================================================================
   ЗДАНИЯ
   ===================================================================== */
function houseEl(p, x, y, s = 1, wall = '#F3E2C7', roof = '#C8443A') {
  const g = svh(`<rect x="-110" y="-180" width="220" height="180" fill="${wall}"/><rect x="40" y="-180" width="70" height="180" fill="#000" opacity=".07"/>
    <path d="M-132 -170 L0 -270 L132 -170Z" fill="${roof}"/><path d="M0 -270 L132 -170 L100 -170Z" fill="#000" opacity=".12"/>
    <rect x="-24" y="-90" width="48" height="90" rx="6" fill="#7A4A2E"/>
    <rect class="win" x="-86" y="-140" width="46" height="42" rx="5" fill="#BFE3FF"/><rect class="win" x="40" y="-140" width="46" height="42" rx="5" fill="#BFE3FF"/>`, p);
  at(g, x, y, s);
  return g;
}
function factoryEl(p, x, y, s = 1, c = '#8F97A8') {
  const g = sv('g', null, p);
  const smoke = svh([0, 1, 2, 3, 4].map(() => `<circle r="34" fill="#D9DCE3"/>`).join(''), g);
  g.insertAdjacentHTML('beforeend', `<rect x="150" y="-420" width="56" height="300" fill="${shade(c, .15)}"/><rect x="150" y="-420" width="56" height="20" fill="#D8343E"/><rect x="150" y="-370" width="56" height="12" fill="#fff" opacity=".7"/>
    <path d="M-250 0 V-200 L-160 -270 V-200 L-70 -270 V-200 L20 -270 V-200 L110 -270 V-200 L250 -200 V0Z" fill="${c}"/>
    <path d="M-160 -270 V-200 L-190 -200Z M-70 -270 V-200 L-100 -200Z M20 -270 V-200 L-10 -200Z M110 -270 V-200 L80 -200Z" fill="#000" opacity=".15"/>
    ${[-210, -130, -50, 30].map(xx => `<rect x="${xx}" y="-170" width="56" height="52" rx="5" fill="#FFE29A"/><path d="M${xx} -144h56M${xx + 28} -170v52" stroke="${c}" stroke-width="5"/>`).join('')}
    <rect x="110" y="-200" width="140" height="200" fill="${shade(c, .08)}"/>`);
  const gateL = sv('rect', { x: 128, y: -150, width: 52, height: 150, fill: '#5B6476' }, g);
  const gateR = sv('rect', { x: 180, y: -150, width: 52, height: 150, fill: '#4E5668' }, g);
  at(g, x, y, s);
  return { g, smoke: [...smoke.children], gateL, gateR };
}
function parliamentEl(p, x, y, s = 1, c = '#EDE6D8', flagC = '#3D8BFF') {
  const g = sv('g', null, p);
  g.innerHTML = `<rect x="-300" y="-40" width="600" height="40" fill="${shade(c, .12)}"/><rect x="-280" y="-70" width="560" height="34" fill="${shade(c, .06)}"/>
    <rect x="-250" y="-300" width="500" height="232" fill="${c}"/>
    ${[-215, -145, -75, -5, 65, 135, 205].map(xx => `<rect x="${xx}" y="-292" width="30" height="222" fill="${tint(c, .5)}"/><rect x="${xx + 20}" y="-292" width="10" height="222" fill="#000" opacity=".08"/>`).join('')}
    <rect x="-270" y="-320" width="540" height="26" fill="${shade(c, .05)}"/>
    <path d="M-280 -320 L0 -420 L280 -320Z" fill="${tint(c, .2)}"/><path d="M-200 -330 L0 -398 L200 -330Z" fill="${shade(c, .08)}"/>
    <rect x="-90" y="-520" width="180" height="70" fill="${c}"/>
    <path d="M-110 -514 Q-110 -640 0 -650 Q110 -640 110 -514Z" fill="${tint(flagC, .25)}"/><path d="M30 -646 Q110 -630 110 -514 L60 -514 Q66 -610 30 -646Z" fill="#000" opacity=".12"/>
    <rect x="-4" y="-760" width="8" height="120" fill="#555"/>`;
  const flag = sv('path', { fill: flagC }, g);
  at(g, x, y, s);
  return { g, flag, fx: 4, fy: -760 };
}
/* развевающийся флаг: path обновляется каждый кадр */
function waveFlag(path, x0, y0, w, h, t, amp = 12, stripes) {
  let d = '';
  for (let i = 0; i <= 16; i++) { const x = i / 16 * w; d += (i ? 'L' : 'M') + n1(x0 + x) + ' ' + n1(y0 + Math.sin(x / 50 - t * 6) * amp * (x / w)); }
  for (let i = 16; i >= 0; i--) { const x = i / 16 * w; d += 'L' + n1(x0 + x) + ' ' + n1(y0 + h + Math.sin(x / 50 - t * 6) * amp * (x / w)); }
  path.setAttribute('d', d + 'Z');
}
function warehouseEl(p, x, y, s = 1, c = '#B5573B') {
  const g = sv('g', null, p);
  g.innerHTML = `<path d="M-260 0 V-250 L0 -380 L260 -250 V0Z" fill="${c}"/><path d="M0 -380 L260 -250 V0 H160 V-250Z" fill="#000" opacity=".1"/>
    <path d="M-280 -240 L0 -392 L280 -240" fill="none" stroke="${shade(c, .35)}" stroke-width="22" stroke-linejoin="round"/>
    <rect x="-130" y="-230" width="260" height="230" fill="#2A1A14"/>
    <circle cx="0" cy="-300" r="36" fill="#F3E2C7"/>`;
  const inside = sv('g', null, g);
  const doorL = svh(`<rect x="-130" y="-230" width="130" height="230" fill="${tint(c, .15)}"/><path d="M-130 -230 L0 0 M0 -230 L-130 0" stroke="${shade(c, .2)}" stroke-width="10"/><rect x="-130" y="-230" width="130" height="230" fill="none" stroke="${shade(c, .3)}" stroke-width="10"/>`, g);
  const doorR = svh(`<rect x="0" y="-230" width="130" height="230" fill="${tint(c, .1)}"/><path d="M0 -230 L130 0 M130 -230 L0 0" stroke="${shade(c, .2)}" stroke-width="10"/><rect x="0" y="-230" width="130" height="230" fill="none" stroke="${shade(c, .3)}" stroke-width="10"/>`, g);
  at(g, x, y, s);
  return { g, doorL, doorR, inside };
}
function signBuilding(p, x, y, s, wall, roof, label, icon) {
  const g = svh(`<rect x="-120" y="-220" width="240" height="220" fill="${wall}"/><rect x="50" y="-220" width="70" height="220" fill="#000" opacity=".07"/>
    <rect x="-140" y="-246" width="280" height="34" rx="6" fill="${roof}"/>
    <rect x="-80" y="-206" width="160" height="40" rx="8" fill="#fff"/><text x="0" y="-176" text-anchor="middle" font-family="Rubik" font-weight="800" font-size="26" fill="${roof}">${label}</text>
    ${icon || ''}
    ${[-90, -30, 30].map(xx => `<rect class="win" x="${xx}" y="-150" width="44" height="44" rx="5" fill="#BFE3FF"/>`).join('')}
    <rect x="34" y="-100" width="56" height="100" rx="6" fill="${shade(roof, .2)}"/>`, p);
  at(g, x, y, s);
  return g;
}
function schoolEl(p, x, y, s = 1) { return signBuilding(p, x, y, s, '#FFE3A8', '#E07A1F', 'MAKTAB', `<path d="M-30 -262 L0 -300 L30 -262Z" fill="#E07A1F"/><circle cx="0" cy="-276" r="7" fill="#FFE3A8"/>`); }
function hospitalEl(p, x, y, s = 1) { return signBuilding(p, x, y, s, '#F4F6FA', '#E5484D', 'SHIFOXONA', `<path d="M-12 -300h24v20h20v24h-20v20h-24v-20h-20v-24h20Z" fill="#E5484D"/>`); }
/* восточный портал с куполом (силуэт Регистана, без конкретного здания) */
function madrasaEl(p, x, y, s = 1) {
  const tile = pattern(36, 36, `<rect width="36" height="36" fill="#1F6FB5"/><path d="M18 2 L34 18 L18 34 L2 18Z" fill="#2E8FD6"/><circle cx="18" cy="18" r="5" fill="#F2D27A"/>`);
  const g = svh(`<rect x="-330" y="-300" width="660" height="300" fill="#D9B98A"/>
    <rect x="-150" y="-470" width="300" height="470" fill="#E3C79C"/><rect x="-150" y="-470" width="300" height="40" fill="${tile}"/>
    <path d="M-95 0 V-300 Q-95 -390 0 -410 Q95 -390 95 -300 V0Z" fill="${tile}"/><path d="M-70 0 V-290 Q-70 -360 0 -376 Q70 -360 70 -290 V0Z" fill="#14324F"/>
    <rect x="-300" y="-560" width="56" height="560" fill="#D9B98A"/><rect x="-300" y="-560" width="56" height="200" fill="${tile}"/><path d="M-310 -560 h76 l-8 -24 h-60Z" fill="#C9A06A"/>
    <rect x="244" y="-560" width="56" height="560" fill="#D9B98A"/><rect x="244" y="-560" width="56" height="200" fill="${tile}"/><path d="M234 -560 h76 l-8 -24 h-60Z" fill="#C9A06A"/>
    <path d="M-170 -300 Q-170 -460 0 -480 Q170 -460 170 -300Z" fill="#2B9BD8" transform="translate(-330 30) scale(.5)"/>
    <path d="M-120 -470 Q-120 -610 0 -630 Q120 -610 120 -470Z" fill="${tile}"/><path d="M40 -626 Q120 -600 120 -470 H70 Q74 -580 40 -626Z" fill="#000" opacity=".12"/>
    <rect x="-4" y="-680" width="8" height="54" fill="#E9B949"/><circle cx="0" cy="-686" r="10" fill="#E9B949"/>`, p);
  at(g, x, y, s);
  return g;
}
function stallEl(p, x, y, s = 1, c = '#E5484D') {
  const aw = pattern(60, 60, `<rect width="30" height="60" fill="${c}"/><rect x="30" width="30" height="60" fill="#fff"/>`);
  const g = sv('g', null, p);
  g.innerHTML = `<rect x="-150" y="-300" width="14" height="300" fill="#6B4630"/><rect x="136" y="-300" width="14" height="300" fill="#6B4630"/>
    <path d="M-176 -330 L176 -330 L186 -250 L-186 -250Z" fill="${aw}"/>
    ${[-186, -124, -62, 0, 62, 124].map(xx => `<path d="M${xx} -250 q31 34 62 0Z" fill="${c}"/>`).join('')}
    <rect x="-160" y="-120" width="320" height="120" rx="8" fill="#C98D5A"/><rect x="-160" y="-130" width="320" height="22" rx="6" fill="#8E5A35"/>
    ${[-110, -50, 10, 70].map((xx, i) => `<circle cx="${xx + 20}" cy="-150" r="24" fill="${['#F5A524', '#E5484D', '#7CC24B', '#F5D33F'][i]}"/>`).join('')}`;
  const tag = svh(`<rect x="-62" y="-36" width="124" height="72" rx="14" fill="#fff" stroke="${c}" stroke-width="6"/>`, g);
  const price = sv('text', { x: 0, y: 16, 'text-anchor': 'middle', 'font-family': 'Unbounded', 'font-weight': 900, 'font-size': 40, fill: c }, tag);
  at(tag, 0, -380);
  at(g, x, y, s);
  return { g, tag, price };
}

/* =====================================================================
   ПРЕДМЕТЫ (строки разметки; рисуются вокруг (0,0))
   ===================================================================== */
const PROP = {
  coin: (r = 30) => `<circle r="${r}" fill="#F2B632"/><circle r="${r * .78}" fill="#FFD25E"/><text y="${r * .36}" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="${r}" fill="#C98A12">$</text>`,
  sack: `<path d="M-40 40 Q-56 -10 -24 -36 L-30 -54 Q0 -46 30 -54 L24 -36 Q56 -10 40 40 Q0 52 -40 40Z" fill="#D9B77A"/><path d="M-26 -38 Q0 -30 26 -38" stroke="#9C7A3E" stroke-width="6" fill="none"/><path d="M-10 0 L0 -16 L10 0 L0 16Z" fill="#9C7A3E"/>`,
  crate: `<rect x="-42" y="-42" width="84" height="84" rx="6" fill="#C98D5A"/><path d="M-42 -42 L42 42 M42 -42 L-42 42" stroke="#9C6838" stroke-width="9"/><rect x="-42" y="-42" width="84" height="84" rx="6" fill="none" stroke="#8E5A35" stroke-width="8"/>`,
  brick: `<rect x="-40" y="-18" width="80" height="36" rx="4" fill="#D0603F"/><path d="M-40 0h80M0 -18v18" stroke="#A84630" stroke-width="5"/>`,
  ballot: (c = '#3D8BFF') => `<rect x="-36" y="-48" width="72" height="96" rx="8" fill="#fff" stroke="#D5DAE6" stroke-width="3"/><path d="M-22 -24h30M-22 -8h44" stroke="#C5CBDA" stroke-width="6" stroke-linecap="round"/><path d="m-14 16 10 10 22-22" fill="none" stroke="${c}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>`,
  heart: `<path d="M0 30 C-60 -6 -34 -50 0 -24 C34 -50 60 -6 0 30Z" fill="#FF4D6D"/>`,
  qmark: `<circle r="40" fill="#fff"/><text y="22" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="58" fill="#7B4DFF">?</text>`,
  key: `<circle cx="-30" cy="0" r="22" fill="none" stroke="#F2B632" stroke-width="12"/><path d="M-8 0 H46 M30 0 V16 M42 0 V12" stroke="#F2B632" stroke-width="12" stroke-linecap="round"/>`,
  briefcase: `<rect x="-40" y="-30" width="80" height="58" rx="8" fill="#6B4630"/><path d="M-14 -30 V-42 H14 V-30" fill="none" stroke="#4A2F1F" stroke-width="7"/><rect x="-40" y="-8" width="80" height="6" fill="#4A2F1F"/>`,
  clipboard: `<rect x="-34" y="-46" width="68" height="92" rx="8" fill="#8E5A35"/><rect x="-26" y="-36" width="52" height="74" rx="4" fill="#fff"/><rect x="-14" y="-52" width="28" height="14" rx="4" fill="#C5CBDA"/><path d="M-16 -18h32M-16 -2h32M-16 14h20" stroke="#9AA3B5" stroke-width="5" stroke-linecap="round"/>`,
  megaphone: `<path d="M-10 -14 L60 -44 L60 44 L-10 14Z" fill="#E5484D"/><rect x="-30" y="-16" width="24" height="32" rx="6" fill="#B8323A"/><ellipse cx="60" cy="0" rx="10" ry="44" fill="#FF8A8F"/><rect x="-16" y="12" width="12" height="26" rx="4" fill="#333"/>`,
  dutar: `<ellipse cx="0" cy="40" rx="38" ry="52" fill="#B66A2E"/><ellipse cx="0" cy="40" rx="24" ry="36" fill="#8E4F1E"/><rect x="-7" y="-150" width="14" height="160" rx="5" fill="#7A3F16"/><path d="M-3 -150 V70 M3 -150 V70" stroke="#F3E2C7" stroke-width="1.5"/>`,
  lagan: `<ellipse rx="70" ry="26" fill="#1F6FB5"/><ellipse rx="54" ry="18" fill="#fff"/><ellipse rx="34" ry="11" fill="#2E8FD6"/><path d="M-50 0 Q0 -14 50 0 Q0 14 -50 0Z" fill="none" stroke="#1F6FB5" stroke-width="3"/>`,
  non: `<circle r="48" fill="#D9933F"/><circle r="30" fill="#F0C27A"/>${[0, 1, 2, 3, 4, 5].map(i => `<circle cx="${(Math.cos(i) * 14).toFixed(1)}" cy="${(Math.sin(i) * 14).toFixed(1)}" r="3" fill="#A8692A"/>`).join('')}<circle r="48" fill="none" stroke="#B87430" stroke-width="5"/>`,
  atlas: `<rect x="-60" y="-40" width="120" height="80" rx="6" fill="#7A2BB5"/><path d="M-60 -20 Q-30 -40 0 -20 T60 -20 M-60 10 Q-30 -10 0 10 T60 10" stroke="#F2C044" stroke-width="9" fill="none"/><path d="M-60 -5 Q-30 -25 0 -5 T60 -5" stroke="#3EC6E0" stroke-width="6" fill="none"/>`,
  gear: (r, c) => `<path d="${(() => { let d = ''; const n = 12, r2 = r * 1.24; for (let i = 0; i < n; i++) { const a = i / n * Math.PI * 2, s = Math.PI * 2 / n; for (const [rr, b] of [[r, a - s * .5], [r, a - s * .22], [r2, a - s * .14], [r2, a + s * .14], [r, a + s * .22]]) d += (d ? 'L' : 'M') + (rr * Math.cos(b)).toFixed(1) + ' ' + (rr * Math.sin(b)).toFixed(1); } return d + 'Z'; })()}" fill="${c}"/><circle r="${r * .55}" fill="${shade(c, .3)}"/><circle r="${r * .3}" fill="${tint(c, .4)}"/>`,
  stop: `<path d="M-41 -100 L41 -100 L100 -41 L100 41 L41 100 L-41 100 L-100 41 L-100 -41Z" fill="#E5484D" stroke="#fff" stroke-width="10"/><rect x="-62" y="-14" width="124" height="28" rx="8" fill="#fff"/>`,
  check: (c) => `<circle r="70" fill="${c}"/><circle r="70" fill="none" stroke="#fff" stroke-width="8"/><path d="m-32 2 22 22 44-44" fill="none" stroke="#fff" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"/>`,
  bigx: `<path d="M-90 -90 L90 90 M90 -90 L-90 90" stroke="#E5484D" stroke-width="34" stroke-linecap="round"/>`,
  padlock: `<path class="shackle" d="M-34 -10 V-50 Q-34 -86 0 -86 Q34 -86 34 -50 V-10" fill="none" stroke="#B9BFCC" stroke-width="14"/><rect x="-50" y="-14" width="100" height="84" rx="14" fill="#F2B632"/><circle cy="18" r="11" fill="#7A5410"/><rect x="-4" y="18" width="8" height="24" fill="#7A5410"/>`,
  throne: `<path d="M-120 0 V-120 H120 V0Z" fill="#7A1426"/><path d="M-100 -120 V-380 Q0 -460 100 -380 V-120Z" fill="#9E1B2F"/><path d="M-70 -150 V-350 Q0 -410 70 -350 V-150Z" fill="#C8243D"/><rect x="-140" y="-150" width="40" height="150" rx="10" fill="#E9B949"/><rect x="100" y="-150" width="40" height="150" rx="10" fill="#E9B949"/><circle cx="0" cy="-420" r="18" fill="#E9B949"/>`,
  podium: (c) => `<path d="M-90 0 L-70 -170 H70 L90 0Z" fill="${c}"/><rect x="-100" y="-190" width="200" height="30" rx="8" fill="${shade(c, .2)}"/><path d="M0 -190 V-250" stroke="#333" stroke-width="6"/><circle cx="0" cy="-256" r="10" fill="#333"/><circle cx="0" cy="-90" r="34" fill="#fff" opacity=".9"/><path d="M-12 -98 L0 -118 L12 -98 L0 -64Z" fill="${c}"/>`,
  box: (c = '#3D8BFF') => `<rect x="-110" y="-150" width="220" height="150" rx="10" fill="#DDEBFF" opacity=".55" stroke="#fff" stroke-width="6"/><rect x="-118" y="-170" width="236" height="26" rx="8" fill="${c}"/><rect x="-50" y="-162" width="100" height="10" rx="5" fill="#0B1530"/><path d="M-90 -130 L-70 -20" stroke="#fff" stroke-width="8" opacity=".6" stroke-linecap="round"/>`,
  table: `<rect x="-170" y="-12" width="340" height="24" rx="6" fill="#8E5A35"/><rect x="-150" y="10" width="18" height="110" fill="#6B4630"/><rect x="132" y="10" width="18" height="110" fill="#6B4630"/>`,
  pedestal: (c) => `<rect x="-90" y="0" width="180" height="1000" fill="${c}"/><rect x="-104" y="-16" width="208" height="30" rx="8" fill="${tint(c, .2)}"/><rect x="40" y="0" width="50" height="1000" fill="#000" opacity=".15"/>`,
  dome: (c) => `<path d="M-520 0 A520 420 0 0 1 520 0" fill="${c}" fill-opacity=".16" stroke="${tint(c, .3)}" stroke-width="12"/><path d="M-400 -120 A420 300 0 0 1 -120 -330" fill="none" stroke="#fff" stroke-width="14" stroke-linecap="round" opacity=".35"/>`,
  stormcloud: `<g fill="#3B3550"><ellipse cx="0" cy="0" rx="110" ry="40"/><circle cx="-40" cy="-24" r="44"/><circle cx="30" cy="-40" r="54"/><circle cx="80" cy="-12" r="36"/></g><path d="M10 30 L-14 80 L8 80 L-10 130 L36 66 L14 66 L30 30Z" fill="#FFD84D"/>`,
  chart: (c) => `<rect x="-160" y="-130" width="320" height="230" rx="18" fill="#fff"/><path d="M-130 70 H130 M-130 70 V-100" stroke="#C5CBDA" stroke-width="6" stroke-linecap="round"/>`,
  sparkle: (c = '#fff') => `<path d="M0 -26 C4 -6 6 -4 26 0 C6 4 4 6 0 26 C-4 6 -6 4 -26 0 C-6 -4 -4 -6 0 -26Z" fill="${c}"/>`,
  bubble: (txt, c = '#fff', tc = '#111') => `<path d="M-130 -60 H130 Q150 -60 150 -40 V30 Q150 50 130 50 H-40 L-80 90 L-70 50 H-130 Q-150 50 -150 30 V-40 Q-150 -60 -130 -60Z" fill="${c}"/><text y="8" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="34" fill="${tc}">${txt}</text>`,
  arrowDown: (c = '#E5484D') => `<path d="M-18 -50 H18 V0 H40 L0 46 L-40 0 H-18Z" fill="${c}"/>`,
  waves: (c = '#fff') => `<g fill="none" stroke="${c}" stroke-width="8" stroke-linecap="round"><path class="w0" d="M0 -30 Q20 0 0 30"/><path class="w1" d="M24 -50 Q54 0 24 50"/><path class="w2" d="M48 -70 Q88 0 48 70"/></g>`,
  spot: (c = '#FFF2C2') => `<path d="M-40 -1400 L40 -1400 L230 0 L-230 0Z" fill="${c}" opacity=".18"/><ellipse rx="230" ry="40" fill="${c}" opacity=".25"/>`,
  sun: `<circle r="90" fill="#FFD25E"/><circle r="70" fill="#FFE59A"/>`,
  star: (c = '#F2C044') => `<path d="M0 -40 L11 -12 L40 -12 L17 6 L26 36 L0 18 L-26 36 L-17 6 L-40 -12 L-11 -12Z" fill="${c}"/>`,
  sign: (txt, c) => `<rect x="-8" y="0" width="16" height="120" fill="#6B4630"/><rect x="-120" y="-60" width="240" height="70" rx="12" fill="${c}"/><text y="-12" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="30" fill="#fff">${txt}</text>`,
  belt: `<rect x="-300" y="-14" width="600" height="28" rx="14" fill="#3A3F4F"/>`,
};
const prop = (p, html, x = 0, y = 0, s = 1) => { const g = svh(html, p); at(g, x, y, s); return g; };
