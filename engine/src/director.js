// Режиссёрский набор для шотов любой серии: камера, расстановка персонажей, лица и липсинк, «кадр удара»,
// комикс-панели, вставки, титры, велосипед, дроны Тени, позы драки. Серия 1 написана до него и держит свои
// копии этих помощников в episodes/e01/shots.js; новые серии пишутся через makeDirector(C).
//
//   import { makeDirector } from 'engine/director.js';
//   export function buildShots(C) {
//     const D = makeDirector(C), { shot, look, place, face, post, S } = D, { timur: TI } = C.ch;
//     shot(0, 5, (lt, t) => { place(TI, S, [0, 0, 100], Math.PI); TI.pose(POSE.stand(t)); face(TI, 'timur', t);
//       look([0, 1.6, 104], [0, 1.4, 100], 40); return S; });
//     return D.shots;
//   }
import * as THREE from 'three';
import { E, P, kf, lerp, clamp, shake, pulse, toon, glow, mesh, noise, W, H } from './core.js';
import { POSE, seq, blend, blinkAt, gait, squash, springAt, secondary, ikArm, makeSpider } from './rig.js';
import { plume, puffTex } from './dressing.js';

export const V = (x, y, z) => new THREE.Vector3(x, y, z);
export const L2W = (x, y, z) => [40 + x, 258.82 + y, -440 + z];          // координаты лаборатории → мир
export const yawTo = (a, b) => Math.atan2(b[0] - a[0], b[2] - a[2]);    // поворот «смотреть из a на b»
export { E, P, kf, lerp, clamp, pulse, POSE, seq, blend, gait, squash, springAt, ikArm };

/* ---------- памятка по координатам мира (метры, Y — вверх) ----------
   Неоновый проспект: ось Z, x ≈ 0 (полосы ±4.5), перекрёстки каждые 80 м (z = 80k).
   Башня «Аркада»: (40, 0, −440), лаборатория — пол на 258.82 (L2W), шпиль/молниеотвод ≈ 378.
   Северный мост: полотно x 300…640, z −412…−388 (центр −400), пилоны x 390 и 550, перила z −388.5/−411.5.
   Крыши у моста (для прыжков): (305.5, 74.1, −387); река Вельга — вода на y −30, x 330…610.
   Кухня деда — отдельная сцена C.kitchen.scene; логово Тени — C.lair.scene; кабина №42 — C.cab.scene. */

/* ---------- чёрный дрон-паук Тени (рой «Тенета») ---------- */
export function makeDrone(scale = 4.5) {
  const d = makeSpider({ scale });
  d.traverse(m => {
    if (!m.isMesh) return;
    if (m.material.isMeshBasicMaterial && m.material.side !== THREE.BackSide) m.material = glow(0xff1a1a, 3.5);
    else if (m.material.isMeshToonMaterial) m.material = toon(0x111216);
  });
  return d;
}

