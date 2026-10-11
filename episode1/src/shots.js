// Режиссура: каждый кадр (шот) серии — функция от локального времени.
// Персонажи, камера и эффекты выставляются заново для каждого кадра — рендер детерминирован.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { E, P, kf, tw, lerp, clamp, shake, pulse, toon, glow, mesh, W, H, noise } from './core.js';
import { POSE, seq, blend, blinkAt, gait, squash, springAt, secondary, ikArm } from './rig.js';
import { updateTraffic, makeCar } from './city.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const L2W = (x, y, z) => [40 + x, 258.82 + y, -440 + z];          // координаты лаборатории → мир
const yawTo = (a, b) => Math.atan2(b[0] - a[0], b[2] - a[2]);
const TMP = new THREE.Vector3(), TMP2 = new THREE.Vector3();

/* ---------- кабина автобуса для окна звонка ---------- */
export function makeCab() {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0b1020);
  const c = document.createElement('canvas'); c.width = 1024; c.height = 256;
  const g = c.getContext('2d'); g.fillStyle = '#0a0d1c'; g.fillRect(0, 0, 1024, 256);
  for (let i = 0; i < 90; i++) { g.fillStyle = ['#ffc070', '#80c8ff', '#ff6a8a', '#fff'][i % 4]; g.globalAlpha = .7; g.fillRect((i * 97) % 1024, 40 + (i * 53) % 170, 30 + (i % 5) * 20, 4); }
  const tex = new THREE.CanvasTexture(c); tex.wrapS = THREE.RepeatWrapping; tex.colorSpace = THREE.SRGBColorSpace;
  const win = new THREE.Mesh(new THREE.PlaneGeometry(6, 1.6), new THREE.MeshBasicMaterial({ map: tex, color: new THREE.Color(1.4, 1.4, 1.4) }));
  win.position.set(-.4, 1.7, -1.4); scene.add(win);
  mesh(new THREE.BoxGeometry(6, .2, .3), toon(0x30384a), { pos: [-.4, .85, -1.3], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(6, .8, .3), toon(0x1b2130), { pos: [-.4, .45, -1.3], outline: false, parent: scene });
  mesh(new RoundedBoxGeometry(.8, 1.0, .3, 2, .1), toon(0x334060), { pos: [0, .95, -.35], outline: .01, parent: scene });
  const wheel = mesh(new THREE.TorusGeometry(.26, .03, 8, 28), toon(0x111111), { pos: [0, 1.12, .52], rot: [-1.0, 0, 0], outline: .008, parent: scene });
  mesh(new THREE.BoxGeometry(1.2, .5, .5), toon(0x232a38), { pos: [0, .8, .95], outline: false, parent: scene });
  scene.add(new THREE.HemisphereLight(0xa0b4ff, 0x201820, 1.4));
  const dash = new THREE.PointLight(0x7feaff, 6, 4, 1.3); dash.position.set(.2, 1.3, 1.1); scene.add(dash);
  const warm = new THREE.PointLight(0xffb070, 4, 5, 1.5); warm.position.set(-.8, 1.9, .6); scene.add(warm);
  const cam = new THREE.PerspectiveCamera(34, 520 / 360, .05, 50);
  return { scene, cam, tex, wheel };
}

