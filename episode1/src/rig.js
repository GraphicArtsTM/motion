// Персонажи: иерархический риг из примитивов, библиотека поз, мимика.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon, glow, mesh, lerp, clamp, noise, E } from './core.js';

const cap = (r, len) => new THREE.CapsuleGeometry(r, Math.max(len - 2 * r, .001), 6, 14);
const sph = (r, w = 20, h = 14) => new THREE.SphereGeometry(r, w, h);
const rbox = (x, y, z, r = .02) => new RoundedBoxGeometry(x, y, z, 3, Math.min(r, x / 2.1, y / 2.1, z / 2.1));

const JOINTS = ['hips', 'spine', 'chest', 'neck', 'head', 'armL', 'foreL', 'handL', 'armR', 'foreR', 'handR',
  'legL', 'shinL', 'footL', 'legR', 'shinR', 'footR'];

/* ---------- текстура нанокостюма: тёмная ткань с бирюзовой паутиной ---------- */
function webCanvas(glowOnly) {
  const c = document.createElement('canvas'); c.width = c.height = 512;
  const g = c.getContext('2d');
  g.fillStyle = glowOnly ? '#000' : '#2c3850'; g.fillRect(0, 0, 512, 512);
  if (!glowOnly) {                         // лёгкая фактура ткани
    for (let i = 0; i < 4000; i++) { g.fillStyle = `rgba(255,255,255,${Math.random() * .025})`; g.fillRect(Math.random() * 512, Math.random() * 512, 2, 2); }
  }
  g.strokeStyle = glowOnly ? '#5ee' : '#3a4a5c'; g.lineWidth = glowOnly ? 2 : 3;
  // редкая сетка паутины: вертикальные нити + провисающие поперечные
  for (let i = 0; i <= 4; i++) { g.beginPath(); g.moveTo(i * 128, 0); g.lineTo(i * 128, 512); g.stroke(); }
  for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
    g.beginPath(); g.moveTo(i * 128, j * 128 + 30); g.quadraticCurveTo(i * 128 + 64, j * 128 + 66, i * 128 + 128, j * 128 + 30); g.stroke();
  }
  if (!glowOnly) { g.fillStyle = 'rgba(200,30,50,.0)'; }
  const tx = new THREE.CanvasTexture(c); tx.wrapS = tx.wrapT = THREE.RepeatWrapping; tx.colorSpace = THREE.SRGBColorSpace;
  tx.repeat.set(1.5, 1.5);
  return tx;
}
let SUIT_MAT;
function suitMaterial() {
  if (SUIT_MAT) return SUIT_MAT;
  SUIT_MAT = toon(0xffffff, { map: webCanvas(false), emissiveMap: webCanvas(true), emissive: 0x33e6ff });
  SUIT_MAT.emissiveIntensity = 1.1;
  return SUIT_MAT;
}

/* ---------- базовый скелет ---------- */
function skeleton(d) {
  const J = {};
  const g = n => (J[n] = new THREE.Group());
  const root = new THREE.Group();
  root.add(g('hips')); J.hips.position.y = d.hipY;
  J.hips.add(g('spine')); J.spine.position.y = .08 * d.k;
  J.spine.add(g('chest')); J.chest.position.y = d.chestY;
  J.chest.add(g('neck')); J.neck.position.y = d.neckY;
  J.neck.add(g('head')); J.head.position.y = .09 * d.k;
  for (const [s, sx] of [['L', 1], ['R', -1]]) {
    J.chest.add(g('arm' + s)); J['arm' + s].position.set(sx * d.shX, d.shY, 0);
    J['arm' + s].add(g('fore' + s)); J['fore' + s].position.y = -d.upper;
    J['fore' + s].add(g('hand' + s)); J['hand' + s].position.y = -d.lower;
    J.hips.add(g('leg' + s)); J['leg' + s].position.set(sx * d.hipX, -.04 * d.k, 0);
    J['leg' + s].add(g('shin' + s)); J['shin' + s].position.y = -d.thigh;
    J['shin' + s].add(g('foot' + s)); J['foot' + s].position.y = -d.shin;
  }
  return { root, J };
}

const DIM = k => ({
  k, hipY: .92 * k, chestY: .3 * k, neckY: .2 * k, shX: .2 * k, shY: .1 * k,
  upper: .29 * k, lower: .27 * k, hipX: .095 * k, thigh: .44 * k, shin: .43 * k,
});

/* ---------- лицо ---------- */
function addFace(J, o, R, c) {
  const headC = new THREE.Vector3(0, .13, 0);
  const onSphere = (x, y, push = 0) => new THREE.Vector3(x, headC.y + y, Math.sqrt(Math.max(R * R - x * x - y * y, 0)) + push);
  const face = new THREE.Group(); J.head.add(face);
  const white = new THREE.MeshBasicMaterial({ color: 0xd8d8d8 }), dark = toon(0x14100e);
  const eyes = [], pupils = [], brows = [];
  for (const sx of [1, -1]) {
    const e = mesh(sph(.036 * (o.eyeK || 1)), white, { pos: onSphere(sx * .058, .025, -.012).toArray(), scale: [1, 1.2, .55], outline: .006 });
    face.add(e); eyes.push(e);
    const p = mesh(sph(.019 * (o.eyeK || 1), 12, 8), dark, { pos: [0, 0, .028], scale: [1, 1, .6] });
    e.add(p); pupils.push(p);
    const b = mesh(rbox(.07, .016, .02, .007), toon(o.brow || o.hair || 0x222222), { pos: onSphere(sx * .06, .085, .004).toArray(), outline: .004 });
    face.add(b); brows.push(b);
  }
  const mouth = mesh(sph(.03, 16, 10), toon(0x3a0d10), { pos: onSphere(0, -.065, -.006).toArray(), scale: [1.3, .25, .45] });
  face.add(mouth);
  const nose = mesh(sph(.024, 12, 8), toon(o.skin), { pos: onSphere(0, -.01, -.004).toArray(), scale: [1, .9, 1.1], outline: .004 });
  face.add(nose);
  for (const sx of [1, -1]) mesh(sph(.035, 12, 8), toon(o.skin), { pos: [sx * R * .98, headC.y, -.01], scale: [.5, 1, .8], outline: .005, parent: face });
  return { face, eyes, pupils, brows, mouth, headC };
}

