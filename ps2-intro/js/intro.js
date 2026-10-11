/* PlayStation 2 — современное интро, 1920×1080.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Тайминг привязан к оригинальной дорожке: гул стартует на 0.53 с, звон логотипа — 14.36 с. */
import * as THREE from 'three';
import { EffectComposer } from '../lib/three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from '../lib/three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from '../lib/three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from '../lib/three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from '../lib/three/addons/postprocessing/OutputPass.js';
import { RoomEnvironment } from '../lib/three/addons/environments/RoomEnvironment.js';
import { Reflector } from '../lib/three/addons/objects/Reflector.js';

const params = new URLSearchParams(location.search);
/* две версии: remake — бережный ремейк оригинала (20 с),
   pro — авторская Director's Cut (26 с): пролог, зеркальный пол, 3D-логотип из частиц */
const PRO = params.get('v') === 'pro';
const OFF = PRO ? 2.5 : 0;                        // в pro оригинальная дорожка стартует на 2.5 с позже
const W = 1920, H = 1080, DUR = PRO ? 26 : 20;
const OUT0 = PRO ? 23.9 : 18.3;                   // начало ухода в чёрное (абсолютное время)
const Q = +(params.get('q') || 1);               // масштаб: 1 = 1080p, 2 = 4K, 0.5 = превью

/* ключевые моменты (секунды, относительно оригинальной дорожки; абсолютное время = r + OFF) */
const T = {
  start: 0.53,   // в оригинале вступает гул
  sce0: 1.35,    // надпись Sony Computer Entertainment
  sce1: 3.95,
  dive0: 8.15,   // камера ныряет в центр
  cut1: 9.38,    // вспышка → пустота
  conv0: 9.7,    // цветные огни закручиваются к центру
  hit: 14.36,    // удар логотипа (звон в оригинале)
};

/* ---------- утилиты ---------- */
const clamp = (x, a = 0, b = 1) => x < a ? a : x > b ? b : x;
const lerp = (a, b, k) => a + (b - a) * k;
const E = {
  lin: x => x,
  inQuad: x => x * x,
  outQuad: x => 1 - (1 - x) * (1 - x),
  inCubic: x => x * x * x,
  outCubic: x => 1 - Math.pow(1 - x, 3),
  inOutCubic: x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2,
  inOutSine: x => -(Math.cos(Math.PI * x) - 1) / 2,
  outQuint: x => 1 - Math.pow(1 - x, 5),
  inExpo: x => x <= 0 ? 0 : Math.pow(2, 10 * x - 10),
  outExpo: x => x >= 1 ? 1 : 1 - Math.pow(2, -10 * x),
  outBack: x => { const c1 = 1.4, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
};
const P = (t, t0, d) => clamp((t - t0) / d);
function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, e] = keys[i], [t0, v0] = keys[i - 1];
    if (t <= t1) return lerp(v0, v1, (e || E.inOutCubic)(P(t, t0, t1 - t0)));
  }
  return keys[keys.length - 1][1];
}
function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}
const pulse = (t, t0, rise, fall) => t < t0 - rise ? 0 : t < t0 ? E.inCubic(P(t, t0 - rise, rise)) : Math.exp(-(t - t0) / fall);

/* ---------- процедурные текстуры ---------- */
function noise2(seed) {
  const R = rng(seed), N = 256, perm = new Uint8Array(512), gx = new Float32Array(N), gy = new Float32Array(N);
  for (let i = 0; i < N; i++) { perm[i] = i; const a = R() * Math.PI * 2; gx[i] = Math.cos(a); gy[i] = Math.sin(a); }
  for (let i = N - 1; i > 0; i--) { const j = (R() * (i + 1)) | 0; [perm[i], perm[j]] = [perm[j], perm[i]]; }
  for (let i = 0; i < N; i++) perm[i + N] = perm[i];
  const f = t => t * t * t * (t * (t * 6 - 15) + 10);
  return (x, y) => {
    const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, X = xi & 255, Y = yi & 255;
    const g = (ix, iy, dx, dy) => { const h = perm[perm[ix] + iy]; return gx[h] * dx + gy[h] * dy; };
    const u = f(xf), v = f(yf);
    const a = g(X, Y, xf, yf), b = g(X + 1, Y, xf - 1, yf), c = g(X, Y + 1, xf, yf - 1), d = g(X + 1, Y + 1, xf - 1, yf - 1);
    return lerp(lerp(a, b, u), lerp(c, d, u), v);
  };
}
function cloudTexture(seed, size = 256) {
  const n = noise2(seed), cv = document.createElement('canvas'); cv.width = cv.height = size;
  const ctx = cv.getContext('2d'), img = ctx.createImageData(size, size);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const u = x / size - .5, v = y / size - .5, r = Math.sqrt(u * u + v * v) * 2;
    let s = 0, amp = .5, fr = 3;
    for (let o = 0; o < 6; o++) { s += amp * n(u * fr + 10 + o * 3.1, v * fr - 7 + o * 1.7); amp *= .5; fr *= 2.03; }
    const fall = Math.pow(clamp(1 - r), 1.6);
    const val = clamp((s * 1.6 + .35)) * fall;
    const i = (y * size + x) * 4;
    img.data[i] = img.data[i + 1] = img.data[i + 2] = 255; img.data[i + 3] = Math.round(255 * Math.pow(val, 1.3));
  }
  ctx.putImageData(img, 0, 0);
  const tx = new THREE.CanvasTexture(cv); tx.colorSpace = THREE.SRGBColorSpace; return tx;
}
function glowTexture(size = 256, power = 2.2) {
  const cv = document.createElement('canvas'); cv.width = cv.height = size;
  const ctx = cv.getContext('2d'), img = ctx.createImageData(size, size);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const u = (x + .5) / size * 2 - 1, v = (y + .5) / size * 2 - 1, r = Math.sqrt(u * u + v * v);
    const a = Math.pow(clamp(1 - r), power) * .85 + Math.exp(-r * r * 60) * .15;
    const i = (y * size + x) * 4; img.data[i] = img.data[i + 1] = img.data[i + 2] = 255; img.data[i + 3] = Math.round(255 * clamp(a));
  }
  ctx.putImageData(img, 0, 0);
  return new THREE.CanvasTexture(cv);
}
function streakTexture() {
  const w = 512, h = 32, cv = document.createElement('canvas'); cv.width = w; cv.height = h;
  const ctx = cv.getContext('2d'), img = ctx.createImageData(w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const u = (x + .5) / w * 2 - 1, v = (y + .5) / h * 2 - 1;
    const a = Math.exp(-u * u * 5) * Math.exp(-v * v * 9) * (0.6 + 0.4 * Math.exp(-u * u * 60));
    const i = (y * w + x) * 4; img.data[i] = img.data[i + 1] = img.data[i + 2] = 255; img.data[i + 3] = Math.round(255 * clamp(a));
  }
  ctx.putImageData(img, 0, 0);
  return new THREE.CanvasTexture(cv);
}
async function logoTexture() {
  const img = new Image(); img.src = 'assets/ps2-logo.svg'; await img.decode();
  const w = 4096, h = Math.round(w * 740 / 3580), pad = 48;
  const cv = document.createElement('canvas'); cv.width = w + pad * 2; cv.height = h + pad * 2;
  cv.getContext('2d').drawImage(img, pad, pad, w, h);
  const tx = new THREE.CanvasTexture(cv); tx.anisotropy = 8; tx.generateMipmaps = true; tx.minFilter = THREE.LinearMipmapLinearFilter;
  return { tx, cv, pad, aspect: cv.width / cv.height };
}

