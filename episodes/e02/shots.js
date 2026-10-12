// Серия 2 «Сигнал» — аниматик: все сцены сценария (STORY.md) поставлены с камерой, персонажами, дронами,
// эффектами и комикс-надписями. Время — сюжетное, как в dialogue.json и audio/cues.py.
// Помощники — engine/src/director.js (look, move, place, face, web, drone, impact, comic, caption…).
import * as THREE from 'three';
import { toon, glow, mesh, noise } from 'engine/core.js';
import { makeDirector, FIGHT, V, L2W, yawTo, E, P, kf, lerp, clamp, pulse, POSE, seq, blend, gait, squash, springAt, ikArm } from 'engine/director.js';

export function buildShots(C) {
  const D = makeDirector(C);
  const { S, shot, look, move, place, face, post, impact, comic, caption, web, drone, handW, headW, fadeIn, fadeOut, shk, addv, rimOn, env } = D;
  const { city, lab, kitchen, lair, ch, props, U } = C;
  const { timur: TI, ded: DE, vera: VE, shadow: SH } = ch;
  const K = kitchen.scene, Z = lair.scene;

  /* ---------- реквизит серии ---------- */
  // ядро «Арахны» в руке Тени
  const core = new THREE.Group(); mesh(new THREE.CylinderGeometry(.06, .06, .22, 16), glow(0x5ff6ff, 3.2), { outline: .01, parent: core });
  const coreL = new THREE.PointLight(0x5ff6ff, 6, 4, 1.4); core.add(coreL);
  // дедов карабин на лямке рюкзака (после глушилки — светится бирюзой)
  const carabM = toon(0xd6dae2, { emissive: 0x30343c });
  const carab = mesh(new THREE.TorusGeometry(.045, .011, 8, 20), carabM, { scale: [.7, 1.2, 1], outline: .004 });
  const chip = mesh(new THREE.BoxGeometry(.03, .02, .012), glow(0x3ff0ff, 3), { pos: [.03, 0, 0], outline: false, parent: carab });
  // коробка доставки
  const box = mesh(new THREE.BoxGeometry(.42, .3, .32), toon(0xc9a06a), { outline: .01 });
  mesh(new THREE.BoxGeometry(.44, .05, .1), toon(0x15b9a8), { pos: [0, .13, 0], outline: false, parent: box });
  // водонапорный бак на крыше у моста
  const tank = new THREE.Group(); tank.position.set(279, 74, -372); S.add(tank);
  mesh(new THREE.CylinderGeometry(2.4, 2.4, 4.2, 18), toon(0x6b4a3a), { pos: [0, 4.6, 0], outline: .05, parent: tank });
  mesh(new THREE.ConeGeometry(2.7, 1.3, 18), toon(0x2a2e38), { pos: [0, 7.35, 0], outline: .05, parent: tank });
  for (const [x, z] of [[1.6, 1.6], [-1.6, 1.6], [1.6, -1.6], [-1.6, -1.6]]) mesh(new THREE.CylinderGeometry(.14, .14, 2.5, 6), toon(0x2a2e38), { pos: [x, 1.25, z], outline: .02, parent: tank });
  // тарелки, крышка и записка «Ешь, курьер» на кухне
  const extraPlates = [0, 1].map(i => { const p = mesh(new THREE.CylinderGeometry(.22, .16, .04, 24), toon(0xffffff), { outline: .008, parent: K }); p.position.set(.85, .87 + i * .045, -.35); return p; });
  const lid = mesh(new THREE.SphereGeometry(.2, 18, 10, 0, Math.PI * 2, 0, Math.PI / 2), toon(0xb8bec8), { scale: [1, .55, 1], outline: .008, parent: K }); lid.position.set(.5, .87, -.5);
  const noteTex = (() => { const c = document.createElement('canvas'); c.width = 256; c.height = 160; const g = c.getContext('2d');
    g.fillStyle = '#f4ecd2'; g.fillRect(0, 0, 256, 160); g.fillStyle = '#2a3a8a'; g.font = 'italic 600 40px Rubik'; g.fillText('Ешь,', 40, 70); g.fillText('курьер', 60, 125);
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t; })();
  const note = new THREE.Mesh(new THREE.PlaneGeometry(.16, .1), new THREE.MeshBasicMaterial({ map: noteTex })); note.rotation.x = -Math.PI / 2; note.rotation.z = .3; note.position.set(.25, .86, -.3); K.add(note);
  // монитор логова с кадром Веры (тизер)
  const veraTex = (() => { const c = document.createElement('canvas'); c.width = 512; c.height = 320; const g = c.getContext('2d');
    g.fillStyle = '#0a0204'; g.fillRect(0, 0, 512, 320); g.strokeStyle = 'rgba(255,40,40,.35)'; for (let y = 0; y < 320; y += 4) { g.beginPath(); g.moveTo(0, y); g.lineTo(512, y); g.stroke(); }
    g.fillStyle = '#ff3a3a'; g.beginPath(); g.arc(256, 120, 48, 0, 7); g.fill(); g.fillRect(196, 168, 120, 130);          // силуэт с пучком
    g.beginPath(); g.arc(256, 66, 26, 0, 7); g.fill();
    g.font = '700 30px Rubik'; g.fillText('ОБЪЕКТ: ЛИС В. · ПОМОГАЕТ НОСИТЕЛЮ', 18, 306);
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t; })();
  const veraScreen = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 1.62), new THREE.MeshBasicMaterial({ map: veraTex, color: new THREE.Color(1.6, 1.6, 1.6) })); veraScreen.position.set(0, 3.0, -3.7); Z.add(veraScreen);

  D.onReset(() => {
    core.visible = false; carab.visible = false; chip.visible = false; box.visible = false; tank.visible = false;
    extraPlates.forEach(p => p.visible = false); lid.visible = false; note.visible = false; veraScreen.visible = false;
    carabM.emissive.setHex(0x30343c);
  });
  /** карабин на лямке у груди (после 178.5 — с глушилкой и светится) */
  const strapCarab = (t, glowK = 0) => {
    TI.J.chest.add(carab); carab.visible = true; carab.position.set(.1 * TI.d.k, .12 * TI.d.k, .14 * TI.d.k); carab.rotation.set(0, 0, .2);
    chip.visible = t > 178.5; carabM.emissive.setRGB(.19 + .1 * glowK, .2 + .7 * glowK, .24 + .9 * glowK);
  };

  /* ======================= ХОЛОДНОЕ НАЧАЛО: логово ======================= */
  const lairBase = (t, o = {}) => {
    place(SH, Z, [0, .02, .2], 0);
    const lift = E.inOutCubic(P(t, o.liftAt ?? 99, .9));
    SH.pose({ ...POSE.sitChair(t * .5), armR: [lerp(-.6, -2.2, lift), lerp(0, .2, lift), .15], foreR: [lerp(-.9, -.6, lift), 0, 0], handR: [lerp(0, -.4, lift), 0, 0], gripR: .8 });
    face(SH, 'shadow', t, { seed: 4 });
    if (o.core !== false) { SH.J.handR.add(core); core.visible = true; core.position.set(0, -.1, .06); core.rotation.set(Math.PI / 2, 0, 0); coreL.intensity = 4 + 2 * Math.sin(t * 5); }
    SH.redEyes.visible = true;
    SH.redEyes.children.forEach((e, i) => e.scale.setScalar(clamp((t - (o.eyesAt ?? 0) - i * .06) / .15) * (1 + .3 * C.mouthOf('shadow', t))));
    lair.red.intensity = 10 + 6 * Math.sin(t * 2);
  };
  shot(0, 6, (lt, t) => {
    lairBase(t, { eyesAt: 99 });
    SH.redEyes.visible = false;
    move(t, [[0, [.9, 1.9, 6.4], [0, 1.6, .2], 46], [6, [.4, 1.8, 3.6], [0, 1.65, .2], 36]]);
    fadeIn(lt, 1.0);
    return Z;
  }, { noFlash: true });
  shot(6, 11.6, (lt, t) => {
    lairBase(t, { eyesAt: 6.2, liftAt: 9.4 });
    // на полу загораются глаза дронов
    for (let i = 0; i < 5; i++) drone(i, [-1.6 + i * .8, 0, 2.2 + (i % 2) * .7], Math.PI, t, { parent: Z, scale: .55, walk: 0 });
    D.drones.forEach((d, i) => d.traverse(m => { if (m.isMesh && m.material.isMeshBasicMaterial) m.visible = t > 9.6 + i * .12; }));
    if (t < 9.0) { const hp = headW(SH); look(hp.clone().add(V(.15, .05, 1.25)).toArray(), hp.toArray(), 30); }
    else { const k = E.inOutSine(P(t, 9.0, 2.6)); look([lerp(.3, 0, k), lerp(1.4, .5, k), lerp(4.6, 5.4, k)], [0, lerp(1.2, .3, k), 2], 40); }
    return Z;
  }, { noFlash: true });
  shot(11.6, 16.5, (lt, t) => {
    lairBase(t, { eyesAt: 6.2, liftAt: 9.4 });
    for (let i = 0; i < 5; i++) {
      const z = 2.2 + (i % 2) * .7 + Math.max(0, t - 11.7 - i * .15) * 3.2;
      drone(i, [-1.6 + i * .8 + Math.sin(t * 3 + i) * .15, 0, z], 0, t * 3, { parent: Z, scale: .55, walk: 1 });
    }
    look([.2, .3, 8.6], [0, 1.0, 0], 50);
    fadeOut(lt, 4.9, .6);
    return Z;
  }, { noFlash: true });
  shot(16.5, 20.5, (lt, t) => {
    D.titleCard(lt, 'СЕРИЯ 2 · СИГНАЛ');
    post(o => o.fill('#000', (lt - 3.5) / .5));
    return S;
  }, { noSubs: true, noFlash: true });

  /* ======================= СЦЕНА 1. Кухня ======================= */
  const kitchenBase = (t, o = {}) => {
    place(DE, K, [-.55, 0, -1.45], 0);
    const dp = POSE.sitChair(t);
    DE.pose(o.dedPose ? o.dedPose(dp) : dp);
    face(DE, 'ded', t, { seed: 2, ...o.dedFace });
    kitchen.flashLight.intensity = 3 + 25 * U.flash.value;
    extraPlates.forEach(p => p.visible = true);
  };
  shot(20.5, 35, (lt, t) => {
    kitchenBase(t, { dedPose: p => ({ ...p, head: [.05, t < 27.6 ? .55 : .1, 0] }), dedFace: { look: t < 27.6 ? [.9, .1] : [.5, -.3], brow: t > 28.2 ? .4 : 0, smile: t > 29.6 ? .4 : 0 } });
    place(TI, K, [.55, 0, .25], Math.PI);
    TI.pose(FIGHT.eat(t));
    face(TI, 'timur', t, { brow: .2, smile: t > 32.4 ? .9 : .3, look: [0, -.6], mk: 1 });
    strapCarab(t);
    if (t < 25.0) look([1.9, 1.6, 1.7], [0, .95, -.75], 42);                      // общий: внук ест, дед — в телевизор
    else if (t < 27.6) { const tv = C.kitchenD.tvPos; look([tv.x + .05, tv.y + .26, tv.z + .72], [tv.x, tv.y + .24, tv.z], 40); }
    else if (t < 32.4) { const hp = headW(DE); look(hp.clone().add(V(.35, .02, 1.05)).toArray(), hp.clone().add(V(0, -.06, 0)).toArray(), 32); }
    else { const hp = headW(TI); look(hp.clone().add(V(-.35, .02, -1.05)).toArray(), hp.clone().add(V(0, -.08, 0)).toArray(), 32); }
    fadeIn(lt, .5);
    if (t > 23 && t < 27) comic('ЧАВК!', 1300, 300, t - 23.2, { size: .45, color: '#ffd23d', dur: .8 });
    return K;
  }, { noFlash: false });
  shot(35, 48, (lt, t) => {
    const reach = pulse(t, 41.4, 46.2, .5, .5);
    kitchenBase(t, {
      dedPose: p => reach > 0 ? { ...p, armR: [lerp(-.6, -1.35, reach), lerp(0, .35, reach), .15], foreR: [lerp(-.9, -.35, reach), 0, 0], gripR: .6, spine: [lerp(.08, .25, reach), 0, 0] } : p,
      dedFace: { look: [.6, .2], brow: t < 41 ? .3 : .1, smile: t > 43.5 ? .7 : 0 },
    });
    // Тимур встаёт и подходит к деду
    const tp = kf(t, [[36.6, [.55, 0, .25]], [38.6, [.05, 0, -.45], E.inOutSine]]);
    place(TI, K, tp, t < 36.6 ? Math.PI : lerp(Math.PI, Math.PI + 1.25, E.inOutSine(P(t, 36.6, 1.6))));
    TI.pose(t < 36.6 ? FIGHT.eat(t) : t < 38.6 ? blend(POSE.stand(t), POSE.walk(gait(Math.hypot(tp[0] - .55, tp[2] - .25), .55, .9)), clamp((t - 36.8) * 3)) : POSE.stand(t));
    face(TI, 'timur', t, { brow: .25, smile: t > 44.4 ? .8 : .2, look: t > 41 ? [-.4, -.4] : [-.3, 0] });
    strapCarab(t);
    if (reach > 0) { carab.updateMatrixWorld(true); const c = carab.getWorldPosition(V(0, 0, 0)); const hw = D.handW(DE, 'R');
      ikArm(DE, 'R', hw.clone().lerp(c.add(V(0, -.02, -.04)), reach), V(.3, -1, -.2)); }
    if (t < 38.6) look([1.8, 1.55, .9], [-.1, 1.05, -.7], 40);
    else if (t < 41.4) { const hp = headW(TI); look(hp.clone().add(V(-.9, .0, -.55)).toArray(), hp.clone().add(V(0, -.1, 0)).toArray(), 34); }
    else if (t < 44.4) { carab.updateMatrixWorld(true); const c = carab.getWorldPosition(V(0, 0, 0)); look(c.clone().add(V(1.15, .3, -.75)).toArray(), c.clone().add(V(-.2, -.05, -.25)).toArray(), 34); }   // рука деда на карабине внука
    else { const k = E.inOutSine(P(t, 44.4, 3.6)); look([lerp(1.2, 1.6, k), lerp(1.4, 1.6, k), lerp(-.2, .6, k)], [-.25, 1.15, -.95], 38); }
    fadeOut(lt, 13, .5);
    return K;
  });

  /* ======================= СЦЕНА 2. Проспект: цена силы ======================= */
  // траектория: качается на нитях над проспектом → нить рвётся на 56.9 → падает на щит «БЫСТРО» (x −40, z 200)
  const flyPts = [[48.4, [6, 92, 362]], [49.6, [-3, 80, 340]], [50.8, [5, 94, 318]], [52.0, [-4, 82, 296]], [53.2, [6, 96, 274]], [54.4, [-5, 84, 252]], [55.6, [3, 97, 232]], [56.9, [-6, 101, 216]]];
  const flyCurve = new THREE.CatmullRomCurve3(flyPts.map(p => V(...p[1])), false, 'centripetal');
  const BOARD = [-39.6, 83.9, 200.4];
  const flyAt = t => {
    if (t <= 56.9) { const ts = flyPts.map(p => p[0]); const tt = clamp(t, ts[0], ts[ts.length - 1]); let i = 0; while (i < ts.length - 2 && tt > ts[i + 1]) i++;
      return flyCurve.getPoint(clamp((i + (tt - ts[i]) / (ts[i + 1] - ts[i])) / (ts.length - 1))); }
    const k = P(t, 56.9, 2.5), a = flyAt(56.9), b = V(...BOARD);               // баллистика до щита
    return a.clone().lerp(b, k).add(V(0, Math.sin(k * Math.PI) * 6 - 0, 0));
  };
  const anchorAt = t => { const p = flyAt(Math.min(t, 56.8)); const i = Math.floor((t - 48.4) / 1.2); return V((i % 2 ? -1 : 1) * 14, p.y + 46, p.z - 22); };
  shot(48.4, 64, (lt, t) => {
    env({ fill: [[0, 90, 260], 20, 0x7feaff] });
    TI.setSuit(true);
    const p = flyAt(t), q = flyAt(t + .05), vel = q.clone().sub(p);
    if (t < 59.4) {
      place(TI, S, p.toArray(), 0);
      D.orient(TI, V(0, 1, 0).lerp(t < 56.9 ? anchorAt(t).sub(p).normalize() : vel.clone().normalize().negate(), .55), vel.clone().setY(0).normalize().add(V(0, 0, -.001)));
      TI.pose(t < 56.9 ? POSE.swing(t) : POSE.fall(t));
      if (t < 56.95) props.webs.add(handW(TI, 'R'), anchorAt(t), { w: .04, wob: .2, wobT: (t - 48.4) % 1.2 });
      if (t > 56.4 && t < 57.0) { TI.mats.hand.emissive.setRGB(1.2, .1, .05); props.sparks.burst(handW(TI, 'R'), t - 56.6, { speed: 2, life: .3, size: .05 }); }   // запястья краснеют, нить «чихает»
    } else {                                                                       // висит на щите
      place(TI, S, [BOARD[0] + .45, BOARD[1] - 2.05 - .25 * E.outBack(P(t, 59.4, .5)), BOARD[2]], Math.PI / 2);
      TI.pose({ ...POSE.hangUpside(t), spine: [.1, 0, .05 * Math.sin(t * 2)], armL: [-2.9, 0, .25], armR: [-2.9, 0, .25], foreL: [-.1, 0, 0], foreR: [-.1, 0, 0], legL: [-.1, 0, .05], legR: [.15, 0, .05], gripL: 1, gripR: 1 });
      squash(TI, springAt(t, 59.4, -.2, 14, 6));
    }
    face(TI, 'timur', t, { squint: t > 56.6 ? 1.2 : .6, energy: .8 });
    // коробка в руке
    TI.J.handL.add(box); box.visible = true; box.position.set(0, -.18, .1); box.rotation.set(0, 0, 0);
    // камера «на нити», затем проводка падения
    if (t < 56.9) { const c = p.clone().add(V(9, 3, 13)); look(addv(c.toArray(), shk(t, .05, 2)), p.clone().add(V(0, .6, -2)).toArray(), 52); D.speedLines(.35, t); }
    else if (t < 59.4) look([-14, 92, 214], p.toArray(), 54);
    else look(addv([-31.5, 80.4, 205.6], shk(t, .3 * Math.exp(-(t - 59.4) * 5), 16)), [BOARD[0] + .4, BOARD[1] - 1.4, BOARD[2]], 42);
    impact(t, 59.4, { zoom: .14, shake: .25 });
    comic('ЧИХ!', 1200, 300, t - 56.75, { size: .45, color: '#ff8a3d', dur: .7 });
    comic('ШМЯК!', 760, 360, t - 59.4, { size: .7, color: '#ffe23d', dur: 1.0 });
    return S;
  }, { flashK: .6 });
  shot(64, 78, (lt, t) => {
    TI.setSuit(true);
    place(TI, S, [BOARD[0] + .45, BOARD[1] - 2.3, BOARD[2]], Math.PI / 2);
    const phone = t > 72.4;
    TI.pose({ ...POSE.hangUpside(t), spine: [.1, 0, .05 * Math.sin(t * 2)], armL: [-2.9, 0, .25], foreL: [-.1, 0, 0], gripL: 1,
      armR: phone ? [-1.1, .3, .3] : [-2.9, 0, .25], foreR: phone ? [-1.8, 0, 0] : [-.1, 0, 0], gripR: phone ? .6 : 1, head: phone ? [.35, -.2, 0] : [0, 0, 0],
      legL: [-.1 + .1 * Math.sin(t * 1.3), 0, .05], legR: [.15, 0, .05] });
    face(TI, 'timur', t, { brow: t < 70 ? .6 : .2, smile: t > 66 && t < 70 ? .4 : 0, look: phone ? [0, -.7] : [.3, 0] });
    TI.J.handR.add(box); box.visible = !phone; box.position.set(0, -.18, .1);
    const k = E.inOutSine(P(t, 64, 8));
    if (t < 72.4) look([lerp(-30.5, -32, k), lerp(81.6, 82.4, k), lerp(206.5, 203.5, k)], [BOARD[0] + .4, BOARD[1] - 1.6, BOARD[2]], lerp(40, 34, k));
    else look([-36.4, 82.6, 201.6], [BOARD[0] + .3, BOARD[1] - 1.5, BOARD[2] - .1], 32);
    if (t > 66.4 && t < 68) comic('УРРР…', 1250, 620, t - 66.6, { size: .4, color: '#ffd23d', dur: 1.0, rot: .1 });
    const nk = pulse(t, 72.6, 77.8, .25, .3);
    post(o => o.notice(1180, 120, nk, { title: 'Новый заказ · 23:58', lines: ['Башня «Аркада», 87 этаж, лаборатория', 'Заказчик: В. Лис · «Срочно. Курьеру-пауку»'], time: '23:41' }));
    fadeOut(lt, 14, .4);
    return S;
  });

  /* ======================= СЦЕНА 3. Лаборатория: радар ======================= */
  const veraAt = (t, pos, yaw, o = {}) => {
    place(VE, lab.group, pos, yaw);
    VE.pose(o.pose || { ...POSE.stand(t), armR: [-.9, .25, .1], foreR: [-1.0, 0, 0], handR: [-.3, 0, 0], armL: [-.5, -.2, .25], foreL: [-1.3, 0, 0], head: [.3, 0, 0], grip: .6 });
    VE.tablet.visible = o.tablet !== false;
    face(VE, 'vera', t, { seed: 1, ...o.face });
  };
  shot(78, 96, (lt, t) => {
    D.labBase(t, { lights: .22, red: .25, broken: true });
    veraAt(t, [1.6, 0, -12.6], .41, { face: { brow: t > 85 ? .8 : .3, look: [0, -.6] } });
    const reds = t < 85.3 ? [] : [[.62, .6], [.3, .32], [.52, .2]].slice(0, 1 + Math.floor((t - 85.3) * 2));
    const ra = clamp((t - 78.5) / .4);
    if (ra > 0) post(o => { o.g.globalAlpha = ra; o.radar(1180, 160, 640, 400, t, { blue: [.45, lerp(.9, .5, P(t, 78, 16))], reds }); o.g.globalAlpha = 1; });
    const k = E.inOutSine(P(t, 78, 7));
    if (t < 85) look(L2W(lerp(4.6, 3.6, k), 1.85, lerp(-6.8, -8.2, k)), L2W(1.5, 1.5, -12.6), lerp(36, 30, k));
    else { const hp = headW(VE); look(hp.clone().add(V(-.2, .05, 1.0)).toArray(), hp.clone().add(V(0, -.06, 0)).toArray(), 30); }
    caption('Лаборатория «Аркады». Доктор Лис.', 90, 90, t - 78.4, { dur: 2.6 });
    fadeIn(lt, .4); fadeOut(lt, 18, .4);
    return S;
  });

  /* ======================= СЦЕНА 4. Крыша: Тенета ======================= */
  const ROOF = 74.1;
  const TIr = t => kf(t, [[96.4, [300, ROOF + 22, -340]], [97.0, [292, ROOF, -362], E.inQuad], [110.4, [292, ROOF, -362]], [110.9, [291.2, ROOF, -362.2], E.outCubic],
    [120, [291.2, ROOF, -362.2]], [128.8, [291.6, ROOF, -362.6]], [143.2, [293.6, ROOF, -363.6], E.inOutSine], [147.4, [293.6, ROOF, -363.6]], [149.4, [330, ROOF + 40, -420], E.inQuad]]);
  const TIyaw = t => kf(t, [[96, Math.PI / 2], [123.6, Math.PI / 2], [124.6, -Math.PI * .1, E.inOutSine], [143, -Math.PI * .1], [143.6, Math.PI * .35]]);
  // дроны: 0 — прыгает и прилипает к баку, 1 и 2 — сталкиваются лбами, 3 — говорит голосом Тени
  const DR = [
    t => kf(t, [[102.6, [308.6, ROOF - 5, -366]], [104.2, [308.3, ROOF, -365.5], E.outQuad], [108.0, [301, ROOF, -364.5], E.inOutSine], [110.4, [299.5, ROOF, -364.2]], [111.4, [293.5, ROOF + 2.4, -363], E.outQuad], [111.62, [292.6, ROOF + 1.4, -362.6]], [112.0, [280.6, ROOF + 4.2, -369.6], E.outCubic]]),
    t => kf(t, [[102.9, [308.6, ROOF - 5, -360]], [104.5, [308.3, ROOF, -359.8], E.outQuad], [116.4, [298.6, ROOF, -357.2], E.inOutSine], [116.6, [298.6, ROOF, -357.2]], [118.2, [294.8, ROOF + 1.2, -362.1], E.inQuad], [119.4, [295.6, ROOF, -360.4], E.outQuad]]),
    t => kf(t, [[103.2, [308.6, ROOF - 5, -370]], [104.8, [308.3, ROOF, -369.8], E.outQuad], [116.4, [298.0, ROOF, -367.4], E.inOutSine], [116.6, [298.0, ROOF, -367.4]], [118.2, [294.8, ROOF + 1.2, -362.7], E.inQuad], [119.4, [295.2, ROOF, -364.8], E.outQuad]]),
    t => kf(t, [[122.6, [286, ROOF - 5, -337]], [124.4, [287, ROOF, -338.2], E.outQuad], [128.8, [289.6, ROOF, -348.6], E.inOutSine], [129.4, [290.6, ROOF + 2.6, -354.4], E.outQuad], [130.0, [291.8, ROOF, -360.0], E.inQuad],
      [143.2, [292.4, ROOF, -360.4]], [144.1, [292.4, ROOF, -360.4]], [145.4, [312, ROOF - 14, -352], E.outQuad]]),
  ];
  const drYaw = (i, t) => { const p = DR[i](t), q = DR[i](t + .1); const d = Math.hypot(q[0] - p[0], q[2] - p[2]); return d > .02 ? Math.atan2(q[0] - p[0], q[2] - p[2]) : yawTo(p, TIr(t)); };
  const roofBase = (t, o = {}) => {
    env({ key: 1.6, rim: 2.0, rimPos: [360, 60, -420], fill: [[292, 78, -355], 14, 0x7feaff] });
    tank.visible = true;
    TI.setSuit(true);
    const tp = TIr(t); place(TI, S, tp, TIyaw(t)); rimOn([tp[0], tp[1] + 1.2, tp[2]], 0xa8f0ff, 2.6);
    for (let i = 0; i < 4; i++) {
      const p = DR[i](t); if (p[1] < ROOF - 4.9 && i !== 3) continue; if (i === 3 && t < 122.6) continue;
      const climbing = p[1] < ROOF - .05 && t < 125;
      const stuck0 = i === 0 && t > 112.0, down = (i === 1 || i === 2) && t > 118.2, dead3 = i === 3 && t > 130 && t < 144.1;
      drone(i, p, drYaw(i, t), t * 2.4 + i, { walk: climbing || stuck0 || down || dead3 ? (stuck0 ? .15 : 0) : 1, pitch: climbing ? -Math.PI / 2 : down ? .5 : 0, roll: down ? (i === 1 ? 1.2 : -1.0) : 0, scale: .8 });
    }
  };
  shot(96, 108, (lt, t) => {
    roofBase(t);
    TI.pose(seq(t - 96.4, [[0, POSE.flip(t)], [.6, POSE.heroLand()], [2.2, FIGHT.guard, .5]]));
    squash(TI, springAt(t, 97.0, -.26, 15, 7));
    face(TI, 'timur', t, { squint: t > 98.3 ? 1 : .5, energy: .6 });
    const sense = pulse(t, 98.3, 101.6, .3, .6); D.sense(t, sense, 98.3);
    if (t > 97 && t < 98) D.ring(V(292, ROOF + .2, -362), (t - 97) * 7, 1 - (t - 97), 0xffffff);
    if (sense > .1) D.ring(headW(TI), .3 + ((t - 98.3) % 1) * 1.5, (1 - (t - 98.3) % 1) * .7 * sense);
    if (t < 102.4) move(t, [[96, [286.6, 77.2, -355.4], [292, 75.8, -362], 50], [102.4, [288.6, 75.5, -358.4], [292, 75.6, -362], 40]]);
    else if (t < 105.6) { const p = DR[0](t); look([305.2, ROOF + .5, -362.4], [p[0] + 1, p[1] + .4, p[2]], 40); }     // из-за спины: дроны лезут через край
    else move(t, [[105.6, [288, 75.4, -357.6], [300, 74.8, -364.4], 46], [108, [289, 75.8, -356.6], [300, 74.8, -364.4], 44]]);
    if (t > 104.9 && t < 106.6) props.sparks2.burst(V(...DR[0](t)).add(V(0, .5, 0)), (t - 104.9) % .4, { speed: 1, life: .3, size: .04 });
    comic('ТУДУМ!', 560, 320, t - 97.0, { size: .5, color: '#ffffff', dur: .8 });
    fadeIn(lt, .4);
    return S;
  }, { flashK: .7 });
  shot(108, 121, (lt, t) => {
    roofBase(t);
    TI.pose(seq(t - 108, [[0, FIGHT.guard], [2.4, FIGHT.leanBack, .18], [3.2, POSE.shootFwd('L'), .12], [4.4, FIGHT.guard, .3], [8.2, FIGHT.shootBoth, .12], [8.6, POSE.pull(t), .15], [10.4, FIGHT.guard, .4]]));
    face(TI, 'timur', t, { squint: .8, energy: 1 });
    // дрон 0 прилипает к баку
    if (t > 111.5) web(TI, 'L', t < 112.0 ? V(...DR[0](t)) : V(280.6, ROOF + 4.4, -369.6), t, 111.55, { w: .045 });
    if (t > 112.0) props.webs.add(V(280.6, ROOF + 4.4, -369.6), V(279.6, ROOF + 4.6, -370.4), { w: .08, splat: true, splatSize: .9 });
    // две нити — сталкивает дронов лбами
    if (t > 116.4 && t < 118.3) { web(TI, 'L', V(...DR[1](t)).add(V(0, .4, 0)), t, 116.4); web(TI, 'R', V(...DR[2](t)).add(V(0, .4, 0)), t, 116.45); }
    if (t > 118.2) { const c = V(294.8, ROOF + 1.4, -362.4); props.sparks.burst(c, t - 118.2, { speed: 9, life: .9 }); for (let i = 0; i < 2; i++) D.ring(c, .4 + ((t - 118.2) * 3 + i * .4) % 1 * 3, Math.max(0, .9 - (t - 118.2) * 1.4)); }
    const sense = pulse(t, 110.0, 111.3, .1, .3); D.sense(t, sense, 110.0);
    // камера
    if (t < 110.0) move(t, [[108, [286.6, 75.6, -356], [296, 75, -363.6], 46], [110, [287.6, 75.4, -356.8], [295, 75, -363.2], 44]]);
    else if (t < 112.4) look(addv([288.6, 74.9, -357.4], shk(t, .04, 3)), [292.4, 75.6, -362.8], 40);              // слоу-мо: дрон пролетает над Тимуром
    else if (t < 116.0) { const k = E.inOutSine(P(t, 112.4, 3.6)); look([lerp(287, 288, k), 76.4, lerp(-361, -358, k)], [lerp(281, 286, k), lerp(78, 76, k), lerp(-369, -366, k)], 44); }   // дрон на баке
    else look(addv([288.4, 75.6, -356.2], shk(t, t > 118.2 ? .3 * Math.exp(-(t - 118.2) * 4) : .03, 14)), [295.4, 75.4, -362.2], 48);
    impact(t, 112.0, { zoom: .08, shake: .15 }); impact(t, 118.2, { zoom: .16, shake: .25 });
    comic('ШЛЁП!', 520, 300, t - 112.0, { size: .5, color: '#7ff8ff', dur: .8 });
    comic('БДЫЩ!', 1250, 330, t - 118.2, { size: .75, color: '#ffe23d', dur: 1.0 });
    return S;
  }, { flashK: .7 });
  shot(121, 135, (lt, t) => {
    roofBase(t);
    TI.pose(seq(t - 121, [[0, FIGHT.guard], [2.0, tt => ({ ...POSE.stand(tt), armL: [-.3, 0, .5], foreL: [-1.0, 0, 0], gripL: .9 })], [3.4, FIGHT.guard, .4], [7.8, FIGHT.leanBack, .15], [8.6, POSE.shootFwd('R'), .1], [9.4, FIGHT.guard, .4]]));
    face(TI, 'timur', t, { squint: .6, smile: t < 124 ? .4 : 0, energy: .8 });
    if (t > 129.0 && t < 130.4) web(TI, 'R', V(...DR[3](t)).add(V(0, .5, 0)), t, 129.0, { w: .05 });
    if (t > 130) props.sparks.burst(V(291.8, ROOF + .3, -360), t - 130, { speed: 7, life: .8 });
    if (t < 124.4) { const hp = headW(TI); look(hp.clone().add(V(1.5, .1, 1.3)).toArray(), hp.clone().add(V(0, -.15, 0)).toArray(), 36); }   // «Вы кто такие?»
    else if (t < 128.6) { const p = DR[3](t); look([p[0] + 2.4, ROOF + 1.0, p[2] - 4.4], [p[0], ROOF + .6, p[2]], 44); }                   // сзади крадётся ещё один
    else look(addv([286.4, 76.2, -364.6], shk(t, t > 130 ? .3 * Math.exp(-(t - 130) * 4) : .04, 14)), [291.4, 75.2, -358.4], 50);
    impact(t, 130.0, { zoom: .14, shake: .25 });
    comic('БУХ!', 1260, 360, t - 130.0, { size: .6, color: '#ff8a3d', dur: .8 });
    return S;
  }, { flashK: .7 });
  shot(135, 150, (lt, t) => {
    roofBase(t);
    TI.pose(seq(t - 135, [[0, FIGHT.guard], [1.4, tt => POSE.stand(tt)], [7.8, FIGHT.load, .3], [8.6, FIGHT.kickR, .12], [9.4, FIGHT.guard, .3], [12.0, POSE.shootUp(), .2], [12.4, POSE.swing(t), .3]]));
    face(TI, 'timur', t, { brow: .6, squint: .5, look: [0, -.5] });
    // дрон-«рупор» Тени: глаза мигают в такт голосу
    const d3 = D.drones[3]; d3.traverse(m => { if (m.isMesh && m.material.isMeshBasicMaterial) m.visible = t > 144.1 || C.mouthOf('drone', t) > .15 || Math.sin(t * 13) > .7; });
    if (t > 144.1 && t < 146) props.sparks.burst(V(...DR[3](t)), t - 144.1, { speed: 5, life: .6 });
    if (t > 147.2) web(TI, 'R', [330, ROOF + 60, -440], t, 147.2, { w: .04 });
    if (t < 141.0) { const p = DR[3](t); look([p[0] - .8, ROOF + .7, p[2] - 1.9], [p[0], ROOF + .35, p[2]], 34); }                  // крупно: дрон говорит голосом Тени
    else if (t < 143.4) { const hp = headW(TI); look(hp.clone().add(V(-.4, .0, 1.4)).toArray(), hp.clone().add(V(0, -.1, 0)).toArray(), 32); }   // «Я не прячусь. Я доставляю.»
    else if (t < 147.0) look(addv([287.6, 75.8, -366.4], shk(t, t > 144.1 ? .25 * Math.exp(-(t - 144.1) * 4) : .02, 14)), [297, 74.6, -358], 52);
    else move(t, [[147, [286, 76.5, -368], [295, 78, -366], 50], [150, [290, 80, -372], [320, 100, -410], 54]]);
    impact(t, 144.1, { zoom: .12, shake: .2 });
    comic('ПИНОК!', 1260, 300, t - 144.1, { size: .6, color: '#ffe23d', dur: .9 });
    fadeOut(lt, 15, .4);
    return S;
  }, { flashK: .7 });

  /* ======================= СЦЕНА 5. Лаборатория: напарница ======================= */
  const VP = [14.6, 0, .5];                                     // Вера (координаты лаборатории)
  const TIl = t => kf(t, [[150, [23.2, 9.5, 1.6]], [151.6, [23.2, 9.5, 1.6]], [153.0, [17.2, 0, 1.2], E.inQuad], [174.6, [17.2, 0, 1.2]], [175.6, [15.9, 0, .9], E.inOutSine], [187, [15.9, 0, .9]], [188.2, [15.5, 0, .2], E.outCubic]]);
  const labNight = (t, o = {}) => {
    D.labBase(t, { lights: o.alarm ? .3 : .2, red: o.alarm ? (Math.sin(t * 7) > 0 ? .9 : .3) : .2, broken: true });
    TI.setSuit(true);
  };
  shot(150, 176, (lt, t) => {
    labNight(t);
    const tp = TIl(t);
    place(TI, lab.group, tp, t < 175 ? -Math.PI / 2 : -Math.PI / 2 - .25);
    TI.pose(t < 151.6 ? POSE.spiderCrouch(t) : t < 153.0 ? POSE.flip(t) : seq(t - 153, [[0, POSE.heroLand()], [1.6, tt => POSE.stand(tt), .5],
      [13.2, tt => ({ ...POSE.stand(tt), armL: [-.3, 0, .5], armR: [-.3, 0, .5], foreL: [-1.2, 0, 0], foreR: [-1.2, 0, 0], head: [.1, 0, 0] }), .4], [21.6, tt => POSE.walk(tt * .9), .3]]));
    if (t > 153) squash(TI, springAt(t, 153.0, -.22, 15, 7));
    face(TI, 'timur', t, { brow: t > 157.5 && t < 160 ? .9 : .3, smile: t > 165 && t < 167 ? .5 : 0, energy: .4 });
    if (t > 151.6 && t < 153.1) props.webs.add(handW(TI, 'R'), V(...L2W(20.2, 22.4, 1.4)), { w: .04 });
    veraAt(t, VP, Math.PI / 2, { pose: { ...POSE.stand(t), armR: [-1.1, .2, .1], foreR: [-.9, 0, 0], handR: [-.3, 0, 0], armL: [-.4, -.1, .3], foreL: [-1.4, 0, 0], head: [-.05, .1, 0], grip: .6 },
      face: { smile: t > 153.4 && t < 156 ? .8 : t > 162 && t < 165 ? .5 : 0, brow: t > 166 ? .5 : .2, look: [0, 0] } });
    const R = (x, y, z) => L2W(x, y, z);
    if (t < 153.4) look(R(14.8, 2.2, 6.4), L2W(tp[0], tp[1] + 1.0, tp[2]), 48);                                                                     // влезает в разбитое окно
    else if (t < 157.6) { const hp = headW(VE); look(hp.clone().add(V(1.1, .1, .75)).toArray(), hp.clone().add(V(0, -.06, 0)).toArray(), 32); }       // «Курьер. Я так и знала.»
    else if (t < 160.4) { const hp = headW(TI); look(hp.clone().add(V(-1.2, .05, -.5)).toArray(), hp.clone().add(V(0, -.1, 0)).toArray(), 32); }
    else if (t < 166.0) look(R(15.9, 1.7, 5.4), R(15.9, 1.3, .9), 42);                                                                                   // двое в кадре
    else if (t < 171.6) { const hp = headW(VE); look(hp.clone().add(V(1.0, .1, .9)).toArray(), hp.clone().add(V(0, -.06, 0)).toArray(), 32); }
    else { const hp = headW(TI); look(hp.clone().add(V(-1.1, .05, -.7)).toArray(), hp.clone().add(V(0, -.1, 0)).toArray(), 32); }
    const rk = pulse(t, 166.4, 171.6, .3, .3);
    if (rk > 0) post(o => { o.g.globalAlpha = rk; o.radar(1180, 140, 640, 400, t, { blue: [.47, .5], reds: [[.62, .58], [.7, .3]], label: 'СИГНАЛ НОСИТЕЛЯ · ОТКРЫТ' }); o.g.globalAlpha = 1; });
    fadeIn(lt, .5);
    return S;
  });
  shot(176, 186, (lt, t) => {
    labNight(t);
    place(TI, lab.group, TIl(t), -Math.PI / 2 - .25);
    // Тимур держит карабин на ладони, Вера защёлкивает в нём чип
    TI.pose({ ...POSE.stand(t), armR: [-1.1, -.3, .1], foreR: [-.9, 0, 0], handR: [.3, 0, 0], gripR: .3, head: [.35, 0, 0] });
    TI.J.handR.add(carab); carab.visible = true; carab.position.set(0, -.1, .08); carab.rotation.set(0, 0, .3); carab.scale.set(1.0, 1.7, 1.4);
    const g = clamp((t - 178.5) / .4) * (.75 + .25 * Math.sin(t * 6)); chip.visible = t > 178.2; carabM.emissive.setRGB(.19 + .3 * g, .2 + 1.4 * g, .24 + 1.7 * g);
    face(TI, 'timur', t, { brow: .4, smile: t > 181 ? .6 : 0, look: [0, -.7] });
    veraAt(t, [14.9, 0, .7], Math.PI / 2, { tablet: false, pose: { ...POSE.stand(t), armR: [-1.2, .25, .1], foreR: [-.7, 0, 0], handR: [.2, 0, 0], gripR: .8, head: [.35, .1, 0], spine: [.12, 0, 0] },
      face: { smile: t > 179 ? .7 : .2, look: [0, -.7] } });
    carab.updateMatrixWorld(true); const cw = carab.getWorldPosition(V(0, 0, 0));
    if (t > 178.5) props.swirl.update(cw, t - 178.5, clamp(1 - (t - 181.5) / 1.5));             // нанонить «втекает» в карабин
    if (t > 178.5 && t < 179.6) props.sparks2.burst(cw, t - 178.5, { speed: 2, life: .5, size: .04 });
    if (t < 182) { const k = E.inOutSine(P(t, 176, 6)); look(cw.clone().add(V(-.1, lerp(.26, .2, k), lerp(.7, .55, k))).toArray(), cw.toArray(), lerp(30, 24, k)); }   // макро: карабин
    else { const hp = headW(TI); look(hp.clone().add(V(-1.0, .05, -.8)).toArray(), hp.clone().add(V(0, -.1, 0)).toArray(), 32); }
    comic('ЩЁЛК!', 1250, 330, t - 178.3, { size: .45, color: '#7ff8ff', dur: .7 });
    return S;
  });

  /* ======================= СЦЕНА 6. Дроны в лаборатории ======================= */
  const LD = [
    t => kf(t, [[186.2, [24.2, 8.6, 3.2]], [188.4, [24.0, 0, 3.0], E.inQuad], [191.4, [19.8, 0, 1.8], E.inOutSine], [191.7, [19.8, 0, 1.8]], [192.4, [21.6, 0, 3.4], E.outCubic]]),
    t => kf(t, [[186.5, [24.2, 8.6, -1.6]], [188.8, [24.0, 0, -1.4], E.inQuad], [191.4, [19.6, 0, -1.2], E.inOutSine], [191.7, [19.6, 0, -1.2]], [192.6, [21.4, 0, -2.6], E.outCubic],
      [195.4, [21.4, 0, -2.6]], [195.6, [21.0, .2, -2.4]], [196.2, [17.4, 1.6, -.4], E.outQuad], [197.2, [22.4, 0, -3.4], E.outCubic]]),
  ];
  shot(186, 206, (lt, t) => {
    labNight(t, { alarm: t > 186.4 });
    const tp = TIl(t);
    place(TI, lab.group, tp, kf(t, [[186, -Math.PI / 2 - .25], [188, Math.PI / 2, E.inOutSine]]));
    TI.pose(seq(t - 186, [[0, tt => POSE.stand(tt)], [1.4, FIGHT.guard, .3], [5.4, FIGHT.shootBoth, .12], [6.0, POSE.pull(t), .15], [7.4, FIGHT.guard, .3], [9.4, FIGHT.load, .2], [10.0, FIGHT.kickR, .1], [10.8, FIGHT.guard, .3], [13.4, tt => POSE.stand(tt), .6]]));
    face(TI, 'timur', t, { squint: t < 199 ? .8 : .3, smile: t > 199.2 ? .8 : 0, energy: 1 });
    strapCarab(t, .6 + .2 * Math.sin(t * 4));
    veraAt(t, [12.6, 0, .1], Math.PI / 2, { tablet: true, pose: t < 188 ? { ...POSE.stand(t), spine: [-.1, 0, 0], head: [-.2, 0, 0], armL: [-1.4, 0, .4], foreL: [-1.6, 0, 0] } : { ...POSE.crouch(), spine: [.45, 0, 0], head: [-.5, 0, 0] },
      face: { wide: t < 191, brow: .9, look: [.6, .3] } });
    for (let i = 0; i < 2; i++) {
      const p = LD[i](t); if (t < (i ? 186.5 : 186.2)) continue;
      const w = L2W(...p), climbing = p[1] > .1 && t < 189, pinned = t > 191.7 && !(i === 1 && t > 195.4 && t < 197.2), dead = i === 1 && t > 197.2;
      drone(i, w, -Math.PI / 2, t * 2.4 + i, { parent: S, walk: pinned || dead ? 0 : 1, pitch: climbing ? Math.PI / 2 : dead ? .6 : 0, roll: dead ? 1.2 : 0, scale: .8 });
      if (pinned && !dead) props.webs.add(V(...w).add(V(0, .4, 0)), V(...L2W(p[0], 0, p[2] + (i ? -1 : 1))), { w: .07, splat: true, splatSize: .9 });
      if (dead) D.drones[1].traverse(m => { if (m.isMesh && m.material.isMeshBasicMaterial) m.visible = Math.sin(t * 40) > .3 && t < 197.8; });
    }
    if (t > 191.4 && t < 191.75) { web(TI, 'L', V(...L2W(...LD[0](t))).add(V(0, .4, 0)), t, 191.45); web(TI, 'R', V(...L2W(...LD[1](t))).add(V(0, .4, 0)), t, 191.5); }
    if (t > 196.2) props.sparks.burst(V(...L2W(17.4, 1.6, -.4)), t - 196.2, { speed: 8, life: .9 });
    if (t > 186.4 && t < 187.6) props.sparks2.burst(V(...L2W(24.2, 8.8, 1)), t - 186.4, { speed: 4, life: .8, grav: 6 });
    const R = (x, y, z) => L2W(x, y, z);
    if (t < 188.2) look(addv(R(14.2, 2.0, 5.4), shk(t, .05, 6)), R(22, 4.2, .8), 50);                         // стекло трещит, дроны лезут
    else if (t < 195.4) look(addv(R(13.4, 1.4, 4.6), shk(t, t > 192.4 ? .25 * Math.exp(-(t - 192.4) * 4) : .03, 14)), R(18.6, 1.0, .6), 50);
    else if (t < 199.2) look(addv(R(15.0, 1.3, 3.8), shk(t, t > 196.2 ? .3 * Math.exp(-(t - 196.2) * 4) : .03, 14)), R(17.6, 1.3, -.6), 46);
    else { const hp = headW(TI); look(hp.clone().add(V(1.3, .05, .7)).toArray(), hp.clone().add(V(0, -.1, 0)).toArray(), 34); }   // «Доставка закрыта…»
    impact(t, 192.4, { zoom: .1, shake: .2 }); impact(t, 196.2, { zoom: .15, shake: .25 });
    comic('ХРУСТЬ!', 1280, 260, t - 186.4, { size: .5, color: '#ff8a3d', dur: .8 });
    comic('ШЛЁП-ШЛЁП!', 640, 300, t - 191.7, { size: .55, color: '#7ff8ff', dur: .9 });
    comic('БАМ!', 1180, 380, t - 196.2, { size: .7, color: '#ffe23d', dur: .9 });
    fadeOut(lt, 20, .5);
    return S;
  }, { flashK: .6 });

  /* ======================= СЦЕНА 7. Дом ======================= */
  shot(206, 222.3, (lt, t) => {
    kitchenBase(t, { dedPose: p => ({ ...p, spine: [.75, 0, .05], head: [.55, .4, .2], armL: [-1.25, .4, .2], armR: [-1.25, -.4, .2], foreL: [-1.6, 0, 0], foreR: [-1.6, 0, 0] }),
      dedFace: { noBlink: true, blink: 1, smile: .3 } });
    extraPlates.forEach(p => p.visible = false);
    lid.visible = t < 214.4; note.visible = t < 214.4;
    const tp = kf(t, [[206, [3.0, 0, .6]], [209.4, [.95, 0, .3], E.inOutSine], [211.0, [.55, 0, .25], E.inOutSine]]);
    place(TI, K, tp, t < 209.4 ? -Math.PI / 2 - .3 : Math.PI);
    TI.pose(t < 209.4 ? POSE.walk(gait(Math.hypot(tp[0] - 3, tp[2] - .6), .55, .7)) : t < 213.6 ? seq(t - 209.4, [[0, tt => POSE.stand(tt)], [1.6, tt => POSE.sitChair(tt), .8]]) : FIGHT.eat(t));
    face(TI, 'timur', t, { brow: .2, smile: t > 211 ? .7 : .3, look: t < 212 ? [-.5, -.4] : [0, -.6] });
    strapCarab(t, .45 + .25 * Math.sin(t * 2));
    if (t < 211) look([1.8, 1.6, 1.6], [-.2, .9, -1.0], 42);
    else if (t < 215.4) { const k = E.inOutSine(P(t, 211, 3)); look([lerp(.9, .6, k), lerp(1.4, 1.3, k), lerp(-.1, -.2, k)], [.4, .9, -.45], 32); }    // записка «Ешь, курьер»
    else { const k = E.inOutSine(P(t, 215.4, 7)); look([lerp(1.6, 2.6, k), lerp(1.55, 2.0, k), lerp(1.4, 2.4, k)], [0, 1.0, -.7], 40); }
    fadeIn(lt, .5); fadeOut(lt, 16.3, .5);
    return K;
  }, { noFlash: false });

  /* ======================= Финал: логотип и тизер ======================= */
  shot(222.3, 226, (lt, t) => {
    look([0, 100, 200], [0, 100, 0], 45);
    post(o => o.logo(lt, { sub: 'КОНЕЦ ВТОРОЙ СЕРИИ' }));
    post(o => o.title([{ text: 'мультфильм студии', font: '500 28px Rubik', y: 958, color: '#9fb4d8' },
      { text: 'GraphicArts Animation', font: '800 42px Unbounded', y: 1008, color: '#ffffff', stroke: 8, glow: '#ff7b1c' }], clamp((lt - 1.0) / .6)));
    post(o => o.fill('#000', (lt - 3.2) / .5));
    return S;
  }, { noSubs: true, noFlash: true });
  shot(226, 236, (lt, t) => {
    lairBase(t, { eyesAt: 227.2, core: true });
    veraScreen.visible = true;
    drone(0, [.55, .95, .45], -.6 + Math.sin(t * .8) * .2, t, { parent: Z, scale: .3, walk: 0 });
    const k = E.inOutSine(P(t, 226, 5.5));
    look([lerp(-1.2, .3, k), lerp(2.2, 1.8, k), lerp(5.8, 2.8, k)], [lerp(0, 0, k), lerp(2.6, 1.75, k), lerp(-3.4, .2, k)], lerp(42, 32, k));
    fadeIn(lt, .8);
    post(o => o.fill('#000', (t - 232.2) / .3 * .85));
    post(o => o.title([{ text: 'ПРОДОЛЖЕНИЕ СЛЕДУЕТ…', font: '900 76px Unbounded', y: 540, color: '#ff3a3a', stroke: 14, glow: '#ff0000' }], clamp((t - 232.4) / .5)));
    post(o => o.title([{ text: '© 2026 GraphicArts Animation', font: '500 24px Rubik', y: 1030, color: '#8a94a8' }], clamp((t - 233.0) / .5)));
    post(o => o.fill('#000', (t - 235.3) / .6));
    return Z;
  }, { noFlash: true });

  return D.shots;
}