/* ---------- персонажи ---------- */
export function makeCharacter(kind) {
  const k = kind === 'kronov' ? 1.6 : kind === 'ded' ? 1.0 : kind === 'vera' ? .96 : 1.0;
  const d = DIM(k);
  const { root, J } = skeleton(d);
  const ch = { kind, root, J, d, parts: {}, suit: false, faceRig: null, extras: {} };
  const OL = .012 * k;
  const C = {
    timur: { skin: 0xd9996b, hair: 0x22160f, top: 0xff7b1c, topDark: 0xc95410, pants: 0x283554, shoes: 0xf3f1ea },
    ded: { skin: 0xc98d68, hair: 0xd9d6d0, top: 0x2b3f6b, topDark: 0x1d2c4d, pants: 0x232f4a, shoes: 0x1a1a1a },
    vera: { skin: 0xf0c3a0, hair: 0xd8481f, top: 0xf4f6f8, topDark: 0xc9d2da, pants: 0x3b3446, shoes: 0x2a2a2a },
    shadow: { skin: 0x050507, hair: 0x050507, top: 0x07070a, topDark: 0x050507, pants: 0x050507, shoes: 0x050507 },
  }[kind] || {};
  ch.colors = C;

  if (kind === 'kronov') return buildKronov(ch, d);

  const m = {
    skin: toon(C.skin), top: toon(C.top), topDark: toon(C.topDark), pants: toon(C.pants), shoes: toon(C.shoes), hair: toon(C.hair),
    hand: toon(C.skin, { emissive: 0x000000 }),
  };
  ch.mats = m;
  const reg = (role, msh) => { (ch.parts[role] = ch.parts[role] || []).push(msh); msh.userData.role = role; msh.userData.base = msh.material; return msh; };

  // таз и торс
  reg('pants', mesh(rbox(.3 * k, .17 * k, .19 * k, .07 * k), m.pants, { pos: [0, .01 * k, 0], outline: OL, parent: J.hips }));
  const belly = kind === 'ded' ? 1.18 : 1;
  const torso = reg('top', mesh(cap(.155 * k, .46 * k), m.top, { pos: [0, .2 * k, .0], scale: [1.22, 1, .82 * belly], outline: OL, parent: J.spine }));
  if (kind === 'vera') { // халат: юбка-конус от пояса
    const coat = reg('top', mesh(new THREE.CylinderGeometry(.19 * k, .27 * k, .55 * k, 20, 1, true), toon(C.top, { side: THREE.DoubleSide }), { pos: [0, -.27 * k, 0], scale: [1, 1, .8], outline: OL, parent: J.hips }));
    coat.userData.coat = true;
  }
  reg('skin', mesh(new THREE.CylinderGeometry(.05 * k, .055 * k, .12 * k, 12), m.skin, { pos: [0, .03 * k, 0], outline: OL * .7, parent: J.neck }));

  // голова
  const R = .165 * k;
  const head = reg('skin', mesh(sph(R, 28, 20), m.skin, { pos: [0, .13 * k, 0], scale: [1, 1.03, 1], outline: OL, parent: J.head }));
  ch.head = head;
  const fr = addFace(J, { skin: C.skin, hair: C.hair, brow: kind === 'ded' ? 0xe8e6e0 : C.hair, eyeK: kind === 'vera' ? 1.05 : 1 }, .165, C);
  ch.faceRig = fr; fr.face.scale.setScalar(k); // лицо строится в единичном масштабе
  reg('face', fr.face);

  // руки
  for (const s of ['L', 'R']) {
    reg('top', mesh(cap(.058 * k, d.upper + .03 * k), m.top, { pos: [0, -d.upper / 2 + .01 * k, 0], outline: OL, parent: J['arm' + s] }));
    reg('top', mesh(cap(.05 * k, d.lower + .02 * k), kind === 'vera' ? m.top : m.topDark, { pos: [0, -d.lower / 2, 0], outline: OL, parent: J['fore' + s] }));
    reg('hand', mesh(sph(.056 * k, 14, 10), m.hand, { pos: [0, -.045 * k, .005], scale: [.95, 1.25, .72], outline: OL * .8, parent: J['hand' + s] }));
    // ноги
    reg('pants', mesh(cap(.078 * k, d.thigh + .04 * k), m.pants, { pos: [0, -d.thigh / 2, 0], outline: OL, parent: J['leg' + s] }));
    reg('pants', mesh(cap(.064 * k, d.shin + .03 * k), m.pants, { pos: [0, -d.shin / 2, 0], outline: OL, parent: J['shin' + s] }));
    reg('shoes', mesh(rbox(.11 * k, .08 * k, .25 * k, .035 * k), m.shoes, { pos: [0, -.02 * k, .055 * k], outline: OL, parent: J['foot' + s] }));
  }

  if (kind === 'timur') {
    // волосы: шапка + торчащие пряди
    const hairG = new THREE.Group(); J.head.add(hairG); reg('hair', hairG);
    mesh(new THREE.SphereGeometry(R * 1.04, 24, 14, 0, Math.PI * 2, 0, Math.PI * .52), m.hair, { pos: [0, .145 * k, -.012], scale: [1, .92, 1.02], outline: OL, parent: hairG });
    const spikes = [[0, .3, .08, -.5], [.07, .29, .05, -.3], [-.07, .29, .06, -.7], [.1, .26, -.03, .1], [-.1, .26, -.02, .2], [0, .29, -.07, .5], [.04, .27, .12, -1]];
    for (const [x, y, z, r] of spikes) mesh(new THREE.ConeGeometry(.05, .13, 8), m.hair, { pos: [x * k, y * k, z * k], rot: [r - .2, 0, -x * 5], outline: OL * .8, parent: hairG });
    // капюшон, рюкзак, лямки, карабин
    reg('acc', mesh(new THREE.TorusGeometry(.12 * k, .055 * k, 10, 20), m.topDark, { pos: [0, .43 * k, -.1 * k], rot: [1.2, 0, 0], scale: [1.1, 1, 1], outline: OL, parent: J.spine }));
    const pack = reg('acc', mesh(rbox(.36 * k, .42 * k, .22 * k, .05 * k), toon(0x15b9a8), { pos: [0, .22 * k, -.24 * k], outline: OL, parent: J.spine }));
    mesh(rbox(.3 * k, .1 * k, .02 * k, .01), toon(0xfff1c2), { pos: [0, .07 * k, -.111 * k], outline: false, parent: pack }); // полоса-светоотражатель
    for (const sx of [1, -1]) reg('acc', mesh(rbox(.05 * k, .4 * k, .03 * k, .012), toon(0x0f7f74), { pos: [sx * .1 * k, .26 * k, .13 * k], rot: [-.12, 0, 0], outline: OL * .5, parent: J.spine }));
    const carab = reg('acc', mesh(new THREE.TorusGeometry(.035 * k, .009 * k, 8, 20), toon(0xc8ccd4, { emissive: 0x222630 }), { pos: [.1 * k, .14 * k, .16 * k], scale: [.7, 1.2, 1], outline: OL * .4, parent: J.spine }));
    ch.carabiner = carab;
    // маска костюма: линзы
    const lenses = new THREE.Group(); J.head.add(lenses); lenses.visible = false; ch.lenses = lenses;
    const lensMat = new THREE.MeshBasicMaterial({ color: 0xdff4f8 });
    for (const sx of [1, -1]) {
      const L = mesh(sph(.06, 20, 12), lensMat, { pos: [sx * .068 * k, .155 * k, .132 * k], rot: [0, sx * .38, sx * -.45], scale: [1.25, .82, .35], outline: .014, parent: lenses });
      L.userData.sx = sx;
    }
    ch.lensList = lenses.children.filter(c => c.userData.sx);
  }
  if (kind === 'ded') {
    const capG = new THREE.Group(); J.head.add(capG); reg('hair', capG);
    mesh(new THREE.CylinderGeometry(R * 1.05, R * 1.0, .09 * k, 24), m.top, { pos: [0, .26 * k, 0], outline: OL, parent: capG });
    mesh(new THREE.CylinderGeometry(R * 1.12, R * 1.12, .025 * k, 24), m.topDark, { pos: [0, .31 * k, .01], outline: OL, parent: capG });
    mesh(rbox(.2 * k, .015 * k, .1 * k, .006), toon(0x111111), { pos: [0, .23 * k, .16 * k], rot: [.25, 0, 0], outline: OL * .6, parent: capG });
    mesh(rbox(.05 * k, .03 * k, .01 * k, .005), glow(0xffd36b, 1.2), { pos: [0, .28 * k, .175 * k], outline: false, parent: capG });
    // седые виски и усы
    for (const sx of [1, -1]) mesh(sph(.06 * k, 12, 8), m.hair, { pos: [sx * .14 * k, .14 * k, -.04 * k], scale: [.6, 1, 1.2], outline: OL * .6, parent: capG });
    const must = mesh(cap(.026 * k, .16 * k), m.hair, { pos: [0, .095 * k, .158 * k], rot: [0, 0, Math.PI / 2], scale: [1, 1, .8], outline: OL * .6, parent: J.head });
    reg('face', must);
    reg('acc', mesh(rbox(.06 * k, .03 * k, .02 * k, .005), glow(0xffd36b, 1), { pos: [.08 * k, .32 * k, .14 * k], outline: false, parent: J.spine }));
  }
  if (kind === 'vera') {
    const hairG = new THREE.Group(); J.head.add(hairG); reg('hair', hairG);
    mesh(new THREE.SphereGeometry(R * 1.05, 24, 14, 0, Math.PI * 2, 0, Math.PI * .55), m.hair, { pos: [0, .15 * k, -.02], outline: OL, parent: hairG });
    mesh(sph(.085 * k), m.hair, { pos: [0, .25 * k, -.13 * k], outline: OL, parent: hairG });
    for (const sx of [1, -1]) mesh(cap(.035 * k, .2 * k), m.hair, { pos: [sx * .15 * k, .08 * k, .04 * k], rot: [0, 0, sx * .12], outline: OL * .6, parent: hairG });
    // очки
    const gl = toon(0x222222);
    for (const sx of [1, -1]) mesh(new THREE.TorusGeometry(.043 * k, .007 * k, 6, 18), gl, { pos: [sx * .058 * k, .155 * k, .155 * k], outline: false, parent: J.head });
    mesh(rbox(.03 * k, .007 * k, .007 * k, .002), gl, { pos: [0, .16 * k, .165 * k], outline: false, parent: J.head });
    reg('acc', mesh(rbox(.07 * k, .09 * k, .01 * k, .005), toon(0x2c7be5), { pos: [-.09 * k, .3 * k, .14 * k], outline: false, parent: J.spine })); // бейдж
  }
  if (kind === 'shadow') {
    fr.face.visible = false;
    const eyes = new THREE.Group(); J.head.add(eyes); ch.redEyes = eyes;
    const em = glow(0xff1020, 4);
    [[-.05, .2, .8], [.05, .2, .8], [-.1, .17, .7], [.1, .17, .7], [-.035, .14, .65], [.035, .14, .65], [-.12, .23, .55], [.12, .23, .55]]
      .forEach(([x, y, s]) => mesh(sph(.022 * s + .006, 10, 8), em, { pos: [x, y, .15 - Math.abs(x) * .3], outline: false, parent: eyes }));
  }
  return finish(ch);
}

