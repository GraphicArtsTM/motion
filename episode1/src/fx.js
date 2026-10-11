// Эффекты: нити паутины, искры, кольца «паучьего чутья», частицы нанонити.
import * as THREE from 'three';
import { glow, rng } from './core.js';

const UP = new THREE.Vector3(0, 1, 0);

export function makeWebs(scene, n = 24) {
  const geo = new THREE.CylinderGeometry(1, 1, 1, 6, 1); geo.translate(0, .5, 0);
  const mat = glow(0x9ff8ff, 2.6);
  const splatGeo = (() => {                       // «клякса» нити в точке крепления
    const pts = [];
    for (let i = 0; i < 8; i++) { const a = i / 8 * Math.PI * 2; pts.push(0, 0, 0, Math.cos(a), Math.sin(a), 0); }
    for (const R of [.45, .8]) for (let i = 0; i < 8; i++) { const a = i / 8 * Math.PI * 2, b = (i + 1) / 8 * Math.PI * 2; pts.push(Math.cos(a) * R, Math.sin(a) * R, 0, Math.cos(b) * R, Math.sin(b) * R, 0); }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3)); return g;
  })();
  const pool = [], splats = [];
  for (let i = 0; i < n; i++) {
    const m = new THREE.Mesh(geo, mat); m.visible = false; m.frustumCulled = false; scene.add(m); pool.push(m);
    const s = new THREE.LineSegments(splatGeo, new THREE.LineBasicMaterial({ color: new THREE.Color(0x9ff8ff).multiplyScalar(2.6) }));
    s.visible = false; s.frustumCulled = false; scene.add(s); splats.push(s);
  }
  let used = 0;
  const tmp = new THREE.Vector3();
  return {
    reset() { used = 0; pool.forEach(m => m.visible = false); splats.forEach(s => s.visible = false); },
    /* нить от a до b; k — доля вылета (0..1), w — толщина, sag — провисание */
    add(a, b, o = {}) {
      const k = o.k ?? 1, w = o.w ?? .035;
      if (k <= 0) return;
      const end = tmp.copy(a).lerp(b, k);
      const segs = o.sag ? 6 : 1;
      let prev = a.clone();
      for (let s = 1; s <= segs && used < pool.length; s++) {
        const u = s / segs;
        const p = a.clone().lerp(end, u);
        if (o.sag) p.y -= Math.sin(u * Math.PI) * o.sag;
        const m = pool[used++];
        const d = p.clone().sub(prev), len = d.length();
        m.position.copy(prev); m.quaternion.setFromUnitVectors(UP, d.normalize());
        m.scale.set(w, len, w); m.visible = true;
        prev = p;
      }
      if (k >= 1 && o.splat !== false) {
        const s = splats[Math.min(used, splats.length - 1)];
        s.position.copy(b); s.scale.setScalar(o.splatSize ?? .6); s.visible = true;
        if (o.splatNormal) s.lookAt(b.clone().add(o.splatNormal)); else s.lookAt(a);
      }
    },
  };
}

/* Искры: облако точек, вылетающих из источника; dt — время с начала */
export function makeSparks(scene, n = 400, color = 0xffd27a) {
  const g = new THREE.BufferGeometry();
  const pos = new Float32Array(n * 3); g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  const m = new THREE.Points(g, new THREE.PointsMaterial({ color: new THREE.Color(color).multiplyScalar(3), size: .12, sizeAttenuation: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  m.frustumCulled = false; m.visible = false; scene.add(m);
  const r = rng(31);
  const vel = []; for (let i = 0; i < n; i++) vel.push([(r() - .5) * 2, r() * 1.4, (r() - .5) * 2, .4 + r() * .9, r()]);
  return {
    pts: m,
    burst(origin, dt, o = {}) {
      const sp = o.speed ?? 9, life = o.life ?? 1.2, grav = o.grav ?? 9.8, size = o.size ?? .12;
      m.visible = dt >= 0 && dt < life * 1.4; if (!m.visible) return;
      m.material.size = size; m.material.opacity = Math.max(0, 1 - dt / (life * 1.4));
      for (let i = 0; i < n; i++) {
        const v = vel[i], T = Math.min(dt, life * v[3] * 1.4);
        pos[i * 3] = origin.x + v[0] * sp * T;
        pos[i * 3 + 1] = origin.y + v[1] * sp * T - grav * T * T * .5;
        pos[i * 3 + 2] = origin.z + v[2] * sp * T;
      }
      g.attributes.position.needsUpdate = true;
    },
    hide() { m.visible = false; },
  };
}

/* Кольцо-волна (паучье чутьё, удары) */
export function makeRings(scene, n = 4) {
  const list = [];
  for (let i = 0; i < n; i++) {
    const m = new THREE.Mesh(new THREE.RingGeometry(.92, 1, 64), new THREE.MeshBasicMaterial({ color: new THREE.Color(0x7ff8ff).multiplyScalar(2.5), transparent: true, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending }));
    m.visible = false; m.frustumCulled = false; scene.add(m); list.push(m);
  }
  let used = 0;
  return {
    reset() { used = 0; list.forEach(m => m.visible = false); },
    add(pos, radius, alpha, faceCam, color) {
      if (used >= list.length || alpha <= 0) return;
      const m = list[used++]; m.visible = true; m.position.copy(pos); m.scale.setScalar(radius);
      m.material.opacity = alpha; if (color) m.material.color.set(color).multiplyScalar(2.5);
      if (faceCam) m.quaternion.copy(faceCam.quaternion); else m.rotation.set(-Math.PI / 2, 0, 0);
    },
  };
}

/* Спираль нанонити вокруг героя при рождении костюма */
export function makeSilkSwirl(scene, n = 600) {
  const g = new THREE.BufferGeometry();
  const pos = new Float32Array(n * 3); g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  const m = new THREE.Points(g, new THREE.PointsMaterial({ color: new THREE.Color(0x7ff8ff).multiplyScalar(3), size: .05, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  m.frustumCulled = false; m.visible = false; scene.add(m);
  const r = rng(44); const seeds = []; for (let i = 0; i < n; i++) seeds.push([r(), r(), r()]);
  return {
    update(center, k, t) { // k: 0..1 прогресс
      m.visible = k > 0 && k < 1; if (!m.visible) return;
      for (let i = 0; i < n; i++) {
        const [a, b, c] = seeds[i];
        const R = (1.2 - k * .9) * (.4 + a * .8);
        const ang = b * 6.283 + t * (4 + c * 6);
        const y = c * 1.9 * (k * 1.3) - .1;
        pos[i * 3] = center.x + Math.cos(ang) * R; pos[i * 3 + 1] = center.y + Math.min(y, 1.9); pos[i * 3 + 2] = center.z + Math.sin(ang) * R;
      }
      g.attributes.position.needsUpdate = true;
      m.material.opacity = Math.sin(k * Math.PI);
    },
  };
}
