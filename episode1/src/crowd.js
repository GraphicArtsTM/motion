// Толпа на мосту: люди убегают от Кронова, потом останавливаются у концов моста и снимают на телефоны
// (экраны светятся, мигают вспышки), радуются спасению автобуса. Полиция въезжает на мост,
// офицеры выходят из машин с фонарями и осторожно идут к примотанному к пилону Кронову.
// Всё детерминировано: позиция и поза — функции времени.
import * as THREE from 'three';
import { toon, glow, mesh, rng, clamp, lerp, kf, E, P, V } from './core.js';

const COATS = [0x3a4a6a, 0x6a3a3a, 0x2f2f35, 0x5a5040, 0x2a4a40, 0x7a6a50, 0x8a2f4a, 0x2f5a7a, 0xc0a060, 0x4a3a6a];
const SKIN = [0xd9996b, 0xf0c3a0, 0xa86b45, 0xe8b48a];
const HAIR = [0x1a1410, 0x3a2414, 0x6a4a2a, 0x111111, 0xb08a50];

function person(scene, i, o = {}) {
  const g = new THREE.Group(); g.visible = false; scene.add(g);
  const coat = toon(o.coat ?? COATS[i % COATS.length]), skin = toon(SKIN[i % SKIN.length]), pants = toon(o.pants ?? [0x1e2028, 0x2a3040, 0x3a3a3a][i % 3]);
  const body = new THREE.Group(); body.position.y = .92; g.add(body);
  mesh(new THREE.CapsuleGeometry(.21, .5, 4, 10), coat, { pos: [0, .38, 0], scale: [1.05, 1, .75], outline: .018, parent: body });
  const head = new THREE.Group(); head.position.set(0, .86, 0); body.add(head);
  mesh(new THREE.SphereGeometry(.14, 14, 10), skin, { pos: [0, .08, 0], scale: [1, 1.08, 1], outline: .014, parent: head });
  if (o.cop) {   // фуражка
    mesh(new THREE.CylinderGeometry(.16, .14, .09, 14), toon(0x1b2440), { pos: [0, .22, 0], outline: .012, parent: head });
    mesh(new THREE.CylinderGeometry(.15, .15, .03, 14), toon(0x3b78d8), { pos: [0, .2, 0], outline: false, parent: head });
    mesh(new THREE.BoxGeometry(.2, .015, .1), toon(0x0d0f16), { pos: [0, .18, .14], rot: [.25, 0, 0], outline: false, parent: head });
  } else if (i % 4 !== 3) mesh(new THREE.SphereGeometry(.15, 12, 8, 0, Math.PI * 2, 0, 1.35), toon(HAIR[i % HAIR.length]), { pos: [0, .1, -.015], outline: false, parent: head });
  else mesh(new THREE.CylinderGeometry(.12, .15, .14, 12), toon([0xd03030, 0x30a0d0, 0xe0c030][i % 3]), { pos: [0, .2, 0], outline: .012, parent: head }); // шапка
  if (o.cop) {   // светоотражающие полосы
    for (const y of [.22, .42]) mesh(new THREE.CylinderGeometry(.225, .225, .04, 16), glow(0xc8ff3a, 1.4), { pos: [0, y, 0], scale: [1.05, 1, .78], outline: false, parent: body });
  }
  const legs = [-1, 1].map(s => { const l = new THREE.Group(); l.position.set(s * .1, 0, 0); body.add(l);
    mesh(new THREE.CapsuleGeometry(.075, .62, 4, 8), pants, { pos: [0, -.42, 0], outline: .014, parent: l });
    mesh(new THREE.BoxGeometry(.12, .07, .22), toon(0x111216), { pos: [0, -.86, .04], outline: false, parent: l }); return l; });
  const arms = [-1, 1].map(s => { const a = new THREE.Group(); a.position.set(s * .27, .64, 0); body.add(a);
    mesh(new THREE.CapsuleGeometry(.06, .26, 4, 8), coat, { pos: [0, -.17, 0], outline: .012, parent: a });
    const f = new THREE.Group(); f.position.set(0, -.36, 0); a.add(f);
    mesh(new THREE.CapsuleGeometry(.05, .22, 4, 8), coat, { pos: [0, -.14, 0], outline: .012, parent: f });
    mesh(new THREE.SphereGeometry(.05, 8, 6), skin, { pos: [0, -.3, 0], outline: false, parent: f });
    return { a, f }; });
  // телефон в правой руке: экран к лицу (локальная +y предплечья), вспышка — с обратной стороны
  const phone = new THREE.Group(); phone.position.set(0, -.36, .02); arms[1].f.add(phone);
  mesh(new THREE.BoxGeometry(.075, .012, .15), toon(0x111318), { outline: false, parent: phone });
  const screen = mesh(new THREE.BoxGeometry(.066, .004, .136), glow(0xbfe4ff, 1.6), { pos: [0, .008, 0], outline: false, parent: phone });
  const flash = new THREE.Sprite(new THREE.SpriteMaterial({ map: FLASH, color: 0xffffff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  flash.position.set(.02, -.03, .05); flash.scale.setScalar(.01); phone.add(flash);
  phone.visible = false;
  // фонарь у полицейского
  let torch = null;
  if (o.cop) {
    torch = new THREE.Group(); torch.position.set(0, -.32, .05); arms[1].f.add(torch);
    mesh(new THREE.CylinderGeometry(.03, .035, .2, 8), toon(0x15171c), { rot: [0, 0, 0], outline: false, parent: torch });
    mesh(new THREE.SphereGeometry(.032, 8, 6), glow(0xfff4d0, 4), { pos: [0, -.1, 0], outline: false, parent: torch });
    const beam = new THREE.Mesh(new THREE.ConeGeometry(1.1, 9, 16, 1, true), new THREE.MeshBasicMaterial({ color: 0xfff0c8, transparent: true, opacity: .05, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending }));
    beam.position.set(0, -4.6, 0); torch.add(beam);
  }
  g.traverse(m => { if (m.isMesh || m.isSprite) m.frustumCulled = false; });
  return { g, body, head, legs, arms, phone, screen, flash, torch };
}

const FLASH = (() => {
  const c = document.createElement('canvas'); c.width = c.height = 64; const x = c.getContext('2d');
  const gr = x.createRadialGradient(32, 32, 0, 32, 32, 32); gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(.25, 'rgba(220,235,255,.6)'); gr.addColorStop(1, 'rgba(200,220,255,0)');
  x.fillStyle = gr; x.fillRect(0, 0, 64, 64); return new THREE.CanvasTexture(c);
})();

// позы (углы в радианах; рука по оси x: минус — вперёд)
function poseRun(p, ph, amp = 1) {
  const s = Math.sin(ph);
  p.legs[0].rotation.x = s * .9 * amp; p.legs[1].rotation.x = -s * .9 * amp;
  p.arms[0].a.rotation.set(-s * .8 * amp, 0, .12); p.arms[1].a.rotation.set(s * .8 * amp, 0, -.12);
  p.arms[0].f.rotation.x = -1.3; p.arms[1].f.rotation.x = -1.3;
  p.body.rotation.x = .28 * amp; p.body.position.y = .92 + Math.abs(Math.cos(ph)) * .09 * amp;
}
function poseWalk(p, ph, amp = 1) {
  const s = Math.sin(ph);
  p.legs[0].rotation.x = s * .45 * amp; p.legs[1].rotation.x = -s * .45 * amp;
  p.arms[0].a.rotation.set(-s * .3 * amp, 0, .08); p.arms[1].a.rotation.set(s * .3 * amp, 0, -.08);
  p.arms[0].f.rotation.x = -.25; p.arms[1].f.rotation.x = -.25;
  p.body.rotation.x = .04; p.body.position.y = .92 + Math.abs(Math.cos(ph)) * .03;
}
function poseStand(p, t, seed) {
  p.legs[0].rotation.x = 0; p.legs[1].rotation.x = 0;
  p.arms[0].a.rotation.set(.05, 0, .1 + Math.sin(t * 1.3 + seed) * .03); p.arms[1].a.rotation.set(.05, 0, -.1);
  p.arms[0].f.rotation.x = -.15; p.arms[1].f.rotation.x = -.15;
  p.body.rotation.x = 0; p.body.position.y = .92 + Math.sin(t * 2 + seed) * .006;
}
function poseFilm(p, t, seed, two) {      // телефон поднят перед лицом
  poseStand(p, t, seed);
  p.arms[1].a.rotation.set(-1.5 + Math.sin(t * 1.7 + seed) * .04, .25, -.15); p.arms[1].f.rotation.x = -.75;
  if (two) { p.arms[0].a.rotation.set(-1.35, -.35, .2); p.arms[0].f.rotation.x = -.9; }
}
function poseCheer(p, t, seed, film) {
  if (film) poseFilm(p, t, seed, false); else poseStand(p, t, seed);
  const w = Math.sin(t * 9 + seed * 3);
  p.arms[0].a.rotation.set(-2.8, 0, .35 + w * .2); p.arms[0].f.rotation.x = -.2;
  p.body.position.y = .92 + Math.max(0, Math.sin(t * 7 + seed)) * .12;
}
function poseAim(p, t) {                  // полицейский: фонарь вперёд, вторая рука поддерживает
  poseStand(p, t, 0);
  p.arms[1].a.rotation.set(-1.45, .15, 0); p.arms[1].f.rotation.x = -.1;
  p.arms[0].a.rotation.set(-1.3, -.45, 0); p.arms[0].f.rotation.x = -.5;
}

export function makeCrowd(scene, life) {
  const r = rng(4242);
  const C = { people: [] };
  // группы: [x0, z, dir, xStop, t0, speed] — бегущие от Кронова; dir=0 — сразу стоят у края моста
  const plan = [];
  const lanesE = [-401.6, -402.4, -400.9, -403.1, -399.9], lanesW = [-393.2, -394.6, -395.8, -392.6];
  for (let i = 0; i < 10; i++) plan.push({ x0: 458 + r() * 34, z: lanesE[i % lanesE.length] + (r() - .5) * .5, dir: 1, xs: 566 + r() * 22, t0: 117 + r() * 2.2, v: 3.8 + r() * 1.4 });
  for (let i = 0; i < 6; i++) plan.push({ x0: 431 + r() * 9, z: lanesW[i % lanesW.length] + (r() - .5) * .5, dir: -1, xs: 301 + r() * 8, t0: 122.4 + r() * 1.4, v: 3.9 + r() * 1.2 });
  for (let i = 0; i < 9; i++) plan.push({ x0: 299 + r() * 10, z: -409 + r() * 18, dir: 0 });
  for (let i = 0; i < 8; i++) plan.push({ x0: 570 + r() * 22, z: -409 + r() * 18, dir: 0 });
  plan.forEach((pl, i) => {
    const p = person(scene, i); Object.assign(p, pl);
    p.seed = r() * 6; p.two = r() < .3; p.films = r() < .75; p.fl = 1.4 + r() * 2.6; p.flPh = r() * 5; p.cheer = r() < .6;
    C.people.push(p);
  });
  // смелый зевака подходит ближе — с его телефона потом видно героя крупно
  const brave = person(scene, 99, { coat: 0xd2502a }); brave.seed = 1.3; C.brave = brave;
  C.bravePos = t => kf(t, [[168.5, [520, 0, -401.5]], [177.8, [482, 0, -401.2], E.inOutSine]]);
  // полиция: две машины въезжают на мост, офицеры выходят
  const cars = life.police;
  for (const pc of cars.slice(0, 2)) {
    pc.doors = [1, -1].map(s => { const h = new THREE.Group(); h.position.set(s * 1.035, .72, .55); pc.c.add(h);
      mesh(new THREE.BoxGeometry(.06, .66, 1.15), toon(0xf0f0f0), { pos: [0, 0, -.58], outline: .03, parent: h });
      mesh(new THREE.BoxGeometry(.065, .2, 1.0), toon(0x2050c0), { pos: [0, -.05, -.6], outline: false, parent: h });
      mesh(new THREE.BoxGeometry(.04, .32, .95), toon(0x1a2333), { pos: [0, .5, -.6], outline: false, parent: h });
      return h; });
  }
  const route = [
    { a: [316, -404, 1.2], b: [366, -396.4, 1.32], t0: 163.6, d: 2.5 },
    { a: [323, -397, 1.7], b: [372.5, -404.2, 1.86], t0: 163.95, d: 2.4 },
  ];
  C.cops = [];
  route.forEach((rt, ci) => [1, -1].forEach((s, j) => {
    const p = person(scene, 200 + ci * 2 + j, { cop: true, coat: 0x1d2a4a, pants: 0x161c30 });
    Object.assign(p, { car: ci, side: s, t0: rt.t0 + rt.d + .45 + j * .3 + ci * .2, seed: ci * 2 + j });
    C.cops.push(p);
  }));

  C.update = (t, on) => {
    for (const p of [...C.people, ...C.cops, brave]) p.g.visible = on;
    // машины полиции: стоят у въезда, потом въезжают на мост
    route.forEach((rt, i) => {
      const pc = cars[i], u = E.outQuad(P(t, rt.t0, rt.d));
      const x = lerp(rt.a[0], rt.b[0], u), z = lerp(rt.a[1], rt.b[1], u) + Math.sin(u * Math.PI) * (i ? -1.5 : 1.5);
      pc.c.position.set(x, 0, z);
      const turn = u > 0 && u < 1 ? Math.atan2(rt.b[0] - rt.a[0], rt.b[1] - rt.a[1]) : 0;
      pc.c.rotation.y = u <= 0 ? rt.a[2] : u >= 1 ? rt.b[2] : lerp(lerp(rt.a[2], turn, clamp(u * 4)), rt.b[2], clamp((u - .7) / .3));
      pc.c.rotation.z = Math.sin(clamp((u - .85) / .15) * Math.PI) * .03;   // клевок при торможении
      const open = E.outBack(P(t, rt.t0 + rt.d + .25, .5));
      pc.doors.forEach((h, k) => h.rotation.y = (k === 0 ? -1 : 1) * open * 1.05);
    });
    // офицеры
    for (const p of C.cops) {
      const pc = cars[p.car].c; pc.updateMatrixWorld(true);
      const out = P(t, p.t0, .7);
      p.g.visible = on && out > 0;
      if (!p.g.visible) continue;
      const kp = V(393.6, 0, -389.8);
      const local = V(p.side * lerp(.5, 1.75, E.outCubic(out)), 0, lerp(.2, -.45, out));
      const at = local.applyMatrix4(pc.matrixWorld); at.y = 0;
      const go = P(t, 170.6 + p.seed * .25, 9), dir = kp.clone().sub(at).setY(0);
      const dist = dir.length(); dir.normalize();
      const walk = Math.min(go * 14.5, Math.max(0, dist - 5.5 - p.seed * .6));
      const pos = at.clone().addScaledVector(dir, walk);
      p.g.position.copy(pos);
      p.g.rotation.y = lerpAng(pc.rotation.y + p.side * Math.PI / 2, Math.atan2(dir.x, dir.z), E.inOutSine(out));
      if (out < 1) { poseWalk(p, t * 6, .6); p.body.rotation.x = .5 * (1 - out); p.body.position.y = .92 - .35 * (1 - E.outCubic(out)); }
      else if (go > 0 && go < 1 && walk < Math.max(0, dist - 5.5 - p.seed * .6)) { poseWalk(p, walk * 3.6, .8); p.arms[1].a.rotation.set(-1.35, .1, 0); p.arms[1].f.rotation.x = -.1; }
      else poseAim(p, t);
      p.head.rotation.y = Math.sin(t * .9 + p.seed) * .08;
    }
    // люди
    for (const p of C.people) {
      if (!on) continue;
      let x = p.x0, running = false;
      if (p.dir) {
        const d = Math.max(0, t - p.t0) * p.v, maxD = Math.abs(p.xs - p.x0);
        x = p.x0 + p.dir * Math.min(d, maxD); running = t > p.t0 && d < maxD;
        p.arr = p.t0 + maxD / p.v;
      } else p.arr = 110;
      p.g.position.set(x, 0, p.z);
      const action = V(t < 165 ? 446 : 400, 0, -399);
      if (running) {
        p.g.rotation.y = p.dir > 0 ? Math.PI / 2 : -Math.PI / 2;
        poseRun(p, (t - p.t0) * p.v * 2.1 + p.seed, 1);
        p.head.rotation.y = Math.sin((t - p.t0) * 1.7 + p.seed) > .85 ? -p.dir * 1.2 : 0;   // оглядывается назад
        p.phone.visible = false;
      } else if (t < p.t0) {
        p.g.rotation.y = Math.atan2(action.x - x, action.z - p.z); poseStand(p, t, p.seed); p.body.rotation.x = -.1;  // застыли в испуге
        p.arms[0].a.rotation.set(-.6, 0, .3); p.arms[0].f.rotation.x = -1.6;
        p.phone.visible = false;
      } else {
        const turn = clamp((t - p.arr) / .6);
        const yaw = Math.atan2(action.x - x, action.z - p.z) + Math.sin(p.seed * 7) * .25;
        p.g.rotation.y = p.dir ? lerp(p.dir > 0 ? Math.PI / 2 : -Math.PI / 2, yaw, E.inOutSine(turn)) : yaw;
        const cheer = p.cheer && t > 174.3 + p.seed * .05 && t < 179;
        if (cheer) poseCheer(p, t, p.seed, p.films);
        else if (p.films && t > p.arr + .8) poseFilm(p, t, p.seed, p.two);
        else { poseStand(p, t, p.seed); if (turn < 1) { p.body.rotation.x = .3 * (1 - turn); p.arms[0].a.rotation.x = .4; p.arms[1].a.rotation.x = .4; } }
        p.head.rotation.y = 0;
        p.phone.visible = p.films && t > p.arr + .8;
      }
      // вспышки и мерцание экрана
      const fk = ((t + p.flPh) % p.fl) / p.fl, strike = (t > 169.05 && t < 170.5) || (t > 174.1 && t < 175.4);
      const fl = p.phone.visible && (fk < .035 || (strike && hashN(Math.floor(t * 12) + p.seed * 100) > .82));
      p.flash.scale.setScalar(fl ? .9 : .001);
    }
    // смелый зевака
    {
      const p = brave, pos = C.bravePos(t), moving = t > 168.6 && t < 177.7;
      p.g.visible = on;
      p.g.position.set(...pos);
      p.g.rotation.y = -Math.PI / 2 - .05;
      if (moving) { poseRun(p, (520 - pos[0]) * 2.2, .55); p.phone.visible = true; p.arms[1].a.rotation.set(-1.4, .25, -.15); p.arms[1].f.rotation.x = -.7; }
      else { poseFilm(p, t, 1.3, true); p.phone.visible = true; }
      p.flash.scale.setScalar(.001);
    }
  };
  C.braveCam = t => {     // точка зрения телефона смелого зеваки
    const p = C.bravePos(t);
    return [p[0] - .35, 1.72, p[2] + .05];
  };
  return C;
}
const lerpAng = (a, b, k) => { let d = (b - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2; return a + d * k; };
const hashN = n => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };
