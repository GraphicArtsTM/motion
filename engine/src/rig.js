// Персонажи: иерархический риг из примитивов, библиотека поз, мимика.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon, glow, mesh, lerp, clamp, noise, E, rimify } from './core.js';

const cap = (r, len) => new THREE.CapsuleGeometry(r, Math.max(len - 2 * r, .001), 8, 22);
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
  SUIT_MAT.emissiveIntensity = 1.35;
  rimify(SUIT_MAT, 0x5fe8ff, .55, 2.2);
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

/* ---------- лицо: глаза с радужкой и бликом, веки, брови, рот с зубами ---------- */
function addFace(J, o, R) {
  const headC = new THREE.Vector3(0, .13, 0);
  const onSphere = (x, y, push = 0) => new THREE.Vector3(x, headC.y + y, Math.sqrt(Math.max(R * R - x * x - y * y, 0)) + push);
  const face = new THREE.Group(); J.head.add(face);
  const white = new THREE.MeshBasicMaterial({ color: 0xe6e6e2 }), dark = new THREE.MeshBasicMaterial({ color: 0x0b0908 });
  const irisM = toon(o.iris || 0x5a3418), shine = new THREE.MeshBasicMaterial({ color: 0xffffff });
  const lidM = toon(o.skin);
  const ek = o.eyeK || 1, er = .036 * ek;
  const eyes = [], pupils = [], brows = [], lids = [], lowLids = [], cheeks = [];
  for (const sx of [1, -1]) {
    const pos = onSphere(sx * .058, .025, -.012);
    const e = mesh(sph(er), white, { pos: pos.toArray(), scale: [1, 1.2, .55], outline: .006 });
    face.add(e); eyes.push(e);
    const iris = new THREE.Group(); iris.position.z = er * .78; e.add(iris);
    mesh(sph(er * .62, 14, 10), irisM, { scale: [1, 1, .5], parent: iris });
    mesh(sph(er * .33, 12, 8), dark, { pos: [0, 0, er * .2], scale: [1, 1, .5], parent: iris });
    mesh(sph(er * .14, 8, 6), shine, { pos: [er * .2, er * .25, er * .3], parent: iris });
    pupils.push(iris);
    // верхнее веко: полусфера цвета кожи, поворотом закрывает глаз
    const lid = new THREE.Group(); lid.position.copy(pos); lid.scale.set(1.08, 1.25, .62); face.add(lid);
    mesh(new THREE.SphereGeometry(er * 1.06, 18, 10, 0, Math.PI * 2, 0, Math.PI / 2), lidM, { outline: .005, parent: lid });
    lids.push(lid);
    if (o.lashes) for (let i = 0; i < 3; i++) mesh(new THREE.BoxGeometry(.004, .016, .003), dark, { pos: [sx * (.012 + i * .011), .004, er * 1.04], rot: [-.3, 0, sx * (.35 + i * .3)], parent: lid });
    // нижнее веко: поднимается при улыбке и прищуре
    const ll = new THREE.Group(); ll.position.copy(pos); ll.scale.set(1.06, 1.2, .6); face.add(ll);
    mesh(new THREE.SphereGeometry(er * 1.05, 18, 8, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), lidM, { outline: .004, parent: ll });
    lowLids.push(ll);
    // щёки: приподнимаются при улыбке
    const ck = mesh(sph(.03, 12, 8), lidM, { pos: onSphere(sx * .072, -.042, -.012).toArray(), scale: [1.3, .85, .5], parent: face });
    cheeks.push(ck); ck.userData.y0 = ck.position.y;

    const bw = mesh(rbox(.078, .022, .026, .01), toon(o.brow || o.hair || 0x222222), { pos: onSphere(sx * .06, .088, .006).toArray(), outline: .004 });
    face.add(bw); brows.push(bw);
  }
  // рот: тёмная полость + верхние зубы + язык
  const mouth = new THREE.Group(); mouth.position.copy(onSphere(0, -.068, -.008)); face.add(mouth);
  const cav = mesh(sph(.03, 16, 10), toon(0x3a0d10), { scale: [1.3, .25, .45], outline: .004, parent: mouth });
  const teeth = mesh(rbox(.042, .012, .01, .004), white, { pos: [0, .009, .01], parent: mouth });
  const tongue = mesh(sph(.017, 10, 8), toon(0xc0505a), { pos: [0, -.012, .006], scale: [1.3, .6, .6], parent: mouth });
  const nose = mesh(sph(.024, 12, 8), toon(o.skin), { pos: onSphere(0, -.01, -.004).toArray(), scale: [1, .9, 1.1], outline: .004 });
  face.add(nose);
  for (const sx of [1, -1]) mesh(sph(.035, 12, 8), toon(o.skin), { pos: [sx * R * .98, headC.y, -.01], scale: [.5, 1, .8], outline: .005, parent: face });
  if (o.blush) for (const sx of [1, -1]) mesh(sph(.022, 10, 8), toon(o.blush, { transparent: true, opacity: .45 }), { pos: onSphere(sx * .085, -.035, -.004).toArray(), scale: [1.3, .7, .3], parent: face });
  if (o.wrinkles) for (const sx of [1, -1]) mesh(new THREE.TorusGeometry(.03, .003, 4, 12, Math.PI * .7), toon(0x9a5a3c), { pos: onSphere(sx * .058, -.018, .0).toArray(), rot: [0, 0, Math.PI + Math.PI * .15], parent: face });
  return { face, eyes, pupils, brows, lids, lowLids, cheeks, mouth, cav, teeth, tongue, headC, nose };
}

/* ---------- кисть с пальцами ---------- */
function makeHand(mat, k, OL, side) {
  const g = new THREE.Group(); g.scale.setScalar(k);
  mesh(rbox(.04, .075, .07, .017), mat, { pos: [0, -.042, 0], outline: OL * .7, parent: g });
  const fingers = [];
  [.027, .009, -.009, -.026].forEach((z, i) => {
    const s1 = new THREE.Group(); s1.position.set(0, -.078, z * 1.0); g.add(s1);
    const L1 = i === 3 ? .026 : .033, L2 = i === 3 ? .022 : .028;
    mesh(cap(.0105, L1 + .01), mat, { pos: [0, -L1 / 2, 0], outline: OL * .5, parent: s1 });
    const s2 = new THREE.Group(); s2.position.y = -L1; s1.add(s2);
    mesh(cap(.0095, L2 + .008), mat, { pos: [0, -L2 / 2, 0], outline: OL * .5, parent: s2 });
    fingers.push({ s1, s2 });
  });
  const t1 = new THREE.Group(); t1.position.set(-side * .012, -.03, .037); t1.rotation.set(-.6, 0, side * .5); g.add(t1);
  mesh(cap(.011, .034), mat, { pos: [0, -.015, 0], outline: OL * .5, parent: t1 });
  const t2 = new THREE.Group(); t2.position.y = -.03; t1.add(t2);
  mesh(cap(.0105, .028), mat, { pos: [0, -.012, 0], outline: OL * .5, parent: t2 });
  return { g, fingers, thumb: [t1, t2], side };
}
/* curl: 0 — раскрытая ладонь, 1 — кулак; spider — жест «паутина» (средний и безымянный прижаты) */
function setGrip(h, curl = .35, spider = 0) {
  h.fingers.forEach((f, i) => {
    const c = spider && (i === 1 || i === 2) ? 1 : spider && (i === 0 || i === 3) ? 0 : curl;
    f.s1.rotation.z = -h.side * c * 1.35; f.s2.rotation.z = -h.side * c * 1.6;
    f.s1.rotation.x = (i - 1.5) * .06 * (1 - c);
  });
  const tc = spider ? 0 : curl;
  h.thumb[0].rotation.set(-.6 + tc * .4, 0, h.side * (.5 - tc * .9)); h.thumb[1].rotation.z = -h.side * tc * .8;
}

