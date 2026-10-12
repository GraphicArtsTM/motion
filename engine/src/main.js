// Движок «Паука Новограда»: сборка общего мира (город, персонажи, интерьеры, эффекты), постобработка,
// таймлайн и детерминированный renderAt(t). Серия подключается по ?ep=e01 из папки episodes/<ep>/
// (episode.js — шоты и настройки, timeline.json, dialogue.json, assets/ — звук и липсинк).
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { W, H, clamp } from './core.js';
import { makeCity, U, flashAt, makeBus, makeBike, makeBolt } from './city.js';
import { makeLab, makeKitchen, makeLair, makeShards, makeCab } from './interiors.js';
import { makeSchool } from './school.js';
import { makeZaton } from './zaton.js';
import { makeCharacter, makeSpider } from './rig.js';
import { makeWebs, makeSparks, makeRings, makeSilkSwirl } from './fx.js';
import { makeOverlay } from './overlay.js';
import { makeStreetLife } from './props.js';
import { makeCrowd } from './crowd.js';
import { dressLab, dressBridge, dressKitchen } from './dressing.js';
import { makeSpray } from './fx.js';
import { makeGradePass, makeAccumulator } from './post.js';
import { BokehPass } from 'three/addons/postprocessing/BokehPass.js';

const params = new URLSearchParams(location.search);
const RENDER = params.has('render');
// качество: q=high — для рендера на видеокарте (MSAA 4×, HDR-буфер, bloom в 1/2), по умолчанию — быстрый режим
const HIGH = params.get('q') === 'high';
const FPS = +(params.get('fps') || 30);

await Promise.all([
  ['Unbounded', 'engine/fonts/Unbounded-900.ttf', '900'], ['Unbounded', 'engine/fonts/Unbounded-700.ttf', '700'],
  ['Rubik', 'engine/fonts/Rubik-600.ttf', '600'], ['Rubik', 'engine/fonts/Rubik-800.ttf', '800'],
].map(async ([f, url, w]) => { const ff = new FontFace(f, `url(${url})`, { weight: w }); await ff.load(); document.fonts.add(ff); }));

/* ---------- какая серия ---------- */
const EPISODES = await fetch('episodes/index.json').then(r => r.json());
const EP = params.get('ep') || EPISODES.default;
const BASE = `episodes/${EP}/`;
const EPI = (await import(`../../episodes/${EP}/episode.js`)).default;
document.title = `Паук Новограда — ${EPI.title || EP}`;
const [timeline, dialogue, lipsync] = await Promise.all([
  fetch(BASE + 'timeline.json').then(r => r.json()),
  fetch(BASE + 'dialogue.json').then(r => r.json()),
  fetch(BASE + 'assets/lipsync.json').then(r => r.ok ? r.json() : null).catch(() => null),
]);
// грейд и motion blur — настройки серии (по сюжетному времени)
const gradeAt = EPI.gradeAt || (() => 'night');
const mblurAt = t => (EPI.mblur || []).some(([a, b]) => t >= a && t < b);