/* ---------- позы драки (Тимур и тяжёлый противник) ---------- */
export const FIGHT = {
  guard: tt => ({ ...POSE.stand(tt), spine: [.18, 0, 0], head: [-.12, 0, 0], armL: [-1.05, -.2, .45], foreL: [-1.85, 0, 0], armR: [-.85, -.2, .4], foreR: [-1.95, 0, 0], gripL: .9, gripR: .9,
    legL: [-.35, 0, .2], legR: [.3, 0, .2], shinL: [.4, 0, 0], shinR: [.25, 0, 0], hy: -.13 + .01 * Math.sin(tt * 9) }),
  leanBack: { hy: -.42, spine: [-.85, 0, .05], chest: [-.25, 0, 0], head: [.55, 0, 0], armL: [.7, 0, 1.25], armR: [.6, 0, 1.35], foreL: [-.3, 0, 0], foreR: [-.3, 0, 0],
    legL: [-.75, 0, .25], legR: [-.35, 0, .2], shinL: [1.5, 0, 0], shinR: [1.1, 0, 0], footL: [-.3, 0, 0], gripL: .2, gripR: .2 },
  load: { ...POSE.crouch(), spine: [.35, 0, 0], head: [-.3, 0, 0], armL: [.6, 0, .5], armR: [.6, 0, .5], foreL: [-.4, 0, 0], foreR: [-.4, 0, 0] },
  dropKick: { spine: [-.55, 0, 0], head: [.45, 0, 0], armL: [.9, 0, .8], armR: [.9, 0, .8], foreL: [-.5, 0, 0], foreR: [-.5, 0, 0],
    legL: [-1.55, 0, .08], legR: [-1.45, 0, .08], shinL: [.05, 0, 0], shinR: [.15, 0, 0], footL: [.5, 0, 0], footR: [.5, 0, 0], hy: -.05 },
  kickR: { spine: [-.25, -.2, 0], armL: [-.6, 0, .9], armR: [-.2, 0, .9], foreL: [-1.2, 0, 0], foreR: [-1.0, 0, 0], legR: [-1.7, 0, .1], shinR: [.05, 0, 0], footR: [.4, 0, 0], legL: [.15, 0, .1], shinL: [.3, 0, 0], hy: -.05 },
  tuck: POSE.flip(0),
  zip: { ...POSE.swing(0), armR: [-1.75, 0, .05], foreR: [0, 0, 0], handR: [-.6, 0, 0], spiderR: 1, gripR: .9, spine: [.2, 0, 0] },
  shootBoth: { spine: [.15, 0, 0], armL: [-1.55, .25, .05], armR: [-1.55, -.25, .05], foreL: [0, 0, 0], foreR: [0, 0, 0], handL: [-1, 0, 0], handR: [-1, 0, 0], spiderL: 1, spiderR: 1,
    legL: [-.45, 0, .2], legR: [.35, 0, .2], shinL: [.5, 0, 0], shinR: [.3, 0, 0], hy: -.12 },
  eat: tt => ({ ...POSE.sitChair(tt), armR: [-.9, .3, .2], foreR: [-1.9 + .5 * Math.max(0, Math.sin(tt * 6)), 0, 0], gripR: .8, head: [.25 - .1 * Math.max(0, Math.sin(tt * 6)), 0, 0], spine: [.25, 0, 0] }),
  tired: tt => ({ ...POSE.stand(tt), hy: -.08, spine: [.45, 0, 0], head: [.3, 0, 0], armL: [-.2, 0, .1], armR: [-.2, 0, .1], foreL: [-.3, 0, 0], foreR: [-.3, 0, 0], legL: [-.3, 0, .25], legR: [.2, 0, .25], shinL: [.5, 0, 0], shinR: [.4, 0, 0] }),
};
export const HEAVY = {
  windUp: { grip: 1, spine: [.1, .55, 0], chest: [0, .35, 0], head: [-.1, -.4, 0], armR: [-.55, .35, 1.25], foreR: [-2.0, 0, 0], armL: [-1.0, 0, .45], foreL: [-1.3, 0, 0],
    legL: [-.45, 0, .18], legR: [.35, 0, .18], shinL: [.35, 0, 0], shinR: [.15, 0, 0], hy: -.12 },
  swing: k => ({ grip: 1, spine: [lerp(.1, .5, k), lerp(.55, -.45, k), 0], chest: [0, lerp(.35, -.25, k), 0], head: [lerp(-.1, .3, k), lerp(-.4, .35, k), 0],
    armR: [lerp(-.55, -1.25, k), lerp(.35, -.2, k), lerp(1.25, .1, k)], foreR: [lerp(-2.0, -.1, k), 0, 0], armL: [lerp(-1.0, .4, k), 0, lerp(.45, .7, k)], foreL: [-1.0, 0, 0],
    legL: [lerp(-.45, -.8, k), 0, .18], legR: [lerp(.35, .55, k), 0, .18], shinL: [lerp(.35, .7, k), 0, 0], shinR: [.15, 0, 0], hy: lerp(-.12, -.22, k) }),
  hitBack: tt => ({ grip: .2, spine: [-.55, .15 * Math.sin(tt * 9), 0], chest: [-.2, 0, 0], head: [-.55, 0, 0], armL: [-1.7 + .3 * Math.sin(tt * 13), 0, .95], armR: [-1.5 + .3 * Math.sin(tt * 11), 0, 1.05],
    foreL: [-.3, 0, 0], foreR: [-.4, 0, 0], legL: [-.75, 0, .25], legR: [-.25, 0, .25], shinL: [.35, 0, 0], shinR: [.2, 0, 0], footL: [.5, 0, 0], footR: [.5, 0, 0], hy: -.1 }),
  slump: tt => ({ grip: .1, hy: -.86, spine: [.35, 0, .15], chest: [.1, 0, 0], head: [.5 + .03 * Math.sin(tt * 2), .25, .2], armL: [.1, 0, .6], armR: [.2, 0, .45], foreL: [-.35, 0, 0], foreR: [-.2, 0, 0],
    legL: [-1.45, 0, .3], legR: [-1.25, 0, .4], shinL: [.3, 0, 0], shinR: [.55, 0, 0], footL: [-.4, 0, 0], footR: [-.3, 0, 0] }),
};

