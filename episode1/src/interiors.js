// Интерьеры: лаборатория «Аркада» (внутри башни, в общей сцене города), кухня деда, логово Тени.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon, glow, mesh, rng, textTexture } from './core.js';
import { makeSpider } from './rig.js';

function canvasTex(w, h, draw) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}

/* ---------- лаборатория: координаты относительно башни, пол на y = 258.8 ---------- */
export function makeLab(tower) {
  const L = new THREE.Group(); L.position.y = 258.8; tower.add(L);
  const lab = { group: L, capsules: [], refs: {} };
  const floorTex = canvasTex(1024, 1024, (g, w, h) => {
    g.fillStyle = '#0a0f17'; g.fillRect(0, 0, w, h);
    g.strokeStyle = 'rgba(70,220,255,.35)'; g.lineWidth = 3;
    for (let i = 0; i <= 16; i++) { g.beginPath(); g.moveTo(i * w / 16, 0); g.lineTo(i * w / 16, h); g.stroke(); g.beginPath(); g.moveTo(0, i * h / 16); g.lineTo(w, i * h / 16); g.stroke(); }
    g.strokeStyle = 'rgba(70,220,255,.8)'; g.lineWidth = 6;
    g.beginPath(); g.arc(w / 2, h * .22, 110, 0, Math.PI * 2); g.stroke();
    g.beginPath(); g.arc(w / 2, h * .22, 150, 0, Math.PI * 2); g.stroke();
  });
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(49, 49), new THREE.MeshToonMaterial({ map: floorTex, emissive: 0xffffff, emissiveMap: floorTex, emissiveIntensity: .9 }));
  floor.rotation.x = -Math.PI / 2; floor.position.y = .02; L.add(floor);
  // потолок со световыми полосами
  const ceil = new THREE.Mesh(new THREE.PlaneGeometry(49, 49), toon(0x0d1119)); ceil.rotation.x = Math.PI / 2; ceil.position.y = 22.5; L.add(ceil);
  for (let x = -18; x <= 18; x += 9) mesh(new THREE.BoxGeometry(.6, .2, 40), glow(0xbff6ff, 2.2), { pos: [x, 22.3, 0], outline: false, parent: L });

  // лифтовая шахта с дверью (z = +13 — фасад дверей)
  mesh(new RoundedBoxGeometry(14, 22.4, 8, 2, .3), toon(0x232a36), { pos: [0, 11.2, 17], outline: false, parent: L });
  mesh(new THREE.BoxGeometry(7, 7.5, .3), toon(0x11151c), { pos: [0, 3.75, 12.9], outline: false, parent: L });
  const doors = [];
  for (const s of [-1, 1]) { const d = mesh(new THREE.BoxGeometry(3.2, 7, .3), toon(0x8592a6), { pos: [s * 1.6, 3.5, 12.75], outline: .04, parent: L }); doors.push(d); }
  mesh(new THREE.BoxGeometry(7.6, .4, .4), glow(0x3ff0ff, 2), { pos: [0, 7.8, 12.85], outline: false, parent: L });
  lab.doors = doors;
  const logo = textTexture('ПРОЕКТ «АРАХНА»', { size: 90, color: '#7ff8ff' });
  const lp = new THREE.Mesh(new THREE.PlaneGeometry(10, 10 / logo.aspect), new THREE.MeshBasicMaterial({ map: logo.tex, transparent: true, color: new THREE.Color(1.8, 1.8, 1.8) }));
  lp.position.set(0, 11, 12.81); L.add(lp);

  // капсулы
  const glassM = new THREE.MeshBasicMaterial({ color: 0x9fe8ff, transparent: true, opacity: .16, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending });
  const liquidM = new THREE.MeshBasicMaterial({ color: new THREE.Color(0x1fd0ff).multiplyScalar(.6), transparent: true, opacity: .32, depthWrite: false, blending: THREE.AdditiveBlending });
  const metal = toon(0x5c6678), ring = glow(0x3ff0ff, 2.6);
  const makeCapsule = (x, z, s = 1, gold = false) => {
    const c = new THREE.Group(); c.position.set(x, 0, z); c.scale.setScalar(s); L.add(c);
    mesh(new THREE.CylinderGeometry(1.25, 1.4, .8, 24), metal, { pos: [0, .4, 0], outline: .04, parent: c });
    mesh(new THREE.TorusGeometry(1.05, .06, 6, 32), ring, { pos: [0, .82, 0], rot: [Math.PI / 2, 0, 0], outline: false, parent: c });
    const glass = mesh(new THREE.CylinderGeometry(1.05, 1.05, 3.4, 28, 1, true), glassM, { pos: [0, 2.5, 0], outline: false, parent: c });
    const liquid = mesh(new THREE.CylinderGeometry(.98, .98, 3.2, 24), liquidM, { pos: [0, 2.45, 0], outline: false, parent: c });
    mesh(new THREE.CylinderGeometry(1.2, 1.25, .6, 24), metal, { pos: [0, 4.45, 0], outline: .04, parent: c });
    mesh(new THREE.CylinderGeometry(.2, .2, 3, 8), toon(0x2a303c), { pos: [0, 6.2, 0], outline: false, parent: c });
    const sp = makeSpider({ scale: gold ? 3.2 : 2.6, gold }); sp.position.set(0, 2.1, 0); c.add(sp);
    const cap = { g: c, glass, liquid, spider: sp, x, z, s, gold };
    lab.capsules.push(cap);
    return cap;
  };
  for (const x of [-9, 9]) for (const z of [-8, -2, 4]) makeCapsule(x, z);
  lab.main = makeCapsule(0, -11, 1.45, true);
  // реактор с ядром за главной капсулой
  const reactor = new THREE.Group(); reactor.position.set(0, 0, -17.5); L.add(reactor);
  mesh(new RoundedBoxGeometry(4, 10, 3, 2, .3), toon(0x2a3140), { pos: [0, 5, -.5], outline: .05, parent: reactor });
  const coreSlot = mesh(new THREE.BoxGeometry(2, 3.2, .4), toon(0x0b0e14), { pos: [0, 5, 1.05], outline: false, parent: reactor });
  const core = mesh(new THREE.CylinderGeometry(.35, .35, 2.4, 20), glow(0x5ff6ff, 3.2), { pos: [0, 5, 1.2], outline: .05, parent: reactor });
  for (const y of [2, 8]) mesh(new THREE.BoxGeometry(3, .25, .3), glow(0x3ff0ff, 2), { pos: [0, y, 1.0], outline: false, parent: reactor });
  lab.core = core;
  // кабели от реактора к капсулам
  const cableM = toon(0x151a22);
  for (const [x, z] of [[-9, -8], [9, -8], [-9, -2], [9, -2], [0, -11]]) {
    const pts = [new THREE.Vector3(0, .15, -16), new THREE.Vector3(x * .5, .15, (z - 16) / 2), new THREE.Vector3(x, .15, z)];
    L.add(new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 20, .12, 6), cableM));
  }
  // пульты с экранами у окон
  const screenTex = [
    canvasTex(512, 320, (g, w, h) => { g.fillStyle = '#04121a'; g.fillRect(0, 0, w, h); g.strokeStyle = '#3ff0ff'; g.lineWidth = 4; g.beginPath();
      for (let x = 0; x < w; x += 4) g.lineTo(x, h * .55 + Math.sin(x * .05) * 50 * Math.sin(x * .011)); g.stroke();
      g.fillStyle = '#7ff8ff'; g.font = '700 34px Rubik'; g.fillText('НИТЬ: 3,2 ГПа', 24, 50); g.fillText('ПРОЧНЕЕ СТАЛИ ×5', 24, 290); }),
    canvasTex(512, 320, (g, w, h) => { g.fillStyle = '#04121a'; g.fillRect(0, 0, w, h); g.strokeStyle = '#3ff0ff'; g.lineWidth = 3;
      for (let i = 1; i < 7; i++) { g.beginPath(); g.arc(w / 2, h / 2, i * 22, 0, Math.PI * 2); g.stroke(); }
      for (let a = 0; a < 8; a++) { g.beginPath(); g.moveTo(w / 2, h / 2); g.lineTo(w / 2 + Math.cos(a * Math.PI / 4) * 150, h / 2 + Math.sin(a * Math.PI / 4) * 150); g.stroke(); }
      g.fillStyle = '#ffcf5a'; g.font = '700 30px Rubik'; g.fillText('АРАХНА-7', 20, 40); }),
    canvasTex(512, 320, (g, w, h) => { g.fillStyle = '#1a0606'; g.fillRect(0, 0, w, h); g.fillStyle = '#ff5a4a'; g.font = '800 44px Rubik';
      g.fillText('ВНИМАНИЕ', 120, 120); g.font = '600 30px Rubik'; g.fillText('ОБРАЗЦЫ НЕ ГОТОВЫ', 90, 190); g.fillText('К ПРИМЕНЕНИЮ', 140, 235); }),
  ];
  lab.screens = [];
  [[-19, -6, 0], [-19, 2, 1], [-19, 10, 2], [6, -16, 1]].forEach(([x, z, k], i) => {
    const d = new THREE.Group(); d.position.set(x, 0, z); d.rotation.y = i < 3 ? Math.PI / 2 : 0; L.add(d);
    mesh(new RoundedBoxGeometry(5, 1.2, 1.8, 2, .15), toon(0x2a3140), { pos: [0, 1.4, 0], outline: .04, parent: d });
    mesh(new THREE.BoxGeometry(.3, 1.4, .3), toon(0x1a1f28), { pos: [0, .5, 0], outline: false, parent: d });
    const s = new THREE.Mesh(new THREE.PlaneGeometry(4, 2.5), new THREE.MeshBasicMaterial({ map: screenTex[k], color: new THREE.Color(1.6, 1.6, 1.6) }));
    s.position.set(0, 3.3, -.3); d.add(s); lab.screens.push(s);
  });
  // свет лаборатории (в сцене города постоянно, выключается вне лаборатории)
  const l1 = new THREE.PointLight(0x7feaff, 0, 46, 1.2); l1.position.set(0, 16, -4); L.add(l1);
  const l2 = new THREE.PointLight(0xffffff, 0, 30, 1.4); l2.position.set(-12, 10, 8); L.add(l2);
  const l3 = new THREE.PointLight(0xff4020, 0, 40, 1.3); l3.position.set(0, 6, 9); L.add(l3);
  lab.lights = [l1, l2, l3];
  // осколки стекла и искры (пулы)
  lab.shards = makeShards(L, 260);
  return lab;
}

