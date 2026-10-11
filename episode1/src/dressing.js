// Наполнение локаций: голограмма и маячки в лаборатории, вертолёт и дым над мостом, кот и часы на кухне.
// Каждый объект обновляется функцией от времени — рендер остаётся детерминированным.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon, glow, mesh, rng, clamp } from './core.js';
import { makeCar } from './city.js';

export function puffTex(rgb, a = .9) {
  const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
  const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64); gr.addColorStop(0, `rgba(${rgb},${a})`); gr.addColorStop(1, `rgba(${rgb},0)`);
  g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
  return new THREE.CanvasTexture(c);
}
/* столб дыма/пара: спрайты поднимаются, расширяются и тают */
export function plume(parent, n, tex, o = {}) {
  const list = [];
  for (let i = 0; i < n; i++) {
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, opacity: 0 }));
    sp.visible = false; parent.add(sp); list.push({ sp, ph: i / n, sd: Math.sin(i * 12.9898) * 43758.5453 % 1 });
  }
  return {
    update(origin, t, k = 1) {
      for (const p of list) {
        const a = ((t * (o.speed ?? .25) + p.ph) % 1);
        p.sp.visible = k > 0;
        p.sp.position.set(origin.x + Math.sin(a * 4 + p.sd * 9) * (o.wobble ?? .4) * a + (o.wind ?? 0) * a, origin.y + a * (o.rise ?? 6), origin.z + Math.cos(a * 3 + p.sd * 7) * (o.wobble ?? .4) * a);
        p.sp.scale.setScalar((o.size ?? 1) * (.4 + a * (o.grow ?? 3)));
        p.sp.material.opacity = k * (o.alpha ?? .5) * Math.sin(Math.PI * Math.min(1, a * 1.15));
      }
    },
    hide() { list.forEach(p => p.sp.visible = false); },
  };
}