/* ---------- Кронов в экзокостюме ---------- */
function buildKronov(ch, d) {
  const k = d.k, J = ch.J, OL = .016 * k;
  const metal = toon(0x4a5260), dark = toon(0x262b33), orange = toon(0xff6a17);
  const visorM = glow(0xff2a1a, 3.2), coreM = glow(0xffa340, 3);
  ch.mats = { metal, dark, orange, visorM, coreM };
  const R = rbox;
  mesh(R(.4 * k, .22 * k, .28 * k, .06 * k), dark, { pos: [0, 0, 0], outline: OL, parent: J.hips });
  const torso = mesh(R(.62 * k, .5 * k, .4 * k, .1 * k), metal, { pos: [0, .28 * k, 0], outline: OL, parent: J.spine });
  mesh(R(.5 * k, .12 * k, .42 * k, .05 * k), orange, { pos: [0, .5 * k, 0], outline: OL, parent: J.spine });
  ch.core = mesh(new THREE.CylinderGeometry(.075 * k, .075 * k, .05 * k, 24), coreM, { pos: [0, .32 * k, .2 * k], rot: [Math.PI / 2, 0, 0], outline: OL, parent: J.spine });
  mesh(R(.32 * k, .3 * k, .14 * k, .05), dark, { pos: [0, .3 * k, -.25 * k], outline: OL, parent: J.spine }); // ранец
  for (const sx of [1, -1]) mesh(new THREE.CylinderGeometry(.05 * k, .07 * k, .12 * k, 12), dark, { pos: [sx * .1 * k, .35 * k, -.36 * k], rot: [.3, 0, 0], outline: OL, parent: J.spine });
  // шлем
  mesh(R(.3 * k, .3 * k, .32 * k, .11 * k), metal, { pos: [0, .14 * k, 0], outline: OL, parent: J.head });
  ch.visor = mesh(R(.25 * k, .07 * k, .05 * k, .02 * k), visorM, { pos: [0, .16 * k, .15 * k], outline: OL * .7, parent: J.head });
  mesh(R(.06 * k, .1 * k, .3 * k, .02 * k), orange, { pos: [0, .3 * k, -.01], outline: OL, parent: J.head });
  for (const s of ['L', 'R']) {
    const sx = s === 'L' ? 1 : -1;
    mesh(sph(.16 * k, 16, 12), orange, { pos: [sx * .06 * k, .04 * k, 0], scale: [1.1, .8, 1], outline: OL, parent: J['arm' + s] });
    mesh(cap(.09 * k, d.upper), metal, { pos: [0, -d.upper / 2, 0], outline: OL, parent: J['arm' + s] });
    mesh(cap(.105 * k, d.lower + .04 * k), dark, { pos: [0, -d.lower / 2, 0], outline: OL, parent: J['fore' + s] });
    mesh(R(.2 * k, .07 * k, .22 * k, .03 * k), orange, { pos: [0, -d.lower * .55, .02], outline: OL * .8, parent: J['fore' + s] });
    mesh(R(.17 * k, .17 * k, .17 * k, .05 * k), metal, { pos: [0, -.07 * k, .01], outline: OL, parent: J['hand' + s] });
    mesh(cap(.11 * k, d.thigh + .05 * k), metal, { pos: [0, -d.thigh / 2, 0], outline: OL, parent: J['leg' + s] });
    mesh(sph(.1 * k, 12, 10), orange, { pos: [0, 0, .06 * k], outline: OL, parent: J['shin' + s] });
    mesh(cap(.1 * k, d.shin + .03 * k), dark, { pos: [0, -d.shin / 2, 0], outline: OL, parent: J['shin' + s] });
    mesh(R(.2 * k, .13 * k, .34 * k, .05 * k), metal, { pos: [0, -.03 * k, .07 * k], outline: OL, parent: J['foot' + s] });
  }
  // светящееся ядро «Арахны», которое Кронов уносит (по умолчанию скрыто)
  const stolen = new THREE.Group(); J.handL.add(stolen); stolen.position.set(0, -.2 * k, .05); stolen.visible = false;
  mesh(new THREE.CylinderGeometry(.06, .06, .22, 16), glow(0x5ff6ff, 3), { outline: .012, parent: stolen });
  ch.stolen = stolen;
  return finish(ch);
}

