// Лицей «Новоград» (серия 2): коридор со шкафчиками, класс физики, столовая. Три отдельные сцены с дневным
// светом из окон. Координаты: в каждой сцене пол на y = 0; подробности — в комментариях у каждой функции.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon, glow, mesh, rng } from './core.js';

const tex = (w, h, draw, rep) => {
  const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  if (rep) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(...rep); }
  return t;
};
const rb = (x, y, z, r = .03) => new RoundedBoxGeometry(x, y, z, 2, Math.min(r, x / 2.1, y / 2.1, z / 2.1));
const plane = (w, h, map, o = {}) => new THREE.Mesh(new THREE.PlaneGeometry(w, h), o.basic ? new THREE.MeshBasicMaterial({ map, color: o.color ?? 0xffffff, transparent: !!o.transparent }) : toon(0xffffff, { map }));

/* солнце следует за точкой, куда смотрит камера (тени на видеокарте) */
const aimable = (scene, sun) => { const off = sun.position.clone().sub(sun.target.position); scene.userData.aim = f => { sun.position.copy(f).add(off); sun.target.position.copy(f); }; };

/* вид из окна: небо, деревья, дома — днём (k = 1) */
function windowView(seed = 1) {
  return tex(512, 384, (g, w, h) => {
    const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#8fc4f2'); gr.addColorStop(.7, '#dcefff'); gr.addColorStop(1, '#f6f2e4');
    g.fillStyle = gr; g.fillRect(0, 0, w, h);
    const r = rng(seed);
    for (let i = 0; i < 4; i++) { g.fillStyle = 'rgba(255,255,255,.85)'; const x = r() * w, y = 30 + r() * 90; for (let j = 0; j < 5; j++) { g.beginPath(); g.arc(x + j * 22, y + Math.sin(j) * 8, 22, 0, 7); g.fill(); } }
    for (let i = 0; i < 9; i++) { g.fillStyle = ['#b9c6d6', '#a8b8cc', '#c8d0da'][i % 3]; const bw = 40 + r() * 60, bh = 80 + r() * 140; g.fillRect(i * 60 - 10, h - bh - 60, bw, bh + 60); }
    for (let i = 0; i < 7; i++) { g.fillStyle = ['#e0952e', '#c9b23a', '#6f9b45', '#d06a2a'][i % 4]; g.beginPath(); g.arc(i * 80 + 20, h - 50, 46 + r() * 20, 0, 7); g.fill(); }
    g.fillStyle = '#7a8a6a'; g.fillRect(0, h - 20, w, 20);
  });
}

/* плакат: заголовок + картинка-силуэт */
function poster(title, sub, bg, fg, kind = 0) {
  return tex(256, 360, (g, w, h) => {
    g.fillStyle = bg; g.fillRect(0, 0, w, h);
    g.fillStyle = fg; g.font = '900 34px Unbounded'; g.textAlign = 'center';
    title.split('\n').forEach((l, i) => g.fillText(l, w / 2, 56 + i * 40));
    g.font = '600 20px Rubik'; sub.split('\n').forEach((l, i) => g.fillText(l, w / 2, h - 40 + i * 24 - (sub.split('\n').length - 1) * 24));
    g.globalAlpha = .9;
    if (kind === 0) { g.beginPath(); g.arc(w / 2, 200, 60, 0, 7); g.fill(); g.fillStyle = bg; g.beginPath(); g.arc(w / 2 - 20, 190, 14, 0, 7); g.arc(w / 2 + 20, 190, 14, 0, 7); g.fill(); }  // мяч
    if (kind === 1) { for (let i = 0; i < 5; i++) { g.beginPath(); g.moveTo(w / 2, 140); g.lineTo(w / 2 + Math.cos(i * 1.26) * 80, 210 + Math.sin(i * 1.26) * 70); g.lineWidth = 6; g.strokeStyle = fg; g.stroke(); } }      // атом
    if (kind === 2) { g.fillRect(70, 150, 116, 110); g.fillStyle = bg; g.fillRect(84, 166, 88, 60); }                                                                                                 // книга
  });
}

