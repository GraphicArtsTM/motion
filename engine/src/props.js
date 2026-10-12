// Городская жизнь: прохожие под зонтами, деревья, гидранты, урны, скамейки, светофоры, пар из люков,
// рекламные щиты на крышах, полицейские машины с мигалками у моста. Всё детерминировано по времени.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon, glow, mesh, rng, outlineMat } from './core.js';
import { makeCar } from './city.js';

function instanced(scene, geo, mat, list, outline = .04) {
  const im = new THREE.InstancedMesh(geo, mat, list.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
  list.forEach((v, i) => { e.set(0, v[3] || 0, 0); q.setFromEuler(e); m4.compose(new THREE.Vector3(v[0], v[1], v[2]), q, new THREE.Vector3(...(v[4] || [1, 1, 1]))); im.setMatrixAt(i, m4); });
  im.frustumCulled = false; scene.add(im);
  if (outline) { const ol = new THREE.InstancedMesh(geo, outlineMat(outline), list.length); ol.instanceMatrix = im.instanceMatrix; ol.frustumCulled = false; scene.add(ol); }
  return im;
}

function adTexture(draw, w = 1024, h = 384) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}

export function makeStreetLife(scene) {
  const r = rng(909);
  const L = { peds: [], lights: [], police: [] };
  const AV = [-14.5, 14.5];              // тротуары проспекта x = 0

  // деревья в кадках, гидранты, урны, скамейки вдоль проспекта
  const trees = [], hyd = [], bins = [], benches = [];
  for (let z = 250; z > -420; z -= 18) for (const x of AV) {
    if (Math.abs(((z % 80) + 80) % 80 - 10) < 13) continue;          // не на перекрёстке
    const k = r();
    if (k < .45) trees.push([x * 1.0 + Math.sign(x) * .5, 0, z + r() * 4]);
    else if (k < .6) hyd.push([x - Math.sign(x) * 2.6, 0, z]);
    else if (k < .8) bins.push([x - Math.sign(x) * 2.2, 0, z, r() * 3]);
    else benches.push([x + Math.sign(x) * 1.5, 0, z, x < 0 ? Math.PI / 2 : -Math.PI / 2]);
  }
  instanced(scene, new THREE.BoxGeometry(1.4, .7, 1.4).translate(0, .35, 0), toon(0x3d3a40), trees);
  instanced(scene, new THREE.CylinderGeometry(.12, .16, 3.2, 6).translate(0, 2.1, 0), toon(0x3a2a1e), trees, .03);
  instanced(scene, new THREE.IcosahedronGeometry(1.5, 1).translate(0, 4.2, 0), toon(0x1f5a3a), trees, .05);
  instanced(scene, new THREE.IcosahedronGeometry(1.0, 1).translate(.6, 5.0, .3), toon(0x2a7048), trees, .04);
  instanced(scene, new THREE.CylinderGeometry(.2, .24, .8, 10).translate(0, .4, 0), toon(0xd83030), hyd, .03);
  instanced(scene, new THREE.SphereGeometry(.21, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2).translate(0, .8, 0), toon(0xd83030), hyd, .02);
  instanced(scene, new THREE.CylinderGeometry(.32, .28, 1.0, 12).translate(0, .5, 0), toon(0x2d5a3a), bins, .03);
  instanced(scene, new THREE.CylinderGeometry(.34, .34, .08, 12).translate(0, 1.03, 0), toon(0x1f3d28), bins, .02);
  instanced(scene, new RoundedBoxGeometry(2.0, .12, .55, 2, .04).translate(0, .5, 0), toon(0x7a4a2a), benches, .03);
  instanced(scene, new RoundedBoxGeometry(2.0, .5, .1, 2, .04).translate(0, .85, -.25), toon(0x7a4a2a), benches, .03);
  instanced(scene, new THREE.BoxGeometry(.1, .5, .5).translate(.9, .25, 0), toon(0x222222), benches, false);
  instanced(scene, new THREE.BoxGeometry(.1, .5, .5).translate(-.9, .25, 0), toon(0x222222), benches, false);

  // припаркованные машины у бордюра
  for (let i = 0; i < 14; i++) {
    const c = makeCar(i + 5, i % 5 === 2); const sx = i % 2 ? 1 : -1;
    c.position.set(sx * 9.2, 0, 230 - i * 47 - r() * 8); c.rotation.y = sx > 0 ? Math.PI : 0;
    c.children.forEach(ch => { if (ch.material?.blending === THREE.AdditiveBlending) ch.visible = false; }); // фары выключены
    scene.add(c);
  }

  // светофоры на перекрёстках проспекта
  for (let q = -5; q <= 3; q++) for (const sx of [-1, 1]) {
    const g = new THREE.Group(); g.position.set(sx * 10.6, 0, q * 80 + sx * 11); scene.add(g);
    mesh(new THREE.CylinderGeometry(.1, .12, 5, 8), toon(0x22252c), { pos: [0, 2.5, 0], outline: .02, parent: g });
    mesh(new THREE.BoxGeometry(.2, .2, 4.2), toon(0x22252c), { pos: [0, 4.9, -sx * 2], outline: .02, parent: g });
    const box = new THREE.Group(); box.position.set(0, 4.3, -sx * 3.8); g.add(box);
    mesh(new RoundedBoxGeometry(.5, 1.3, .45, 2, .08), toon(0x1a1c22), { outline: .02, parent: box });
    const lamps = [0xff2a2a, 0xffc21a, 0x2aff6a].map((c, i) => mesh(new THREE.SphereGeometry(.14, 10, 8), glow(c, 2.5), { pos: [0, .38 - i * .38, sx * .22], outline: false, parent: box }));
    L.lights.push({ lamps, ph: (q + (sx > 0 ? .5 : 0)) * 3.7 });
  }

  // пар из люков
  const steamTex = adTexture((g, w, h) => { const gr = g.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2); gr.addColorStop(0, 'rgba(220,225,240,.55)'); gr.addColorStop(1, 'rgba(220,225,240,0)'); g.fillStyle = gr; g.fillRect(0, 0, w, h); }, 128, 128);
  L.steam = [];
  for (const [x, z] of [[-3, 140], [4, 60], [-5, -30], [2.5, -150], [-2, -260], [5, -350]]) {
    mesh(new THREE.CylinderGeometry(.45, .45, .03, 16), toon(0x2a2a30), { pos: [x, .02, z], outline: false, parent: scene });
    for (let i = 0; i < 5; i++) {
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: steamTex, transparent: true, depthWrite: false, opacity: .5 }));
      scene.add(sp); L.steam.push({ sp, x, z, ph: i / 5 });
    }
  }

  // прохожие под зонтами
  const coatC = [0x3a4a6a, 0x6a3a3a, 0x2f2f35, 0x5a5040, 0x2a4a40, 0x7a6a50];
  const umbC = [0xe8343c, 0x2b6fd6, 0x222222, 0xf2c230, 0x1c9a6a, 0x9b3fc4, 0xff8a1d];
  for (let i = 0; i < 34; i++) {
    const g = new THREE.Group(); scene.add(g);
    const coat = toon(coatC[i % coatC.length]), skin = toon([0xd9996b, 0xf0c3a0, 0xa86b45][i % 3]);
    mesh(new THREE.CapsuleGeometry(.22, .7, 4, 10), coat, { pos: [0, 1.2, 0], scale: [1, 1, .8], outline: .02, parent: g });
    mesh(new THREE.SphereGeometry(.15, 12, 8), skin, { pos: [0, 1.82, 0], outline: .015, parent: g });
    const legs = [-1, 1].map(s => { const lg = new THREE.Group(); lg.position.set(s * .1, .85, 0); g.add(lg); mesh(new THREE.CapsuleGeometry(.075, .6, 4, 8), toon(0x1e2028), { pos: [0, -.42, 0], outline: .015, parent: lg }); return lg; });
    const arm = new THREE.Group(); arm.position.set(.2, 1.5, .05); g.add(arm);
    mesh(new THREE.CapsuleGeometry(.06, .4, 4, 8), coat, { pos: [0, -.1, .15], rot: [-1.2, 0, 0], outline: .015, parent: arm });
    const umb = new THREE.Group(); umb.position.set(.1, 2.3, .1); g.add(umb);
    mesh(new THREE.ConeGeometry(.75, .35, 10, 1, true), toon(umbC[i % umbC.length], { side: THREE.DoubleSide }), { pos: [0, .1, 0], outline: .02, parent: umb });
    mesh(new THREE.CylinderGeometry(.015, .015, .8, 4), toon(0x111111), { pos: [0, -.3, 0], outline: false, parent: umb });
    const x = AV[i % 2] + (r() - .5) * 3, dir = r() < .5 ? 1 : -1;
    L.peds.push({ g, legs, umb, x, dir, off: r() * 680, speed: 1.1 + r() * .5, ph: r() * 6 });
  }

  // рекламные щиты на крышах вдоль проспекта
  const ads = [
    adTexture((g, w, h) => { g.fillStyle = '#071a24'; g.fillRect(0, 0, w, h); g.fillStyle = '#3ff0ff'; g.font = '900 120px Unbounded'; g.fillText('АРКАДА', 50, 170);
      g.font = '600 50px Rubik'; g.fillStyle = '#bff6ff'; g.fillText('Будущее уже здесь', 56, 270); g.strokeStyle = '#3ff0ff'; g.lineWidth = 6;
      for (let a = 0; a < 8; a++) { g.beginPath(); g.moveTo(860, 190); g.lineTo(860 + Math.cos(a * .785) * 120, 190 + Math.sin(a * .785) * 120); g.stroke(); } g.beginPath(); g.arc(860, 190, 40, 0, 7); g.fillStyle = '#3ff0ff'; g.fill(); }),
    adTexture((g, w, h) => { g.fillStyle = '#ff7b1c'; g.fillRect(0, 0, w, h); g.fillStyle = '#fff'; g.font = '900 130px Unbounded'; g.fillText('БЫСТРО', 40, 180);
      g.font = '700 54px Rubik'; g.fillText('доставка за 10 минут', 46, 285); g.fillStyle = '#15b9a8'; g.fillRect(820, 90, 160, 180); }),
    adTexture((g, w, h) => { const gr = g.createLinearGradient(0, 0, w, 0); gr.addColorStop(0, '#3b0a5a'); gr.addColorStop(1, '#c0306a'); g.fillStyle = gr; g.fillRect(0, 0, w, h);
      g.fillStyle = '#fff'; g.font = '900 110px Unbounded'; g.fillText('НОВОГРАД ТВ', 50, 200); g.font = '600 46px Rubik'; g.fillText('Новости 24/7', 56, 290); }),
    adTexture((g, w, h) => { g.fillStyle = '#10241a'; g.fillRect(0, 0, w, h); g.fillStyle = '#7dffb0'; g.font = '900 110px Unbounded'; g.fillText('ПЛОВ', 50, 190);
      g.font = '600 50px Rubik'; g.fillStyle = '#fff'; g.fillText('как у бабушки · 24 часа', 56, 290); }),
  ];
  [[-40, 120, 92, 0], [40, 40, 110, 2], [-40, -120, 80, 1], [40, -200, 98, 3], [-40, 200, 70, 1], [40, -320, 120, 0]].forEach(([x, z, y, k], i) => {
    const g = new THREE.Group(); g.position.set(x, 0, z); g.rotation.y = x < 0 ? Math.PI / 2 : -Math.PI / 2; scene.add(g);
    const p = new THREE.Mesh(new THREE.PlaneGeometry(26, 9.75), new THREE.MeshBasicMaterial({ map: ads[k], color: new THREE.Color(1.5, 1.5, 1.5) }));
    p.position.set(0, y + 9, 0); g.add(p);
    mesh(new THREE.BoxGeometry(26.6, 10.3, .5), toon(0x15171d), { pos: [0, y + 9, -.3], outline: false, parent: g });
    for (const sx of [-1, 1]) mesh(new THREE.BoxGeometry(.4, 8, .4), toon(0x15171d), { pos: [sx * 10, y + 2, -.4], outline: false, parent: g });
  });

  // полиция у въезда на мост
  for (let i = 0; i < 3; i++) {
    const c = makeCar(i, false); scene.add(c);
    c.children[0].material = toon(0xf0f0f0);
    c.position.set(316 + i * 7, 0, -404 + (i % 2) * 7); c.rotation.y = 1.2 + i * .5;
    const red = mesh(new THREE.BoxGeometry(.5, .2, .3), glow(0xff2020, 3), { pos: [-.35, 1.75, -.2], outline: false, parent: c });
    const blue = mesh(new THREE.BoxGeometry(.5, .2, .3), glow(0x2050ff, 3), { pos: [.35, 1.75, -.2], outline: false, parent: c });
    c.visible = false; L.police.push({ c, red, blue, i });
  }
  L.policeLight = new THREE.PointLight(0xff2020, 0, 40, 1.2); scene.add(L.policeLight);

  L.update = (t, o = {}) => {
    for (const p of L.peds) {
      const s = ((p.off + p.speed * t) % 680 + 680) % 680;
      p.g.position.set(p.x, 0, p.dir > 0 ? -420 + s : 260 - s); p.g.rotation.y = p.dir > 0 ? 0 : Math.PI;
      const ph = t * p.speed * 3.2 + p.ph;
      p.legs[0].rotation.x = Math.sin(ph) * .5; p.legs[1].rotation.x = -Math.sin(ph) * .5;
      p.g.position.y = Math.abs(Math.cos(ph)) * .04; p.umb.rotation.z = Math.sin(ph) * .04;
    }
    for (const l of L.lights) {
      const c = ((t + l.ph) % 12 + 12) % 12, st = c < 5 ? 2 : c < 6.5 ? 1 : 0;
      l.lamps.forEach((m, i) => m.visible = i === st);
    }
    for (const s of L.steam) {
      const k = (t * .35 + s.ph) % 1;
      s.sp.position.set(s.x + Math.sin(k * 5 + s.ph * 9) * .5, .3 + k * 4, s.z); s.sp.scale.setScalar(1 + k * 3.5); s.sp.material.opacity = .45 * Math.sin(k * Math.PI);
    }
    const pol = !!o.police;
    for (const p of L.police) {
      p.c.visible = pol; const f = Math.floor(t * 6 + p.i) % 2;
      p.red.visible = f === 0; p.blue.visible = f === 1;
    }
    L.policeLight.intensity = pol ? 40 : 0; L.policeLight.position.set(t < 165 ? 325 : 369, 4, -400);
    L.policeLight.color.set(Math.floor(t * 6) % 2 ? 0x2050ff : 0xff2020);
  };
  return L;
}