function finish(ch) {
  ch.pose = p => applyPose(ch, p);
  ch.setFace = f => setFace(ch, f);
  ch.setSuit = on => setSuit(ch, on);
  ch.root.traverse(o => { if (o.isMesh) o.frustumCulled = false; });
  return ch;
}

function setSuit(ch, on) {
  if (ch.suit === on || ch.kind !== 'timur') return;
  ch.suit = on;
  const sm = suitMaterial();
  for (const role of ['top', 'pants', 'skin', 'hand', 'shoes']) for (const m of ch.parts[role] || []) m.material = on ? sm : m.userData.base;
  for (const role of ['hair', 'face', 'acc']) for (const m of ch.parts[role] || []) m.visible = !on;
  ch.lenses.visible = on;
}

/* ---------- позы ---------- */
const ZERO = [0, 0, 0];
function applyPose(ch, p) {
  const J = ch.J;
  for (const n of JOINTS) {
    const v = p[n] || ZERO;
    const mir = n.endsWith('R') && n !== 'hips';
    J[n].rotation.set(v[0], mir ? -v[1] : v[1], mir ? -v[2] : v[2]);
  }
  J.hips.position.set(p.hx || 0, ch.d.hipY + (p.hy || 0) * ch.d.k, p.hz || 0);
}
export function blend(a, b, k) {
  if (k <= 0) return a; if (k >= 1) return b;
  const o = {};
  for (const n of [...JOINTS, 'hx', 'hy', 'hz']) {
    const va = a[n], vb = b[n];
    if (va === undefined && vb === undefined) continue;
    if (typeof (va ?? vb) === 'number') o[n] = lerp(va || 0, vb || 0, k);
    else { const A = va || ZERO, B = vb || ZERO; o[n] = [lerp(A[0], B[0], k), lerp(A[1], B[1], k), lerp(A[2], B[2], k)]; }
  }
  return o;
}
/* Последовательность поз: [[t, poseOrFn], ...] с плавным переходом xf секунд перед каждой */
export function seq(t, list, xf = .25) {
  let i = 0;
  while (i + 1 < list.length && t >= list[i + 1][0]) i++;
  const cur = typeof list[i][1] === 'function' ? list[i][1](t - list[i][0]) : list[i][1];
  if (i > 0) {
    const k = clamp((t - list[i][0]) / (list[i][2] ?? xf));
    if (k < 1) {
      const prev = typeof list[i - 1][1] === 'function' ? list[i - 1][1](t - list[i - 1][0]) : list[i - 1][1];
      return blend(prev, cur, E.inOutSine(k));
    }
  }
  return cur;
}