/* ---------- персонажи ---------- */
/* палитры школьников: верх, низ, волосы, обувь, кожа, причёска (0 — короткая, 1 — хвост, 2 — каре, 3 — кепка, 4 — ёжик), девочка */
const STUDENTS = [
  { top: 0xf4f4f0, pants: 0x2a3550, hair: 0x2a1a10, shoes: 0x1a1a1a, skin: 0xe0a77a, style: 0, girl: 0, vest: 0x24324f },
  { top: 0xe6dccb, pants: 0x3a3a44, hair: 0x5a3018, shoes: 0xf2f2f2, skin: 0xf0c3a0, style: 1, girl: 1 },
  { top: 0x7a8fb8, pants: 0x22252e, hair: 0x14100c, shoes: 0x2a2a2a, skin: 0xc98d68, style: 2, girl: 1 },
  { top: 0xd94f3c, pants: 0x2f3440, hair: 0x221410, shoes: 0xf2f2f2, skin: 0xd9996b, style: 3, girl: 0, cap: 0x1f5fa8 },
  { top: 0x3e7a5a, pants: 0x2a2a30, hair: 0x3a2a1a, shoes: 0x3a2a20, skin: 0xe8b48a, style: 4, girl: 0 },
  { top: 0xf2c94c, pants: 0x34405c, hair: 0x7a3a18, shoes: 0xf2f2f2, skin: 0xf0c3a0, style: 1, girl: 1 },
  { top: 0x9b5ab8, pants: 0x262a33, hair: 0x101010, shoes: 0x1a1a1a, skin: 0xb07650, style: 2, girl: 1 },
  { top: 0xf4f4f0, pants: 0x2a3550, hair: 0x4a2e18, shoes: 0x1a1a1a, skin: 0xd9996b, style: 0, girl: 0, vest: 0x5a2030 },
  { top: 0x2b2f38, pants: 0x1e2028, hair: 0x14100c, shoes: 0xf2f2f2, skin: 0xc98d68, style: 3, girl: 0, cap: 0xd94f3c },   // дружок Азима в кепке
  { top: 0x1d4fa0, pants: 0x2a2a30, hair: 0x2a1a10, shoes: 0xf2f2f2, skin: 0xe0a77a, style: 4, girl: 0 },                 // второй дружок — тоже в куртке команды
  { top: 0xe8a0b0, pants: 0x2a3550, hair: 0x2a1a10, shoes: 0xf2f2f2, skin: 0xd9996b, style: 2, girl: 1 },
  { top: 0x5a8ac0, pants: 0x3a3a44, hair: 0x1a120c, shoes: 0x1a1a1a, skin: 0xc98d68, style: 0, girl: 0, vest: 0x2a4a3a },
  { top: 0xf4f4f0, pants: 0x262a33, hair: 0x6a4a2a, shoes: 0x2a2a2a, skin: 0xf0c3a0, style: 1, girl: 1, vest: 0x24324f },
  { top: 0xc8783a, pants: 0x2a2a30, hair: 0x14100c, shoes: 0xf2f2f2, skin: 0xb07650, style: 4, girl: 0 },
  { top: 0x6ab89a, pants: 0x34405c, hair: 0x3a2a1a, shoes: 0xf2f2f2, skin: 0xe8b48a, style: 2, girl: 1 },
  { top: 0x8a8a94, pants: 0x1e2028, hair: 0x2a1a10, shoes: 0x1a1a1a, skin: 0xe0a77a, style: 3, girl: 0, cap: 0x2f8a4a },
];
export function makeCharacter(kind, opt = {}) {
  const SV = kind === 'student' ? STUDENTS[(opt.variant ?? 0) % STUDENTS.length] : null;
  const k = kind === 'kronov' ? 1.6 : kind === 'ded' ? 1.0 : kind === 'vera' ? .96 : kind === 'azim' ? 1.1 : kind === 'odilman' ? 1.08 : kind === 'marjon' ? .97 : kind === 'teacher' ? .95
    : SV ? (SV.girl ? .95 : 1.0) + ((opt.variant ?? 0) % 3 - 1) * .025 : 1.0;
  const d = DIM(k);
  if (kind === 'azim' || kind === 'odilman') d.shX = .235 * k;            // широкие плечи
  const { root, J } = skeleton(d);
  const ch = { kind, root, J, d, parts: {}, suit: false, faceRig: null, extras: {} };
  const OL = .012 * k;
  const C = {
    timur: { skin: 0xd9996b, hair: 0x22160f, top: 0xff7b1c, topDark: 0xc95410, pants: 0x283554, shoes: 0xf3f1ea },
    ded: { skin: 0xc98d68, hair: 0xd9d6d0, top: 0x2b3f6b, topDark: 0x1d2c4d, pants: 0x232f4a, shoes: 0x1a1a1a },
    vera: { skin: 0xf0c3a0, hair: 0xd8481f, top: 0xf4f6f8, topDark: 0xc9d2da, pants: 0x3b3446, shoes: 0x2a2a2a },
    shadow: { skin: 0x050507, hair: 0x050507, top: 0x07070a, topDark: 0x050507, pants: 0x050507, shoes: 0x050507 },
    marjon: { skin: 0xeab38c, hair: 0x7a2a16, top: 0x2f6b4f, topDark: 0x2f6b4f, pants: 0x2c3a5c, shoes: 0xf3f1ea },
    diyor: { skin: 0xe6b48f, hair: 0x120d0a, top: 0x1e2b4a, topDark: 0x1e2b4a, pants: 0x2b2e36, shoes: 0x4a2a18 },
    azim: { skin: 0xc98d68, hair: 0x1a120c, top: 0x1d4fa0, topDark: 0xf2f2ee, pants: 0x2a2a30, shoes: 0xf2f2f2 },
    teacher: { skin: 0xf0c3a0, hair: 0xa8a39c, top: 0x7a2e3c, topDark: 0x7a2e3c, pants: 0x4a4550, shoes: 0x2a2a2a },
    odilman: { skin: 0xc98d68, hair: 0x111111, top: 0xffffff, topDark: 0x1b2440, pants: 0xffffff, shoes: 0x1b2440 },
    student: SV && { skin: SV.skin, hair: SV.hair, top: SV.top, topDark: SV.top, pants: SV.pants, shoes: SV.shoes },
  }[kind] || {};
  ch.colors = C;

  if (kind === 'kronov') return buildKronov(ch, d);

  const m = {
    skin: toon(C.skin), top: toon(C.top), topDark: toon(C.topDark), pants: toon(C.pants), shoes: toon(C.shoes), hair: toon(C.hair),
    hand: toon(kind === 'odilman' ? C.topDark : C.skin, { emissive: 0x000000 }),
  };
  if (kind === 'odilman') { m.top = odilSuit(); m.pants = m.top; }
  ch.mats = m;
  const reg = (role, msh) => { (ch.parts[role] = ch.parts[role] || []).push(msh); msh.userData.role = role; msh.userData.base = msh.material; return msh; };

  // таз и торс
  reg('pants', mesh(rbox(.3 * k, .17 * k, .19 * k, .07 * k), m.pants, { pos: [0, .01 * k, 0], outline: OL, parent: J.hips }));
  const belly = kind === 'ded' ? 1.18 : 1;
  const wide = kind === 'azim' ? 1.42 : kind === 'odilman' ? 1.38 : kind === 'marjon' || SV?.girl || kind === 'teacher' ? 1.1 : kind === 'diyor' ? 1.16 : 1.22;
  const torso = reg('top', mesh(cap(.155 * k, .46 * k), m.top, { pos: [0, .2 * k, .0], scale: [wide, 1, .82 * belly * (kind === 'azim' ? 1.12 : 1)], outline: OL, parent: J.spine }));
  ch.torso = torso;
  if (kind === 'teacher' || (SV?.girl && SV.style === 2)) {   // юбка до колен
    reg('pants', mesh(new THREE.CylinderGeometry(.17 * k, .25 * k, .42 * k, 20, 1, true), toon(kind === 'teacher' ? 0x4a4550 : 0x2a2f3a, { side: THREE.DoubleSide }), { pos: [0, -.2 * k, 0], scale: [1, 1, .82], outline: OL, parent: J.hips }));
  }
  if (kind === 'vera') { // халат: юбка-конус от пояса
    const coat = reg('top', mesh(new THREE.CylinderGeometry(.19 * k, .27 * k, .55 * k, 20, 1, true), toon(C.top, { side: THREE.DoubleSide }), { pos: [0, -.27 * k, 0], scale: [1, 1, .8], outline: OL, parent: J.hips }));
    coat.userData.coat = true;
  }
  reg('skin', mesh(new THREE.CylinderGeometry(.05 * k, .055 * k, .12 * k, 12), m.skin, { pos: [0, .03 * k, 0], outline: OL * .7, parent: J.neck }));

  // голова
  const R = .165 * k;
  const head = reg('skin', mesh(sph(R, 28, 20), m.skin, { pos: [0, .13 * k, 0], scale: [1, 1.03, 1], outline: OL, parent: J.head }));
  ch.head = head;
  const girl = kind === 'vera' || kind === 'marjon' || kind === 'teacher' || !!SV?.girl;
  const fr = addFace(J, { skin: C.skin, hair: C.hair, brow: kind === 'ded' ? 0xe8e6e0 : kind === 'teacher' ? 0x8a857e : C.hair, eyeK: kind === 'vera' || kind === 'marjon' ? 1.05 : kind === 'azim' ? .9 : 1,
    iris: { timur: 0x6b3a1c, ded: 0x3d5a78, vera: 0x3f8a52, marjon: 0x5f7f32, diyor: 0x3a2414, azim: 0x2a1a10, teacher: 0x5a4a3a, odilman: 0x2a1a10 }[kind] || (SV ? [0x4a2a14, 0x2f5a7a, 0x3a5a2a][(opt.variant ?? 0) % 3] : 0x220000),
    blush: { timur: 0xe0705a, vera: 0xf08a80, marjon: 0xf0806e }[kind] || (SV?.girl ? 0xf08a80 : undefined),
    lashes: girl, wrinkles: kind === 'ded' }, .165);
  ch.faceRig = fr; fr.face.scale.setScalar(k); // лицо строится в единичном масштабе
  reg('face', fr.face);

  // руки
  for (const s of ['L', 'R']) {
    reg('top', mesh(cap((kind === 'azim' || kind === 'odilman' ? .068 : .058) * k, d.upper + .03 * k), kind === 'azim' ? m.topDark : m.top, { pos: [0, -d.upper / 2 + .01 * k, 0], outline: OL, parent: J['arm' + s] }));
    reg('top', mesh(cap(.05 * k, d.lower + .02 * k), kind === 'vera' ? m.top : m.topDark, { pos: [0, -d.lower / 2, 0], outline: OL, parent: J['fore' + s] }));
    const hd = makeHand(m.hand, k, OL, s === 'L' ? 1 : -1); J['hand' + s].add(hd.g); ch['hand' + s] = hd;
    hd.g.traverse(o => { if (o.isMesh && o.material === m.hand) reg('hand', o); });
    setGrip(hd, .35);
    // ноги
    reg('pants', mesh(cap(.078 * k, d.thigh + .04 * k), m.pants, { pos: [0, -d.thigh / 2, 0], outline: OL, parent: J['leg' + s] }));
    reg('pants', mesh(cap(.064 * k, d.shin + .03 * k), kind === 'odilman' ? m.topDark : m.pants, { pos: [0, -d.shin / 2, 0], outline: OL, parent: J['shin' + s] }));
    reg('shoes', mesh(rbox(.11 * k, .08 * k, .25 * k, .035 * k), m.shoes, { pos: [0, -.02 * k, .055 * k], outline: OL, parent: J['foot' + s] }));
  }

  // детали одежды
  for (const s of ['L', 'R']) {
    reg(kind === 'vera' ? 'top' : 'acc', mesh(new THREE.TorusGeometry(.05 * k, .016 * k, 6, 16), kind === 'timur' ? m.topDark : m.top, { pos: [0, -d.lower + .03 * k, 0], rot: [Math.PI / 2, 0, 0], outline: OL * .5, parent: J['fore' + s] }));
    reg('pants', mesh(new THREE.TorusGeometry(.064 * k, .018 * k, 6, 16), m.pants, { pos: [0, -d.shin + .05 * k, 0], rot: [Math.PI / 2, 0, 0], outline: OL * .5, parent: J['shin' + s] }));
    // подошва и шнуровка кроссовок/ботинок
    reg('acc', mesh(rbox(.118 * k, .03 * k, .262 * k, .012 * k), toon(kind === 'timur' ? 0xf7f7f2 : 0x2a2420), { pos: [0, -.058 * k, .058 * k], outline: OL * .6, parent: J['foot' + s] }));
    if (kind === 'timur') {
      reg('acc', mesh(rbox(.06 * k, .012 * k, .1 * k, .005), toon(0xffffff), { pos: [0, .022 * k, .09 * k], rot: [.35, 0, 0], outline: false, parent: J['foot' + s] }));
      reg('acc', mesh(rbox(.115 * k, .045 * k, .06 * k, .015 * k), toon(0xe8343c), { pos: [0, -.03 * k, -.04 * k], outline: false, parent: J['foot' + s] }));
    }
  }
  reg('acc', mesh(rbox(.31 * k, .035 * k, .2 * k, .012), toon(kind === 'vera' ? 0x2a2a2a : 0x1a1410), { pos: [0, .07 * k, 0], outline: OL * .5, parent: J.hips }));   // ремень
  if (kind === 'timur') {
    reg('acc', mesh(rbox(.2 * k, .085 * k, .03 * k, .02 * k), m.topDark, { pos: [0, .08 * k, .118 * k], outline: OL * .5, parent: J.spine }));    // карман-кенгуру
    for (const sx of [1, -1]) reg('acc', mesh(cap(.007 * k, .13 * k), toon(0xf4f1ea), { pos: [sx * .035 * k, .33 * k, .128 * k], rot: [-.1, 0, 0], outline: false, parent: J.spine }));
  }
  if (kind === 'ded') {
    for (let i = 0; i < 4; i++) reg('acc', mesh(sph(.012 * k, 8, 6), toon(0xd9a441, { emissive: 0x3a2a00 }), { pos: [.03 * k, (.09 + i * .085) * k, .136 * k], outline: false, parent: J.spine }));
    for (const sx of [1, -1]) reg('acc', mesh(rbox(.09 * k, .07 * k, .02 * k, .01), m.topDark, { pos: [sx * .05 * k, .41 * k, .1 * k], rot: [-.5, sx * .3, sx * .5], outline: OL * .5, parent: J.spine }));
    reg('acc', mesh(rbox(.06 * k, .03 * k, .012 * k, .005), toon(0xd9a441), { pos: [-.07 * k, .3 * k, .14 * k], outline: false, parent: J.spine }));
  }
  if (kind === 'vera') {
    for (const sx of [1, -1]) reg('acc', mesh(rbox(.06 * k, .2 * k, .015 * k, .006), m.topDark, { pos: [sx * .055 * k, .3 * k, .125 * k], rot: [0, 0, sx * .35], outline: OL * .5, parent: J.spine }));
    reg('acc', mesh(rbox(.08 * k, .07 * k, .015 * k, .008), m.topDark, { pos: [.08 * k, .2 * k, .128 * k], outline: false, parent: J.spine }));
    for (const [x, c] of [[.07, 0x2c7be5], [.088, 0xe8343c]]) reg('acc', mesh(new THREE.CylinderGeometry(.005 * k, .005 * k, .07 * k, 6), toon(c), { pos: [x * k, .24 * k, .133 * k], outline: false, parent: J.spine }));
  }

  if (kind === 'timur') {
    // эмблема паука на груди и спине костюма, браслеты-паутиномёты
    const emb = new THREE.Group(); J.spine.add(emb); emb.visible = false; ch.suitOnly = [emb];
    const eg = glow(0x7ff8ff, 1.6);
    for (const [z, flip] of [[.131 * k, 1], [-.131 * k, -1]]) {
      const e = new THREE.Group(); e.position.set(0, .27 * k, z); e.rotation.y = flip < 0 ? Math.PI : 0; emb.add(e);
      mesh(sph(.022 * k, 10, 8), eg, { scale: [.8, 1.1, .3], parent: e });
      mesh(sph(.03 * k, 10, 8), eg, { pos: [0, -.04 * k, 0], scale: [.8, 1.25, .3], parent: e });
      for (let i = 0; i < 8; i++) {
        const sd = i < 4 ? 1 : -1, j = i % 4;
        const lg = mesh(new THREE.BoxGeometry(.075 * k, .006 * k, .004 * k), eg, { pos: [sd * .04 * k, (.01 - j * .016) * k, 0], rot: [0, 0, sd * (.7 - j * .45)], parent: e });
      }
    }
    for (const s of ['L', 'R']) { const b = mesh(new THREE.TorusGeometry(.052 * k, .012 * k, 6, 18), glow(0x7ff8ff, 1.8), { pos: [0, -d.lower + .045 * k, 0], rot: [Math.PI / 2, 0, 0], outline: OL * .4, parent: J['fore' + s] }); b.visible = false; ch.suitOnly.push(b); }
    // волосы: шапка + торчащие пряди
    const hairG = new THREE.Group(); J.head.add(hairG); reg('hair', hairG);
    mesh(new THREE.SphereGeometry(R * 1.04, 24, 14, 0, Math.PI * 2, 0, Math.PI * .52), m.hair, { pos: [0, .145 * k, -.012], scale: [1, .92, 1.02], outline: OL, parent: hairG });
    const spikes = [[0, .3, .08, -.5], [.07, .29, .05, -.3], [-.07, .29, .06, -.7], [.1, .26, -.03, .1], [-.1, .26, -.02, .2], [0, .29, -.07, .5], [.04, .27, .12, -1]];
    ch.spikes = spikes.map(([x, y, z, r]) => { const sp = mesh(new THREE.ConeGeometry(.05, .13, 8), m.hair, { pos: [x * k, y * k, z * k], rot: [r - .2, 0, -x * 5], outline: OL * .8, parent: hairG }); sp.userData.rx = r - .2; return sp; });
    // капюшон, рюкзак, лямки, карабин
    ch.hood = reg('acc', mesh(new THREE.TorusGeometry(.12 * k, .055 * k, 10, 20), m.topDark, { pos: [0, .43 * k, -.1 * k], rot: [1.2, 0, 0], scale: [1.1, 1, 1], outline: OL, parent: J.spine }));
    const pack = ch.pack = reg('acc', mesh(rbox(.36 * k, .42 * k, .22 * k, .05 * k), toon(0x15b9a8), { pos: [0, .22 * k, -.24 * k], outline: OL, parent: J.spine }));
    mesh(rbox(.3 * k, .1 * k, .02 * k, .01), toon(0xfff1c2), { pos: [0, .07 * k, -.111 * k], outline: false, parent: pack }); // полоса-светоотражатель
    for (const sx of [1, -1]) reg('acc', mesh(rbox(.05 * k, .4 * k, .03 * k, .012), toon(0x0f7f74), { pos: [sx * .1 * k, .26 * k, .13 * k], rot: [-.12, 0, 0], outline: OL * .5, parent: J.spine }));
    const carab = reg('acc', mesh(new THREE.TorusGeometry(.035 * k, .009 * k, 8, 20), toon(0xc8ccd4, { emissive: 0x222630 }), { pos: [.1 * k, .14 * k, .16 * k], scale: [.7, 1.2, 1], outline: OL * .4, parent: J.spine }));
    ch.carabiner = carab;
    // наушники на шее — курьер всегда «на связи»
    const hph = new THREE.Group(); hph.position.set(0, .015 * k, .02 * k); J.neck.add(hph); reg('acc', hph);
    mesh(new THREE.TorusGeometry(.085 * k, .012 * k, 6, 20, Math.PI), toon(0x1c1f26), { rot: [-Math.PI / 2 + .35, 0, Math.PI], outline: OL * .4, parent: hph });
    for (const sx of [1, -1]) {
      mesh(new THREE.CylinderGeometry(.035 * k, .035 * k, .025 * k, 16), toon(0x1c1f26), { pos: [sx * .085 * k, -.02 * k, .02 * k], rot: [0, 0, Math.PI / 2], outline: OL * .4, parent: hph });
      mesh(new THREE.CylinderGeometry(.022 * k, .022 * k, .027 * k, 12), toon(0xff7b1c), { pos: [sx * .086 * k, -.02 * k, .02 * k], rot: [0, 0, Math.PI / 2], outline: false, parent: hph });
    }
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
    ch.bun = mesh(sph(.085 * k), m.hair, { pos: [0, .25 * k, -.13 * k], outline: OL, parent: hairG });
    for (const sx of [1, -1]) mesh(cap(.035 * k, .2 * k), m.hair, { pos: [sx * .15 * k, .08 * k, .04 * k], rot: [0, 0, sx * .12], outline: OL * .6, parent: hairG });
    // очки
    const gl = toon(0x222222);
    for (const sx of [1, -1]) mesh(new THREE.TorusGeometry(.043 * k, .007 * k, 6, 18), gl, { pos: [sx * .058 * k, .155 * k, .155 * k], outline: false, parent: J.head });
    mesh(rbox(.03 * k, .007 * k, .007 * k, .002), gl, { pos: [0, .16 * k, .165 * k], outline: false, parent: J.head });
    reg('acc', mesh(rbox(.07 * k, .09 * k, .01 * k, .005), toon(0x2c7be5), { pos: [-.09 * k, .3 * k, .14 * k], outline: false, parent: J.spine })); // бейдж
    // планшет в руке (видимость задаёт режиссура)
    const tab = new THREE.Group(); J.handR.add(tab); tab.position.set(0, -.11 * k, .05 * k); tab.rotation.set(-1.2, 0, 0); tab.visible = false; ch.tablet = tab;
    mesh(rbox(.17 * k, .23 * k, .014 * k, .012 * k), toon(0x22262e), { outline: OL * .4, parent: tab });
    const tc = document.createElement('canvas'); tc.width = 128; tc.height = 170; const tg = tc.getContext('2d');
    tg.fillStyle = '#062030'; tg.fillRect(0, 0, 128, 170); tg.strokeStyle = '#3ff0ff'; tg.lineWidth = 3;
    tg.beginPath(); for (let x = 0; x < 128; x += 4) tg.lineTo(x, 60 + Math.sin(x * .12) * 20); tg.stroke();
    tg.fillStyle = '#3ff0ff'; for (let i = 0; i < 5; i++) tg.fillRect(12, 100 + i * 12, 30 + (i * 37) % 80, 5);
    const tt = new THREE.CanvasTexture(tc); tt.colorSpace = THREE.SRGBColorSpace;
    mesh(new THREE.PlaneGeometry(.15 * k, .2 * k), new THREE.MeshBasicMaterial({ map: tt, color: new THREE.Color(1.4, 1.4, 1.4) }), { pos: [0, 0, .008 * k], parent: tab });
  }
  if (['marjon', 'diyor', 'azim', 'teacher', 'odilman', 'student'].includes(kind)) buildCast(ch, kind, d, m, fr, reg, R, OL, SV, opt);
  if (kind === 'shadow') {
    fr.face.visible = false;
    const eyes = new THREE.Group(); J.head.add(eyes); ch.redEyes = eyes;
    const em = glow(0xff1020, 4);
    [[-.05, .2, .8], [.05, .2, .8], [-.1, .17, .7], [.1, .17, .7], [-.035, .14, .65], [.035, .14, .65], [-.12, .23, .55], [.12, .23, .55]]
      .forEach(([x, y, s]) => mesh(sph(.022 * s + .006, 10, 8), em, { pos: [x, y, .15 - Math.abs(x) * .3], outline: false, parent: eyes }));
  }
  return finish(ch);
}