/* ---------- светящиеся точки (пыль, хвосты комет, искры) ---------- */
const pointsMat = () => new THREE.ShaderMaterial({
  uniforms: { uScale: { value: 1 }, uMap: { value: null } },
  vertexShader: `attribute float aSize; attribute float aAlpha; attribute vec3 aColor; uniform float uScale;
    varying float vA; varying vec3 vC;
    void main(){ vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mv;
      gl_PointSize = max(aSize * uScale / -mv.z, 1.5); vA = aAlpha * clamp(aSize * uScale / -mv.z / 1.5, 0.0, 1.0); vC = aColor; }`,
  fragmentShader: `varying float vA; varying vec3 vC;
    void main(){ vec2 p = gl_PointCoord - 0.5; float d = length(p) * 2.0; float a = exp(-d * d * 5.0) - 0.0067;
      if (a <= 0.0) discard; gl_FragColor = vec4(vC, a * vA); }`,
  transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
});
function glowPoints(n) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(n * 3), 3));
  g.setAttribute('aSize', new THREE.BufferAttribute(new Float32Array(n), 1));
  g.setAttribute('aAlpha', new THREE.BufferAttribute(new Float32Array(n), 1));
  g.setAttribute('aColor', new THREE.BufferAttribute(new Float32Array(n * 3), 3));
  const m = pointsMat(), p = new THREE.Points(g, m); p.frustumCulled = false;
  p.pos = g.attributes.position.array; p.size = g.attributes.aSize.array; p.alpha = g.attributes.aAlpha.array; p.col = g.attributes.aColor.array;
  p.commit = () => { for (const k of ['position', 'aSize', 'aAlpha', 'aColor']) g.attributes[k].needsUpdate = true; };
  return p;
}
const pxScale = cam => H * Q / (2 * Math.tan(THREE.MathUtils.degToRad(cam.fov) / 2));

/* ---------- постобработка ---------- */
const RayShader = {
  uniforms: { tDiffuse: { value: null }, uLight: { value: new THREE.Vector2(.5, .5) }, uStr: { value: 0 }, uThresh: { value: .3 }, uDecay: { value: .96 }, uLen: { value: .8 } },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `uniform sampler2D tDiffuse; uniform vec2 uLight; uniform float uStr, uThresh, uDecay, uLen; varying vec2 vUv;
    float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    void main(){
      vec4 base = texture2D(tDiffuse, vUv);
      if (uStr <= 0.001) { gl_FragColor = base; return; }
      vec2 d = vUv - uLight; vec3 acc = vec3(0.0); float w = 1.0, tot = 0.0; float j = hash(vUv * 917.0);
      for (int i = 0; i < 40; i++) {
        float k = (float(i) + j) / 40.0;
        vec3 c = texture2D(tDiffuse, vUv - d * k * uLen).rgb;
        acc += max(c - uThresh, 0.0) * w; tot += w; w *= uDecay;
      }
      gl_FragColor = vec4(base.rgb + acc / tot * uStr, base.a);
    }`,
};
const FinalShader = {
  uniforms: { tDiffuse: { value: null }, uCA: { value: .002 }, uFlash: { value: 0 }, uFlashCol: { value: new THREE.Color(0.86, 0.92, 1) },
    uFade: { value: 0 }, uGrain: { value: .03 }, uVig: { value: .55 }, uSeed: { value: 0 } },
  vertexShader: RayShader.vertexShader,
  fragmentShader: `uniform sampler2D tDiffuse; uniform float uCA, uFlash, uFade, uGrain, uVig, uSeed; uniform vec3 uFlashCol; varying vec2 vUv;
    float hash(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
    void main(){
      vec2 c = vUv - 0.5; float r2 = dot(c, c);
      vec2 off = c * uCA * (0.35 + r2 * 3.0);
      vec3 col = vec3(texture2D(tDiffuse, vUv + off).r, texture2D(tDiffuse, vUv).g, texture2D(tDiffuse, vUv - off).b);
      float vig = smoothstep(0.9, 0.2, length(c * vec2(1.0, 0.78)));
      col *= mix(1.0, vig, uVig);
      col = mix(col, uFlashCol, clamp(uFlash, 0.0, 1.0));
      col *= 1.0 - uFade;
      float g = hash(gl_FragCoord.xy + uSeed * 37.0) + hash(gl_FragCoord.yx * 1.7 + uSeed * 11.0) - 1.0;
      col += g * uGrain * (0.35 + 0.65 * (1.0 - uFade));
      gl_FragColor = vec4(col, 1.0);
    }`,
};

/* ================================================================== */
const canvas = document.getElementById('gl');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, preserveDrawingBuffer: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Q);
renderer.setSize(W, H, false);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;

const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(W * Q, H * Q, { type: THREE.HalfFloatType, samples: 4 }));
const renderPass = new RenderPass(new THREE.Scene(), new THREE.PerspectiveCamera());
const bloom = new UnrealBloomPass(new THREE.Vector2(W, H), .8, .6, .6);
const rays = new ShaderPass(RayShader);
const output = new OutputPass();
const final = new ShaderPass(FinalShader);
[renderPass, bloom, rays, output, final].forEach(p => composer.addPass(p));

const tex = {};
const COLORS = [0xff3d6e, 0x34f5a4, 0x3d8bff, 0xff6fe8].map(c => new THREE.Color(c));   // красный, зелёный, синий, розовый

