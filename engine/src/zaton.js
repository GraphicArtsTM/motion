// Старый Затон (серия 2): двор пятиэтажки, где живут Тимур и Маржон, улица с остановкой «42» и — в стороне,
// в той же сцене — фасад лицея «Новоград» с воротами. Время суток — Z.setTime('morning' | 'sunset' | 'dusk').
// Координаты (м, Y — вверх):
//   дом Тимура и Маржон: фасад на z = 0 (смотрит в +z), x −36…36, 5 этажей (пол 1-го этажа y = 1.0, этаж 2.8 м);
//   подъезды: x = −16.5, −4.5 (Тимур, Z.door.timur), 4.5 (Маржон, Z.door.marjon), 16.5; лавочки у подъездов z ≈ 2.4;
//   окно мамы Маржон — 2-й этаж над её подъездом (Z.momWin, x = 10.5, y = 5.35);
//   двор z 4…16 (площадка x −32…−18), тротуар z 16…19.5, дорога z 19.5…27, остановка «42» — (22, 0, 18.2);
//   через дорогу — дом с магазином «ПРОДУКТЫ» (фасад на z = 34);
//   лицей — группа Z.school в (600, 0, 0): фасад z = 0, портик x −7…7, ворота x ±4 на z = 16, флаги z = 10.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon, glow, mesh, rng, textTexture } from './core.js';
import { makeCar, makeBus } from './city.js';

const tex = (w, h, draw, rep) => {
  const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  if (rep) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(...rep); }
  return t;
};
const rb = (x, y, z, r = .05) => new RoundedBoxGeometry(x, y, z, 2, Math.min(r, x / 2.1, y / 2.1, z / 2.1));
const PX = 28;                                   // пикселей на метр в текстурах фасадов

/* фасад панельной пятиэтажки: цвет + карта светящихся окон; stair — номера колонок-лестниц */
function panelFacade(cols, stair, seed, o = {}) {
  const w = cols * 3 * PX, h = 16 * PX, r = rng(seed);
  const lit = [];
  const col = tex(w, h, (g) => {
    g.fillStyle = o.wall || '#d9d2c4'; g.fillRect(0, 0, w, h);
    // панели и швы
    g.strokeStyle = 'rgba(80,70,60,.28)'; g.lineWidth = 2;
    for (let i = 0; i <= cols; i++) { g.beginPath(); g.moveTo(i * 3 * PX, 0); g.lineTo(i * 3 * PX, h); g.stroke(); }
    for (let f = 0; f <= 5; f++) { const y = h - (1 + f * 2.8) * PX; g.beginPath(); g.moveTo(0, y); g.lineTo(w, y); g.stroke(); }
    g.fillStyle = 'rgba(0,0,0,.06)'; for (let i = 0; i < 80; i++) g.fillRect(r() * w, r() * h, 2 + r() * 30, 2 + r() * 60);   // подтёки
    g.fillStyle = o.plinth || '#8d7f70'; g.fillRect(0, h - PX, w, PX);                                                        // цоколь
    g.fillStyle = '#b7ad9c'; g.fillRect(0, 0, w, PX * .9);                                                                    // парапет
    for (let i = 0; i < cols; i++) {
      const x0 = i * 3 * PX;
      if (stair.includes(i)) {          // лестничная клетка: узкие окна на полуэтажах
        for (let f = 1; f < 5; f++) { const y = h - (1 + f * 2.8 - 1.0) * PX; g.fillStyle = '#4a5a6a'; g.fillRect(x0 + 1.0 * PX, y - .9 * PX, 1.0 * PX, .9 * PX); g.fillStyle = '#e8e4da'; g.fillRect(x0 + 1.47 * PX, y - .9 * PX, 3, .9 * PX); }
        continue;
      }
      for (let f = 0; f < 5; f++) {
        const yb = h - (1 + f * 2.8 + .8) * PX, ww = 1.5 * PX, wh = 1.45 * PX, wx = x0 + .75 * PX;
        g.fillStyle = '#efeae0'; g.fillRect(wx - 4, yb - wh - 4, ww + 8, wh + 8);                         // рама
        const k = r(); g.fillStyle = k < .3 ? '#3b4a5c' : k < .6 ? '#4d5f73' : '#2f3a48'; g.fillRect(wx, yb - wh, ww, wh);
        if (r() < .7) { g.fillStyle = ['#e7c58a', '#c98a8a', '#9fc0a0', '#e8e0d0', '#d8a05a'][Math.floor(r() * 5)]; g.fillRect(wx, yb - wh, ww * (.2 + r() * .2), wh); g.fillRect(wx + ww * (.8 - r() * .15), yb - wh, ww * .25, wh); }
        g.fillStyle = 'rgba(255,255,255,.18)'; g.beginPath(); g.moveTo(wx, yb - wh); g.lineTo(wx + ww * .4, yb - wh); g.lineTo(wx, yb - wh * .4); g.fill();   // отблеск
        g.fillStyle = '#efeae0'; g.fillRect(wx + ww / 2 - 2, yb - wh, 4, wh); g.fillRect(wx - 6, yb, ww + 12, 5);   // импост и отлив
        if (r() < .55) lit.push([wx, yb - wh, ww, wh, r()]);
      }
    }
  });
  const emi = tex(w, h, (g) => {
    g.fillStyle = '#000'; g.fillRect(0, 0, w, h);
    for (const [x, y, ww, hh, k] of lit) { g.fillStyle = k < .75 ? '#ffb85a' : k < .9 ? '#ffe2a8' : '#9fc8ff'; g.fillRect(x, y, ww, hh); }
    for (let i = 0; i < cols; i++) if (stair.includes(i)) for (let f = 1; f < 5; f++) { g.fillStyle = '#c8d8b0'; g.fillRect(i * 3 * PX + PX, h - (1 + f * 2.8 - 1) * PX - .9 * PX, PX, .9 * PX); }
  });
  return { col, emi, w: cols * 3 };
}

/* дерево: ствол + крона из «облаков» осенних цветов */
function tree(parent, x, z, s, seed, birch = false) {
  const r = rng(seed), g = new THREE.Group(); g.position.set(x, 0, z); g.scale.setScalar(s); g.rotation.y = r() * 6; parent.add(g);
  const barkM = toon(birch ? 0xeeeae0 : 0x5a4636);
  mesh(new THREE.CylinderGeometry(.16, .26, 3.4, 8), barkM, { pos: [0, 1.7, 0], outline: .02, parent: g });
  if (birch) for (let i = 0; i < 6; i++) mesh(new THREE.BoxGeometry(.2, .05, .02), toon(0x222222), { pos: [Math.cos(i) * .17, .5 + i * .45, Math.sin(i) * .17], rot: [0, -i, 0], outline: false, parent: g });
  for (const a of [.6, 2.6, 4.4]) mesh(new THREE.CylinderGeometry(.05, .1, 1.6, 6), barkM, { pos: [Math.cos(a) * .45, 3.4, Math.sin(a) * .45], rot: [Math.sin(a) * .6, 0, -Math.cos(a) * .6], outline: .01, parent: g });
  const pal = birch ? [0xf2c63a, 0xe8d04a, 0xd9b030] : [[0xe0802a, 0xd06424, 0xf0a030], [0xf2c63a, 0xe0a828, 0xc9b23a], [0xb8462a, 0xd06a2a, 0xa83a22], [0x7aa04a, 0x9ab040, 0xd0a030]][Math.floor(r() * 4)];
  for (let i = 0; i < 7; i++) {
    const a = r() * 6.28, d = i ? .8 + r() * .9 : 0;
    mesh(new THREE.IcosahedronGeometry(1 + r() * .7, 1), toon(pal[i % pal.length]), { pos: [Math.cos(a) * d, 4.4 + r() * 1.4 + (i ? 0 : .8), Math.sin(a) * d], scale: [1, .85, 1], outline: .03, parent: g });
  }
  return g;
}