/* ---------- ODILMAN: красный костюм с чёрной паутиной ---------- */
let ODIL_MAT;
function odilSuit() {
  if (ODIL_MAT) return ODIL_MAT;
  const c = document.createElement('canvas'); c.width = c.height = 512; const g = c.getContext('2d');
  const gr = g.createLinearGradient(0, 0, 512, 512); gr.addColorStop(0, '#d42430'); gr.addColorStop(1, '#a8141e');
  g.fillStyle = gr; g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 3000; i++) { g.fillStyle = `rgba(0,0,0,${Math.random() * .05})`; g.fillRect(Math.random() * 512, Math.random() * 512, 2, 2); }
  g.strokeStyle = '#0d0a10'; g.lineWidth = 10; g.lineCap = 'round';
  for (let i = 0; i <= 4; i++) { g.beginPath(); g.moveTo(i * 128 + 20, 0); g.bezierCurveTo(i * 128 - 10, 170, i * 128 + 50, 340, i * 128 + 20, 512); g.stroke(); }
  g.lineWidth = 7;
  for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) { g.beginPath(); g.moveTo(i * 128 + 20, j * 128 + 40); g.quadraticCurveTo(i * 128 + 84, j * 128 + 82, i * 128 + 148, j * 128 + 40); g.stroke(); }
  const tx = new THREE.CanvasTexture(c); tx.wrapS = tx.wrapT = THREE.RepeatWrapping; tx.colorSpace = THREE.SRGBColorSpace; tx.repeat.set(1.3, 1.3);
  ODIL_MAT = toon(0xffffff, { map: tx });
  rimify(ODIL_MAT, 0xff8a7a, .4, 2.2); ODIL_MAT.userData.rim = true;
  return ODIL_MAT;
}