/* ---------- зеркальный пол с сеткой, волнами и бегущими огнями (только pro) ---------- */
const FloorShader = {
  name: 'Floor',
  uniforms: { color: { value: null }, tDiffuse: { value: null }, textureMatrix: { value: null },
    uRefl: { value: .4 }, uGrid: { value: .2 }, uBlur: { value: .0025 }, uFadeR: { value: 8 }, uStep: { value: 1.06 },
    uW: { value: new THREE.Vector4(-99, -99, -99, -99) }, uRun: { value: -1 }, uRunA: { value: 0 },
    uC0: { value: COLORS_LIN(0) }, uC1: { value: COLORS_LIN(1) }, uC2: { value: COLORS_LIN(2) }, uC3: { value: COLORS_LIN(3) } },
  vertexShader: `uniform mat4 textureMatrix; varying vec4 vUv; varying vec3 vW;
    void main(){ vUv = textureMatrix * vec4(position, 1.0); vW = (modelMatrix * vec4(position, 1.0)).xyz;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `uniform sampler2D tDiffuse; uniform float uRefl, uGrid, uBlur, uFadeR, uStep, uRun, uRunA; uniform vec4 uW;
    uniform vec3 uC0, uC1, uC2, uC3; varying vec4 vUv; varying vec3 vW;
    float runner(float along, float across, float run){
      float m = exp(-across * across * 1600.0) + exp(-across * across * 90.0) * 0.18;
      float d = run - along;
      float tl = d >= 0.0 ? exp(-d * 0.75) : exp(-d * d * 30.0);
      return m * tl * step(0.0, along);
    }
    void main(){
      vec2 p = vUv.xy / vUv.w; vec3 refl = vec3(0.0);
      for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) refl += texture2D(tDiffuse, p + vec2(float(i), float(j)) * uBlur).rgb;
      refl /= 9.0;
      float r = length(vW.xz), fade = exp(-r / uFadeR);
      vec2 q = vW.xz / uStep; vec2 g = abs(fract(q) - 0.5); vec2 fw = fwidth(q) * 1.2;
      vec2 l = 1.0 - smoothstep(vec2(0.0), fw + 0.004, g); float line = max(l.x, l.y);
      float wv = exp(-pow(r - uW.x, 2.0) * 1.2) + exp(-pow(r - uW.y, 2.0) * 1.2) + exp(-pow(r - uW.z, 2.0) * 1.2) * 0.8 + exp(-pow(r - uW.w, 2.0) * 0.6);
      vec3 col = refl * uRefl * mix(0.35, 1.0, fade);
      col += vec3(0.22, 0.38, 1.0) * line * fade * (uGrid + wv * 1.6);
      col += vec3(0.12, 0.2, 0.6) * wv * fade * 0.25;
      float h = uStep * 0.5;
      vec3 run = uC0 * runner(vW.x, vW.z - h, uRun) + uC1 * runner(-vW.x, vW.z + h, uRun)
               + uC2 * runner(vW.z, vW.x - h, uRun) + uC3 * runner(-vW.z, vW.x + h, uRun);
      col += run * uRunA * 5.0 * (0.4 + 0.6 * fade);
      gl_FragColor = vec4(col, 1.0);
    }`,
};
function COLORS_LIN(k) { return [0xff3d6e, 0x34f5a4, 0x3d8bff, 0xff6fe8].map(c => new THREE.Color(c))[k]; }
function makeFloor(scene, y, size = 80) {
  const f = new Reflector(new THREE.PlaneGeometry(size, size), { shader: FloorShader, textureWidth: (W * Q / 2) | 0, textureHeight: (H * Q / 2) | 0, multisample: 0, clipBias: .003 });
  f.rotation.x = -Math.PI / 2; f.position.y = y; scene.add(f);
  return f.material.uniforms;
}

/* ================== СЦЕНА A — поле светящихся башен ================== */
const A = { scene: new THREE.Scene(), cam: new THREE.PerspectiveCamera(42, W / H, .05, 200) };
function buildA() {
  const s = A.scene;
  s.background = new THREE.Color(0x010207);
  s.fog = new THREE.FogExp2(0x020718, .045);
  const pm = new THREE.PMREMGenerator(renderer);
  s.environment = pm.fromScene(new RoomEnvironment(), .04).texture;
  s.environmentIntensity = .22;

  s.add(new THREE.AmbientLight(0x1c2c66, .55));
  const key = new THREE.DirectionalLight(0xe6edff, 2.1); key.position.set(6, 30, 10); s.add(key);
  const rim = new THREE.DirectionalLight(0x5a7cff, .8); rim.position.set(-12, 6, -14); s.add(rim);
  A.core = new THREE.PointLight(0x3a62ff, 70, 20, 1.5); A.core.position.set(0, 1.2, 0); s.add(A.core);

  /* башни на сетке с пропусками, центр свободен для пролёта камеры */
  const R = rng(7), list = [], STEP = 1.06;
  for (let i = -17; i <= 17; i++) for (let j = -17; j <= 17; j++) {
    const x = i * STEP + (R() - .5) * .16, z = j * STEP + (R() - .5) * .16, d = Math.hypot(x, z);
    const keep = R(), wr = R(), hr = R(), tr = R(), dr = R(), gr = R(), ph = R(), pr = R(), pa = R();
    if (d > 16 || d < 1.45 || keep > .05 + .62 * Math.exp(-d / 6.5)) continue;
    list.push({ x, z, d, w: .4 + wr * .17,
      h: .4 + Math.pow(hr, 1.7) * 11 * (.4 + .6 * Math.exp(-d / 7)),
      t0: T.start - .15 + d * .13 + tr * .9, dur: 1.1 + dr * 1.5, glow: .25 + gr * .75,
      ph: ph * 6.283, pul: pr < .2 ? .1 + pa * .22 : 0 });
  }
  A.towers = list;
  const geo = new THREE.BoxGeometry(1, 1, 1); geo.translate(0, .5, 0);
  geo.setAttribute('aUv', geo.attributes.uv.clone());
  A.glowAttr = new THREE.InstancedBufferAttribute(new Float32Array(list.length), 1);
  geo.setAttribute('aGlow', A.glowAttr);
  const mat = new THREE.MeshStandardMaterial({ color: 0xdfe7ff, roughness: .38, metalness: 0, envMapIntensity: 1 });
  A.edge = { value: 1 };
  mat.onBeforeCompile = sh => {
    sh.uniforms.uEdge = A.edge; sh.uniforms.uEdgeCol = { value: new THREE.Color(0x8fb4ff) };
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute float aGlow; attribute vec2 aUv; varying float vGlow; varying vec3 vOP; varying vec3 vON; varying vec2 vUv2; varying float vWY;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvGlow = aGlow; vOP = position; vON = normal; vUv2 = aUv; vWY = (instanceMatrix * vec4(position, 1.0)).y;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform float uEdge; uniform vec3 uEdgeCol; varying float vGlow; varying vec3 vOP; varying vec3 vON; varying vec2 vUv2; varying float vWY;')
      .replace('#include <color_fragment>', '#include <color_fragment>\nfloat hy = clamp(vOP.y, 0.0, 1.0); float hw = clamp(vWY / 10.0, 0.0, 1.0);\ndiffuseColor.rgb *= mix(0.025, 1.0, pow(hw, 0.9));')
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        vec2 q = min(vUv2, 1.0 - vUv2); float e;
        if (vON.y > 0.5) e = (1.0 - smoothstep(0.0, 0.06, min(q.x, q.y))) * 1.4 + 0.18;
        else e = (1.0 - smoothstep(0.0, 0.045, q.x)) * pow(hy, 2.0) * 0.9 + pow(hy, 6.0) * 0.12;
        totalEmissiveRadiance += uEdgeCol * e * vGlow * uEdge * (0.15 + 0.85 * pow(hw, 1.1));`);
  };
  A.mesh = new THREE.InstancedMesh(geo, mat, list.length);
  A.mesh.frustumCulled = false;
  s.add(A.mesh);

  /* туманность в центре: слои облаков, башни их заслоняют → объём */
  A.neb = [];
  const RN = rng(21);
  for (let k = 0; k < 14; k++) {
    const m = new THREE.SpriteMaterial({ map: tex.cloud[k % 3], color: new THREE.Color().setHSL(.6 + RN() * .08, .9, .38 + RN() * .2),
      transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false, opacity: .5 });
    const sp = new THREE.Sprite(m); const a = RN() * 6.28, r = RN() * 3.2;
    sp.position.set(Math.cos(a) * r, .2 + RN() * 2.6, Math.sin(a) * r);
    sp.base = { sc: 5 + RN() * 9, rot: RN() * 6.28, spd: (RN() - .5) * .16, ph: RN() * 6.28, op: .14 + RN() * .22 };
    s.add(sp); A.neb.push(sp);
  }
  A.coreGlow = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex.glow, color: 0x6f8fff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
  A.coreGlow.position.set(0, .9, 0); s.add(A.coreGlow);

  /* пыль */
  const RD = rng(33), ND = 2600; A.dust = glowPoints(ND); A.dustSeed = [];
  for (let i = 0; i < ND; i++) {
    A.dustSeed.push([(RD() - .5) * 34, RD() * 9, (RD() - .5) * 34, RD() * 6.28, .02 + RD() * .05]);
    const c = .5 + RD() * .5; A.dust.col.set([.55 * c, .7 * c, 1.0 * c], i * 3);
  }
  s.add(A.dust);

  /* кометы — цветные огоньки, как в оригинале, но с хвостами и подсветкой башен */
  A.comets = COLORS.map((c, k) => makeComet(s, c, 56, .32, true));
  if (PRO) {
    A.floor = makeFloor(s, 0);
    A.igFlare = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex.streak, color: 0x9fb8ff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
    s.add(A.igFlare);
  }
}
function makeComet(scene, color, n, head, withLight) {
  const tr = glowPoints(n); scene.add(tr);
  const st = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex.streak, color, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
  scene.add(st);
  let light = null; if (withLight) { light = new THREE.PointLight(color, 0, 7, 1.8); scene.add(light); }
  return { tr, st, light, color, n, head };
}
/* fn(t) → [x,y,z]; trail — шаг по времени между точками хвоста */
function updComet(c, fn, t, inten, trail, streak = 1) {
  const p0 = fn(t);
  for (let i = 0; i < c.n; i++) {
    const p = fn(t - i * trail), f = 1 - i / c.n;
    c.tr.pos.set(p, i * 3);
    c.tr.size[i] = (i === 0 ? c.head * 1.6 : c.head * (.25 + .75 * f)) ;
    c.tr.alpha[i] = inten * Math.pow(f, 1.6) * (i === 0 ? 1 : .8);
    const wb = i < 2 ? 1.6 : 1;   // ядро — почти белое
    c.tr.col.set([lerp(c.color.r, 1, i < 2 ? .6 : 0) * 3 * wb, lerp(c.color.g, 1, i < 2 ? .6 : 0) * 3 * wb, lerp(c.color.b, 1, i < 2 ? .6 : 0) * 3 * wb], i * 3);
  }
  c.tr.commit();
  c.st.position.set(...p0);
  c.st.scale.set(c.head * 9 * streak, c.head * .5, 1);
  c.st.material.opacity = clamp(inten) * .9;
  c.st.visible = inten > .01;
  if (c.light) { c.light.position.set(...p0); c.light.intensity = inten * 9; }
}
const cometPathA = k => t => {
  const s = t * (.95 + k * .17) + k * 1.9;
  const r = 4.2 + 3.2 * Math.sin(s * .63 + k * 2.1);
  return [r * Math.cos(s), 1.8 + 2.2 * (.5 + .5 * Math.sin(s * 1.27 + k * 1.3)), r * Math.sin(s)];
};