const S = Math.sin, Cc = Math.cos, PI = Math.PI;
export const POSE = {
  stand: (t = 0) => ({ armL: [.03, 0, .1 + .01 * S(t * 2)], armR: [.03, 0, .1 + .01 * S(t * 2)], foreL: [-.2, 0, 0], foreR: [-.2, 0, 0],
    spine: [.01 * S(t * 2), 0, 0], legL: [0, 0, .03], legR: [0, 0, .03], hy: .004 * S(t * 2) }),
  talk: (t = 0) => ({ ...POSE.stand(t), armL: [-.35 - .15 * S(t * 3.1), .2, .25], foreL: [-1.1 - .2 * S(t * 4), 0, 0], handL: [0, 0, .3],
    armR: [.05, 0, .12], foreR: [-.3, 0, 0], head: [.05 * S(t * 2.3), .08 * S(t * 1.7), 0] }),
  run: (t, f = 1.6) => {
    const ph = t * f * PI * 2, s = S(ph), c = Cc(ph);
    return { spine: [.28, 0, 0], chest: [.05, .12 * s, 0], head: [-.25, -.1 * s, 0],
      armL: [.9 * s, 0, .15], armR: [-.9 * s, 0, .15], foreL: [-1.4, 0, 0], foreR: [-1.4, 0, 0],
      legL: [-.85 * s - .2, 0, 0], legR: [.85 * s - .2, 0, 0], shinL: [.7 + .7 * Math.max(0, c), 0, 0], shinR: [.7 + .7 * Math.max(0, -c), 0, 0],
      footL: [.2, 0, 0], footR: [.2, 0, 0], hy: -.04 + .04 * Math.abs(c) };
  },
  walk: (t, f = .9) => {
    const ph = t * f * PI * 2, s = S(ph), c = Cc(ph);
    return { spine: [.04, 0, 0], chest: [0, .06 * s, 0], armL: [.35 * s, 0, .1], armR: [-.35 * s, 0, .1], foreL: [-.35, 0, 0], foreR: [-.35, 0, 0],
      legL: [-.4 * s, 0, 0], legR: [.4 * s, 0, 0], shinL: [.35 * Math.max(0, c) + .05, 0, 0], shinR: [.35 * Math.max(0, -c) + .05, 0, 0], hy: .02 * Math.abs(c) - .02 };
  },
  heavyWalk: (t, f = .7) => { const p = POSE.walk(t, f); p.spine = [.1, 0, 0]; p.armL[2] = .35; p.armR[2] = .35; p.hy -= .03; return p; },
  bike: (t, cad = 1.4) => {
    const ph = t * cad * PI * 2, s = S(ph), c = Cc(ph);
    return { hy: -.2, hz: -.08, spine: [.62, 0, 0], chest: [.12, 0, 0], neck: [-.3, 0, 0], head: [-.45, 0, 0],
      armL: [-1.12, 0, .2], armR: [-1.12, 0, .2], foreL: [-.35, 0, -.1], foreR: [-.35, 0, -.1], handL: [.2, 0, 0], handR: [.2, 0, 0],
      legL: [-1.15 - .35 * s, 0, .05], legR: [-1.15 + .35 * s, 0, .05], shinL: [1.45 + .4 * c, 0, 0], shinR: [1.45 - .4 * c, 0, 0],
      footL: [-.2, 0, 0], footR: [-.2, 0, 0] };
  },
  bikeStand: () => ({ hy: -.25, hz: -.05, spine: [.9, 0, 0], chest: [.1, 0, 0], head: [-.7, 0, 0], armL: [-1.25, 0, .25], armR: [-1.25, 0, .25], foreL: [-.6, 0, 0], foreR: [-.6, 0, 0],
    legL: [-.9, 0, .15], legR: [-.5, 0, .15], shinL: [1.1, 0, 0], shinR: [.7, 0, 0] }),
  crouch: () => ({ hy: -.42, spine: [.55, 0, 0], head: [-.5, 0, 0], armL: [-.5, 0, .35], armR: [-.5, 0, .35], foreL: [-.6, 0, 0], foreR: [-.6, 0, 0],
    legL: [-1.6, 0, .35], legR: [-1.6, 0, .35], shinL: [2.2, 0, 0], shinR: [2.2, 0, 0], footL: [-.5, 0, 0], footR: [-.5, 0, 0] }),
  spiderCrouch: (t = 0) => ({ hy: -.48, spine: [.7, 0, 0], head: [-.85, .15 * S(t * 1.3), 0], armL: [-.9, -.4, .9], armR: [-.9, -.4, .9], foreL: [-1.1, 0, 0], foreR: [-1.1, 0, 0],
    handL: [.4, 0, 0], handR: [.4, 0, 0], legL: [-1.5, 0, .75], legR: [-1.5, 0, .75], shinL: [2.4, 0, 0], shinR: [2.4, 0, 0], footL: [-.7, 0, 0], footR: [-.7, 0, 0] }),
  heroLand: () => ({ hy: -.5, spine: [.75, -.1, 0], head: [-.7, .1, 0], armL: [.4, 0, .9], foreL: [-.3, 0, 0], armR: [-1.0, 0, .2], foreR: [-.2, 0, 0], handR: [-.6, 0, 0],
    legL: [-1.7, 0, .25], shinL: [2.3, 0, 0], footL: [-.6, 0, 0], legR: [-.2, 0, .1], shinR: [2.5, 0, 0], footR: [.6, 0, 0] }),
  lie: (t = 0) => ({ armL: [0, 0, .5], armR: [-.3, 0, .8], foreL: [-.4, 0, 0], foreR: [-.1, 0, 0], legL: [0, 0, .1], legR: [-.3, 0, .05], shinR: [.6, 0, 0],
    head: [0, .3, 0], spine: [.02 * S(t * 2), 0, 0] }),
  sitUp: () => ({ hy: -.6, spine: [.4, 0, 0], head: [-.2, 0, 0], armL: [.5, 0, .3], armR: [-.3, 0, .2], foreL: [-.3, 0, 0], foreR: [-1.4, 0, 0],
    legL: [-1.45, 0, .1], legR: [-1.2, 0, .2], shinL: [.2, 0, 0], shinR: [1.2, 0, 0] }),
  lookHand: (t = 0) => ({ hy: -.6, spine: [.3, 0, 0], head: [.25, -.25, 0], armL: [.3, 0, .3], foreL: [-.2, 0, 0], armR: [-1.2, -.5, .1], foreR: [-1.4, 0, 0], handR: [.3 * S(t * 2), 0, -.3],
    legL: [-1.45, 0, .1], legR: [-1.2, 0, .2], shinL: [.2, 0, 0], shinR: [1.2, 0, 0] }),
  fall: t => ({ spine: [-.3 + .2 * S(t * 7), .3 * S(t * 3), 0], head: [.3, 0, 0], armL: [-2.6 + .5 * S(t * 11), 0, .6 + .3 * S(t * 9)], armR: [-2.4 + .5 * S(t * 10 + 1), 0, .7 + .3 * S(t * 8)],
    foreL: [-.5, 0, 0], foreR: [-.4, 0, 0], legL: [-.6 + .6 * S(t * 9), 0, .3], legR: [-.3 - .6 * S(t * 9), 0, .3], shinL: [.9, 0, 0], shinR: [.8, 0, 0] }),
  shootUp: () => ({ spine: [-.15, 0, 0], head: [.35, 0, 0], armR: [-2.9, 0, .15], foreR: [0, 0, 0], handR: [-.9, 0, 0], armL: [.3, 0, .8], foreL: [-.6, 0, 0],
    legL: [-.4, 0, .1], legR: [.2, 0, .1], shinL: [.9, 0, 0], shinR: [.5, 0, 0] }),
  shootFwd: (arm = 'R') => {
    const o = { spine: [.1, .15, 0], head: [0, -.1, 0], armL: [.2, 0, .3], foreL: [-1.2, 0, 0], armR: [.2, 0, .3], foreR: [-1.2, 0, 0], legL: [-.4, 0, .15], legR: [.3, 0, .1], shinL: [.5, 0, 0], shinR: [.3, 0, 0], hy: -.08 };
    o['arm' + arm] = [-1.55, 0, .05]; o['fore' + arm] = [0, 0, 0]; o['hand' + arm] = [-1.0, 0, 0];
    return o;
  },
  swing: t => ({ spine: [-.15, 0, .05 * S(t * 2)], head: [.1, 0, 0], armR: [-3.0, 0, .1], foreR: [-.05, 0, 0], handR: [-.6, 0, 0], armL: [-.4, 0, 1.0], foreL: [-.9, 0, 0],
    legL: [-.9, 0, .1], legR: [-.25, 0, .1], shinL: [1.4, 0, 0], shinR: [.5, 0, 0], footL: [.3, 0, 0], footR: [.4, 0, 0] }),
  flip: t => ({ spine: [.9, 0, 0], head: [-.4, 0, 0], armL: [-1.4, 0, .3], armR: [-1.4, 0, .3], foreL: [-1.6, 0, 0], foreR: [-1.6, 0, 0],
    legL: [-2.0, 0, .1], legR: [-2.0, 0, .1], shinL: [2.4, 0, 0], shinR: [2.4, 0, 0], hy: -.2 }),
  pull: (t = 0) => ({ hy: -.3, hz: -.15, spine: [-.35, 0, 0], head: [.15 + .03 * S(t * 23), 0, 0], armL: [-1.35, .1, .12], armR: [-1.35, .1, .12], foreL: [-.15, 0, 0], foreR: [-.15, 0, 0],
    handL: [-.4, 0, 0], handR: [-.4, 0, 0], legL: [-1.2, 0, .2], legR: [.35, 0, .15], shinL: [1.4, 0, 0], shinR: [.35, 0, 0], footL: [-.2, 0, 0] }),
  hangUpside: t => ({ spine: [0, 0, .04 * S(t * 1.5)], head: [0, 0, 0], armL: [-.3, 0, .25 + .05 * S(t * 2)], armR: [-.4, -.4, .3], foreL: [-1.9, 0, 0], foreR: [-1.8, 0, 0],
    legL: [0, 0, -.02], legR: [0, 0, -.02], shinL: [.05, 0, 0], shinR: [.05, 0, 0], footL: [.6, 0, 0], footR: [.6, 0, 0] }),
  sitChair: (t = 0) => ({ hy: -.42, hz: -.05, spine: [.08, 0, 0], legL: [-1.55, 0, .08], legR: [-1.55, 0, .08], shinL: [1.55, 0, 0], shinR: [1.55, 0, 0],
    armL: [-.6, 0, .15], armR: [-.6, 0, .15], foreL: [-.9, 0, 0], foreR: [-.9, 0, 0], head: [.04 * S(t), 0, 0] }),
  punch: (t, arm = 'R') => {
    const k = E.outCubic(clamp(t / .18)) * (1 - E.inQuad(clamp((t - .35) / .4)));
    const o = { spine: [.2, -.4 * k, 0], chest: [0, -.3 * k, 0], armL: [-.5, 0, .3], foreL: [-1.6, 0, 0], armR: [-.5, 0, .3], foreR: [-1.6, 0, 0], legL: [-.5, 0, .1], legR: [.4, 0, .1], shinL: [.4, 0, 0], hy: -.1 };
    o['arm' + arm] = [lerp(-.5, -1.55, k), 0, lerp(.3, .05, k)]; o['fore' + arm] = [lerp(-1.6, -.05, k), 0, 0];
    return o;
  },
  roar: (t = 0) => ({ spine: [-.25, 0, 0], head: [-.35, 0, 0], armL: [-.3, 0, 1.0 + .05 * S(t * 30)], armR: [-.3, 0, 1.0 + .05 * S(t * 30)], foreL: [-1.3, 0, 0], foreR: [-1.3, 0, 0], legL: [-.2, 0, .25], legR: [-.2, 0, .25], shinL: [.3, 0, 0], shinR: [.3, 0, 0], hy: -.05 }),
  dodge: () => ({ hy: -.35, spine: [.3, 0, .9], head: [0, 0, -.5], armL: [-.4, 0, 1.6], foreL: [-.4, 0, 0], armR: [.2, 0, .4], foreR: [-1.0, 0, 0],
    legL: [-.3, 0, .6], legR: [-1.0, 0, -.1], shinL: [.3, 0, 0], shinR: [1.6, 0, 0] }),
  strained: t => ({ spine: [.35, .4 * S(t * 2), .2 * S(t * 3)], head: [-.2, 0, 0], armL: [-1.1 + .3 * S(t * 25), 0, .5], armR: [-.9 + .3 * S(t * 23), 0, .5], foreL: [-.5, 0, 0], foreR: [-.5, 0, 0],
    legL: [-.3, 0, .2], legR: [-.3, 0, .2], shinL: [.5, 0, 0], shinR: [.5, 0, 0], hy: -.1 }),
  collapse: () => ({ hy: -.55, spine: [.9, 0, .2], head: [.4, 0, .3], armL: [.2, 0, .3], armR: [.4, 0, .1], foreL: [-.3, 0, 0], foreR: [-.2, 0, 0],
    legL: [-1.4, 0, .3], legR: [-1.0, 0, .3], shinL: [2.3, 0, 0], shinR: [2.0, 0, 0] }),
  phone: (t = 0) => ({ ...POSE.stand(t), armR: [-.5, .4, .45], foreR: [-2.3, 0, 0], handR: [0, 0, .5], head: [0, -.1, .1] }),
  reach: () => ({ spine: [.2, 0, 0], armR: [-1.4, .2, .1], foreR: [-.2, 0, 0], handR: [.2, 0, 0], armL: [.1, 0, .15], foreL: [-.4, 0, 0], head: [.2, 0, 0] }),
  hold: () => ({ armL: [-.9, .3, .1], armR: [-.9, .3, .1], foreL: [-.8, 0, 0], foreR: [-.8, 0, 0], handL: [0, 0, -.3], handR: [0, 0, -.3], spine: [.05, 0, 0] }),
  lookUp: (t = 0) => ({ ...POSE.stand(t), spine: [-.12, 0, 0], neck: [-.3, 0, 0], head: [-.35, 0, 0], armL: [-.2, 0, .15], foreL: [-.6, 0, 0] }),
};