/* ---------- школьный состав серии 2: Маржон, Диёр, Азим, учительница, школьники, ODILMAN ---------- */
function buildCast(ch, kind, d, m, fr, reg, R, OL, SV, opt) {
  const k = d.k, J = ch.J;
  const hairG = new THREE.Group(); J.head.add(hairG); reg('hair', hairG);
  const capHair = (mat, theta = .55, y = .145, sc = [1, .93, 1.03], rr = 1.05) =>
    mesh(new THREE.SphereGeometry(R * rr, 24, 14, 0, Math.PI * 2, 0, Math.PI * theta), mat, { pos: [0, y * k, -.012], scale: sc, outline: OL, parent: hairG });
  const front = (y, w = 1.12) => .155 * k * .82 * w;            // передняя поверхность торса на уровне груди (z)
  /** хвост из звеньев: ch.tail — для вторичной анимации */
  const ponytail = (mat, n = 4, len = .12, r0 = .052, base = [0, .27, -.15]) => {
    let parent = new THREE.Group(); parent.position.set(base[0] * k, base[1] * k, base[2] * k); hairG.add(parent);
    mesh(new THREE.TorusGeometry(.04 * k, .014 * k, 6, 14), toon(0x2f6b4f), { rot: [Math.PI / 2 + .6, 0, 0], outline: OL * .5, parent });
    const segs = [];
    for (let i = 0; i < n; i++) {
      const g = new THREE.Group(); if (i) g.position.y = -len * k; parent.add(g);
      g.userData.rx = i ? -.55 : 2.35; g.rotation.x = g.userData.rx;
      const r = lerp(r0, r0 * .45, i / (n - 1));
      mesh(cap(r * k, (len + r) * k), mat, { pos: [0, -len * k / 2, 0], scale: [1.1, 1, .8], outline: OL * .8, parent: g });
      segs.push(g); parent = g;
    }
    return segs;
  };
  const glasses = (col = 0x222222, w = .007) => {
    const gl = toon(col);
    for (const sx of [1, -1]) mesh(new THREE.TorusGeometry(.043 * k, w * k, 6, 18), gl, { pos: [sx * .058 * k, .155 * k, .155 * k], outline: false, parent: J.head });
    mesh(rbox(.03 * k, .007 * k, .007 * k, .002), gl, { pos: [0, .16 * k, .165 * k], outline: false, parent: J.head });
  };
  const onFace = (x, y, push = .002) => [x, .13 + y, Math.sqrt(Math.max(.165 * .165 - x * x - y * y, 0)) + push];

  if (kind === 'marjon') {
    capHair(m.hair, .5, .15, [1, .95, 1.06], 1.06);
    mesh(sph(.08 * k), m.hair, { pos: [.045 * k, .285 * k, .1 * k], rot: [.35, 0, -.4], scale: [1.3, .3, .62], outline: OL * .8, parent: hairG });   // косая чёлка
    for (const sx of [1, -1]) mesh(cap(.03 * k, (sx > 0 ? .2 : .26) * k), m.hair, { pos: [sx * .152 * k, (sx > 0 ? .1 : .07) * k, .045 * k], rot: [.1, 0, sx * .12], outline: OL * .6, parent: hairG });
    ch.tail = ponytail(m.hair, 4, .13, .056);
    for (const sx of [1, -1]) mesh(sph(.011 * k, 8, 6), glow(0xffd36b, 1.3), { pos: [sx * .168 * k, .07 * k, .0], outline: false, parent: J.head });   // серёжки
    const frk = toon(0xb86a44);
    [[.07, -.03], [.085, -.045], [.062, -.05], [.095, -.028], [.078, -.06]].forEach(([x, y]) => { for (const sx of [1, -1]) mesh(sph(.0045, 6, 4), frk, { pos: onFace(sx * x, y), outline: false, parent: fr.face }); });
    // бомбер: воротник-резинка, белая футболка, молния, низ куртки, нашивка
    const rib = toon(0x234f3a);
    reg('acc', mesh(new THREE.TorusGeometry(.085 * k, .02 * k, 8, 20), rib, { pos: [0, .46 * k, -.005 * k], rot: [Math.PI / 2 + .2, 0, 0], scale: [1.1, 1, 1], outline: OL * .4, parent: J.spine }));
    reg('acc', mesh(new THREE.CircleGeometry(.04 * k, 3), toon(0xf6f4ee), { pos: [0, .43 * k, front(.4) + .003 * k], rot: [0, 0, -Math.PI / 2], scale: [1, .8, 1], outline: false, parent: J.spine }));
    reg('acc', mesh(new THREE.BoxGeometry(.008 * k, .36 * k, .008 * k), toon(0xc9c9c9), { pos: [.012 * k, .2 * k, front(.2) + .006 * k], outline: false, parent: J.spine }));
    reg('acc', mesh(new THREE.TorusGeometry(.155 * k, .026 * k, 6, 24), rib, { pos: [0, .015 * k, 0], rot: [Math.PI / 2, 0, 0], scale: [1.1, .82, 1], outline: OL * .5, parent: J.spine }));
    reg('acc', mesh(rbox(.06 * k, .045 * k, .01 * k, .01), toon(0xff7b1c), { pos: [.055 * k, -.09 * k, .0], rot: [0, Math.PI / 2, 0], outline: false, parent: J.armL }));
    // скетчбук (видимость задаёт режиссура)
    const sk = new THREE.Group(); J.handL.add(sk); sk.position.set(0, -.1 * k, .05 * k); sk.rotation.set(-1.1, 0, 0); sk.visible = false; ch.sketch = sk;
    mesh(rbox(.17 * k, .23 * k, .02 * k, .008), toon(0xe85a7a), { outline: OL * .4, parent: sk });
    // раскрытый разворот с комиксом про героя (на обеих сторонах — видно с любого ракурса)
    const pc = document.createElement('canvas'); pc.width = 256; pc.height = 340; const g = pc.getContext('2d');
    g.fillStyle = '#fbf8ef'; g.fillRect(0, 0, 256, 340); g.strokeStyle = '#1a1a1a'; g.lineWidth = 4;
    g.strokeRect(10, 10, 236, 150); g.strokeRect(10, 172, 112, 156); g.strokeRect(134, 172, 112, 156);
    g.strokeStyle = '#2a7ad8'; g.lineWidth = 3; g.beginPath(); g.moveTo(40, 20); g.lineTo(70, 70); g.lineTo(55, 72); g.lineTo(85, 130); g.stroke();   // молния
    g.fillStyle = '#d8402c'; g.beginPath(); g.arc(160, 62, 16, 0, 7); g.fill(); g.fillRect(146, 78, 28, 44);                                    // герой
    g.strokeStyle = '#d8402c'; g.lineWidth = 6; g.beginPath(); g.moveTo(150, 84); g.lineTo(120, 40); g.moveTo(170, 84); g.lineTo(205, 52); g.stroke();
    g.fillStyle = '#fff'; g.beginPath(); g.ellipse(154, 60, 5, 3, -.4, 0, 7); g.ellipse(166, 60, 5, 3, .4, 0, 7); g.fill();
    g.fillStyle = '#e8e2d2'; g.fillRect(30, 230, 70, 34); g.fillStyle = '#d8402c'; g.fillRect(30, 256, 70, 8);                                  // автобус
    g.strokeStyle = '#555'; g.lineWidth = 1.5; g.beginPath(); g.moveTo(65, 182); g.lineTo(65, 230); g.stroke();
    g.fillStyle = '#1a1a1a'; g.font = '800 17px Rubik'; g.fillText('ЧЕЛОВЕК-', 144, 220); g.fillText('МОЛНИЯ?', 144, 242);
    g.font = '600 14px Rubik'; g.fillText('или…', 150, 280); g.fillText('ПАУК?', 150, 300);
    const pt = new THREE.CanvasTexture(pc); pt.colorSpace = THREE.SRGBColorSpace;
    for (const sz of [1, -1]) { const pg = new THREE.Mesh(new THREE.PlaneGeometry(.155 * k, .21 * k), new THREE.MeshBasicMaterial({ map: pt, color: 0x8c8c8c })); pg.position.z = sz * .0105 * k; if (sz < 0) pg.rotation.y = Math.PI; sk.add(pg); }
  }
  if (kind === 'diyor') {
    capHair(m.hair, .46, .15, [1, .9, 1.03], 1.05);
    mesh(sph(.09 * k), m.hair, { pos: [.03 * k, .29 * k, .06 * k], rot: [.45, 0, -.25], scale: [1.25, .48, .9], outline: OL * .8, parent: hairG });   // уложенная чёлка
    for (const sx of [1, -1]) mesh(rbox(.02 * k, .06 * k, .03 * k, .008), m.hair, { pos: [sx * .158 * k, .1 * k, .03 * k], outline: false, parent: hairG });
    const lapel = toon(0x16203a), white = toon(0xf7f7f4);
    reg('acc', mesh(rbox(.08 * k, .21 * k, .01 * k, .006), white, { pos: [0, .34 * k, front(.34) - .006 * k], outline: false, parent: J.spine }));      // рубашка
    for (const sx of [1, -1]) reg('acc', mesh(rbox(.05 * k, .22 * k, .014 * k, .006), lapel, { pos: [sx * .052 * k, .33 * k, front(.33) + .002 * k], rot: [0, 0, sx * .33], outline: OL * .4, parent: J.spine }));
    reg('acc', mesh(rbox(.034 * k, .19 * k, .012 * k, .005), toon(0xb3262e), { pos: [.006 * k, .3 * k, front(.3) + .006 * k], rot: [0, 0, .07], outline: OL * .3, parent: J.spine }));  // галстук
    reg('acc', mesh(rbox(.04 * k, .035 * k, .016 * k, .008), toon(0x9a1e26), { pos: [0, .405 * k, front(.4) + .008 * k], outline: OL * .3, parent: J.spine }));
    reg('acc', mesh(new THREE.TorusGeometry(.06 * k, .016 * k, 6, 16), white, { pos: [0, .46 * k, .01 * k], rot: [Math.PI / 2 + .25, 0, 0], outline: OL * .4, parent: J.spine }));   // воротник
    for (let i = 0; i < 2; i++) reg('acc', mesh(sph(.011 * k, 8, 6), toon(0xd9a441, { emissive: 0x3a2a00 }), { pos: [-.025 * k, (.16 - i * .07) * k, front(.15) + .004 * k], outline: false, parent: J.spine }));
    reg('acc', mesh(rbox(.045 * k, .02 * k, .01 * k, .004), white, { pos: [-.085 * k, .33 * k, front(.33) - .004 * k], outline: false, parent: J.spine }));   // платок в кармане
    reg('acc', mesh(new THREE.TorusGeometry(.05 * k, .012 * k, 6, 16), toon(0xd9a441, { emissive: 0x3a2a00 }), { pos: [0, -d.lower + .07 * k, 0], rot: [Math.PI / 2, 0, 0], outline: OL * .3, parent: J.foreL })); // часы
    for (const s of ['L', 'R']) reg('acc', mesh(new THREE.TorusGeometry(.048 * k, .012 * k, 6, 16), white, { pos: [0, -d.lower + .02 * k, 0], rot: [Math.PI / 2, 0, 0], outline: false, parent: J['fore' + s] }));
  }
  if (kind === 'azim') {
    capHair(toon(0x2a2018), .47, .14, [1.03, .96, 1.05], 1.07);                                 // ёжик
    reg('skin', mesh(rbox(.2 * k, .085 * k, .14 * k, .04 * k), m.skin, { pos: [0, .045 * k, .04 * k], outline: OL * .7, parent: J.head }));   // тяжёлая челюсть
    reg('skin', mesh(new THREE.CylinderGeometry(.075 * k, .08 * k, .12 * k, 12), m.skin, { pos: [0, .03 * k, 0], outline: OL * .7, parent: J.neck }));
    fr.brows.forEach(b => b.scale.set(1.12, 1.35, 1.1));
    const blue = toon(0x1d4fa0), white = toon(0xf2f2ee);
    const stripe = (y, r, sx = 1, parent = J.spine) => { mesh(new THREE.TorusGeometry(r * k, .022 * k, 6, 24), blue, { pos: [0, y * k, 0], rot: [Math.PI / 2, 0, 0], scale: [sx, .9, 1], outline: OL * .4, parent }); mesh(new THREE.TorusGeometry(r * k, .008 * k, 6, 24), white, { pos: [0, (y + .02) * k, 0], rot: [Math.PI / 2, 0, 0], scale: [sx * 1.02, .92, 1], outline: false, parent }); };
    stripe(.46, .12, 1.15); stripe(.02, .16, 1.42);
    for (const s of ['L', 'R']) { mesh(new THREE.TorusGeometry(.05 * k, .02 * k, 6, 16), blue, { pos: [0, -d.lower + .035 * k, 0], rot: [Math.PI / 2, 0, 0], outline: OL * .4, parent: J['fore' + s] }); }
    for (let i = 0; i < 4; i++) reg('acc', mesh(sph(.012 * k, 8, 6), white, { pos: [0, (.08 + i * .09) * k, front(.2, 1.12) + .006 * k], outline: false, parent: J.spine }));
    // нашивка «7» на груди
    const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
    g.fillStyle = '#f2f2ee'; g.beginPath(); g.arc(64, 64, 60, 0, 7); g.fill(); g.fillStyle = '#c8202c'; g.font = '900 96px Unbounded'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText('7', 66, 70);
    const tx = new THREE.CanvasTexture(c); tx.colorSpace = THREE.SRGBColorSpace;
    reg('acc', mesh(new THREE.CircleGeometry(.055 * k, 20), new THREE.MeshBasicMaterial({ map: tx, color: new THREE.Color(.9, .9, .9) }), { pos: [.075 * k, .31 * k, front(.31, 1.12) + .008 * k], rot: [0, .25, 0], outline: false, parent: J.spine }));
    ch.gum = mesh(sph(.03 * k, 12, 8), toon(0xff8ab8), { pos: [0, .07 * k, .19 * k], outline: OL * .4, parent: J.head }); ch.gum.visible = false;
  }
  if (kind === 'teacher') {
    capHair(m.hair, .55, .15, [1, .95, 1.04], 1.05);
    ch.bun = mesh(sph(.08 * k), m.hair, { pos: [0, .26 * k, -.12 * k], outline: OL, parent: hairG });
    glasses(0x5a3a2a, .006);
    for (let i = 0; i < 9; i++) { const a = -1 + i * .25; reg('acc', mesh(sph(.012 * k, 8, 6), toon(0xe8e2d4), { pos: [Math.sin(a) * .1 * k, .42 * k - Math.cos(a) * .03 * k, .1 * k + Math.cos(a) * .02 * k], outline: false, parent: J.spine })); }   // бусы
    for (let i = 0; i < 4; i++) reg('acc', mesh(sph(.01 * k, 8, 6), toon(0x3a1a20), { pos: [.0, (.08 + i * .08) * k, front(.2, 1.1) + .004 * k], outline: false, parent: J.spine }));
    const chalk = mesh(new THREE.CylinderGeometry(.008, .008, .07, 8), toon(0xffffff), { pos: [0, -.1 * k, .03 * k], rot: [Math.PI / 2, 0, 0], outline: .002, parent: J.handR }); chalk.visible = false; ch.chalk = chalk;
  }
  if (kind === 'student') {
    const st = SV.style;
    if (st === 0) { capHair(m.hair, .5); mesh(sph(.07 * k), m.hair, { pos: [0, .27 * k, .08 * k], scale: [1.4, .45, .8], outline: OL * .7, parent: hairG }); }
    if (st === 1) { capHair(m.hair, .56, .15, [1, .95, 1.06], 1.06); ch.tail = ponytail(m.hair, 3, .12, .05); }
    if (st === 2) { capHair(m.hair, .66, .14, [1.05, .98, 1.08], 1.08); mesh(cap(.04 * k, .2 * k), m.hair, { pos: [0, .25 * k, .12 * k], rot: [0, 0, Math.PI / 2], scale: [1, 1.1, .7], outline: OL * .6, parent: hairG }); }
    if (st === 3) {
      capHair(m.hair, .45);
      mesh(new THREE.SphereGeometry(R * 1.08, 20, 12, 0, Math.PI * 2, 0, Math.PI * .48), toon(SV.cap), { pos: [0, .16 * k, -.01], outline: OL, parent: hairG });
      mesh(rbox(.2 * k, .015 * k, .13 * k, .006), toon(SV.cap), { pos: [0, .2 * k, .17 * k], rot: [-.15, 0, 0], outline: OL * .6, parent: hairG });
    }
    if (st === 4) { capHair(m.hair, .5); for (let i = 0; i < 5; i++) mesh(new THREE.ConeGeometry(.04 * k, .09 * k, 6), m.hair, { pos: [(i - 2) * .04 * k, .3 * k, (.03 - Math.abs(i - 2) * .02) * k], rot: [-.2, 0, -(i - 2) * .25], outline: OL * .6, parent: hairG }); }
    if (SV.vest) {                                     // школьная форма: жилет и галстук
      reg('acc', mesh(cap(.158 * k, .4 * k), toon(SV.vest), { pos: [0, .2 * k, 0], scale: [1.22 * 1.02, .92, .84], outline: OL, parent: J.spine }));
      reg('acc', mesh(rbox(.03 * k, .16 * k, .012 * k, .005), toon(0x1a2440), { pos: [0, .34 * k, front(.34) + .012 * k], outline: false, parent: J.spine }));
    }
    if ((opt.variant ?? 0) % 2 === 0) reg('acc', mesh(rbox(.3 * k, .36 * k, .16 * k, .05 * k), toon([0x2c7be5, 0xe8343c, 0x3a3a44, 0xf2c94c, 0x15b9a8][(opt.variant ?? 0) % 5]), { pos: [0, .22 * k, -.2 * k], outline: OL, parent: J.spine }));
  }
  if (kind === 'odilman') {
    [...fr.eyes, ...fr.lids, ...fr.lowLids, ...fr.brows, ...fr.cheeks, fr.nose].forEach(o => o.visible = false);
    const navy = toon(0x1b2440), black = toon(0x0d0a10);
    rimify(navy, 0x7a8cff, .35, 2.4); navy.userData.rim = true;
    // капюшон-маска: закрывает голову до носа, сзади — до шеи
    mesh(new THREE.SphereGeometry(R * 1.07, 28, 18, 0, Math.PI * 2, 0, Math.PI * .585), navy, { pos: [0, .13 * k, 0], outline: OL, parent: J.head });
    mesh(new THREE.SphereGeometry(R * 1.065, 24, 16, Math.PI, Math.PI, 0, Math.PI * .92), navy, { pos: [0, .13 * k, -.005], outline: OL, parent: J.head });
    reg('acc', mesh(new THREE.CylinderGeometry(.07 * k, .1 * k, .14 * k, 14), navy, { pos: [0, .03 * k, 0], outline: OL * .7, parent: J.neck }));
    reg('acc', mesh(new THREE.TorusGeometry(.105 * k, .028 * k, 8, 20), navy, { pos: [0, .47 * k, 0], rot: [Math.PI / 2, 0, 0], scale: [1.2, 1, 1], outline: OL * .7, parent: J.spine }));
    // белые глаза маски
    const lensM = new THREE.MeshBasicMaterial({ color: 0xf2f4f8 });
    ch.lensList = [1, -1].map(sx => mesh(sph(.052, 18, 10), lensM, { pos: [sx * .064 * k, .17 * k, .153 * k], rot: [0, sx * .42, sx * .42], scale: [1.5, .5, .3], outline: .016, parent: J.head }));
    // бородка и усы
    reg('face', mesh(cap(.017 * k, .055 * k), black, { pos: [0, .03 * k, .142 * k], rot: [.35, 0, 0], outline: OL * .3, parent: J.head }));
    reg('face', mesh(cap(.011 * k, .1 * k), black, { pos: [0, .085 * k, .158 * k], rot: [0, 0, Math.PI / 2], outline: false, parent: J.head }));
    // чёрный паук на груди: тело + 8 лап, обнимающих торс
    const fz = front(.3, 1.38);
    const sp = new THREE.Group(); sp.position.set(0, .28 * k, fz * .98); J.spine.add(sp);
    mesh(sph(.04 * k, 12, 8), black, { scale: [.8, 1.15, .35], outline: false, parent: sp });
    mesh(sph(.05 * k, 12, 8), black, { pos: [0, -.075 * k, -.004 * k], scale: [.85, 1.3, .35], outline: false, parent: sp });
    for (let i = 0; i < 8; i++) {
      const sd = i < 4 ? 1 : -1, j = i % 4, a = sd * (.95 - j * .42);
      const l1 = mesh(new THREE.BoxGeometry(.14 * k, .02 * k, .01 * k), black, { pos: [sd * .07 * k * Math.cos(a - sd * .9), (.02 - j * .03) * k + .05 * k * Math.sin(a), 0], rot: [0, 0, a], outline: false, parent: sp });
      mesh(new THREE.BoxGeometry(.12 * k, .018 * k, .01 * k), black, { pos: [sd * .17 * k, (.05 - j * .07) * k, -.03 * k], rot: [0, -sd * .6, a * .4 - sd * .5], outline: false, parent: sp });
    }
    // ленты маски за головой (ch.ribbons — ветер во вторичной анимации)
    ch.ribbons = [1, -1].map(sx => {
      let parent = new THREE.Group(); parent.position.set(sx * .03 * k, .2 * k, -.16 * k); J.head.add(parent);
      const segs = [];
      for (let i = 0; i < 5; i++) {
        const g = new THREE.Group(); if (i) g.position.y = -.15 * k; parent.add(g);
        mesh(new THREE.BoxGeometry(.045 * k * (1 - i * .08), .16 * k, .008 * k), navy, { pos: [0, -.075 * k, 0], outline: OL * .5, parent: g });
        segs.push(g); parent = g;
      }
      return segs;
    });
    ch.wind = .6;
    // пояс и перчатки до локтя уже из палитры; швы на перчатках
    for (const s of ['L', 'R']) mesh(new THREE.TorusGeometry(.055 * k, .014 * k, 6, 16), black, { pos: [0, -.02 * k, 0], rot: [Math.PI / 2, 0, 0], outline: false, parent: J['fore' + s] });
  }
}