export function makeDirector(C) {
  const { city, lab, cab, ch, props, camera: cam, U } = C;
  const { timur: TI, ded: DE, kronov: KR } = ch;
  const S = city.scene;
  const shots = [];
  const resets = [];
  C.frameReset = t => resets.forEach(f => f(t));

  const D = { S, shots, V, L2W, yawTo };
  /** шот: [t0, t1) в сюжетном времени; run(lt, t) выставляет кадр и возвращает сцену (S, C.kitchen.scene, …).
   *  o: { noSubs, noFlash, flashK, hideBolts } */
  D.shot = (t0, t1, run, o = {}) => shots.push({ t0, t1, run, ...o });
  /** сброс общих объектов перед каждым кадром (то, что шоты включают сами) */
  D.onReset = f => resets.push(f);
  D.post = f => C.post.push(f);
  const post = D.post;

  /* ---- камера ---- */
  D.look = (pos, at, fov = 45, roll = 0) => {
    cam.position.set(...pos); cam.up.set(0, 1, 0); cam.lookAt(...at);
    const dist = Math.hypot(pos[0] - at[0], pos[1] - at[1], pos[2] - at[2]);
    if (fov <= 38 && dist < 8) C.dof = { focus: dist, aperture: .0007 };    // крупный план — глубина резкости
    if (roll) cam.rotateZ(roll);
    cam.fov = fov; cam.updateProjectionMatrix();
  };
  /** проезд камеры: ключи [[t, pos, at, fov], ...] */
  D.move = (t, keys, ease = E.inOutSine) => {
    let i = 0; while (i < keys.length - 2 && t > keys[i + 1][0]) i++;
    const a = keys[i], b = keys[Math.min(i + 1, keys.length - 1)], k = ease(P(t, a[0], Math.max(1e-6, b[0] - a[0])));
    const L3 = (p, q) => p.map((v, j) => lerp(v, q[j], k));
    D.look(L3(a[1], b[1]), L3(a[2], b[2]), lerp(a[3] ?? 45, b[3] ?? 45, k));
  };
  D.shk = (t, a, f = 9) => shake(t, a, f);
  D.addv = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  /* «кадр удара»: вспышка на 1–2 кадра + толчок камеры */
  D.impact = (t, t0, o = {}) => {
    const dt = t - t0;
    if (dt >= 0 && dt < .045) post(ov => ov.fill(o.color || '#ffffff', .75));
    else if (dt >= .045 && dt < .09) post(ov => ov.fill('#000000', .35));
    if (dt >= 0 && dt < .6) {
      const kick = Math.exp(-dt * 10);
      cam.fov *= 1 - (o.zoom ?? .12) * kick; cam.updateProjectionMatrix();
      const sh = D.shk(t, (o.shake ?? .12) * kick, 22); cam.position.x += sh[0]; cam.position.y += sh[1]; cam.position.z += sh[2];
    }
  };

  /* ---- персонажи ---- */
  D.place = (c, parent, pos, yaw = 0) => { parent.add(c.root); c.root.visible = true; c.root.position.set(...pos); c.root.rotation.set(0, yaw, 0); };
  D.orient = (c, up, fwd) => {
    const u = up.clone().normalize(), f = fwd.clone().sub(u.clone().multiplyScalar(fwd.dot(u))).normalize();
    const r = new THREE.Vector3().crossVectors(u, f).normalize();
    c.root.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(r, u, f));
  };
  const faceHooks = new Map();
  D.onFace = (c, f) => faceHooks.set(c, f);
  /** лицо и «жизнь»: липсинк по голосу (who — персонаж из dialogue.json), моргание, дыхание, взгляд.
   *  o: { brow, smile, squint, wide, look:[x,y], dim (визор Кронова), energy (вторичная анимация), seed } */
  /** повернуть голову к точке (взгляд на собеседника/событие): поверх позы, k — сила (0…1) */
  const _q = new THREE.Quaternion();
  D.attendAngles = (c, at) => {
    c.root.updateMatrixWorld(true);
    const h = c.J.neck.getWorldPosition(V(0, 0, 0)), tg = at.isVector3 ? at : V(...at);
    const d = tg.clone().sub(h).applyQuaternion(c.root.getWorldQuaternion(_q).invert());
    const yaw = clamp(Math.atan2(d.x, d.z) - c.J.spine.rotation.y - c.J.chest.rotation.y, -1.25, 1.25);
    const pitch = clamp(Math.atan2(-d.y, Math.hypot(d.x, d.z)) - c.J.spine.rotation.x * .5, -.6, .6);
    return [yaw, pitch];
  };
  D.attend = (c, at, k = 1) => {
    const [yaw, pitch] = D.attendAngles(c, at);
    c.J.neck.rotation.y += yaw * .35 * k; c.J.head.rotation.y += yaw * .55 * k;
    c.J.head.rotation.x = lerp(c.J.head.rotation.x, pitch * .8, .75 * k);
  };
  /** лицо и «жизнь»: …, o.at — точка, куда смотреть (голова поворачивается), o.atK — сила поворота */
  D.face = (c, who, t, o = {}) => {
    faceHooks.get(c)?.(t);
    const sd = o.seed ?? 0;
    c.J.chest.scale.set(1 + .008 * Math.sin(t * 2.1 + sd), 1 + .012 * Math.sin(t * 2.1 + sd), 1 + .018 * Math.sin(t * 2.1 + sd));
    const look = o.at ? [noise(t * .8 + sd * 7) * .1, noise(t * .7 + sd * 7 + 40) * .07] : [noise(t * .8 + sd * 7) * .35, noise(t * .7 + sd * 7 + 40) * .2];
    c.setFace({ mouth: C.mouthOf(who, t) * (o.mk ?? 1), shape: C.shapeOf(who), fric: C.fricOf(who), blink: o.noBlink ? 0 : blinkAt(t, sd), look, ...o });
    secondary(c, t, o.energy ?? .2);
    if (o.at) D.attend(c, o.at, o.atK ?? 1);
  };
  D.handW = (c, s = 'R') => { c.root.updateMatrixWorld(true); return c.J['hand' + s].localToWorld(V(0, -.09 * c.d.k, 0)); };
  D.headW = c => { c.root.updateMatrixWorld(true); return c.J.head.localToWorld(V(0, .16 * c.d.k, .1)); };
  D.footW = (c, s = 'R') => { c.root.updateMatrixWorld(true); return c.J['foot' + s].localToWorld(V(0, -.05, 0)); };

  /* ---- свет и окружение ---- */
  D.rimOn = (target, color = 0x9feaff, k = 2.4) => { C.rim = { target: V(...target), color, k }; };
  D.env = o => {                               // ночной город: ключевой/контровой свет, подсветка
    city.key.intensity = o.key ?? 1.4; city.rim.intensity = o.rim ?? 1.2;
    if (o.rimPos) city.rim.position.set(...o.rimPos);
    if (o.fill) { city.fill.position.set(...o.fill[0]); city.fill.intensity = o.fill[1] * .2; city.fill.color.set(o.fill[2] ?? 0x55e6ff); }
  };
  D.labLights = (k = 1, red = 0) => { lab.lights[0].intensity = 45 * k; lab.lights[1].intensity = 25 * k; lab.lights[2].intensity = 70 * red; };
  /** лаборатория: без дождя, свет, капсулы с «Арахнами» (o.broken — разбитые капсулы после серии 1) */
  D.labBase = (t, o = {}) => {
    city.rain.visible = false;
    D.env({ key: .35, rim: .5 });
    D.labLights(o.lights ?? 1, o.red ?? 0);
    lab.capsules.forEach((c, i) => {
      c.spider.userData.anim(t + i, 0, .2); c.spider.position.y = 2.1 + Math.sin(t * 1.5 + i) * .12; c.spider.rotation.y = Math.sin(t * .4 + i) * .6;
      c.glass.visible = !o.broken; c.liquid.visible = !o.broken; c.spider.visible = !o.broken;
    });
    lab.doors.forEach((d, i) => { d.visible = true; const sd = i ? 1 : -1;
      if (o.broken) { d.position.set(sd * 7.6, .4, 3.75); d.rotation.set(-1.57, sd * .4, sd * .2); } else { d.position.set(sd * 1.6, 3.5, 12.75); d.rotation.set(0, 0, 0); } });
    if (o.broken) { lab.main.spider.visible = false; lab.core.visible = false; lab.shards.update(2.4, lab.capsules.map(c => V(c.x, 2.5 * c.s, c.z))); }
    else lab.core.visible = true;
  };

  /* ---- 2D-слой ---- */
  D.fadeIn = (lt, d = .5, col = '#000') => post(o => o.fill(col, 1 - lt / d));
  D.fadeOut = (lt, t1, d = .5, col = '#000') => post(o => o.fill(col, (lt - (t1 - d)) / d));
  /** комикс-надпись: comic('БАМ!', x, y, t - t0, { size, color, rot, dur }) */
  D.comic = (text, x, y, dt, o) => post(ov => ov.comic(text, x, y, dt, o));
  /** плашка-подпись: caption('Соседняя крыша…', x, y, t - t0, { dur, bg }) */
  D.caption = (text, x, y, dt, o) => post(ov => ov.caption(text, x, y, dt, o));
  D.title = (lines, a) => post(ov => ov.title(lines, a));
  D.logo = (lt, sub) => post(ov => ov.logo(lt, { sub }));
  D.speedLines = (k, t) => post(ov => ov.speedLines(k, t));
  D.lensDrops = (t, k) => post(ov => ov.lensDrops(t, k));

  /* ---- комикс-панель: второй ракурс поверх кадра ---- */
  const panelCams = [new THREE.PerspectiveCamera(30, 1, .05, 3000), new THREE.PerspectiveCamera(30, 1, .05, 3000)];
  D.panel = (i, k, rect, scene, pos, at, fov = 30, roll = 0, frame = null) => {
    if (k <= 0) return;
    const [x, y, w, h] = rect, s = E.outBack(clamp(k));
    const ws = Math.round(w * s), hs = Math.round(h * s), px = Math.round(x + (w - ws) / 2), py = Math.round(y + (h - hs) / 2);
    const pc = panelCams[i]; pc.position.set(...pos); pc.up.set(0, 1, 0); pc.lookAt(...at); if (roll) pc.rotateZ(roll); pc.fov = fov;
    (C.panels = C.panels || []).push({ x: px, y: py, w: ws, h: hs, scene, cam: pc });
    post(o => frame ? frame(o, px, py, ws, hs) : o.panelFrame(px, py, ws, hs));
  };
  /** вставка «дед на связи» (кабина автобуса, рамка видеозвонка) */
  D.cabCall = (t, k, o = {}) => {
    if (k <= 0) return;
    D.place(DE, cab.scene, [0, .05, -.1], 0);
    const p = POSE.sitChair(t); p.armL = [-1.1, .1, .1]; p.armR = [-1.1, .1, .1]; p.foreL = [-.5, 0, 0]; p.foreR = [-.5, 0, 0];
    p.head = [.05, -.25 + .08 * Math.sin(t * .7), 0];
    DE.pose(p); D.face(DE, 'ded', t, { brow: .35, seed: 2, look: [.6, 0], ...o });
    cab.tex.offset.x = -t * .25; cab.wheel.rotation.z = Math.sin(t * .6) * .2;
    cab.alarm.intensity = 0; cab.dash.intensity = 6; cab.warm.intensity = 4;
    cab.cam.position.set(.55, 1.42, 1.35); cab.cam.lookAt(.02, 1.36, 0);
    const x = 1340, y = 60, w = 520, h = 360, s = E.outBack(clamp(k));
    const ws = Math.round(w * s), hs = Math.round(h * s);
    C.inset = { x: x + (w - ws) / 2 | 0, y: y + (h - hs) / 2 | 0, w: ws, h: hs, scene: cab.scene, cam: cab.cam };
    post(ov => ov.callFrame(x + (w - ws) / 2, y + (h - hs) / 2, ws, hs, 1, t));
  };

  /* ---- велосипед (IK: ладони на руле) ---- */
  D.rideBike = (t, x, z, o = {}) => {
    const b = props.bike; b.visible = true; b.position.set(x, o.y || 0, z); b.rotation.set(o.pitch || 0, Math.PI + (o.yaw || 0), o.lean || 0);
    b.userData.wheels.forEach(w => w.rotation.x = -t * 13 / .35);
    b.add(TI.root); TI.root.visible = true; TI.root.position.set(0, .2, -.02); TI.root.rotation.set(0, 0, 0);
    TI.pose(o.pose || POSE.bike(t));
    if (!o.freeHands) {
      b.updateMatrixWorld(true);
      for (const [sd, sx] of [['L', 1], ['R', -1]]) if (!(o.freeL && sd === 'L')) ikArm(TI, sd, b.localToWorld(V(sx * .26, .92, .43)), b.localToWorld(V(sx * .45, -.5, -1)).sub(b.position));
    }
    if (!(o.y > .05)) { const back = V(0, 0, -1).applyQuaternion(b.quaternion).setY(0).normalize(); props.spray.update(b.localToWorld(V(0, .05, -.6)), back, t, 1); }
  };

  /* ---- паутина и эффекты ---- */
  /** нить из ладони: web(TI, 'R', [x,y,z], t, t0) — выстреливает за .15 с */
  D.web = (c, side, to, t, t0, o = {}) => { if (t < t0) return; props.webs.add(D.handW(c, side), to.isVector3 ? to : V(...to), { k: E.outCubic(P(t, t0, o.dur ?? .15)), w: o.w ?? .045, wob: o.wob ?? .3, wobT: t - t0, ...o }); };
  D.sparks = (pos, dt, o) => props.sparks.burst(pos.isVector3 ? pos : V(...pos), dt, o);
  D.ring = (pos, r, a, color = 0xffffff) => props.rings.add(pos.isVector3 ? pos : V(...pos), r, a, cam, color);
  /** паучье чутьё: мир синеет и замедляется (k 0..1) */
  D.sense = (t, k, t0) => { U.sense.value = k * .8; U.rainTime.value = t0 + (t - t0) * lerp(1, .1, k); };

  /* ---- дроны Тени ---- */
  const drones = Array.from({ length: 6 }, () => { const d = makeDrone(3.2); S.add(d); d.visible = false; return d; });
  D.drones = drones;
  /** дрон i в точке pos, смотрит в сторону yaw; walk — фаза ходьбы лапами (0 — стоит), hover — парит */
  D.drone = (i, pos, yaw = 0, t = 0, o = {}) => {
    const d = drones[i]; d.visible = true; if (o.parent && d.parent !== o.parent) o.parent.add(d);
    d.position.set(...pos); d.rotation.set(o.pitch || 0, yaw, o.roll || 0); d.scale.setScalar(o.scale ?? 1);
    d.userData.anim(t, o.walk ?? 1, o.amp ?? .3);
  };
  D.onReset(() => drones.forEach(d => { d.visible = false; if (d.parent !== S) S.add(d); }));

  /* ---- выхлоп ранца Кронова и дым повреждений ---- */
  const exhaustT = puffTex('150,140,135', .7), dmgT = puffTex('30,28,30', .9);
  const krEx = [0, 1].map(() => plume(S, 6, exhaustT, { rise: 1.6, grow: 2.2, size: .5, alpha: .35, speed: .9, wobble: .2 }));
  const krDmg = plume(S, 10, dmgT, { rise: 7, grow: 3, size: 1.2, alpha: .6, speed: .3, wobble: .6, wind: 2 });
  /** включить эффекты костюма Кронова на этот кадр: o.damaged — дым и искры, o.core — светящееся ядро в груди */
  D.kronovFX = (t, o = {}) => {
    if (KR.root.parent !== S) return;
    KR.root.updateMatrixWorld(true);
    KR.arachna.visible = !!o.core;
    [1, -1].forEach((sx, i) => krEx[i].update(KR.J.spine.localToWorld(V(sx * .1 * KR.d.k, .27 * KR.d.k, -.5 * KR.d.k)), t + i * .3, o.damaged ? 0 : 1));
    if (o.damaged) krDmg.update(KR.J.spine.localToWorld(V(0, .35 * KR.d.k, .1)), t, 1); else krDmg.hide();
  };
  D.onReset(() => { krEx.forEach(p => p.hide()); krDmg.hide(); KR.arachna.visible = false; });

  /** стандартная заставка серии: паутина + логотип + подпись (используйте в шоте сразу после холодного начала) */
  D.titleCard = (lt, sub) => { D.look([0, 100, 200], [0, 100, 0], 45); D.logo(lt, sub); };

  return D;
}