/* ---------- лаборатория ---------- */
export function dressLab(lab) {
  const L = lab.group;
  const D = {};
  // голографический проектор с вращающимся паучком
  const holo = new THREE.Group(); holo.position.set(-5, 0, 8.5); L.add(holo);
  mesh(new THREE.CylinderGeometry(1.1, 1.3, .9, 24), toon(0x2a3140), { pos: [0, .45, 0], outline: .03, parent: holo });
  mesh(new THREE.TorusGeometry(.9, .05, 6, 32), glow(0x3ff0ff, 2.2), { pos: [0, .92, 0], rot: [Math.PI / 2, 0, 0], outline: false, parent: holo });
  const beamM = new THREE.MeshBasicMaterial({ color: new THREE.Color(0x3ff0ff).multiplyScalar(.5), transparent: true, opacity: .18, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide });
  mesh(new THREE.CylinderGeometry(1.1, .8, 2.6, 24, 1, true), beamM, { pos: [0, 2.2, 0], outline: false, parent: holo });
  const hs = new THREE.Group(); hs.position.y = 2.6; holo.add(hs);
  const lineM = new THREE.LineBasicMaterial({ color: new THREE.Color(0x7ff8ff).multiplyScalar(2.2), transparent: true, opacity: .85 });
  const wire = (geo, pos, scale) => { const l = new THREE.LineSegments(new THREE.WireframeGeometry(geo), lineM); l.position.set(...pos); if (scale) l.scale.set(...scale); hs.add(l); return l; };
  wire(new THREE.SphereGeometry(.32, 10, 8), [0, 0, -.3], [1, .8, 1.25]);
  wire(new THREE.SphereGeometry(.22, 8, 6), [0, 0, .2], [1, .8, 1.1]);
  for (let i = 0; i < 8; i++) {
    const sd = i < 4 ? 1 : -1, j = i % 4;
    const pts = [new THREE.Vector3(sd * .15, 0, .25 - j * .15), new THREE.Vector3(sd * .6, .3, .3 - j * .22), new THREE.Vector3(sd * .9, -.35, .35 - j * .3)];
    hs.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), lineM));
  }
  D.holo = hs;
  // индикаторы на пультах
  D.leds = [];
  const ledC = [0x3dff8a, 0xffc21a, 0x3ff0ff, 0xff3a3a];
  for (const [x, z, ry] of [[-19, -6, Math.PI / 2], [-19, 2, Math.PI / 2], [-19, 10, Math.PI / 2], [6, -16, 0]]) {
    for (let i = 0; i < 6; i++) {
      const led = mesh(new THREE.BoxGeometry(.12, .06, .12), glow(ledC[i % 4], 2.6), { outline: false, parent: L });
      const off = new THREE.Vector3(-1.8 + i * .7, 2.02, .6).applyAxisAngle(new THREE.Vector3(0, 1, 0), ry);
      led.position.set(x + off.x, off.y, z + off.z); D.leds.push({ led, ph: i * 1.7 + x });
    }
  }
  // пар над капсулами
  const steamT = puffTex('200,240,255', .6);
  D.steam = lab.capsules.map(c => ({ c, pl: plume(L, 4, steamT, { rise: 2.2, grow: 2, size: .8, alpha: .25, speed: .35 }) }));
  // красные маячки тревоги на потолке: вращающиеся лучи
  D.beacons = [];
  for (const [x, z] of [[-14, -14], [14, -14], [-14, 8], [14, 8]]) {
    const g = new THREE.Group(); g.position.set(x, 21.6, z); L.add(g);
    mesh(new THREE.CylinderGeometry(.35, .45, .5, 12), glow(0xff2020, 3), { outline: false, parent: g });
    const beam = mesh(new THREE.ConeGeometry(2.2, 9, 16, 1, true), new THREE.MeshBasicMaterial({ color: new THREE.Color(0xff2020).multiplyScalar(.6), transparent: true, opacity: .14, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }), { pos: [4.5, -1.5, 0], rot: [0, 0, Math.PI / 2 + .5], outline: false, parent: g });
    g.visible = false; D.beacons.push(g);
  }
  D.update = (t, o = {}) => {
    hs.rotation.y = t * .8; hs.position.y = 2.6 + Math.sin(t * 1.3) * .08;
    for (const l of D.leds) l.led.visible = Math.sin(t * 3.1 + l.ph) > -.3 || o.alarm;
    for (const s of D.steam) o.inLab && s.c.glass.visible ? s.pl.update(new THREE.Vector3(s.c.x, 4.8 * s.c.s, s.c.z), t + s.c.x, 1) : s.pl.hide();
    D.beacons.forEach((b, i) => { b.visible = !!o.alarm && !!o.inLab; b.rotation.y = t * 4 + i; });
  };
  return D;
}