/* ---------- Кронов в экзокостюме ---------- */
function buildKronov(ch, d) {
  const k = d.k, J = ch.J, OL = .016 * k;
  // массивный торс брони: плечи и бёдра шире, чем у обычного скелета, — руки не «растут» из корпуса
  J.armL.position.set(.33 * k, .12 * k, 0); J.armR.position.set(-.33 * k, .12 * k, 0);
  J.legL.position.x = .13 * k; J.legR.position.x = -.13 * k;
  d.shX = .33 * k;
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
  // детали брони: воротник, светящиеся швы, вентиляция, поршни на коленях и локтях
  mesh(new THREE.TorusGeometry(.14 * k, .045 * k, 8, 20), dark, { pos: [0, .52 * k, 0], rot: [Math.PI / 2, 0, 0], outline: OL, parent: J.spine });
  const seam = glow(0xff7a2a, 2.2);
  for (const sx of [1, -1]) {
    mesh(new THREE.BoxGeometry(.012 * k, .3 * k, .012 * k), seam, { pos: [sx * .2 * k, .26 * k, .2 * k], outline: false, parent: J.spine });
    for (let i = 0; i < 3; i++) mesh(new THREE.BoxGeometry(.09 * k, .014 * k, .02 * k), dark, { pos: [sx * .2 * k, (.36 + i * .035) * k, -.205 * k], outline: false, parent: J.spine });
    mesh(new THREE.CylinderGeometry(.03 * k, .03 * k, .05 * k, 10), glow(0xffa340, 2.5), { pos: [sx * .1 * k, .27 * k, -.43 * k], rot: [Math.PI / 2 + .3, 0, 0], outline: false, parent: J.spine });
  }
  for (const s of ['L', 'R']) {
    mesh(new THREE.BoxGeometry(.012 * k, d.lower * .7, .012 * k), seam, { pos: [0, -d.lower * .45, .105 * k], outline: false, parent: J['fore' + s] });
    mesh(new THREE.BoxGeometry(.012 * k, d.shin * .6, .012 * k), seam, { pos: [0, -d.shin * .5, .1 * k], outline: false, parent: J['shin' + s] });
    mesh(new THREE.CylinderGeometry(.025 * k, .025 * k, d.thigh * .7, 8), toon(0xb8c0cc), { pos: [0, -d.thigh * .5, -.11 * k], outline: OL * .5, parent: J['leg' + s] });
    mesh(new THREE.CylinderGeometry(.022 * k, .022 * k, d.upper * .6, 8), toon(0xb8c0cc), { pos: [0, -d.upper * .5, -.09 * k], outline: OL * .5, parent: J['arm' + s] });
    for (let i = 0; i < 4; i++) {           // кулак: костяшки + согнутые пальцы
      mesh(cap(.024 * k, .07 * k), dark, { pos: [(i - 1.5) * .042 * k, -.15 * k, .075 * k], rot: [Math.PI / 2, 0, 0], outline: OL * .4, parent: J['hand' + s] });
      mesh(cap(.022 * k, .06 * k), metal, { pos: [(i - 1.5) * .042 * k, -.19 * k, .055 * k], outline: OL * .4, parent: J['hand' + s] });
    }
    mesh(cap(.026 * k, .08 * k), dark, { pos: [(s === 'L' ? -1 : 1) * .085 * k, -.12 * k, .06 * k], rot: [.4, 0, (s === 'L' ? 1 : -1) * .8], outline: OL * .4, parent: J['hand' + s] });
  }
  mesh(new THREE.BoxGeometry(.012 * k, .012 * k, .28 * k), seam, { pos: [0, .3 * k, 0], outline: false, parent: J.head });
  // светящееся ядро «Арахны», которое Кронов уносит (по умолчанию скрыто)
  const stolen = new THREE.Group(); J.handL.add(stolen); stolen.position.set(0, -.2 * k, .05); stolen.visible = false;
  mesh(new THREE.CylinderGeometry(.06, .06, .22, 16), glow(0x5ff6ff, 3), { outline: .012, parent: stolen });
  ch.stolen = stolen;
  // ядро «Арахны», вставленное Кроновым себе в грудь (перегревается, искрит) — видимость задаёт режиссура
  const ar = new THREE.Group(); ar.position.set(0, .32 * k, .22 * k); J.spine.add(ar); ar.visible = false; ch.arachna = ar;
  ch.arachnaM = glow(0x5ff6ff, 3.2);
  mesh(new THREE.CylinderGeometry(.06 * k, .06 * k, .2 * k, 16), ch.arachnaM, { rot: [0, 0, Math.PI / 2], outline: .012, parent: ar });
  for (const sx of [-1, 1]) mesh(new THREE.TorusGeometry(.07 * k, .015 * k, 6, 16), dark, { pos: [sx * .08 * k, 0, 0], rot: [0, Math.PI / 2, 0], outline: .008, parent: ar });
  return finish(ch);
}

