// Общие утилиты: изинги, ключевые кадры, детерминированный рандом, тун-материалы, контуры.
import * as THREE from 'three';

export const W = 1920, H = 1080;
export const clamp = (x, a = 0, b = 1) => x < a ? a : x > b ? b : x;
export const lerp = (a, b, k) => a + (b - a) * k;
export const smooth = x => x * x * (3 - 2 * x);
export const P = (t, t0, d) => clamp((t - t0) / d);

export const E = {
  lin: x => x,
  inQuad: x => x * x,
  outQuad: x => 1 - (1 - x) * (1 - x),
  inOutQuad: x => x < .5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2,
  inCubic: x => x * x * x,
  outCubic: x => 1 - Math.pow(1 - x, 3),
  inOutCubic: x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2,
  inOutSine: x => -(Math.cos(Math.PI * x) - 1) / 2,
  outQuint: x => 1 - Math.pow(1 - x, 5),
  inExpo: x => x <= 0 ? 0 : Math.pow(2, 10 * x - 10),
  outExpo: x => x >= 1 ? 1 : 1 - Math.pow(2, -10 * x),
  inOutExpo: x => x <= 0 ? 0 : x >= 1 ? 1 : x < .5 ? Math.pow(2, 20 * x - 10) / 2 : (2 - Math.pow(2, -20 * x + 10)) / 2,
  outBack: x => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outElastic: x => x <= 0 ? 0 : x >= 1 ? 1 : Math.pow(2, -10 * x) * Math.sin((x * 10 - .75) * (2 * Math.PI) / 3) + 1,
};
export const tw = (t, t0, d, a, b, e = E.inOutCubic) => lerp(a, b, e(P(t, t0, d)));

/* Ключевые кадры для чисел или массивов: [[t, v], [t, v, ease], ...] — ease относится к отрезку, который заканчивается этим ключом */
export function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, e] = keys[i], [t0, v0] = keys[i - 1];
    if (t <= t1) {
      const k = (e || E.inOutCubic)(P(t, t0, t1 - t0));
      return Array.isArray(v0) ? v0.map((a, j) => lerp(a, v1[j], k)) : lerp(v0, v1, k);
    }
  }
  return keys[keys.length - 1][1];
}

/* Детерминированный рандом */
export function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}
export const hash = n => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };
/* Гладкий 1D-шум для тряски камеры */
export function noise(x) {
  const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
  return lerp(hash(i), hash(i + 1), u) * 2 - 1;
}
export const shake = (t, amp, freq = 9, seed = 0) => [noise(t * freq + seed) * amp, noise(t * freq + seed + 50) * amp, noise(t * freq + seed + 99) * amp * .5];

/* Окно активности: 0 → 1 → 0 с плавными краями */
export const pulse = (t, t0, t1, fadeIn = .1, fadeOut = .1) => Math.min(P(t, t0, fadeIn), 1 - P(t, t1 - fadeOut, fadeOut));

/* ---------- тун-шейдинг ---------- */
const grad = (() => {
  const d = new Uint8Array([70, 70, 70, 255, 150, 150, 150, 255, 255, 255, 255, 255]);
  const tx = new THREE.DataTexture(d, 3, 1, THREE.RGBAFormat);
  tx.minFilter = tx.magFilter = THREE.NearestFilter; tx.needsUpdate = true;
  return tx;
})();
export function toon(color, o = {}) {
  const m = new THREE.MeshToonMaterial({ color, gradientMap: grad, ...o });
  if (o.emissive != null) m.emissive = new THREE.Color(o.emissive);
  return m;
}
export const glow = (color, k = 2.5, o = {}) => new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(k), ...o });

/* Контур «вывернутой оболочкой»: копия меха с выдавливанием по нормали, рисуется только изнанка */
const outlineMats = new Map();
export function outlineMat(width = .02, color = 0x05060a) {
  const key = width + '_' + color;
  if (outlineMats.has(key)) return outlineMats.get(key);
  const m = new THREE.MeshBasicMaterial({ color, side: THREE.BackSide });
  m.onBeforeCompile = sh => {
    sh.vertexShader = sh.vertexShader.replace('#include <begin_vertex>',
      `vec3 transformed = position + normalize(normal) * ${width.toFixed(4)};`);
  };
  m.customProgramCacheKey = () => 'ol' + key;
  outlineMats.set(key, m);
  return m;
}
export function mesh(geo, mat, o = {}) {
  const m = new THREE.Mesh(geo, mat);
  if (o.pos) m.position.set(...o.pos);
  if (o.rot) m.rotation.set(...o.rot);
  if (o.scale) Array.isArray(o.scale) ? m.scale.set(...o.scale) : m.scale.setScalar(o.scale);
  if (o.outline !== false && o.outline !== undefined) {
    const ol = new THREE.Mesh(geo, outlineMat(o.outline));
    ol.renderOrder = -1;
    m.add(ol);
  }
  if (o.parent) o.parent.add(m);
  return m;
}

/* Канвас-текстура с текстом (неоновые вывески, таблички) */
export function textTexture(text, o = {}) {
  const c = document.createElement('canvas');
  const fs = o.size || 120, font = `${o.weight || 900} ${fs}px ${o.font || 'Unbounded'}`;
  const g = c.getContext('2d');
  g.font = font;
  const w = Math.ceil(g.measureText(text).width + fs * .6), h = Math.ceil(fs * 1.5);
  c.width = w; c.height = h;
  g.font = font; g.textAlign = 'center'; g.textBaseline = 'middle';
  if (o.bg) { g.fillStyle = o.bg; g.fillRect(0, 0, w, h); }
  if (o.stroke) { g.lineWidth = fs * .12; g.strokeStyle = o.stroke; g.strokeText(text, w / 2, h / 2 + fs * .05); }
  g.fillStyle = o.color || '#fff';
  g.fillText(text, w / 2, h / 2 + fs * .05);
  const tx = new THREE.CanvasTexture(c);
  tx.colorSpace = THREE.SRGBColorSpace;
  tx.anisotropy = 4;
  return { tex: tx, aspect: w / h };
}

export const V = (x, y, z) => new THREE.Vector3(x, y, z);
export { THREE };