export function buildShots(C) {
  const { city, lab, kitchen, lair, cab, ch, props, camera: cam, U } = C;
  const { timur: TI, ded: DE, vera: VE, kronov: KR, shadow: SH } = ch;
  const S = city.scene;

  /* ---- помощники ---- */
  const look = (pos, at, fov = 45, roll = 0) => {
    cam.position.set(...pos); cam.up.set(0, 1, 0); cam.lookAt(...at);
    if (roll) cam.rotateZ(roll);
    cam.fov = fov; cam.updateProjectionMatrix();
  };
  const shk = (t, a, f = 9) => shake(t, a, f);
  const addv = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const place = (c, parent, pos, yaw = 0) => {
    parent.add(c.root); c.root.visible = true; c.root.position.set(...pos); c.root.rotation.set(0, yaw, 0);
  };
  const orient = (c, up, fwd) => {            // ориентация по «верху» и «взгляду»
    const u = up.clone().normalize(), f = fwd.clone().sub(u.clone().multiplyScalar(fwd.dot(u))).normalize();
    const r = new THREE.Vector3().crossVectors(u, f).normalize();
    c.root.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(r, u, f));
  };
  const face = (c, who, t, o = {}) => {
    const sd = o.seed ?? 0;
    // дыхание и «живые» микродвижения глаз
    c.J.chest.scale.set(1 + .008 * Math.sin(t * 2.1 + sd), 1 + .012 * Math.sin(t * 2.1 + sd), 1 + .018 * Math.sin(t * 2.1 + sd));
    c.setFace({ mouth: C.mouthOf(who, t) * (o.mk ?? 1), shape: C.shapeOf(who), fric: C.fricOf(who), blink: o.noBlink ? 0 : blinkAt(t, sd),
      look: [noise(t * .8 + sd * 7) * .35, noise(t * .7 + sd * 7 + 40) * .2], ...o });
    secondary(c, t, o.energy ?? .2);
  };
  /* «кадр удара»: вспышка на 1–2 кадра + толчок камеры (зум) — классический приём экшн-анимации */
  const impact = (t, t0, o = {}) => {
    const dt = t - t0;
    if (dt >= 0 && dt < .045) post(ov => ov.fill(o.color || '#ffffff', .75));
    else if (dt >= .045 && dt < .09) post(ov => ov.fill('#000000', .35));
    if (dt >= 0 && dt < .6) {
      const kick = Math.exp(-dt * 10);
      cam.fov *= 1 - (o.zoom ?? .12) * kick; cam.updateProjectionMatrix();
      const sh = shk(t, (o.shake ?? .12) * kick, 22); cam.position.x += sh[0]; cam.position.y += sh[1]; cam.position.z += sh[2];
    }
  };
  /* комикс-панель: второй ракурс поверх кадра (рисуется отдельной камерой) */
  const panelCams = [new THREE.PerspectiveCamera(30, 1, .05, 3000), new THREE.PerspectiveCamera(30, 1, .05, 3000)];
  const panel = (i, k, rect, scene, pos, at, fov = 30) => {
    if (k <= 0) return;
    const [x, y, w, h] = rect, s = E.outBack(clamp(k));
    const ws = Math.round(w * s), hs = Math.round(h * s), px = Math.round(x + (w - ws) / 2), py = Math.round(y + (h - hs) / 2);
    const pc = panelCams[i]; pc.position.set(...pos); pc.up.set(0, 1, 0); pc.lookAt(...at); pc.fov = fov;
    (C.panels = C.panels || []).push({ x: px, y: py, w: ws, h: hs, scene, cam: pc });
    post(o => o.panelFrame(px, py, ws, hs));
  };
  /* контровой свет за героем относительно камеры — силуэт отделяется от тёмного фона */
  const rimOn = (target, color = 0x9feaff, k = 2.4) => { C.rim = { target: V(...target), color, k }; };
  const handW = (c, s = 'R') => { c.root.updateMatrixWorld(true); return c.J['hand' + s].localToWorld(V(0, -.09 * c.d.k, 0)); };
  const headW = c => { c.root.updateMatrixWorld(true); return c.J.head.localToWorld(V(0, .16 * c.d.k, .1)); };
  const post = f => C.post.push(f);
  const fadeIn = (lt, d = .5, col = '#000') => post(o => o.fill(col, 1 - lt / d));
  const fadeOut = (lt, t1, d = .5, col = '#000') => post(o => o.fill(col, (lt - (t1 - d)) / d));
  const env = o => {                         // настройка ночного города
    city.key.intensity = o.key ?? 1.4; city.rim.intensity = o.rim ?? 1.2;
    if (o.rimPos) city.rim.position.set(...o.rimPos);
    if (o.fill) { city.fill.position.set(...o.fill[0]); city.fill.intensity = o.fill[1] * .2; city.fill.color.set(o.fill[2] ?? 0x55e6ff); }
  };
  const labLights = (k = 1, red = 0) => { lab.lights[0].intensity = 45 * k; lab.lights[1].intensity = 25 * k; lab.lights[2].intensity = 70 * red; };

  /* ---- велосипед ---- */
  const bikeZ = t => 182 - 13 * (t - 21);
  const rideBike = (t, x, z, o = {}) => {
    const b = props.bike; b.visible = true; b.position.set(x, o.y || 0, z); b.rotation.set(o.pitch || 0, Math.PI + (o.yaw || 0), o.lean || 0);
    b.userData.wheels.forEach(w => w.rotation.x = -t * 13 / .35);
    b.add(TI.root); TI.root.visible = true; TI.root.position.set(0, .2, -.02); TI.root.rotation.set(0, 0, 0);
    TI.pose(o.pose || POSE.bike(t));
    if (!o.freeHands) {                      // IK: ладони точно на ручках руля
      b.updateMatrixWorld(true);
      for (const [sd, sx] of [['L', 1], ['R', -1]]) if (!(o.freeL && sd === 'L')) ikArm(TI, sd, b.localToWorld(V(sx * .26, .92, .43)), b.localToWorld(V(sx * 1.5, .3, -.3)).sub(b.position));
    }
    const sq = o.squash || 0; if (sq) { b.scale.set(1 / Math.sqrt(1 + sq), 1 + sq, 1 / Math.sqrt(1 + sq)); } else b.scale.set(1, 1, 1);
  };
  const cabCall = (t, k) => {               // вставка «дед на связи»
    if (k <= 0) return;
    place(DE, cab.scene, [0, .05, -.1], 0);
    const p = POSE.sitChair(t); p.armL = [-1.1, .1, .1]; p.armR = [-1.1, .1, .1]; p.foreL = [-.5, 0, 0]; p.foreR = [-.5, 0, 0];
    p.head = [.05, -.25 + .08 * Math.sin(t * .7), 0];
    DE.pose(p); face(DE, 'ded', t, { brow: .35, seed: 2, look: [.6, 0] });
    cab.tex.offset.x = -t * .25;
    cab.wheel.rotation.z = Math.sin(t * .6) * .2;
    cab.cam.position.set(.55, 1.42, 1.35); cab.cam.lookAt(.02, 1.36, 0);
    const x = 1340, y = 60, w = 520, h = 360, s = E.outBack(clamp(k));
    const ws = Math.round(w * s), hs = Math.round(h * s);
    C.inset = { x: x + (w - ws) / 2 | 0, y: y + (h - hs) / 2 | 0, w: ws, h: hs, scene: cab.scene, cam: cab.cam };
    post(o => o.callFrame(x + (w - ws) / 2, y + (h - hs) / 2, ws, hs, 1, t));
  };

  /* ---- мост и автобус ---- */
  const BUS = { x: 455, z: -388.6 };
  const busState = (t, tilt, slide) => {
    const bp = props.busPivot; bp.visible = true; bp.position.set(BUS.x, 0, BUS.z + slide); bp.rotation.set(tilt, 0, 0);
    props.bus.userData.body.rotation.z = Math.sin(t * 2.3) * .01 * tilt * 5;
  };
  const busTilt = t => kf(t, [[120, .22], [154.6, .22], [155.6, .52, E.outQuad], [156.6, .62, E.outCubic], [171, .62], [174, 0, E.inOutCubic]]);
  const busSlide = t => kf(t, [[120, 0], [154.6, 0], [156.6, 2.6, E.outCubic], [171, 2.6], [174, -2.4, E.inOutCubic]]);
  const busRear = t => { props.busPivot.updateMatrixWorld(true); return props.bus.localToWorld(V(0, 1.6, -6)); };
  const wreck = [];                         // брошенные машины на мосту
  for (let i = 0; i < 3; i++) { const c = makeCar(i + 3); S.add(c); c.visible = false; wreck.push(c); }
  const fire = new THREE.PointLight(0xff7a2a, 0, 40, 1.4); S.add(fire);
  const flames = [];
  for (let i = 0; i < 10; i++) { const f = mesh(new THREE.SphereGeometry(.6, 10, 8), glow(i % 2 ? 0xff9a2a : 0xffd04a, 2.6, { transparent: true, opacity: .8 }), { outline: false, parent: S }); f.visible = false; flames.push(f); }
  const bridgeProps = t => {
    const pos = [[448.5, -406, .25, 0], [470, -394, -.8, 1], [492, -406, 2.4, 2]];
    wreck.forEach((c, i) => { c.visible = true; c.position.set(pos[i][0], 0, pos[i][1]); c.rotation.set(0, pos[i][2], i === 2 ? Math.PI : 0); if (i === 2) c.position.y = 2.1; });
    // машина подпрыгивает от удара Кронова
    const jd = t - 125.7; if (jd > 0) { const b = Math.max(0, Math.sin(jd * 9) * Math.exp(-jd * 4)); wreck[0].position.y = b * .9; wreck[0].rotation.z = b * .25; wreck[0].rotation.x = -b * .1; }
    fire.intensity = 300 + 120 * Math.sin(t * 17) * Math.sin(t * 5.3); fire.position.set(492, 3, -406);
    flames.forEach((f, i) => { const ph = (t * 1.3 + i * .37) % 1; f.visible = true; f.position.set(492 + Math.sin(i * 2.1) * 1.2, 2.4 + ph * 3.2, -406 + Math.cos(i * 1.7) * 1.0); f.scale.setScalar((1 - ph) * 1.4 + .2); });
  };
  const hideBridgeProps = () => { wreck.forEach(c => c.visible = false); flames.forEach(f => f.visible = false); fire.intensity = 0; };

  /* ---- траектория первого полёта ---- */
  const A1 = V(175, 96, -388), A2 = V(290, 84, -413);
  const swingPts = [[107.0, [136, 50, -404]], [108.2, [150, 34, -399]], [109.4, [175, 31, -396]], [110.6, [204, 44, -397]], [111.4, [222, 62, -399]],
    [112.2, [238, 66, -402]], [113.0, [252, 52, -404]], [113.8, [270, 40, -404]], [114.6, [290, 37, -402]], [115.4, [302, 54, -398]], [116.2, [306, 74, -390]], [116.6, [305.5, 74.6, -387]]];
  const swingCurve = new THREE.CatmullRomCurve3(swingPts.map(p => V(...p[1])), false, 'centripetal');
  const swingAt = t => {
    const ts = swingPts.map(p => p[0]);
    const tt = clamp(t, ts[0], ts[ts.length - 1]);
    let i = 0; while (i < ts.length - 2 && tt > ts[i + 1]) i++;
    const u = (i + (tt - ts[i]) / (ts[i + 1] - ts[i])) / (ts.length - 1);
    return swingCurve.getPoint(clamp(u));
  };
  const swingVel = t => swingAt(t + .05).sub(swingAt(t - .05)).multiplyScalar(10);

  /* ---- бой на мосту: позиции ---- */
  const TIp = t => kf(t, [[140.3, [310, 74, -386]], [141.3, [425, 0, -398], E.inQuad], [151.3, [425, 0, -398]], [151.9, [423, 0, -401], E.outCubic], [152.5, [426, 2.8, -400]],
    [153.3, [446, 0, -399], E.inOutQuad], [156.8, [448, 0, -401]], [157.2, [452, 0, -403], E.outCubic], [163.8, [452, 0, -403]], [164.4, [446, 6, -404], E.outQuad], [165.2, [430, 4, -404]], [165.8, [418, 0, -404], E.inQuad], [175, [418, 0, -404]]]);
  const KRp = t => kf(t, [[141, [440, 0, -399]], [143.6, [434, 0, -399], E.inOutSine], [151, [431, 0, -399]], [153.8, [431, 0, -399]], [154.4, [444, 0, -397], E.outCubic], [163, [444, 0, -397]],
    [164.4, [448, 0, -402], E.inQuad], [164.6, [448, 0, -402]], [165.6, [393.6, 1.5, -389.8], E.inOutQuad], [175, [393.6, 1.5, -389.8]]]);

  /* ======================= ШОТЫ ======================= */
  const shots = [];
  const shot = (t0, t1, run, o = {}) => shots.push({ t0, t1, run, ...o });

  /* ===== СЦЕНА 1. Пролог ===== */
  shot(0, 6, (lt, t) => {
    env({ key: .8 });
    const k = E.inOutSine(lt / 6);
    look([lerp(-330, -230, k), lerp(170, 140, k), lerp(320, 150, k)], [40, lerp(160, 190, k), -440], 42);
    post(o => o.fill('#000', 1 - clamp((lt - .45) / .5) * .9 - clamp((lt - 1.2) / 1.5) * .1));
    updateTraffic(city, t);
    return S;
  });
  shot(6, 11, (lt, t) => {
    env({});
    const k = E.inOutCubic(lt / 5);
    const p = [lerp(-30, 2, k), lerp(150, 26, k), lerp(330, 120, k)];
    look(addv(p, shk(t, .3, 1.5)), [lerp(20, 0, k), lerp(20, 12, k), lerp(-200, -150, k)], lerp(50, 62, k), lerp(-.25, .05, k));
    updateTraffic(city, t);
    return S;
  });
  shot(11, 16.5, (lt, t) => {
    env({});
    const k = E.inOutSine(lt / 5.5);
    const sh = t > 13.3 ? shk(t, .9 * Math.exp(-(t - 13.3) * 2.5), 14) : [0, 0, 0];
    look(addv([lerp(-4, 2, k), lerp(40, 90, k), lerp(-330, -372, k)], sh), [40, lerp(250, 330, k), -440], lerp(56, 44, k), -.06);
    updateTraffic(city, t);
    post(o => o.fill('#000', (lt - 5.1) / .4));
    return S;
  });
  /* заставка */
  shot(16.5, 21, (lt, t) => {
    look([0, 100, 200], [0, 100, 0], 45);
    post(o => o.logo(lt, { sub: 'СЕРИЯ 1 · УКУС МОЛНИИ' }));
    post(o => o.fill('#000', (lt - 4.1) / .4));
    return S;
  }, { noSubs: true, noFlash: true });

  /* ===== СЦЕНА 2. Опоздание ===== */
  shot(21, 26, (lt, t) => {
    env({ fill: [[4.5, 3, bikeZ(t) + 2], 0], rimPos: [40, 30, bikeZ(t) - 80] });
    const z = bikeZ(t), x = 4.5 + Math.sin(t * 1.3) * .4;
    rideBike(t, x, z, { lean: Math.sin(t * 1.3 + 1) * .08 });
    face(TI, 'timur', t, { brow: .2, look: [0, -.2], energy: 1 });
    const back = lerp(6.5, 4.2, E.inOutSine(lt / 5));
    look(addv([x - 1.2, 1.0, z - back], shk(t, .04, 3)), [x, 1.3, z], 50, .03);
    updateTraffic(city, t);
    fadeIn(lt, .4);
    post(o => o.comic('ДЗЫНЬ!', 1500, 260, lt - .5, { size: .55, rot: .12, color: '#7ff8ff', dur: 1.0 }));
    return S;
  });
  shot(26, 33, (lt, t) => {
    env({});
    const z = bikeZ(t), x = 4.5 + Math.sin(t * 1.3) * .4;
    const p = POSE.bike(t); p.head = [-.35, .5, 0];           // слушает звонок, смотрит в камеру
    rideBike(t, x, z, { pose: p, lean: Math.sin(t * 1.3 + 1) * .06 });
    face(TI, 'timur', t, { brow: .45, look: [.3, 0], energy: .8 });
    look(addv([x - 3.6, 1.2, z - 1.4], shk(t, .03, 3)), [x, 1.15, z - .3], 40);
    updateTraffic(city, t);
    cabCall(t, clamp((lt - .1) / .3) - clamp((lt - 6.6) / .3));
    return S;
  });
  shot(33, 38, (lt, t) => {
    env({});
    // слоу-мо прыжка через такси
    const wt = t < 34.7 ? t : t < 35.5 ? 34.7 + (t - 34.7) * .3 : 34.94 + (t - 35.5);
    const z = bikeZ(wt), x = 4.5;
    const j = clamp((wt - 34.3) / 1.0);
    const y = Math.sin(j * Math.PI) * 2.3;
    const pitch = j > 0 && j < 1 ? -Math.cos(j * Math.PI) * .35 : 0;
    // присед перед прыжком → вытягивание в отрыве → сплющивание при приземлении
    const crouch = pulse(wt, 33.95, 34.32, .3, .05);
    const pBase = j > 0 && j < 1 ? POSE.bikeStand() : POSE.bike(wt);
    const p = crouch > 0 ? blend(pBase, { ...POSE.bike(wt), hy: -.32, spine: [.8, 0, 0], head: [-.7, 0, 0] }, crouch) : pBase;
    const sq = -.12 * crouch + .14 * pulse(wt, 34.3, 34.75, .05, .3) + springAt(wt, 35.3, -.2, 16, 8);
    rideBike(wt, x, z, { y, pitch, pose: p, squash: sq });
    face(TI, 'timur', t, { brow: .3, wide: j > 0 && j < 1, energy: 1 });
    // такси выезжает поперёк
    const taxi = city.cars[1].g; taxi.visible = true;
    const tx = kf(t, [[33, -40], [34.4, 3.0, E.outCubic], [40, 3.0]]);
    taxi.position.set(tx, 0, 0); taxi.rotation.set(0, Math.PI / 2, 0);
    const k = E.inOutSine(clamp((t - 33) / 5));
    const a = lerp(-2.4, -.6, k);
    const cp = [x + Math.cos(a) * 5, 1.0 + y * .5, z + Math.sin(a) * 5 - 1.5];
    updateTraffic(city, t, -380, 240, (c, i) => i !== 1 && Math.hypot(c.g.position.x - cp[0], c.g.position.z - cp[2]) > 0);
    city.cars.forEach((c, i) => { if (i !== 1 && Math.abs(c.g.position.z - cp[2]) < 14) c.g.visible = false; });
    taxi.visible = true;
    look(addv(cp, shk(t, .03, 4)), [x, 1 + y * .7, z - 1], lerp(50, 40, k));
    post(o => o.comic('БИ-БИП!', 520, 330, t - 34.2, { size: .6, color: '#ffe23d', rot: -.1, dur: 1.0 }));
    post(o => o.speedLines(pulse(t, 34.5, 35.9, .1, .3) * .8, t));
    // комикс-панель: крупно лицо Тимура над такси
    const hp = headW(TI);
    panel(0, pulse(t, 34.55, 35.6, .12, .12) * 1.01, [1260, 90, 560, 330], S, hp.clone().add(V(-1.0, .15, -1.25)).toArray(), hp.toArray(), 28);
    return S;
  });
  shot(38, 44, (lt, t) => {
    env({ fill: [[6, 2.5, bikeZ(t) - 3], 20, 0xffb070] });
    const z = bikeZ(t), x = 4.5;
    const p = POSE.bike(t);
    const touch = pulse(t, 39.2, 42.8, .5, .5);
    p.armL = [lerp(-1.12, -.6, touch), lerp(0, -.5, touch), lerp(.2, .1, touch)]; p.foreL = [lerp(-.35, -2.0, touch), 0, 0];
    p.head = [-.25 - .2 * touch, 0, 0];
    rideBike(t, x, z, { pose: p, freeL: touch > .05 });
    face(TI, 'timur', t, { brow: lerp(.2, -.05, touch), smile: t > 41.8 ? .8 : .2, look: [0, -.5 * touch], energy: .6 });
    const k = E.inOutSine(lt / 6);
    look(addv([x - .2, 1.55, z - lerp(2.2, 1.5, k)], shk(t, .02, 3)), [x, lerp(1.3, 1.25, k), z], lerp(42, 32, k));
    updateTraffic(city, t);
    cabCall(t, clamp((lt - .1) / .3) - clamp((lt - 3.7) / .3));
    fadeOut(lt, 6, .25);
    return S;
  });

  /* ===== СЦЕНА 3. Лаборатория ===== */
  shot(44, 48, (lt, t) => {
    env({ fill: [[12, 3, -404], 50, 0x7feaff] });
    const k = E.inOutCubic(lt / 4);
    const bz = kf(t, [[44, -360], [45.3, -404, E.outCubic]]);
    rideBike(t * (t < 45.3 ? 1 : 0), 6, bz, { pose: t < 45.3 ? POSE.bike(t) : POSE.bikeStand(), yaw: t > 44.8 ? .5 * E.outCubic(P(t, 44.8, .5)) : 0, lean: t > 44.8 ? -.15 : 0 });
    if (t > 45.8) {                            // слез и бежит ко входу
      const tp = kf(t, [[45.8, [7, 0, -405]], [48, [14, 0, -412], E.inQuad]]);
      props.bike.remove(TI.root); place(TI, S, tp, 2.2);
      const dist = Math.hypot(tp[0] - 7, tp[2] + 405);       // фаза бега по пройденному пути — ноги не скользят
      TI.pose(seq(t - 45.8, [[0, POSE.stand(t)], [.5, () => POSE.run(gait(dist, 1.1, 1.6), 1.6)]]));
      squash(TI, springAt(t, 45.85, -.12, 14, 8));
    }
    face(TI, 'timur', t, { brow: .3 });
    look([lerp(-2, 0, k), lerp(1.2, .8, k), -392], [lerp(8, 40, k), lerp(4, 320, k), lerp(-405, -440, k)], lerp(55, 60, k));
    if (t > 45.4) post(o => o.comic('ВЖ-Ж-Ж!', 1300, 820, t - 45.1, { size: .45, color: '#fff', rot: .1, burst: false, dur: .8 }));
    updateTraffic(city, t);
    fadeIn(lt, .3);
    return S;
  });
  // лифт открывается, Тимур с посылкой, Вера у главной капсулы
  const labBase = (t, o = {}) => {
    city.rain.visible = false;
    env({ key: .35, rim: .5 });
    labLights(o.lights ?? 1, o.red ?? 0);
    lab.capsules.forEach((c, i) => { c.spider.userData.anim(t + i, 0, .2); c.spider.position.y = 2.1 + Math.sin(t * 1.5 + i) * .12; c.spider.rotation.y = Math.sin(t * .4 + i) * .6; c.glass.visible = true; c.liquid.visible = true; c.spider.visible = true; });
    lab.doors.forEach((d, i) => { d.visible = true; d.position.set((i ? 1 : -1) * (1.6 + 3 * E.inOutCubic(P(t, 48, .8))), 3.5, 12.75); d.rotation.set(0, 0, 0); });
    lab.core.visible = true;
  };
  const box = mesh(new RoundedBoxGeometry(.42, .3, .32, 2, .03), toon(0xc9a06a), { outline: .01 });
  mesh(new THREE.BoxGeometry(.44, .05, .1), toon(0x15b9a8), { pos: [0, .13, 0], outline: false, parent: box });
  // клубы дыма (спрайты) для выбитых дверей
  const smokeTex = (() => { const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
    const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64); gr.addColorStop(0, 'rgba(120,110,105,.9)'); gr.addColorStop(1, 'rgba(120,110,105,0)'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
    return new THREE.CanvasTexture(c); })();
  const smoke = Array.from({ length: 9 }, () => { const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: smokeTex, transparent: true, depthWrite: false })); sp.visible = false; S.add(sp); return sp; });
  const holdBox = c => { c.J.handL.add(box); box.visible = true; box.position.set(-.12, -.1, .02); box.rotation.set(0, 0, 0); };
  shot(48, 56, (lt, t) => {
    labBase(t);
    const tp = kf(t, [[48.6, [0, 0, 11]], [51.5, [0, 0, 3], E.inOutSine], [56, [0, 0, 1.5]]]);
    place(TI, lab.group, tp, Math.PI + (t > 53.4 ? Math.sin((t - 53.4) * 1.4) * .7 : 0));
    const p = t < 51.5 ? POSE.walk(gait(11 - tp[2], .62, .9)) : POSE.stand(t); p.armL = [-.35, .35, .1]; p.foreL = [-1.45, 0, 0]; p.armR = [-.35, .35, .1]; p.foreR = [-1.45, 0, 0]; p.grip = .6;
    if (t > 53.4) { p.head = [-.25, .3 * Math.sin((t - 53.4) * 1.1), 0]; }
    TI.pose(p); holdBox(TI);
    face(TI, 'timur', t, { brow: .55, wide: t > 53.4, mouth: C.mouthOf('timur', t) });
    const turn = E.outBack(P(t, 48.6, .8));                 // разворот с лёгким перелётом
    place(VE, lab.group, [2.4, 0, -6.8], lerp(Math.PI * .9, 0, turn));
    VE.pose(seq(t - 48.6, [[0, POSE.stand(t)], [.3, tt => POSE.adjustGlasses(tt)], [1.3, tt => POSE.talk(tt + 48)]], .35)); face(VE, 'vera', t, { brow: .3, seed: 1, smile: .4 });
    const k = E.inOutSine(lt / 8);
    if (t < 53.4) look(L2W(lerp(4.6, 4.0, k), lerp(2.3, 2.0, k), lerp(-10.5, -9.5, k)), L2W(lerp(.5, 1.0, k), 1.5, lerp(8, 2, k)), 44);
    else look(L2W(-1.2, 1.5, -1.2), L2W(.3, 1.55, 1.6), 36);
    fadeIn(lt, .25);
    return S;
  });
  shot(56, 62, (lt, t) => {
    labBase(t);
    const sp = lab.main.spider;
    place(TI, lab.group, [0, 0, 1.0], Math.PI);
    place(VE, lab.group, [1.8, 0, -4.2], -2.5 + E.inOutCubic(P(t, 59.6, .6)) * 1.0);
    if (t < 59.6) {            // макро паучка: поворачивается к Тимуру
      sp.rotation.y = lerp(0, .35, E.inOutCubic(P(t, 57.2, .8)));
      sp.userData.anim(t, 0, 1);
      sp.position.y = 2.1 + Math.sin(t * 1.5) * .05;
      TI.pose(POSE.stand(t)); holdBox(TI); face(TI, 'timur', t, {});
      VE.pose(seq(t - 56, [[0, tt => POSE.talk(tt)], [1.2, tt => POSE.adjustGlasses(tt)], [2.2, tt => POSE.talk(tt)]], .35)); face(VE, 'vera', t, {});
      const k = E.inOutSine((t - 56) / 3.6);
      look(L2W(lerp(.8, .3, k), lerp(3.6, 3.4, k), lerp(-7.6, -8.3, k)), L2W(0, 3.1, -11), lerp(30, 24, k));
    } else {                   // Вера забирает посылку, грозит пальцем
      VE.pose(seq(t - 59.6, [[0, POSE.talk(t)], [.4, { ...POSE.stand(t), armR: [-1.3, 0, .2], foreR: [-1.2, 0, 0], handR: [-.5, 0, 0], head: [.1, Math.sin(t * 9) * .15, 0] }]]));
      face(VE, 'vera', t, { brow: -.2 });
      TI.pose({ ...POSE.stand(t), head: [.1, .2, 0] }); face(TI, 'timur', t, { brow: .5, smile: .3 });
      VE.J.handL.add(box); box.visible = true; box.position.set(.0, -.12, .2);
      look(L2W(-2.4, 1.7, -1.0), L2W(1.2, 1.5, -3.2), 38);
    }
    return S;
  });
  // Кронов выбивает двери
  shot(62, 72.5, (lt, t) => {
    labBase(t, { red: pulse(t, 62, 80, .3, .1) * (.6 + .4 * Math.sin(t * 6)) });
    const blast = t - 62.0;
    lab.doors.forEach((d, i) => {
      const s = i ? 1 : -1, k = clamp(blast / 1.2);
      d.position.set(s * (1.6 + 6 * E.outCubic(k)), 3.5 + Math.sin(k * Math.PI) * 2, 12.75 - 9 * E.outCubic(k)); d.rotation.set(-k * 2, s * k * 1.5, s * k);
    });
    if (blast > 0) props.sparks.burst(V(...L2W(0, 3.5, 12.5)), blast, { speed: 8, life: .9 });
    // дым в проёме и оранжевый контровой свет из лифта — Кронов выходит силуэтом
    smoke.forEach((sp, i) => {
      const k = clamp((blast - i * .05) / 3.5); sp.visible = blast > 0 && k < 1;
      sp.position.set(...L2W(Math.sin(i * 2.3) * (1 + k * 4), 1 + i * .45 + k * 2, 12.4 - k * (2 + i % 3)));
      sp.scale.setScalar(2 + k * 6); sp.material.opacity = .5 * (1 - k);
    });
    lab.lights[2].position.set(0, 4, 15.5); lab.lights[2].color.set(0xff7a2a);
    lab.lights[2].intensity = blast > 0 ? 260 * Math.exp(-blast * .6) + 40 : 0;
    const kp = kf(t, [[62.25, [0, 0, 12.4]], [66, [0, 0, 6], E.lin], [70.8, [0, 0, 5]], [71.4, [.6, 0, 3.4], E.outCubic]]);
    place(KR, lab.group, kp, Math.PI);
    const kd = 12.4 - kp[2], kph = gait(kd, .95, .7);
    KR.pose(t < 66 ? POSE.heavyWalk(kph) : seq(t - 66, [[0, POSE.stand(t)], [.25, tt => POSE.fistShake(tt)], [1.3, tt => POSE.stand(tt)], [5.0, { ...POSE.stand(t), spine: [.45, 0, 0], neck: [.2, 0, 0], head: [.25, 0, 0] }]]));
    if (t < 66) squash(KR, -.035 * Math.abs(Math.cos(kph * .7 * Math.PI * 2)));   // проседание брони на каждом шаге
    face(KR, 'kronov', t);
    place(TI, lab.group, [-1.5, 0, 1.6], Math.PI * .8);
    TI.pose({ ...POSE.stand(t), spine: [-.1, 0, 0], armL: [-.3, 0, .4], armR: [-.3, 0, .4], foreL: [-1.2, 0, 0], foreR: [-1.2, 0, 0] });
    face(TI, 'timur', t, { brow: .7, wide: true, look: [0, .3] });
    place(VE, lab.group, [kf(t, [[66.5, 1.2], [67.6, .6, E.outCubic]]), 0, kf(t, [[66.5, -1.2], [67.6, 1.8, E.outCubic]])], 0);
    VE.pose(t > 67 ? { ...POSE.talk(t * 1.3), armR: [-1.0, .3, .5], foreR: [-.3, 0, 0], spine: [.15, 0, 0] } : POSE.stand(t));
    face(VE, 'vera', t, { brow: -.5, mouth: C.mouthOf('vera', t) });
    if (t < 63.2) { const k = E.outCubic(P(t, 62, 1.2)); look(L2W(lerp(1.4, .8, k), 1.25, lerp(3.2, 4.2, k)), L2W(0, lerp(3.4, 2.8, k), 12.6), 50, .03); impact(t, 62.0, { zoom: .18, shake: .3 }); }
    else if (t < 67.1) { const k = E.inOutSine(P(t, 63, 4)); look(addv(L2W(-1.2 + k, .35, lerp(-.5, 1.0, k)), shk(t, .03, 2)), L2W(0, 2.4, kp[2]), 52, .04); }
    else if (t < 71.4) look(L2W(3.6, 1.7, 3.2), L2W(.4, 1.8, 2.2), 38);
    else { const k = E.outCubic(P(t, 71.4, .8)); look(L2W(-.4, 1.9, .2), L2W(.5, lerp(2.0, 2.3, k), 3.2), lerp(40, 28, k)); }
    return S;
  });
  // ядро, удар молнии, капсулы лопаются, Арахна-7 в прыжке
  shot(72.5, 77.6, (lt, t) => {
    const surge = t > 74 ? 1 : 0;
    labBase(t, { lights: surge ? .35 + .65 * Math.abs(Math.sin(t * 23)) * (t < 75.5 ? 1 : .3) : 1, red: .6 + surge * .8 });
    const kp = kf(t, [[72.5, [.6, 0, 3.4]], [73.2, [0, 0, -13.5], E.inOutQuad], [74.6, [0, 0, -13.5]], [75.8, [-6, 0, -6], E.inOutQuad], [77.6, [-14, 0, -2], E.inQuad]]);
    place(KR, lab.group, kp, t < 74.6 ? Math.PI : -1.0);
    KR.pose(t < 73.2 ? POSE.run(t, 1.4) : t < 74.6 ? POSE.punch(t - 73.2, 'L') : POSE.run(t, 1.2));
    KR.stolen.visible = t > 73.6; lab.core.visible = t <= 73.6;
    face(KR, 'kronov', t);
    // капсулы
    const burst = t - 74.3;
    lab.capsules.forEach(c => { if (burst > 0) { c.glass.visible = false; c.liquid.visible = false; } });
    if (burst > 0) lab.shards.update(burst, lab.capsules.map(c => V(c.x, 2.5 * c.s, c.z)), t > 76 ? .3 : 1);
    if (burst > 0) props.sparks.burst(V(...L2W(0, 6, -17)), t - 74.0, { speed: 10, life: 1.4 });
    // паучок: выпрыгивает из главной капсулы к Тимуру (слоу-мо 76..77.6)
    const sp = props.spider;
    lab.main.spider.visible = t < 75.6;
    if (t >= 75.6) {
      sp.visible = true; lab.group.add(sp);
      const j = t < 76 ? (t - 75.6) / .4 * .3 : .3 + (t - 76) / 1.6 * .7;
      const a = V(0, 3.4, -11), b = V(-1.0, 1.25, 1.4);
      const p = a.clone().lerp(b, j); p.y += Math.sin(j * Math.PI) * 2.2;
      sp.position.copy(p); sp.rotation.set(-.4 + j * .8, .1, 0); sp.scale.setScalar(1);
      sp.userData.anim(t, 0, 1);
    }
    place(TI, lab.group, [-1.0, 0, 1.6], Math.PI);
    TI.pose(t < 76 ? { ...POSE.stand(t), spine: [-.15, 0, 0], armL: [-.4, 0, .5], armR: [-.4, 0, .5], foreL: [-1.3, 0, 0], foreR: [-1.3, 0, 0] } : { ...POSE.stand(t), spine: [-.25, 0, 0], armR: [-1.2, .3, .3], foreR: [-.6, 0, 0], handR: [0, 0, .5], armL: [-.2, 0, .6], foreL: [-1.6, 0, 0] });
    face(TI, 'timur', t, { brow: .9, wide: true, mouth: t > 76 ? .6 : 0 });
    place(VE, lab.group, [2.2, 0, 2.2], -2.5); VE.pose({ ...POSE.stand(t), armL: [-.4, 0, .6], armR: [-.4, 0, .6], foreL: [-1.6, 0, 0], foreR: [-1.6, 0, 0], spine: [.3, 0, 0] }); face(VE, 'vera', t, { brow: .9, wide: true });
    // камера
    const sh = shk(t, t > 74 ? .5 * Math.exp(-(t - 74) * 1.5) : .04, 16);
    if (t < 74) { const k = E.inOutSine(P(t, 72.5, 1.5)); look(addv(L2W(lerp(6.5, 5, k), lerp(3.4, 3.8, k), lerp(-14, -15.8, k)), sh), L2W(lerp(1, 0, k), lerp(2.8, 4.2, k), lerp(-12, -17, k)), 50); }
    else if (t < 76) look(addv(L2W(-5.5, 3.2, -1), sh), L2W(0, 3.5, -12), 54, .08);
    else { const k = (t - 76) / 1.6; look(addv(L2W(-3.6, 2.2, lerp(-2, -.6, k)), sh), sp.getWorldPosition(TMP).toArray(), lerp(44, 36, k), -.1); }
    if (t > 74 && t < 74.6) post(o => o.fill('#e8f4ff', (1 - (t - 74) / .6) * .8));
    impact(t, 73.45, { zoom: .1, shake: .15 }); impact(t, 74.0, { zoom: .14, shake: .3, color: '#dff4ff' });
    post(o => o.comic('ДЗЫНЬ!', 600, 300, t - 74.35, { size: .55, color: '#bff6ff', rot: -.15, dur: .9 }));
    post(o => o.speedLines(pulse(t, 76, 77.6, .2, .1) * .5, t));
    return S;
  }, { flashK: .6 });
  // укус
  shot(77.6, 80.2, (lt, t) => {
    labBase(t, { lights: .4 + .3 * Math.abs(Math.sin(t * 19)), red: 1.2 });
    place(TI, lab.group, [-1.0, 0, 1.6], Math.PI);
    const p = { ...POSE.stand(t), armR: [-1.2, .3, .3], foreR: [-.6, 0, 0], handR: [.0, 0, .5 + Math.sin(t * 30) * .1 * (t > 77.8 ? 1 : 0)], spine: [-.2, 0, 0], head: [.2, .3, 0] };
    TI.pose(p);
    const bite = P(t, 77.8, .15);
    face(TI, 'timur', t, { brow: 1, wide: true, mouth: Math.max(C.mouthOf('timur', t), bite * .7) });
    const glowK = bite * (.6 + .4 * Math.sin(t * 25));
    TI.mats.hand.emissive.setRGB(.05 * glowK, .6 * glowK, .8 * glowK);
    const hw = handW(TI, 'R');
    const sp = props.spider; sp.visible = true; S.add(sp);
    sp.position.copy(hw).add(V(0, .12, 0)); sp.rotation.set(-.3, 2.6, 0); sp.scale.setScalar(t < 79.2 ? 1 : 1 - (t - 79.2)); sp.userData.anim(t, .3, 1);
    if (t > 79.2) sp.visible = (t - 79.2) < 1;
    if (t > 77.8) props.sparks2.burst(hw, t - 77.8, { speed: 2.5, life: .7, grav: 0, size: .04 });
    const sh = shk(t, t > 77.8 ? .06 : .01, 20);
    look(addv(hw.clone().add(V(.6, .5, -1.3)).toArray(), sh), hw.clone().add(V(0, .3, 0)).toArray(), 38);
    if (t > 78.9) { post(o => o.fill('#e9fdff', (t - 78.9) / 1.0)); }
    post(o => o.comic('КУСЬ!', 1350, 360, t - 77.8, { size: .7, color: '#7ff8ff', dur: 1.1 }));
    impact(t, 77.8, { zoom: .16, shake: .1, color: '#bff6ff' });
    return S;
  }, { flashK: 0 });
  shot(80.2, 83, (lt, t) => {
    labBase(t, { lights: .15, red: 1.6 });
    place(KR, lab.group, kf(t, [[80.2, [-18, 0, -1]], [81.8, [-22.5, 0, -1], E.inQuad], [83, [-30, -6, -1], E.inQuad]]), -Math.PI / 2);
    KR.pose(t < 81.8 ? POSE.run(t) : POSE.flip(t)); KR.stolen.visible = true; face(KR, 'kronov', t);
    const out = t - 81.8;
    if (out > 0) props.shards.update(out, [V(15, 263, -441)]);
    look(L2W(-8, 2.4, 2), L2W(-22, 3, -1), 40);
    post(o => o.fill('#e9fdff', 1 - (t - 80.2) / .9));
    fadeOut(lt, 2.8, .5);
    return S;
  });

  /* ===== СЦЕНА 4. Пробуждение ===== */
  const ROOF = [128, 112.05, -432];
  shot(83, 90, (lt, t) => {
    env({ fill: [[128, 115, -429], 15, 0x7feaff] });
    place(TI, S, ROOF, .4);
    let p;
    if (t < 85.8) { TI.root.rotation.set(-Math.PI / 2, 0, .4); TI.root.position.y = ROOF[1] + .17; p = POSE.lie(t); }
    else p = seq(t - 85.8, [[0, POSE.lie(t)], [.9, POSE.sitUp()], [2.2, tt => POSE.lookHand(tt)]], .7);
    if (t >= 85.8) { const k = E.inOutCubic(P(t, 85.8, .9)); TI.root.rotation.set(-Math.PI / 2 * (1 - k), .4, .4 * (1 - k)); TI.root.position.y = ROOF[1] + .17 * (1 - k); }
    TI.pose(p);
    const g = .5 + .5 * Math.sin(t * 3);
    TI.mats.hand.emissive.setRGB(.02 * g, .2 * g, .3 * g);
    face(TI, 'timur', t, { brow: .5, blink: t < 85 ? 1 : blinkAt(t), look: [0, -.3] });
    if (t < 87.6) { const k = E.inOutSine(P(t, 83, 4.6)); look([128 + Math.sin(k) * .4, lerp(122, 116.5, k), -432 + .01], [128, 112, -432], 40, k * .6); }
    else { const hw = handW(TI, 'R'); look(hw.clone().add(V(-.2, .55, .9)).toArray(), hw.toArray(), 32); }
    fadeIn(lt, 1.4);
    return S;
  });
  shot(90, 97, (lt, t) => {
    const sense = pulse(t, 90, 97, .5, .3);
    U.sense.value = sense;
    U.rainTime.value = 90 + (t - 90) * lerp(1, .015, clamp(sense * 1.4));
    city.rain.userData.mat.uniforms.alpha.value = .5 + sense * .5;
    env({ fill: [[128, 114, -431], 40, 0x7feaff] });
    place(TI, S, ROOF, .4 + E.inOutSine(P(t, 90, 3)) * .5);
    TI.pose(seq(t - 90, [[0, POSE.lookHand(0)], [.8, tt => POSE.stand(tt)], [4, tt => ({ ...POSE.stand(tt), armL: [-.2, 0, .7 + .1 * Math.sin(tt * 30)], armR: [-.2, 0, .7], foreL: [-.4, 0, 0], foreR: [-.4, 0, 0], spine: [-.1, 0, 0], head: [-.2, 0, 0] })]], .8));
    const suitK = P(t, 94, 2.8);
    TI.setSuit(t > 96.6);
    if (!TI.suit) face(TI, 'timur', t, { brow: .6, wide: true, look: [Math.sin(t), .2] }); else face(TI, 'timur', t, { squint: 1.05 });
    TI.mats.hand.emissive.setRGB(.03, .35, .5);
    const c = V(...ROOF); props.swirl.update(c, suitK, t);
    const hp = headW(TI);
    for (let i = 0; i < 3; i++) { const ph = ((t - 90) * .7 + i / 3) % 1; props.rings.add(hp, .3 + ph * 5, (1 - ph) * .6 * sense, cam); }
    const a = .4 + (t - 90) * .55;
    look([128 + Math.sin(a) * 3.2, 113.4 + Math.sin(t * .5) * .3, -432 + Math.cos(a) * 3.2], [128, 113.1, -432], 42);
    if (t > 96.4) post(o => o.fill('#dffcff', 1 - Math.abs(t - 96.65) / .25));
    return S;
  });
  // на стене (северный фасад здания, нормаль +z)
  const WALL = [131, 92, -412.85];
  const onWall = (pos, yaw = 0) => {
    place(TI, S, pos, 0);
    const q = new THREE.Quaternion().setFromUnitVectors(V(0, 1, 0), V(0, 0, 1));
    TI.root.quaternion.copy(q).multiply(new THREE.Quaternion().setFromAxisAngle(V(0, 1, 0), Math.PI + yaw));
  };
  shot(97, 102, (lt, t) => {
    env({ fill: [[131, 92, -410], 40, 0x7feaff] });
    TI.setSuit(true);
    onWall([WALL[0], WALL[1] + E.inOutSine(P(t, 97, 4.5)) * 1.2, WALL[2]], Math.sin(t * .8) * .2);
    TI.pose(POSE.spiderCrouch(t)); face(TI, 'timur', t, { squint: t > 97.8 && t < 99.4 ? 1.25 : 1 });
    const k = E.inOutSine(P(t, 97, 5));
    // камера сначала «лежит» вместе со стеной, потом раскручивается
    cam.position.set(lerp(128.5, 133.5, k), lerp(90.8, 89.0, k), lerp(-411, -406.5, k));
    cam.up.set(0, 0, 1).lerp(V(0, 1, 0), E.inOutCubic(P(t, 98.8, 2.4))).normalize();
    cam.lookAt(WALL[0], WALL[1] + .4, WALL[2] + .3); cam.fov = lerp(40, 50, k); cam.updateProjectionMatrix();
    post(o => o.comic('?!', 1450, 300, t - 98.2, { size: .8, color: '#7ff8ff', dur: 1.4 }));
    return S;
  });
  // срывается и падает
  shot(102, 107, (lt, t) => {
    env({ fill: [[131, 70, -405], 30, 0x7feaff] });
    TI.setSuit(true);
    const k = P(t, 102.3, 4.7);
    const pos = [WALL[0] + 1.0 + 6 * k, WALL[1] + 1.2 - 48 * k * k - (t < 102.3 ? 0 : 1), WALL[2] + 2.2 * Math.sqrt(k) + 1.2 * k];
    if (t < 102.3) { onWall([WALL[0], WALL[1] + 1.2, WALL[2]], 0); TI.pose(POSE.spiderCrouch(t)); }
    else { place(TI, S, pos, 0); TI.root.rotation.set(Math.sin(t * 2.6) * 2.2, t * 1.4, Math.cos(t * 2.1) * .8); TI.pose(POSE.fall(t)); }
    face(TI, 'timur', t, { squint: 1.3 });
    if (t < 104.6) look([WALL[0] + 3, 18, WALL[2] + 9], [pos[0], pos[1], pos[2]], lerp(26, 40, P(t, 102, 2.6)));
    else look([pos[0] + 1.2, pos[1] + 4.5, pos[2] + 2.5], [pos[0], pos[1] - 6, pos[2] + 1], 58, Math.sin(t * 3) * .2);
    post(o => o.speedLines(clamp((t - 102.8) / .8) * .9, t));
    return S;
  });
  // ВЖУХ — первая нить
  shot(107, 108.2, (lt, t) => {
    env({ fill: [[140, 45, -400], 30, 0x7feaff] });
    TI.setSuit(true);
    const pos = swingAt(t);
    place(TI, S, pos.toArray(), 0);
    orient(TI, A1.clone().sub(pos), V(1, 0, .1));
    TI.pose(POSE.shootUp());
    face(TI, 'timur', t, { squint: .75 });
    const hw = handW(TI, 'R');
    props.webs.add(hw, A1, { k: E.outCubic(P(t, 107.1, .3)), w: .05, splatSize: 1.2, splatNormal: V(0, 0, 1), wob: .9, wobT: t - 107.4 });
    look(hw.clone().add(V(-1.6, -1.2, 1.4)).toArray(), hw.clone().add(V(.4, 1.2, -.3)).toArray(), 46, .2);
    post(o => o.comic('ВЖУХ!', 1250, 330, t - 107.15, { size: .9, color: '#7ff8ff', dur: 1.0 }));
    return S;
  });
  // ПОЛЁТ
  shot(108.2, 117.2, (lt, t) => {
    env({ fill: [[0, 0, 0], 0] });
    TI.setSuit(true);
    const pos = swingAt(t), vel = swingVel(t);
    place(TI, S, pos.toArray(), 0);
    const swing1 = t < 111.4, swing2 = t > 112.3 && t < 115.4, flipK = P(t, 111.45, .8);
    const anchor = swing1 ? A1 : swing2 ? A2 : null;
    if (anchor) { orient(TI, anchor.clone().sub(pos), vel); TI.pose(POSE.swing(t)); }
    else if (t < 112.3) { orient(TI, V(0, 1, 0), V(1, 0, 0)); TI.root.rotateX(-flipK * Math.PI * 2); TI.pose(blend(POSE.flip(t), POSE.swing(t), Math.abs(flipK - .5) * 2 > .8 ? 1 : 0)); }
    else { orient(TI, V(0, 1, 0).lerp(vel.clone().normalize(), .3), V(.2, 0, 1)); TI.pose(t < 116.3 ? POSE.flip(t) : POSE.heroLand()); }
    face(TI, 'timur', t, { squint: .9, energy: 1.2 });
    // вытягивание в начале сальто, пружинка при приземлении
    squash(TI, .13 * pulse(t, 111.35, 111.85, .06, .3) + springAt(t, 116.6, -.26, 15, 7));
    if (anchor) props.webs.add(handW(TI, 'R'), anchor, { w: .05, k: swing2 ? E.outCubic(P(t, 112.3, .25)) : 1, splatSize: 1.2, splatNormal: V(0, 0, 1),
      wob: .7, wobT: swing2 ? t - 112.55 : t - 107.4 });
    const sh = shk(t, .08, 6);
    if (t < 111.4) {            // камера «на нити»: летит прямо за героем, чуть сбоку, крен в дуге
      const vn = vel.clone().normalize(), side = V(0, 1, 0).cross(vn).normalize();
      const k = E.inOutSine(P(t, 108.2, 3.2));
      const cp = pos.clone().addScaledVector(vn, -lerp(4.6, 3.2, k)).addScaledVector(side, lerp(1.8, 1.2, k)).add(V(0, lerp(1.6, .9, k), 0));
      look(addv(cp.toArray(), sh), pos.clone().addScaledVector(vn, 5).add(V(0, .6, 0)).toArray(), lerp(62, 56, k), -vel.y * .012 - .06);
    } else if (t < 114.4) {     // фронтально, вдоль улицы: сальто на фоне неба
      look(addv([340, lerp(55, 44, P(t, 111.4, 3)), -399], sh), pos.toArray(), lerp(34, 46, P(t, 111.4, 3)));
    } else {                    // облёт и приземление
      const k = E.inOutSine(P(t, 114.4, 2.8));
      look(addv([lerp(296, 312, k), lerp(46, 77, k), lerp(-404, -380, k)], sh), pos.toArray(), lerp(50, 40, k), lerp(.12, 0, k));
    }
    post(o => o.speedLines(pulse(t, 108.2, 116.3, .2, .4) * .45, t));
    post(o => o.comic('ВЖУХ!', 600, 280, t - 112.35, { size: .6, color: '#7ff8ff', rot: .1, dur: .8 }));
    if (t > 116.55) props.rings.add(V(305.5, 74.2, -387), .3 + (t - 116.55) * 6, Math.max(0, 1 - (t - 116.55) * 1.8));
    return S;
  });
  // «А потом я увидел мост»
  shot(117.2, 123, (lt, t) => {
    env({ fill: [[305, 76, -386], 20, 0x7feaff] });
    TI.setSuit(true);
    place(TI, S, [305.5, 74.1, -387], Math.PI / 2 + .1);
    TI.pose(seq(t - 117.2, [[0, POSE.heroLand()], [1.4, tt => ({ ...POSE.stand(tt), head: [.1, 0, 0] })]], 1.2));
    squash(TI, springAt(t, 116.6, -.26, 15, 7));
    face(TI, 'timur', t, { squint: 1 });
    bridgeProps(t); busState(t, busTilt(t), busSlide(t));
    place(KR, S, [446, 0, -399], -Math.PI / 2); KR.pose(POSE.roar(t)); face(KR, 'kronov', t);
    const k = E.inOutCubic(P(t, 117.2, 5.8));
    look([lerp(303, 311, k), lerp(75.4, 81, k), lerp(-385, -384, k)], [lerp(305.5, 455, k), lerp(75, 4, k), lerp(-387, -394, k)], lerp(50, 36, k));
    return S;
  });

  /* ===== СЦЕНА 5. Мост ===== */
  const bridgeBase = t => { bridgeProps(t); busState(t, busTilt(t), busSlide(t)); env({ key: 2.0, rim: 2.2, rimPos: [520, 40, -460] }); C.camFill = [6, 0xffd0a0];
    if (t >= 141 && t < 175) { const p = TIp(t); rimOn([p[0], p[1] + 1.2, p[2]], 0xa8f0ff, 3.0); } };
  shot(123, 129, (lt, t) => {
    bridgeBase(t);
    // Кронов подходит к брошенной машине, бьёт кулаком и рычит в сторону города
    const kp = kf(t, [[123, [443.5, 0, -397]], [125.2, [446, 0, -399.6], E.inOutSine]]);
    const kd = Math.hypot(kp[0] - 443.5, kp[2] + 397);
    place(KR, S, kp, t < 126.6 ? 2.9 : lerp(2.9, -Math.PI / 2, E.outBack(P(t, 126.6, .6))));
    KR.pose(seq(t - 123, [[0, () => POSE.heavyWalk(gait(kd, .95, .7))], [2.2, POSE.stand(t)], [2.5, tt => POSE.punch(tt, 'R')], [3.6, tt => POSE.roar(tt)]], .25));
    face(KR, 'kronov', t);
    if (t > 125.6) props.sparks.burst(V(447.2, 1.3, -403.4), t - 125.7, { speed: 7, life: 1 });
    if (t < 125.4) {          // общий план
      const k = E.inOutSine(P(t, 123, 2.4));
      look(addv([lerp(418, 424, k), lerp(14, 11, k), lerp(-362, -368, k)], shk(t, .1, 2)), [450, 1.6, -396], 44);
    } else {                  // средний план снизу: удар крупно
      const k = E.inOutSine(P(t, 125.4, 3.6));
      look(addv([lerp(440.2, 441.2, k), lerp(1.2, 1.5, k), lerp(-401.2, -400.4, k)], shk(t, .03, 3)), [446.6, lerp(2.4, 2.9, k), -401.8], lerp(46, 40, k));
      impact(t, 125.7, { zoom: .14, shake: .25 });
    }
    fadeIn(lt, .3);
    post(o => o.comic('БАМ!', 1240, 420, t - 125.7, { size: .7, color: '#ff8a3d', dur: .9 }));
    return S;
  });
  shot(129, 133, (lt, t) => {
    bridgeBase(t);
    place(KR, S, [442, 0, -399], -Math.PI / 2); KR.pose(POSE.roar(t)); face(KR, 'kronov', t);
    props.busPivot.updateMatrixWorld(true);
    const sign = props.bus.localToWorld(V(0, 3.2, 6.05));
    const k = E.inOutExpo(P(t, 129.3, 1.2));
    look([lerp(330, 438, k), lerp(70, 10, k), lerp(-386, -360, k)], sign.toArray(), lerp(30, 14, k));
    post(o => o.speedLines(pulse(t, 129.3, 130.6, .1, .3) * .6, t));
    return S;
  });
  // сомнение: «Обещал — держи»
  const carab = mesh(new THREE.TorusGeometry(.035, .009, 8, 20), toon(0xd6dae2, { emissive: 0x30343c }), { scale: [.7, 1.2, 1], outline: .004 });
  shot(133, 141, (lt, t) => {
    bridgeBase(t);
    TI.setSuit(true);
    place(TI, S, [305.5, 74.1, -387], Math.PI / 2 + .1);
    const p = { ...POSE.stand(t), armR: [-1.0, -.6, .2], foreR: [-1.4, 0, 0], handR: [.4, 0, 0], head: [.35, -.2, 0], spine: [.15, 0, 0] };
    const jump = P(t, 140.2, .3);
    TI.pose(t < 139.6 ? p : blend(POSE.crouch(), POSE.flip(t), jump));
    TI.J.handR.add(carab); carab.visible = t < 139.6; carab.position.set(0, -.08, .05); carab.rotation.set(0, 0, 0);
    if (t > 140.2) TI.root.position.set(305.5 + (t - 140.2) * 12, 74.1 + (t - 140.2) * 6, -387);
    const fear = pulse(t, 133.5, 139.3, .3, .5);
    face(TI, 'timur', t, { squint: t > 139.3 ? .55 : lerp(1, 1.3, fear) });
    const memory = pulse(t, 136.4, 138.6, .3, .4);
    U.tint.value.setRGB(1 + memory * .25, 1 + memory * .05, 1 - memory * .3);
    if (t < 136.4) { const k = E.inOutSine(P(t, 133, 3.4)); look([lerp(307.8, 307.2, k), 75.9, lerp(-386.2, -386.5, k)], [305.6, 75.85, -387], lerp(34, 26, k)); }
    else if (t < 138.6) { const hw = handW(TI, 'R'); look(hw.clone().add(V(.35, .15, .35)).toArray(), hw.toArray(), 30); }
    else { const k = E.outCubic(P(t, 138.6, 1.5)); look([lerp(307.6, 307.2, k), 75.6, -386.6], [305.6, 75.35, -387], lerp(30, 22, k)); }
    post(o => o.fill('#3a2410', memory * .25));
    if (t > 139.4 && t < 140.4) post(o => o.speedLines((t - 139.4) * .9, t));
    return S;
  });
  // приземление перед Кроновым
  shot(141, 147, (lt, t) => {
    bridgeBase(t);
    TI.setSuit(true);
    const tp = TIp(t);
    place(TI, S, tp, Math.PI / 2);
    TI.pose(seq(t - 141.3, [[-1, POSE.flip(t)], [0, POSE.heroLand()], [2.4, tt => ({ ...POSE.stand(tt), spine: [.1, 0, 0], armL: [-.3, 0, .5], armR: [-.3, 0, .5], foreL: [-1.0, 0, 0], foreR: [-1.0, 0, 0], legL: [-.2, 0, .2], legR: [.1, 0, .2], hy: -.1 })]], .15));
    face(TI, 'timur', t, { squint: .7, energy: .6 });
    squash(TI, springAt(t, 141.3, -.28, 15, 7));                       // отдача приземления
    const kp = KRp(t); place(KR, S, kp, -Math.PI / 2);
    // идёт, останавливается и грозит кулаком на «…с кем связался!»
    KR.pose(seq(t - 141, [[0, tt => POSE.roar(tt)], [.6, () => POSE.heavyWalk(gait(440 - kp[0], .95, .7))], [2.6, tt => POSE.stand(tt)], [3.0, tt => POSE.fistShake(tt)], [5.2, tt => POSE.stand(tt)]], .3));
    if (t > 141.6 && t < 143.6) squash(KR, -.035 * Math.abs(Math.cos(gait(440 - kp[0], .95, .7) * .7 * Math.PI * 2)));
    face(KR, 'kronov', t);
    if (t > 141.3) { props.rings.add(V(425, .2, -398), (t - 141.3) * 7, Math.max(0, 1 - (t - 141.3) * 1.5), null, 0xffffff); props.sparks.burst(V(425, .3, -398), t - 141.3, { speed: 4, life: .6, size: .1 }); }
    if (t < 142.4) { const k = E.outCubic(P(t, 141, .38)); look(addv([418, 1.0, -392], shk(t, t > 141.3 ? .25 * Math.exp(-(t - 141.3) * 4) : 0, 16)), [lerp(421, 425, k), lerp(8, 1.2, k), -398], 50); }
    else { const k = E.inOutSine(P(t, 142.4, 4.6)); look(addv([lerp(419.5, 420.2, k), .7, lerp(-399.8, -401.2, k)], shk(t, .02, 2)), [kp[0], lerp(2.6, 3.0, k), kp[2]], lerp(44, 36, k), .03); }
    post(o => o.comic('ТУДУМ!', 520, 300, t - 141.3, { size: .55, color: '#ffffff', dur: .9 }));
    impact(t, 141.3, { zoom: .12, shake: .2 });
    return S;
  });
  // «Курьерская доставка! Распишитесь!»
  shot(147, 151, (lt, t) => {
    bridgeBase(t);
    TI.setSuit(true);
    place(TI, S, TIp(t), Math.PI / 2);
    TI.pose(seq(t - 147, [[0, tt => ({ ...POSE.stand(tt), armL: [-.3, 0, .5], foreL: [-1.0, 0, 0] })], [1.1, POSE.shootFwd('R')], [2.6, tt => POSE.stand(tt)]], .2));
    face(TI, 'timur', t, { squint: .8 });
    const kp = KRp(t); place(KR, S, kp, -Math.PI / 2);
    const hit = t - 148.4;
    KR.pose(hit < 0 ? POSE.stand(t) : seq(hit, [[0, { ...POSE.stand(t), spine: [-.3, 0, 0], head: [-.5, 0, 0], armL: [-1.8, 0, .6], foreL: [-1.6, 0, 0], armR: [-1.6, 0, .6], foreR: [-1.8, 0, 0] }], [1.4, tt => POSE.roar(tt)]], .3));
    face(KR, 'kronov', t, { dim: hit > 0 && hit < 1.5 ? .3 : 1 });
    if (hit > -.2) { const hw = handW(TI, 'R'); const vis = headW(KR).add(V(-.25, -.1, 0)); props.webs.add(hw, vis, { k: E.outCubic(P(t, 148.3, .2)), w: .04, splatSize: .35, splatNormal: V(-1, 0, 0), wob: .3, wobT: t - 148.5 }); }
    squash(KR, springAt(t, 148.5, -.08, 12, 6));
    if (t < 149.6) look([419.8, 1.8, -394.5], [433, 2.6, -399], 40);
    else look(addv([429, 2.2, -395.2], shk(t, .05, 8)), [434, 3, -399], 34);
    impact(t, 148.47, { zoom: .1, shake: .08, color: '#c8fbff' });
    // комикс-панель: визор, залепленный паутиной
    const kh = headW(KR);
    panel(0, pulse(t, 148.45, 149.55, .1, .15) * 1.01, [90, 90, 560, 330], S, kh.clone().add(V(-1.9, .25, -.9)).toArray(), kh.clone().add(V(0, -.1, 0)).toArray(), 30);
    post(o => o.comic('ШЛЁП!', 1300, 380, t - 148.5, { size: .6, color: '#7ff8ff', dur: .9 }));
    return S;
  });
  // бой
  shot(151, 157, (lt, t) => {
    bridgeBase(t);
    TI.setSuit(true);
    // слоу-мо уклонения
    const tp = TIp(t);
    place(TI, S, tp, Math.PI / 2 + (t > 152.4 && t < 153.4 ? 0 : t > 153.4 ? Math.PI : 0));
    const fk = P(t, 152.4, .9);
    TI.pose(seq(t - 151, [[0, tt => POSE.stand(tt)], [.4, POSE.dodge()], [1.4, POSE.flip(t)], [2.4, { ...POSE.punch(.2, 'R'), legR: [-1.6, 0, .1], shinR: [.1, 0, 0] }], [3.0, tt => POSE.stand(tt)]], .15));
    if (t > 152.4 && t < 153.3) TI.root.rotateX(-fk * Math.PI * 2);
    squash(TI, .14 * pulse(t, 152.35, 152.75, .05, .25) + springAt(t, 153.35, -.22, 15, 7));
    face(TI, 'timur', t, { squint: .7, energy: 1 });
    const sense = pulse(t, 151.3, 152.5, .1, .3);
    U.sense.value = sense * .8;
    U.rainTime.value = 151.3 + (t - 151.3) * lerp(1, .1, sense);
    const kp = KRp(t); place(KR, S, kp, t < 153.8 ? -Math.PI / 2 : t < 154.4 ? Math.PI / 2 : Math.PI / 2 - .4);
    KR.pose(seq(t - 151, [[0, tt => POSE.punch(tt * (sense > .5 ? .3 : 1), 'R')], [2.6, tt => POSE.stand(tt)], [2.8, { ...POSE.stand(t), spine: [.5, 0, 0], armL: [-.5, 0, .9], armR: [-.5, 0, .9] }], [3.8, tt => POSE.roar(tt)]], .2));
    face(KR, 'kronov', t);
    squash(KR, springAt(t, 153.65, -.1, 12, 6));
    if (t > 151.3 && t < 152.5) props.rings.add(headW(TI), .3 + (t - 151.3) * 1.5, (1 - (t - 151.3)) * .8, cam);
    if (t > 154.5) props.sparks.burst(V(449, 2, -395), t - 154.5, { speed: 8, life: 1.1 });
    let sh = shk(t, .04, 3);
    if (t > 153.6) sh = addv(sh, shk(t, .25 * Math.exp(-(t - 153.6) * 4), 18));
    if (t < 152.4) look(addv([427, 1.8, -389.5], sh), [427.5, 1.9, -399.5], 44);
    else if (t < 154.3) look(addv([lerp(428, 438, P(t, 152.4, 1.8)), 3.5, -389], sh), [tp[0], tp[1] + 1.2, tp[2]], 46, -.05);
    else look(addv([438, 5, -386], sh), [452, 1, -391], 44);
    post(o => o.comic('БАМ!', 1250, 430, t - 153.65, { size: .7, color: '#ffe23d', dur: .9 }));
    post(o => o.comic('ХРЯСЬ!', 640, 380, t - 154.6, { size: .65, color: '#ff8a3d', rot: .12, dur: 1.0 }));
    impact(t, 153.65, { zoom: .14, shake: .2 }); impact(t, 154.6, { zoom: .1, shake: .3 });
    return S;
  }, { flashK: .7 });
  // держит автобус
  shot(157, 163, (lt, t) => {
    bridgeBase(t);
    TI.setSuit(true);
    place(TI, S, TIp(t), 0);
    TI.pose(seq(t - 157, [[0, POSE.shootFwd('R')], [.35, tt => POSE.pull(tt)]], .25));
    face(TI, 'timur', t, { squint: .6 + .1 * Math.sin(t * 20) });
    const rear = busRear(t);
    const hl = handW(TI, 'L'), hr = handW(TI, 'R');
    const k = E.outCubic(P(t, 157.1, .25));
    props.webs.add(hr, rear.clone().add(V(.8, .6, 0)), { k, w: .05 + .01 * Math.sin(t * 40), wob: .6, wobT: t - 157.35 });
    props.webs.add(hl, rear.clone().add(V(-.8, .6, 0)), { k, w: .05 + .01 * Math.sin(t * 43), wob: .6, wobT: t - 157.4 });
    if (t > 160.4) {      // привязывает к фонарю
      const post0 = V(460, 6.5, -398.9 - 11.5 + 0);
      props.webs.add(rear.clone().add(V(.8, .6, 0)), V(460, 3, -411), { k: E.outCubic(P(t, 160.5, .3)), w: .05 });
      props.webs.add(rear.clone().add(V(-.8, .6, 0)), V(448, 3, -411), { k: E.outCubic(P(t, 160.7, .3)), w: .05 });
    }
    const kp = KRp(t); place(KR, S, kp, Math.PI / 2 - .4); KR.pose(seq(t - 157, [[0, POSE.collapse()], [3.6, tt => POSE.roar(tt)]], 1.2)); face(KR, 'kronov', t, { dim: t < 160 ? .4 : 1 });
    const sh = shk(t, .03 + .04 * pulse(t, 157, 160, .2, .5), 14);
    if (t < 159.2) look(addv([446.5, .9, -405.5], sh), [452, 1.6, -398], 44);
    else if (t < 160.4) {     // крупно: лицо в маске, на пределе сил
      const hp = headW(TI); look(addv(hp.clone().add(V(.25, .1, 1.35)).toArray(), shk(t, .02, 18)), hp.clone().add(V(0, -.05, 0)).toArray(), 30);
    }
    else if (t < 161.6) { const hw = hr; look(addv(hw.clone().add(V(.9, .25, -.6)).toArray(), sh), hw.clone().add(V(0, .1, 1.5)).toArray(), 36); }
    else look(addv([445.5, 3.5, -409], sh), [452, 1.4, -400], 48);
    return S;
  });
  // «Молния не бьёт дважды» — Кронов примотан к пилону, удар молнии
  shot(163, 171, (lt, t) => {
    bridgeBase(t);
    TI.setSuit(true);
    const tp = TIp(t);
    place(TI, S, tp, t < 164 ? 0 : -Math.PI / 2);
    TI.pose(seq(t - 163, [[0, tt => POSE.pull(tt)], [1.0, POSE.flip(t)], [1.6, POSE.shootFwd('R')], [2.8, POSE.shootFwd('L')], [3.6, tt => ({ ...POSE.stand(tt), armR: [-2.9, 0, .3], foreR: [-.2, 0, 0], head: [-.4, 0, 0] })], [5.8, POSE.crouch()]], .2));
    face(TI, 'timur', t, { squint: t > 168 ? 1.2 : .8, energy: .8 });
    squash(TI, .13 * pulse(t, 163.95, 164.4, .05, .25) + springAt(t, 165.8, -.2, 15, 7));
    const rear = busRear(t);
    props.webs.add(rear.clone().add(V(.8, .6, 0)), V(460, 3, -411), { w: .05 });
    props.webs.add(rear.clone().add(V(-.8, .6, 0)), V(448, 3, -411), { w: .05 });
    const kp = KRp(t); place(KR, S, kp, t < 164.6 ? Math.PI / 2 - .6 : Math.PI);
    const zap = t - 169.05;
    KR.pose(t < 164.6 ? POSE.run(t, 1.3) : t < 165.6 ? POSE.fall(t) : zap < 0 ? { ...POSE.strained(t), armL: [.2, 0, .4], armR: [.2, 0, .4] } : zap < 1.4 ? { ...POSE.strained(t * 3), head: [-.6, 0, 0] } : POSE.collapse());
    face(KR, 'kronov', t, { dim: zap > 1.2 ? Math.max(0, 1 - (zap - 1.2) * 2) * (Math.sin(t * 40) > 0 ? 1 : .2) : 1 });
    if (zap > 0 && zap < 1.6) { KR.mats.coreM.color.setRGB(.5, 2 + Math.sin(t * 60), 3); } else KR.mats.coreM.color.setRGB(3, 1.9, .75);
    // нити: рывок и обмотка вокруг пилона
    const kh = headW(KR);
    if (t > 164.5 && t < 165.6) props.webs.add(handW(TI, 'R'), kh, { w: .045 });
    if (t > 165.8) {
      for (let i = 0; i < 6; i++) {
        const y = .6 + i * .45, a = V(393.6 + Math.sin(i) * .8, y, -389.8 - .9), b = V(391.6, y + .2, -387.5 + (i % 2 ? 1.6 : -1.6));
        props.webs.add(a, b, { k: E.outCubic(P(t, 165.8 + i * .12, .2)), w: .05, splat: false });
      }
    }
    if (zap > 0) props.sparks2.burst(V(393.6, 2.5, -389.8), zap, { speed: 7, life: 1.4, grav: 4 });
    if (zap > 0) props.sparks.burst(V(390, 126, -387.5), zap, { speed: 14, life: 1.2 });
    if (zap > 0 && zap < 1.3) for (let i = 0; i < 2; i++) props.rings.add(V(393.6, 2, -389.8), .5 + ((zap * 2 + i * .5) % 1) * 4, .8, cam, 0x9ff8ff);
    // камера
    let sh = shk(t, .04, 3);
    if (zap > 0) sh = addv(sh, shk(t, .6 * Math.exp(-zap * 2.2), 20));
    if (t < 165.8) look(addv([lerp(440, 420, P(t, 163, 2.8)), 5, -380], sh), [kp[0], kp[1] + 2, kp[2]], 50);
    else if (t < 168.2) look(addv([404, 2.2, -394], sh), [kf(t, [[165.8, 399], [167.4, 395]]), kf(t, [[165.8, 2], [167.4, 3], [168.2, 12]]), -390], 44);
    else if (t < 169.0) look(addv([410, 1.2, -380], sh), [392, 60, -390], 60);
    else look(addv([418, 6, -368], sh), [393, lerp(30, 8, E.outCubic(P(t, 169, 1.2))), -389], 54);
    if (zap > 0 && zap < .5) post(o => o.fill('#e8f4ff', (1 - zap / .5) * .9));
    post(o => o.comic('БА-БАХ!', 960, 360, t - 169.1, { size: 1.0, color: '#bff6ff', rot: -.05, dur: 1.4 }));
    impact(t, 165.6, { zoom: .12, shake: .25 }); impact(t, 169.0, { zoom: .18, shake: .2, color: '#e8f4ff' });
    squash(KR, springAt(t, 165.6, -.12, 12, 6));
    return S;
  }, { flashK: 1.2 });
  // вытягивает автобус
  shot(171, 175, (lt, t) => {
    bridgeBase(t);
    TI.setSuit(true);
    place(TI, S, [452 - (t - 171) * .6, 0, -406.5], 0);
    TI.pose(POSE.pull(t));
    face(TI, 'timur', t, { squint: .65 });
    const rear = busRear(t);
    props.webs.add(handW(TI, 'R'), rear.clone().add(V(.8, .6, 0)), { w: .055 });
    props.webs.add(handW(TI, 'L'), rear.clone().add(V(-.8, .6, 0)), { w: .055 });
    place(KR, S, [393.6, .2, -389.2], Math.PI); KR.pose(POSE.collapse()); face(KR, 'kronov', t, { dim: 0 });
    for (let i = 0; i < 6; i++) { const y = .6 + i * .45; props.webs.add(V(393.6 + Math.sin(i) * .8, y, -390.1), V(391.6, y + .2, -387.5 + (i % 2 ? 1.6 : -1.6)), { w: .05, splat: false }); }
    if (t > 174) props.rings.add(V(455, .2, -389), (t - 174) * 9, Math.max(0, 1 - (t - 174) * 1.4), null, 0xffffff);
    const k = E.inOutSine(lt / 4);
    look(addv([lerp(470, 474, k), lerp(14, 9, k), lerp(-372, -366, k)], shk(t, t > 174 ? .2 * Math.exp(-(t - 174) * 4) : .02, 14)), [454, 1.5, -394], 44);
    post(o => o.comic('БУМ!', 1320, 600, t - 174.05, { size: .55, color: '#ffffff', dur: .8 }));
    impact(t, 174.05, { zoom: .08, shake: .2 });
    squash(TI, springAt(t, 174.05, -.1, 12, 6));
    return S;
  });

  /* ===== СЦЕНА 6. Обещание ===== */
  shot(175, 183, (lt, t) => {
    bridgeBase(t);
    city.rain.userData.mat.uniforms.alpha.value = .35;
    // дед выходит из автобуса
    const dp = kf(t, [[175.4, [456.6, .5, -390.4]], [176.6, [456.6, 0, -393.6], E.inOutSine], [182, [456.4, 0, -394.2]]]);
    place(DE, S, dp, Math.PI + .25);
    DE.pose(t < 176.6 ? POSE.walk(gait(Math.hypot(dp[0] - 456.6, dp[2] + 390.4), .55, .9)) : blend(POSE.stand(t), POSE.lookUp(t), E.inOutSine(P(t, 176.6, .6))));
    face(DE, 'ded', t, { brow: .45, look: [0, .8], smile: t > 181 ? .9 : 0, seed: 2 });
    // Тимур висит вниз головой на нити
    TI.setSuit(true);
    const zip = P(t, 181.5, .7);
    const hang = V(454.6, 6.2 + E.inQuad(zip) * 40, -396.2);
    place(TI, S, hang.toArray(), 0);
    TI.root.rotation.set(Math.PI, Math.PI * .1 + Math.sin(t * .8) * .15, 0);
    TI.root.position.y = hang.y + TI.d.hipY + .45;
    TI.pose(t < 181.4 ? { ...POSE.hangUpside(t), armR: t > 179.6 && t < 181.3 ? [-.6, .2, 1.4] : [-.4, -.4, .3], foreR: t > 179.6 && t < 181.3 ? [-1.2, 0, 0] : [-1.8, 0, 0] } : POSE.shootUp());
    face(TI, 'timur', t, { squint: .9 });
    squash(TI, .22 * pulse(t, 181.45, 182.1, .06, .3));                 // рывок вверх — вытягивается
    props.webs.add(V(454.6, hang.y + 2.4, -396.2), V(454.6, 70, -396.2), { w: .035, splat: false, wob: .25, wobT: t - 181.45 });
    if (t < 176.9) { const k = E.inOutSine(P(t, 175, 1.9)); look([lerp(459.5, 459, k), 1.3, lerp(-399.5, -399, k)], [456, lerp(1.6, 2.4, k), -394.5], 46); }
    else if (t < 179.4) {     // крупно: дед смотрит вверх на героя
      const hp = headW(DE), k = E.inOutSine(P(t, 176.9, 2.5));
      look(hp.clone().add(V(lerp(1.05, .95, k), lerp(1.0, .9, k), lerp(-1.0, -.85, k))).toArray(), hp.clone().add(V(0, -.08, 0)).toArray(), lerp(32, 28, k));
    }
    else look([455.4, 4.0, -393.4], [454.6, 6.4, -396.2], 38);
    if (t > 181.4) post(o => o.comic('ВЖУХ!', 980, 260, t - 181.45, { size: .55, color: '#7ff8ff', dur: .8 }));
    fadeOut(lt, 8, .5);
    return S;
  });
  // кухня
  shot(183, 195, (lt, t) => {
    const K = kitchen.scene;
    // дед за столом, лицом к двери
    place(DE, K, [-.55, 0, -1.45], 0);
    const dp = POSE.sitChair(t);
    const point = pulse(t, 184.3, 185.9, .25, .3);                     // «Опять опоздал.» — грозит пальцем
    if (point > 0) { dp.armR = [lerp(-.6, -1.25, point), .25 * point, .15]; dp.foreR = [lerp(-.9, -.35, point), 0, 0]; dp.handR = [.18 * Math.sin(t * 9) * point, 0, 0]; dp.gripR = .9; }
    if (t > 189.4 && t < 191.0) { dp.armR = [-1.1, -.2, .1]; dp.foreR = [-.4, 0, 0]; }
    DE.pose(dp);
    const deLook = t < 186.8 ? [.9, .1] : t > 192.4 ? [.4, -.6] : [.5, 0];
    face(DE, 'ded', t, { brow: t < 186 ? -.35 : .15, smile: t > 192.6 ? 1 : 0, look: deLook, seed: 2 });
    // Тимур входит
    const tp = kf(t, [[183, [3.0, 0, .6]], [185.6, [.85, 0, .25], E.inOutSine], [186.6, [.55, 0, .25]]]);
    place(TI, K, tp, t < 185.6 ? -Math.PI / 2 - .3 : Math.PI);
    TI.pose(t < 185.6 ? POSE.walk(gait(Math.hypot(tp[0] - 3, tp[2] - .6), .55, .9)) : seq(t - 185.6, [[0, tt => POSE.stand(tt)], [1.0, tt => POSE.sitChair(tt)]], .7));
    if (t > 186.6) { TI.root.position.set(.55, 0, .25 - E.inOutSine(P(t, 186.6, .7)) * .0); }
    face(TI, 'timur', t, { brow: .3, smile: t > 186 && t < 189 ? .7 : .3, look: [-.5, 0] });
    const g = .2 + .2 * Math.sin(t * 3);
    TI.mats.hand.emissive.setRGB(.05 * g, .5 * g, .7 * g);
    kitchen.plates[0].position.x = kf(t, [[189.6, -.5], [190.6, .3, E.inOutSine]]);
    kitchen.flashLight.intensity = 3 + 25 * C.U.flash.value;
    if (t < 186.2) look([1.6, 1.5, 1.6], [0, 1.0, -1.0], 44);
    else if (t < 189.3) look([-.25, 1.4, -.95], [.55, 1.15, .3], 36);
    else if (t < 192.4) look([.3, 1.3, -.45], [-.55, 1.2, -1.45], 34);
    else if (t < 193.8) {   // крупно: дед улыбается — всё понял
      const hp = headW(DE); look(hp.clone().add(V(.25, .02, .95)).toArray(), hp.clone().add(V(0, -.06, 0)).toArray(), 30);
    }
    else { const k = E.inOutSine(P(t, 193.8, 1.2)); look([lerp(1.8, 2.3, k), lerp(1.7, 1.9, k), lerp(1.5, 2.1, k)], [0, 1.0, -.8], 40); }
    fadeIn(lt, .5); fadeOut(lt, 12, .5);
    return K;
  }, { noFlash: false });
  // финал: на шпиле башни
  shot(195, 203, (lt, t) => {
    env({ key: 1.6, rim: 1.6, rimPos: [300, 80, -900] });
    city.rain.visible = false;
    city.sky.userData.mat.uniforms.dawn.value = .45;
    TI.setSuit(true);
    city.tower.userData.tip.visible = false; U.fogDensity.value = .0008;
    place(TI, S, [40, 377.2, -440], .6);
    TI.pose({ ...POSE.spiderCrouch(t), hy: -.4, armR: [-1.4, 0, .3], foreR: [-.3, 0, 0], armL: [-.6, 0, .9] });
    face(TI, 'timur', t, { squint: 1 });
    const k = E.inOutSine(lt / 8);
    const a = lerp(.2, 1.5, k), R = lerp(3.0, 34, E.inOutCubic(k));
    look([40 + Math.sin(a) * R, 377.9 + lerp(.3, 6, k), -440 + Math.cos(a) * R], [40 - Math.sin(a) * lerp(0, 30, k), lerp(377.8, 372, k), -440 - Math.cos(a) * lerp(0, 30, k)], lerp(40, 55, k));
    C.camFill = [5, 0xffc8a0];
    fadeIn(lt, .5);
    return S;
  }, { noFlash: true });
  shot(203, 207, (lt, t) => {
    look([0, 100, 200], [0, 100, 0], 45);
    post(o => o.logo(lt, { sub: 'КОНЕЦ ПЕРВОЙ СЕРИИ' }));
    post(o => o.fill('#000', (lt - 3.5) / .5));
    return S;
  }, { noSubs: true, noFlash: true });
  // тизер
  shot(207, 216, (lt, t) => {
    const Z = lair.scene;
    place(SH, Z, [0, .02, .2], 0);
    SH.pose(POSE.sitChair(t * .5));
    SH.redEyes.visible = t > 208.2;
    SH.redEyes.children.forEach((e, i) => e.scale.setScalar(clamp((t - 208.2 - i * .06) / .15) * (1 + .3 * C.mouthOf('shadow', t))));
    lair.red.intensity = 10 + 6 * Math.sin(t * 2);
    const k = E.inOutSine(P(t, 207, 5.5));
    look([lerp(.9, .2, k), lerp(1.9, 1.8, k), lerp(5.8, 2.6, k)], [0, lerp(1.6, 1.75, k), .2], lerp(42, 30, k));
    fadeIn(lt, .8);
    post(o => o.fill('#000', (t - 212.4) / .3 * .85));
    post(o => o.title([{ text: 'ПРОДОЛЖЕНИЕ СЛЕДУЕТ…', font: '900 76px Unbounded', y: 540, color: '#ff3a3a', stroke: 14, glow: '#ff0000' }], clamp((t - 212.6) / .5)));
    post(o => o.fill('#000', (t - 215.3) / .6));
    return Z;
  }, { noFlash: true });

  /* сброс общих объектов перед каждым кадром */
  C.frameReset = t => {
    box.visible = false; carab.visible = false; hideBridgeProps();
    smoke.forEach(sp => sp.visible = false); lab.lights[2].position.set(0, 6, 9); lab.lights[2].color.set(0xff4020);
    props.spider.scale.setScalar(1);
    KR.mats.coreM.color.setRGB(3, 1.9, .75);
    updateTraffic(city, t);
  };
  return shots;
}