function finish(ch) {
  // лёгкий контровой свет на всех тун-материалах персонажа (костюм — свой, ярче)
  ch.root.traverse(o => { if (o.isMesh && o.material?.isMeshToonMaterial && !o.material.userData.rim) rimify(o.material, ch.kind === 'kronov' ? 0xffb080 : 0x9fc4ff, ch.kind === 'kronov' ? .18 : .14); });
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
  for (const m of ch.suitOnly || []) m.visible = on;
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
  if (ch.handL) { setGrip(ch.handL, p.gripL ?? p.grip ?? .35, p.spiderL || 0); setGrip(ch.handR, p.gripR ?? p.grip ?? .35, p.spiderR || 0); }
}
export function blend(a, b, k, extrap = false) {
  if (k <= 0) return a; if (k >= 1 && !(extrap && k > 1.0001)) return b;
  const o = {};
  for (const n of [...JOINTS, 'hx', 'hy', 'hz', 'grip', 'gripL', 'gripR', 'spiderL', 'spiderR']) {
    const va = a[n], vb = b[n];
    if (va === undefined && vb === undefined) continue;
    if (typeof (va ?? vb) === 'number') { const d0 = n.startsWith('grip') ? .35 : 0; o[n] = lerp(va ?? d0, vb ?? d0, k); }
    else { const A = va || ZERO, B = vb || ZERO; o[n] = [lerp(A[0], B[0], k), lerp(A[1], B[1], k), lerp(A[2], B[2], k)]; }
  }
  return o;
}
/* Последовательность поз: [[t, poseOrFn], ...] с плавным переходом xf секунд перед каждой */
/* Переход с лёгким перелётом (overshoot): поза «доходит» с запасом и возвращается — живее, чем ровный лерп */
const SNAP = x => { const c = .9; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };
export function seq(t, list, xf = .25) {
  let i = 0;
  while (i + 1 < list.length && t >= list[i + 1][0]) i++;
  const cur = typeof list[i][1] === 'function' ? list[i][1](t - list[i][0]) : list[i][1];
  if (i > 0) {
    const d = list[i][2] ?? xf;
    const k = clamp((t - list[i][0]) / d);
    if (k < 1) {
      const prev = typeof list[i - 1][1] === 'function' ? list[i - 1][1](t - list[i - 1][0]) : list[i - 1][1];
      const ease = list[i][3] || (d > .6 ? E.inOutSine : SNAP);
      return blend(prev, cur, ease(k), true);
    }
  }
  return cur;
}
/* Время для цикла шага по пройденному пути: ноги не скользят (stride — длина шага, f — частота позы) */
export const gait = (dist, stride = .7, f = .9) => dist / (2 * stride * f);

