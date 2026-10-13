// Серия 2 «Личная жизнь» — все шоты (сюжетное время, как в dialogue.json и STORY.md).
// Сцены: кухня утром → заставка → ворота лицея → класс физики → столовая → коридор (Азим) → двор Затона на закате
// (Маржон, апельсины, «Эм-Джей») → кухня вечером → логотип → тизер: ODILMAN на крыше в грозу.
import * as THREE from 'three';
import { makeDirector, FIGHT, HEAVY, POSE, V, E, P, kf, lerp, clamp, pulse, seq, blend, gait, squash, springAt, ikArm, yawTo } from 'engine/director.js';
import { toon, glow, mesh, noise } from 'engine/core.js';

export function buildShots(C) {
  const D = makeDirector(C);
  const { shot, look, move, place, face, post, comic, caption, fadeIn, fadeOut, headW, handW, impact } = D;
  const { kitchen, school, zaton: Z, city, ch, props, camera: cam, U } = C;
  const { timur: TI, ded: DE, marjon: MJ, diyor: DI, azim: AZ, teacher: TE, odilman: OD } = ch;
  const ST = i => ch['s' + i];
  // паучье чутьё в любой сцене: синий грейд и замедление (в интерьерах городские шейдеры не работают — тонируем кадр)
  const sense = (t, k, t0) => { D.sense(t, k, t0); if (k > .05) { C.grade = 'sense'; post(o => o.fill('#2a5cff', .13 * k)); } };
  const K = kitchen.scene, KD = C.kitchenD;
  const CR = school.corridor, CL = school.classroom, CN = school.canteen;
  const SX = 600;                                 // лицей в сцене Затона

  /* ---------- общие помощники ---------- */
  const WHO = { timur: TI, ded: DE, marjon: MJ, diyor: DI, azim: AZ, teacher: TE, odilman: OD };
  // насколько персонаж сейчас говорит (0…1, плавно) — для жестов
  const talkK = (who, t) => C.lines.reduce((m, l) => l.who === who ? Math.max(m, pulse(t, l.t - .15, l.t + l.d + .25, .3, .45)) : m, 0);
  const SEED = { timur: 0, ded: 2, marjon: 3, diyor: 4, azim: 5, teacher: 6, odilman: 7 };
  /** жест говорящего поверх любой базовой позы (руки/голова), side — какой рукой жестикулирует */
  const talking = (base, who, t, amt = 1, side = 'L') => {
    const k = talkK(who, t) * amt; if (k <= 0) return base;
    const tp = POSE.talk(t + (SEED[who] ?? 0) * 1.7);
    const g = { ...base, head: [(base.head?.[0] ?? 0) + tp.head[0], (base.head?.[1] ?? 0) + tp.head[1], base.head?.[2] ?? 0] };
    if (side === 'L') { g.armL = tp.armL; g.foreL = tp.foreL; g.handL = tp.handL; g.gripL = tp.gripL; }
    else { g.armR = [tp.armL[0], -tp.armL[1], tp.armL[2]]; g.foreR = tp.foreL; g.handR = [tp.handL[0], 0, -tp.handL[2]]; g.gripR = tp.gripL; }
    return blend(base, g, k);
  };
  // зеркальная поза (левый хук из правого)
  const mirror = p => { const o = {}; for (const [k, v] of Object.entries(p)) {
    const n = k.endsWith('L') ? k.slice(0, -1) + 'R' : k.endsWith('R') ? k.slice(0, -1) + 'L' : k;
    o[n] = Array.isArray(v) ? [v[0], -v[1], -v[2]] : v; } return o; };
  const sit = (t, o = {}) => ({ ...POSE.sitChair(t), ...o });
  // крупный план: смещение [вбок, вверх, вперёд] в системе персонажа
  const Y = new THREE.Vector3(0, 1, 0);
  const rel = (c, off) => V(...off).applyAxisAngle(Y, c.root.rotation.y);
  const close = (c, off = [.25, .02, 1.0], fov = 30, aim = [0, -.07, 0]) => {
    const h = headW(c); look(h.clone().add(rel(c, off)).toArray(), h.clone().add(V(...aim)).toArray(), fov);
  };
  // через плечо A на B
  const ots = (A, B, side = 1, fov = 32, back = .85, up = .12, sd = .5) => {
    const a = headW(A), b = headW(B), d = b.clone().sub(a).setY(0).normalize(), r = new THREE.Vector3().crossVectors(d, Y);
    look(a.clone().addScaledVector(d, -back).addScaledVector(r, side * sd).add(V(0, up, 0)).toArray(), b.clone().add(V(0, -.06, 0)).toArray(), fov);
  };
  /** ходьба по ломаной: скорость sp м/с, старт t0; o.run, o.end(t) — поза в конце, o.endYaw */
  const path = (pts, d) => {
    let L = 0; const seg = pts.slice(1).map((p, i) => { const l = Math.hypot(p[0] - pts[i][0], p[2] - pts[i][2]); L += l; return l; });
    d = clamp(d, 0, L); let i = 0, acc = 0; while (i < seg.length - 1 && acc + seg[i] < d) acc += seg[i++];
    const k = seg[i] ? (d - acc) / seg[i] : 0, a = pts[i], b = pts[i + 1] || a;
    return { p: [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)], L };
  };
  const walk = (c, sc, pts, t, t0, sp = 1.25, o = {}) => {
    const d = Math.max(0, (t - t0) * sp), { p, L } = path(pts, d);
    const ahead = path(pts, Math.min(d + .5, L)).p, behind = path(pts, Math.max(0, d - .5)).p;
    let yaw = d >= L - .02 ? (o.endYaw ?? yawTo(behind, p)) : yawTo(p, ahead);
    if (d >= L - .02 && o.endYaw != null) yaw = lerp(yawTo(behind, p), o.endYaw, E.inOutSine(P(t - t0 - L / sp, 0, .5)));
    if (!(d < L)) { if (o.endYaw == null) yaw = yawTo(pts[pts.length - 2], pts[pts.length - 1]); }
    place(c, sc, p, yaw);
    const moving = t >= t0 && d < L;
    const stride = .7 * c.d.k;
    c.pose(moving ? (o.run ? POSE.run(gait(d, 1.15 * c.d.k, 1.6), 1.6) : o.walkPose ? o.walkPose(gait(d, stride, .9)) : POSE.walk(gait(d, stride, .9))) : (o.end ? o.end(t) : POSE.stand(t)));
    return { p, yaw, done: d >= L, d, L };
  };
  // фигуранты: позы «жизни» на заднем плане — перенос веса, у каждого своя манера держать руки, кивки, жесты
  const wshift = (p, t, s, a = 1) => {           // перенос веса с ноги на ногу
    const w = Math.sin(t * .42 + s * 2.3);
    p.hx = (p.hx || 0) + .025 * w * a; p.spine = [(p.spine?.[0] ?? 0), (p.spine?.[1] ?? 0), (p.spine?.[2] ?? 0) - .035 * w * a];
    p.legL = [p.legL?.[0] ?? 0, 0, (p.legL?.[2] ?? .03) + .04 * Math.max(0, w) * a]; p.legR = [p.legR?.[0] ?? 0, 0, (p.legR?.[2] ?? .03) + .04 * Math.max(0, -w) * a];
    p.shinL = [.14 * Math.max(0, -w) * a, 0, 0]; p.shinR = [.14 * Math.max(0, w) * a, 0, 0];
    return p;
  };
  const arms = (p, s) => {                       // манера: 0 — руки вдоль, 1 — рука на поясе, 2 — руки за спиной, 3 — лямки рюкзака
    const v = Math.floor(s * 7.31) % 4;
    if (v === 1) { p.armR = [-.25, 0, .62]; p.foreR = [-1.55, 0, 0]; p.gripR = .8; }
    if (v === 2) { p.armL = [.38, 0, .16]; p.foreL = [-.7, 0, 0]; p.armR = [.38, 0, .16]; p.foreR = [-.7, 0, 0]; }
    if (v === 3) { p.armL = [-.35, 0, .28]; p.foreL = [-2.0, 0, 0]; p.armR = [-.35, 0, .28]; p.foreR = [-2.0, 0, 0]; p.grip = .9; }
    return p;
  };
  const nod = (t, s) => .12 * Math.max(0, Math.sin(t * 2.2 + s * 5)) ** 6;
  const LIFE = {
    stand: (t, s) => wshift(arms(POSE.stand(t + s), s), t, s),
    talk: (t, s) => { const p = wshift(POSE.talk(t * .9 + s * 3), t, s, .6); const g2 = Math.max(0, Math.sin(t * .8 + s * 4));
      if (g2 > .3) { p.armR = [-.35 - .3 * g2 * Math.sin(t * 3 + s), -.2, .25]; p.foreR = [-1.1 - .3 * g2, 0, 0]; p.handR = [0, 0, -.3]; }
      p.head = [p.head[0] + nod(t, s), p.head[1], .06 * Math.sin(t * .7 + s)]; return p; },
    listen: (t, s) => { const p = wshift(arms(POSE.stand(t + s), s + .3), t, s); p.head = [.05 + nod(t, s + 1), 0, .08 * Math.sin(t * .3 + s)]; return p; },
    phone: (t, s) => { const p = wshift(POSE.phone(t + s), t, s, .5); p.foreR = [-2.3 + .15 * Math.sin(t * .9 + s), 0, 0]; p.handL = [0, 0, 0]; return p; },
    film: (t, s) => ({ ...wshift(POSE.stand(t + s), t, s, .4), armR: [-1.35, .3, .2], foreR: [-.9, 0, 0], handR: [-.4, 0, 0], armL: [-1.25, -.3, .25], foreL: [-1.0, 0, 0], gripR: .7, gripL: .7, head: [.08, 0, 0] }),
    laugh: (t, s) => ({ ...POSE.stand(t + s), spine: [-.12 + .06 * Math.sin(t * 14 + s), .1 * Math.sin(t * 2 + s), 0], head: [-.28, 0, .1 * Math.sin(t * 3)], armL: [-.35, 0, .3], armR: [-.35, 0, .3], foreL: [-1.4, 0, 0], foreR: [-1.4, 0, 0], hy: -.02 * Math.abs(Math.sin(t * 7)) }),
    sit: (t, s) => sit(t + s, { head: [.05 + nod(t, s), .15 * Math.sin(t * .3 + s), 0], spine: [.08 + .03 * Math.sin(t * .5 + s), 0, 0] }),
    sitTalk: (t, s) => { const tp = POSE.talk(t + s); return sit(t + s, { armL: tp.armL, foreL: tp.foreL, handL: tp.handL, head: [tp.head[0] + nod(t, s), tp.head[1], 0] }); },
    eat: (t, s) => { const p = FIGHT.eat(t * (.8 + (s % 1) * .5) + s); p.head = [p.head[0], .2 * Math.sin(t * .4 + s), 0]; return p; },
    write: (t, s) => sit(t + s, { spine: [.32, 0, 0], head: [.3, .1 * Math.sin(t + s), 0], armR: [-.75, .1, .1], foreR: [-1.0 + .15 * Math.sin(t * 7 + s), 0, 0], armL: [-.7, -.1, .1], foreL: [-1.1, 0, 0] }),
    yawn: (t, s) => { const y = Math.max(0, Math.sin(t * .35 + s)) ** 4; return sit(t + s, { armL: [-.6 - 1.9 * y, 0, .15 + .3 * y], foreL: [-.9 + .5 * y, 0, 0], armR: [-.6 - 1.9 * y, 0, .15 + .3 * y], foreR: [-.9 + .5 * y, 0, 0], head: [-.3 * y, 0, 0], spine: [.08 - .2 * y, 0, 0] }); },
    chin: (t, s) => sit(t + s, { armR: [-1.1, .3, .1], foreR: [-2.1, 0, 0], handR: [0, 0, .4], spine: [.25, 0, 0], head: [-.05, -.2 + .1 * Math.sin(t * .3 + s), .15] }),
    lean: (t, s) => ({ ...POSE.stand(t + s), spine: [-.06, 0, 0], legL: [.05, 0, -.05], legR: [-.15, .3, .12], shinR: [.2, 0, 0], armL: [.1, 0, .1], armR: [-.4, 0, .5], foreR: [-1.6, 0, 0], head: [nod(t, s), 0, .1] }),
    wow: (t, s) => ({ ...POSE.stand(t + s), spine: [-.1, 0, 0], head: [-.12, 0, 0], armL: [-.9, 0, .2], foreL: [-1.9 + .2 * Math.sin(t * 6 + s), 0, 0], armR: [-.9, 0, .2], foreR: [-1.9, 0, 0] }),
    cheer: (t, s) => ({ ...POSE.stand(t + s), armL: [-2.6 + .3 * Math.sin(t * 9 + s), 0, .3], foreL: [-.4, 0, 0], armR: [-.5, 0, .2], foreR: [-1.4, 0, 0], grip: 1, hy: -.03 * Math.abs(Math.sin(t * 9 + s)) }),
  };
  /** фигурант: o.at — куда смотрит (по умолчанию — общий «фокус» сцены C.focus), o.who — чей голос (смех толпы) */
  let FOCUS = null;
  const extra = (i, sc, pos, yaw, t, mode = 'stand', o = {}) => {
    const c = ST(i); place(c, sc, pos, yaw); c.pose((typeof mode === 'function' ? mode : LIFE[mode])(t, i * 1.37));
    const at = o.at === false ? undefined : o.at || FOCUS || undefined;
    face(c, o.who || 's', t, { seed: i % 5, smile: o.smile ?? .25, look: o.look, wide: o.wide, mk: o.mk ?? (o.who ? .8 : 0), at, atK: o.atK ?? .75, energy: .3 });
    return c;
  };
  /** прогулка туда-обратно между a и b (фон): sp — скорость, ph — сдвиг по времени, o.pose — что делает руками */
  const stroll = (i, sc, a, b, t, sp = 1.1, ph = 0, o = {}) => {
    const c = ST(i), L = Math.hypot(b[0] - a[0], b[2] - a[2]), T1 = L / sp, per = 2 * T1 + 2.4, u = ((t + ph) % per + per) % per;
    let k, yaw, moving = true;
    const yAB = yawTo(a, b), yBA = yawTo(b, a);
    if (u < T1) { k = u / T1; yaw = yAB; }
    else if (u < T1 + 1.2) { k = 1; yaw = lerp(yAB, yAB + Math.PI, E.inOutSine((u - T1) / 1.2)); moving = false; }
    else if (u < 2 * T1 + 1.2) { k = 1 - (u - T1 - 1.2) / T1; yaw = yBA; }
    else { k = 0; yaw = lerp(yBA, yBA + Math.PI, E.inOutSine((u - 2 * T1 - 1.2) / 1.2)); moving = false; }
    const pos = [lerp(a[0], b[0], k), 0, lerp(a[2], b[2], k)];
    place(c, sc, pos, yaw);
    let p = moving ? POSE.walk(gait(u * sp, .7 * c.d.k, .9)) : LIFE.stand(t, i);
    if (o.pose) p = { ...p, ...o.pose };
    c.pose(p);
    face(c, 's', t, { seed: i % 5, smile: .3, energy: .35, at: o.at, atK: .6 });
    return c;
  };
  // взгляд на говорящего: средневзвешенная голова тех, кто сейчас говорит (иначе — fallback)
  const speakerAt = (t, whos, fb) => {
    let w = 0; const acc = V(0, 0, 0);
    for (const n of whos) { const k = talkK(n, t); if (k > 0 && WHO[n]?.root.visible) { acc.addScaledVector(headW(WHO[n]), k); w += k; } }
    return w > 0 ? acc.multiplyScalar(1 / w) : (fb?.isVector3 ? fb : fb ? V(...fb) : undefined);
  };
  D.onReset(() => { FOCUS = null; });

  /* ---------- реквизит ---------- */
  const PROPS = [];
  const prop = obj => { obj.visible = false; PROPS.push(obj); return obj; };
  D.onReset(() => { PROPS.forEach(p => p.visible = false); CL.paper.visible = false; CR.dent.visible = false; Z.oranges.forEach(o => o.visible = false); Z.bag.visible = false;
    Z.bus.visible = false; MJ.sketch.visible = false; TE.chalk.visible = false; AZ.gum.visible = false; AZ.gum.scale.setScalar(1); OD.wind = .6; });
  const hold = (obj, c, side = 'R', pos = [0, -.1, .03], rot = [0, 0, 0]) => {
    const j = c.J['hand' + side]; if (obj.parent !== j) j.add(obj);
    obj.position.set(pos[0] * c.d.k, pos[1] * c.d.k, pos[2] * c.d.k); obj.rotation.set(...rot); obj.visible = true; return obj;
  };
  const put = (obj, sc, pos, rot = [0, 0, 0]) => { if (obj.parent !== sc) sc.add(obj); obj.position.set(...pos); obj.rotation.set(...rot); obj.visible = true; return obj; };
  const canvasTex = (w, h, draw) => { const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h); const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t; };
  // лепёшка
  const nonT = canvasTex(128, 128, g => { const gr = g.createRadialGradient(64, 64, 10, 64, 64, 64); gr.addColorStop(0, '#f2d49a'); gr.addColorStop(.55, '#d9a25a'); gr.addColorStop(1, '#a8682a'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
    g.fillStyle = 'rgba(90,50,20,.5)'; for (let i = 0; i < 26; i++) { const a = i * 2.4, r = 8 + (i % 6) * 5; g.beginPath(); g.arc(64 + Math.cos(a) * r, 64 + Math.sin(a) * r, 2, 0, 7); g.fill(); } });
  const non = prop(new THREE.Group());
  mesh(new THREE.CylinderGeometry(.11, .11, .028, 24), toon(0xffffff, { map: nonT }), { outline: .004, parent: non });
  mesh(new THREE.TorusGeometry(.1, .018, 6, 24), toon(0xc8843a), { rot: [Math.PI / 2, 0, 0], pos: [0, .01, 0], outline: .003, parent: non });
  const pialaD = prop(mesh(new THREE.CylinderGeometry(.045, .03, .045, 14), toon(0x2a6bb0), { outline: .003 }));
  const cups = [0, 1].map(() => { const g = prop(new THREE.Group());
    mesh(new THREE.CylinderGeometry(.04, .032, .13, 14), toon(0xf2efe6), { outline: .003, parent: g });
    mesh(new THREE.CylinderGeometry(.042, .042, .015, 14), toon(0x5a3a22), { pos: [0, .07, 0], outline: .002, parent: g });
    mesh(new THREE.CylinderGeometry(.041, .041, .04, 14), toon(0xc87a3a), { pos: [0, -.005, 0], outline: false, parent: g }); return g; });
  const phones = Array.from({ length: 9 }, (_, i) => { const g = prop(new THREE.Group());
    mesh(new THREE.BoxGeometry(.072, .148, .011), toon(0x15171c), { outline: .002, parent: g });
    mesh(new THREE.PlaneGeometry(.064, .136), glow([0x9fd8ff, 0xffd0a0, 0xc0ffd8][i % 3], 1.3), { pos: [0, 0, -.0062], rot: [0, Math.PI, 0], outline: false, parent: g }); return g; });
  const trays = [0, 1].map(i => { const g = prop(new THREE.Group());
    mesh(new THREE.BoxGeometry(.46, .02, .32), toon([0xe0874a, 0x2f8a4a][i]), { outline: .004, parent: g });
    mesh(new THREE.CylinderGeometry(.1, .075, .03, 14), toon(0xffffff), { pos: [-.08, .02, 0], outline: .003, parent: g });
    mesh(new THREE.SphereGeometry(.07, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), toon(0xf0c060), { pos: [-.08, .03, 0], scale: [1, .5, 1], outline: .003, parent: g });
    mesh(new THREE.CylinderGeometry(.035, .03, .09, 10), toon([0xe85a5a, 0x3a8ad0][i]), { pos: [.13, .055, .05], outline: .003, parent: g }); return g; });
  const spoon = prop(new THREE.Group());
  mesh(new THREE.CylinderGeometry(.006, .006, .13, 6), toon(0xc9ced6), { pos: [0, -.04, 0], outline: false, parent: spoon });
  mesh(new THREE.SphereGeometry(.018, 8, 6), toon(0xc9ced6), { pos: [0, -.11, .006], scale: [1, 1.4, .5], outline: false, parent: spoon });
  const phones2 = phones;
  // наушники Тимура
  const phonesH = prop(new THREE.Group());
  mesh(new THREE.TorusGeometry(.115, .012, 6, 20, Math.PI), toon(0x1a1d24), { pos: [0, .14, .0], outline: .003, parent: phonesH });
  for (const sx of [1, -1]) mesh(new THREE.CylinderGeometry(.042, .042, .03, 14), toon(0xe8343c), { pos: [sx * .118, .135, 0], rot: [0, 0, Math.PI / 2], outline: .003, parent: phonesH });
  // звёздочки над головой Азима
  const starT = canvasTex(64, 64, g => { g.fillStyle = '#ffe23d'; g.strokeStyle = '#000'; g.lineWidth = 4; g.beginPath(); for (let i = 0; i < 10; i++) { const r = i % 2 ? 12 : 28, a = i / 10 * Math.PI * 2 - Math.PI / 2; g.lineTo(32 + Math.cos(a) * r, 32 + Math.sin(a) * r); } g.closePath(); g.fill(); g.stroke(); });
  const stars = prop(new THREE.Group());
  const starS = Array.from({ length: 4 }, () => { const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: starT, depthTest: false })); s.scale.setScalar(.09); s.renderOrder = 5; stars.add(s); return s; });
  // газета (тизер)
  const newsT = canvasTex(256, 340, g => { g.fillStyle = '#ebe6d8'; g.fillRect(0, 0, 256, 340); g.fillStyle = '#1a1a1a'; g.font = '900 22px Unbounded'; g.fillText('НОВОГРАД', 14, 32); g.fillRect(10, 40, 236, 3);
    g.font = '900 28px Rubik'; g.fillText('ГЕРОЙ', 14, 80); g.fillText('С МОСТА', 14, 110); g.fillStyle = '#5a6a7a'; g.fillRect(14, 124, 228, 110);
    g.strokeStyle = '#e8343c'; g.lineWidth = 5; g.beginPath(); g.moveTo(20, 200); g.lineTo(236, 200); g.stroke(); g.fillStyle = '#f2f2ee'; g.save(); g.translate(130, 196); g.rotate(.35); g.fillRect(0, -10, 60, 18); g.restore();
    g.fillStyle = '#333'; for (let i = 0; i < 8; i++) g.fillRect(14, 248 + i * 11, 100 + (i * 37) % 120, 5); });
  const paper = prop(mesh(new THREE.PlaneGeometry(.34, .45), toon(0xffffff, { map: newsT, side: THREE.DoubleSide }), { outline: false }));
  const paperBall = prop(mesh(new THREE.IcosahedronGeometry(.075, 1), toon(0xffffff, { map: newsT }), { outline: .004 }));

  /* ---------- персонажи: сидячие/стоячие «посты» ---------- */
  const seat = (r, c, side) => [-3.0 + c * 2.7 + (side ? .32 : -.32), 0, -1.6 + r * 1.6 + .55];   // класс
  const stoolA = (i, south) => [-3.2 - 1.35 + i * .9, 0, .8 + (south ? .85 : -.85)];               // столовая, стол A

  /* ================================================================
     ХОЛОДНОЕ НАЧАЛО: кухня, утро (0 – 14)
     ================================================================ */
  const dedAt = (t, o = {}) => {
    place(DE, K, [-.55, 0, -1.45], 0);
    let p = sit(t);
    if (o.sip) { const k = o.sip; p = blend(p, { ...p, armR: [-1.25, .45, .25], foreR: [-1.9, 0, 0], handR: [.2, 0, .3], head: [-.08, 0, 0] }, k); }
    if (o.p) p = { ...p, ...o.p };
    DE.pose(talking(p, 'ded', t, o.gest ?? .8, 'L'));
    hold(pialaD, DE, 'R', [0, -.09, .045]);
    face(DE, 'ded', t, { seed: 2, at: o.at, atK: o.atK ?? .9, ...o.face });
  };
  shot(0, 5.2, (lt, t) => {
    const tvp = KD.tvPos;
    dedAt(t, { sip: pulse(t, 1.2, 4.2, .6, .6), at: [tvp.x, tvp.y + .25, tvp.z], atK: 1 - pulse(t, 1.4, 4.0, .4, .4) * .6 });
    const tv = KD.tvPos, k = E.inOutSine(P(lt, 0, 5.2));
    look([lerp(tv.x - .35, tv.x + .06, k), lerp(tv.y + .8, tv.y + .3, k), lerp(tv.z + 2.7, tv.z + .95, k)], [lerp(tv.x + .25, tv.x + .01, k), lerp(tv.y + .1, tv.y + .24, k), tv.z], lerp(46, 34, k));
    fadeIn(lt, 1.0);
    caption('Старый Затон.\nУтро после моста', 60, 60, lt - 1.0, { dur: 3.6 });
    return K;
  });
  shot(5.2, 10.6, (lt, t) => {
    const turn = E.inOutSine(P(t, 5.9, .5));
    dedAt(t, { sip: 1 - E.inOutSine(P(t, 5.3, .6)), p: { spine: [.08, .3 * turn, 0] }, at: [lerp(-1.25, 3.4, turn), lerp(1.15, 1.6, turn), lerp(-2.7, .6, turn)], face: { brow: -.4 * turn - .3 * talkK('ded', t) } });
    const k = E.inOutSine(P(lt, 0, 5.4));
    look([lerp(1.3, 1.05, k), 1.32, lerp(.75, .35, k)], [-.55, 1.12, -1.45], lerp(40, 34, k));
    return K;
  });
  shot(10.6, 14, (lt, t) => {
    // Тимур: влетает, хватает лепёшку, пятится к двери, подмигивает — и исчезает
    const pos = kf(t, [[10.6, [3.3, 0, .55]], [10.95, [.95, 0, -.05], E.outCubic], [11.6, [1.0, 0, 0]], [12.9, [2.55, 0, .45], E.inOutSine], [13.25, [4.2, 0, .6], E.inQuad]]);
    const yaw = t < 11.0 ? -Math.PI / 2 : t < 12.95 ? lerp(-Math.PI / 2 - .9, -Math.PI / 2 - .5, P(t, 11, 1.9)) : Math.PI / 2;
    place(TI, K, pos, yaw);
    let p;
    if (t < 10.95) p = POSE.run(t * 1.4, 2.0);
    else if (t < 11.25) p = { ...POSE.reach(), armR: [-1.1, .2, .1], spine: [.4, 0, 0] };
    else if (t < 12.95) p = talking({ ...POSE.walk(-(t - 11.25) * .9), armR: [-.6, .2, .2], foreR: [-1.3, 0, 0], handR: [0, 0, .3] }, 'timur', t, 1, 'L');
    else p = POSE.run(t * 1.8, 2.2);
    TI.pose(p);
    squash(TI, springAt(t, 10.97, -.07, 16, 8));            // резкая остановка у стола
    dedAt(t, { p: { spine: [.08, .3, 0] }, gest: 0, at: t < 13.2 ? headW(TI) : [3.4, 1.5, .6], face: { brow: t > 13.3 ? .4 : -.2, smile: t > 13.4 ? .8 : 0 } });
    face(TI, 'timur', t, { smile: .8, brow: .4, blink: t > 12.6 && t < 12.85 ? 1 : undefined, energy: .6, at: t > 11.1 && t < 12.95 ? headW(DE) : undefined, atK: .8 });
    if (t >= 11.05) hold(non, TI, 'R', [0, -.11, .05], [1.3, 0, 0]);
    else put(non, K, [.5, .86, -.3]);
    if (t > 13.1) D.speedLines(1 - P(t, 13.1, .6), t);
    // кот на подоконнике подпрыгивает от хлопка двери
    const cat = KD.cat.head.parent, j = Math.max(0, Math.sin(Math.PI * P(t, 13.3, .45)));
    cat.position.y = 1.1 + .28 * j; cat.rotation.z = .15 * j;
    if (t > 13.25) comic('ХЛОП!', 1500, 420, t - 13.3, { size: .55, rot: .1, dur: .7 });
    look([-1.9, 1.45, 2.35], [.9, 1.0, -.45], 46);
    fadeOut(lt, 3.4, .25);
    return K;
  });
  D.onReset(() => { const cat = KD.cat.head.parent; cat.position.y = 1.1; cat.rotation.z = 0; });

  /* заставка серии */
  shot(14, 18.5, (lt, t) => { D.logo(lt, 'СЕРИЯ 2 · ЛИЧНАЯ ЖИЗНЬ'); fadeOut(lt, 4.5, .35); look([0, 1.5, 3], [0, 1, 0], 45); return K; }, { noSubs: true });

  /* ================================================================
     СЦЕНА 1. Ворота лицея, утро (18.5 – 41)
     ================================================================ */
  const ZS = Z.scene;
  // школьники идут к дверям: маршрут, старт, скорость
  const GATE = [
    [0, [[SX - 24, 0, 18.2], [SX - 2, 0, 17.6], [SX - 1, 0, 14], [SX - .6, 0, 4.6]], 15.2, 1.2],
    [1, [[SX - 30, 0, 18.6], [SX - 1.6, 0, 17.8], [SX - .8, 0, 14], [SX - .2, 0, 4.6]], 14.0, 1.3],
    [2, [[SX + 26, 0, 18.4], [SX + 1.8, 0, 17.6], [SX + 1, 0, 14], [SX + .4, 0, 4.6]], 14.5, 1.2],
    [3, [[SX + 20, 0, 19.0], [SX + 2.4, 0, 17.8], [SX + 1.3, 0, 13], [SX + .8, 0, 4.6]], 17.0, 1.25],
    [4, [[SX - 18, 0, 17.6], [SX - 2.4, 0, 17.4], [SX - 1.6, 0, 12], [SX - 1, 0, 4.6]], 18.0, 1.15],
    [5, [[SX + 32, 0, 18.0], [SX + 1.2, 0, 17.6], [SX + .5, 0, 13], [SX, 0, 4.6]], 15.5, 1.35],
    [6, [[SX - 9, 0, 13], [SX - 6, 0, 8], [SX - 1.6, 0, 4.8]], 18.6, 1.0],
    [7, [[SX + 9, 0, 12], [SX + 5, 0, 8], [SX + 1.4, 0, 4.8]], 19.6, 1.05],
    [10, [[SX - 36, 0, 18.4], [SX - 1.4, 0, 17.6], [SX - .6, 0, 14], [SX - .3, 0, 4.6]], 25.0, 1.5],
    [11, [[SX + 34, 0, 18.4], [SX + 1.6, 0, 17.6], [SX + .6, 0, 14], [SX + .3, 0, 4.6]], 26.0, 1.5],
    [12, [[SX + 30, 0, 19.0], [SX + 2, 0, 17.8], [SX + 1.0, 0, 13], [SX + .5, 0, 4.6]], 33.6, 2.2],
    [13, [[SX - 28, 0, 18.8], [SX - 2.2, 0, 17.8], [SX - 1.2, 0, 13], [SX - .5, 0, 4.6]], 33.9, 2.3],
  ];
  const gateKids = t => {
    for (const [i, pts, t0, sp] of GATE) {
      const r = walk(ST(i), ZS, pts, t, t0, sp, { run: sp > 2 });
      if (r.done) { ST(i).root.visible = false; continue; }
      face(ST(i), 's', t, { seed: i % 5, smile: .3 });
    }
    // кучки у клумб и флагов: болтают, смотрят в телефон, машут друзьям; после звонка — бегут внутрь
    if (t < 34.3) {
      const a14 = extra(14, ZS, [SX + 14.5, 0, 11.5], -1.9, t, 'talk', { at: headW(ST(15)) }); extra(15, ZS, [SX + 13.4, 0, 11.2], 1.3, t, 'listen');
      ST(15).root.updateMatrixWorld(true);
      extra(8, ZS, [SX - 15, 0, 12.6], .6, t, 'phone', { at: false }); hold(phones[8], ST(8), 'R', [0, -.1, .04], [-.3, 0, 0]);
      extra(16, ZS, [SX - 9.6, 0, 9.4], 1.1, t, 'talk'); extra(17, ZS, [SX - 8.6, 0, 9.9], -2.0, t, 'laugh'); extra(18, ZS, [SX - 9.0, 0, 8.6], -.3, t, 'listen');
      extra(19, ZS, [SX + 7.2, 0, 6.2], .4, t, (tt, s) => ({ ...POSE.crouch(), spine: [.7, 0, 0], armL: [-1.0, 0, .2], foreL: [-.6 + .2 * Math.sin(tt * 9), 0, 0], armR: [-1.0, 0, .2], foreR: [-.6, 0, 0], head: [.4, 0, 0] }), { at: false });  // завязывает шнурок
    } else { for (const [i, p0] of [[14, [SX + 14.5, 0, 11.5]], [15, [SX + 13.4, 0, 11.2]], [16, [SX - 9.6, 0, 9.4]], [17, [SX - 8.6, 0, 9.9]], [18, [SX - 9, 0, 8.6]], [19, [SX + 7.2, 0, 6.2]]]) {
      const r = walk(ST(i), ZS, [p0, [SX + (i % 2 ? .4 : -.4), 0, 6], [SX, 0, 3.6]], t, 34.3 + (i % 3) * .25, 2.6, { run: true }); if (r.done) ST(i).root.visible = false; else face(ST(i), 's', t, { seed: i % 5, smile: .2, energy: .6 }); } }
    // по тротуару мимо ограды идут прохожие; девочка машет подруге
    for (const [i, a, b, sp, ph] of [[20, [SX - 40, 0, 18.9], [SX + 40, 0, 18.9], 1.1, 0], [21, [SX + 38, 0, 19.2], [SX - 38, 0, 19.2], 1.0, 9]]) stroll(i, ZS, a, b, t, sp, ph);
    if (t < 34.3) { const wave = Math.max(0, Math.sin(t * 1.3)); extra(22, ZS, [SX + 5.5, 0, 12.6], 2.6, t, (tt, s) => ({ ...LIFE.stand(tt, s), armR: [-2.6, 0, .4 + .25 * Math.sin(tt * 10) * wave], foreR: [-.5, 0, 0], gripR: 0 }), { smile: .8, at: [SX - 9, 1.5, 9.4] }); }
  };
  const diyorGate = (t, pose) => {
    place(DI, ZS, [SX + 2.45, 0, 17.65], -Math.PI / 2 - .12);
    DI.pose(pose); face(DI, 'diyor', t, { seed: 4, smile: .35, brow: .2, energy: .3, at: t > 19.4 && t < 34.4 ? [SX + 1.25, 1.55, 17.7] : t < 19.4 && t > 18.9 ? [SX - 12, 1.4, 18] : undefined, atK: .85 });
  };
  shot(18.5, 21.0, (lt, t) => {
    Z.setTime('morning'); gateKids(t);
    // Диёр ждёт: два стакана, смотрит на часы
    const watch = pulse(t, 18.6, 19.7, .3, .3);
    diyorGate(t, { ...POSE.stand(t), armL: [-.9 * watch - .2, -.4 * watch, .15], foreL: [-1.6 * watch - .5, 0, 0], handL: [0, 0, .4 * watch], armR: [-.6, 0, .15], foreR: [-.9, 0, 0], head: [.3 * watch, .4 * (1 - watch), 0] });
    hold(cups[0], DI, 'R', [0, -.1, .045]); hold(cups[1], DI, 'L', [0, -.1, .045]);
    // Тимур подбегает
    const r = walk(TI, ZS, [[SX - 30, 0, 18.3], [SX + 1.25, 0, 17.7]], t, 16.2, 9.6, { run: true, endYaw: Math.PI / 2 + .1, end: tt => FIGHT.tired(tt) });
    face(TI, 'timur', t, { smile: .4, energy: .7 });
    move(t, [[18.5, [SX + 15, 10, 44], [SX, 6.5, 0], 40], [21.0, [SX + 6.5, 2.0, 27.5], [SX + 1.4, 1.9, 15.5], 36]], E.inOutSine);
    fadeIn(lt, .5);
    return ZS;
  });
  shot(21.0, 24.4, (lt, t) => {
    Z.setTime('morning'); gateKids(t);
    diyorGate(t, talking({ ...POSE.stand(t), armR: [-.6, 0, .15], foreR: [-.9, 0, 0] }, 'diyor', t, 1, 'L'));
    hold(cups[0], DI, 'R', [0, -.1, .045]); hold(cups[1], DI, 'L', [0, -.1, .045]);
    place(TI, ZS, [SX + 1.25, 0, 17.7], Math.PI / 2 + .1);
    const rub = pulse(t, 22.5, 24.2, .3, .3);
    TI.pose(blend(seq(t - 21, [[0, tt => FIGHT.tired(tt + 21)], [.9, tt => POSE.stand(tt)]], .5), { ...POSE.stand(t), armR: [-2.3, .5, .5], foreR: [-2.0, 0, 0], handR: [0, 0, .3], head: [.2, 0, .1] }, rub));
    face(TI, 'timur', t, { smile: .3, squint: 1 - .3 * rub, at: headW(DI), atK: .8 - .5 * rub });
    look([SX + 1.9, 1.5, 21.4], [SX + 1.9, 1.32, 17.6], 36);
    return ZS;
  });
  shot(24.4, 29.1, (lt, t) => {
    Z.setTime('morning'); gateKids(t);
    const give = E.inOutSine(P(t, 24.5, .5)), back = E.inOutSine(P(t, 25.3, .4)), show = pulse(t, 25.9, 29.1, .4, .1);
    diyorGate(t, talking({ ...POSE.stand(t), armL: [-1.0 * give * (1 - back) - .2, 0, .15], foreL: [-.9 + .5 * give * (1 - back), 0, 0],
      armR: [-.6 - .7 * show, .3 * show, .15], foreR: [-.9 - .9 * show, 0, 0], handR: [0, 0, .5 * show], head: [.1, 0, 0] }, 'diyor', t, .6, 'L'));
    hold(cups[0], DI, 'R', [0, -.1, .045]);
    if (show > 0) { hold(phones[0], DI, 'R', [0, -.1, .045], [-.4, 0, 0]); cups[0].visible = false; }
    place(TI, ZS, [SX + 1.25, 0, 17.7], Math.PI / 2 + .1);
    TI.pose({ ...POSE.stand(t), armR: [-.75 * Math.max(back, give * .6), .2, .15], foreR: [-1.1, 0, 0] });
    face(TI, 'timur', t, { smile: .2, at: show > .3 ? handW(DI, 'R') : headW(DI), atK: .8 });
    hold(cups[1], t < 25.2 ? DI : TI, t < 25.2 ? 'L' : 'R', [0, -.1, .045]);
    ots(TI, DI, -1, 36, 1.35, .25, .95);
    // телефон Диёра: видео очевидца с моста
    const phk = pulse(t, 26.3, 29.1, .35, .15);
    if (phk > 0) {
      props.busPivot.visible = true; props.busPivot.position.set(455, 0, -386); props.busPivot.rotation.set(.62, 0, 0);
      props.bus.userData.body.rotation.z = Math.sin(t * 2.3) * .03;
      props.busPivot.updateMatrixWorld(true);
      const rear = props.bus.localToWorld(V(0, 1.6, -6));
      props.webs.add(V(452, .9, -393.5), rear, { k: 1, w: .06, wob: .05, wobT: t });
      props.webs.add(V(458, .9, -393.5), rear.clone().add(V(.6, 0, 0)), { k: 1, w: .06, wob: .05, wobT: t + 1 });
      D.panel(1, phk * 1.01, [1380, 96, 380, 660], city.scene, [472 + Math.sin(t * 1.3) * .3, 4.2, -421 + Math.sin(t * .9) * .2], [455, -2, -389], 30, .05 * Math.sin(t * 1.1), (o, x, y, w, h) => o.phoneFrame(x, y, w, h, t, 26.3));
    }
    return ZS;
  });
  shot(29.1, 33.4, (lt, t) => {
    Z.setTime('morning'); gateKids(t);
    const sip = pulse(t, 29.0, 29.9, .3, .3);
    place(TI, ZS, [SX + 1.25, 0, 17.7], Math.PI / 2 + .1);
    TI.pose(talking({ ...POSE.stand(t), armR: [-.75 - .55 * sip, .3 * sip, .15], foreR: [-1.1 - .9 * sip, 0, 0], handR: [0, 0, .4 * sip] }, 'timur', t, .7, 'L'));
    hold(cups[1], TI, 'R', [0, -.1, .045]);
    face(TI, 'timur', t, { smile: t < 31.3 ? .15 : .55, look: [t < 31.3 ? -.5 : .1, -.1], brow: .1, at: t > 31.3 ? headW(DI) : undefined });
    const indig = talkK('diyor', t);
    diyorGate(t, { ...POSE.shrug(t), armL: [-.2 - .6 * indig, 0, .45 + .3 * indig], armR: [-.2 - .6 * indig, 0, .45 + .3 * indig], foreL: [-1.3, 0, 0], foreR: [-1.3, 0, 0] });
    hold(cups[0], DI, 'L', [0, -.1, .045]); hold(phones[0], DI, 'R', [0, -.1, .045], [-.4, 0, 0]);
    if (t < 31.3) close(TI, [-.32, .03, .95], 30);
    else ots(TI, DI, -1, 36, 1.3, .2, .65);
    return ZS;
  });
  shot(33.4, 41.0, (lt, t) => {
    Z.setTime('morning'); gateKids(t);
    // звонок! друзья бегут к дверям
    const r1 = walk(TI, ZS, [[SX + 1.25, 0, 17.7], [SX + .2, 0, 15.4], [SX - .2, 0, 6.5], [SX - .3, 0, 3.4]], t, 34.6, 4.6, { run: true });
    const r2 = walk(DI, ZS, [[SX + 2.45, 0, 17.65], [SX + 1.2, 0, 15.4], [SX + .6, 0, 6.5], [SX + .3, 0, 3.4]], t, 34.75, 4.3, { run: true });
    if (t < 34.6) { TI.pose(POSE.stand(t)); place(TI, ZS, [SX + 1.25, 0, 17.7], Math.PI / 2 + .1 - P(t, 34.0, .5) * 1.3); DI.pose(POSE.stand(t)); place(DI, ZS, [SX + 2.45, 0, 17.65], -Math.PI / 2 - .12 - P(t, 34.1, .5) * 1.3); }
    if (r1.done) TI.root.visible = false; if (r2.done) DI.root.visible = false;
    hold(cups[1], TI, 'R', [0, -.1, .045]); hold(cups[0], DI, 'L', [0, -.1, .045]);
    face(TI, 'timur', t, { smile: .4, energy: .6 }); face(DI, 'diyor', t, { seed: 4, smile: .2, energy: .6, look: [0, .3] });
    if (t > 33.9) comic('ДЗЫНЬ!', 420, 230, t - 33.95, { size: .55, rot: -.1, dur: .9, color: '#ffffff', burstColor: '#ffe23d' });
    move(t, [[33.4, [SX + 2.0, 1.55, 21.2], [SX + 1.6, 1.4, 17.6], 38], [35.4, [SX + 4.5, 2.2, 23.5], [SX + .5, 1.8, 12], 40], [41, [SX + 3, 9.5, 32], [SX, 7, 0], 42]], E.inOutSine);
    fadeOut(lt, 7.6, .4, '#fff');
    return ZS;
  });

  /* ================================================================
     СЦЕНА 2. Класс физики (41 – 66)
     ================================================================ */
  const CS = CL.scene;
  const SEATS = { 0: seat(0, 0, 0), 1: seat(0, 0, 1), 2: seat(0, 1, 1), 3: seat(0, 2, 0), 4: seat(0, 2, 1), 5: seat(1, 0, 0), 6: seat(1, 2, 1), 7: seat(2, 0, 1),
    10: seat(2, 1, 1), 11: seat(2, 2, 0), 12: seat(2, 2, 1), 13: seat(3, 2, 0), 14: seat(0, 1, 0), 15: seat(3, 2, 1), 8: seat(3, 0, 1), 9: seat(3, 1, 1),
    16: seat(1, 0, 1), 17: seat(2, 0, 0), 18: seat(3, 0, 0) };
  const CLASS_MODE = { 1: 'write', 5: 'yawn', 12: 'chin', 17: 'write', 3: 'write', 13: 'chin' };
  const AZS = seat(3, 1, 0), TIS = seat(1, 1, 0), DIS = seat(1, 1, 1), MJS = seat(1, 2, 0);
  /** класс: все смотрят на учительницу (o.focus — на кого), o.laugh — смеются, оборачиваются к Азиму */
  const classLife = (t, o = {}) => {
    TE.root.updateMatrixWorld(true);
    const teach = TE.root.visible ? headW(TE) : V(.5, 1.55, -3.85);
    for (const [i, p] of Object.entries(SEATS)) {
      const laugh = o.laugh ? o.laugh * (i % 3 ? 1 : .6) : 0, m = CLASS_MODE[i] || 'sit';
      const at = o.focus ? (o.focus.isVector3 ? o.focus : V(...o.focus)) : laugh > .2 && o.azim ? o.azim : teach;
      extra(+i, CS, p, Math.PI, t, (tt, s) => {
        const b = LIFE[o.focus && m !== 'sit' ? 'sit' : m](tt, s);
        return laugh > 0 ? blend(b, { ...b, spine: [-.1 + .06 * Math.sin(tt * 15 + s), .15 * Math.sin(s * 3), 0], armL: [-.5, 0, .3], foreL: [-1.6, 0, 0] }, laugh) : b;
      }, { who: laugh > 0 ? 'crowd' : undefined, smile: .3 + laugh * .7, mk: laugh, at, atK: m === 'write' && !o.focus ? .25 : .8 });
    }
  };
  const teacherBoard = (t, p, yaw = 0) => { place(TE, CS, p, yaw); };
  const diyorDesk = (t, at) => { place(DI, CS, DIS, Math.PI); DI.pose(talking(at ? LIFE.sit(t, 4) : LIFE.write(t, 4), 'diyor', t, .5)); face(DI, 'diyor', t, { seed: 4, at: at || (TE.root.visible ? headW(TE) : undefined), atK: at ? .9 : .3 }); };
  const marjonDesk = (t, o = {}) => { place(MJ, CS, MJS, Math.PI); MJ.pose(o.p || sit(t, { head: [.08, .15 * Math.sin(t * .4), 0], armL: [-.9, -.2, .1], foreL: [-1.3, 0, 0], armR: [-.8, .2, .1], foreR: [-1.2 + .1 * Math.sin(t * 5), 0, 0] }));
    face(MJ, 'marjon', t, { seed: 3, smile: .3, at: o.at === undefined ? (TE.root.visible ? headW(TE) : undefined) : o.at || undefined, atK: .7, ...o.face }); MJ.sketch.visible = !!o.sketch; };
  const azimDesk = (t, p, f = {}) => { place(AZ, CS, AZS, Math.PI); AZ.pose(p); face(AZ, 'azim', t, { seed: 5, mouth: talkK('azim', t) > 0 ? undefined : .12 + .1 * Math.sin(t * 7), ...f }); AZ.gum.visible = true; };   // жуёт жвачку
  const timurDesk = (t, p, f = {}) => { place(TI, CS, TIS, Math.PI); TI.pose(p); face(TI, 'timur', t, f); };
  // полёт бумажного комка: из руки Азима в затылок Тимура (сюжетное время, с замедлением чутья)
  const PAPER0 = 49.15, PAPER1 = 51.0;
  const paperAt = t => { const k = P(t, PAPER0, PAPER1 - PAPER0); const a = V(AZS[0] + .18, 1.42, AZS[2] - .3), b = V(TIS[0] - .05, 1.5, TIS[2] + .2);
    const q = a.clone().lerp(b, k); q.y += Math.sin(Math.PI * k) * .35; return q; };
  shot(41, 47.3, (lt, t) => {
    U.sense.value = 0;
    classLife(t); diyorDesk(t); marjonDesk(t);
    azimDesk(t, sit(t, { spine: [-.05, 0, 0], legL: [-1.35, 0, .3], legR: [-1.4, 0, .3] }), { smile: .2, squint: .8 });
    timurDesk(t, sit(t, { armR: [-.8, 0, .1], foreR: [-1.6, 0, 0], handR: [0, 0, .2], head: [-.1, .05, 0] }), { look: [0, .3], smile: .1 });
    // учительница пишет и поворачивается к классу
    const turn = E.inOutSine(P(t, 43.4, .7));
    teacherBoard(t, [.5, 0, -3.85], lerp(Math.PI, .15, turn));
    TE.pose(talking(blend({ ...POSE.stand(t), armR: [-2.3, -.2, .3], foreR: [-.5 + .15 * Math.sin(t * 9), 0, 0], handR: [-.3, 0, 0], gripR: .8 }, { ...POSE.stand(t), armR: [-.4, 0, .2], foreR: [-1.4, 0, 0], gripR: .8 }, turn), 'teacher', t, 1, 'L'));
    TE.chalk.visible = true; face(TE, 'teacher', t, { seed: 6, brow: .2, at: turn > .5 ? [0, 1.2, 1.5] : [.6, 1.9, -4.5], atK: .8 });
    move(t, [[41, [.4, 1.65, 3.9], [.3, 1.55, -3.6], 40], [47.3, [.3, 1.55, 1.9], [.4, 1.5, -3.7], 36]], E.inOutSine);
    fadeIn(lt, .4, '#fff');
    return CS;
  });
  shot(47.3, 49.2, (lt, t) => {
    const lg = pulse(t, 47.25, 48.6, .1, .5);
    const azH = V(AZS[0], 1.35, AZS[2]);
    classLife(t, { laugh: lg, azim: azH }); diyorDesk(t, lg > .2 ? azH : undefined); marjonDesk(t, { at: lg > .2 ? azH : undefined, face: { smile: .2 + .5 * lg } });
    // Азим «играет мускулами», потом мнёт бумажку и прицеливается
    const flex = pulse(t, 47.2, 48.3, .2, .3), aim = E.inOutSine(P(t, 48.4, .6));
    azimDesk(t, blend(blend(sit(t), { ...sit(t), hy: -.3, spine: [-.1, 0, 0], armR: [-.3, -.2, 1.35], foreR: [-2.1, 0, 0], armL: [-.3, .2, 1.3], foreL: [-2.0, 0, 0], grip: 1 }, flex),
      { ...sit(t), spine: [-.15, -.3, 0], armR: [-.6, .5, .9], foreR: [-1.9, 0, 0], grip: .9, head: [.05, .2, 0] }, aim), { smile: .8, squint: .7 + .3 * flex, look: [aim * .2, .1] });
    if (aim > .3) hold(CL.paper, AZ, 'R', [0, -.1, .04]);
    place(ST(8), CS, SEATS[8], Math.PI);
    timurDesk(t, sit(t, { armR: [-.8, 0, .1], foreR: [-1.6, 0, 0], handR: [0, 0, .2] }), { look: [0, .2] });
    place(TE, CS, [.5, 0, -3.85], .15); TE.pose({ ...POSE.stand(t), armR: [-.4, 0, .2], foreR: [-1.4, 0, 0], armL: [-.5, 0, .3], foreL: [-1.9, 0, 0] }); TE.chalk.visible = true; face(TE, 'teacher', t, { seed: 6, brow: -.4, at: azH, squint: .8 });
    look([AZS[0] + .55, 1.3, AZS[2] - 1.35], [AZS[0] - .05, 1.15, AZS[2]], 38);
    return CS;
  });
  shot(49.2, 50.35, (lt, t) => {
    // паучье чутьё: мир синеет, комок летит медленно; Тимур не оборачивается — только глаза
    const k = pulse(t, 49.2, 51.6, .25, .3);
    sense(t, k, 49.2);
    classLife(t); diyorDesk(t); marjonDesk(t);
    azimDesk(t, { ...sit(t), spine: [-.1, .25, 0], armR: [-1.4, .3, .3], foreR: [-.3, 0, 0], grip: .2 }, { smile: .8 });
    CL.paper.visible = true; put(CL.paper, CS, paperAt(t).toArray());
    timurDesk(t, sit(t, { armR: [-.8, 0, .1], foreR: [-1.6, 0, 0], handR: [0, 0, .2], head: [-.05, -.06 * P(t, 49.6, .3), 0] }), { look: [-.85 * E.outCubic(P(t, 49.55, .2)), .15], squint: 1 - .35 * P(t, 49.5, .3), noBlink: true });
    const h = headW(TI); D.ring(h.clone().add(V(0, .02, .05)), .25 + .5 * P(t, 49.4, .8), 1 - P(t, 49.4, .9), 0x9ff8ff);
    look([TIS[0] + .08, 1.3, TIS[2] - .95], [TIS[0], 1.28, TIS[2]], 30);
    return CS;
  });
  shot(50.35, 51.5, (lt, t) => {
    const k = pulse(t, 49.2, 51.55, .25, .3);
    sense(t, k, 49.2);
    classLife(t); diyorDesk(t); marjonDesk(t, { face: { look: [-.8, 0], wide: t > 51 } });
    azimDesk(t, { ...sit(t), spine: [-.1, .25, 0], armR: [-1.4, .3, .3], foreR: [-.3, 0, 0], grip: .2 }, { smile: .8 * (1 - P(t, 51.05, .2)), wide: t > 51.1 });
    // рука взлетает и ловит комок за затылком, не глядя
    const up = E.outBack(P(t, 50.55, .35));
    timurDesk(t, sit(t, { armL: [-.8, 0, .1], foreL: [-1.6, 0, 0], armR: [-.8 - 2.0 * up, .1, .1 + .2 * up], foreR: [-1.6 * (1 - up) - .9 * up, 0, 0], grip: t > PAPER1 ? .95 : .2 }), { look: [-.6, .1] });
    const pp = t < PAPER1 ? paperAt(t) : handW(TI, 'R');
    if (t < PAPER1) put(CL.paper, CS, pp.toArray()); else hold(CL.paper, TI, 'R', [0, -.09, .02]);
    if (up > 0 && t < PAPER1 + .2) ikArm(TI, 'R', paperAt(Math.min(t + .05, PAPER1)), V(-.4, -.2, .6), up);
    if (t > PAPER1 - .02) { comic('ХВАТЬ!', 1180, 300, t - PAPER1, { size: .5, rot: .08, dur: .6 }); }
    look([TIS[0] + 1.05, 1.5, TIS[2] + 1.45], [TIS[0] - .05, 1.38, TIS[2] + .15], 34);
    return CS;
  });
  shot(51.5, 53.07, (lt, t) => {
    const tiH = V(TIS[0], 1.3, TIS[2]);
    classLife(t, { focus: tiH }); diyorDesk(t, tiH);
    timurDesk(t, sit(t, { armR: [-.8, 0, .1], foreR: [-1.6, 0, 0], handR: [0, 0, .2], grip: .95 }), { smile: .15 });
    hold(CL.paper, TI, 'R', [0, -.09, .02]);
    if (t < 52.2) {   // Азим: челюсть отвисла
      azimDesk(t, { ...sit(t), spine: [-.15, 0, 0], armR: [-1.2, .3, .3], foreR: [-.3, 0, 0], grip: .2 }, { wide: true, mouth: .5, brow: .9 });
      AZ.gum.visible = false;
      close(AZ, [-.28, .02, .95], 32);
    } else {         // Маржон всё видела — улыбается краешком рта
      marjonDesk(t, { at: tiH, p: sit(t, { armL: [-.9, -.2, .1], foreL: [-1.7, 0, 0], handL: [0, 0, .4] }), face: { smile: .7, brow: .5 } });
      close(MJ, [.32, .01, .92], 30, [-.02, -.06, 0]);
    }
    return CS;
  });
  shot(53.07, 56.6, (lt, t) => {
    TI.root.updateMatrixWorld(true);
    const tiNow = t < 54.25 ? V(TIS[0], 1.3, TIS[2]) : V(...path([[TIS[0], 0, TIS[2]], [TIS[0] - .9, 0, TIS[2] - .4], [-1.25, 0, -2.4], [-.8, 0, -3.35]], (t - 54.25) * 1.25).p).add(V(0, 1.55, 0));
    classLife(t, { focus: t > 53.6 ? tiNow : undefined }); diyorDesk(t, t > 53.6 ? tiNow : undefined); marjonDesk(t, { at: t > 53.6 ? tiNow : undefined });
    azimDesk(t, sit(t), { squint: .7, at: tiNow });
    // «Арсланов! К доске!» — палец; Тимур встаёт и идёт к доске
    place(TE, CS, [.5, 0, -3.85], .15); TE.pose(talking(seq(t - 53.07, [[0, tt => POSE.pointFinger(tt)], [2.6, tt => POSE.stand(tt)]], .4), 'teacher', t, .4, 'L'));
    face(TE, 'teacher', t, { seed: 6, brow: .4, squint: .85, at: tiNow });
    const r = walk(TI, CS, [[TIS[0], 0, TIS[2]], [TIS[0] - .9, 0, TIS[2] - .4], [-1.25, 0, -2.4], [-.8, 0, -3.35]], t, 54.25, 1.25, { endYaw: Math.PI - .25 });
    if (t < 54.25) { place(TI, CS, TIS, Math.PI); TI.pose(seq(t - 53.07, [[0, tt => sit(tt)], [.65, tt => POSE.stand(tt), .5]])); }
    face(TI, 'timur', t, { brow: .45, look: [.3, .1] });
    if (t < 54.4) look([.1, 1.25, -1.6], [.5, 1.6, -3.85], 34);
    else move(t, [[54.4, [1.6, 1.75, 4.2], [-.6, 1.25, -2.4], 40], [56.6, [.9, 1.7, 3.0], [-.6, 1.4, -3.4], 36]]);
    return CS;
  });
  shot(56.6, 62.0, (lt, t) => {
    const tb = V(-.8, 1.6, -3.35);
    classLife(t, { focus: tb }); diyorDesk(t, tb); marjonDesk(t, { at: tb, face: { smile: .4 } }); azimDesk(t, sit(t), { squint: .8, at: tb });
    place(TI, CS, [-.8, 0, -3.35], kf(t, [[56.6, Math.PI - .25], [57.4, .35], [59.0, .25]]));
    const peek = pulse(t, 57.3, 58.6, .2, .3);
    TI.pose(talking({ ...POSE.stand(t), armR: [-2.0 * pulse(t, 58.0, 59.2, .2, .3), .3, .2], foreR: [-1.3, 0, 0], head: [0, .9 * peek, 0] }, 'timur', t, .7, 'L'));
    face(TI, 'timur', t, { brow: .3 + .3 * peek, look: [.6 * peek, .1], smile: t > 60.2 ? .5 : .1, at: peek < .3 && talkK('teacher', t) > .3 ? headW(TE) : undefined, atK: .7 });
    // «Хм. Верно.» — поправляет очки
    place(TE, CS, [1.25, 0, -3.55], -.55);
    TE.pose(talking(t > 59.7 ? POSE.adjustGlasses(t) : { ...POSE.stand(t), armL: [-.5, 0, .3], foreL: [-1.9, 0, 0], armR: [-.5, 0, .3], foreR: [-1.9, 0, 0] }, 'teacher', t, .3, 'R'));
    face(TE, 'teacher', t, { seed: 6, brow: t > 59.8 ? .6 : 0, squint: .85, at: tb });
    if (t < 59.8) look([-.1, 1.42, -1.45], [-.75, 1.42, -3.35], 34);
    else close(TE, [-.25, .03, .95], 32);
    return CS;
  });
  shot(62.0, 66.0, (lt, t) => {
    // учительница снова пишет на доске
    place(TE, CS, [.7, 0, -3.9], Math.PI); TE.pose({ ...POSE.stand(t), armR: [-2.2, -.2, .3], foreR: [-.5 + .15 * Math.sin(t * 9), 0, 0], handR: [-.3, 0, 0], gripR: .8 }); TE.chalk.visible = true; face(TE, 'teacher', t, { seed: 6 });
    classLife(t); diyorDesk(t); azimDesk(t, sit(t), { squint: .8, brow: -.5, at: TI.root.visible ? headW(TI) : undefined });
    const r = walk(TI, CS, [[-.8, 0, -3.35], [-1.25, 0, -2.4], [TIS[0] - .9, 0, TIS[2] - .4], [TIS[0], 0, TIS[2]]], t, 62.1, 1.2, { endYaw: Math.PI, end: tt => sit(tt) });
    face(TI, 'timur', t, { smile: .35, look: [.4, 0] });
    // Маржон провожает его взглядом и открывает скетчбук
    const turn = E.inOutSine(P(t, 62.3, 1.2)), draw = E.inOutSine(P(t, 64.0, .6));
    marjonDesk(t, { p: sit(t, { head: [.08, .7 * turn * (1 - draw), 0], spine: [.1 + .2 * draw, 0, 0], armL: [-.8, -.1, .1], foreL: [-1.4, 0, 0], armR: [-.8, .2, .1], foreR: [-1.2 + .2 * Math.sin(t * 8) * draw, 0, 0] }), face: { smile: .45, look: [.4 * (1 - draw), -.5 * draw] } });
    MJ.sketch.visible = draw > .2;
    look([MJS[0] + .75, 1.62, MJS[2] + 1.45], [lerp(-.4, MJS[0] - .2, draw * .6), lerp(1.4, 1.0, draw), lerp(-1.3, MJS[2] - .3, draw * .7)], 34);
    fadeOut(lt, 4, .4);
    return CS;
  });

  /* ================================================================
     СЦЕНА 3. Столовая (66 – 108)
     ================================================================ */
  const NS = CN.scene;
  const TRAY = [-2.75, .8, .4];
  const canteenLife = (t, o = {}) => {
    CN.drawTV(t);
    // столы с едящими/болтающими
    const P0 = [[0, [-3.2 - 1.35, 0, -2.2 - .85], 0, 'eat'], [1, [-3.2 - .45, 0, -2.2 - .85], 0, 'sitTalk'], [2, [-3.2 + .45, 0, -2.2 + .85], Math.PI, 'eat'],
      [3, [2.8 - .45, 0, -2.2 - .85], 0, 'eat'], [4, [2.8 + .45, 0, -2.2 - .85], 0, 'sit'], [5, [2.8 + 1.35, 0, -2.2 + .85], Math.PI, 'eat'],
      [6, [2.8 - 1.35, 0, .8 - .85], 0, 'eat'], [7, [2.8 - .45, 0, .8 + .85], Math.PI, 'sit'], [10, [-3.2 + 1.35, 0, 3.8 - .85], 0, 'eat'], [11, [-3.2 + .45, 0, 3.8 + .85], Math.PI, 'sit'],
      [12, [-3.2 - .45, 0, 3.8 - .85], 0, 'eat'], [13, [2.8 + 1.35, 0, .8 + .85], Math.PI, 'eat']];
    // соседи по столу смотрят друг на друга, иногда — на телевизор с новостями
    const TVH = V(CN.tvPos.x, 2.5, CN.tvPos.z);
    for (const [i, p, y, m] of P0) {
      const tz = [-2.2, .8, 3.8].reduce((a, b) => Math.abs(b - p[2]) < Math.abs(a - p[2]) ? b : a), mate = V(p[0] + (i % 2 ? .45 : -.45), 1.15, tz + (p[2] > tz ? -.85 : .85));
      const tv = Math.sin(t * .23 + i * 1.9) > .82;
      extra(i, NS, p, y, t, m === 'sitTalk' ? LIFE.sitTalk : m, { at: o.at || (tv ? TVH : mate), atK: m === 'eat' && !tv ? .35 : .8, who: o.wow ? 'crowd' : undefined });
    }
    [21, 22, 23].forEach((i, k) => extra(i, NS, [2.8 - 1.35 + k * .9, 0, .8 + .85], Math.PI, t, k === 1 ? 'eat' : 'sitTalk', { at: V(2.8 - 1.35 + k * .9 + (k ? -.9 : .9), 1.15, 1.65) }));
    // очередь у раздачи, автомат с напитками, ребята с подносами ходят по залу
    extra(14, NS, [-1.5, 0, -4.4], Math.PI, t, 'phone', { at: false }); hold(phones[1], ST(14), 'R', [0, -.1, .04], [-.3, 0, 0]);
    extra(15, NS, [-.6, 0, -4.5], Math.PI - .3, t, 'listen', { at: V(-1.5, 1.5, -4.4) });
    extra(18, NS, [.4, 0, -4.45], Math.PI + .2, t, 'stand', { at: V(.6, 1.1, -5.4) }); extra(19, NS, [1.3, 0, -4.4], Math.PI, t, 'talk', { at: V(.4, 1.5, -4.45) });
    extra(20, NS, [6.9, 0, -4.2], Math.PI / 2, t, (tt, s) => ({ ...LIFE.stand(tt, s), armR: [-1.3, .2, .1], foreR: [-.3, 0, 0], handR: [-.4, 0, 0] }), { at: V(7.2, 1.2, -4.2) });
    const c16 = stroll(16, NS, [-.2, 0, -3.6], [.1, 0, 4.9], t, .95, 0, { pose: { armL: [-.85, -.2, .1], armR: [-.85, .2, .1], foreL: [-.9, 0, 0], foreR: [-.9, 0, 0], grip: .6 } });
    c16.root.add(trays[0]); trays[0].position.set(0, .98 * c16.d.k, .36); trays[0].visible = true;
    const c17 = stroll(17, NS, [5.6, 0, 5.2], [5.6, 0, -3.2], t, 1.05, 6, { pose: { armL: [-.85, -.2, .1], armR: [-.85, .2, .1], foreL: [-.9, 0, 0], foreR: [-.9, 0, 0], grip: .6 } });
    c17.root.add(trays[1]); trays[1].position.set(0, .98 * c17.d.k, .36); trays[1].visible = true;
    // Азим с дружками шумят за дальним столом
    if (o.azim !== false) {
      place(AZ, NS, [2.8 + .45, 0, 3.8 + .85], Math.PI); AZ.pose(LIFE.sitTalk(t, 2)); face(AZ, 'azim', t, { seed: 5, smile: .7, mouth: .2 + .2 * Math.max(0, Math.sin(t * 9)), at: V(2.8 + 1.35, 1.15, 2.95) });
      extra(8, NS, [2.8 - .45, 0, 3.8 + .85], Math.PI, t, 'laugh', { at: headW(AZ) }); extra(9, NS, [2.8 + 1.35, 0, 3.8 - .85], 0, t, 'eat', { at: headW(AZ) });
    }
  };
  const diyorTable = (t, o = {}) => {
    place(DI, NS, stoolA(1, false), 0);
    DI.pose(talking(o.p || sit(t, { armR: [-.8, .1, .1], foreR: [-1.3, 0, 0] }), 'diyor', t, o.gest ?? 1, 'L'));
    if (!o.noCup) hold(cups[0], DI, 'R', [0, -.1, .045]);
    face(DI, 'diyor', t, { seed: 4, smile: .35, at: o.at !== undefined ? o.at : t > 72.5 ? speakerAt(t, ['marjon', 'timur'], V(-2.75, 1.2, 1.65)) : undefined, atK: .85, ...o.face });
  };
  const timurTable = (t, o = {}) => {
    place(TI, NS, stoolA(2, false), 0);
    const freeze = o.freeze || 0;
    let p = o.p || blend(FIGHT.eat(t * (o.speed ?? 1.4)), { ...sit(t), armR: [-1.05, .3, .2], foreR: [-1.55, 0, 0], head: [.05, 0, 0], spine: [.15, 0, 0] }, freeze);
    TI.pose(talking(p, 'timur', t, o.gest ?? .6, 'L'));
    hold(spoon, TI, 'R', [0, -.08, .03], [-.6, 0, 0]);
    put(CN.timurTray, NS, TRAY);
    face(TI, 'timur', t, { at: o.at, atK: .7, ...o.face });
  };
  const marjonTable = (t, o = {}) => {
    place(MJ, NS, stoolA(2, true), Math.PI);
    MJ.pose(talking(o.p || sit(t, { armL: [-.9, -.1, .1], foreL: [-1.0, 0, 0], armR: [-.9, .1, .1], foreR: [-1.1, 0, 0] }), 'marjon', t, o.gest ?? 1, 'R'));
    face(MJ, 'marjon', t, { seed: 3, smile: .45, at: o.at !== undefined ? o.at : speakerAt(t, ['diyor', 'timur'], V(-3.65, 1.2, -.05)), atK: .85, ...o.face });
  };
  D.onReset(() => { if (CN.timurTray.parent !== CN.scene) CN.scene.add(CN.timurTray); CN.timurTray.position.set(...TRAY); CN.timurTray.rotation.set(0, 0, 0); });
  shot(66, 70.98, (lt, t) => {
    canteenLife(t);
    diyorTable(t, { at: TI.root.visible ? V(-2.75, 1.3, -.4) : undefined });
    // Тимур идёт от раздачи с подносом (три порции плова) и садится
    const r = walk(TI, NS, [[-.4, 0, -4.2], [-.6, 0, -1.1], [-2.75, 0, -.75]], t, 66.0, 1.35, { endYaw: 0, end: tt => seq(tt - 68.6, [[0, POSE.stand(tt)], [0, sit(tt), .45]]) });
    const sitK = E.inOutSine(P(t, 68.6, .45));
    TI.root.position.z = lerp(TI.root.position.z, stoolA(2, false)[2], sitK);
    if (t < 68.4) {
      TI.pose({ ...TI.J && POSE.walk(gait(r.d, .7, .9)), ...(r.done ? POSE.stand(t) : {}), armL: [-.85, -.2, .1], armR: [-.85, .2, .1], foreL: [-.9, 0, 0], foreR: [-.9, 0, 0], grip: .6 });
      TI.root.add(CN.timurTray); CN.timurTray.position.set(0, .98, .36); CN.timurTray.rotation.set(0, 0, 0);
    } else { put(CN.timurTray, NS, TRAY); if (t > 68.95) { TI.pose(talking(FIGHT.eat(t * 1.6), 'timur', t, .5)); hold(spoon, TI, 'R', [0, -.08, .03], [-.6, 0, 0]); } }
    face(TI, 'timur', t, { smile: .4 });
    if (t < 68.9) move(t, [[66, [1.6, 2.5, 3.8], [-.6, 1.0, -2.6], 44], [68.9, [-.7, 1.75, 2.6], [-2.9, 1.0, -.2], 40]]);
    else look([-2.95, 1.32, 1.95], [-3.2, 1.08, -.05], 36);
    fadeIn(lt, .4);
    return NS;
  });
  shot(70.98, 76.07, (lt, t) => {
    canteenLife(t);
    // Маржон подходит, стукается кулачками с Диёром (не глядя), садится напротив; Тимур застыл с ложкой
    const r = walk(MJ, NS, [[1.2, 0, 2.6], [-1.2, 0, 2.0], [-2.75, 0, 2.05]], t, 70.2, 1.3, { endYaw: Math.PI });
    const bump = pulse(t, 71.7, 72.6, .2, .25), sitK = E.inOutSine(P(t, 72.9, .5));
    MJ.root.position.z = lerp(MJ.root.position.z, stoolA(2, true)[2], sitK);
    let mp = r.done ? blend(POSE.stand(t), sit(t), sitK) : MJ.J && POSE.walk(gait(r.d, .68, .9));
    if (bump > 0) mp = { ...mp, armL: [-1.25 * bump, -.2, .15], foreL: [-.4, 0, 0], gripL: 1 };
    MJ.pose(talking(mp, 'marjon', t, sitK, 'R')); face(MJ, 'marjon', t, { seed: 3, smile: .6, at: t < 72.8 ? V(-3.65, 1.2, -.05) : V(-3.2, 1.2, -.05), atK: .8 });
    diyorTable(t, { at: headW(MJ), p: bump > 0 ? sit(t, { armL: [-1.3 * bump, .3, .1], foreL: [-.3, 0, 0], gripL: 1, armR: [-.8, .1, .1], foreR: [-1.3, 0, 0] }) : undefined, face: { smile: .6 } });
    const fr = E.outCubic(P(t, 71.2, .25));
    timurTable(t, { freeze: fr, at: fr > .3 ? headW(MJ) : undefined, face: { wide: fr > .5 && t < 74, smile: .1, brow: .5 * fr } });
    if (t < 73.0) look([-.15, 1.48, .95], [-3.3, 1.1, .75], 42);
    else close(TI, [.2, .02, .95], 30);
    return NS;
  });
  // спор об имени: Диёр ↔ Маржон, Тимур ест и молчит
  shot(76.07, 92.04, (lt, t) => {
    canteenLife(t);
    const book = E.inOutSine(P(t, 78.4, .5)) * (1 - E.inOutSine(P(t, 85.6, .5)));
    marjonTable(t, { p: blend(sit(t, { armL: [-.9, -.1, .1], foreL: [-1.0, 0, 0], armR: [-.9, .1, .1], foreR: [-1.1, 0, 0] }), sit(t, { armL: [-1.3, .2, .2], foreL: [-1.2, 0, 0], handL: [0, 0, .5], armR: [-.9, .1, .1], foreR: [-1.1, 0, 0] }), book),
      face: { look: t > 86 && t < 89.6 ? [.0, 0] : [-.35, 0], smile: t > 86 && t < 89.6 ? .3 : .5, brow: t > 86 && t < 89.6 ? -.2 : .2 } });
    MJ.sketch.visible = book > .3;
    const brand = pulse(t, 82.4, 85.4, .3, .4), sad = pulse(t, 89.6, 92.2, .5, .4);
    diyorTable(t, { p: brand > 0 ? sit(t, { armL: [-1.4, .5, .5], foreL: [-.6, 0, 0], armR: [-1.4, -.5, .5], foreR: [-.6, 0, 0], handL: [0, 0, .6], handR: [0, 0, -.6], gripL: .1, gripR: .1 }) : sit(t, { armR: [-.8, .1, .1], foreR: [-1.3, 0, 0], head: [.25 * sad, 0, 0] }),
      noCup: brand > 0, gest: 1 - brand, face: { smile: .6 - .55 * sad, look: [.5 * (1 - sad), -.4 * sad], brow: .3 - .5 * sad } });
    timurTable(t, { speed: 1.2, at: talkK('marjon', t) > .3 ? headW(MJ) : talkK('diyor', t) > .3 ? headW(DI) : undefined, face: { smile: .2 } });
    if (brand > 0) comic('ПАУК-НОВОГРАД™', 960, 250, t - 82.6, { size: .5, rot: -.05, dur: 2.6, color: '#e8343c', burstColor: '#7ff8ff' });
    // монтаж по говорящему
    const sp = ['g5', 'm2', 'g6', 'm3', 'g7'].map(id => C.lines.find(l => l.id === id));
    const cur = sp.filter(l => t >= l.t - .1).pop();
    if (!cur || cur.who === 'diyor') ots(MJ, DI, 1, 32, .9);
    else ots(DI, MJ, 1, 32, .9);
    return NS;
  });
  shot(92.04, 102.2, (lt, t) => {
    canteenLife(t);
    diyorTable(t, { at: t < 99.9 ? V(-2.75, 1.25, -.05) : undefined, face: { smile: t > 99.8 ? .8 : .4 } });
    marjonTable(t, { at: V(-2.75, 1.25, -.05), p: sit(t, { armL: [-1.05, -.3, .1], foreL: [-1.9, 0, 0], handL: [0, 0, .3], spine: [.15, 0, 0], head: [.05, 0, .1 * pulse(t, 98.3, 100, .3, .4)] }), gest: .4,
      face: { smile: t > 98.2 ? .85 : .45, brow: .3 } });
    // «А ты как думаешь, Тимур?» — пауза — «он просто держит обещания»
    const stop = E.inOutSine(P(t, 92.6, .4));
    timurTable(t, { freeze: stop, gest: .3, at: t > 95.5 ? headW(MJ) : undefined, face: { look: [0, t < 95.5 ? -.3 : .05], smile: t > 98.3 ? .6 : .15, brow: .2 } });
    if (t < 94.6) ots(TI, MJ, 1, 32);
    else if (t < 98.4) { const k = E.inOutSine(P(t, 94.6, 3.8)); close(TI, [.18, .02, lerp(1.15, .78, k)], lerp(32, 28, k)); }
    else if (t < 99.95) close(MJ, [-.2, .02, .85], 28);
    else look([-1.7, 1.85, 3.4], [-3.2, 1.0, .6], 38);
    return NS;
  });
  shot(102.2, 108.0, (lt, t) => {
    canteenLife(t);
    marjonTable(t, { gest: .3, face: { look: [-.2, 0], smile: .7 } });
    diyorTable(t, { face: { smile: .7, look: [.3, 0] } });
    timurTable(t, { face: { smile: .55 } });
    // через зал: телевизор с новостями о герое на переднем плане
    const k = E.inOutSine(P(lt, 0, 5.8));
    look([lerp(6.4, 5.6, k), lerp(2.3, 2.1, k), lerp(4.6, 3.9, k)], [lerp(-1.2, -2.6, k), 1.4, lerp(.6, .8, k)], 40);
    fadeOut(lt, 5.8, .5);
    return NS;
  });

  /* ================================================================
     СЦЕНА 4. Коридор: Азим «Флэш» (108 – 152)
     ================================================================ */
  const RS = CR.scene;
  const X0 = -1.25;                                 // шкафчик Диёра
  const TIF = [X0, 0, -1.5], AZF = [X0 + .08, 0, -.42];       // позиции в драке: Тимур спиной к шкафчикам, Азим напротив
  const FIGHTP = V(X0, 1.45, -.95);
  /** коридор: пары болтают и смотрят друг на друга, кто-то ходит, пьёт из фонтанчика, роется в шкафчике;
   *  с t ≥ 118 (конфликт) все оборачиваются на драку, o.wow — «ого!», o.film — снимают на телефоны */
  const corridorLife = (t, o = {}) => {
    const wow = o.wow || 0, film = o.film || 0, tense = t > 118.2;
    const L = [[0, [-6.5, 0, -1.35], .2, 'talk', 1], [1, [-5.8, 0, -1.2], -2.6, 'listen', 0], [2, [5.2, 0, -1.3], -.4, 'lean'], [3, [9.0, 0, -1.25], .3, 'phone'],
      [4, [-9.5, 0, 1.3], 2.0, 'talk', 5], [5, [-8.7, 0, 1.6], -1.4, 'listen', 4], [6, [10.5, 0, 1.4], -2.2, 'talk', 7], [7, [11.2, 0, .9], 1.1, 'laugh', 6],
      [10, [3.6, 0, 1.2], -1.9, 'stand'], [11, [-7.6, 0, 1.6], 2.5, 'phone'], [12, [7.4, 0, -1.3], .1, 'lean'], [13, [-7.4, 0, -1.3], .5, 'stand'],
      [19, [-12.4, 0, .9], 1.6, 'talk', 20], [20, [-11.5, 0, 1.2], -1.9, 'listen', 19], [21, [18.4, 0, -1.4], 2.8, 'stand'], [22, [17.6, 0, -1.2], -2.6, 'talk', 21]];
    const mateAt = id => { const r = L.find(q => q[0] === id); return V(r[1][0], 1.55, r[1][2]); };
    L.forEach(([i, p, y, m, mate], j) => {
      const yy = wow > 0 || tense ? lerp(y, yawTo(p, [X0, 0, -.9]), clamp((tense ? .55 : 0) + wow)) : y;
      const mm = film > 0 && j % 3 !== 2 ? 'film' : wow > 0 ? (j % 4 === 1 ? 'cheer' : j % 2 ? 'wow' : 'stand') : tense && m === 'talk' ? 'listen' : m;
      const at = tense || wow > 0 ? FIGHTP : mate != null ? mateAt(mate) : false;
      extra(i, RS, p, yy, t, mm, { wide: wow > .5 && j % 2 === 0, smile: wow > 0 ? .15 : .3, at, atK: .85 });
      if (mm === 'film' || mm === 'phone') hold(phones[1 + (j % 8)], ST(i), 'R', [0, -.1, .045], [-.3, 0, 0]);
    });
    // ходят по коридору; когда начинается конфликт — останавливаются и смотрят
    for (const [i, a, b, sp, ph] of [[14, [-15, 0, .6], [14, 0, .9], 1.15, 0], [15, [13, 0, .4], [-14, 0, .2], 1.0, 7], [16, [-3, 0, 2.0], [15, 0, 2.0], .9, 3], [17, [16, 0, -.6], [2, 0, -.4], 1.1, 11]]) {
      const c = stroll(i, RS, a, b, Math.min(t, 118.2), sp, ph);
      if (tense) { c.root.rotation.y = lerp(c.root.rotation.y, yawTo(c.root.position.toArray(), [X0, 0, -.9]), clamp((t - 118.2) * 1.5)); c.pose(wow > 0 ? LIFE.wow(t, i) : film > 0 && i % 2 ? LIFE.film(t, i) : LIFE.listen(t, i));
        face(c, 's', t, { seed: i % 5, at: FIGHTP, wide: wow > .5 }); if (film > 0 && i % 2) hold(phones[i % 8 + 1], c, 'R', [0, -.1, .045], [-.3, 0, 0]); }
    }
    // роется в шкафчике; пьёт из фонтанчика
    extra(18, RS, [8.6, 0, -1.45], tense ? -2.4 : Math.PI, t, tense ? 'listen' : (tt, s) => ({ ...LIFE.stand(tt, s), armR: [-1.4, .1, .1], foreR: [-.6 + .2 * Math.sin(tt * 3), 0, 0], armL: [-.6, 0, .2], foreL: [-1.2, 0, 0], head: [.2, 0, 0] }), { at: tense ? FIGHTP : false });
    extra(23, RS, [12.6, 0, -1.25], tense ? -2.2 : Math.PI, t, tense ? 'listen' : (tt, s) => ({ ...POSE.stand(tt), spine: [.75, 0, 0], head: [-.3, 0, 0], armR: [-.9, 0, .2], foreR: [-.6, 0, 0] }), { at: tense ? FIGHTP : false });
    CR.doorD.rotation.y = -1.7; CR.doorM.rotation.y = -1.5;
  };
  // дружки Азима
  const cronies = (t, o = {}) => {
    place(ST(8), RS, o.p8 || [X0 + 1.7, 0, .35], o.y8 ?? -2.0); ST(8).pose(o.pose8 || { ...POSE.stand(t + 1), armL: [-.2, 0, .3], armR: [-.2, 0, .3], foreL: [-1.6, 0, 0], foreR: [-1.6, 0, 0] });
    face(ST(8), 's', t, { seed: 1, smile: o.smile ?? .6, wide: o.wide });
    place(ST(9), RS, o.p9 || [X0 + 2.3, 0, -.75], o.y9 ?? -1.6); ST(9).pose(o.pose9 || LIFE.lean(t, 2)); face(ST(9), 's', t, { seed: 4, smile: o.smile ?? .5, wide: o.wide });
  };
  const marjonLocker = (t, o = {}) => {
    place(MJ, RS, o.p || [6.2, 0, -1.4], o.yaw ?? Math.PI); MJ.pose(o.pose || { ...POSE.stand(t), armL: [-1.2, -.3, .2], foreL: [-.6 + .25 * Math.sin(t * 2), 0, 0], head: [.2, 0, 0] });
    face(MJ, 'marjon', t, { seed: 3, smile: .3, at: o.at !== undefined ? o.at : t > 117.6 ? FIGHTP : V(6.2, 1.45, -2.0), atK: .9, ...o.face });
  };
  shot(108, 113.84, (lt, t) => {
    corridorLife(t);
    marjonLocker(t, { yaw: kf(t, [[108, Math.PI], [111.0, Math.PI], [111.8, Math.PI + 1.2]]), face: { look: [.6, 0] } });
    // Диёр у шкафчика; Азим с дружками входит справа и хлопает ладонью по дверце
    const r = walk(AZ, RS, [[9.5, 0, .1], [3.0, 0, -.2], [X0 + .1, 0, -.6]], t, 103.6, 1.45, { walkPose: POSE.heavyWalk, endYaw: Math.PI });
    const slam = E.outCubic(P(t, 111.4, .18));
    if (r.done) { AZ.pose(talking({ ...POSE.stand(t), spine: [.15, 0, 0], armL: [-1.4 * slam, -.5 * slam, .35], foreL: [-.5 * slam, 0, 0], gripL: .1 }, 'azim', t, .8, 'R'));
      if (slam > 0) ikArm(AZ, 'L', V(X0 - .45, 1.78, -1.95), V(-.5, -.3, .4), slam); }
    face(AZ, 'azim', t, { seed: 5, squint: .75, smile: .5, brow: -.4, energy: .3, at: r.done ? V(X0, 1.55, -1.5) : undefined, mouth: talkK('azim', t) > 0 ? undefined : .15 + .1 * Math.sin(t * 7) }); AZ.gum.visible = true;
    walk(ST(8), RS, [[11, 0, .5], [X0 + 1.7, 0, .35]], t, 104.4, 1.5, { endYaw: -2.0 }); face(ST(8), 's', t, { seed: 1, smile: .6 });
    walk(ST(9), RS, [[10.4, 0, 1.0], [X0 + 2.3, 0, -.75]], t, 104.8, 1.6, { endYaw: -1.6, end: tt => LIFE.lean(tt, 2) }); face(ST(9), 's', t, { seed: 4, smile: .5 });
    const turn = E.inOutSine(P(t, 110.2, .5)), flinch = springAt(t, 111.5, -.06);
    place(DI, RS, [X0, 0, -1.5], lerp(Math.PI, 0, turn));
    DI.pose({ ...POSE.stand(t), armL: [-.7 * (1 - turn), 0, .15], foreL: [-1.2 * (1 - turn), 0, 0], spine: [-.1 * turn + flinch, 0, 0], head: [-.1 * turn, 0, 0] });
    face(DI, 'diyor', t, { seed: 4, smile: .2 * (1 - turn), wide: slam > .5, brow: .6 * turn, at: turn > .5 ? headW(AZ) : V(X0, 1.5, -2.2), atK: .9 });
    if (slam > 0 && t < 111.9) impact(t, 111.58, { zoom: .05, shake: .05 });
    if (t < 110.6) move(t, [[108, [9.5, 1.75, 2.15], [-2, 1.2, -1.3], 44], [110.6, [6.5, 1.65, 1.9], [-1.2, 1.25, -1.0], 40]]);
    else look([X0 + .75, .95, -1.55], [X0 + .1, 1.8, -.55], 40);
    fadeIn(lt, .4);
    return RS;
  });
  shot(113.84, 118.34, (lt, t) => {
    corridorLife(t); marjonLocker(t, { yaw: Math.PI + 1.2, face: { look: [.6, 0] } }); cronies(t);
    // «Мне всё равно. Гони.» — хватает Диёра за галстук; Тимур подходит слева
    const grab = E.outCubic(P(t, 115.9, .3));
    place(AZ, RS, [X0 + .1, 0, -.6], Math.PI);
    AZ.pose(talking({ ...POSE.stand(t), spine: [.15, 0, 0], armL: [-1.4, -.5, .35], foreL: [-.5, 0, 0], gripL: .1, armR: [-.9 * grab, -.2, .2], foreR: [-1.0, 0, 0], gripR: grab }, 'azim', t, 0));
    ikArm(AZ, 'L', V(X0 - .45, 1.78, -1.95), V(-.5, -.3, .4));
    if (grab > 0) ikArm(AZ, 'R', V(X0, 1.32, -1.32), V(.4, -.6, .4), grab);
    face(AZ, 'azim', t, { seed: 5, squint: .7, brow: -.6, smile: .2, at: V(X0, 1.55, -1.5), mouth: talkK('azim', t) > 0 ? undefined : .1 }); AZ.gum.visible = true;
    const bub = t > 114.0 && t < 115.2 ? E.outQuad(P(t, 114.0, 1.1)) : 0; AZ.gum.scale.setScalar(1 + 3.2 * bub);
    if (t > 115.2 && t < 115.6) comic('ЧПОК', 1250, 280, t - 115.2, { size: .3, dur: .4, burst: false, color: '#ff8ab8' });
    place(DI, RS, [X0, 0, -1.5], 0); DI.pose(talking({ ...POSE.stand(t), spine: [-.12 - .08 * grab, 0, 0], armL: [-.4, 0, .4], foreL: [-1.2, 0, 0], head: [-.1, 0, 0] }, 'diyor', t, .8, 'R'));
    face(DI, 'diyor', t, { seed: 4, brow: .7, wide: grab > .5, at: headW(AZ) });
    walk(TI, RS, [[-11, 0, .6], [X0 - 1.15, 0, -.55]], t, 109.3, 1.25, { endYaw: .9 });
    face(TI, 'timur', t, { brow: -.2, at: headW(AZ), atK: .6 });
    if (t < 115.81) ots(AZ, DI, 1, 34, 1.0, .12, .55);
    else look([-5.6, 1.5, 1.4], [X0 - .3, 1.3, -.9], 40);
    return RS;
  });
  shot(118.34, 120.63, (lt, t) => {
    corridorLife(t); marjonLocker(t, { yaw: Math.PI + 1.25, face: { look: [.6, 0], brow: .3 } }); cronies(t, { smile: .3 });
    // «Не давай ему, Диёр.» — Тимур снимает руку Азима с галстука и встаёт между ними
    const take = E.inOutSine(P(t, 118.6, .35)), off = E.inOutSine(P(t, 119.2, .4)), step = E.inOutSine(P(t, 119.6, .9));
    const tp = [lerp(X0 - 1.15, TIF[0], step), 0, lerp(-.55, TIF[2], step)];
    const ap = [X0 + .1, 0, lerp(-.6, AZF[2], off)];
    place(AZ, RS, ap, Math.PI);
    AZ.pose({ ...POSE.stand(t), spine: [.15 - .15 * off, 0, 0], armL: [-1.4 * (1 - off), -.5, .35], foreL: [-.5, 0, 0], armR: [-.9, -.2, .2], foreR: [-1.0, 0, 0], gripR: 1 - off });
    face(AZ, 'azim', t, { seed: 5, squint: .8, brow: -.7, at: V(X0 - .8, 1.6, -.9) }); AZ.gum.visible = true;
    place(TI, RS, tp, lerp(.9, 0, step));
    TI.pose(talking({ ...POSE.stand(t), armL: [-1.1 * take * (1 - step * .8), -.2, .1], foreL: [-.6, 0, 0], gripL: .9 * take }, 'timur', t, .5, 'R'));
    if (take > 0 && step < 1) { AZ.root.updateMatrixWorld(true); ikArm(TI, 'L', handW(AZ, 'R'), V(-.4, -.6, .3), take * (1 - step)); }
    face(TI, 'timur', t, { brow: -.3, squint: .85, at: headW(AZ), atK: .9 });
    if (take < .5) ikArm(AZ, 'R', V(X0, 1.32, -1.32), V(.4, -.6, .4), 1 - off);
    place(DI, RS, [lerp(X0, X0 + 1.05, step), 0, lerp(-1.5, -1.35, step)], lerp(0, -.9, step)); DI.pose({ ...POSE.stand(t), spine: [-.1, 0, 0] }); face(DI, 'diyor', t, { seed: 4, brow: .7, at: FIGHTP });
    if (t < 120.4) close(TI, [.15, -.18, .9], 32, [0, -.02, 0]);
    else look([-4.3, 1.45, -.95], [X0, 1.35, -.95], 38);
    return RS;
  });
  const fightBase = (t, o = {}) => {
    corridorLife(t, o); cronies(t, o.cr || {});
    place(DI, RS, [X0 + 1.05, 0, -1.35], -.9); DI.pose(talking({ ...POSE.stand(t), spine: [-.06, 0, 0], ...o.di }, 'diyor', t, .8)); face(DI, 'diyor', t, { seed: 4, brow: .7, at: FIGHTP, ...o.dif });
  };
  shot(120.63, 128.15, (lt, t) => {
    // «Ты кто такой вообще?» — тычет пальцем; «Тот, кто обычно опаздывает…»
    const mjT = E.inOutSine(P(t, 124.2, 1.3));
    fightBase(t);
    marjonLocker(t, { p: [lerp(6.2, 3.6, mjT), 0, lerp(-1.4, -.8, mjT)], yaw: Math.PI + 1.25, pose: mjT > 0 && mjT < 1 ? POSE.walk(gait(mjT * 2.7, .68, .9)) : POSE.stand(t), face: { look: [.5, 0], brow: .4 } });
    place(AZ, RS, AZF, Math.PI);
    const poke = pulse(t, 121.6, 123.4, .2, .3);
    AZ.pose(talking(blend({ ...POSE.stand(t), spine: [.12, 0, 0] }, POSE.pointFinger(t), poke), 'azim', t, .7, 'L'));
    if (poke > .3) ikArm(AZ, 'R', V(TIF[0], 1.3, TIF[2] + .22), V(.4, -.6, .3), poke);
    face(AZ, 'azim', t, { seed: 5, squint: .7, brow: -.6, smile: t < 124 ? .5 : 0, at: V(TIF[0], 1.58, TIF[2]), mouth: talkK('azim', t) > 0 ? undefined : .12 + .1 * Math.sin(t * 7) }); AZ.gum.visible = true;
    place(TI, RS, TIF, 0); TI.pose(talking({ ...POSE.stand(t), spine: [-.02, 0, 0] }, 'timur', t, .45, 'L')); face(TI, 'timur', t, { brow: -.25, squint: .9, smile: t > 125.6 ? .25 : 0, at: V(AZF[0], 1.78, AZF[2]), atK: .9 });
    if (t < 124.0) look([-4.3, 1.48, -.95], [X0, 1.38, -.95], 38);
    else if (t < 126.0) ots(AZ, TI, 1, 30, .55);
    else if (t < 127.4) close(MJ, [-.3, .02, 1.1], 32);
    else ots(AZ, TI, 1, 30, .55);
    return RS;
  });
  shot(128.15, 130.3, (lt, t) => {
    fightBase(t, { cr: { smile: .2 } });
    marjonLocker(t, { p: [3.6, 0, -.8], yaw: Math.PI + 1.25, pose: POSE.stand(t), face: { look: [.5, 0], brow: .5 } });
    // толчок двумя руками — Тимур не сдвинулся ни на сантиметр; Азим смотрит на свои ладони
    const push = pulse(t, 128.2, 128.75, .12, .2), lookH = pulse(t, 128.8, 129.5, .15, .2), wind = E.inOutSine(P(t, 129.6, .6));
    place(AZ, RS, [AZF[0], 0, AZF[2] + .05 * springAt(t, 128.35, -1)], Math.PI);
    let ap = blend({ ...POSE.stand(t), spine: [.12, 0, 0] }, { ...POSE.stand(t), spine: [.35, 0, 0], armL: [-1.45, 0, .1], armR: [-1.45, 0, .1], foreL: [-.2, 0, 0], foreR: [-.2, 0, 0], gripL: 0, gripR: 0, legL: [-.4, 0, .1], legR: [.4, 0, .1], hy: -.06 }, push);
    ap = blend(ap, { ...POSE.stand(t), armL: [-1.0, -.3, .2], armR: [-1.0, .3, .2], foreL: [-1.3, 0, 0], foreR: [-1.3, 0, 0], handL: [0, 0, -.6], handR: [0, 0, .6], gripL: 0, gripR: 0, head: [.4, 0, 0] }, lookH);
    ap = blend(ap, HEAVY.windUp, wind);
    AZ.pose(ap); face(AZ, 'azim', t, { seed: 5, brow: lookH > .3 ? .8 : -.8, wide: lookH > .3, squint: lookH > .3 ? 1 : .7, look: lookH > .3 ? [0, -.6] : [0, .1], at: lookH > .3 ? undefined : V(TIF[0], 1.58, TIF[2]) }); AZ.gum.visible = true;
    place(TI, RS, TIF, 0); TI.pose({ ...POSE.stand(t) }); face(TI, 'timur', t, { brow: -.2, squint: .9, at: V(AZF[0], 1.78, AZF[2]) });
    squash(TI, springAt(t, 128.35, -.015));
    if (lookH > .5) comic('?!', 1250, 330, t - 128.85, { size: .45, dur: .7, burst: false, color: '#ffffff' });
    if (t < 129.4) look([-4.3, 1.48, -.95], [X0, 1.35, -.95], 38);
    else close(AZ, [-.2, -.15, .9], 30, [0, -.03, 0]);
    return RS;
  });
  // слоу-мо: удар в шкафчик, нырок, толчок ладонью
  const SWING1 = 130.65, HIT1 = 131.05, SWING2 = 131.95, PALM = 132.45, WALL = 132.92;
  const azimFlight = t => {
    const k = E.outQuad(P(t, PALM, WALL - PALM));
    return [lerp(AZF[0], AZF[0] + .25, k), .35 * Math.sin(Math.PI * k) * (t < WALL ? 1 : 0), lerp(AZF[2], 2.12, k)];
  };
  const fightPoses = t => {
    // Азим
    let ap;
    if (t < SWING1) ap = HEAVY.windUp;
    else if (t < HIT1 + .1) ap = HEAVY.swing(E.inCubic(P(t, SWING1, HIT1 - SWING1)));
    else if (t < SWING2) ap = blend(HEAVY.swing(1), { ...mirror(HEAVY.windUp), armR: [-.6, .2, .4], foreR: [-1.8 + .4 * Math.sin(t * 30), 0, 0], handR: [.4 * Math.sin(t * 40), 0, 0], gripR: .4 }, E.inOutSine(P(t, HIT1 + .15, .55)));
    else if (t < PALM) ap = mirror(HEAVY.swing(E.inCubic(P(t, SWING2, PALM - .05 - SWING2))));
    else if (t < WALL + .1) ap = HEAVY.hitBack(t);
    else ap = blend(HEAVY.hitBack(t), HEAVY.slump(t), E.inOutQuad(P(t, WALL + .1, .7)));
    // Тимур: уклон вбок (кулак проходит мимо головы), нырок, толчок
    const lean = pulse(t, SWING1 + .12, HIT1 + .35, .2, .35);
    let tp = blend(FIGHT.guard(t), { ...FIGHT.guard(t), spine: [.1, 0, -.55], head: [0, 0, -.35], hy: -.08, legR: [-.1, 0, .35] }, lean);
    if (t > SWING2 - .1) tp = blend(tp, { ...FIGHT.load, spine: [.6, 0, 0] }, pulse(t, SWING2 - .1, PALM + .02, .2, .08));
    if (t > PALM - .08) tp = blend(tp, { ...POSE.stand(t), spine: [.25, 0, 0], armR: [-1.55, 0, .05], foreR: [-.05, 0, 0], handR: [-1.25, 0, 0], gripR: 0, armL: [.3, 0, .5], foreL: [-.8, 0, 0], legL: [-.7, 0, .15], legR: [.5, 0, .15], shinL: [.5, 0, 0], hy: -.12 },
      pulse(t, PALM - .08, PALM + 1.4, .08, .6));
    return { ap, tp };
  };
  shot(130.3, 133.0, (lt, t) => {
    const k = pulse(t, 130.35, 132.95, .2, .2);
    sense(t, k, 130.3);
    fightBase(t, { cr: { wide: t > HIT1, smile: 0 }, dif: { wide: true } });
    marjonLocker(t, { p: [3.6, 0, -.8], yaw: Math.PI + 1.25, pose: POSE.stand(t), face: { look: [.5, 0], wide: t > HIT1 } });
    const { ap, tp } = fightPoses(t);
    const ap0 = t < PALM ? [AZF[0], 0, AZF[2] - .12 * pulse(t, SWING1, HIT1 + .3, .3, .3)] : azimFlight(t);
    place(AZ, RS, ap0, Math.PI); AZ.pose(ap);
    face(AZ, 'azim', t, { seed: 5, brow: -1, squint: t < HIT1 ? .6 : 1, wide: t > HIT1 && t < SWING2, mouth: t > HIT1 && t < HIT1 + .6 ? .7 : undefined, energy: .8 });
    place(TI, RS, TIF, 0); TI.pose(tp); face(TI, 'timur', t, { brow: -.4, squint: .8, look: [0, .1], noBlink: true, energy: .6 });
    // вмятина в дверце и искры удара
    if (t > HIT1) { CR.dent.visible = true; CR.dent.position.set(TIF[0] + .02, 1.56, -1.985); }
    if (t > HIT1 && t < HIT1 + .5) D.sparks(V(TIF[0], 1.56, -1.9), t - HIT1, { n: 30, speed: 2.5 });
    if (t > HIT1 - .02) { comic('БДЫНЬ!', 560, 300, t - HIT1, { size: .55, rot: -.12, dur: .8 }); impact(t, HIT1, { zoom: .07, shake: .08 }); }
    if (t > PALM - .02) { comic('ТОЛЧОК!', 1360, 330, t - PALM, { size: .45, rot: .1, dur: .55, color: '#7ff8ff' }); impact(t, PALM, { zoom: .1, shake: .1, color: '#cff8ff' }); }
    if (t > SWING2 - .05 && t < PALM) D.ring(handW(AZ, 'L'), .2 + .3 * P(t, SWING2, .4), .6, 0x9ff8ff);
    // сбоку по правилу 180°: Тимур слева, Азим справа
    if (t < 131.9) look([-3.55, 1.5, -1.0], [X0, 1.42, -.98], 36);
    else move(t, [[131.9, [-3.7, 1.35, -.85], [X0, 1.15, -.9], 38], [133.0, [-4.6, 1.5, .1], [X0 + .1, 1.0, .6], 42]]);
    return RS;
  }, { flashK: 0 });
  shot(133.0, 136.42, (lt, t) => {
    fightBase(t, { cr: { wide: true, smile: 0, pose8: LIFE.wow(t, 1) }, dif: { wide: true } });
    marjonLocker(t, { p: [3.6, 0, -.8], yaw: Math.PI + 1.25, pose: LIFE.wow(t, 3), face: { look: [.3, -.1], wide: true } });
    const { ap, tp } = fightPoses(t);
    place(AZ, RS, azimFlight(t), Math.PI); AZ.pose(ap); face(AZ, 'azim', t, { seed: 5, squint: .3, look: [Math.sin(t * 5) * .5, .3], brow: .5, smile: .2 });
    place(TI, RS, TIF, 0); TI.pose(blend(tp, POSE.stand(t), E.inOutSine(P(t, 133.6, .8)))); face(TI, 'timur', t, { brow: .3, squint: 1, wide: t > 134, look: [0, -.1] });
    // табличка «мокрый пол» падает от удара
    CR.wetSign.position.set(X0 + .75, 0, 1.95); CR.wetSign.rotation.set(0, -.5, -1.45 * E.outCubic(P(t, WALL + .02, .4)));
    CR.wet.position.set(X0 + .2, .005, 1.2);
    if (t < WALL + .7) { comic('ТЫДЫЩ!', 1560, 230, t - WALL, { size: .6, rot: .1, dur: 1.1 }); }
    if (t > WALL + .6) { hold(stars, AZ, 'R', [0, 0, 0]); AZ.J.head.add(stars); stars.position.set(0, .34 * AZ.d.k, 0); stars.visible = true; starS.forEach((s, i) => { const a = t * 4 + i * Math.PI / 2; s.position.set(Math.cos(a) * .2, .02 * Math.sin(a * 2), Math.sin(a) * .2); }); }
    look([-4.6, 1.45, .2], [X0 + .1, .9, .9], 42);
    return RS;
  });
  shot(136.42, 152, (lt, t) => {
    // тишина → «Ого-о-о!», телефоны; Маржон, Диёр; «Пол мокрый»; Азим в космосе
    fightBase(t, { wow: E.inOutSine(P(t, 136.3, .6)), film: E.inOutSine(P(t, 136.9, .6)) * (t < 146 ? 1 : 0),
      di: talkK('diyor', t) > 0 ? { armL: [-.6, 0, .4], foreL: [-1.4, 0, 0], armR: [-.6, 0, .4], foreR: [-1.4, 0, 0] } : {}, dif: { wide: t < 139.3, smile: t > 139.3 ? .4 : 0 },
      cr: { wide: true, smile: 0, pose8: LIFE.wow(t, 1), p9: [X0 + .9, 0, 1.6], y9: Math.PI - .3, pose9: { ...POSE.crouch(), spine: [.5, 0, 0], armR: [-1.0, 0, .2], foreR: [-.4, 0, 0] } } });
    CR.wetSign.position.set(X0 + .75, 0, 1.95); CR.wetSign.rotation.set(0, -.5, -1.45); CR.wet.position.set(X0 + .2, .005, 1.2);
    CR.dent.visible = true; CR.dent.position.set(TIF[0] + .02, 1.56, -1.985);
    place(AZ, RS, azimFlight(200), Math.PI); AZ.pose(HEAVY.slump(t));
    face(AZ, 'azim', t, { seed: 5, squint: .35, look: [Math.sin(t * 2.5) * .6, .3], brow: .5, smile: .3, mk: 1 });
    AZ.J.head.add(stars); stars.position.set(0, .34 * AZ.d.k, 0); stars.visible = true; starS.forEach((s, i) => { const a = t * 4 + i * Math.PI / 2; s.position.set(Math.cos(a) * .2, .02 * Math.sin(a * 2), Math.sin(a) * .2); });
    // Маржон подходит ближе
    const mjK = E.inOutSine(P(t, 136.6, 1.0));
    marjonLocker(t, { p: [lerp(3.6, 1.4, mjK), 0, lerp(-.8, -.55, mjK)], yaw: Math.PI + 1.35, at: t < 143.6 ? V(X0, 1.58, -1.5) : undefined, pose: mjK > 0 && mjK < 1 ? POSE.walk(gait(mjK * 2.2, .68, .9)) : talking(POSE.stand(t), 'marjon', t, .4), face: { brow: .6, smile: t > 141 ? .45 : 0 } });
    // Тимур: «Он… поскользнулся. Пол мокрый.» — показывает на табличку; потом уходит с Диёром
    const pointK = pulse(t, 139.6, 141.6, .3, .4);
    if (t < 143.6) {
      place(TI, RS, TIF, kf(t, [[136.4, 0], [139.4, 0], [139.8, .55], [141.6, .55], [142.2, -.6]]));
      TI.pose(blend(talking(POSE.stand(t), 'timur', t, .4), POSE.pointFinger(t), pointK)); face(TI, 'timur', t, { smile: t > 139 ? .45 : .1, brow: .3, at: pointK > .3 ? V(X0 + .75, .3, 1.95) : t < 137.9 ? headW(MJ) : headW(DI), atK: .8 });
    } else {
      walk(TI, RS, [[TIF[0], 0, TIF[2]], [X0 - 2, 0, -.3], [-11, 0, .2]], t, 143.6, 1.3);
      walk(DI, RS, [[X0 + 1.05, 0, -1.35], [X0 - 1.2, 0, -.2], [-12, 0, -.1]], t, 143.9, 1.4);
      face(TI, 'timur', t, { smile: .5 }); face(DI, 'diyor', t, { seed: 4, smile: .7, look: [.4, 0] });
    }
    // монтаж
    if (t < 137.12) look([4.8, 1.65, 1.0], [X0, 1.2, -.3], 44);
    else if (t < 137.93) close(MJ, [-.2, .02, .9], 30);
    else if (t < 139.32) close(DI, [-.25, .02, .95], 30);
    else if (t < 141.88) look([X0 - 1.7, 1.45, 1.2], [X0 + .3, 1.0, .1], 42);
    else if (t < 143.6) close(AZ, [.35, -.05, 1.55], 34, [0, -.08, 0]);
    else {   // Маржон смотрит им вслед — достаёт скетчбук
      const k = E.inOutSine(P(t, 145.5, 1));
      MJ.pose({ ...POSE.stand(t), armL: [-1.1 * k, -.2, .15], foreL: [-1.2 * k, 0, 0], handL: [0, 0, .4 * k], armR: [-1.0 * k, .3, .15], foreR: [-1.4 * k + .1 * Math.sin(t * 9) * k, 0, 0], head: [.25 * k, .3 * (1 - k), 0] });
      MJ.sketch.visible = k > .3; MJ.root.rotation.y = Math.PI + 1.35 - .3 * (1 - k);
      face(MJ, 'marjon', t, { seed: 3, smile: .55, at: k > .5 ? handW(MJ, 'L') : TI.root.visible ? headW(TI) : undefined, atK: .9 });
      if (t < 148.2) look([2.7, 1.7, -1.35], [-2, 1.25, 0], 40);
      else { close(MJ, [-.35, .05, 1.0], 30, [0, -.1, 0]); MJ.sketch.lookAt(cam.position); }
    }
    fadeOut(lt, 15.58, .7);
    return RS;
  });

  /* ================================================================
     СЦЕНА 5. Двор Старого Затона, закат (152 – 205)
     ================================================================ */
  const MJE = [4.5, 0, 0];                       // подъезд Маржон
  const BENCH = [[6.4, 0, 2.42], [7.2, 0, 2.42]];
  const orangePile = (i, c) => { c.root.updateMatrixWorld(true); return c.J.chest.localToWorld(V((i % 3 - 1) * .07, -.12 + Math.floor(i / 3) * .07, .2)); };
  // апельсины: выпадают из пакета (в замедлении), Тимур ловит и собирает в охапку
  const TEAR = 160.45;
  const orangeAt = (i, t) => {
    const fallT = (t - TEAR - i * .04) * .35;                     // слоу-мо падения
    const start = V(6.75 + (i % 3 - 1) * .05, .55, 4.35 + (i % 2) * .05);
    const v = V(Math.sin(i * 2.1) * .9, .8 + (i % 3) * .3, Math.cos(i * 1.7) * .7);
    const p = start.clone().addScaledVector(v, fallT); p.y -= 4.9 * fallT * fallT;
    return p;
  };
  shot(152, 156.3, (lt, t) => {
    Z.setTime('sunset');
    // автобус «42» отъезжает, Тимур в наушниках идёт домой
    Z.bus.visible = true; Z.bus.position.set(lerp(21, -45, E.inQuad(P(t, 152.3, 4.8))), 0, 21.4); Z.bus.rotation.y = -Math.PI / 2;
    yardLife(t, { watch: headW(TI) });
    walk(TI, ZS, [[22.4, 0, 18.0], [12, 0, 17.4], [7, 0, 15.4]], t, 153.0, 1.15);
    TI.J.head.rotation.x += .07 * Math.sin(t * Math.PI * 2 * 1.05); TI.J.neck.rotation.z = .05 * Math.sin(t * Math.PI * 1.05);   // кивает в такт музыке
    hold(phonesH, TI, 'R'); TI.J.head.add(phonesH); phonesH.position.set(0, 0, 0); phonesH.rotation.set(0, 0, 0); phonesH.visible = true;
    face(TI, 'timur', t, { smile: .35, look: [0, -.1] });
    extra(12, ZS, [24.5, 0, 17.9], -1.2, t, 'phone'); hold(phones[2], ST(12), 'R', [0, -.1, .04], [-.3, 0, 0]);
    move(t, [[152, [40, 9, 31.5], [15, 2, 12], 42], [156.3, [35, 3.6, 25.5], [12, 2, 13], 40]], E.inOutSine);
    fadeIn(lt, .8);
    return ZS;
  });
  shot(156.3, 160.35, (lt, t) => {
    Z.setTime('sunset');
    const r = walk(TI, ZS, [[22.4, 0, 18.0], [12, 0, 17.4], [7, 0, 15.4], [3.6, 0, 9.5], [3.3, 0, 7.4]], t, 153.0, 1.15, { end: tt => POSE.stand(tt) });
    if (!r.done) { TI.J.head.rotation.x += .07 * Math.sin(t * Math.PI * 2 * 1.05); TI.J.neck.rotation.z = .05 * Math.sin(t * Math.PI * 1.05); }
    TI.J.head.add(phonesH); phonesH.position.set(0, 0, 0); phonesH.visible = true;
    face(TI, 'timur', t, { smile: .35, at: t > 159.2 ? V(6.9, 1.5, 4.6) : undefined, atK: .7 });
    Z.scareAt = 158.7; yardLife(t, { watch: headW(TI) });
    // Маржон с пакетом из «Продуктов» идёт к своему подъезду
    walk(MJ, ZS, [[16, 0, 12.5], [9.5, 0, 6.6], [6.9, 0, 4.6]], t, 152.2, 1.12, { endYaw: -2.0 });
    MJ.pose({ ...MJ.J && (t < 160 ? POSE.walk(gait(Math.max(0, t - 152.2) * 1.12, .68, .9)) : POSE.stand(t)), armR: [-.15, .1, .25], foreR: [-.4, 0, 0], gripR: 1 });
    hold(Z.bag, MJ, 'R', [0, -.1, 0]); face(MJ, 'marjon', t, { seed: 3, smile: .3, at: Math.sin(t * .6) > .3 ? V(-24, 1, 10) : undefined, atK: .6 });
    // дети на качелях
    const tp = TI.root.position;
    look([tp.x - 2.6, 1.55, tp.z + 3.4], [tp.x + .2, 1.25, tp.z - .5], 40);
    return ZS;
  });
  shot(160.35, 162.2, (lt, t) => {
    Z.setTime('sunset'); yardLife(t, { watch: V(6.6, 1.2, 4.7) });
    const k = pulse(t, 160.4, 162.15, .2, .25); sense(t, k, 160.35);
    // пакет рвётся, апельсины летят; Тимур в два прыжка рядом и ловит их все
    place(MJ, ZS, [6.9, 0, 4.6], -2.0);
    const oops = E.outBack(P(t, TEAR, .4));
    MJ.pose({ ...POSE.stand(t), armR: [-.3 - .4 * oops, .1, .25], foreR: [-.4 - .3 * oops, 0, 0], gripR: 1, armL: [-1.0 * oops, -.3, .4], foreL: [-1.2, 0, 0], spine: [.15 * oops, 0, 0], hy: -.04 * oops });
    face(MJ, 'marjon', t, { seed: 3, wide: t > TEAR + .1, mouth: t > TEAR + .1 ? .5 : 0, brow: .7 * oops, at: t > TEAR ? V(6.75, .3, 4.6) : undefined });
    hold(Z.bag, MJ, 'R', [0, -.1, 0], [.5 * oops, 0, .9 * oops]);
    const dash = E.outCubic(P(t, 160.7, .25));
    const tpos = [lerp(3.3, 6.25, dash), 0, lerp(7.4, 4.75, dash)];
    place(TI, ZS, tpos, lerp(2.4, 1.15, dash));
    TI.J.head.add(phonesH); phonesH.visible = true;
    const juggle = P(t, 160.95, 1.0);
    TI.pose(t < 160.7 ? POSE.stand(t) : t < 160.95 ? POSE.run(t * 1.5, 2) : blend({ ...POSE.stand(t), armL: [-1.3 + .4 * Math.sin(t * 16), -.2, .2], foreL: [-.8, 0, 0], armR: [-1.3 + .4 * Math.sin(t * 16 + 2), .2, .2], foreR: [-.8, 0, 0], hy: -.06 }, POSE.hold(), E.inOutSine(P(t, 161.75, .3))));
    face(TI, 'timur', t, { brow: .3, noBlink: true, at: Z.oranges[3].position.clone(), atK: .8 });
    for (let i = 0; i < 7; i++) {
      const o = Z.oranges[i]; o.visible = t > TEAR;
      if (!o.visible) continue;
      const caught = 160.95 + i * .1;
      let p = orangeAt(i, Math.min(t, caught));
      p.y = Math.max(p.y, .055);
      if (t > caught) { const q = orangePile(i, TI), kk = E.inOutSine(P(t, caught, .45)); p = p.clone().lerp(q, kk); p.y += Math.sin(Math.PI * kk) * .5; }
      put(o, ZS, p.toArray(), [t * 3 + i, 0, 0]);
    }
    if (t > TEAR && t < TEAR + .5) comic('ТРЕСЬ!', 1350, 300, t - TEAR, { size: .4, rot: .1, dur: .5, color: '#ffffff' });
    if (t > 161.75) comic('ХОП!', 380, 250, t - 161.75, { size: .45, rot: -.1, dur: .45 });
    Z.scareAt = 158.7;
    look([3.6, 1.3, 3.0], [6.6, .9, 4.6], 42);
    return ZS;
  });
  // жизнь двора: бабушки на лавочке у подъезда Тимура (обсуждают всех, кто проходит), дети на качелях и с мячом
  const ball = prop(mesh(new THREE.SphereGeometry(.11, 14, 10), toon(0xf2f2ee), { outline: .004 }));
  mesh(new THREE.SphereGeometry(.112, 6, 4), toon(0x1a1a1a, { wireframe: true }), { parent: ball });
  const yardLife = (t, o = {}) => {
    if (t > 158.7) Z.scareAt = 158.7;   // голуби вспорхнули, когда Тимур прошёл мимо
    const watch = o.watch;
    for (const [c, x, sd] of [[ch.granny0, -7.15, 0], [ch.granny1, -6.35, 1]]) {
      place(c, ZS, [x, 0, 2.42], 0);
      const tp = POSE.talk(t * .8 + sd * 3);
      c.pose(sit(t + sd, { armL: talkK('x', t) ? tp.armL : [-.75, .2, .1], foreL: [-1.3, 0, 0], armR: [-.75, -.2, .1], foreR: [-1.3, 0, 0], spine: [.12, (sd ? -1 : 1) * .15, 0],
        ...(Math.sin(t * .9 + sd * 2) > .2 ? { armL: tp.armL, foreL: tp.foreL, handL: tp.handL } : {}) }));
      const other = sd ? V(-7.15, 1.05, 2.42) : V(-6.35, 1.05, 2.42);
      face(c, 's', t, { seed: 2 + sd, smile: .35, at: watch && Math.sin(t * .5 + sd) > -.4 ? watch : other, atK: .85, mk: Math.sin(t * .9 + sd * 2) > .2 ? .35 : 0, energy: .2 });
    }
    // качели: дети сидят и раскачиваются вместе с сиденьем
    Z.swings.forEach((sw, i) => {
      const c = ST(20 + i); sw.updateMatrixWorld(true);
      const seatW = sw.localToWorld(V(0, -1.98, 0));
      place(c, ZS, [seatW.x, seatW.y - .33, seatW.z], 0); c.root.scale.setScalar(.72);
      c.root.rotation.x = sw.rotation.x;
      c.pose(sit(t + i, { armL: [-2.5, 0, .25], foreL: [-.3, 0, 0], armR: [-2.5, 0, .25], foreR: [-.3, 0, 0], grip: 1, shinL: [1.55 - .6 * Math.sin(t * 1.9 + i * 2), 0, 0], shinR: [1.55 - .6 * Math.sin(t * 1.9 + i * 2), 0, 0] }));
      face(c, 's', t, { seed: i, smile: .8, energy: .5 });
    });
    // мальчишки гоняют мяч у горки
    const kx = -22.8 + 1.6 * Math.sin(t * 1.1), kz = 12.2 + .8 * Math.sin(t * .7);
    const k1 = ST(22); place(k1, ZS, [kx, 0, kz], Math.cos(t * 1.1) > 0 ? 1.5 : -1.6); k1.root.scale.setScalar(.7); k1.pose(POSE.run(t * 1.3, 1.8)); face(k1, 's', t, { seed: 3, smile: .7 });
    const k2 = ST(23); place(k2, ZS, [-19.6, 0, 11.4], -1.3); k2.root.scale.setScalar(.72); k2.pose(LIFE.cheer(t, 2)); face(k2, 's', t, { seed: 4, smile: .8, at: V(kx, .6, kz) });
    put(ball, ZS, [kx + .45 * Math.cos(t * 1.1), .11 + .5 * Math.abs(Math.sin(t * 5.2)), kz + .2], [t * 6, t * 3, 0]);
  };
  // разговор у подъезда и на лавочке
  const pileOnBench = () => Z.oranges.forEach((o, i) => put(o, ZS, [7.75 + (i % 3) * .1, .53 + Math.floor(i / 3) * .08, 2.36 + ((i >> 1) % 2) * .08]));
  shot(162.2, 165.6, (lt, t) => {
    Z.setTime('sunset'); yardLife(t, { watch: V(6.6, 1.3, 4.7) });
    place(MJ, ZS, [6.9, 0, 4.6], -2.0); MJ.pose(talking({ ...POSE.stand(t), armR: [-.3, .1, .25], foreR: [-.4, 0, 0], gripR: 1 }, 'marjon', t, 1, 'L'));
    hold(Z.bag, MJ, 'R', [0, -.1, 0]);
    place(TI, ZS, [6.25, 0, 4.75], 1.15); TI.pose(POSE.hold());
    face(MJ, 'marjon', t, { seed: 3, smile: .6, brow: .3, at: headW(TI) });
    face(TI, 'timur', t, { smile: .3, brow: .2, at: Math.sin(t * 1.3) > .4 ? Z.oranges[4].position.clone() : headW(MJ), atK: .8 });
    Z.oranges.forEach((o, i) => put(o, ZS, orangePile(i, TI).toArray()));
    look([8.9, 1.55, 6.9], [6.55, 1.3, 4.65], 38);
    return ZS;
  });
  const benchSit = (t, o = {}) => {
    place(TI, ZS, BENCH[0], 0); place(MJ, ZS, BENCH[1], 0);
    const lean = o.lean ?? 0;
    const swingL = .18 * Math.sin(t * 2.4), fid = Math.max(0, Math.sin(t * .7)) ** 3;   // Маржон болтает ногами, Тимур теребит пальцы
    TI.pose(talking(o.tp || sit(t, { armL: [-.55, .1, .15], foreL: [-1.15 - .1 * fid, 0, 0], armR: [-.55, -.1, .15], foreR: [-1.15 - .1 * fid * Math.sin(t * 9), 0, 0], head: [.12, 0, 0], spine: [.15, .1, 0] }), 'timur', t, .5, 'R'));
    MJ.pose(talking(o.mp || sit(t, { spine: [.05 + .1 * lean, -.25 - .2 * lean, 0], armL: [-.6, 0, .15], foreL: [-1.2, 0, 0], armR: [-.6, 0, .15], foreR: [-1.2, 0, 0], shinL: [1.55 + swingL, 0, 0], shinR: [1.55 - swingL, 0, 0] }), 'marjon', t, .8, 'R'));
    TI.root.updateMatrixWorld(true); MJ.root.updateMatrixWorld(true);
    const hT = headW(TI), hM = headW(MJ);
    face(TI, 'timur', t, { smile: .3, at: o.tAt || hM, atK: o.tLook ?? .5, ...o.tf }); face(MJ, 'marjon', t, { seed: 3, smile: .55, at: o.mAt || hT, atK: o.mLook ?? .9, ...o.mf });
    pileOnBench();
    phonesH.visible = false;   // наушники сняты — разговор важнее музыки
  };
  const singleT = (k = 0) => close(TI, [.48, .02, lerp(1.05, .85, k)], lerp(30, 27, k), [.05, -.06, 0]);
  const singleM = (k = 0) => close(MJ, [-.48, .02, lerp(1.05, .85, k)], lerp(30, 27, k), [-.05, -.06, 0]);
  shot(165.6, 182.16, (lt, t) => {
    Z.setTime('sunset'); yardLife(t, { watch: V(6.8, 1.2, 2.4) });
    const shy = pulse(t, 172.0, 175.6, .4, .5), lean = pulse(t, 176.0, 182.5, .5, .5);
    benchSit(t, { tLook: talkK('timur', t) > 0 && shy < .3 ? .9 : .35, mLook: 1, lean,
      tp: shy > 0 ? sit(t, { armR: [-.5 - .8 * shy, .3, .3], foreR: [-1.0 - .9 * shy, 0, 0], handR: [0, 0, .4], armL: [-.5, 0, .2], foreL: [-1.0, 0, 0], head: [.3 * shy, .2, 0], spine: [.2, .1, 0] }) : undefined,
      tAt: shy > .3 ? V(6.6, .3, 3.4) : undefined, tf: { smile: t > 180.4 ? .6 : .3, brow: .2 + .3 * shy },
      mf: { smile: t > 176 ? .7 : .45, brow: .3 + .3 * lean } });
    const cur = C.lines.filter(l => l.t - .1 <= t && ['t10', 'm8', 't11', 'm9', 't12', 'm10'].includes(l.id)).pop();
    if (!cur || cur.who === 'timur') singleT(cur?.id === 't11' ? E.inOutSine(P(t, 172.15, 3.5)) : 0);
    else singleM(cur.id === 'm10' ? E.inOutSine(P(t, 180.4, 1.6)) : 0);
    if (lt < .1) fadeIn(lt, .1);
    return ZS;
  });
  shot(182.16, 194.89, (lt, t) => {
    Z.setTime('sunset'); yardLife(t, { watch: V(6.8, 1.2, 2.4) });
    // «Эм-Джей»: Тимур рисует буквы в воздухе, Маржон показывает свой комикс
    const draw = pulse(t, 187.0, 190.2, .3, .3), show = pulse(t, 189.6, 192.6, .4, .4), up = E.inOutSine(P(t, 192.6, .8));
    benchSit(t, { tLook: .9,
      tp: draw > 0 ? sit(t, { armR: [-1.7, .1, .2], foreR: [-.4, 0, 0], handR: [-.3 + .4 * Math.sin(t * 6), 0, .3 * Math.sin(t * 4)], gripR: .9, head: [.05, .5, 0], spine: [.1, .15, 0] }) : undefined,
      mp: up > 0 ? blend(sit(t), { ...POSE.stand(t), armR: [-.3, .1, .25], foreR: [-.4, 0, 0], gripR: 1 }, up) : show > 0 ? sit(t, { armL: [-1.25, .3, .2], foreL: [-1.0, 0, 0], handL: [0, 0, .7], spine: [.05, -.45, 0], head: [.1, -.6, 0], armR: [-.6, 0, .15], foreR: [-1.2, 0, 0] }) : undefined,
      tAt: draw > .3 ? handW(TI, 'R') : undefined, mAt: show > .3 ? handW(MJ, 'L') : draw > .3 ? handW(TI, 'R') : undefined,
      tf: { smile: t > 186.7 ? .55 : .3, brow: .4 }, mf: { smile: t > 191.3 ? .8 : .5, brow: t > 185 && t < 186.7 ? .7 : .3 } });
    MJ.sketch.visible = show > .3;
    if (up > 0) { MJ.root.position.y = 0; hold(Z.bag, MJ, 'R', [0, -.1, 0]); }
    if (draw > 0) { comic('M', 520, 250, t - 187.4, { size: .55, rot: -.05, dur: 2.8, burst: false, color: '#ffd23d' }); comic('J', 1400, 250, t - 188.6, { size: .55, rot: .05, dur: 1.6, burst: false, color: '#7ff8ff' }); }
    if (t < 185.14) look([6.8, 1.12, 5.9], [6.8, 1.0, 2.4], 34);
    else if (t < 186.74) singleM(.5);
    else if (t < 189.4) singleT(.3);
    else if (t < 191.34) { const h = handW(MJ, 'L'); look(h.clone().add(V(-.5, .35, .55)).toArray(), h.toArray(), 32); MJ.sketch.lookAt(cam.position); }
    else look([6.8, 1.15, 5.6], [6.8, 1.05, 2.4], 36);
    return ZS;
  });
  shot(194.89, 205, (lt, t) => {
    Z.setTime('sunset'); yardLife(t, { watch: V(6.8, 1.2, 2.4) });
    // мама из окна; Маржон уходит в подъезд; «До завтра… Эм-Джей»; ладонь прилипает к стене
    const win = E.inOutSine(P(t, 194.6, .5));
    Z.momSash.rotation.y = -1.2 * win; Z.momSil.visible = t > 194.7 && t < 198.5; Z.momRoom.material.color.setScalar(1 + .3 * win);
    const r = walk(MJ, ZS, [[7.2, 0, 2.6], [5.6, 0, 1.6], [4.6, 0, .75]], t, 197.6, 1.05, { endYaw: .35 });
    if (t < 197.6) { place(MJ, ZS, [7.2, 0, 2.6], kf(t, [[194.9, 0], [195.4, -.4], [196.8, -2.6], [197.6, -2.4]])); MJ.pose(talking({ ...POSE.lookUp(t), armR: [-.3, .1, .25], foreR: [-.4, 0, 0], gripR: 1 }, 'marjon', t, .8, 'L')); }
    else if (r.done) { const wave = pulse(t, 199.5, 201.5, .3, .3); MJ.pose(talking({ ...POSE.stand(t), armR: [-.3, .1, .25], foreR: [-.4, 0, 0], gripR: 1, armL: [-2.5 * wave, 0, .3], foreL: [-.6 + .3 * Math.sin(t * 12) * wave, 0, 0] }, 'marjon', t, 0)); }
    hold(Z.bag, MJ, 'R', [0, -.1, 0]);
    if (t > 201.9) MJ.root.visible = false;
    face(MJ, 'marjon', t, { seed: 3, smile: .7, at: t < 197.4 ? V(10.5, 5.3, 0) : t > 198.9 ? V(6.5, 1.55, 2.9) : undefined, atK: .9 });
    Z.oranges.forEach((o, i) => { if (t < 196.6) put(o, ZS, [7.75 + (i % 3) * .1, .53 + Math.floor(i / 3) * .08, 2.36 + ((i >> 1) % 2) * .08]); });
    // Тимур
    const jump = Math.max(0, Math.sin(Math.PI * P(t, 202.25, .5))), stick = pulse(t, 202.8, 203.85, .05, .02), pull = pulse(t, 203.1, 203.85, .2, .02), pop = t > 203.85;
    let tpos = [6.5, 0, 2.9], tyaw = kf(t, [[194.9, 0], [195.4, -.4], [197.6, -2.2], [201.5, -2.3], [202.1, Math.PI], [205, Math.PI]]);
    if (t > 202.1) tpos = [kf(t, [[202.1, 6.5], [202.75, 5.95]]), .45 * jump, kf(t, [[202.1, 2.9], [202.75, .62], [203.85, .62], [204.2, .95, E.outCubic]])];
    place(TI, ZS, tpos, tyaw);
    let tp = t < 197.6 ? POSE.lookUp(t) : POSE.stand(t);
    if (t > 202.1 && t < 202.8) tp = { ...POSE.stand(t), armR: [-2.7, 0, .3], foreR: [-.6, 0, 0], grip: 1, legL: [-.6 * jump, 0, .1], shinL: [1.2 * jump, 0, 0] };
    if (stick > 0) tp = { ...POSE.stand(t), armR: [-1.6, 0, .2], foreR: [-.2, 0, 0], gripR: 0, spine: [-.25 * pull, 0, 0], legL: [.2 * pull, 0, .1], legR: [-.3 * pull, 0, .1], hy: -.05 * pull };
    if (pop) tp = blend({ ...POSE.stand(t), armR: [-.9, .3, .3], foreR: [-1.4, 0, 0], handR: [.2 * Math.sin(t * 20), 0, 0], spine: [-.1, 0, 0], head: [0, .6 * Math.sin(t * 3), 0] }, POSE.walk(t - 204.4), E.inOutSine(P(t, 204.4, .4)));
    TI.pose(talking(tp, 'timur', t, .3));
    if (stick > 0) ikArm(TI, 'R', V(6.0 - .05 * pull, 2.02, .03), V(.5, -.6, .4), 1);
    face(TI, 'timur', t, { smile: t > 200.5 ? .9 : .5, wide: stick > 0 && pull > .3, brow: stick > 0 ? .8 : .3, at: t < 197.4 ? V(10.5, 5.3, 0) : t < 202 ? (MJ.root.visible ? headW(MJ) : V(4.6, 1.5, .5)) : t > 203.9 ? V(-2, 1.5, 6) : undefined, atK: .9 });
    if (pop && t < 204.4) comic('ЧПОК!', 1280, 300, t - 203.85, { size: .5, rot: .1, dur: .55 });
    // монтаж
    if (t < 197.2) look([9.6, 1.0, 8.6], [10.0, 4.6, 0], 40);
    else if (t < 200.76) look([5.3, 1.5, 4.7], [4.6, 1.35, .8], 36);
    else if (t < 202.1) close(TI, [-.35, .02, .95], 30);
    else look([8.0, 1.5, 3.1], [5.8, 1.35, .4], 40);
    fadeOut(lt, 10.11, .5);
    return ZS;
  });

  /* ================================================================
     СЦЕНА 6. Кухня, вечер (205 – 216.5) и двор в сумерках (216.5 – 221)
     ================================================================ */
  shot(205, 216.5, (lt, t) => {
    dedAt(t, { sip: pulse(t, 205.0, 205.7, .3, .3), at: V(.55, 1.2, .25), face: { smile: t > 209.5 ? .8 : .35, brow: t > 209.6 && t < 212 ? .5 : 0 } });
    // Тимур мечтательно смотрит в окно, подперев щёку
    place(TI, K, [.55, 0, .25], Math.PI);
    const dream = sit(t, { armR: [-1.1, .3, .1], foreR: [-2.1, 0, 0], handR: [0, 0, .4], spine: [.25, 0, 0], head: [-.05, -.35, .15] });
    const startle = pulse(t, 212.0, 213.2, .15, .4);
    TI.pose(talking(blend(dream, sit(t, { spine: [0, 0, 0], armL: [-.7, 0, .2], foreL: [-1.3, 0, 0] }), startle), 'timur', t, .6));
    face(TI, 'timur', t, { smile: .85 - .5 * startle, squint: .85, brow: .3 + .4 * startle, at: startle > .2 || talkK('timur', t) > .3 ? headW(DE) : V(1.4, 1.75, -2.98), atK: .8 });
    if (t < 208.5) look([-1.9, 1.5, .95], [.15, 1.0, -.6], 42);
    else if (t < 209.7) close(TI, [.3, .02, .9], 30);
    else if (t < 212.1) close(DE, [.25, .02, 1.0], 30);
    else if (t < 213.4) close(TI, [-.3, .02, .95], 30);
    else { const k = E.inOutSine(P(t, 213.4, 3.1)); look([lerp(.4, 1.45, k), lerp(1.5, 1.8, k), lerp(1.4, -.95, k)], [lerp(-.2, 1.4, k), lerp(1.1, 1.75, k), lerp(-1, -3, k)], lerp(40, 36, k)); }
    fadeIn(lt, .5);
    return K;
  });
  shot(216.5, 221, (lt, t) => {
    const k = E.inOutSine(P(lt, 0, 4.5));
    Z.setTime('sunset', 'dusk', .75 + .25 * k);
    look([lerp(-9, -10, k), lerp(3, 26, k), lerp(18, 40, k)], [lerp(-6, -5, k), lerp(6, 14, k), lerp(0, -80, k)], 44);
    fadeIn(lt, .4); fadeOut(lt, 4.5, .6);
    return ZS;
  });

  /* логотип */
  shot(221, 225.5, (lt, t) => {
    D.logo(lt, 'КОНЕЦ ВТОРОЙ СЕРИИ');
    D.title([{ text: 'мультфильм студии GraphicArts Animation', font: '600 30px Rubik', y: 1000, color: '#cfefff', stroke: 6 }], clamp((lt - 1.8) / .5));
    fadeOut(lt, 4.5, .5);
    look([0, 1.5, 3], [0, 1, 0], 45);
    return K;
  }, { noSubs: true });

  /* ================================================================
     ТИЗЕР. ODILMAN (225.5 – 241)
     ================================================================ */
  const OP = [305.2, 74.1, -384.2], OYAW = 1.66;
  const odil = (t, p, o = {}) => {
    place(OD, city.scene, OP, OYAW); OD.wind = o.wind ?? 1.0;
    OD.pose(p); face(OD, 'odilman', t, { seed: 7, energy: .9, ...o.face });
    const glowK = o.glow ?? 1;
    OD.lensList.forEach(L => L.material.color.setRGB(.95 * glowK, .96 * glowK, 1 * glowK));
  };
  const night = (t, o = {}) => {
    D.env({ key: .55, rim: 2.2, rimPos: [360, 90, -470] });
    D.rimOn([OP[0], OP[1] + 1.5, OP[2]], o.rimCol ?? 0xff3a5a, 2.6);
    C.camFill = [1.2, 0x6a7aff];
    C.bloom = o.bloom ?? .9;
  };
  shot(225.5, 229.45, (lt, t) => {
    night(t);
    odil(t, { ...POSE.stand(t), spine: [-.05, 0, 0], head: [.1, 0, 0], armL: [.05, 0, .18], armR: [.05, 0, .18], grip: 1, legL: [0, 0, .12], legR: [0, 0, .12] }, { face: { squint: .9 } });
    const k = E.inOutSine(P(lt, 0, 4));
    look([lerp(302.2, 302.9, k), lerp(74.35, 74.6, k), lerp(-381.2, -381.9, k)], [OP[0] + .4, OP[1] + lerp(2.2, 1.7, k), OP[2] - .2], lerp(44, 38, k));
    D.lensDrops(t, .6);
    fadeIn(lt, .6);
    return city.scene;
  }, { flashK: 1.4 });
  shot(229.45, 231.3, (lt, t) => {
    night(t);
    // сминает газету «ГЕРОЙ С МОСТА» и бросает вниз
    const crush = E.inCubic(P(t, 230.15, .35)), toss = E.outCubic(P(t, 230.75, .4));
    odil(t, { ...POSE.stand(t), armR: [-1.15 + .3 * toss, .3, .2 - .4 * toss], foreR: [-1.0 + .6 * toss, 0, 0], handR: [0, 0, .3], gripR: .2 + .8 * crush, head: [.4, 0, 0] });
    if (crush < .6) { hold(paper, OD, 'R', [0, -.17, .07], [-1.2, 0, 0]); paper.scale.set(1 - .5 * crush, 1 - .6 * crush, 1); }
    else if (t < 230.75) { hold(paperBall, OD, 'R', [0, -.12, .05]); paperBall.scale.setScalar(.7 + .3 * (1 - crush)); }
    else { const h = handW(OD, 'R'); const dt = t - 230.75; put(paperBall, city.scene, [h.x + dt * 1.5, h.y - 4.9 * dt * dt, h.z - dt * .4], [dt * 9, dt * 5, 0]); }
    const h = handW(OD, 'R');
    look(h.clone().add(V(-.75, .25, .55)).toArray(), h.clone().add(V(0, -.05, 0)).toArray(), 34);
    if (t > 230.15 && t < 230.7) comic('ХРУСТЬ', 1300, 320, t - 230.15, { size: .4, rot: .1, dur: .5, color: '#ffffff', burstColor: '#e8343c' });
    D.lensDrops(t, .4);
    return city.scene;
  }, { flashK: 1.4 });
  shot(231.3, 235.2, (lt, t) => {
    night(t, { bloom: 1.0 + .6 * pulse(t, 233.0, 235.5, .15, 1) });
    // наезд на маску: «Я — ODILMAN. И все заплатят!» — белые глаза вспыхивают
    const flare = pulse(t, 233.05, 235.4, .1, 1.5);
    odil(t, talking({ ...POSE.stand(t), spine: [-.05, 0, 0], head: [-.05, 0, 0], armL: [.05, 0, .18], armR: [-.2, 0, .3], foreR: [-1.2, 0, 0], grip: 1 }, 'odilman', t, .4, 'R'), { glow: 1 + 2.2 * flare, face: { squint: 1 - .25 * flare, wide: flare > .4 } });
    const k = E.inOutCubic(P(lt, 0, 3.6));
    close(OD, [lerp(-.2, -.06, k), lerp(-.1, -.03, k), lerp(2.4, .78, k)], lerp(36, 26, k), [0, -.04, 0]);
    D.lensDrops(t, .5);
    return city.scene;
  }, { flashK: 1.2 });
  shot(235.2, 241, (lt, t) => {
    night(t);
    odil(t, { ...POSE.stand(t), spine: [-.05, 0, 0], head: [.12, 0, 0], armL: [.05, 0, .18], armR: [.05, 0, .18], grip: 1, legL: [0, 0, .14], legR: [0, 0, .14] }, { glow: 1.6, face: { squint: .9 } });
    const k = E.inOutSine(P(lt, 0, 5.8));
    look([OP[0] - lerp(6, 9, k), OP[1] + lerp(1.4, 2.6, k), OP[2] + lerp(4.5, 7, k)], [OP[0] + 1, OP[1] + 1.4, OP[2] - .5], 40);
    // титр ODILMAN
    const a = clamp((lt - .4) / .25), glitch = lt < 1.1 ? (Math.sin(lt * 90) > .4 ? 14 : 0) : 0;
    D.title([{ text: 'ODILMAN', font: '900 190px Unbounded', y: 470, color: '#e8343c', stroke: 26, glow: '#ff2a3a', dx: glitch },
      { text: 'ODILMAN', font: '900 190px Unbounded', y: 470, color: 'rgba(127,248,255,.35)', dx: -glitch * 1.5 }], a);
    D.title([{ text: 'ПРОДОЛЖЕНИЕ СЛЕДУЕТ…', font: '700 46px Unbounded', y: 640, color: '#ffffff', stroke: 8 }], clamp((lt - 2.2) / .5));
    D.lensDrops(t, .3);
    fadeOut(lt, 5.8, .7);
    return city.scene;
  }, { flashK: 1.4, noSubs: true });

  return D.shots;
}