const tmpM = new THREE.Matrix4(), tmpQ = new THREE.Quaternion(), tmpV = new THREE.Vector3(), tmpS = new THREE.Vector3();
function renderA(t, ta) {
  const s = A.scene, cam = A.cam;
  /* башни */
  const wave1 = (t - 3.1) * 7.5, wave2 = (t - 6.0) * 7.5;
  for (let i = 0; i < A.towers.length; i++) {
    const b = A.towers[i], p = P(t, b.t0, b.dur);
    let h = b.h * E.outBack(p);
    if (b.pul) h *= 1 + b.pul * Math.sin(t * 1.4 + b.ph) * E.inOutSine(P(t, b.t0 + b.dur, 1.5));
    h = Math.max(h, .001);
    tmpV.set(b.x, 0, b.z); if (p > 0) tmpS.set(b.w, h, b.w); else tmpS.set(0, 0, 0);
    A.mesh.setMatrixAt(i, tmpM.compose(tmpV, tmpQ, tmpS));
    const land = t > b.t0 + b.dur * .55 ? Math.exp(-(t - b.t0 - b.dur * .55) * 2.2) : 0;
    const wv = Math.exp(-Math.pow(b.d - wave1, 2) * .5) + Math.exp(-Math.pow(b.d - wave2, 2) * .5) * .8;
    A.glowAttr.array[i] = b.glow * (.25 + 2.2 * land * E.outQuad(p)) + wv * 1.6 * E.outQuad(p);
  }
  A.mesh.instanceMatrix.needsUpdate = true; A.glowAttr.needsUpdate = true;
  A.edge.value = kf(t, [[0, 0], [T.start, .15], [2.5, .7], [T.dive0, .8], [T.cut1, 2.0, E.inCubic]]);

  /* туманность */
  const nebIn = kf(t, [[0, 0], [T.start, .05], [3.5, 1, E.inOutSine], [8.6, 1.1], [T.cut1, 1.5, E.inQuad]]);
  for (const sp of A.neb) {
    const b = sp.base;
    sp.material.rotation = b.rot + t * b.spd;
    sp.material.opacity = b.op * nebIn * (.8 + .2 * Math.sin(t * .7 + b.ph));
    const sc = b.sc * (.9 + .1 * Math.sin(t * .4 + b.ph)); sp.scale.set(sc, sc, 1);
  }
  const cg = kf(t, [[0, 0], [T.start, .1], [3, .8], [8.6, .9], [T.cut1, 2.2, E.inCubic]]);
  A.coreGlow.material.opacity = cg * .6; A.coreGlow.scale.setScalar(4 + cg * 2.5);
  A.core.intensity = 70 * kf(t, [[0, 0], [T.start, .1], [3, 1], [T.cut1, 1.8]]);

  /* пыль */
  const dIn = kf(t, [[0, 0], [1.2, 1]]);
  for (let i = 0; i < A.dustSeed.length; i++) {
    const [x, y, z, ph, sz] = A.dustSeed[i];
    A.dust.pos.set([x + Math.sin(t * .2 + ph) * .3, (y + t * .12 + Math.sin(t * .5 + ph) * .2) % 9, z + Math.cos(t * .17 + ph) * .3], i * 3);
    A.dust.size[i] = sz; A.dust.alpha[i] = .55 * dIn * (.6 + .4 * Math.sin(t * 2 + ph * 3));
  }
  A.dust.commit();

  /* камера: почти сверху, медленный дрейф, затем нырок в центр */
  let az = .55 + t * .055 + .55 * E.inCubic(P(t, T.dive0, T.cut1 - T.dive0));
  let el = THREE.MathUtils.degToRad(kf(t, [[0, 80], [T.dive0, 70, E.inOutSine], [T.cut1, 44, E.inCubic]]));
  let dist = kf(t, [[0, 24], [T.dive0, 16.5, E.inOutSine], [T.cut1, 1.2, E.inCubic]]);
  const tgt = new THREE.Vector3(0, kf(t, [[0, .4], [T.cut1, 1.1]]), 0);
  if (PRO) {
    /* пролог: камера у самого пола, затем кран вверх, пока вокруг вырастают башни */
    az = -.35 + ta * .075 + .55 * E.inCubic(P(t, T.dive0, T.cut1 - T.dive0));
    el = THREE.MathUtils.degToRad(kf(ta, [[0, 4], [2.2, 8, E.inOutSine], [OFF + 3.7, 76, E.inOutCubic], [OFF + T.dive0, 70, E.inOutSine], [OFF + T.cut1, 44, E.inCubic]]));
    dist = kf(ta, [[0, 7], [2.2, 10, E.inOutSine], [OFF + 3.7, 24, E.inOutCubic], [OFF + T.dive0, 16.5, E.inOutSine], [OFF + T.cut1, 1.2, E.inCubic]]);
    tgt.y = kf(ta, [[0, .25], [2.4, .5], [OFF + 3.7, .4], [OFF + T.cut1, 1.1]]);
  }
  cam.position.set(tgt.x + Math.cos(az) * Math.cos(el) * dist, tgt.y + Math.sin(el) * dist, tgt.z + Math.sin(az) * Math.cos(el) * dist);
  cam.up.set(0, 1, 0); cam.lookAt(tgt);
  cam.rotateZ(THREE.MathUtils.degToRad(kf(t, [[0, -4], [T.dive0, 6, E.inOutSine], [T.cut1, 22, E.inCubic]]) * (PRO ? E.inOutSine(P(ta, 2.4, 3)) : 1)));
  cam.fov = PRO ? kf(ta, [[0, 34], [2.4, 38], [OFF + 3.7, 40], [OFF + T.dive0, 42], [OFF + T.cut1, 64, E.inCubic]]) : kf(t, [[0, 40], [T.dive0, 42], [T.cut1, 64, E.inCubic]]);
  cam.updateProjectionMatrix();
  const sc = pxScale(cam);
  A.dust.material.uniforms.uScale.value = sc;

  /* кометы */
  const cIn = kf(t, [[2.0, 0], [3.0, 1], [T.dive0, 1], [T.cut1, 1.6]]);
  A.comets.forEach((c, k) => { c.tr.material.uniforms.uScale.value = sc; updComet(c, cometPathA(k), t, cIn * (k === 3 ? .8 : 1), .011, .9); });

  /* пост: лучи из центра туманности */
  tmpV.copy(tgt).project(cam);
  rays.uniforms.uLight.value.set(tmpV.x * .5 + .5, tmpV.y * .5 + .5);
  rays.uniforms.uStr.value = kf(t, [[0, 0], [3, .28], [T.dive0, .32], [T.cut1, 1.1, E.inCubic]]);
  rays.uniforms.uThresh.value = .35; rays.uniforms.uDecay.value = .965; rays.uniforms.uLen.value = .75;
  bloom.strength = kf(t, [[0, .55], [8.6, .65], [T.cut1, 1.5, E.inCubic]]); bloom.radius = .6; bloom.threshold = .6;
  if (PRO) {
    /* зажигание: в темноте вспыхивает точка, по полу бегут четыре цветных огня и волна */
    const ign = pulse(ta, .62, .05, .5);
    A.coreGlow.material.opacity = Math.max(A.coreGlow.material.opacity, ign * .9 + E.outCubic(P(ta, .6, 1.2)) * .5 * (1 - P(t, 3, 2)));
    A.igFlare.position.copy(A.coreGlow.position); A.igFlare.scale.set(2.5 + ign * 8, .08 + ign * .16, 1); A.igFlare.material.opacity = ign * .7 + .25 * E.outCubic(P(ta, .6, .8)) * (1 - P(t, 0, 2));
    A.coreGlow.scale.setScalar(t > 0 ? 4 + cg * 2.5 : .5 + ign * 1.6 + 1.6 * E.outCubic(P(ta, .6, 1.5)) + 3.5 * E.inOutSine(P(ta, 1.5, OFF + .5 - 1.5)));
    A.core.intensity = Math.max(A.core.intensity, 70 * (ign * 1.5 + .35 * P(ta, .6, 1)));
    const f = A.floor;
    f.uRefl.value = .55; f.uBlur.value = .0022;
    f.uGrid.value = .08 * E.outCubic(P(ta, .7, 2.5)) + .05 * A.edge.value;
    f.uW.value.set((ta - .65) * 7, (t - 3.1) * 7.5, (t - 6.0) * 7.5, (ta - OFF - T.cut1 + .5) * 30);
    f.uRun.value = (ta - .7) * 9; f.uRunA.value = ta > .7 ? Math.exp(-Math.max(0, ta - 2.2) * .9) : 0;
    rays.uniforms.uStr.value = Math.max(rays.uniforms.uStr.value, ign * .9);
    bloom.strength = Math.max(bloom.strength, .55 + ign * .8);
  }
  return [s, cam];
}