/* Сжатие/растяжение с сохранением объёма: a > 0 — вытянуться, a < 0 — сплющиться */
export function squash(ch, a) {
  const y = 1 + a, xz = 1 / Math.sqrt(Math.max(y, .2));
  ch.root.scale.set(xz, y, xz);
}
/* Импульс сжатия: удар в момент t0, затухающие колебания (как пружина) */
export const springAt = (t, t0, amp = -.18, freq = 14, damp = 7) => t < t0 ? 0 : amp * Math.cos((t - t0) * freq) * Math.exp(-(t - t0) * damp);

/* Вторичная анимация: рюкзак, капюшон, пряди волос, пучок — раскачиваются с запаздыванием */
export function secondary(ch, t, energy = .2) {
  const s1 = Math.sin(t * 7.3), s2 = Math.sin(t * 5.1 + 1), e = energy;
  if (ch.pack) ch.pack.rotation.set(-.05 + .12 * e * s1, .06 * e * s2, .08 * e * s2);
  if (ch.hood) ch.hood.rotation.set(1.2 + .25 * e * s2, 0, .1 * e * s1);
  if (ch.bun) ch.bun.position.y = .25 * ch.d.k + .008 * e * s1;
  if (ch.spikes) ch.spikes.forEach((m, i) => { m.rotation.x = m.userData.rx + .18 * e * Math.sin(t * 9 + i); });
  if (ch.tail) ch.tail.forEach((g, i) => { g.rotation.x = g.userData.rx + (.06 + .25 * e) * Math.sin(t * 4.2 - i * .9); g.rotation.z = (.04 + .12 * e) * Math.sin(t * 3.1 - i * .8); });
  if (ch.ribbons) ch.ribbons.forEach((r, j) => r.forEach((g, i) => {     // ленты маски — на ветру
    const w = ch.wind ?? .6;
    g.rotation.x = (i ? .25 : -.9) + w * (.35 * Math.sin(t * 6.3 - i * 1.1 + j) + .2);
    g.rotation.z = (j ? 1 : -1) * (.12 + .25 * w * Math.sin(t * 4.7 - i * .9 + j * 2));
  }));
}

/* IK руки: кисть тянется к точке в мире (двухзвенная аналитическая IK, локоть — в сторону pole) */
const _v = () => new THREE.Vector3();
export function ikArm(ch, side, target, pole = new THREE.Vector3(0, -1, -.3), weight = 1) {
  const J = ch.J, sh = J['arm' + side], el = J['fore' + side];
  ch.root.updateMatrixWorld(true);
  const parent = sh.parent;
  const inv = new THREE.Matrix4().copy(parent.matrixWorld).invert();
  const T = target.clone().applyMatrix4(inv);            // цель в пространстве груди
  const S0 = sh.position.clone();
  const a = ch.d.upper, b = ch.d.lower + .07 * ch.d.k;
  const dirv = T.clone().sub(S0); let dist = dirv.length();
  dist = Math.min(dist, (a + b) * .999); dirv.normalize();
  // угол в плече по теореме косинусов
  const cosA = clamp((a * a + dist * dist - b * b) / (2 * a * dist), -1, 1);
  const angA = Math.acos(cosA);
  const poleL = pole.clone().transformDirection(inv).normalize();
  const n = new THREE.Vector3().crossVectors(dirv, poleL).normalize();
  if (n.lengthSq() < 1e-6) n.set(1, 0, 0);
  const upperDir = dirv.clone().applyAxisAngle(n, angA);    // плечо отклоняется к pole — локоть смотрит наружу
  const elbow = S0.clone().addScaledVector(upperDir, a);
  const lowerDir = T.clone().sub(elbow).normalize();
  // плечо: «вниз» (−y) поворачиваем в upperDir
  const qS = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, -1, 0), upperDir);
  const qSoff = sh.quaternion.clone();
  sh.quaternion.copy(qSoff.slerp(qS, weight));
  // предплечье: в локале плеча
  const lowerLocal = lowerDir.clone().applyQuaternion(sh.quaternion.clone().invert());
  const qE = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, -1, 0), lowerLocal);
  el.quaternion.copy(el.quaternion.clone().slerp(qE, weight));
  ch.root.updateMatrixWorld(true);
}