/* ---------- мимика ---------- */
function setFace(ch, f = {}) {
  if (ch.kind === 'kronov') {
    const s = 1 + (f.mouth || 0) * .8;
    ch.mats.visorM.color.setRGB(3.2 * s * (f.dim ?? 1), .25 * s * (f.dim ?? 1), .16 * (f.dim ?? 1));
    return;
  }
  if (ch.suit) {
    for (const L of ch.lensList) L.scale.set(1.25, .82 * (f.squint ?? 1) * (1 - .9 * (f.blink || 0)), .35);
    return;
  }
  const fr = ch.faceRig; if (!fr) return;
  const blink = f.blink || 0;
  const look = f.look || [0, 0];
  fr.eyes.forEach((e, i) => { e.scale.y = 1.2 * Math.max(.08, 1 - blink) * (f.wide ? 1.15 : 1); e.scale.x = f.wide ? 1.12 : 1; });
  fr.pupils.forEach(p => { p.position.x = look[0] * .012; p.position.y = look[1] * .012; });
  const br = f.brow || 0; // >0 — тревога/удивление, <0 — злость
  fr.brows.forEach((b, i) => { const sx = i === 0 ? 1 : -1; b.rotation.z = sx * br * .35; b.position.y = fr.headC.y + .085 + Math.abs(br) * .015 * Math.sign(br); });
  const mo = clamp(f.mouth || 0);
  fr.mouth.scale.set(1.3 - mo * .25 + (f.smile || 0) * .4, .22 + mo * 1.15, .45);
}
/* моргание: детерминированно по времени */
export function blinkAt(t, seed = 0) {
  const period = 3.1 + seed * .7, ph = ((t + seed * 1.3) % period) / period * period;
  return ph < .13 ? Math.sin(ph / .13 * Math.PI) : 0;
}