/* ================== СЦЕНА B — гиперпространство и сходящиеся огни ================== */
const B = { scene: new THREE.Scene(), cam: new THREE.PerspectiveCamera(50, W / H, .05, 300) };
const ZR = 95;
function buildB() {
  const s = B.scene; s.background = new THREE.Color(0x000105);
  const R = rng(55), N = 4200; B.stars = glowPoints(N); B.starSeed = [];
  for (let i = 0; i < N; i++) {
    const a = R() * 6.283, r = 1.2 + Math.pow(R(), .7) * 26;
    B.starSeed.push([Math.cos(a) * r, Math.sin(a) * r, -R() * ZR, .03 + R() * .09, R() * 6.28]);
    const c = R(), m = .6 + R() * .4;
    B.stars.col.set(c < .7 ? [.55 * m, .72 * m, 1.1 * m] : c < .85 ? [.9 * m, .6 * m, 1.1 * m] : [1.1 * m, 1.1 * m, 1.1 * m], i * 3);
  }
  s.add(B.stars);
  /* линии-стрики (растягиваются со скоростью) */
  const NL = 900; B.lineSeed = [];
  const lg = new THREE.BufferGeometry();
  lg.setAttribute('position', new THREE.BufferAttribute(new Float32Array(NL * 6), 3));
  lg.setAttribute('color', new THREE.BufferAttribute(new Float32Array(NL * 6), 3));
  for (let i = 0; i < NL; i++) { const a = R() * 6.283, r = 2 + Math.pow(R(), .6) * 22; B.lineSeed.push([Math.cos(a) * r, Math.sin(a) * r, -R() * ZR, .4 + R() * .6]); }
  B.lines = new THREE.LineSegments(lg, new THREE.LineBasicMaterial({ vertexColors: true, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
  B.lines.frustumCulled = false; s.add(B.lines);
  /* дальняя туманность */
  B.neb = [];
  for (let k = 0; k < 7; k++) {
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex.cloud[k % 3], color: new THREE.Color().setHSL(.62 + R() * .12, .85, .3 + R() * .15),
      transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: .5 }));
    sp.position.set((R() - .5) * 30, (R() - .5) * 16, -45 - R() * 20); sp.base = { sc: 30 + R() * 30, rot: R() * 6.28, spd: (R() - .5) * .1 };
    s.add(sp); B.neb.push(sp);
  }
  B.core = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex.glow, color: 0xaac4ff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
  s.add(B.core);
  B.comets = COLORS.map(c => makeComet(s, c, 160, .22, false));
}
/* путь пролёта сквозь «звёзды»: быстро после вспышки, затишье, разгон к удару */
function travel(t) {
  const u = Math.max(0, t - T.cut1);
  return 46 * (1 - Math.exp(-u * 2.6)) + 2.2 * u + Math.pow(Math.max(0, t - 11.6), 3) * 2.3;
}
const speedAt = t => (travel(t + .01) - travel(t - .01)) / .02;
const cometPathB = k => t => {
  const tau = P(t, T.conv0, T.hit - T.conv0);
  const r = 7.5 * (1 - E.inCubic(tau)) * (1 - .25 * tau) + .02;
  const a = k * Math.PI / 2 + .9 * (t - T.conv0) + 7.5 * Math.pow(tau, 2.6);
  const z = -16 * Math.pow(1 - tau, 1.6);
  return [Math.cos(a) * r * 1.25, Math.sin(a) * r * .8, z];
};
function renderB(t) {
  const s = B.scene, cam = B.cam;
  const tau = P(t, T.conv0, T.hit - T.conv0);
  cam.position.set(0, 0, kf(t, [[T.cut1, 12], [T.hit, 9.5, E.inOutSine]]));
  cam.up.set(0, 1, 0); cam.lookAt(0, 0, 0);
  const shake = Math.pow(P(t, 12.8, T.hit - 12.8), 2) * .05;
  cam.rotateZ(THREE.MathUtils.degToRad(kf(t, [[T.cut1, -10], [T.hit, 28, E.inOutSine]])) + Math.sin(t * 61) * shake);
  cam.position.x += Math.sin(t * 47.3) * shake; cam.position.y += Math.cos(t * 53.1) * shake;
  cam.fov = kf(t, [[T.cut1, 70], [10.4, 50, E.outCubic], [13.2, 50], [T.hit, 60, E.inCubic]]);
  cam.updateProjectionMatrix();
  const sc = pxScale(cam), S = travel(t), v = speedAt(t);
  B.stars.material.uniforms.uScale.value = sc;
  const fadeIn = kf(t, [[T.cut1, 0], [T.cut1 + .25, 1]]);
  for (let i = 0; i < B.starSeed.length; i++) {
    const [x, y, z0, sz, ph] = B.starSeed[i];
    const z = ((z0 + S) % ZR + ZR) % ZR - ZR + 10;
    B.stars.pos.set([x, y, z], i * 3);
    B.stars.size[i] = sz;
    B.stars.alpha[i] = fadeIn * clamp((z + ZR - 10) / 25) * clamp((11 - z) / 4) * (.7 + .3 * Math.sin(t * 3 + ph));
  }
  B.stars.commit();
  const lp = B.lines.geometry.attributes.position.array, lc = B.lines.geometry.attributes.color.array;
  const len = clamp(v * .035, .05, 9);
  for (let i = 0; i < B.lineSeed.length; i++) {
    const [x, y, z0, br] = B.lineSeed[i];
    const z = ((z0 + S * 1.15) % ZR + ZR) % ZR - ZR + 10;
    lp.set([x, y, z, x, y, z - len], i * 6);
    const a = fadeIn * br * clamp((z + ZR - 10) / 30) * clamp((11 - z) / 3) * clamp(v / 25) * 1.4;
    lc.set([.5 * a, .65 * a, 1.2 * a, 0, 0, 0], i * 6);
  }
  B.lines.geometry.attributes.position.needsUpdate = true; B.lines.geometry.attributes.color.needsUpdate = true;
  for (const sp of B.neb) { sp.material.rotation = sp.base.rot + t * sp.base.spd; sp.scale.setScalar(sp.base.sc); sp.material.opacity = .45 * fadeIn * (.6 + .6 * tau); }

  const cIn = kf(t, [[T.conv0 - .2, 0], [T.conv0 + .6, 1], [T.hit, 2.2, E.inCubic]]);
  B.comets.forEach((c, k) => { c.tr.material.uniforms.uScale.value = sc; updComet(c, cometPathB(k), t, cIn, .0042, .7 + .6 * tau * tau); });
  const ce = Math.pow(tau, 3.5);
  B.core.material.opacity = clamp(ce * 1.0 + .05 * fadeIn); B.core.scale.setScalar(.6 + ce * 3 + Math.sin(t * 40) * ce * .15);

  rays.uniforms.uLight.value.set(.5, .5);
  rays.uniforms.uStr.value = .5 * E.inCubic(P(t, T.hit - .35, .35)); rays.uniforms.uThresh.value = 3.0; rays.uniforms.uDecay.value = .97; rays.uniforms.uLen.value = .9;
  bloom.strength = .85 + ce * .5; bloom.radius = .65; bloom.threshold = .55;
  return [s, cam];
}