const S = Math.sin, Cc = Math.cos, PI = Math.PI;
export const POSE = {
  stand: (t = 0) => ({ armL: [.03, 0, .1 + .01 * S(t * 2)], armR: [.03, 0, .1 + .01 * S(t * 2)], foreL: [-.2, 0, 0], foreR: [-.2, 0, 0],
    spine: [.01 * S(t * 2), 0, 0], legL: [0, 0, .03], legR: [0, 0, .03], hy: .004 * S(t * 2) }),
  talk: (t = 0) => ({ ...POSE.stand(t), gripL: .1, armL: [-.35 - .15 * S(t * 3.1), .2, .25], foreL: [-1.1 - .2 * S(t * 4), 0, 0], handL: [0, 0, .3],
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
    return { grip: .85, hy: -.2, hz: -.08, spine: [.62, 0, 0], chest: [.12, 0, 0], neck: [-.3, 0, 0], head: [-.45, 0, 0],
      armL: [-1.12, 0, .2], armR: [-1.12, 0, .2], foreL: [-.35, 0, -.1], foreR: [-.35, 0, -.1], handL: [.2, 0, 0], handR: [.2, 0, 0],
      legL: [-1.15 - .35 * s, 0, .05], legR: [-1.15 + .35 * s, 0, .05], shinL: [1.45 + .4 * c, 0, 0], shinR: [1.45 - .4 * c, 0, 0],
      footL: [-.2, 0, 0], footR: [-.2, 0, 0] };
  },
  bikeStand: () => ({ grip: .85, hy: -.25, hz: -.05, spine: [.9, 0, 0], chest: [.1, 0, 0], head: [-.7, 0, 0], armL: [-1.25, 0, .25], armR: [-1.25, 0, .25], foreL: [-.6, 0, 0], foreR: [-.6, 0, 0],
    legL: [-.9, 0, .15], legR: [-.5, 0, .15], shinL: [1.1, 0, 0], shinR: [.7, 0, 0] }),
  crouch: () => ({ hy: -.42, spine: [.55, 0, 0], head: [-.5, 0, 0], armL: [-.5, 0, .35], armR: [-.5, 0, .35], foreL: [-.6, 0, 0], foreR: [-.6, 0, 0],
    legL: [-1.6, 0, .35], legR: [-1.6, 0, .35], shinL: [2.2, 0, 0], shinR: [2.2, 0, 0], footL: [-.5, 0, 0], footR: [-.5, 0, 0] }),
  spiderCrouch: (t = 0) => ({ grip: .05, hy: -.48, spine: [.7, 0, 0], head: [-.85, .15 * S(t * 1.3), 0], armL: [-.9, -.4, .9], armR: [-.9, -.4, .9], foreL: [-1.1, 0, 0], foreR: [-1.1, 0, 0],
    handL: [.4, 0, 0], handR: [.4, 0, 0], legL: [-1.5, 0, .75], legR: [-1.5, 0, .75], shinL: [2.4, 0, 0], shinR: [2.4, 0, 0], footL: [-.7, 0, 0], footR: [-.7, 0, 0] }),
  heroLand: () => ({ gripR: .05, gripL: .5, hy: -.5, spine: [.75, -.1, 0], head: [-.7, .1, 0], armL: [.4, 0, .9], foreL: [-.3, 0, 0], armR: [-1.0, 0, .2], foreR: [-.2, 0, 0], handR: [-.6, 0, 0],
    legL: [-1.7, 0, .25], shinL: [2.3, 0, 0], footL: [-.6, 0, 0], legR: [-.2, 0, .1], shinR: [2.5, 0, 0], footR: [.6, 0, 0] }),
  lie: (t = 0) => ({ armL: [0, 0, .5], armR: [-.3, 0, .8], foreL: [-.4, 0, 0], foreR: [-.1, 0, 0], legL: [0, 0, .1], legR: [-.3, 0, .05], shinR: [.6, 0, 0],
    head: [0, .3, 0], spine: [.02 * S(t * 2), 0, 0] }),
  sitUp: () => ({ hy: -.6, spine: [.4, 0, 0], head: [-.2, 0, 0], armL: [.5, 0, .3], armR: [-.3, 0, .2], foreL: [-.3, 0, 0], foreR: [-1.4, 0, 0],
    legL: [-1.45, 0, .1], legR: [-1.2, 0, .2], shinL: [.2, 0, 0], shinR: [1.2, 0, 0] }),
  lookHand: (t = 0) => ({ hy: -.6, spine: [.3, 0, 0], head: [.25, -.25, 0], armL: [.3, 0, .3], foreL: [-.2, 0, 0], armR: [-1.2, -.5, .1], foreR: [-1.4, 0, 0], handR: [.3 * S(t * 2), 0, -.3],
    legL: [-1.45, 0, .1], legR: [-1.2, 0, .2], shinL: [.2, 0, 0], shinR: [1.2, 0, 0] }),
  fall: t => ({ grip: .05, spine: [-.3 + .2 * S(t * 7), .3 * S(t * 3), 0], head: [.3, 0, 0], armL: [-2.6 + .5 * S(t * 11), 0, .6 + .3 * S(t * 9)], armR: [-2.4 + .5 * S(t * 10 + 1), 0, .7 + .3 * S(t * 8)],
    foreL: [-.5, 0, 0], foreR: [-.4, 0, 0], legL: [-.6 + .6 * S(t * 9), 0, .3], legR: [-.3 - .6 * S(t * 9), 0, .3], shinL: [.9, 0, 0], shinR: [.8, 0, 0] }),
  shootUp: () => ({ spiderR: 1, gripL: .2, spine: [-.15, 0, 0], head: [.35, 0, 0], armR: [-2.9, 0, .15], foreR: [0, 0, 0], handR: [-.9, 0, 0], armL: [.3, 0, .8], foreL: [-.6, 0, 0],
    legL: [-.4, 0, .1], legR: [.2, 0, .1], shinL: [.9, 0, 0], shinR: [.5, 0, 0] }),
  shootFwd: (arm = 'R') => {
    const o = { spine: [.1, .15, 0], head: [0, -.1, 0], armL: [.2, 0, .3], foreL: [-1.2, 0, 0], armR: [.2, 0, .3], foreR: [-1.2, 0, 0], legL: [-.4, 0, .15], legR: [.3, 0, .1], shinL: [.5, 0, 0], shinR: [.3, 0, 0], hy: -.08 };
    o['arm' + arm] = [-1.55, 0, .05]; o['fore' + arm] = [0, 0, 0]; o['hand' + arm] = [-1.0, 0, 0]; o['spider' + arm] = 1;
    return o;
  },
  swing: t => ({ gripR: .9, gripL: .15, spine: [-.15, 0, .05 * S(t * 2)], head: [.1, 0, 0], armR: [-3.0, 0, .1], foreR: [-.05, 0, 0], handR: [-.6, 0, 0], armL: [-.4, 0, 1.0], foreL: [-.9, 0, 0],
    legL: [-.9, 0, .1], legR: [-.25, 0, .1], shinL: [1.4, 0, 0], shinR: [.5, 0, 0], footL: [.3, 0, 0], footR: [.4, 0, 0] }),
  flip: t => ({ spine: [.9, 0, 0], head: [-.4, 0, 0], armL: [-1.4, 0, .3], armR: [-1.4, 0, .3], foreL: [-1.6, 0, 0], foreR: [-1.6, 0, 0],
    legL: [-2.0, 0, .1], legR: [-2.0, 0, .1], shinL: [2.4, 0, 0], shinR: [2.4, 0, 0], hy: -.2 }),
  pull: (t = 0) => ({ grip: .95, hy: -.3, hz: -.15, spine: [-.35, 0, 0], head: [.15 + .03 * S(t * 23), 0, 0], armL: [-1.35, .1, .12], armR: [-1.35, .1, .12], foreL: [-.15, 0, 0], foreR: [-.15, 0, 0],
    handL: [-.4, 0, 0], handR: [-.4, 0, 0], legL: [-1.2, 0, .2], legR: [.35, 0, .15], shinL: [1.4, 0, 0], shinR: [.35, 0, 0], footL: [-.2, 0, 0] }),
  hangUpside: t => ({ spine: [0, 0, .04 * S(t * 1.5)], head: [0, 0, 0], armL: [-.3, 0, .25 + .05 * S(t * 2)], armR: [-.4, -.4, .3], foreL: [-1.9, 0, 0], foreR: [-1.8, 0, 0],
    legL: [0, 0, -.02], legR: [0, 0, -.02], shinL: [.05, 0, 0], shinR: [.05, 0, 0], footL: [.6, 0, 0], footR: [.6, 0, 0] }),
  sitChair: (t = 0) => ({ hy: -.42, hz: -.05, spine: [.08, 0, 0], legL: [-1.55, 0, .08], legR: [-1.55, 0, .08], shinL: [1.55, 0, 0], shinR: [1.55, 0, 0],
    armL: [-.6, 0, .15], armR: [-.6, 0, .15], foreL: [-.9, 0, 0], foreR: [-.9, 0, 0], head: [.04 * S(t), 0, 0] }),
  punch: (t, arm = 'R') => {
    const k = E.outCubic(clamp(t / .18)) * (1 - E.inQuad(clamp((t - .35) / .4)));
    const o = { grip: .95, spine: [.2, -.4 * k, 0], chest: [0, -.3 * k, 0], armL: [-.5, 0, .3], foreL: [-1.6, 0, 0], armR: [-.5, 0, .3], foreR: [-1.6, 0, 0], legL: [-.5, 0, .1], legR: [.4, 0, .1], shinL: [.4, 0, 0], hy: -.1 };
    o['arm' + arm] = [lerp(-.5, -1.55, k), 0, lerp(.3, .05, k)]; o['fore' + arm] = [lerp(-1.6, -.05, k), 0, 0];
    return o;
  },
  roar: (t = 0) => ({ grip: 1, spine: [-.25, 0, 0], head: [-.35, 0, 0], armL: [-.3, 0, 1.0 + .05 * S(t * 30)], armR: [-.3, 0, 1.0 + .05 * S(t * 30)], foreL: [-1.3, 0, 0], foreR: [-1.3, 0, 0], legL: [-.2, 0, .25], legR: [-.2, 0, .25], shinL: [.3, 0, 0], shinR: [.3, 0, 0], hy: -.05 }),
  dodge: () => ({ hy: -.35, spine: [.3, 0, .9], head: [0, 0, -.5], armL: [-.4, 0, 1.6], foreL: [-.4, 0, 0], armR: [.2, 0, .4], foreR: [-1.0, 0, 0],
    legL: [-.3, 0, .6], legR: [-1.0, 0, -.1], shinL: [.3, 0, 0], shinR: [1.6, 0, 0] }),
  strained: t => ({ spine: [.35, .4 * S(t * 2), .2 * S(t * 3)], head: [-.2, 0, 0], armL: [-1.1 + .3 * S(t * 25), 0, .5], armR: [-.9 + .3 * S(t * 23), 0, .5], foreL: [-.5, 0, 0], foreR: [-.5, 0, 0],
    legL: [-.3, 0, .2], legR: [-.3, 0, .2], shinL: [.5, 0, 0], shinR: [.5, 0, 0], hy: -.1 }),
  collapse: () => ({ hy: -.55, spine: [.9, 0, .2], head: [.4, 0, .3], armL: [.2, 0, .3], armR: [.4, 0, .1], foreL: [-.3, 0, 0], foreR: [-.2, 0, 0],
    legL: [-1.4, 0, .3], legR: [-1.0, 0, .3], shinL: [2.3, 0, 0], shinR: [2.0, 0, 0] }),
  phone: (t = 0) => ({ ...POSE.stand(t), armR: [-.5, .4, .45], foreR: [-2.3, 0, 0], handR: [0, 0, .5], head: [0, -.1, .1] }),
  reach: () => ({ spine: [.2, 0, 0], armR: [-1.4, .2, .1], foreR: [-.2, 0, 0], handR: [.2, 0, 0], armL: [.1, 0, .15], foreL: [-.4, 0, 0], head: [.2, 0, 0] }),
  hold: () => ({ grip: .55, armL: [-.9, .3, .1], armR: [-.9, .3, .1], foreL: [-.8, 0, 0], foreR: [-.8, 0, 0], handL: [0, 0, -.3], handR: [0, 0, -.3], spine: [.05, 0, 0] }),
  pointFinger: (t = 0) => ({ ...POSE.stand(t), armR: [-1.25, .25, .2], foreR: [-.35, 0, 0], handR: [.15 * Math.sin(t * 9), 0, 0], gripR: .9, head: [.08, -.1, 0] }),
  adjustGlasses: (t = 0) => ({ ...POSE.stand(t), armL: [-.9, -.5, .3], foreL: [-2.35, 0, 0], handL: [0, 0, .4], gripL: .7, head: [.12, 0, 0] }),
  fistShake: (t = 0) => ({ ...POSE.stand(t), armR: [-.9, .1, .35], foreR: [-1.6, 0, 0], handR: [.15 * Math.sin(t * 16), 0, 0], gripR: 1, spine: [.08, -.1, 0] }),
  shrug: (t = 0) => ({ ...POSE.stand(t), armL: [-.2, 0, .45], armR: [-.2, 0, .45], foreL: [-1.3, 0, 0], foreR: [-1.3, 0, 0], gripL: 0, gripR: 0, head: [0, 0, .12] }),
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
  if (ch.kind === 'odilman') for (const L of ch.lensList) L.scale.set(1.5, .5 * (f.squint ?? 1) * (f.wide ? 1.3 : 1), .3);
  const fr = ch.faceRig; if (!fr) return;
  const blink = f.blink || 0;
  const look = f.look || [0, 0];
  const br = f.brow || 0; // >0 — тревога/удивление, <0 — злость
  const base = f.wide ? -.25 : f.squint ? .45 : br < 0 ? .3 - br * .25 : .12;
  const closure = Math.max(blink, base);
  fr.lids.forEach((l, i) => { const sx = i === 0 ? 1 : -1; l.rotation.set(lerp(-1.25, 1.6, clamp(closure)), 0, sx * (br < 0 ? br * .35 : br * .15)); });
  fr.eyes.forEach(e => { e.scale.set(f.wide ? 1.1 : 1, f.wide ? 1.3 : 1.2, .55); });
  fr.pupils.forEach(p => { p.position.x = look[0] * .011; p.position.y = look[1] * .011; });
  const smil = clamp(f.smile || 0), sq = f.squint ? .5 : br < 0 ? .25 : 0;
  fr.lowLids.forEach(l => l.rotation.x = lerp(1.25, .45, clamp(smil * .55 + sq + blink * .4)));
  fr.cheeks.forEach(c => { c.position.y = c.userData.y0 + smil * .012; c.scale.set(1.3 + smil * .15, .85 + smil * .2, .5); });
  fr.brows.forEach((b, i) => { const sx = i === 0 ? 1 : -1; b.rotation.z = sx * br * .38; b.position.y = fr.headC.y + .088 + br * .016 + (f.wide ? .01 : 0); });
  const mo = clamp(f.mouth || 0), sh = clamp(f.shape || 0), sm = f.smile || 0;
  const sx = (1.3 - mo * .2 + sm * .45) * (1 - sh * .45), sy = .2 + mo * 1.2 * (1 + sh * .3);
  fr.cav.scale.set(sx, sy, .45);
  fr.mouth.rotation.z = 0; fr.mouth.position.y = fr.headC.y - .068 + sm * .004;
  const fc = clamp(f.fric || 0);
  if (fc > .4) fr.cav.scale.set(sx * 1.05, Math.min(sy, .45), .45);          // «с/ф/ш»: губы почти сомкнуты, видны зубы
  fr.teeth.visible = mo > .18 || fc > .4; fr.teeth.scale.set(sx * .62, 1, 1); fr.teeth.position.y = .03 * Math.min(sy, fc > .4 ? .45 : sy) * .32;
  fr.tongue.visible = mo > .35; fr.tongue.position.y = -.03 * sy * .35;
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