/* ---------- рендерер и постобработка ---------- */
const renderer = new THREE.WebGLRenderer({ antialias: false, preserveDrawingBuffer: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(1); renderer.setSize(W, H, false);
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.05;
document.getElementById('stage').insertBefore(renderer.domElement, document.getElementById('ov'));
const camera = new THREE.PerspectiveCamera(45, W / H, .05, 6000);
const rt = new THREE.WebGLRenderTarget(W, H, { type: HIGH || params.has('hdr') ? THREE.HalfFloatType : THREE.UnsignedByteType, samples: +(params.get('msaa') ?? (HIGH ? 4 : 0)) });
const composer = new EffectComposer(renderer, rt);
const renderPass = new RenderPass(new THREE.Scene(), camera);
const bloom = new UnrealBloomPass(new THREE.Vector2(W / +(params.get('bd') ?? (HIGH ? 2 : 4)), H / +(params.get('bd') ?? (HIGH ? 2 : 4))), .75, .55, .92);
composer.addPass(renderPass); if (!params.has('nobloom')) composer.addPass(bloom);
// глубина резкости на крупных планах (только на видеокарте — это ещё один проход сцены)
const bokeh = HIGH ? new BokehPass(new THREE.Scene(), camera, { focus: 3, aperture: .0006, maxblur: .006 }) : null;
if (bokeh) { bokeh.enabled = false; composer.addPass(bokeh); }
composer.addPass(new OutputPass());
const grade = makeGradePass(); composer.addPass(grade);
const accum = HIGH ? makeAccumulator(renderer, W, H) : null;
// мягкие тени (на видеокарте)
if (HIGH) { renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap; }
const overlay = makeOverlay(document.getElementById('ov'));

/* ---------- мир ---------- */
const city = makeCity();
const lab = makeLab(city.tower);
const life = makeStreetLife(city.scene);
const crowd = makeCrowd(city.scene, life);
const kitchen = makeKitchen();
const labD = dressLab(lab), bridgeD = dressBridge(city.scene), kitchenD = dressKitchen(kitchen);
const lair = makeLair();
const cab = makeCab();
// лицей «Новоград» (коридор, класс, столовая) и двор Старого Затона с фасадом лицея — серия 2 и дальше
const school = makeSchool();
const zaton = makeZaton();
const ch = {
  timur: makeCharacter('timur'), ded: makeCharacter('ded'), vera: makeCharacter('vera'),
  kronov: makeCharacter('kronov'), shadow: makeCharacter('shadow'),
  // лицей (серия 2): друзья, задира, учительница, ODILMAN и школьники s0…s9 (s8, s9 — дружки Азима)
  marjon: makeCharacter('marjon'), diyor: makeCharacter('diyor'), azim: makeCharacter('azim'), teacher: makeCharacter('teacher'), odilman: makeCharacter('odilman'),
  ...Object.fromEntries(Array.from({ length: 10 }, (_, i) => ['s' + i, makeCharacter('student', { variant: i })])),
};
// контактные тени под персонажами
const blobTex = (() => { const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
  const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64); gr.addColorStop(0, 'rgba(0,0,0,.6)'); gr.addColorStop(1, 'rgba(0,0,0,0)'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
  return new THREE.CanvasTexture(c); })();
for (const c of Object.values(ch)) {
  const b = new THREE.Mesh(new THREE.PlaneGeometry(1.1 * c.d.k, 1.1 * c.d.k), new THREE.MeshBasicMaterial({ map: blobTex, transparent: true, depthWrite: false }));
  b.rotation.x = -Math.PI / 2; b.position.y = .015; b.renderOrder = 2; c.root.add(b); c.blob = b;
}
const props = {
  bike: makeBike(), bus: makeBus(), spider: makeSpider({ scale: 3.2, gold: true }),
  webs: makeWebs(city.scene, 40), sparks: makeSparks(city.scene, 500), sparks2: makeSparks(city.scene, 300, 0x9ff8ff),
  rings: makeRings(city.scene, 5), spray: makeSpray(city.scene), swirl: makeSilkSwirl(city.scene), shards: makeShards(city.scene, 220, 21),
};
const busPivot = new THREE.Group(); busPivot.add(props.bus); props.bus.position.z = -1; props.busPivot = busPivot;
city.scene.add(busPivot, props.bike, props.spider);

// молнии: заранее собранные разряды
const bolts = timeline.strikes.map((s, i) => {
  const b = makeBolt(new THREE.Vector3(...s.from), new THREE.Vector3(...s.to), 100 + i, { width: s.w ?? 1.2, branches: s.br ?? 5, scale: s.sc ?? 1, jag: s.jag ?? 1 });
  b.visible = false; city.bolts.add(b); return { ...s, mesh: b };
});

if (HIGH) {
  city.key.castShadow = true; city.key.shadow.mapSize.set(2048, 2048);
  Object.assign(city.key.shadow.camera, { left: -26, right: 26, top: 26, bottom: -26, near: 10, far: 300 }); city.key.shadow.bias = -.0006; city.key.shadow.normalBias = .02;
  const lampK = kitchen.scene.children.find(o => o.isPointLight && o.intensity > 2);
  if (lampK) { lampK.castShadow = true; lampK.shadow.mapSize.set(1024, 1024); lampK.shadow.bias = -.002; }
  for (const S of [school.corridor, school.classroom, school.canteen, zaton]) if (S.sun) {
    S.sun.castShadow = true; S.sun.shadow.mapSize.set(2048, 2048); S.sun.shadow.bias = -.0006; S.sun.shadow.normalBias = .02;
    Object.assign(S.sun.shadow.camera, { left: -14, right: 14, top: 14, bottom: -14, near: 1, far: 80 });
  }
  for (const sc of [city.scene, kitchen.scene, lair.scene, cab.scene, school.corridor.scene, school.classroom.scene, school.canteen.scene, zaton.scene]) sc.traverse(o => {
    if (!o.isMesh || o.isInstancedMesh) return;
    const m = o.material;
    if (m?.isMeshToonMaterial) { o.castShadow = true; o.receiveShadow = true; }
  });
  for (const c of Object.values(ch)) c.root.traverse(o => { if (o.isMesh && o.material?.isMeshToonMaterial) { o.castShadow = true; o.receiveShadow = true; } });
}

/* ---------- реплики и липсинк ---------- */
/* карта времени: сюжетное время s (в нём поставлены шоты) → экранное T (растянуто под живую озвучку) */
const STR = timeline.stretch || [];
const toFilm = s => s + STR.reduce((a, [s0, s1, e]) => a + e * clamp((s - s0) / (s1 - s0)), 0);
function toStory(T) {
  let lo = 0, hi = timeline.story_duration ?? T;
  for (let i = 0; i < 50; i++) { const m = (lo + hi) / 2; if (toFilm(m) < T) lo = m; else hi = m; }
  return (lo + hi) / 2;
}
const durs = lipsync?.durations || {};
const lines = dialogue.lines.map(l => ({ ...l, ft: toFilm(l.t), d: durs[l.id] ?? (l.text.length * .07 + .4), env: lipsync?.env?.[l.id], shape: lipsync?.shape?.[l.id], fric: lipsync?.fric?.[l.id] })).sort((a, b) => a.t - b.t);
lines.forEach((l, i) => { const nx = lines[i + 1]; l.end = Math.min(l.ft + l.d + .35, nx ? nx.ft - .05 : 1e9); });
let filmT = 0;
/* открытие рта по огибающей голоса; t — сюжетное время шота, сравниваем в экранном */
function mouthOf(who, t) {
  const T = filmT;
  for (const l of lines) {
    if (l.who !== who) continue;
    const dt = T - l.ft;
    if (dt < 0 || dt > l.d) continue;
    if (l.env) { const i = Math.floor(dt * lipsync.fps); return l.env[Math.min(i, l.env.length - 1)] || 0; }
    return .5 + .5 * Math.sin(dt * 22) * Math.sin(dt * 7.3);
  }
  return 0;
}

/* шипящие/фрикативные звуки в данный момент реплики */
function fricOf(who) {
  for (const l of lines) {
    if (l.who !== who) continue;
    const dt = filmT - l.ft;
    if (dt < 0 || dt > l.d || !l.fric) continue;
    return l.fric[Math.min(Math.floor(dt * lipsync.fps), l.fric.length - 1)] || 0;
  }
  return 0;
}
/* форма рта: 0 — широкая («и», «э»), 1 — округлая («о», «у») */
function shapeOf(who) {
  for (const l of lines) {
    if (l.who !== who) continue;
    const dt = filmT - l.ft;
    if (dt < 0 || dt > l.d || !l.shape) continue;
    return l.shape[Math.min(Math.floor(dt * lipsync.fps), l.shape.length - 1)] || 0;
  }
  return 0;
}
const ctx = { THREE, city, lab, kitchen, lair, cab, school, zaton, ch, props, camera, overlay, U, bolts, lines, mouthOf, shapeOf, fricOf, renderer, timeline, labD, kitchenD, bridgeD, crowd, life, EP };
const shots = EPI.buildShots(ctx);
const DURATION = timeline.duration;          // сама серия
const INTRO = timeline.intro || 0;            // заставка студии перед серией

/* ---------- кадр ---------- */
function resetFrame() {
  for (const c of Object.values(ch)) { c.root.visible = false; c.root.rotation.set(0, 0, 0); c.root.quaternion.identity(); c.root.scale.setScalar(1); }
  for (const k of ['bike', 'spider', 'busPivot']) props[k].visible = false;
  props.webs.reset(); props.rings.reset(); props.spray.hide(); ch.vera.tablet.visible = false; props.sparks.hide(); props.sparks2.hide(); props.swirl.update(new THREE.Vector3(), 0, 0);
  props.shards.update(-1, [new THREE.Vector3()]);
  lab.shards.update(-1, [new THREE.Vector3()]);
  bolts.forEach(b => b.mesh.visible = false);
  U.sense.value = 0; U.fogDensity.value = .0021; U.tint.value.setRGB(1, 1, 1);
  city.rain.visible = true; city.rain.userData.mat.uniforms.alpha.value = .7;
  city.sky.userData.mat.uniforms.dawn.value = 0;
  city.fill.intensity = 0; lab.lights.forEach(l => l.intensity = 0);
  city.key.intensity = 1.4; city.rim.intensity = 1.2; city.hemi.intensity = 1.1;
  ch.timur.setSuit(false); city.tower.userData.tip.visible = true;
  ch.timur.mats.hand.emissive.setRGB(0, 0, 0);
  ch.kronov.stolen.visible = false;
  camera.up.set(0, 1, 0);
  bloom.strength = .75;
  ctx.frameReset?.(ctx.t);
}

let inset = null;
/* логика кадра: персонажи, камера, эффекты на момент T (без отрисовки) */
function frameLogic(T) {
  filmT = T;
  const t = toStory(T);
  ctx.t = t;
  resetFrame();
  const shot = shots.find(s => t >= s.t0 && t < s.t1) || shots[shots.length - 1];
  const lt = t - shot.t0;
  const flash = flashAt(t, timeline.strikes.filter(s => !shot.noFlash));
  U.flash.value = flash * (shot.flashK ?? 1);
  U.time.value = t;
  U.rainTime.value = t;
  city.hemi.intensity = 1.1 + flash * 2.2;
  ctx.t = t; ctx.inset = null; ctx.post = [];
  ctx.camFill = null; ctx.panels = null; ctx.rim = null; ctx.dof = null; ctx.grade = null;
  const scene = shot.run(lt, t, ctx) || city.scene;
  if (ctx.rim) {
    const tg = ctx.rim.target, d = tg.clone().sub(camera.position).setY(0).normalize();
    city.rim.position.copy(tg).addScaledVector(d, 40).add(new THREE.Vector3(0, 18, 0)); city.rim.target.position.copy(tg);
    city.rim.color.set(ctx.rim.color); city.rim.intensity = ctx.rim.k;
  } else city.rim.color.set(0xff9a4a);
  // какие «живые» части мира включены в этот момент — решает серия (episode.world)
  const wo = EPI.world?.(t, scene, ctx) || {};
  life.update(t, { police: !!wo.police });
  crowd.update(t, !!wo.crowd && scene === city.scene);
  labD.update(t, { alarm: !!wo.alarm, inLab: scene === city.scene && !city.rain.visible });
  bridgeD.update(t, !!wo.bridge, camera);
  kitchenD.update(t, { inKitchen: scene === kitchen.scene, ...(wo.kitchen || {}) });
  zaton.update?.(t, scene === zaton.scene);
  const up = new THREE.Vector3();
  for (const c of Object.values(ch)) { up.set(0, 1, 0).applyQuaternion(c.root.getWorldQuaternion(new THREE.Quaternion())); c.blob.visible = c.root.visible && up.y > .95 && !ctx.noBlob?.includes(c); }
  ctx.noBlob = null;
  if (ctx.camFill) { city.fill.position.copy(camera.position).add(new THREE.Vector3(0, 3.5, 0)); city.fill.intensity = ctx.camFill[0] * .8; city.fill.color.set(ctx.camFill[1]); city.fill.distance = 60; city.fill.decay = 1; }
  else { city.fill.distance = 40; city.fill.decay = 1.6; }
  // молнии, видимые в этом кадре
  if (scene === city.scene) for (const b of bolts) { const d = t - b.t; b.mesh.visible = !shot.hideBolts && d > -.02 && d < (b.dur ?? .38) && (Math.sin(d * 90) > -.6 || d < .08); }
  if (ctx.bloom != null) { bloom.strength = ctx.bloom; ctx.bloom = null; }
  renderPass.scene = scene;
  // тени: солнце-«луна» следит за точкой, куда смотрит камера
  if (HIGH) {
    const focus = camera.getWorldDirection(new THREE.Vector3()).multiplyScalar(12).add(camera.position);
    city.key.position.copy(focus).add(new THREE.Vector3(-60, 120, 80).normalize().multiplyScalar(120)); city.key.target.position.copy(focus);
    scene.userData.aim?.(focus);
  }
  if (bokeh) {
    bokeh.enabled = !!ctx.dof; bokeh.scene = scene;
    if (ctx.dof) { bokeh.uniforms.focus.value = ctx.dof.focus; bokeh.uniforms.aperture.value = ctx.dof.aperture ?? .0006; bokeh.uniforms.maxblur.value = ctx.dof.maxblur ?? .007; }
  }
  grade.setGrade(ctx.grade || gradeAt(t), t);
  return { t, shot, scene };
}

function renderAt(T) {
  T = clamp(T, 0, INTRO + DURATION - 1e-4);
  if (T < INTRO) {             // заставка студии GraphicArts Animation — целиком 2D-слой
    renderer.setClearColor(0x000000, 1); renderer.clear();
    overlay.clear(); overlay.studio(T, INTRO); return;
  }
  T -= INTRO;
  const t0 = toStory(T);
  // motion blur: на видеокарте в экшн-сценах усредняем подкадры внутри «затвора 180°»
  let N = HIGH && !params.has('nomblur') && mblurAt(t0) ? +(params.get('mbs') || 5) : 1;
  const shutter = .5 / FPS;
  if (N > 1) {
    // быстрая проводка камеры: подкадров столько, чтобы шаг между ними был ≤ 3 px — иначе вместо смаза «лесенка»
    const probe = s => { frameLogic(clamp(T + s * shutter, 0, DURATION - 1e-4)); return { d: camera.getWorldDirection(new THREE.Vector3()), p: camera.position.clone(), fov: camera.fov }; };
    const a = probe(-.5), b = probe(.5);
    const px = (a.d.angleTo(b.d) + a.p.distanceTo(b.p) * .02) / (a.fov * Math.PI / 180) * H;
    N = Math.min(24, Math.max(N, Math.ceil(px / 3)));
  }
  if (N > 1) {
    accum.clear(); composer.renderToScreen = false;
    for (let i = 0; i < N; i++) {
      frameLogic(clamp(T + (i / (N - 1) - .5) * shutter, 0, DURATION - 1e-4));
      composer.render();
      accum.add(composer.readBuffer.texture, 1 / N);
    }
    composer.renderToScreen = true;
    accum.present();
  }
  const { shot } = frameLogic(T);
  if (N === 1) composer.render();
  // вставки и комикс-панели: вторая камера поверх кадра
  for (const p of [ctx.inset, ...(ctx.panels || [])]) {
    if (!p) continue;
    const { x, y, w, h, scene: s2, cam } = p;
    renderer.setScissorTest(true);
    renderer.setScissor(x, H - y - h, w, h); renderer.setViewport(x, H - y - h, w, h);
    renderer.autoClear = false; renderer.clear(true, true, false);
    cam.aspect = w / h; cam.updateProjectionMatrix();
    renderer.render(s2, cam);
    renderer.autoClear = true; renderer.setScissorTest(false); renderer.setViewport(0, 0, W, H);
  }
  // 2D-слой
  overlay.clear();
  for (const f of ctx.post) f(overlay);
  if (!shot.noSubs) for (const l of lines) {
    const dt = T - l.ft;
    if (dt > -.05 && T < l.end) overlay.subtitle(l.text, Math.min(clamp((dt + .05) / .12), clamp((l.end - T) / .12)), l.who, l.who === 'narrator');
  }
  overlay.vignette(.3);
}

window.renderAt = renderAt;
window.toFilm = s => toFilm(s) + INTRO;   // сюжетное время → время ролика (с заставкой)
window.bench = (t, n = 5) => { const a = performance.now(); for (let i = 0; i < n; i++) { renderAt(t + i * .03); renderer.getContext().finish(); } return (performance.now() - a) / n; };
window.DURATION = INTRO + DURATION;
window.EPISODE = EP;
window.ready = true;

/* ---------- предпросмотр в браузере ---------- */
if (!RENDER) {
  const TOTAL = INTRO + DURATION;
  const ui = document.getElementById('ui'); ui.hidden = false;
  const audio = new Audio(BASE + 'assets/soundtrack.m4a');
  const bar = document.getElementById('bar'), tl = document.getElementById('tl');
  let playing = false, t0 = 0, start = 0;
  const now = () => playing ? (audio.readyState > 2 && !audio.paused ? audio.currentTime : start + (performance.now() - t0) / 1000) : start;
  const seek = t => { start = clamp(t, 0, TOTAL); t0 = performance.now(); try { audio.currentTime = start; } catch (e) { } if (!playing) renderAt(start); };
  const toggle = () => { playing = !playing; start = now(); t0 = performance.now(); if (playing) { audio.currentTime = start; audio.play().catch(() => { }); } else { start = audio.currentTime || start; audio.pause(); } ui.classList.toggle('playing', playing); };
  document.getElementById('play').onclick = toggle;
  addEventListener('keydown', e => { if (e.code === 'Space') { e.preventDefault(); toggle(); } if (e.code === 'ArrowRight') seek(now() + 5); if (e.code === 'ArrowLeft') seek(now() - 5); });
  bar.oninput = () => seek(+bar.value / 1000 * TOTAL);
  const loop = () => {
    const t = now();
    if (playing) { renderAt(t); if (t >= TOTAL) { playing = false; ui.classList.remove('playing'); } }
    bar.value = t / TOTAL * 1000;
    tl.textContent = `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')} / ${Math.floor(TOTAL / 60)}:${String(Math.floor(TOTAL % 60)).padStart(2, '0')}`;
    requestAnimationFrame(loop);
  };
  seek(+(params.get('t') || 0));
  loop();
}