/* ---------- механический паучок «Арахна» ---------- */
export function makeSpider(o = {}) {
  const s = o.scale || 1;
  const g = new THREE.Group();
  const body = toon(o.gold ? 0xd9a441 : 0x5b6575), dark = toon(0x1c2129);
  const eye = glow(o.gold ? 0x6ffcff : 0x3ff0ff, 3);
  const OL = .006 * s;
  const ab = mesh(sph(.1 * s, 16, 12), body, { pos: [0, .06 * s, -.12 * s], scale: [1, .8, 1.25], outline: OL, parent: g });
  mesh(sph(.05 * s, 12, 8), eye, { pos: [0, .06 * s, -.03 * s], scale: [1, .4, 1.4], outline: false, parent: ab }); // светящаяся полоса на брюшке
  const th = mesh(sph(.065 * s, 14, 10), dark, { pos: [0, .055 * s, .03 * s], scale: [1, .8, 1.1], outline: OL, parent: g });
  for (const [x, y] of [[-.022, .02], [.022, .02], [-.04, .005], [.04, .005]]) mesh(sph(.012 * s, 8, 6), eye, { pos: [x * s, (.07 + y) * s, .09 * s], outline: false, parent: g });
  const legs = [];
  for (let i = 0; i < 8; i++) {
    const side = i < 4 ? 1 : -1, j = i % 4;
    const hip = new THREE.Group(); hip.position.set(side * .045 * s, .06 * s, (.06 - j * .04) * s);
    hip.rotation.y = side * (Math.PI / 2) + (j - 1.5) * .45 * side; g.add(hip);
    const upper = new THREE.Group(); upper.rotation.z = 0; hip.add(upper);
    mesh(cap(.011 * s, .14 * s), dark, { pos: [0, 0, .065 * s], rot: [Math.PI / 2, 0, 0], outline: OL * .6, parent: upper });
    const knee = new THREE.Group(); knee.position.z = .13 * s; upper.add(knee);
    mesh(cap(.009 * s, .16 * s), body, { pos: [0, 0, .075 * s], rot: [Math.PI / 2, 0, 0], outline: OL * .6, parent: knee });
    legs.push({ hip, upper, knee, side, j });
  }
  g.userData.legs = legs;
  g.userData.anim = (t, walk = 0, twitch = 0) => {
    for (const L of legs) {
      const ph = t * 9 * walk + L.j * Math.PI / 2 + (L.side > 0 ? 0 : Math.PI);
      L.upper.rotation.x = -.55 - .25 * Math.max(0, Math.sin(ph)) * walk - .3 * twitch * Math.sin(t * 40 + L.j);
      L.knee.rotation.x = 1.25 + .2 * Math.sin(ph) * walk;
      L.hip.rotation.y = L.side * (Math.PI / 2) + (L.j - 1.5) * .45 * L.side + .2 * Math.cos(ph) * walk;
    }
  };
  g.userData.anim(0);
  g.traverse(m => { if (m.isMesh) m.frustumCulled = false; });
  return g;
}