/* ---------- мост: обломки, дым, вертолёт ---------- */
export function dressBridge(scene) {
  const B = {};
  B.cars = [];
  for (const [x, z, ry, roll, i] of [[505, -397, 1.9, Math.PI / 2, 4], [430, -409, -.4, 0, 6]]) {
    const c = makeCar(i); c.position.set(x, roll ? 1.0 : 0, z); c.rotation.set(0, ry, roll); c.visible = false; scene.add(c); B.cars.push(c);
    c.children.forEach(ch => { if (ch.material?.blending === THREE.AdditiveBlending) ch.visible = false; });
  }
  // обломки ограждения и бетона
  const debris = [];
  const r = rng(55);
  for (let i = 0; i < 22; i++) {
    const m = mesh(new THREE.BoxGeometry(.3 + r() * .7, .15 + r() * .3, .3 + r() * .6), toon(i % 3 ? 0x4a4c55 : 0x8a3a2c), { outline: .02, parent: scene });
    m.position.set(446 + r() * 18, .1, -392 + r() * 6); m.rotation.set(r() * 2, r() * 3, r() * 2); m.visible = false; debris.push(m);
  }
  B.debris = debris;
  B.smoke = plume(scene, 14, puffTex('40,36,40', .9), { rise: 26, grow: 5, size: 3, alpha: .55, speed: .12, wind: 10, wobble: 2 });
  // вертолёт с прожектором
  const heli = new THREE.Group(); scene.add(heli); heli.visible = false;
  mesh(new RoundedBoxGeometry(3.4, 2, 6, 3, .8), toon(0x2b3445), { outline: .06, parent: heli });
  mesh(new THREE.BoxGeometry(.5, .5, 6), toon(0x2b3445), { pos: [0, .3, -5.5], outline: .05, parent: heli });
  mesh(new THREE.BoxGeometry(.15, 1.6, .9), toon(0x2b3445), { pos: [0, 1, -8.3], outline: .04, parent: heli });
  mesh(new THREE.SphereGeometry(1.2, 16, 10), toon(0x9fd0ff, { transparent: true, opacity: .55 }), { pos: [0, .1, 2.5], scale: [1, .8, 1], outline: .04, parent: heli });
  const rotor = new THREE.Group(); rotor.position.y = 1.3; heli.add(rotor);
  for (let i = 0; i < 4; i++) mesh(new THREE.BoxGeometry(.3, .05, 9), toon(0x111318), { rot: [0, i * Math.PI / 2, 0], outline: false, parent: rotor });
  mesh(new THREE.SphereGeometry(.25, 8, 6), glow(0xff2020, 4), { pos: [0, -1, -2], outline: false, parent: heli });
  const beam = mesh(new THREE.ConeGeometry(5, 60, 20, 1, true), new THREE.MeshBasicMaterial({ color: new THREE.Color(0xfff2d0).multiplyScalar(.7), transparent: true, opacity: .06, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }), { outline: false, parent: scene });
  beam.visible = false;
  const spotL = new THREE.PointLight(0xfff2d0, 0, 30, 1.2); scene.add(spotL);
  const spotDisk = mesh(new THREE.CircleGeometry(5, 32), new THREE.MeshBasicMaterial({ color: new THREE.Color(0xfff2d0).multiplyScalar(.5), transparent: true, opacity: .12, depthWrite: false, blending: THREE.AdditiveBlending }), { rot: [-Math.PI / 2, 0, 0], outline: false, parent: scene });
  spotDisk.visible = false;
  B.update = (t, on) => {
    B.cars.forEach(c => c.visible = on); debris.forEach(d => d.visible = on);
    if (!on) { B.smoke.hide(); heli.visible = beam.visible = spotDisk.visible = false; spotL.intensity = 0; return; }
    B.smoke.update(new THREE.Vector3(492, 4, -406), t, 1);
    heli.visible = true;
    heli.position.set(470 + Math.sin(t * .2) * 25, 55 + Math.sin(t * .7) * 2, -340 + Math.cos(t * .17) * 10);
    heli.rotation.set(.12, Math.PI + .5 + Math.sin(t * .3) * .3, Math.sin(t * .5) * .06);
    rotor.rotation.y = t * 40;
    // до победы прожектор шарит у автобуса, после — держит поверженного Кронова у пилона
    const k = clamp((t - 170) / 3);
    const tgt = new THREE.Vector3(452 + Math.sin(t * .6) * 6, 0, -397 + Math.cos(t * .45) * 3).lerp(new THREE.Vector3(394 + Math.sin(t * .5), 0, -390), k);
    const from = heli.position.clone().add(new THREE.Vector3(0, -1, 0));
    const dir = tgt.clone().sub(from), len = dir.length();
    beam.visible = true; beam.position.copy(from).addScaledVector(dir, .5); beam.scale.set(1, len / 60, 1);
    beam.quaternion.setFromUnitVectors(new THREE.Vector3(0, -1, 0), dir.normalize());
    spotDisk.visible = true; spotDisk.position.set(tgt.x, .12, tgt.z);
    spotL.intensity = 30; spotL.position.set(tgt.x, 8, tgt.z);
  };
  return B;
}