export function makeShards(parent, n, seed = 9) {
  const g = new THREE.InstancedMesh(new THREE.TetrahedronGeometry(.12), new THREE.MeshBasicMaterial({ color: 0xc8f4ff }), n);
  g.frustumCulled = false; g.visible = false; parent.add(g);
  const r = rng(seed);
  const data = [];
  for (let i = 0; i < n; i++) data.push({ v: new THREE.Vector3((r() - .5) * 2, r() * 1.5 + .2, (r() - .5) * 2).normalize().multiplyScalar(4 + r() * 9), s: .5 + r() * 1.5, rot: r() * 10, src: Math.floor(r() * 1000) });
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), p = new THREE.Vector3(), sc = new THREE.Vector3();
  return {
    mesh: g,
    // dt — время с момента взрыва; origins — список точек-источников
    update(dt, origins, slow = 1) {
      g.visible = dt > 0 && dt < 4;
      if (!g.visible) return;
      const T = dt * slow;
      data.forEach((d, i) => {
        const o = origins[d.src % origins.length];
        p.copy(o).addScaledVector(d.v, T); p.y -= 9.8 * T * T * .5;
        if (p.y < .05) p.y = .05;
        e.set(d.rot + T * 7, d.rot * 2 + T * 5, 0); q.setFromEuler(e); sc.setScalar(d.s);
        m4.compose(p, q, sc); g.setMatrixAt(i, m4);
      });
      g.instanceMatrix.needsUpdate = true;
    },
  };
}