/* небо-купол с градиентом и солнцем */
function skyDome() {
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { top: { value: new THREE.Color() }, hor: { value: new THREE.Color() }, low: { value: new THREE.Color() }, sunDir: { value: new THREE.Vector3(0, 1, 0) }, sunCol: { value: new THREE.Color() }, sunK: { value: 1 }, time: { value: 0 }, cloudK: { value: 1 } },
    vertexShader: 'varying vec3 vD; void main(){ vD = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: `uniform vec3 top, hor, low, sunCol, sunDir; uniform float sunK, time, cloudK; varying vec3 vD;
      float hs(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      float vn(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hs(i), hs(i + vec2(1, 0)), f.x), mix(hs(i + vec2(0, 1)), hs(i + vec2(1, 1)), f.x), f.y); }
      float fbm(vec2 p){ float a = .5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * vn(p); p *= 2.03; a *= .5; } return s; }
      void main(){ float h = vD.y; vec3 c = h > 0.0 ? mix(hor, top, pow(clamp(h * 2.2, 0.0, 1.0), .7)) : mix(hor, low, clamp(-h * 6.0, 0.0, 1.0));
        float d = max(dot(normalize(vD), normalize(sunDir)), 0.0);
        c += sunCol * (pow(d, 900.0) * 3.0 + pow(d, 12.0) * .35 + pow(d, 3.0) * .12) * sunK;
        // кучевые облака: проекция на «купол», дрейф ветром; край к солнцу подсвечен
        if (h > 0.0) {
          vec2 uv = vD.xz / (h + .18) * 1.6 + vec2(time * .012, time * .004);
          float n = fbm(uv), cl = smoothstep(.52, .78, n) * smoothstep(.0, .12, h);
          float lit = clamp(fbm(uv + normalize(sunDir.xz) * .08) - n + .55, 0.0, 1.0);
          vec3 cc = mix(mix(top, hor, .5) * .75, mix(hor, vec3(1.0), .55) + sunCol * .35 * lit, lit) * cloudK + c * (1.0 - cloudK) * .9;
          c = mix(c, cc, cl * .85);
        }
        gl_FragColor = vec4(c, 1.0); }`,
  });
  const m = new THREE.Mesh(new THREE.SphereGeometry(2400, 32, 16), mat); m.frustumCulled = false; m.renderOrder = -10;
  return m;
}

/* кольцо силуэтов города на горизонте (с башней «Аркада» на севере, −z) */
function skylineRing() {
  const t = tex(4096, 512, (g, w, h) => {
    g.clearRect(0, 0, w, h); const r = rng(77);
    for (let layer = 0; layer < 2; layer++) {
      g.fillStyle = layer ? 'rgba(70,80,110,1)' : 'rgba(120,130,160,1)';
      for (let x = 0; x < w;) { const bw = 20 + r() * 70, bh = (layer ? 60 : 100) + r() * (layer ? 140 : 220); g.fillRect(x, h - bh, bw, bh); x += bw + r() * 10; }
    }
    // «Аркада» — тонкий шпиль с огоньком
    const ax = w * .75; g.fillStyle = 'rgba(60,70,100,1)'; g.fillRect(ax - 22, h - 470, 44, 470); g.beginPath(); g.moveTo(ax - 22, h - 470); g.lineTo(ax, h - 510); g.lineTo(ax + 22, h - 470); g.fill();
  });
  const mat = new THREE.MeshBasicMaterial({ map: t, transparent: true, side: THREE.BackSide, fog: false, depthWrite: false });
  const m = new THREE.Mesh(new THREE.CylinderGeometry(1100, 1100, 160, 64, 1, true), mat); m.position.y = 60; m.renderOrder = -9;
  return m;
}

/* ---------- время суток ---------- */
const TIMES = {
  morning: { top: 0x5f9fe6, hor: 0xf3e3c4, low: 0xc9c0b0, sun: 0xfff0d4, sunI: 2.5, dir: [.45, .62, .64], hs: 0xdde9ff, hg: 0x8a7a60, hI: 1.45, fog: 0xe6e4dc, win: .05, lamp: 0, exp: 1, cloud: 1 },
  sunset: { top: 0x41558f, hor: 0xff9e62, low: 0x6a4a50, sun: 0xffb06a, sunI: 2.6, dir: [-.78, .2, .6], hs: 0xffc8a8, hg: 0x5a4058, hI: 1.15, fog: 0xe8a07a, win: .8, lamp: .5, exp: 1, cloud: .9 },
  dusk: { top: 0x101a40, hor: 0x5a3a60, low: 0x20182a, sun: 0x9080ff, sunI: .5, dir: [-.6, .15, .7], hs: 0x6070b0, hg: 0x201828, hI: .8, fog: 0x2a2440, win: 1.6, lamp: 1.2, exp: 1, cloud: .35 },
};

export function makeZaton() {
  const scene = new THREE.Scene(); scene.background = new THREE.Color(0xe6e4dc);
  scene.fog = new THREE.Fog(0xe6e4dc, 90, 460);
  const Z = { scene, door: {}, lamps: [], swings: [], flags: [], winMats: [] };
  const sky = skyDome(); scene.add(sky); const ring = skylineRing(); scene.add(ring);
  const ringCol = new THREE.Color();

  /* земля: трава/листва, асфальт, тротуары, дорога */
  const grassT = tex(256, 256, (g, w, h) => { const r = rng(3); g.fillStyle = '#7d8a4a'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 1600; i++) { g.fillStyle = ['#8a9650', '#6f7c40', '#a89a48', '#b07a38', '#94a058'][i % 5]; g.fillRect(r() * w, r() * h, 2 + r() * 4, 2 + r() * 4); } }, [160, 160]);
  mesh(new THREE.PlaneGeometry(1600, 1600), toon(0xffffff, { map: grassT }), { rot: [-Math.PI / 2, 0, 0], outline: false, parent: scene });
  const asphT = tex(256, 256, (g, w, h) => { const r = rng(5); g.fillStyle = '#5a5a5e'; g.fillRect(0, 0, w, h); for (let i = 0; i < 2500; i++) { g.fillStyle = `rgba(${r() < .5 ? '255,255,255' : '0,0,0'},${.05 + r() * .08})`; g.fillRect(r() * w, r() * h, 2, 2); }
    g.strokeStyle = 'rgba(20,20,20,.35)'; g.lineWidth = 2; g.beginPath(); g.moveTo(30, 0); g.bezierCurveTo(80, 90, 40, 160, 120, 256); g.stroke(); }, [20, 2]);
  const tileT = tex(128, 128, (g, w, h) => { g.fillStyle = '#b8b0a2'; g.fillRect(0, 0, w, h); g.strokeStyle = 'rgba(60,50,40,.35)'; g.lineWidth = 2; for (let i = 0; i <= 4; i++) { g.beginPath(); g.moveTo(i * 32, 0); g.lineTo(i * 32, h); g.stroke(); g.beginPath(); g.moveTo(0, i * 32); g.lineTo(w, i * 32); g.stroke(); } }, [60, 2]);
  const roadT = tex(512, 128, (g, w, h) => { const r = rng(6); g.fillStyle = '#46474c'; g.fillRect(0, 0, w, h); for (let i = 0; i < 3000; i++) { g.fillStyle = `rgba(255,255,255,${r() * .06})`; g.fillRect(r() * w, r() * h, 2, 2); }
    g.fillStyle = '#e8e4d8'; for (let x = 0; x < w; x += 64) g.fillRect(x, h / 2 - 3, 36, 6); g.fillRect(0, 6, w, 4); g.fillRect(0, h - 10, w, 4); }, [12, 1]);
  const flat = (w, d, x, z, map, y = .01, rep) => { const m = map.clone(); m.needsUpdate = true; if (rep) m.repeat.set(...rep); return mesh(new THREE.PlaneGeometry(w, d), toon(0xffffff, { map: m }), { pos: [x, y, z], rot: [-Math.PI / 2, 0, 0], outline: false, parent: scene }); };
  flat(90, 4.4, 0, 3.2, asphT, .012, [18, 1]);              // проезд вдоль дома
  flat(1600, 3.5, 0, 17.75, tileT, .02, [400, 1]);          // тротуар
  flat(1600, 7.5, 0, 23.25, roadT, .015, [200, 1]);         // дорога
  flat(1600, 2.4, 0, 28.2, tileT, .02, [400, 1]);           // тротуар напротив
  for (const z of [16, 19.5, 27]) mesh(new THREE.BoxGeometry(1600, .16, .22), toon(0xa8a49a), { pos: [0, .08, z], outline: false, parent: scene });   // бордюры
  // дорожки к подъездам
  for (const x of [-16.5, -4.5, 4.5, 16.5]) flat(1.8, 2.6, x, 1.4, tileT, .018, [1, 1]);
  flat(2.2, 11, -1, 10.5, tileT, .018, [1, 5]);             // тропинка через двор

  /* дом Тимура и Маржон */
  const STAIR = [6, 10, 13, 17];
  const fac = panelFacade(24, STAIR, 12);
  const wm = toon(0xffffff, { map: fac.col, emissive: 0xffffff, emissiveMap: fac.emi, emissiveIntensity: 0 }); Z.winMats.push(wm);
  const house = new THREE.Group(); scene.add(house); Z.house = house;
  mesh(new THREE.BoxGeometry(72, 16, 12), toon(0xcfc7b8), { pos: [0, 8, -6], outline: .06, parent: house });
  const front = new THREE.Mesh(new THREE.PlaneGeometry(72, 16), wm); front.position.set(0, 8, .015); house.add(front);
  mesh(new THREE.BoxGeometry(72.4, .25, 12.4), toon(0x8a8478), { pos: [0, 16.1, -6], outline: .03, parent: house });     // крыша
  for (const x of [-20, 0, 20]) mesh(new THREE.BoxGeometry(1.2, 1.4, 1.2), toon(0x9a8a7a), { pos: [x, 16.9, -6], outline: .02, parent: house });  // вентшахты
  for (const x of [-26, -8, 14, 30]) mesh(new THREE.CylinderGeometry(.02, .02, 2.2, 4), toon(0x222222), { pos: [x, 17.3, -4], outline: false, parent: house });   // антенны
  const colX = i => -36 + 1.5 + 3 * i;
  // балконы
  const balR = rng(21);
  for (let i = 0; i < 24; i++) {
    if (STAIR.includes(i) || i % 4 !== 1) continue;
    for (let f = 1; f < 5; f++) {
      const b = new THREE.Group(); b.position.set(colX(i), 1 + f * 2.8, 0); house.add(b);
      mesh(new THREE.BoxGeometry(2.7, .14, 1.1), toon(0xbab2a4), { pos: [0, 0, .55], outline: .015, parent: b });
      const glazed = balR() < .5;
      mesh(new THREE.BoxGeometry(2.7, 1.0, .06), toon([0xd9d2c4, 0x9fb0c0, 0xc9a07a, 0xb8c8a8][Math.floor(balR() * 4)]), { pos: [0, .55, 1.08], outline: .012, parent: b });
      for (const sx of [-1, 1]) mesh(new THREE.BoxGeometry(.06, 1.0, 1.1), toon(0xc8c0b0), { pos: [sx * 1.33, .55, .55], outline: .01, parent: b });
      if (glazed) { mesh(new THREE.BoxGeometry(2.7, 1.2, .04), new THREE.MeshBasicMaterial({ color: 0x9ab8d0, transparent: true, opacity: .45 }), { pos: [0, 1.65, 1.08], outline: false, parent: b }); mesh(new THREE.BoxGeometry(2.7, .08, 1.1), toon(0xe8e4dc), { pos: [0, 2.26, .55], outline: .01, parent: b }); }
      else if (balR() < .6) for (let k = 0; k < 3; k++) mesh(new THREE.BoxGeometry(.3, .4, .02), toon([0xe85a5a, 0xffffff, 0x5a9ae8, 0xf2c94c][(i + f + k) % 4]), { pos: [-.8 + k * .5, 1.3, .9], outline: false, parent: b });   // бельё
      if (balR() < .4) mesh(new THREE.SphereGeometry(.22, 8, 6), toon(0x4a8a3a), { pos: [.9, 1.2, .9], outline: .008, parent: b });   // цветок
    }
  }
  // подъезды: козырёк, дверь, ступени, домофон, лампа, номер; лавочки
  const doorM = toon(0x6a3a2a), slab = toon(0xb0a898);
  [[-16.5, 1], [-4.5, 2], [4.5, 3], [16.5, 4]].forEach(([x, n]) => {
    const e = new THREE.Group(); e.position.set(x, 0, 0); house.add(e);
    mesh(new THREE.BoxGeometry(2.2, .3, 1.4), slab, { pos: [0, .15, .7], outline: .015, parent: e });
    mesh(new THREE.BoxGeometry(2.2, .15, .6), slab, { pos: [0, .38, .3], outline: .01, parent: e });
    mesh(new THREE.BoxGeometry(1.3, 2.2, .1), doorM, { pos: [0, 1.55, .05], outline: .015, parent: e });
    mesh(new THREE.BoxGeometry(.5, .5, .02), toon(0x8ab0c8), { pos: [0, 2.1, .11], outline: false, parent: e });
    mesh(new THREE.BoxGeometry(.06, .4, .06), toon(0xc9ced6), { pos: [.5, 1.4, .13], outline: false, parent: e });
    mesh(new THREE.BoxGeometry(.18, .26, .04), toon(0x2a2a2a), { pos: [.85, 1.5, .04], outline: .004, parent: e });   // домофон
    mesh(new THREE.BoxGeometry(2.8, .16, 1.7), slab, { pos: [0, 3.0, .85], outline: .02, parent: e });               // козырёк
    for (const sx of [-1.25, 1.25]) mesh(new THREE.CylinderGeometry(.05, .05, 2.6, 6), toon(0x707070), { pos: [sx, 1.7, 1.55], outline: .006, parent: e });
    const lamp = mesh(new THREE.SphereGeometry(.12, 10, 8), glow(0xffd9a0, .3), { pos: [0, 2.82, .3], outline: false, parent: e }); Z.lamps.push(lamp);
    const nt = textTexture(String(n), { size: 80, color: '#ffffff', bg: '#2f5f8a', weight: 800, font: 'Rubik' });
    const np = new THREE.Mesh(new THREE.PlaneGeometry(.35, .35 / nt.aspect * 1.4), new THREE.MeshBasicMaterial({ map: nt.tex })); np.position.set(-.9, 2.5, .02); e.add(np);
    for (const sx of [-1, 1]) {   // лавочки
      const b = new THREE.Group(); b.position.set(sx * 2.3, 0, 2.4); b.rotation.y = 0; e.add(b);
      mesh(rb(1.6, .06, .42), toon(0x8a5a36), { pos: [0, .45, 0], outline: .008, parent: b });
      mesh(rb(1.6, .32, .05), toon(0x8a5a36), { pos: [0, .7, -.2], rot: [-.15, 0, 0], outline: .008, parent: b });
      for (const lx of [-.65, .65]) mesh(new THREE.BoxGeometry(.06, .45, .4), toon(0x3a3a3a), { pos: [lx, .225, 0], outline: false, parent: b });
    }
    Z.door[n === 2 ? 'timur' : n === 3 ? 'marjon' : 'e' + n] = e;
  });
  const sign = textTexture('ул. Затонная, 12', { size: 60, color: '#ffffff', bg: '#1f4f7a', weight: 700, font: 'Rubik' });
  const sp = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 2.4 / sign.aspect), new THREE.MeshBasicMaterial({ map: sign.tex })); sp.position.set(-34.5, 3.6, .03); house.add(sp);
  // палисадники: бордюр + кусты
  const bushM = [toon(0x5a7a3a), toon(0x8a8a3a), toon(0xa86a2a)];
  for (let x = -34; x <= 34; x += 2.4) {
    if ([-16.5, -4.5, 4.5, 16.5].some(e => Math.abs(x - e) < 2.6)) continue;
    mesh(new THREE.IcosahedronGeometry(.55, 1), bushM[Math.abs(Math.round(x)) % 3], { pos: [x, .45, 1.0], scale: [1.3, .8, .9], outline: .015, parent: scene });
  }
  // окно мамы Маржон (2-й этаж справа от её подъезда): створка открывается, внутри свет и силуэт
  const mw = new THREE.Group(); mw.position.set(10.5, 5.35, .02); house.add(mw); Z.momWin = mw;
  const roomT = tex(128, 128, (g, w, h) => { const gr = g.createRadialGradient(64, 40, 10, 64, 64, 90); gr.addColorStop(0, '#ffe2a8'); gr.addColorStop(1, '#d08a40'); g.fillStyle = gr; g.fillRect(0, 0, w, h);
    g.fillStyle = '#b06030'; g.fillRect(0, 0, 22, h); g.fillRect(w - 22, 0, 22, h); });
  const room = mesh(new THREE.PlaneGeometry(1.5, 1.45), new THREE.MeshBasicMaterial({ map: roomT }), { pos: [0, 0, .01], outline: false, parent: mw }); Z.momRoom = room;
  const silT = tex(128, 160, (g) => { g.fillStyle = '#3a2418'; g.beginPath(); g.arc(64, 54, 26, 0, 7); g.fill(); g.beginPath(); g.moveTo(14, 160); g.quadraticCurveTo(20, 92, 64, 88); g.quadraticCurveTo(108, 92, 114, 160); g.fill();
    g.beginPath(); g.ellipse(64, 34, 30, 16, 0, 0, 7); g.fill(); });
  Z.momSil = mesh(new THREE.PlaneGeometry(.8, 1.0), new THREE.MeshBasicMaterial({ map: silT, transparent: true }), { pos: [0, -.25, .02], outline: false, parent: mw }); Z.momSil.visible = false;
  const sash = new THREE.Group(); sash.position.set(-.75, 0, .04); mw.add(sash); Z.momSash = sash;
  mesh(new THREE.BoxGeometry(.75, 1.45, .05), new THREE.MeshBasicMaterial({ color: 0x4d5f73, transparent: true, opacity: .75 }), { pos: [.375, 0, 0], outline: false, parent: sash });
  for (const [w, h, x, y] of [[.75, .06, .375, .7], [.75, .06, .375, -.7], [.06, 1.45, 0, 0], [.06, 1.45, .75, 0]]) mesh(new THREE.BoxGeometry(w, h, .07), toon(0xefeae0), { pos: [x, y, 0], outline: false, parent: sash });
  mesh(new THREE.BoxGeometry(.75, 1.45, .05), new THREE.MeshBasicMaterial({ color: 0x4d5f73, transparent: true, opacity: .75 }), { pos: [.375, 0, .04], outline: false, parent: mw });
  for (const [w, h, x, y] of [[1.62, .08, 0, .76], [1.62, .08, 0, -.76], [.08, 1.6, -.78, 0], [.08, 1.6, .78, 0]]) mesh(new THREE.BoxGeometry(w, h, .08), toon(0xefeae0), { pos: [x, y, .05], outline: .006, parent: mw });

  /* двор: деревья, площадка, бельё, контейнеры, машины */
  const T = [[-38, 7, 1.1, 0], [-12.5, 7, 1.0, 1], [-1.5, 12.5, 1.15, 0], [11.5, 7.5, .95, 1], [24, 12, 1.2, 0], [36, 7.5, 1.05, 0],
    [-26, 15.2, .9, 1], [-8, 15.2, 1.0, 0], [13, 15.2, .95, 0], [32, 15.4, 1.0, 1], [-46, 12, 1.2, 0], [46, 12, 1.1, 1],
    [-20, 31, 1.1, 0], [6, 31, 1.0, 1], [28, 31, 1.15, 0]];
  T.forEach(([x, z, s, b], i) => tree(scene, x, z, s, 100 + i, !!b));
  // листья на земле
  const leafG = new THREE.CircleGeometry(.09, 5), leafM = toon(0xffffff);
  const leaves = new THREE.InstancedMesh(leafG, leafM, 1400); const lr = rng(55), dm = new THREE.Object3D(), lc = new THREE.Color();
  for (let i = 0; i < 1400; i++) {
    const tz = i < 1100 ? 1 + lr() * 18 : 27 + lr() * 4, tx = (lr() - .5) * 90;
    dm.position.set(tx, .025 + lr() * .01, tz); dm.rotation.set(-Math.PI / 2, 0, lr() * 6); dm.scale.set(1 + lr(), .6 + lr() * .4, 1); dm.updateMatrix(); leaves.setMatrixAt(i, dm.matrix);
    leaves.setColorAt(i, lc.set([0xe0802a, 0xf2c63a, 0xb8462a, 0xd09a30, 0x9a6a2a][i % 5]));
  }
  scene.add(leaves);
  // детская площадка
  const pg = new THREE.Group(); pg.position.set(-25, 0, 10); scene.add(pg);
  const pipeM = toon(0x2f7ab0), red = toon(0xd8402c), yel = toon(0xf2c63a);
  for (const sx of [-1.6, 1.6]) for (const sz of [-.7, .7]) mesh(new THREE.CylinderGeometry(.06, .06, 2.7, 8), pipeM, { pos: [-4 + sx, 1.3, sz * .6], rot: [sz > 0 ? -.25 : .25, 0, 0], outline: .008, parent: pg });
  mesh(new THREE.CylinderGeometry(.07, .07, 3.4, 8), pipeM, { pos: [-4, 2.6, 0], rot: [0, 0, Math.PI / 2], outline: .008, parent: pg });
  for (const sx of [-.8, .8]) {
    const sw = new THREE.Group(); sw.position.set(-4 + sx, 2.6, 0); pg.add(sw); Z.swings.push(sw);
    for (const cx of [-.25, .25]) mesh(new THREE.CylinderGeometry(.012, .012, 2.0, 4), toon(0x777777), { pos: [cx, -1.0, 0], outline: false, parent: sw });
    mesh(rb(.62, .05, .26), sx < 0 ? red : yel, { pos: [0, -2.0, 0], outline: .006, parent: sw });
  }
  // горка
  mesh(new THREE.BoxGeometry(1.2, 1.6, 1.2), red, { pos: [2.5, .8, -.5], outline: .015, parent: pg });
  mesh(new THREE.ConeGeometry(.95, .8, 4), yel, { pos: [2.5, 2.0, -.5], rot: [0, Math.PI / 4, 0], outline: .012, parent: pg });
  mesh(new THREE.BoxGeometry(.8, .06, 2.8), toon(0xc9ced6), { pos: [2.5, .9, 1.2], rot: [.62, 0, 0], outline: .01, parent: pg });
  // песочница с грибком
  mesh(new THREE.BoxGeometry(2.4, .3, 2.4), toon(0x9a6a3a), { pos: [-.5, .15, 3.3], outline: .012, parent: pg });
  mesh(new THREE.BoxGeometry(2.1, .32, 2.1), toon(0xe8d09a), { pos: [-.5, .16, 3.3], outline: false, parent: pg });
  mesh(new THREE.CylinderGeometry(.06, .06, 2.0, 6), toon(0x6a4a2a), { pos: [-.5, 1.0, 3.3], outline: .006, parent: pg });
  mesh(new THREE.ConeGeometry(1.0, .5, 16), red, { pos: [-.5, 2.1, 3.3], outline: .012, parent: pg });
  for (let i = 0; i < 6; i++) mesh(new THREE.SphereGeometry(.09, 6, 4), toon(0xffffff), { pos: [-.5 + Math.cos(i) * .6, 2.05, 3.3 + Math.sin(i) * .6], scale: [1, .4, 1], outline: false, parent: pg });
  // турник
  for (const sx of [-.8, .8]) mesh(new THREE.CylinderGeometry(.05, .05, 2.2, 6), pipeM, { pos: [5.5 + sx, 1.1, 3.4], outline: .006, parent: pg });
  mesh(new THREE.CylinderGeometry(.03, .03, 1.6, 6), toon(0xc9ced6), { pos: [5.5, 2.15, 3.4], rot: [0, 0, Math.PI / 2], outline: .004, parent: pg });
  // верёвка с бельём
  for (const x of [26, 34]) mesh(new THREE.CylinderGeometry(.04, .04, 2.4, 6), toon(0x7a7a7a), { pos: [x, 1.2, 5.8], outline: .006, parent: scene });
  mesh(new THREE.CylinderGeometry(.008, .008, 8, 4), toon(0xdddddd), { pos: [30, 2.25, 5.8], rot: [0, 0, Math.PI / 2], outline: false, parent: scene });
  for (let i = 0; i < 6; i++) mesh(new THREE.PlaneGeometry(.6 + (i % 2) * .3, .7), toon([0xffffff, 0x5a9ae8, 0xe85a5a, 0xf2c94c, 0xffffff, 0x9fc0a0][i], { side: THREE.DoubleSide }), { pos: [26.8 + i * 1.2, 1.88, 5.8], outline: false, parent: scene });
  // мусорные контейнеры
  for (let i = 0; i < 3; i++) mesh(rb(1.2, 1.1, 1.0), toon(0x3a6a4a), { pos: [38 + i * 1.4, .55, 4.5], outline: .012, parent: scene });
  // машины у дома (без фар днём)
  [[-28, 0], [-10.5, 1], [10.5, 3], [24.5, 4]].forEach(([x, i]) => { const c = makeCar(i + 2); c.position.set(x, 0, 3.4); c.rotation.y = Math.PI / 2 * (i % 2 ? 1 : -1); c.scale.setScalar(.95); c.traverse(o => { if (o.userData.lamp) o.visible = false; }); scene.add(c); });

  /* улица: фонари, остановка «42», дом напротив с магазином */
  for (let x = -54; x <= 54; x += 18) {
    const l = new THREE.Group(); l.position.set(x, 0, 16.6); scene.add(l);
    mesh(new THREE.CylinderGeometry(.08, .12, 6.4, 8), toon(0x4a4f58), { pos: [0, 3.2, 0], outline: .01, parent: l });
    mesh(new THREE.CylinderGeometry(.05, .05, 1.8, 6), toon(0x4a4f58), { pos: [0, 6.3, .8], rot: [Math.PI / 2 - .2, 0, 0], outline: .008, parent: l });
    mesh(rb(.35, .14, .7), toon(0x3a3f48), { pos: [0, 6.45, 1.6], outline: .008, parent: l });
    const h = mesh(new THREE.BoxGeometry(.28, .04, .6), glow(0xffd9a0, .3), { pos: [0, 6.37, 1.6], outline: false, parent: l }); Z.lamps.push(h);
  }
  const stop = new THREE.Group(); stop.position.set(22, 0, 18.2); scene.add(stop); Z.busStop = stop;
  mesh(new THREE.BoxGeometry(4.4, .12, 1.7), toon(0x2f5f8a), { pos: [0, 2.5, 0], outline: .015, parent: stop });
  mesh(new THREE.BoxGeometry(4.2, 2.2, .04), new THREE.MeshBasicMaterial({ color: 0xbfe0f0, transparent: true, opacity: .3, depthWrite: false }), { pos: [0, 1.35, -.75], outline: false, parent: stop });
  for (const sx of [-2.1, 2.1]) mesh(new THREE.BoxGeometry(.08, 2.5, .08), toon(0x3a3f48), { pos: [sx, 1.25, -.75], outline: .006, parent: stop });
  mesh(rb(2.6, .06, .4), toon(0x8a5a36), { pos: [-.4, .5, -.45], outline: .006, parent: stop });
  const adT = tex(256, 384, (g, w, h) => { const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#0f2a4a'); gr.addColorStop(1, '#0a1626'); g.fillStyle = gr; g.fillRect(0, 0, w, h);
    g.fillStyle = '#ffd23d'; g.font = '900 30px Unbounded'; g.textAlign = 'center'; g.fillText('ГАРРИЕВ', w / 2, 60); g.fillText('ГРУПП', w / 2, 96);
    g.fillStyle = '#7ff8ff'; g.fillRect(w / 2 - 18, 130, 36, 170); g.beginPath(); g.moveTo(w / 2 - 18, 130); g.lineTo(w / 2, 110); g.lineTo(w / 2 + 18, 130); g.fill();
    g.fillStyle = '#fff'; g.font = '600 20px Rubik'; g.fillText('Строим Новоград', w / 2, 336); g.fillText('будущего', w / 2, 360); });
  const ad = new THREE.Mesh(new THREE.PlaneGeometry(1.1, 1.65), new THREE.MeshBasicMaterial({ map: adT, color: new THREE.Color(1.2, 1.2, 1.2) })); ad.position.set(1.4, 1.4, -.72); stop.add(ad);
  const pole = new THREE.Group(); pole.position.set(2.8, 0, .6); stop.add(pole);
  mesh(new THREE.CylinderGeometry(.05, .05, 2.8, 6), toon(0x9a9aa0), { pos: [0, 1.4, 0], outline: .006, parent: pole });
  const s42 = textTexture('42', { size: 120, color: '#ffffff', bg: '#d8402c', font: 'Unbounded' });
  for (const r of [0, Math.PI]) { const p = new THREE.Mesh(new THREE.PlaneGeometry(.6, .6 / s42.aspect), new THREE.MeshBasicMaterial({ map: s42.tex })); p.position.set(0, 2.6, r ? -.03 : .03); p.rotation.y = r; pole.add(p); }
  const stN = textTexture('«СТАРЫЙ ЗАТОН»', { size: 60, color: '#1f2f4a', bg: '#f2f0e8', weight: 800, font: 'Rubik' });
  const stp = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 3.2 / stN.aspect), new THREE.MeshBasicMaterial({ map: stN.tex })); stp.position.set(0, 2.72, .86); stop.add(stp);
  Z.bus = makeBus(); Z.bus.visible = false; scene.add(Z.bus);
  // дом напротив (фасад на z = 34, смотрит в −z) с магазином
  const fac2 = panelFacade(26, [5, 12, 19], 31, { wall: '#d6c8b0', plinth: '#7a6a5a' });
  const wm2 = toon(0xffffff, { map: fac2.col, emissive: 0xffffff, emissiveMap: fac2.emi, emissiveIntensity: 0 }); Z.winMats.push(wm2);
  mesh(new THREE.BoxGeometry(78, 16, 12), toon(0xcdbfa8), { pos: [-6, 8, 40], outline: .06, parent: scene });
  const f2 = new THREE.Mesh(new THREE.PlaneGeometry(78, 16), wm2); f2.position.set(-6, 8, 33.985); f2.rotation.y = Math.PI; scene.add(f2);
  const shop = textTexture('ПРОДУКТЫ 24', { size: 90, color: '#ffffff', bg: '#2f8a4a', font: 'Unbounded' });
  const shp = new THREE.Mesh(new THREE.PlaneGeometry(6, 6 / shop.aspect), new THREE.MeshBasicMaterial({ map: shop.tex, color: new THREE.Color(1.2, 1.2, 1.2) })); shp.position.set(8, 3.4, 33.9); shp.rotation.y = Math.PI; scene.add(shp);
  mesh(new THREE.BoxGeometry(7, 2.2, .1), glow(0xfff1c8, .9), { pos: [8, 1.5, 33.92], outline: false, parent: scene });
  for (let i = 0; i < 5; i++) mesh(rb(.7, .5, .5), toon([0xf08a2a, 0xe0402a, 0x8ac040, 0xf2c63a, 0xf08a2a][i]), { pos: [5.6 + i * 1.2, .5, 33.4], outline: .008, parent: scene });   // ящики с фруктами

  /* апельсины Маржон и пакет (режиссура двигает) */
  Z.oranges = Array.from({ length: 7 }, (_, i) => {
    const o = mesh(new THREE.SphereGeometry(.055, 12, 10), toon(0xf08a1a), { outline: .004, parent: scene });
    mesh(new THREE.ConeGeometry(.015, .03, 5), toon(0x3a7a2a), { pos: [0, .055, 0], outline: false, parent: o });
    o.visible = false; return o;
  });
  const bag = Z.bag = new THREE.Group(); scene.add(bag); bag.visible = false;
  const bagT = tex(128, 160, (g, w, h) => { g.fillStyle = '#d9b884'; g.fillRect(0, 0, w, h); g.fillStyle = 'rgba(120,80,40,.25)'; for (let y = 0; y < h; y += 6) g.fillRect(0, y, w, 1);
    g.fillStyle = '#2f8a4a'; g.font = '900 22px Rubik'; g.textAlign = 'center'; g.fillText('ПРОДУКТЫ', w / 2, 70); g.fillText('24', w / 2, 96); });
  mesh(rb(.26, .3, .15, .02), toon(0xffffff, { map: bagT }), { pos: [0, -.21, 0], outline: .004, parent: bag });
  for (let i = 0; i < 3; i++) mesh(new THREE.SphereGeometry(.05, 10, 8), toon(0xf08a1a), { pos: [-.07 + i * .07, -.04, (i % 2) * .03 - .015], outline: .003, parent: bag });   // апельсины сверху
  mesh(new THREE.ConeGeometry(.03, .14, 6), toon(0x6aa83a), { pos: [.08, .0, .03], rot: [0, 0, -.3], outline: .003, parent: bag });                                      // лук-перо
  for (const sx of [-1, 1]) mesh(new THREE.TorusGeometry(.045, .008, 4, 10, Math.PI), toon(0xb8986a), { pos: [sx * .05, -.06, 0], outline: false, parent: bag });

  /* ---------- лицей «Новоград» (группа в 600, 0, 0) ---------- */
  const S = new THREE.Group(); S.position.set(600, 0, 0); scene.add(S); Z.school = S;
  const SX = 600;
  const schoolT = tex(64 * PX / 2, 13 * PX, (g, w, h) => {
    const k = .5;   // текстура в половину плотности
    g.fillStyle = '#e8c88a'; g.fillRect(0, 0, w, h);
    g.fillStyle = '#c8a46a'; g.fillRect(0, h - 1.2 * PX * k, w, 1.2 * PX * k);
    g.fillStyle = '#f4ead6'; for (const y of [4.6, 8.2]) g.fillRect(0, h - y * PX * k - 4, w, 8);
    g.fillRect(0, 0, w, .8 * PX * k);
    for (let i = 0; i < 20; i++) {
      const x0 = (i * 3.2 + .3) * PX * k;
      if (i >= 8 && i <= 11) continue;   // портик
      for (let f = 0; f < 3; f++) {
        const yb = h - (1.2 + f * 3.6 + .8) * PX * k, ww = 1.6 * PX * k, wh = 2.2 * PX * k, wx = x0 + .8 * PX * k;
        g.fillStyle = '#f4ead6'; g.fillRect(wx - 5, yb - wh - 5, ww + 10, wh + 10);
        g.fillStyle = '#3d5570'; g.fillRect(wx, yb - wh, ww, wh);
        g.fillStyle = 'rgba(255,255,255,.22)'; g.beginPath(); g.moveTo(wx, yb - wh); g.lineTo(wx + ww * .5, yb - wh); g.lineTo(wx, yb - wh * .5); g.fill();
        g.fillStyle = '#f4ead6'; g.fillRect(wx + ww / 2 - 2, yb - wh, 4, wh); g.fillRect(wx, yb - wh * .7, ww, 4);
        g.beginPath(); g.arc(wx + ww / 2, yb - wh, ww / 2 + 5, Math.PI, 0); g.fill(); g.fillStyle = '#3d5570'; g.beginPath(); g.arc(wx + ww / 2, yb - wh, ww / 2, Math.PI, 0); g.fill();
      }
    }
  });
  mesh(new THREE.BoxGeometry(64, 13, 16), toon(0xe0c088), { pos: [0, 6.5, -8], outline: .06, parent: S });
  mesh(new THREE.PlaneGeometry(64, 13), toon(0xffffff, { map: schoolT }), { pos: [0, 6.5, .015], outline: false, parent: S });
  mesh(new THREE.BoxGeometry(65, .5, 17), toon(0xf4ead6), { pos: [0, 13.2, -8], outline: .03, parent: S });                // карниз
  mesh(new THREE.BoxGeometry(64.4, 2.4, 16.4), toon(0x8a4a3a), { pos: [0, 14.6, -8.2], scale: [1, 1, 1], outline: .03, parent: S });   // кровля
  // портик: колонны, фронтон, ступени, двери, надпись
  mesh(new THREE.BoxGeometry(14, 13.4, 3), toon(0xf0dcae), { pos: [0, 6.7, 1.0], outline: .04, parent: S });
  for (const x of [-5.4, -1.8, 1.8, 5.4]) {
    mesh(new THREE.CylinderGeometry(.42, .48, 8.6, 18), toon(0xf8f2e4), { pos: [x, 5.6, 3.2], outline: .02, parent: S });
    mesh(new THREE.BoxGeometry(1.2, .4, 1.2), toon(0xf8f2e4), { pos: [x, 10.1, 3.2], outline: .01, parent: S });
    mesh(new THREE.BoxGeometry(1.2, .4, 1.2), toon(0xf8f2e4), { pos: [x, 1.3, 3.2], outline: .01, parent: S });
  }
  mesh(new THREE.BoxGeometry(14, .9, 4.6), toon(0xf8f2e4), { pos: [0, 10.75, 2.3], outline: .02, parent: S });
  const ped = mesh(new THREE.CylinderGeometry(4.3, 4.3, 4.4, 3, 1), toon(0xf0dcae), { pos: [0, 12.2, 2.3], rot: [Math.PI / 2, 0, Math.PI / 2], scale: [1, 1, .45], outline: .03, parent: S });
  for (let i = 0; i < 4; i++) mesh(new THREE.BoxGeometry(15 - i * .6, .28, 6.2 - i * .9), toon(0xc9c0b0), { pos: [0, .14 + i * .28, 4.4 - i * .45], outline: .01, parent: S });
  mesh(new THREE.BoxGeometry(3.2, 3.6, .2), toon(0x6a3a22), { pos: [0, 2.9, 2.55], outline: .02, parent: S });
  mesh(new THREE.BoxGeometry(.06, 3.4, .25), toon(0x3a2012), { pos: [0, 2.9, 2.6], outline: false, parent: S });
  for (const sx of [-.3, .3]) mesh(new THREE.BoxGeometry(.06, .5, .06), toon(0xd8b04a), { pos: [sx, 2.8, 2.7], outline: false, parent: S });
  const nm = textTexture('ЛИЦЕЙ «НОВОГРАД»', { size: 110, color: '#1f3a5a', font: 'Unbounded' });
  const nmp = new THREE.Mesh(new THREE.PlaneGeometry(11, 11 / nm.aspect), new THREE.MeshBasicMaterial({ map: nm.tex, transparent: true })); nmp.position.set(0, 10.75, 4.62); S.add(nmp);
  const clT = tex(128, 128, (g) => { g.fillStyle = '#fff'; g.beginPath(); g.arc(64, 64, 60, 0, 7); g.fill(); g.strokeStyle = '#1f3a5a'; g.lineWidth = 6; g.stroke(); g.lineWidth = 7; g.beginPath(); g.moveTo(64, 64); g.lineTo(64, 22); g.moveTo(64, 64); g.lineTo(40, 76); g.stroke(); });
  const clk = new THREE.Mesh(new THREE.CircleGeometry(.75, 32), new THREE.MeshBasicMaterial({ map: clT })); clk.position.set(0, 12.6, 3.3); S.add(clk);
  // флаги на флагштоках
  for (const x of [-13.5, -11.5, -9.5]) {
    mesh(new THREE.CylinderGeometry(.05, .07, 9, 8), toon(0xc9ced6), { pos: [x, 4.5, 10], outline: .006, parent: S });
    mesh(new THREE.SphereGeometry(.1, 8, 6), toon(0xd8b04a), { pos: [x, 9.05, 10], outline: false, parent: S });
    const fg = new THREE.PlaneGeometry(1.8, 1.1, 12, 1); fg.translate(.9, 0, 0);
    const ftex = tex(128, 80, (g) => { if (x === -11.5) { g.fillStyle = '#1f6fb0'; g.fillRect(0, 0, 128, 27); g.fillStyle = '#fff'; g.fillRect(0, 27, 128, 26); g.fillStyle = '#2f9a4a'; g.fillRect(0, 53, 128, 27); g.fillStyle = '#d8402c'; g.fillRect(0, 26, 128, 2); g.fillRect(0, 52, 128, 2); }
      else { g.fillStyle = x < -12 ? '#1f3a5a' : '#d8402c'; g.fillRect(0, 0, 128, 80); g.fillStyle = '#ffd23d'; g.font = '900 30px Unbounded'; g.textAlign = 'center'; g.fillText('ЛН', 64, 52); } });
    const f = new THREE.Mesh(fg, toon(0xffffff, { map: ftex, side: THREE.DoubleSide })); f.position.set(x, 8.35, 10); S.add(f); Z.flags.push({ f, base: fg.attributes.position.array.slice() });
  }
  // площадь, клумбы, деревья, велопарковка
  const pav = tileT.clone(); pav.needsUpdate = true; pav.repeat.set(30, 8);
  mesh(new THREE.PlaneGeometry(80, 16), toon(0xffffff, { map: pav }), { pos: [0, .012, 8], rot: [-Math.PI / 2, 0, 0], outline: false, parent: S });
  for (const sx of [-1, 1]) {
    mesh(new THREE.CylinderGeometry(2.2, 2.3, .4, 24), toon(0x9a8a7a), { pos: [sx * 17, .2, 9], outline: .015, parent: S });
    mesh(new THREE.CylinderGeometry(2.0, 2.0, .42, 24), toon(0x5a3a22), { pos: [sx * 17, .21, 9], outline: false, parent: S });
    for (let i = 0; i < 14; i++) mesh(new THREE.SphereGeometry(.22, 8, 6), toon([0xe85a5a, 0xf2c94c, 0xf08a2a, 0xffffff][i % 4]), { pos: [sx * 17 + Math.cos(i * .45) * 1.5 * (i % 2 ? .5 : 1), .5, 9 + Math.sin(i * .45) * 1.5 * (i % 2 ? .5 : 1)], outline: .005, parent: S });
    for (const tz of [4, 12]) tree(S, sx * 22, tz, 1.1, 300 + tz + sx, tz === 4);
  }
  for (let i = 0; i < 6; i++) mesh(new THREE.TorusGeometry(.35, .03, 6, 16, Math.PI), toon(0x9aa0a8), { pos: [-30 + i * .7, 0, 6], rot: [0, Math.PI / 2, 0], outline: false, parent: S });
  // ограда с воротами (z = 16), калитка открыта
  const fenceM = toon(0x2a3a4a);
  const bars = new THREE.InstancedMesh(new THREE.BoxGeometry(.04, 1.8, .04), fenceM, 400); let bi = 0;
  for (let x = -40; x <= 40; x += .22) { if (Math.abs(x) < 4.2) continue; dm.position.set(x, .9, 16); dm.rotation.set(0, 0, 0); dm.scale.set(1, 1, 1); dm.updateMatrix(); if (bi < 400) bars.setMatrixAt(bi++, dm.matrix); }
  bars.count = bi; S.add(bars);
  for (const sx of [-1, 1]) {
    for (const y of [.25, 1.7]) mesh(new THREE.BoxGeometry(36, .06, .06), fenceM, { pos: [sx * 22.1, y, 16], outline: false, parent: S });
    mesh(new THREE.BoxGeometry(.8, 2.6, .8), toon(0x9a4a3a), { pos: [sx * 4.6, 1.3, 16], outline: .015, parent: S });
    mesh(new THREE.BoxGeometry(1.0, .2, 1.0), toon(0xf4ead6), { pos: [sx * 4.6, 2.7, 16], outline: .01, parent: S });
    mesh(new THREE.SphereGeometry(.22, 10, 8), toon(0xf4ead6), { pos: [sx * 4.6, 2.95, 16], outline: .006, parent: S });
    const gate = new THREE.Group(); gate.position.set(sx * 4.2, 0, 16); gate.rotation.y = sx * 1.3; S.add(gate);
    for (let i = 0; i < 16; i++) mesh(new THREE.BoxGeometry(.04, 1.8, .04), fenceM, { pos: [-sx * (.12 + i * .23), .95, 0], outline: false, parent: gate });
    for (const y of [.25, 1.7]) mesh(new THREE.BoxGeometry(3.7, .06, .06), fenceM, { pos: [-sx * 1.85, y, 0], outline: false, parent: gate });
  }
  // дорога перед лицеем — общая (тротуар z 16…19.5, дорога 19.5…27); машины родителей
  [[-18, 5], [-10, 6], [14, 7]].forEach(([x, i]) => { const c = makeCar(i); c.position.set(SX + x, 0, 21.5); c.rotation.y = Math.PI / 2; c.traverse(o => { if (o.userData.lamp) o.visible = false; }); scene.add(c); });
  for (const tx of [-34, -26, 26, 34]) tree(scene, SX + tx, 30, 1.1, 400 + tx, tx > 0);

  /* жизнь двора: голуби (вспархивают, когда рядом пробегают — Z.scareAt), стая птиц в небе, листопад */
  const pigM = toon(0x8a92a4), pigD = toon(0x4a5060), neckM = toon(0x4a7a6a), beakM = toon(0xd8b07a);
  Z.pigeons = [[-1.8, 8.2], [-1.2, 8.9], [-.4, 8.1], [.4, 9.2], [1.1, 8.4], [-2.4, 9.4], [2.2, 9.0], [-22, 13.5], [-21.3, 14.1]].map(([x, z], i) => {
    const g = new THREE.Group(); g.position.set(x, 0, z); g.rotation.y = i * 1.7; scene.add(g);
    const body = new THREE.Group(); g.add(body);
    mesh(new THREE.SphereGeometry(.09, 12, 8), pigM, { pos: [0, .12, 0], scale: [.8, .75, 1.25], outline: .004, parent: body });
    const head = new THREE.Group(); head.position.set(0, .2, .09); body.add(head);
    mesh(new THREE.SphereGeometry(.045, 10, 8), pigD, { outline: .003, parent: head });
    mesh(new THREE.SphereGeometry(.05, 10, 8), neckM, { pos: [0, -.04, -.02], scale: [1, .8, 1], outline: false, parent: head });
    mesh(new THREE.ConeGeometry(.012, .035, 6), beakM, { pos: [0, -.005, .05], rot: [Math.PI / 2, 0, 0], outline: false, parent: head });
    mesh(new THREE.BoxGeometry(.09, .015, .1), pigD, { pos: [0, .12, -.15], rot: [-.25, 0, 0], outline: .003, parent: body });
    const wings = [-1, 1].map(sx => { const w = new THREE.Group(); w.position.set(sx * .06, .15, 0); body.add(w);
      mesh(new THREE.BoxGeometry(.16, .012, .1), pigM, { pos: [sx * .08, 0, -.01], outline: .003, parent: w }); return w; });
    for (const sx of [-1, 1]) mesh(new THREE.CylinderGeometry(.006, .006, .06, 4), beakM, { pos: [sx * .025, .03, 0], outline: false, parent: body });
    return { g, body, head, wings, x, z, i, ph: i * 1.37 };
  });
  Z.scareAt = null;
  const birdM = new THREE.MeshBasicMaterial({ color: 0x2a2630, side: THREE.DoubleSide, fog: false });
  Z.birds = Array.from({ length: 7 }, (_, i) => {
    const g = new THREE.Group(); scene.add(g);
    const wings = [-1, 1].map(sx => { const w = new THREE.Group(); g.add(w); const m = new THREE.Mesh(new THREE.PlaneGeometry(1.1, .32), birdM); m.position.x = sx * .55; m.rotation.x = -Math.PI / 2; w.add(m); return w; });
    return { g, wings, i };
  });
  const LEAF_N = 140;
  const fallLeaves = [0, 1].map(j => { const im = new THREE.InstancedMesh(new THREE.PlaneGeometry(.11, .08), toon(0xffffff, { side: THREE.DoubleSide }), LEAF_N); im.frustumCulled = false;
    for (let i = 0; i < LEAF_N; i++) im.setColorAt(i, lc.set([0xe0802a, 0xf2c63a, 0xb8462a, 0xd09a30][i % 4])); scene.add(im); return im; });
  const LC = [[0, 9], [600, 12]];

  /* свет */
  const hemi = new THREE.HemisphereLight(0xdde9ff, 0x8a7a60, 1.45); scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xfff0d4, 2.5); scene.add(sun, sun.target); Z.sun = sun; scene.userData.sun = sun;
  Z.sunDir = new THREE.Vector3(.45, .62, .64).normalize();

  /* время суток: setTime(a) или setTime(a, b, k) — смесь двух пресетов */
  const C = (a, b, k, key) => new THREE.Color(a[key]).lerp(new THREE.Color(b[key]), k);
  Z.setTime = (a, b = a, k = 0) => {
    const A = TIMES[a], B = TIMES[b];
    const u = sky.material.uniforms;
    u.top.value.copy(C(A, B, k, 'top')); u.hor.value.copy(C(A, B, k, 'hor')); u.low.value.copy(C(A, B, k, 'low')); u.sunCol.value.copy(C(A, B, k, 'sun'));
    Z.sunDir.set(...A.dir.map((v, i) => v + (B.dir[i] - v) * k)).normalize(); u.sunDir.value.copy(Z.sunDir);
    sun.color.copy(C(A, B, k, 'sun')); sun.intensity = A.sunI + (B.sunI - A.sunI) * k;
    hemi.color.copy(C(A, B, k, 'hs')); hemi.groundColor.copy(C(A, B, k, 'hg')); hemi.intensity = A.hI + (B.hI - A.hI) * k;
    const fog = C(A, B, k, 'fog'); scene.fog.color.copy(fog); scene.background.copy(fog);
    ringCol.copy(fog).lerp(C(A, B, k, 'top'), .35); ring.material.color.copy(ringCol);
    const win = A.win + (B.win - A.win) * k; Z.winMats.forEach(m => m.emissiveIntensity = win);
    const lamp = A.lamp + (B.lamp - A.lamp) * k; Z.lamps.forEach(l => l.material.color.setRGB(1, .85, .63).multiplyScalar(.3 + lamp * 3));
    u.cloudK.value = A.cloud + (B.cloud - A.cloud) * k;
    Z.time = { a, b, k };
  };
  Z.setTime('morning');
  // солнце светит из своего направления в точку, куда смотрит камера (тени — на видеокарте)
  Z.aim = focus => { sun.position.copy(focus).addScaledVector(Z.sunDir, 60); sun.target.position.copy(focus); };
  Z.aim(new THREE.Vector3(0, 0, 6)); scene.userData.aim = Z.aim;

  Z.update = (t, active) => {
    if (!active) { Z.scareAt = null; return; }
    sky.material.uniforms.time.value = t;
    // голуби клюют, при испуге — взлетают
    for (const p of Z.pigeons) {
      const fly = Z.scareAt != null ? Math.max(0, t - Z.scareAt - p.i * .06) : 0;
      const peck = Math.max(0, Math.sin(t * 3.1 + p.ph * 2)) ** 3;
      if (fly > 0) {
        const dir = new THREE.Vector3(Math.sin(p.ph * 3), 0, -Math.abs(Math.cos(p.ph * 3)) - .3).normalize();
        p.g.position.set(p.x + dir.x * fly * 4, Math.min(fly * fly * 3 + fly * 2, 30), p.z + dir.z * fly * 4);
        p.g.rotation.y = Math.atan2(dir.x, dir.z); p.body.rotation.x = -.5;
        p.wings.forEach((w, k) => w.rotation.z = (k ? -1 : 1) * Math.sin(t * 40 + p.i) * .9);
      } else {
        const hop = Math.floor((t * .35 + p.ph) % 4);
        p.g.position.set(p.x + Math.sin(hop * 2.1 + p.ph) * .15, 0, p.z + Math.cos(hop * 1.7 + p.ph) * .15);
        p.g.rotation.y = p.i * 1.7 + hop * .9; p.body.rotation.x = 0;
        p.head.rotation.x = .9 * peck; p.head.position.z = .09 + .03 * peck;
        p.wings.forEach(w => w.rotation.z = 0);
      }
    }
    // стая в небе
    for (const b of Z.birds) {
      const k = ((t * 3 + b.i * 1.4) % 260) - 130;
      b.g.position.set(k + (b.i % 3) * 3, 46 + (b.i % 4) * 2.5 + Math.sin(t * .7 + b.i) * 1.2, -70 - (b.i % 3) * 6 - b.i * 2);
      b.g.rotation.y = Math.PI / 2;
      b.wings.forEach((w, s) => w.rotation.z = (s ? -1 : 1) * Math.sin(t * 9 + b.i) * .5);
    }
    // листопад
    fallLeaves.forEach((im, j) => {
      const [cx, cz] = LC[j];
      for (let i = 0; i < LEAF_N; i++) {
        const h = ((i * 7919) % 1000) / 1000, h2 = ((i * 104729) % 1000) / 1000, sp = .45 + h2 * .35;
        const y = 9 - ((t * sp + h * 9) % 9);
        dm.position.set(cx + (h - .5) * 46 + Math.sin(t * 1.3 + i) * .6, y, cz + (h2 - .5) * 22 + Math.cos(t * 1.1 + i * 2) * .5);
        dm.rotation.set(t * 2.1 + i, t * 1.7 + h * 6, t * 1.3); dm.scale.setScalar(1); dm.updateMatrix(); im.setMatrixAt(i, dm.matrix);
      }
      im.instanceMatrix.needsUpdate = true;
    });
    Z.swings.forEach((s, i) => s.rotation.x = Math.sin(t * 1.9 + i * 2) * (i ? .08 : .35));
    for (const { f, base } of Z.flags) {
      const p = f.geometry.attributes.position;
      for (let i = 0; i < p.count; i++) { const x = base[i * 3]; p.array[i * 3 + 2] = Math.sin(x * 3.2 - t * 6 + f.position.x) * .14 * (x / 1.8); }
      p.needsUpdate = true;
    }
    Z.scareAt = null;
  };
  return Z;
}