/* ---------- кухня: кот, часы, пар от плова ---------- */
export function dressKitchen(K) {
  const scene = K.scene, D = {};
  // кот на подоконнике
  const cat = new THREE.Group(); cat.position.set(1.85, 1.1, -2.75); cat.rotation.y = -.5; scene.add(cat);
  const fur = toon(0xe08a3a), dark = toon(0x2a1a10);
  mesh(new THREE.SphereGeometry(.16, 16, 12), fur, { pos: [0, .14, 0], scale: [1, .8, 1.5], outline: .008, parent: cat });
  const head = new THREE.Group(); head.position.set(0, .28, .2); cat.add(head);
  mesh(new THREE.SphereGeometry(.11, 16, 12), fur, { outline: .008, parent: head });
  for (const sx of [1, -1]) {
    mesh(new THREE.ConeGeometry(.04, .08, 8), fur, { pos: [sx * .06, .1, 0], rot: [0, 0, -sx * .3], outline: .005, parent: head });
    mesh(new THREE.SphereGeometry(.018, 8, 6), toon(0x9fe05a, { emissive: 0x203010 }), { pos: [sx * .04, .02, .095], scale: [1, 1.3, .5], parent: head });
  }
  mesh(new THREE.SphereGeometry(.012, 8, 6), toon(0xf08a9a), { pos: [0, -.02, .11], parent: head });
  const tail = new THREE.Group(); tail.position.set(0, .12, -.22); cat.add(tail);
  const segs = [];
  let parent = tail;
  for (let i = 0; i < 5; i++) { const s = new THREE.Group(); s.position.z = i ? -.07 : 0; parent.add(s); mesh(new THREE.CapsuleGeometry(.025, .06, 4, 8), fur, { rot: [Math.PI / 2, 0, 0], pos: [0, 0, -.035], outline: .005, parent: s }); segs.push(s); parent = s; }
  D.cat = { head, segs };
  // настенные часы
  const clock = new THREE.Group(); clock.position.set(-.6, 2.35, -2.96); scene.add(clock);
  mesh(new THREE.CylinderGeometry(.22, .22, .04, 32), toon(0xf4efe4), { rot: [Math.PI / 2, 0, 0], outline: .01, parent: clock });
  mesh(new THREE.TorusGeometry(.22, .02, 8, 32), toon(0x5a3a22), { outline: false, parent: clock });
  for (let i = 0; i < 12; i++) mesh(new THREE.BoxGeometry(.012, i % 3 ? .02 : .04, .01), toon(0x222222), { pos: [Math.sin(i * Math.PI / 6) * .18, Math.cos(i * Math.PI / 6) * .18, .025], rot: [0, 0, -i * Math.PI / 6], parent: clock });
  const hand = (len, w) => { const g = new THREE.Group(); g.position.z = .03; clock.add(g); mesh(new THREE.BoxGeometry(w, len, .008), toon(0x111111), { pos: [0, len / 2 - .01, 0], parent: g }); return g; };
  D.hourH = hand(.11, .014); D.minH = hand(.16, .01); D.secH = hand(.17, .004);
  // пар от плова
  const steamT = puffTex('255,250,240', .5);
  D.steam = K.plates.map(p => plume(scene, 5, steamT, { rise: .6, grow: 1.6, size: .18, alpha: .35, speed: .3, wobble: .05 }));
  D.update = t => {
    // часы показывают 23:47 и идут
    const sec = 47 * 60 + t; D.secH.rotation.z = -(sec % 60) / 60 * Math.PI * 2;
    D.minH.rotation.z = -((sec / 60) % 60) / 60 * Math.PI * 2; D.hourH.rotation.z = -((23 + sec / 3600) % 12) / 12 * Math.PI * 2;
    segs.forEach((s, i) => { s.rotation.y = Math.sin(t * 1.6 - i * .5) * .35; s.rotation.x = .25; });
    head.rotation.set(Math.sin(t * .5) * .1, Math.sin(t * .35) * .4, 0);
    K.plates.forEach((p, i) => { const w = p.getWorldPosition(new THREE.Vector3()); D.steam[i].update(w.add(new THREE.Vector3(0, .08, 0)), t + i, 1); });
  };
  return D;
}