/* ---------- коридор: x −20…20, шкафчики у северной стены (z = −2.4), окна у южной (z = +2.4), потолок 3.3 ---------- */
function makeCorridor() {
  const scene = new THREE.Scene(); scene.background = new THREE.Color(0xdfe6ee);
  const S = { scene };
  const floorT = tex(256, 256, (g, w, h) => {
    for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) { g.fillStyle = (x + y) % 2 ? '#b9a98a' : '#d6c9ae'; g.fillRect(x * 64, y * 64, 64, 64); }
    g.strokeStyle = 'rgba(0,0,0,.12)'; g.lineWidth = 2; for (let i = 0; i <= 4; i++) { g.beginPath(); g.moveTo(i * 64, 0); g.lineTo(i * 64, h); g.stroke(); g.beginPath(); g.moveTo(0, i * 64); g.lineTo(w, i * 64); g.stroke(); }
  }, [40, 5]);
  const floor = mesh(new THREE.PlaneGeometry(44, 5), toon(0xffffff, { map: floorT }), { rot: [-Math.PI / 2, 0, 0], outline: false, parent: scene });
  S.floor = floor;
  // блик на мокром полу (рядом с табличкой)
  const wet = S.wet = mesh(new THREE.CircleGeometry(1.1, 24), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: .16, depthWrite: false }), { pos: [1.2, .005, .4], rot: [-Math.PI / 2, 0, 0], scale: [1.6, .7, 1], outline: false, parent: scene });
  const wallM = toon(0xf1e7d2), trimM = toon(0x2f6b8a);
  mesh(new THREE.BoxGeometry(44, 3.3, .2), wallM, { pos: [0, 1.65, -2.6], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(44, .9, .22), trimM, { pos: [0, .45, 2.6], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(44, .5, .22), wallM, { pos: [0, 3.05, 2.6], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(44, .12, .26), toon(0xd8cbb0), { pos: [0, .95, 2.56], outline: false, parent: scene });
  // окна южной стены
  const view = windowView(3);
  for (let x = -18; x <= 18; x += 4.5) {
    const v = plane(3.6, 1.8, view, { basic: true, color: 0xffffff }); v.position.set(x, 1.95, 2.69); v.rotation.y = Math.PI; scene.add(v);
    for (const [w, h, px, py] of [[3.8, .12, 0, 2.88], [3.8, .12, 0, 1.02], [.12, 1.9, -1.85, 1.95], [.12, 1.9, 1.85, 1.95], [.08, 1.8, 0, 1.95]]) mesh(new THREE.BoxGeometry(w, h, .12), toon(0xf4f4f0), { pos: [x + px, py, 2.6], outline: .01, parent: scene });
    mesh(new THREE.BoxGeometry(2.4, .5, .12), toon(0xe8e4dc), { pos: [x, .55, 2.45], outline: .01, parent: scene });       // батарея
    for (let i = 0; i < 10; i++) mesh(new THREE.BoxGeometry(.05, .46, .16), toon(0xd8d4cc), { pos: [x - 1.1 + i * .24, .55, 2.42], outline: false, parent: scene });
  }
  // солнечные «пятна» от окон на полу
  const sunM = new THREE.MeshBasicMaterial({ color: 0xfff1c8, transparent: true, opacity: .22, depthWrite: false, blending: THREE.AdditiveBlending });
  for (let x = -18; x <= 18; x += 4.5) mesh(new THREE.PlaneGeometry(3.2, 1.6), sunM, { pos: [x - .6, .006, 1.2], rot: [-Math.PI / 2, 0, .25], outline: false, parent: scene });
  // шкафчики (северная стена): одна полоса с текстурой дверец + корпус
  const lockT = tex(1024, 256, (g, w, h) => {
    for (let i = 0; i < 16; i++) {
      const x = i * 64, col = ['#2f6fb0', '#2f6fb0', '#2a63a0', '#c8402c'][i % 7 === 3 ? 3 : i % 3];
      g.fillStyle = col; g.fillRect(x + 1, 0, 62, h); g.strokeStyle = 'rgba(0,0,0,.4)'; g.lineWidth = 2; g.strokeRect(x + 2, 2, 60, h - 4);
      g.fillStyle = 'rgba(0,0,0,.35)'; for (let v = 0; v < 4; v++) g.fillRect(x + 16, 18 + v * 9, 32, 4);                // вентиляция
      g.fillStyle = '#c9ced6'; g.fillRect(x + 48, 120, 6, 26);                                                            // ручка
      g.fillStyle = '#f2f2ee'; g.font = '700 14px Rubik'; g.fillText(String(100 + i), x + 18, 240);
    }
  }, [4, 1]);
  const lockers = new THREE.Group(); scene.add(lockers); S.lockers = lockers;
  mesh(new THREE.BoxGeometry(32, 1.95, .5), toon(0x274f7a), { pos: [0, .975 + .08, -2.25], outline: .02, parent: lockers });
  const front = plane(32, 1.95, lockT); front.position.set(0, 1.055, -1.995); lockers.add(front);
  mesh(new THREE.BoxGeometry(32, .08, .55), toon(0x1c2a3a), { pos: [0, .04, -2.25], outline: false, parent: lockers });
  // открытая дверца шкафчика Маржон (x = 6.0) и Диёра (x = −1.5) — двигаются режиссурой
  S.lockerDoor = (x, col = 0x2f6fb0) => {
    const h = new THREE.Group(); h.position.set(x - .25, .08, -1.99); scene.add(h);
    mesh(new THREE.BoxGeometry(.5, 1.9, .03), toon(col), { pos: [.25, .95, 0], outline: .01, parent: h });
    mesh(new THREE.BoxGeometry(.04, .3, .04), toon(0xc9ced6), { pos: [.45, .95, .03], outline: false, parent: h });
    return h;
  };
  S.doorM = S.lockerDoor(6.25, 0xc8402c); S.doorD = S.lockerDoor(-1.25);
  // вмятина от кулака Азима (видимость — режиссура)
  S.dent = mesh(new THREE.CircleGeometry(.16, 9), new THREE.MeshBasicMaterial({ color: 0x0c1a2a, transparent: true, opacity: .55 }), { pos: [3.1, 1.45, -1.985], outline: false, parent: scene });
  S.dent.visible = false;
  // над шкафчиками: плакаты, часы, доска объявлений
  const P = [poster('ФУТБОЛ', 'Сборная лицея\nфинал в субботу', '#1d4fa0', '#ffffff', 0), poster('ОЛИМПИАДА\nПО ФИЗИКЕ', 'запись в 214', '#f2c94c', '#2a2a2a', 1), poster('ШКОЛЬНЫЙ\nБАЛ', 'пятница 19:00', '#c8402c', '#ffffff', 2), poster('КЛУБ\nКОМИКСОВ', 'рисуем героев\nкаждую среду', '#2f6b4f', '#ffffff', 2)];
  [[-13, 0], [-5.5, 1], [9.5, 2], [15.5, 3]].forEach(([x, i]) => { const p = plane(.8, 1.12, P[i]); p.position.set(x, 2.55, -2.49); scene.add(p); });
  const board = new THREE.Group(); board.position.set(-9, 2.55, -2.48); scene.add(board);
  mesh(new THREE.BoxGeometry(2.2, 1.0, .05), toon(0xb08a5a), { outline: .01, parent: board });
  for (let i = 0; i < 7; i++) mesh(new THREE.BoxGeometry(.32, .38, .01), toon([0xfff7a0, 0xffffff, 0xa0e0ff, 0xffc0d0][i % 4]), { pos: [-.85 + i * .28, (i % 2 ? .18 : -.15), .03], rot: [0, 0, (i % 3 - 1) * .1], outline: false, parent: board });
  const clockT = tex(128, 128, (g) => { g.fillStyle = '#fff'; g.beginPath(); g.arc(64, 64, 60, 0, 7); g.fill(); g.strokeStyle = '#222'; g.lineWidth = 5; g.stroke(); g.lineWidth = 6; g.beginPath(); g.moveTo(64, 64); g.lineTo(64, 24); g.moveTo(64, 64); g.lineTo(92, 74); g.stroke(); });
  const clock = plane(.45, .45, clockT, { basic: true }); clock.position.set(2.0, 2.75, -2.49); scene.add(clock);
  // двери классов между шкафчиками и в торцах
  for (const x of [-17.5, 17.5]) {
    const d = new THREE.Group(); d.position.set(x, 0, -2.45); scene.add(d);
    mesh(new THREE.BoxGeometry(1.3, 2.3, .1), toon(0x9a6a3a), { pos: [0, 1.15, 0], outline: .015, parent: d });
    mesh(new THREE.BoxGeometry(.5, .7, .02), toon(0xbfe0f0), { pos: [0, 1.7, .06], outline: false, parent: d });
    const lbl = tex(128, 48, (g) => { g.fillStyle = '#fff'; g.fillRect(0, 0, 128, 48); g.fillStyle = '#222'; g.font = '800 30px Rubik'; g.fillText(x < 0 ? '10-А' : '11-Б', 24, 36); });
    const pl = plane(.4, .15, lbl, { basic: true }); pl.position.set(0, 2.45, .06); d.add(pl);
  }
  // торцы коридора: стена и двустворчатая дверь со стеклом
  for (const sx of [-1, 1]) {
    mesh(new THREE.BoxGeometry(.2, 3.4, 5.4), wallM, { pos: [sx * 21.6, 1.7, 0], outline: false, parent: scene });
    for (const dz of [-.62, .62]) {
      mesh(new THREE.BoxGeometry(.08, 2.3, 1.2), toon(0x2f6b8a), { pos: [sx * 21.48, 1.15, dz], outline: .01, parent: scene });
      mesh(new THREE.BoxGeometry(.02, 1.1, .8), new THREE.MeshBasicMaterial({ color: 0xcfe8ff }), { pos: [sx * 21.43, 1.6, dz], outline: false, parent: scene });
    }
    const ex = tex(128, 48, (g) => { g.fillStyle = '#1f9a4a'; g.fillRect(0, 0, 128, 48); g.fillStyle = '#fff'; g.font = '800 28px Rubik'; g.fillText('ВЫХОД', 14, 34); });
    const e = plane(.6, .22, ex, { basic: true }); e.position.set(sx * 21.45, 2.55, 0); e.rotation.y = -sx * Math.PI / 2; scene.add(e);
  }
  // потолок с лампами
  mesh(new THREE.BoxGeometry(44, .1, 5.4), toon(0xf4f2ec), { pos: [0, 3.35, 0], outline: false, parent: scene });
  for (let x = -18; x <= 18; x += 4) mesh(new THREE.BoxGeometry(1.4, .05, .4), glow(0xfff8e8, 1.6), { pos: [x, 3.28, 0], outline: false, parent: scene });
  // табличка «Осторожно: мокрый пол»
  const sign = new THREE.Group(); sign.position.set(1.8, 0, .9); sign.rotation.y = -.5; scene.add(sign); S.wetSign = sign;
  const signT = tex(128, 192, (g) => { g.fillStyle = '#ffd21a'; g.fillRect(0, 0, 128, 192); g.fillStyle = '#1a1a1a'; g.font = '800 20px Rubik'; g.textAlign = 'center'; g.fillText('ОСТОРОЖНО', 64, 40); g.fillText('МОКРЫЙ', 64, 140); g.fillText('ПОЛ', 64, 166);
    g.beginPath(); g.moveTo(64, 56); g.lineTo(98, 118); g.lineTo(30, 118); g.closePath(); g.lineWidth = 6; g.stroke(); g.fillText('!', 64, 108); });
  for (const sd of [1, -1]) { const pnl = mesh(new THREE.BoxGeometry(.42, .62, .02), toon(0xffffff, { map: signT }), { pos: [0, .31, sd * .085], rot: [-sd * .27, sd > 0 ? 0 : Math.PI, 0], outline: .008, parent: sign }); }
  // фонтанчик и урна
  mesh(rb(.5, .9, .4), toon(0xc9ced6), { pos: [12.6, .45, -1.75], outline: .01, parent: scene });
  mesh(new THREE.CylinderGeometry(.22, .18, .6, 16), toon(0x3a6a4a), { pos: [-3.4, .3, 2.1], outline: .01, parent: scene });
  // свет: день из окон + потолочные лампы
  scene.add(new THREE.HemisphereLight(0xeaf2ff, 0x8a7a60, 1.0));
  const sun = new THREE.DirectionalLight(0xfff0d6, 1.6); sun.position.set(-6, 9, 14); sun.target.position.set(0, 0, 0); scene.add(sun, sun.target); S.sun = sun; aimable(scene, sun);
  scene.fog = new THREE.Fog(0xdfe6ee, 26, 60);
  return S;
}

/* ---------- класс физики: x −5…5 (окна на x = +5), z −4.5 (доска)…+4.5, потолок 3.2 ---------- */
function makeClassroom() {
  const scene = new THREE.Scene(); scene.background = new THREE.Color(0xdfe6ee);
  const S = { scene, desks: [] };
  const floorT = tex(256, 256, (g, w, h) => { for (let i = 0; i < 8; i++) { g.fillStyle = i % 2 ? '#b98a5a' : '#c4956a'; g.fillRect(0, i * 32, w, 32); g.fillStyle = 'rgba(0,0,0,.1)'; g.fillRect(((i * 97) % 200), i * 32, 3, 32); } }, [5, 5]);
  mesh(new THREE.PlaneGeometry(10.4, 9.4), toon(0xffffff, { map: floorT }), { rot: [-Math.PI / 2, 0, 0], outline: false, parent: scene });
  const wallM = toon(0xe7eef0), lowM = toon(0x6a9aa8);
  mesh(new THREE.BoxGeometry(10.4, 3.3, .2), wallM, { pos: [0, 1.65, -4.7], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(10.4, 3.3, .2), wallM, { pos: [0, 1.65, 4.7], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(.2, 3.3, 9.4), wallM, { pos: [-5.2, 1.65, 0], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(.2, 1.0, 9.4), lowM, { pos: [-5.1, .5, 0], outline: false, parent: scene });
  // окна (восточная стена x = +5)
  const view = windowView(7);
  mesh(new THREE.BoxGeometry(.2, .9, 9.4), lowM, { pos: [5.2, .45, 0], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(.2, .5, 9.4), wallM, { pos: [5.2, 3.05, 0], outline: false, parent: scene });
  for (const z of [-3, 0, 3]) {
    const v = plane(2.6, 1.8, view, { basic: true }); v.position.set(5.28, 1.85, z); v.rotation.y = -Math.PI / 2; scene.add(v);
    for (const [w, h, pz, py] of [[2.8, .12, 0, 2.8], [2.8, .12, 0, .9], [.12, 1.9, -1.35, 1.85], [.12, 1.9, 1.35, 1.85]]) mesh(new THREE.BoxGeometry(.14, h, w === 2.8 ? 2.8 : .12), toon(0xf4f4f0), { pos: [5.18, py, z + pz], outline: .01, parent: scene });
  }
  const sunM = new THREE.MeshBasicMaterial({ color: 0xfff1c8, transparent: true, opacity: .2, depthWrite: false, blending: THREE.AdditiveBlending });
  for (const z of [-3, 0, 3]) mesh(new THREE.PlaneGeometry(2.6, 2.2), sunM, { pos: [3.3, .006, z + .5], rot: [-Math.PI / 2, 0, .4], outline: false, parent: scene });
  // доска с формулами
  const boardT = tex(1024, 400, (g, w, h) => {
    g.fillStyle = '#24493a'; g.fillRect(0, 0, w, h);
    g.fillStyle = 'rgba(255,255,255,.07)'; for (let i = 0; i < 30; i++) g.fillRect(Math.random() * w, Math.random() * h, 120, 10);
    g.fillStyle = '#f4f4ec'; g.font = '700 64px Rubik'; g.fillText('F = m · a', 60, 110);
    g.font = '500 38px Rubik'; g.fillText('Задача №7. Автобус m = 10 т висит над рекой.', 60, 190);
    g.fillText('Какая сила нужна, чтобы его удержать?', 60, 240);
    g.fillText('F = m · g = 10 000 · 9,8 ≈ 98 000 Н', 60, 320);
    g.strokeStyle = '#f4f4ec'; g.lineWidth = 4; g.strokeRect(760, 40, 180, 90); g.beginPath(); g.moveTo(850, 130); g.lineTo(850, 190); g.stroke(); g.fillText('↓ g', 860, 180);
  });
  S.boardT = boardT;
  mesh(new THREE.BoxGeometry(5.6, 2.1, .08), toon(0x6a4a2a), { pos: [0, 1.85, -4.56], outline: .02, parent: scene });
  const board = plane(5.4, 1.95, boardT); board.position.set(0, 1.85, -4.51); scene.add(board);
  mesh(new THREE.BoxGeometry(5.4, .06, .14), toon(0x6a4a2a), { pos: [0, .8, -4.46], outline: false, parent: scene });
  // стол учителя
  mesh(rb(1.6, .08, .75), toon(0x8a5a36), { pos: [-2.6, .76, -3.4], outline: .015, parent: scene });
  mesh(rb(1.5, .7, .05), toon(0x7a4a2a), { pos: [-2.6, .38, -3.05], outline: .01, parent: scene });
  mesh(rb(.3, .04, .22), toon(0x2c7be5), { pos: [-2.9, .82, -3.4], outline: .005, parent: scene });
  mesh(new THREE.SphereGeometry(.12, 16, 12), toon(0x3a8ad0), { pos: [-2.1, .92, -3.5], outline: .006, parent: scene });  // глобус
  // парты 3 колонки × 4 ряда (двухместные), стулья
  const deskM = toon(0xd9c3a0), legM = toon(0x4a5060), chairM = toon(0x3a6a8a);
  for (let r = 0; r < 4; r++) for (let c = 0; c < 3; c++) {
    const x = -3.0 + c * 2.7, z = -1.6 + r * 1.6;
    const d = new THREE.Group(); d.position.set(x, 0, z); scene.add(d); S.desks.push({ x, z, r, c });
    mesh(rb(1.3, .05, .55), deskM, { pos: [0, .74, 0], outline: .012, parent: d });
    for (const sx of [-.55, .55]) mesh(new THREE.BoxGeometry(.04, .72, .45), legM, { pos: [sx, .36, 0], outline: false, parent: d });
    for (const sx of [-.32, .32]) {
      const ch = new THREE.Group(); ch.position.set(sx, 0, .55); d.add(ch);
      mesh(rb(.4, .04, .38), chairM, { pos: [0, .44, 0], outline: .008, parent: ch });
      mesh(rb(.4, .36, .03), chairM, { pos: [0, .68, .2], outline: .008, parent: ch });
      for (const [a, b] of [[.17, .15], [-.17, .15], [.17, -.15], [-.17, -.15]]) mesh(new THREE.BoxGeometry(.03, .44, .03), legM, { pos: [a, .22, b], outline: false, parent: ch });
      // книги и пеналы
      if ((r + c + (sx > 0 ? 1 : 0)) % 2 === 0) mesh(rb(.22, .03, .3), toon([0xe85a5a, 0x5a9ae8, 0xf2c94c, 0x5ac88a][(r * 3 + c) % 4]), { pos: [sx, .78, -.05], rot: [0, (r - c) * .2, 0], outline: .004, parent: d });
    }
  }
  // плакаты учёных на задней стене, шкаф
  const P = [poster('НЬЮТОН', 'F = m·a', '#f4efe0', '#2a2a2a', 0), poster('ТЕСЛА', 'ток — это\nсвобода', '#f4efe0', '#2a2a2a', 1), poster('ИБН СИНА', 'знание — сила', '#f4efe0', '#2a2a2a', 2)];
  P.forEach((t, i) => { const p = plane(.8, 1.12, t); p.position.set(-2.5 + i * 2.5, 2.2, 4.59); p.rotation.y = Math.PI; scene.add(p); });
  mesh(rb(1.6, 2.0, .45), toon(0x9a6a3a), { pos: [-4.3, 1.0, 3.6], outline: .015, parent: scene });
  const clockT = tex(128, 128, (g) => { g.fillStyle = '#fff'; g.beginPath(); g.arc(64, 64, 60, 0, 7); g.fill(); g.strokeStyle = '#222'; g.lineWidth = 5; g.stroke(); g.lineWidth = 6; g.beginPath(); g.moveTo(64, 64); g.lineTo(64, 24); g.moveTo(64, 64); g.lineTo(30, 70); g.stroke(); });
  const clock = plane(.45, .45, clockT, { basic: true }); clock.position.set(3.2, 2.9, -4.59); scene.add(clock);
  mesh(new THREE.BoxGeometry(10.4, .1, 9.4), toon(0xf4f2ec), { pos: [0, 3.3, 0], outline: false, parent: scene });
  for (const x of [-2.6, 0, 2.6]) for (const z of [-2, 1.6]) mesh(new THREE.BoxGeometry(1.2, .05, .35), glow(0xfff8e8, 1.4), { pos: [x, 3.24, z], outline: false, parent: scene });
  // бумажный комок (полёт — режиссура)
  S.paper = mesh(new THREE.IcosahedronGeometry(.045, 1), toon(0xf6f4ee), { outline: .004, parent: scene }); S.paper.visible = false;
  scene.add(new THREE.HemisphereLight(0xeaf2ff, 0x9a8a70, 1.45));
  const sun = new THREE.DirectionalLight(0xfff0d6, 2.1); sun.position.set(14, 8, 3); sun.target.position.set(0, 0, 0); scene.add(sun, sun.target); S.sun = sun; aimable(scene, sun);
  return S;
}

/* ---------- столовая: x −8…8, z −6 (раздача)…+6, окна на x = −8, ТВ на стене x = +8 ---------- */
function makeCanteen() {
  const scene = new THREE.Scene(); scene.background = new THREE.Color(0xdfe6ee);
  const S = { scene, tables: [] };
  const floorT = tex(256, 256, (g, w, h) => { for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) { g.fillStyle = (x + y) % 2 ? '#c9bfa8' : '#a8977a'; g.fillRect(x * 32, y * 32, 32, 32); } }, [8, 6]);
  mesh(new THREE.PlaneGeometry(16.4, 12.4), toon(0xffffff, { map: floorT }), { rot: [-Math.PI / 2, 0, 0], outline: false, parent: scene });
  const wallM = toon(0xe8dcc0), lowM = toon(0xd0773a);
  mesh(new THREE.BoxGeometry(16.4, 3.6, .2), wallM, { pos: [0, 1.8, -6.2], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(16.4, 3.6, .2), wallM, { pos: [0, 1.8, 6.2], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(.2, 3.6, 12.4), wallM, { pos: [8.2, 1.8, 0], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(.2, 1.0, 12.4), lowM, { pos: [8.1, .5, 0], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(16.4, 1.0, .2), lowM, { pos: [0, .5, 6.1], outline: false, parent: scene });
  // окна (x = −8)
  const view = windowView(11);
  mesh(new THREE.BoxGeometry(.2, .9, 12.4), lowM, { pos: [-8.2, .45, 0], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(.2, .6, 12.4), wallM, { pos: [-8.2, 3.3, 0], outline: false, parent: scene });
  for (const z of [-4, 0, 4]) {
    const v = plane(3.4, 2.0, view, { basic: true }); v.position.set(-8.28, 2.0, z); v.rotation.y = Math.PI / 2; scene.add(v);
    for (const [h, pz, py, w] of [[.12, 0, 3.0, 3.6], [.12, 0, .95, 3.6], [2.1, -1.75, 2.0, .12], [2.1, 1.75, 2.0, .12], [2.1, 0, 2.0, .08]]) mesh(new THREE.BoxGeometry(.14, h, w), toon(0xf4f4f0), { pos: [-8.18, py, z + pz], outline: .01, parent: scene });
  }
  const sunM = new THREE.MeshBasicMaterial({ color: 0xfff1c8, transparent: true, opacity: .2, depthWrite: false, blending: THREE.AdditiveBlending });
  for (const z of [-4, 0, 4]) mesh(new THREE.PlaneGeometry(3.0, 2.6), sunM, { pos: [-6.2, .006, z + .4], rot: [-Math.PI / 2, 0, -.35], outline: false, parent: scene });
  // раздача: прилавок, стекло, лотки с пловом и самсой, меню
  mesh(rb(9, 1.0, .9), toon(0xc9ced6), { pos: [0, .5, -5.4], outline: .015, parent: scene });
  mesh(new THREE.BoxGeometry(9, .04, 1.0), toon(0xe8ecf0), { pos: [0, 1.02, -5.4], outline: false, parent: scene });
  mesh(new THREE.BoxGeometry(9, .5, .02), new THREE.MeshBasicMaterial({ color: 0xbfe8ff, transparent: true, opacity: .25, depthWrite: false }), { pos: [0, 1.4, -5.0], rot: [-.3, 0, 0], outline: false, parent: scene });
  for (let i = 0; i < 6; i++) {
    mesh(rb(1.1, .12, .55), toon(0xd8dde4), { pos: [-3.6 + i * 1.45, 1.1, -5.45], outline: .006, parent: scene });
    mesh(new THREE.SphereGeometry(.4, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), toon([0xf0c060, 0xd99a50, 0x8ac060, 0xf0c060, 0xe0704a, 0xf6e6c0][i]), { pos: [-3.6 + i * 1.45, 1.13, -5.45], scale: [1.2, .25, .6], outline: .004, parent: scene });
  }
  const menuT = tex(512, 256, (g, w, h) => { g.fillStyle = '#1c2a22'; g.fillRect(0, 0, w, h); g.fillStyle = '#f2f0e0'; g.font = '800 40px Rubik'; g.fillText('МЕНЮ', 30, 52);
    g.font = '500 30px Rubik'; ['Плов ........ 25', 'Самса ....... 12', 'Лагман ...... 22', 'Чай ........... 5', 'Компот ....... 6'].forEach((l, i) => g.fillText(l, 30, 100 + i * 34)); });
  const menu = plane(2.4, 1.2, menuT); menu.position.set(0, 2.6, -6.09); scene.add(menu);
  // столы и стулья: 2 колонки × 3 ряда (длинные столы вдоль x)
  const tabM = toon(0xcfd8d0), legM = toon(0x6a707a), stoolM = toon(0xe0874a);
  for (let r = 0; r < 3; r++) for (let c = 0; c < 2; c++) {
    const x = -3.2 + c * 6.0, z = -2.2 + r * 3.0;
    const t = new THREE.Group(); t.position.set(x, 0, z); scene.add(t); S.tables.push({ x, z });
    mesh(rb(3.6, .07, 1.1), tabM, { pos: [0, .76, 0], outline: .015, parent: t });
    for (const sx of [-1.6, 1.6]) for (const sz of [-.42, .42]) mesh(new THREE.CylinderGeometry(.04, .04, .74, 8), legM, { pos: [sx, .37, sz], outline: false, parent: t });
    for (let i = 0; i < 4; i++) for (const sz of [-.85, .85]) {
      const st = new THREE.Group(); st.position.set(-1.35 + i * .9, 0, sz); t.add(st);
      mesh(new THREE.CylinderGeometry(.2, .2, .05, 16), stoolM, { pos: [0, .46, 0], outline: .006, parent: st });
      mesh(new THREE.CylinderGeometry(.03, .03, .44, 8), legM, { pos: [0, .22, 0], outline: false, parent: st });
    }
    // подносы с едой на части мест
    for (let i = 0; i < 3; i++) { const sz = ((i + r + c) % 2 ? -.3 : .3), px = -1.2 + i * 1.1;
      mesh(rb(.42, .02, .3), toon(0xe0874a), { pos: [px, .8, sz], outline: .004, parent: t });
      mesh(new THREE.CylinderGeometry(.11, .08, .03, 16), toon(0xffffff), { pos: [px - .06, .82, sz], outline: .003, parent: t });
      mesh(new THREE.CylinderGeometry(.04, .035, .09, 10), toon([0x3a8ad0, 0xe85a5a, 0x5ac88a][i]), { pos: [px + .13, .86, sz + .06], outline: .003, parent: t });
    }
  }
  // поднос Тимура: три порции плова (место x = −3.2 + .45, z = .8 — второй ряд, левый стол)
  const tray = S.timurTray = new THREE.Group(); scene.add(tray);
  mesh(rb(.5, .02, .34), toon(0x1d4fa0), { outline: .004, parent: tray });
  for (let i = 0; i < 3; i++) { mesh(new THREE.CylinderGeometry(.1, .075, .03, 16), toon(0xffffff), { pos: [-.15 + i * .15, .02, (i % 2) * .06 - .03], outline: .003, parent: tray });
    mesh(new THREE.SphereGeometry(.075, 12, 6, 0, Math.PI * 2, 0, Math.PI / 2), toon(0xf0c060), { pos: [-.15 + i * .15, .03, (i % 2) * .06 - .03], scale: [1, .5, 1], outline: .003, parent: tray }); }
  // телевизор на стене x = +8 (новости — canvas обновляет режиссура через S.drawTV)
  const tvC = document.createElement('canvas'); tvC.width = 512; tvC.height = 288; const tvT = new THREE.CanvasTexture(tvC); tvT.colorSpace = THREE.SRGBColorSpace;
  mesh(rb(2.3, 1.35, .1), toon(0x15171c), { pos: [8.02, 2.5, 1.5], rot: [0, -Math.PI / 2, 0], outline: .015, parent: scene });
  const tv = new THREE.Mesh(new THREE.PlaneGeometry(2.15, 1.21), new THREE.MeshBasicMaterial({ map: tvT, color: new THREE.Color(1.3, 1.3, 1.3) })); tv.position.set(7.95, 2.5, 1.5); tv.rotation.y = -Math.PI / 2; scene.add(tv);
  S.tvPos = tv.position.clone();
  S.drawTV = t => {
    const g = tvC.getContext('2d'), w = 512, h = 288;
    const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#0d2a4a'); gr.addColorStop(1, '#1a0f2a'); g.fillStyle = gr; g.fillRect(0, 0, w, h);
    // «кадр» с мостом и автобусом
    g.strokeStyle = '#e04a3a'; g.lineWidth = 6; g.beginPath(); g.moveTo(40, 170); g.lineTo(470, 170); g.stroke();
    for (const x of [140, 370]) { g.beginPath(); g.moveTo(x, 60); g.lineTo(x, 200); g.stroke(); }
    g.save(); g.translate(300, 168); g.rotate(.35); g.fillStyle = '#f2f2ee'; g.fillRect(0, -18, 90, 30); g.fillStyle = '#e8343c'; g.fillRect(0, 4, 90, 8); g.restore();
    g.strokeStyle = '#7ff8ff'; g.lineWidth = 2; g.beginPath(); g.moveTo(300, 40); g.lineTo(318, 150); g.stroke();
    g.fillStyle = '#7ff8ff'; g.beginPath(); g.arc(300, 40, 6, 0, 7); g.fill();
    g.fillStyle = '#c8202c'; g.fillRect(0, 210, w, 34); g.fillStyle = '#fff'; g.font = '800 22px Rubik'; g.fillText('ГЕРОЙ С МОСТА: КТО ОН?', 14, 234);
    g.fillStyle = '#0c0c14'; g.fillRect(0, 244, w, 44); g.fillStyle = '#ffd23d'; g.font = '600 18px Rubik';
    const msg = 'СРОЧНО • «Паук» удержал автобус №42 • Полиция ищет героя • Опрос: как назвать героя? • ';
    g.fillText(msg + msg, -((t * 70) % 760), 272);
    g.fillStyle = '#fff'; g.font = '700 16px Rubik'; g.fillText('НОВОГРАД ТВ', 400, 26);
    tvT.needsUpdate = true;
  };
  S.drawTV(0);
  // торговый автомат, плакаты, подвесные лампы
  mesh(rb(1.0, 2.0, .8), toon(0xc8202c), { pos: [7.5, 1.0, -4.2], rot: [0, -Math.PI / 2, 0], outline: .015, parent: scene });
  mesh(new THREE.BoxGeometry(.02, 1.2, .6), glow(0xbfe8ff, 1.1), { pos: [7.08, 1.2, -4.2], outline: false, parent: scene });
  const P = [poster('ЕШЬ\nОВОЩИ', 'и будь\nкак Паук', '#5ac88a', '#ffffff', 2), poster('ВОДА —\nЖИЗНЬ', 'пей больше', '#3a8ad0', '#ffffff', 1)];
  P.forEach((t, i) => { const p = plane(.8, 1.12, t); p.position.set(-4 + i * 7, 2.4, 6.09); p.rotation.y = Math.PI; scene.add(p); });
  mesh(new THREE.BoxGeometry(16.4, .1, 12.4), toon(0xf4f2ec), { pos: [0, 3.65, 0], outline: false, parent: scene });
  for (const x of [-3.2, 2.8]) for (const z of [-2.2, .8, 3.8]) {
    mesh(new THREE.CylinderGeometry(.01, .01, .9, 4), toon(0x222222), { pos: [x, 3.2, z], outline: false, parent: scene });
    mesh(new THREE.ConeGeometry(.35, .3, 16, 1, true), toon(0x2f6b4f, { side: THREE.DoubleSide }), { pos: [x, 2.7, z], outline: .006, parent: scene });
    mesh(new THREE.SphereGeometry(.12, 10, 8), glow(0xfff1c8, 2.2), { pos: [x, 2.6, z], outline: false, parent: scene });
  }
  scene.add(new THREE.HemisphereLight(0xeaf2ff, 0x8a7a60, .95));
  const sun = new THREE.DirectionalLight(0xfff0d6, 1.6); sun.position.set(-14, 9, 4); sun.target.position.set(0, 0, 0); scene.add(sun, sun.target); S.sun = sun; aimable(scene, sun);
  const warm = new THREE.PointLight(0xffd8a0, 2.5, 14, 1.4); warm.position.set(0, 3, 0); scene.add(warm);
  return S;
}

export function makeSchool() {
  return { corridor: makeCorridor(), classroom: makeClassroom(), canteen: makeCanteen() };
}