/* ---------- кухня деда ---------- */
export function makeKitchen() {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x120c0a);
  const K = { scene };
  const wallTex = canvasTex(512, 512, (g, w, h) => {
    g.fillStyle = '#c99a6b'; g.fillRect(0, 0, w, h);
    g.fillStyle = 'rgba(120,70,40,.18)'; for (let x = 0; x < w; x += 64) g.fillRect(x, 0, 32, h);
    g.fillStyle = '#7a4a2e'; g.fillRect(0, h * .62, w, 10);
    g.fillStyle = '#5c8a8a'; g.fillRect(0, h * .64, w, h * .36);
    for (let x = 0; x < w; x += 32) for (let y = h * .64; y < h; y += 32) { g.strokeStyle = 'rgba(255,255,255,.15)'; g.strokeRect(x, y, 32, 32); }
  });
  wallTex.wrapS = THREE.RepeatWrapping; wallTex.repeat.set(3, 1);
  const wallM = new THREE.MeshToonMaterial({ map: wallTex });
  const floorTex = canvasTex(512, 512, (g, w, h) => {
    for (let i = 0; i < 8; i++) { g.fillStyle = i % 2 ? '#6b4128' : '#5a3520'; g.fillRect(0, i * 64, w, 64); g.fillStyle = 'rgba(0,0,0,.25)'; g.fillRect(0, i * 64, w, 3); }
  });
  floorTex.wrapS = floorTex.wrapT = THREE.RepeatWrapping; floorTex.repeat.set(2, 2);
  const fl = new THREE.Mesh(new THREE.PlaneGeometry(8, 8), new THREE.MeshToonMaterial({ map: floorTex })); fl.rotation.x = -Math.PI / 2; scene.add(fl);
  const back = new THREE.Mesh(new THREE.PlaneGeometry(8, 3.2), wallM); back.position.set(0, 1.6, -3); scene.add(back);
  const left = new THREE.Mesh(new THREE.PlaneGeometry(8, 3.2), wallM); left.position.set(-3.5, 1.6, 0); left.rotation.y = Math.PI / 2; scene.add(left);
  const right = new THREE.Mesh(new THREE.PlaneGeometry(8, 3.2), wallM); right.position.set(3.5, 1.6, 0); right.rotation.y = -Math.PI / 2; scene.add(right);
  const ceil = new THREE.Mesh(new THREE.PlaneGeometry(8, 8), toon(0x8a6a50)); ceil.position.y = 3.2; ceil.rotation.x = Math.PI / 2; scene.add(ceil);
  // окно с ночным городом и дождём
  const winTex = canvasTex(512, 384, (g, w, h) => {
    const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#0a0e22'); gr.addColorStop(1, '#2a1a30'); g.fillStyle = gr; g.fillRect(0, 0, w, h);
    const r = rng(5);
    for (let i = 0; i < 26; i++) { const bx = r() * w, bw = 20 + r() * 50, bh = 80 + r() * 220; g.fillStyle = '#0d1020'; g.fillRect(bx, h - bh, bw, bh);
      for (let y = h - bh + 6; y < h; y += 12) for (let x = bx + 4; x < bx + bw - 4; x += 9) if (r() < .4) { g.fillStyle = r() < .7 ? '#ffc070' : '#80c8ff'; g.fillRect(x, y, 4, 6); } }
    g.strokeStyle = 'rgba(200,220,255,.25)'; for (let i = 0; i < 90; i++) { const x = r() * w, y = r() * h; g.beginPath(); g.moveTo(x, y); g.lineTo(x - 3, y + 20); g.stroke(); }
  });
  const win = new THREE.Mesh(new THREE.PlaneGeometry(1.8, 1.3), new THREE.MeshBasicMaterial({ map: winTex, color: new THREE.Color(1.3, 1.3, 1.3) }));
  win.position.set(1.4, 1.75, -2.98); scene.add(win);
  const frameM = toon(0xf0e6d8);
  for (const [x, y, w, h] of [[1.4, 2.42, 1.95, .1], [1.4, 1.08, 1.95, .1], [.45, 1.75, .1, 1.4], [2.35, 1.75, .1, 1.4], [1.4, 1.75, .06, 1.3]]) mesh(new THREE.BoxGeometry(w, h, .08), frameM, { pos: [x, y, -2.94], outline: .01, parent: scene });
  // фото деда в горах (рамка) — отсылка к карабину
  const photo = canvasTex(256, 320, (g, w, h) => {
    g.fillStyle = '#e8dcc0'; g.fillRect(0, 0, w, h); g.fillStyle = '#9ec3e0'; g.fillRect(14, 14, w - 28, h - 70);
    g.fillStyle = '#5d6a7a'; g.beginPath(); g.moveTo(14, h - 56); g.lineTo(90, 70); g.lineTo(140, 130); g.lineTo(190, 50); g.lineTo(w - 14, h - 56); g.fill();
    g.fillStyle = '#fff'; g.beginPath(); g.moveTo(70, 105); g.lineTo(90, 70); g.lineTo(108, 92); g.fill(); g.beginPath(); g.moveTo(175, 80); g.lineTo(190, 50); g.lineTo(206, 78); g.fill();
    g.fillStyle = '#c0392b'; g.fillRect(150, 150, 10, 22); g.fillStyle = '#d9996b'; g.beginPath(); g.arc(155, 145, 6, 0, 7); g.fill();
    g.fillStyle = '#3a2a1a'; g.font = '600 22px Rubik'; g.fillText('Памир, 1979', 60, h - 22);
  });
  const ph = new THREE.Mesh(new THREE.PlaneGeometry(.5, .62), new THREE.MeshToonMaterial({ map: photo })); ph.position.set(-1.6, 2.0, -2.97); scene.add(ph);
  mesh(new THREE.BoxGeometry(.58, .7, .03), toon(0x5a3a22), { pos: [-1.6, 2.0, -2.99], outline: .01, parent: scene });
  // стол, стулья, посуда
  const T = new THREE.Group(); T.position.set(0, 0, -.6); scene.add(T);
  mesh(new THREE.BoxGeometry(1.9, .08, 1.1), toon(0x8a5a36), { pos: [0, .78, 0], outline: .015, parent: T });
  mesh(new THREE.BoxGeometry(2.0, .02, 1.2), toon(0xd9cdb8), { pos: [0, .83, 0], outline: false, parent: T });
  for (const [x, z] of [[.85, .45], [-.85, .45], [.85, -.45], [-.85, -.45]]) mesh(new THREE.BoxGeometry(.07, .78, .07), toon(0x6a4226), { pos: [x, .39, z], outline: .01, parent: T });
  const plateM = toon(0xffffff), riceM = toon(0xf0c060);
  K.plates = [];
  for (const x of [-.5, .5]) {
    const p = new THREE.Group(); p.position.set(x, .85, .1); T.add(p); K.plates.push(p);
    mesh(new THREE.CylinderGeometry(.22, .16, .04, 24), plateM, { outline: .008, parent: p });
    mesh(new THREE.SphereGeometry(.15, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), riceM, { scale: [1, .5, 1], pos: [0, .02, 0], outline: .006, parent: p });
    for (let i = 0; i < 5; i++) mesh(new THREE.BoxGeometry(.04, .03, .04), toon(0xd2691e), { pos: [Math.cos(i * 1.3) * .07, .07, Math.sin(i * 1.3) * .07], outline: false, parent: p });
  }
  // чайник и пиалы
  mesh(new THREE.SphereGeometry(.12, 16, 12), toon(0x2a6bb0), { pos: [0, .95, -.25], scale: [1, .85, 1], outline: .008, parent: T });
  mesh(new THREE.CylinderGeometry(.015, .025, .14, 8), toon(0x2a6bb0), { pos: [.13, .97, -.25], rot: [0, 0, -.9], outline: .005, parent: T });
  for (const x of [-.25, .25]) mesh(new THREE.CylinderGeometry(.05, .035, .05, 14), toon(0x2a6bb0), { pos: [x, .87, -.2], outline: .005, parent: T });
  const chairs = [];
  for (const x of [-.55, .55]) for (const s of [1, -1]) {
    const c = new THREE.Group(); c.position.set(x, 0, -.6 + s * .85); c.rotation.y = s > 0 ? Math.PI : 0; scene.add(c); chairs.push(c);
    mesh(new THREE.BoxGeometry(.45, .05, .45), toon(0x7a4a2a), { pos: [0, .46, 0], outline: .01, parent: c });
    mesh(new THREE.BoxGeometry(.45, .55, .05), toon(0x7a4a2a), { pos: [0, .75, -.22], outline: .01, parent: c });
    for (const [a, b] of [[.2, .2], [-.2, .2], [.2, -.2], [-.2, -.2]]) mesh(new THREE.BoxGeometry(.04, .46, .04), toon(0x5a3420), { pos: [a, .23, b], outline: false, parent: c });
  }
  K.chairs = chairs;
  // холодильник и плита
  mesh(new RoundedBoxGeometry(.8, 1.9, .7, 2, .08), toon(0xe9e5dc), { pos: [-2.9, .95, -2.4], outline: .015, parent: scene });
  mesh(new RoundedBoxGeometry(.8, .9, .7, 2, .05), toon(0xd8d4cc), { pos: [-2.0, .45, -2.55], outline: .015, parent: scene });
  mesh(new THREE.CylinderGeometry(.2, .18, .25, 16), toon(0x9a9aa6), { pos: [-2.0, 1.03, -2.55], outline: .008, parent: scene });
  // дверь
  mesh(new THREE.BoxGeometry(1.0, 2.1, .06), toon(0x5a3a22), { pos: [3.46, 1.05, .6], rot: [0, -Math.PI / 2, 0], outline: .01, parent: scene });
  // лампа над столом
  mesh(new THREE.CylinderGeometry(.05, .35, .25, 20, 1, true), toon(0xd9a441, { side: THREE.DoubleSide }), { pos: [0, 2.55, -.6], outline: .01, parent: scene });
  mesh(new THREE.SphereGeometry(.09, 12, 8), glow(0xffe0a0, 4), { pos: [0, 2.48, -.6], outline: false, parent: scene });
  mesh(new THREE.CylinderGeometry(.008, .008, .6, 4), toon(0x111111), { pos: [0, 2.9, -.6], outline: false, parent: scene });
  scene.add(new THREE.HemisphereLight(0xffe2c0, 0x3a2418, 1.0));
  const lamp = new THREE.PointLight(0xffc880, 2.6, 9, 1.4); lamp.position.set(0, 2.3, -.6); scene.add(lamp);
  const winL = new THREE.PointLight(0x6080ff, 3, 6, 1.5); winL.position.set(1.4, 1.8, -2.5); scene.add(winL);
  K.flashLight = winL;
  return K;
}