/* ================== СЦЕНА C — логотип ================== */
const C = { scene: new THREE.Scene(), cam: new THREE.PerspectiveCamera(34, W / H, .05, 200) };
/* путь из SVG (M/L/C, абсолютные координаты potrace) → THREE.Shape[]; дырки определяются по вложенности контуров */
function svgShapes(d, map) {
  const tok = d.match(/[MLCZmlcz]|-?\d*\.?\d+(?:e-?\d+)?/g), paths = [];
  let i = 0, cmd = null, cur = null; const num = () => +tok[i++];
  while (i < tok.length) {
    if (/[A-Za-z]/.test(tok[i])) cmd = tok[i++].toUpperCase();
    if (cmd === 'M') { const [x, y] = map(num(), num()); cur = new THREE.Path(); cur.moveTo(x, y); paths.push(cur); cmd = 'L'; }
    else if (cmd === 'L') { const [x, y] = map(num(), num()); cur.lineTo(x, y); }
    else if (cmd === 'C') { const a = map(num(), num()), b = map(num(), num()), c = map(num(), num()); cur.bezierCurveTo(a[0], a[1], b[0], b[1], c[0], c[1]); }
    else if (cmd === 'Z') cmd = null;
    else i++;
  }
  const pts = paths.map(p => p.getPoints(12));
  const inside = (pt, poly) => { let c = false; for (let a = 0, b = poly.length - 1; a < poly.length; b = a++) {
    const A = poly[a], B = poly[b]; if ((A.y > pt.y) !== (B.y > pt.y) && pt.x < (B.x - A.x) * (pt.y - A.y) / (B.y - A.y) + A.x) c = !c; } return c; };
  const area = poly => Math.abs(THREE.ShapeUtils.area(poly));
  const info = pts.map((poly, k) => ({ k, poly, area: area(poly), parents: pts.map((q, j) => j !== k && area(q) > area(poly) && inside(poly[0], q) ? j : -1).filter(j => j >= 0) }));
  const shapes = new Map();
  for (const n of info) if (n.parents.length % 2 === 0) {
    const sh = new THREE.Shape(THREE.ShapeUtils.isClockWise(n.poly) ? n.poly.slice().reverse() : n.poly); shapes.set(n.k, sh);
  }
  for (const n of info) if (n.parents.length % 2 === 1) {
    const par = n.parents.reduce((m, j) => !shapes.has(j) ? m : m < 0 || info[j].area < info[m].area ? j : m, -1);
    if (par >= 0) shapes.get(par).holes.push(new THREE.Path(THREE.ShapeUtils.isClockWise(n.poly) ? n.poly : n.poly.slice().reverse()));
  }
  return [...shapes.values()];
}
function buildC() {
  const s = C.scene; s.background = new THREE.Color(0x000000);
  const L = tex.logo, LW = PRO ? 5.4 : 5.6, LH = LW / L.aspect;
  C.logoMat = new THREE.ShaderMaterial({
    uniforms: { map: { value: L.tx }, uInt: { value: 2.4 }, uShine: { value: -2 }, uReveal: { value: 1.5 }, uAlpha: { value: 1 }, uTint: { value: new THREE.Color(1, 1, 1) } },
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform sampler2D map; uniform float uInt, uShine, uReveal, uAlpha; uniform vec3 uTint; varying vec2 vUv;
      void main(){
        float a = texture2D(map, vUv).a;
        float dx = abs(vUv.x - 0.5) * 2.0;
        float rv = 1.0 - smoothstep(uReveal - 0.12, uReveal, dx);
        float edge = exp(-pow((dx - uReveal + 0.06) * 16.0, 2.0)) * step(0.001, uReveal) * (1.0 - step(1.3, uReveal));
        float band = exp(-pow((vUv.x + (vUv.y - 0.5) * 0.35 - uShine) * 7.0, 2.0));
        vec3 col = uTint * uInt + vec3(0.7, 0.82, 1.0) * (band * 3.0 + edge * 5.0);
        gl_FragColor = vec4(col, a * rv * uAlpha);
      }`,
    transparent: true, depthWrite: false,
  });
  C.logo = new THREE.Mesh(new THREE.PlaneGeometry(LW, LH), C.logoMat); s.add(C.logo);
  if (params.get('dbg')) C.logo.visible = false;
  C.LW = LW; C.LH = LH;

  /* фон — едва заметная синяя глубина */
  C.neb = [];
  const R = rng(91);
  for (let k = 0; k < 6; k++) {
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex.cloud[k % 3], color: new THREE.Color().setHSL(.6 + R() * .1, .8, .2 + R() * .08),
      transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: .5 }));
    sp.position.set((R() - .5) * 14, (R() - .5) * 6 + 1, -12 - R() * 10); sp.base = { sc: 16 + R() * 16, rot: R() * 6.28, spd: (R() - .5) * .08 };
    s.add(sp); C.neb.push(sp);
  }
  /* искры удара */
  const NS = 1400; C.sparks = glowPoints(NS); C.sparkSeed = [];
  for (let i = 0; i < NS; i++) {
    const a = R() * 6.283, u = R() * 2 - 1, sq = Math.sqrt(1 - u * u);
    const dir = [Math.cos(a) * sq, u * .45, Math.sin(a) * sq * .6];
    const spd = 1.5 + Math.pow(R(), 1.8) * 10;
    C.sparkSeed.push([dir, spd, .02 + R() * .05, R() * 6.28, .4 + R() * 1.4]);
    const pick = R(); const col = pick < .72 ? new THREE.Color(.75, .85, 1.2) : COLORS[(pick * 13 | 0) % 4];
    C.sparks.col.set([col.r * 2, col.g * 2, col.b * 2], i * 3);
  }
  s.add(C.sparks);
  /* пыль */
  const ND = 1400; C.dust = glowPoints(ND); C.dustSeed = [];
  for (let i = 0; i < ND; i++) { C.dustSeed.push([(R() - .5) * 22, (R() - .5) * 12, -R() * 14 + 2, R() * 6.28, .015 + R() * .03]); C.dust.col.set([.6, .72, 1.1], i * 3); }
  s.add(C.dust);
  /* ударные кольца и анаморфный блик */
  const ringMat = (w, col) => new THREE.ShaderMaterial({
    uniforms: { uR: { value: 0 }, uW: { value: w }, uA: { value: 0 }, uCol: { value: new THREE.Color(col) } },
    vertexShader: `varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform float uR, uW, uA; uniform vec3 uCol; varying vec2 vP;
      void main(){ float r = length(vP * vec2(1.0, 1.6)); float a = exp(-pow((r - uR) / uW, 2.0)) * uA; gl_FragColor = vec4(uCol * 2.0, a); }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending });
  C.rings = [ringMat(.1, 0x9fbfff), ringMat(.035, 0xffffff), ringMat(.18, 0x6a5cff)].map(m => { const r = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), m); r.position.z = -.3; s.add(r); return r; });
  C.flare = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex.streak, color: 0x8fb0ff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
  C.flare.position.z = .4; s.add(C.flare);
  C.burst = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex.glow, color: 0xc8d8ff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
  C.burst.position.z = .3; s.add(C.burst);

  if (!PRO) return;
  /* ---- Director's Cut: объёмный логотип, частицы, пол, орбиты огней ---- */
  const pm = new THREE.PMREMGenerator(renderer);
  s.environment = pm.fromScene(new RoomEnvironment(), .02).texture; s.environmentIntensity = .7;
  const inner = LW * (L.cv.width - 2 * L.pad) / L.cv.width, k = inner / 3580, DEPTH = .3;
  const shapes = svgShapes(tex.logoPath, (x, y) => [(x - 1905) * k, -(y - 470) * k]);
  const eg = new THREE.ExtrudeGeometry(shapes, { depth: DEPTH, bevelEnabled: true, bevelThickness: .018, bevelSize: .01, bevelSegments: 3 });
  eg.translate(0, 0, -DEPTH - .02);
  C.sideMat = new THREE.MeshPhysicalMaterial({ color: 0xb8c8ff, metalness: 1, roughness: .2, clearcoat: 1, clearcoatRoughness: .1, envMapIntensity: 1.5 });
  C.capMat = new THREE.MeshStandardMaterial({ color: 0xeef2ff, metalness: .2, roughness: .3, emissive: 0xffffff, emissiveIntensity: .5 });
  C.solid = new THREE.Mesh(eg, [C.capMat, C.sideMat]); s.add(C.solid);
  C.logo.position.z = .002;
  s.add(new THREE.AmbientLight(0x2a3a7a, .4));
  C.sweep = new THREE.PointLight(0xbfd0ff, 0, 14, 1.5); s.add(C.sweep);
  C.floorY = -370 * k - .32;
  C.floor = makeFloor(s, C.floorY, 120);
  /* частицы, собирающиеся в логотип */
  const cv = L.cv, ctx = cv.getContext('2d'), img = ctx.getImageData(0, 0, cv.width, cv.height).data;
  const NP = 11000; C.parts = glowPoints(NP); C.partSeed = [];
  for (let i = 0, tries = 0; i < NP && tries < 4e6; tries++) {
    const px = R() * cv.width | 0, py = R() * cv.height | 0;
    if (img[(py * cv.width + px) * 4 + 3] < 150) continue;
    const tx = (px / cv.width - .5) * LW, ty = (.5 - py / cv.height) * LH;
    const a = R() * 6.283, u = R() * 2 - 1, sq = Math.sqrt(1 - u * u);
    C.partSeed.push([tx, ty, [Math.cos(a) * sq, u * .6, Math.sin(a) * sq * .5], 2 + R() * 6, .1 + (tx / LW + .5) * .4 + R() * .12, .018 + R() * .022, R() * 6.28]);
    const pick = R(), c = pick < .8 ? new THREE.Color(.8, .88, 1.2) : COLORS[(pick * 17 | 0) % 4];
    C.parts.col.set([c.r * 2.2, c.g * 2.2, c.b * 2.2], i * 3); i++;
  }
  s.add(C.parts);
  /* четыре цветных огня облетают логотип и подсвечивают металл */
  C.comets = COLORS.map(c => makeComet(s, c, 90, .16, true));
}
const cometPathC = k => t => {
  const u = t - T.hit, a = k * Math.PI / 2 + .4 + u * (1.25 - k * .06);
  const r = 2.0 + 2.6 * E.outCubic(clamp(u / 1.6));
  return [Math.cos(a) * r * 1.25, -.42 + .06 * Math.sin(a * 2 + k), Math.sin(a) * r * .6 - .3];
};
function renderC(t, ta) {
  const s = C.scene, cam = C.cam, u = t - T.hit;
  const hitE = Math.exp(-u * 3.2);
  if (PRO) {
    const az = THREE.MathUtils.degToRad(kf(u, [[0, -34], [3.2, -5, E.outCubic], [DUR, 7, E.lin]]));
    const el = THREE.MathUtils.degToRad(kf(u, [[0, 9], [3.2, 4, E.outCubic], [DUR, 2.5]]));
    const dist = kf(u, [[0, 8.6], [3.2, 10.6, E.outCubic], [DUR - OFF - T.hit, 9.9, E.inOutSine]]);
    cam.position.set(Math.sin(az) * Math.cos(el) * dist, Math.sin(el) * dist + .05, Math.cos(az) * Math.cos(el) * dist);
    cam.up.set(0, 1, 0); cam.lookAt(0, -.05, 0);
  } else {
    cam.position.set(Math.sin(u * .35) * .12, .05 + Math.sin(u * .27) * .05, kf(t, [[T.hit, 9.0], [T.hit + 1.2, 10.4, E.outCubic], [20, 9.7, E.inOutSine]]));
    cam.up.set(0, 1, 0); cam.lookAt(0, 0, 0);
  }
  cam.rotateZ(THREE.MathUtils.degToRad(kf(u, [[0, 3], [1.4, 0, E.outCubic]])));
  cam.fov = 34; cam.updateProjectionMatrix();
  const sc = pxScale(cam);

  const lm = C.logoMat.uniforms;
  lm.uReveal.value = PRO ? 1.25 : lerp(0, 1.25, E.outCubic(P(u, 0, .55)));
  lm.uInt.value = PRO ? 1.7 + .5 * Math.exp(-Math.pow(u - 1.35, 2) * 5) : 2.0 + 1.5 * hitE;
  lm.uShine.value = u < 2.5 ? lerp(-.6, 1.8, E.inOutSine(P(u, PRO ? 1.3 : .5, 1.5))) : lerp(-.6, 1.8, E.inOutSine(P(u, PRO ? 4.4 : 2.6, 1.4)));
  lm.uAlpha.value = PRO ? E.inOutSine(P(u, 1.1, .6)) : 1;
  const ls = 1 + (PRO ? 0 : .03 * hitE) + .02 * E.outCubic(P(u, 0, 6)); C.logo.scale.set(ls, ls, 1);

  for (const sp of C.neb) { sp.material.rotation = sp.base.rot + t * sp.base.spd; sp.scale.setScalar(sp.base.sc); sp.material.opacity = .3 + .4 * hitE; }

  C.sparks.material.uniforms.uScale.value = sc;
  for (let i = 0; i < C.sparkSeed.length; i++) {
    const [d, spd, sz, ph, life] = C.sparkSeed[i], k = 2.4, dd = spd * (1 - Math.exp(-k * u)) / k + u * .15;
    C.sparks.pos.set([d[0] * dd, d[1] * dd - u * u * .02, d[2] * dd + .3], i * 3);
    C.sparks.size[i] = sz * (1 + 1.5 * Math.exp(-u * 4));
    C.sparks.alpha[i] = Math.exp(-u / life) * (.65 + .35 * Math.sin(u * 9 + ph)) * (PRO ? .6 : 1);
  }
  C.sparks.commit();
  C.dust.material.uniforms.uScale.value = sc;
  for (let i = 0; i < C.dustSeed.length; i++) {
    const [x, y, z, ph, sz] = C.dustSeed[i];
    C.dust.pos.set([x + Math.sin(t * .15 + ph) * .4 + u * .05, y + Math.cos(t * .13 + ph) * .3, z], i * 3);
    C.dust.size[i] = sz; C.dust.alpha[i] = .4 * (.5 + .5 * Math.sin(t * 1.3 + ph * 2)) * E.outCubic(P(u, .1, 1.5));
  }
  C.dust.commit();

  const rk = [[0, 1.4, 6.5], [.05, 1.0, 4.8], [.12, 2.0, 9]];
  C.rings.forEach((r, i) => {
    const [d0, dur, rad] = rk[i], p = P(u, d0, dur);
    r.material.uniforms.uR.value = .3 + rad * E.outCubic(p);
    r.material.uniforms.uA.value = p > 0 && p < 1 ? Math.pow(1 - p, 2.5) * (i === 1 ? .7 : .35) : 0;
    r.lookAt(cam.position);
  });
  C.flare.scale.set(18 * (1 + .5 * (1 - hitE)), .18 + .25 * hitE, 1); C.flare.material.opacity = hitE * .8;
  C.burst.scale.setScalar(1.5 + 5 * (1 - Math.exp(-u * 6))); C.burst.material.opacity = Math.exp(-u * 5.5) * .5;

  rays.uniforms.uLight.value.set(.5, .52);
  rays.uniforms.uStr.value = .45 * Math.exp(-u * 3); rays.uniforms.uThresh.value = 2.2; rays.uniforms.uDecay.value = .96; rays.uniforms.uLen.value = .6;
  bloom.strength = .32 + .7 * hitE; bloom.radius = .55; bloom.threshold = .9;

  if (PRO) {
    /* частицы: взрыв из точки схождения → полёт в форму логотипа → растворение в цельный логотип */
    C.parts.material.uniforms.uScale.value = sc;
    for (let i = 0; i < C.partSeed.length; i++) {
      const [tx, ty, d, spd, dl, sz, ph] = C.partSeed[i];
      const bd = spd * (1 - Math.exp(-2.6 * u)) / 2.6;
      const kk = E.inOutCubic(P(u, dl, .75));
      const sw = (1 - kk) * kk * 1.6;
      const x = lerp(d[0] * bd, tx, kk) + Math.sin(ph + u * 3) * sw * .5;
      const y = lerp(d[1] * bd, ty, kk) + Math.cos(ph * 1.3 + u * 2.6) * sw * .4;
      const z = lerp(d[2] * bd + .5, .03, kk) + Math.sin(ph * 2.1 + u * 2) * sw;
      C.parts.pos.set([x, y, z], i * 3);
      const land = kk >= 1 ? Math.exp(-(u - dl - .75) * 4) : 0;
      C.parts.size[i] = sz * (1 + land * 1.5);
      C.parts.alpha[i] = (.55 + .45 * Math.sin(u * 7 + ph)) * (1 - E.inQuad(P(u, 1.3, .8))) * (.7 + land);
    }
    C.parts.commit();
    const solidIn = params.get('dbg') ? 1 : E.inOutSine(P(u, 1.1, .7));
    C.capMat.opacity = 1; C.capMat.emissiveIntensity = (.18 + .25 * Math.exp(-Math.max(0, u - 1.3) * 2.5)) * solidIn;
    C.solid.visible = solidIn > .001;
    C.capMat.transparent = C.sideMat.transparent = solidIn < 1; C.capMat.opacity = C.sideMat.opacity = solidIn;
    const sw = u < 3 ? P(u, 1.2, 1.8) : P(u, 4.3, 1.6);
    C.sweep.position.set(lerp(-7, 7, E.inOutSine(sw)), 1.4, 1.6); C.sweep.intensity = 14 * Math.sin(Math.PI * sw) * solidIn;
    const cIn = kf(u, [[0, 0], [.25, 1], [3, .7], [6.5, 0]]);
    C.comets.forEach((c, k) => { c.tr.material.uniforms.uScale.value = sc; updComet(c, cometPathC(k), t, cIn, .0055, .35); if (c.light) c.light.intensity = cIn * 5; });
    const f = C.floor;
    f.uRefl.value = .06 + .06 * solidIn; f.uBlur.value = .005; f.uFadeR.value = 6; f.uStep.value = .9;
    f.uGrid.value = .05 + .04 * solidIn; f.uRunA.value = 0;
    f.uW.value.set(u * 9, (u - 1.25) * 7, -99, -99);
    rays.uniforms.uStr.value = .35 * Math.exp(-u * 3);
    bloom.strength = .26 + .7 * hitE + .12 * Math.exp(-Math.pow(u - 1.35, 2) * 6);
  }
  return [s, cam];
}

/* ================== HTML-надпись Sony Computer Entertainment ================== */
const sce = document.getElementById('sce'), sceShine = document.getElementById('sceShine'), sceLine = document.getElementById('sceLine');
let sceLetters = [];
function buildText() {
  const txt = 'Sony Computer Entertainment';
  for (const el of [sce, sceShine]) el.innerHTML = [...txt].map(ch => `<span>${ch === ' ' ? '&nbsp;' : ch}</span>`).join('');
  sceLetters = [...sce.children];
}
function renderText(t) {
  const n = sceLetters.length, vis = t > T.sce0 - .1 && t < T.sce1 + .2;
  for (const el of [sce, sceShine, sceLine]) el.style.visibility = vis ? 'visible' : 'hidden';
  if (!vis) return;
  const out = P(t, T.sce1 - .55, .55);
  const track = lerp(.36, .07, E.outExpo(P(t, T.sce0, 2.4))) + .12 * E.inCubic(out);
  for (const el of [sce, sceShine]) el.style.letterSpacing = track.toFixed(4) + 'em';
  sceLetters.forEach((sp, i) => {
    const d = Math.abs(i - (n - 1) / 2) / ((n - 1) / 2);
    const p = E.outCubic(P(t, T.sce0 + d * .45, .8));
    const o = p * (1 - E.inQuad(out));
    sp.style.opacity = o.toFixed(3);
    sp.style.filter = `blur(${((1 - p) * 12 + out * 10).toFixed(2)}px)`;
    sp.style.transform = `translateY(${((1 - p) * 14).toFixed(2)}px)`;
  });
  const shineX = lerp(-30, 130, E.inOutSine(P(t, T.sce0 + .7, 1.4)));
  sceShine.style.webkitMaskImage = sceShine.style.maskImage = `linear-gradient(100deg, transparent ${shineX - 12}%, #000 ${shineX}%, transparent ${shineX + 12}%)`;
  sceShine.style.opacity = (1 - out).toFixed(3);
  const lw = E.outExpo(P(t, T.sce0 + .25, 1.6));
  sceLine.style.width = (lw * 760).toFixed(1) + 'px';
  sceLine.style.opacity = (lw * .55 * (1 - out)).toFixed(3);
}