/* ---------- логово Тени (тизер) ---------- */
export function makeLair() {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x030305);
  scene.fog = new THREE.Fog(0x030305, 6, 22);
  const Z = { scene, screens: [] };
  const fl = new THREE.Mesh(new THREE.PlaneGeometry(30, 30), toon(0x0b0b10)); fl.rotation.x = -Math.PI / 2; scene.add(fl);
  // стена мониторов
  const mk = (i) => canvasTex(320, 200, (g, w, h) => {
    g.fillStyle = '#0a0204'; g.fillRect(0, 0, w, h);
    g.strokeStyle = 'rgba(255,40,40,.35)'; g.lineWidth = 1; for (let y = 0; y < h; y += 4) { g.beginPath(); g.moveTo(0, y); g.lineTo(w, y); g.stroke(); }
    g.fillStyle = '#ff3a3a'; g.strokeStyle = '#ff3a3a'; g.lineWidth = 3;
    if (i % 3 === 0) { // силуэт героя на нити
      g.beginPath(); g.moveTo(w * .2, 0); g.lineTo(w * .55, h * .55); g.stroke();
      g.beginPath(); g.arc(w * .57, h * .6, 12, 0, 7); g.fill(); g.fillRect(w * .53, h * .64, 18, 34);
      g.font = '700 18px Rubik'; g.fillText('ОБЪЕКТ: ???', 12, h - 12);
    } else if (i % 3 === 1) { // карта
      for (let k = 0; k < 9; k++) { g.strokeRect(20 + k * 32, 20, 26, h - 40); }
      g.beginPath(); g.arc(w * .62, h * .45, 16, 0, 7); g.stroke(); g.font = '700 18px Rubik'; g.fillText('МОСТ · 23:47', 14, h - 10);
    } else { // паук
      g.beginPath(); g.arc(w / 2, h / 2, 18, 0, 7); g.fill();
      for (let a = 0; a < 8; a++) { const an = (a < 4 ? -.9 : 2.24) + (a % 4) * .45; g.beginPath(); g.moveTo(w / 2, h / 2); g.lineTo(w / 2 + Math.cos(an) * 60, h / 2 + Math.sin(an) * 50); g.stroke(); }
      g.font = '700 18px Rubik'; g.fillText('АРАХНА-7: НОСИТЕЛЬ НАЙДЕН', 14, h - 10);
    }
  });
  for (let r = 0; r < 3; r++) for (let c = 0; c < 5; c++) {
    const s = new THREE.Mesh(new THREE.PlaneGeometry(1.9, 1.15), new THREE.MeshBasicMaterial({ map: mk(r * 5 + c), color: new THREE.Color(1.5, 1.5, 1.5) }));
    const a = (c - 2) * .3;
    s.position.set(Math.sin(a) * 6, 1.2 + r * 1.3, -Math.cos(a) * 6 + 2); s.rotation.y = -a; scene.add(s); Z.screens.push(s);
    mesh(new THREE.BoxGeometry(2.0, 1.25, .08), toon(0x111111), { pos: [s.position.x, s.position.y, s.position.z - .06], rot: [0, -a, 0], outline: false, parent: scene });
  }
  // кресло
  mesh(new RoundedBoxGeometry(1.2, 1.8, .3, 2, .1), toon(0x0d0d12), { pos: [0, 1.3, -.3], outline: .02, parent: scene });
  scene.add(new THREE.HemisphereLight(0x401010, 0x000000, .6));
  const red = new THREE.PointLight(0xff2020, 14, 14, 1.5); red.position.set(0, 2.5, -2); scene.add(red);
  Z.red = red;
  return Z;
}