/* ================== кадр ================== */
function renderAt(t, frame = Math.round(t * 60)) {
  const ta = clamp(t, 0, DUR); t = ta - OFF;      // t — время оригинальной дорожки, ta — абсолютное
  const [scene, cam] = t < T.cut1 ? renderA(t, ta) : t < T.hit ? renderB(t, ta) : renderC(t, ta);
  renderPass.scene = scene; renderPass.camera = cam;
  renderText(t);
  const f = final.uniforms;
  f.uFlash.value = Math.max(pulse(t, T.cut1, .25, .09) * .95, pulse(t, T.hit + .03, .14, .08) * .7);
  f.uFade.value = Math.max(PRO ? 1 - P(ta, .05, .45) : 1 - P(t, T.start - .05, .5), E.inOutSine(P(ta, OUT0, 1.5)));
  f.uCA.value = .0022 + .01 * Math.max(pulse(t, T.cut1, .6, .2), pulse(t, T.hit, .3, .25)) + .004 * E.inCubic(P(t, 12.5, T.hit - 12.5)) * (t < T.hit ? 1 : 0);
  f.uSeed.value = frame % 997;
  composer.render();
  return true;
}

window.DURATION = DUR;
window.VERSION = PRO ? 'pro' : 'remake';
window.FPS = 60;
window.renderAt = renderAt;
window.ready = (async () => {
  await document.fonts.load('600 52px Jost');
  tex.cloud = [cloudTexture(3), cloudTexture(8), cloudTexture(13)];
  tex.glow = glowTexture(); tex.streak = streakTexture();
  tex.logo = await logoTexture();
  tex.logoPath = (await (await fetch('assets/ps2-logo.svg')).text()).match(/ d="([^"]+)"/)[1];
  buildA(); buildB(); buildC(); buildText();
  for (const tt of [1, 12, 15].map(x => x + OFF)) renderAt(tt);   // прогрев шейдеров
  renderAt(0);
  const info = renderer.getContext().getExtension('WEBGL_debug_renderer_info');
  window.GPU = info ? renderer.getContext().getParameter(info.UNMASKED_RENDERER_WEBGL) : 'unknown';
  return true;
})();

/* ---------- предпросмотр в браузере ---------- */
if (!window.__RENDER__) {
  window.ready.then(() => {
    const st = params.get('t');
    if (st != null) { renderAt(+st); return; }
    const audio = document.getElementById('audio'), hint = document.getElementById('hint');
    audio.src = PRO ? 'audio/soundtrack_pro.wav' : 'audio/soundtrack.wav';
    let t0 = performance.now(), playing = false;
    const loop = () => {
      const t = playing && !audio.paused ? audio.currentTime : ((performance.now() - t0) / 1000) % DUR;
      renderAt(t); requestAnimationFrame(loop);
    };
    hint.style.display = 'block';
    document.body.addEventListener('click', () => { hint.style.display = 'none'; audio.currentTime = 0; audio.play(); playing = true; });
    audio.addEventListener('ended', () => { audio.currentTime = 0; audio.play(); });
    loop();
  });
}
