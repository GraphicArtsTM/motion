// 2D-слой поверх WebGL: субтитры, заставка, окно звонка, комикс-надписи, вспышки, затемнения, виньетка.
import { W, H, clamp, E, P, lerp, rng } from './core.js';

export function makeOverlay(canvas) {
  canvas.width = W; canvas.height = H;
  const g = canvas.getContext('2d');
  const O = { g, canvas };

  O.clear = () => g.clearRect(0, 0, W, H);

  O.fill = (color, a) => { if (a <= 0) return; g.save(); g.globalAlpha = clamp(a); g.fillStyle = color; g.fillRect(0, 0, W, H); g.restore(); };

  O.vignette = (k = .55) => {
    const r = g.createRadialGradient(W / 2, H / 2, H * .35, W / 2, H / 2, H * .95);
    r.addColorStop(0, 'rgba(0,0,0,0)'); r.addColorStop(1, `rgba(0,0,0,${k})`);
    g.fillStyle = r; g.fillRect(0, 0, W, H);
  };

  O.bars = k => { if (k <= 0) return; const h = 120 * k; g.fillStyle = '#000'; g.fillRect(0, 0, W, h); g.fillRect(0, H - h, W, h); };

  // субтитры
  const wrap = (text, maxW) => {
    const words = text.split(' '), lines = []; let cur = '';
    for (const w of words) { const s = cur ? cur + ' ' + w : w; if (g.measureText(s).width > maxW && cur) { lines.push(cur); cur = w; } else cur = s; }
    if (cur) lines.push(cur); return lines;
  };
  O.subtitle = (text, a, who, italic) => {
    if (a <= 0) return;
    g.save(); g.globalAlpha = clamp(a);
    g.font = `${italic ? 'italic ' : ''}600 46px Rubik`; g.textAlign = 'center'; g.textBaseline = 'alphabetic';
    const lines = wrap(text, 1500);
    lines.forEach((ln, i) => {
      const y = H - 70 - (lines.length - 1 - i) * 58;
      g.lineJoin = 'round'; g.lineWidth = 9; g.strokeStyle = 'rgba(0,0,0,.85)'; g.strokeText(ln, W / 2, y);
      g.fillStyle = who === 'narrator' ? '#d8f7ff' : who === 'shadow' ? '#ff9a9a' : '#ffffff'; g.fillText(ln, W / 2, y);
    });
    g.restore();
  };

  // комикс-надпись: «ВЖУХ!», «БАМ!»
  O.comic = (text, x, y, lt, o = {}) => {
    const dur = o.dur ?? .9; if (lt < 0 || lt > dur) return;
    const k = E.outBack(clamp(lt / .14)), out = 1 - E.inQuad(clamp((lt - dur + .25) / .25));
    g.save(); g.translate(x, y); g.rotate(o.rot ?? -.12); g.scale(k * (o.size ?? 1), k * (o.size ?? 1)); g.globalAlpha = out;
    g.font = '900 120px Unbounded'; g.textAlign = 'center'; g.textBaseline = 'middle';
    // лучи-взрыв за надписью
    if (o.burst !== false) {
      g.fillStyle = o.burstColor || '#ffffff'; g.beginPath();
      const n = 14, r = rng(text.length * 7);
      for (let i = 0; i <= n * 2; i++) { const a = i / (n * 2) * Math.PI * 2, R = (i % 2 ? 150 : 250 + r() * 60) * (o.bw ?? 1); g.lineTo(Math.cos(a) * R * 1.4, Math.sin(a) * R * .8); }
      g.closePath(); g.lineWidth = 8; g.strokeStyle = '#000'; g.stroke(); g.fill();
    }
    g.lineJoin = 'round'; g.lineWidth = 22; g.strokeStyle = '#000'; g.strokeText(text, 0, 0);
    g.fillStyle = o.color || '#ffe23d'; g.fillText(text, 0, 0);
    g.restore();
  };

  // радиальные линии скорости
  O.speedLines = (k, t, cx = W / 2, cy = H / 2) => {
    if (k <= 0) return;
    g.save(); g.globalAlpha = clamp(k) * .55; g.strokeStyle = '#fff';
    const r = rng(Math.floor(t * 20));
    for (let i = 0; i < 70; i++) {
      const a = r() * Math.PI * 2, r0 = 380 + r() * 300, r1 = r0 + 200 + r() * 600;
      g.lineWidth = 1 + r() * 3;
      g.beginPath(); g.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0); g.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); g.stroke();
    }
    g.restore();
  };

  // окно звонка (рамка вокруг вставки с дедом)
  // капли дождя на объективе (крупные планы под дождём)
  O.lensDrops = (t, k = 1) => {
    if (k <= 0) return;
    const r = rng(1234);
    g.save();
    for (let i = 0; i < 26; i++) {
      const born = r() * 6, life = 2 + r() * 3, ph = ((t - born) % 6 + 6) % 6;
      if (ph > life) continue;
      const x = r() * W, y0 = r() * H, rad = 6 + r() * 18, slide = ph > life * .6 ? (ph - life * .6) * (30 + r() * 60) : 0;
      const y = y0 + slide, a = k * Math.min(1, ph * 4) * (1 - Math.max(0, ph - life + .4) / .4);
      const gr = g.createRadialGradient(x - rad * .3, y - rad * .3, rad * .1, x, y, rad);
      gr.addColorStop(0, `rgba(255,255,255,${.35 * a})`); gr.addColorStop(.6, `rgba(180,200,255,${.08 * a})`); gr.addColorStop(1, `rgba(20,30,50,${.25 * a})`);
      g.fillStyle = gr; g.beginPath(); g.ellipse(x, y, rad, rad * 1.1, 0, 0, Math.PI * 2); g.fill();
      if (slide > 0) { g.strokeStyle = `rgba(200,215,255,${.12 * a})`; g.lineWidth = rad * .5; g.beginPath(); g.moveTo(x, y0); g.lineTo(x, y - rad); g.stroke(); }
    }
    g.restore();
  };

  // комикс-подпись: жёлтая плашка рассказчика (без озвучки) — объясняет, что происходит
  O.caption = (text, x, y, lt, o = {}) => {
    const dur = o.dur ?? 2; if (lt < 0 || lt > dur) return;
    const a = Math.min(clamp(lt / .2), clamp((dur - lt) / .25));
    const s = .9 + .1 * E.outBack(clamp(lt / .3));
    g.save(); g.globalAlpha = a; g.translate(x, y); g.scale(s, s); g.rotate(o.rot ?? -.015);
    g.font = '700 34px Rubik';
    const lines = String(text).split('\n'), w = Math.max(...lines.map(l => g.measureText(l).width)) + 44, h = 46 * lines.length + 22;
    g.fillStyle = 'rgba(0,0,0,.35)'; g.fillRect(8, 8, w, h);
    g.fillStyle = o.bg || '#ffe23d'; g.fillRect(0, 0, w, h);
    g.lineWidth = 5; g.strokeStyle = '#111'; g.strokeRect(0, 0, w, h);
    g.fillStyle = '#111'; g.textBaseline = 'top'; lines.forEach((l, i) => g.fillText(l, 22, 14 + i * 46));
    g.restore();
  };

  // HUD-надпись (визор/системы) поверх комикс-вставки
  O.hud = (lines, x, y, a, t) => {
    if (a <= 0) return;
    g.save(); g.globalAlpha = clamp(a);
    g.fillStyle = 'rgba(30,0,0,.75)'; g.fillRect(x - 10, y - 40, 470, 34 * lines.length + 18);
    lines.forEach((ln, i) => {
      g.font = `${i ? 600 : 800} ${i ? 24 : 30}px Rubik`;
      g.fillStyle = i ? '#ffb0a0' : (Math.sin(t * 14) > -.2 ? '#ff4a3a' : '#ffd0c0'); g.fillText(ln, x, y - 8 + i * 34);
    });
    g.restore();
  };

  // рамка комикс-панели
  O.panelFrame = (x, y, w, h) => {
    g.save(); g.lineJoin = 'miter';
    g.lineWidth = 14; g.strokeStyle = '#000'; g.strokeRect(x - 7, y - 7, w + 14, h + 14);
    g.lineWidth = 7; g.strokeStyle = '#fff'; g.strokeRect(x - 2, y - 2, w + 4, h + 4);
    g.restore();
  };

  // кадр «с телефона зеваки»: рамка смартфона, запись, хэштег, счётчик зрителей, сердечки
  O.phoneFrame = (x, y, w, h, t, t0) => {
    g.save();
    const R = Math.min(w, h) * .12;
    // маска: всё вне скруглённого экрана закрываем корпусом
    g.fillStyle = '#0b0c10'; g.beginPath(); g.rect(x - 22, y - 22, w + 44, h + 44);
    g.moveTo(x + R, y); g.arcTo(x + w, y, x + w, y + h, R); g.arcTo(x + w, y + h, x, y + h, R); g.arcTo(x, y + h, x, y, R); g.arcTo(x, y, x + w, y, R); g.closePath(); g.fill('evenodd');
    g.lineWidth = 4; g.strokeStyle = '#3a3e48'; roundRect(g, x - 22, y - 22, w + 44, h + 44, R + 20); g.stroke();
    g.lineWidth = 6; g.strokeStyle = '#000'; roundRect(g, x - 26, y - 26, w + 52, h + 52, R + 24); g.stroke();
    g.fillStyle = '#000'; roundRect(g, x + w / 2 - 48, y + 12, 96, 26, 13); g.fill();
    const lt = t - t0, s = Math.max(0, Math.floor(lt + 13));
    g.textBaseline = 'middle';
    g.fillStyle = 'rgba(0,0,0,.35)'; roundRect(g, x + 14, y + 50, 132, 34, 17); g.fill();
    g.fillStyle = Math.floor(t * 2) % 2 ? '#ff2a3a' : '#a01020'; g.beginPath(); g.arc(x + 34, y + 67, 8, 0, 7); g.fill();
    g.fillStyle = '#fff'; g.font = '600 20px Rubik'; g.fillText('REC 0:' + String(s).padStart(2, '0'), x + 50, y + 68);
    g.textAlign = 'right'; g.font = '600 16px Rubik'; g.fillText('4K · 60', x + w - 18, y + 67); g.textAlign = 'left';
    // рамка фокуса
    const cx = x + w / 2, cy = y + h * .42, fs = 46 + 8 * Math.exp(-lt * 4);
    g.strokeStyle = 'rgba(255,214,60,.9)'; g.lineWidth = 3;
    for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) { g.beginPath(); g.moveTo(cx + sx * fs, cy + sy * (fs - 14)); g.lineTo(cx + sx * fs, cy + sy * fs); g.lineTo(cx + sx * (fs - 14), cy + sy * fs); g.stroke(); }
    // низ: хэштег, зрители
    const gr = g.createLinearGradient(0, y + h - 150, 0, y + h); gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,.65)');
    g.fillStyle = gr; g.fillRect(x, y + h - 150, w, 150);
    g.fillStyle = '#ff2a5a'; roundRect(g, x + 16, y + h - 112, 66, 26, 6); g.fill();
    g.fillStyle = '#fff'; g.font = '700 15px Rubik'; g.fillText('LIVE', x + 29, y + h - 98);
    const viewers = Math.floor(1200 + Math.pow(Math.max(0, lt), 1.6) * 2600);
    g.font = '500 17px Rubik'; g.fillText(viewers.toLocaleString('ru-RU') + ' смотрят', x + 92, y + h - 98);
    g.font = '800 23px Unbounded'; g.fillStyle = '#7ff8ff'; g.fillText('#ПаукНовограда', x + 16, y + h - 62);
    g.font = '500 16px Rubik'; g.fillStyle = 'rgba(255,255,255,.85)'; g.fillText('он спас автобус!!! это реально', x + 16, y + h - 32);
    // сердечки всплывают справа
    for (let i = 0; i < 9; i++) {
      if (lt < i * .22) continue;
      const k = ((lt - i * .22) * .55) % 1, hx = x + w - 44 + Math.sin(i * 2.3 + lt * 3) * 14, hy = y + h - 60 - k * h * .55, hs2 = 9 + (i % 3) * 3;
      g.globalAlpha = Math.min(1, (1 - k) * 2) * .95; g.fillStyle = ['#ff3d6a', '#ff7aa8', '#ffd23d'][i % 3];
      g.beginPath(); g.moveTo(hx, hy + hs2 * .9);
      g.bezierCurveTo(hx - hs2 * 1.4, hy - hs2 * .2, hx - hs2 * .6, hy - hs2 * 1.2, hx, hy - hs2 * .45);
      g.bezierCurveTo(hx + hs2 * .6, hy - hs2 * 1.2, hx + hs2 * 1.4, hy - hs2 * .2, hx, hy + hs2 * .9); g.fill();
    }
    g.restore();
  };

  // уведомление на телефоне (заказ, сообщение): notice(x, y, k, { app, title, lines, time, color })
  O.notice = (x, y, k, o = {}) => {
    if (k <= 0) return;
    const s = E.outBack(clamp(k)), w = 620, h = 70 + 44 * (o.lines?.length || 1);
    g.save(); g.globalAlpha = clamp(k * 1.5); g.translate(x + w / 2, y + h / 2); g.scale(s, s); g.translate(-w / 2, -h / 2);
    g.shadowColor = 'rgba(0,0,0,.6)'; g.shadowBlur = 30;
    g.fillStyle = 'rgba(20,24,36,.94)'; roundRect(g, 0, 0, w, h, 26); g.fill(); g.shadowBlur = 0;
    g.fillStyle = o.color || '#ff7b1c'; roundRect(g, 22, 20, 40, 40, 10); g.fill();
    g.fillStyle = '#fff'; g.font = '900 24px Unbounded'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText('Б', 42, 41);
    g.textAlign = 'left'; g.font = '600 22px Rubik'; g.fillStyle = '#9aa6c0'; g.fillText((o.app || 'БЫСТРО · доставка'), 76, 32);
    g.textAlign = 'right'; g.fillText(o.time || 'сейчас', w - 24, 32); g.textAlign = 'left';
    g.font = '800 28px Rubik'; g.fillStyle = '#fff'; g.fillText(o.title || 'Новый заказ', 76, 66);
    g.font = '500 24px Rubik'; g.fillStyle = '#d8def0';
    (o.lines || []).forEach((l, i) => g.fillText(l, 76, 104 + i * 40));
    g.restore();
  };

  // радар/карта города на планшете Веры: radar(x, y, w, h, t, { blue:[u,v], reds:[[u,v],…], label })
  O.radar = (x, y, w, h, t, o = {}) => {
    g.save();
    g.fillStyle = 'rgba(6,14,22,.92)'; roundRect(g, x, y, w, h, 18); g.fill();
    g.strokeStyle = 'rgba(63,240,255,.5)'; g.lineWidth = 3; roundRect(g, x, y, w, h, 18); g.stroke();
    g.beginPath(); roundRect(g, x + 6, y + 6, w - 12, h - 12, 14); g.clip();
    g.strokeStyle = 'rgba(63,240,255,.13)'; g.lineWidth = 2;
    for (let i = 0; i < 12; i++) { g.beginPath(); g.moveTo(x + i * w / 11, y); g.lineTo(x + i * w / 11, y + h); g.stroke(); g.beginPath(); g.moveTo(x, y + i * h / 7); g.lineTo(x + w, y + i * h / 7); g.stroke(); }
    g.fillStyle = 'rgba(40,80,140,.45)'; g.fillRect(x + w * .72, y, w * .12, h);                 // река
    g.strokeStyle = 'rgba(255,90,60,.6)'; g.lineWidth = 5; g.beginPath(); g.moveTo(x + w * .66, y + h * .55); g.lineTo(x + w * .9, y + h * .55); g.stroke(); // мост
    g.strokeStyle = 'rgba(63,240,255,.35)'; g.lineWidth = 6; g.beginPath(); g.moveTo(x + w * .45, y); g.lineTo(x + w * .45, y + h); g.stroke();     // проспект
    const sweep = (t * 1.2) % 1; g.fillStyle = 'rgba(63,240,255,.07)'; g.fillRect(x + sweep * w - 40, y, 40, h);
    const dot = ([u, v], col, r0) => {
      const px = x + u * w, py = y + v * h, k = (t * 1.6) % 1;
      g.strokeStyle = col; g.globalAlpha = 1 - k; g.lineWidth = 3; g.beginPath(); g.arc(px, py, r0 + k * 30, 0, 7); g.stroke(); g.globalAlpha = 1;
      g.fillStyle = col; g.shadowColor = col; g.shadowBlur = 16; g.beginPath(); g.arc(px, py, r0, 0, 7); g.fill(); g.shadowBlur = 0;
    };
    (o.reds || []).forEach(p => dot(p, '#ff3a3a', 6));
    if (o.blue) dot(o.blue, '#3ff0ff', 9);
    g.restore();
    g.save(); g.font = '700 22px Rubik'; g.fillStyle = '#3ff0ff'; g.textBaseline = 'top';
    g.fillText(o.label || 'АРАХНА-7 · СИГНАЛ', x + 20, y + 16);
    if (o.reds?.length) { g.fillStyle = '#ff5a5a'; g.textAlign = 'right'; g.fillText(`НЕИЗВЕСТНЫЕ: ${o.reds.length}`, x + w - 20, y + 16); }
    g.restore();
  };

  O.callFrame = (x, y, w, h, a, t) => {
    if (a <= 0) return;
    g.save(); g.globalAlpha = clamp(a);
    g.lineWidth = 8; g.strokeStyle = '#ffffff'; roundRect(g, x, y, w, h, 26); g.stroke();
    g.lineWidth = 3; g.strokeStyle = '#000'; roundRect(g, x - 5, y - 5, w + 10, h + 10, 30); g.stroke();
    g.fillStyle = 'rgba(10,14,24,.85)'; roundRect(g, x + 16, y + h - 64, 270, 48, 24); g.fill();
    g.fillStyle = '#3dff8a'; g.beginPath(); g.arc(x + 44, y + h - 40, 9 + Math.sin(t * 8) * 2, 0, 7); g.fill();
    g.fillStyle = '#fff'; g.font = '600 28px Rubik'; g.textBaseline = 'middle'; g.fillText('Дед · на связи', x + 64, y + h - 39);
    g.restore();
  };

  /* ---------- заставка студии GraphicArts Animation ----------
     0.0  тёмный «лист», полутоновые точки; загорается кончик пера
     0.5  перо одной линией рисует монограмму GA (G, перекладина которой становится перекладиной A)
     2.4  всплеск краски: оранжевая, малиновая, бирюзовая, жёлтая кляксы; линия становится «чернильной»
     2.9  буквы GraphicArts выпрыгивают по одной, ниже разъезжается A N I M A T I O N, слоган
     4.3  паучок спускается на нити и садится на точку над «i», в 5.3 уезжает вверх
     5.2  «представляет»; 6.0 — затемнение */
  const GA = (() => {
    const R = 120, s1 = [], s2 = [];
    for (let i = 0; i <= 60; i++) { const a = -.6 - (2 * Math.PI - 1.0) * i / 60; s1.push([Math.cos(a) * R, Math.sin(a) * R]); }
    const e = s1[s1.length - 1];
    s1.push([e[0], .05 * R], [-.27 * R, .05 * R]);
    s2.push([-.46 * R, .66 * R], [0, -.72 * R], [.46 * R, .66 * R]);
    const len = pts => pts.reduce((a, p, i) => i ? a + Math.hypot(p[0] - pts[i - 1][0], p[1] - pts[i - 1][1]) : 0, 0);
    return { R, strokes: [s1, s2], lens: [len(s1), len(s2)] };
  })();
  const partial = (pts, L) => {        // ломаная до длины L и точка пера
    const out = [pts[0]]; let acc = 0;
    for (let i = 1; i < pts.length; i++) {
      const [ax, ay] = pts[i - 1], [bx, by] = pts[i], d = Math.hypot(bx - ax, by - ay);
      if (acc + d >= L) { const k = (L - acc) / d; out.push([ax + (bx - ax) * k, ay + (by - ay) * k]); return out; }
      acc += d; out.push(pts[i]);
    }
    return out;
  };
  const splats = (() => { const r = rng(31), a = [];
    const cols = ['#ff7b1c', '#ff3d7f', '#3ff0ff', '#ffd23d', '#8a5cff'];
    for (let i = 0; i < 14; i++) { const ang = r() * Math.PI * 2, d = 120 + r() * 230; a.push({ ang, d, r: 22 + r() * 70, c: cols[i % cols.length], dl: r() * .15, blobs: 5 + Math.floor(r() * 4), seed: r() * 9 }); }
    return a; })();
  const blob = (x, y, r, seed, n) => {
    g.beginPath();
    for (let i = 0; i <= 24; i++) { const a = i / 24 * Math.PI * 2, rr = r * (1 + .13 * Math.sin(a * n + seed) + .09 * Math.sin(a * 3 + seed * 2) + .04 * Math.sin(a * 11 + seed)); const px = x + Math.cos(a) * rr, py = y + Math.sin(a) * rr; i ? g.lineTo(px, py) : g.moveTo(px, py); }
    g.closePath(); g.fill();
  };
  O.studio = (t, dur = 6.5) => {
    const cx = W / 2, cy = 400;
    g.save();
    // фон: глубокий синий, мягкое пятно света, полутон
    const bg = g.createRadialGradient(cx, cy, 40, cx, cy, W * .75);
    bg.addColorStop(0, '#16213d'); bg.addColorStop(.55, '#0a0f1e'); bg.addColorStop(1, '#020308');
    g.fillStyle = bg; g.fillRect(0, 0, W, H);
    g.fillStyle = 'rgba(120,170,255,.06)';
    for (let y = 0; y < H; y += 22) for (let x = (y / 22) % 2 ? 11 : 0; x < W; x += 22) {
      const d = Math.hypot(x - cx, y - cy) / 900, r = 3.2 * (1 - d) * clamp(t / .6);
      if (r > .3) { g.beginPath(); g.arc(x, y, r, 0, 7); g.fill(); }
    }
    // всплеск краски
    const sp = t - 2.4;
    if (sp > 0) for (const s of splats) {
      const k = E.outBack(clamp((sp - s.dl) / .35)); if (k <= 0) continue;
      const d = s.d * E.outCubic(clamp((sp - s.dl) / .5));
      g.fillStyle = s.c; g.globalAlpha = .9;
      blob(cx + Math.cos(s.ang) * d, cy + Math.sin(s.ang) * d * .8, s.r * k, s.seed, s.blobs);
      for (let j = 1; j <= 3; j++) blob(cx + Math.cos(s.ang) * (d + s.r * (1.1 + j * .45)), cy + Math.sin(s.ang) * (d + s.r * (1.1 + j * .45)) * .8, s.r * .16 * k / j * 1.4, s.seed + j, 3);
      g.globalAlpha = 1;
    }
    if (sp > 0) {                      // ударная волна
      const k = clamp(sp / .45); g.strokeStyle = `rgba(255,255,255,${(1 - k) * .8})`; g.lineWidth = 10 * (1 - k) + 1;
      g.beginPath(); g.arc(cx, cy, 60 + k * 420, 0, 7); g.stroke();
    }
    // монограмма
    const draw = clamp((t - .5) / 1.9), total = GA.lens[0] + GA.lens[1];
    let L = E.inOutCubic(draw) * total, pen = null;
    const ink = clamp((t - 2.4) / .25), scale = 1 + .08 * Math.exp(-Math.max(0, sp) * 6) * (sp > 0 ? 1 : 0);
    g.translate(cx, cy); g.scale(scale, scale);
    g.lineCap = 'round'; g.lineJoin = 'round';
    const pass = (w, col, blur, dx = 0, dy = 0) => {
      g.strokeStyle = col; g.lineWidth = w; g.shadowColor = col; g.shadowBlur = blur;
      let rest = L;
      GA.strokes.forEach((st, i) => { if (rest <= 0) return; const pts = partial(st, Math.min(rest, GA.lens[i])); rest -= GA.lens[i];
        g.beginPath(); pts.forEach(([x, y], j) => j ? g.lineTo(x + dx, y + dy) : g.moveTo(x + dx, y + dy)); g.stroke(); pen = pts[pts.length - 1]; });
      g.shadowBlur = 0;
    };
    if (ink > 0) { g.globalAlpha = ink; pass(34, '#000', 0); pass(26, '#ff7b1c', 0, 9, 9); pass(26, '#ffffff', 0); g.globalAlpha = 1; }
    if (ink < 1) { g.globalAlpha = 1 - ink; pass(12, '#7ff8ff', 28); pass(4, '#ffffff', 0); g.globalAlpha = 1; }
    if (t > .35 && draw < 1 && pen) {  // светящийся кончик пера и искры
      const pk = clamp((t - .35) / .2);
      g.fillStyle = '#fff'; g.shadowColor = '#7ff8ff'; g.shadowBlur = 40; g.beginPath(); g.arc(pen[0], pen[1], 9 * pk, 0, 7); g.fill(); g.shadowBlur = 0;
      const r = rng(Math.floor(t * 30));
      for (let i = 0; i < 6; i++) { const a = r() * 7, d = 10 + r() * 34; g.fillStyle = `rgba(160,250,255,${.4 + r() * .6})`; g.fillRect(pen[0] + Math.cos(a) * d, pen[1] + Math.sin(a) * d, 3, 3); }
    } else if (t <= .5) {
      const pk = clamp((t - .15) / .3); const p0 = GA.strokes[0][0];
      g.fillStyle = '#fff'; g.shadowColor = '#7ff8ff'; g.shadowBlur = 40 * pk; g.beginPath(); g.arc(p0[0], p0[1], 9 * pk, 0, 7); g.fill(); g.shadowBlur = 0;
    }
    g.setTransform(1, 0, 0, 1, 0, 0);
    // название студии по буквам
    const word = 'GraphicArts', ty = 690;
    g.font = '900 112px Unbounded'; g.textBaseline = 'alphabetic';
    const widths = [...word].map(c => g.measureText(c).width), tw = widths.reduce((a, b) => a + b, 0);
    let x = cx - tw / 2, iTop = null;
    [...word].forEach((c, i) => {
      const k = clamp((t - 2.9 - i * .055) / .35); if (k <= 0) { x += widths[i]; return; }
      const s = E.outBack(k), lx = x + widths[i] / 2;
      if (c === 'i') iTop = [lx, ty - 112 * .78];
      g.save(); g.translate(lx, ty - (1 - k) * 40); g.scale(s, s); g.globalAlpha = clamp(k * 2);
      g.lineJoin = 'round'; g.lineWidth = 14; g.strokeStyle = '#000'; g.strokeText(c, -widths[i] / 2, 0);
      g.fillStyle = i < 7 ? '#ff7b1c' : '#3ff0ff'; g.fillText(c, -widths[i] / 2 + 6, 6);
      g.fillStyle = '#ffffff'; g.fillText(c, -widths[i] / 2, 0);
      g.restore(); x += widths[i];
    });
    // A N I M A T I O N
    const ak = E.outCubic(clamp((t - 3.55) / .6));
    if (ak > 0) {
      g.globalAlpha = ak; g.font = '700 40px Rubik'; g.fillStyle = '#7ff8ff'; g.textAlign = 'center';
      const spc = 12 + 20 * ak, letters = [...'ANIMATION'], ay = 770;
      letters.forEach((c, i) => g.fillText(c, cx + (i - (letters.length - 1) / 2) * (28 + spc), ay));
      const half = (letters.length / 2) * (28 + spc) + 30;
      g.fillRect(cx - half - 160 * ak, ay - 16, 160 * ak, 3); g.fillRect(cx + half, ay - 16, 160 * ak, 3);
      g.globalAlpha = 1;
    }
    // слоган, потом «представляет»
    const tg = Math.min(clamp((t - 4.0) / .4), 1 - clamp((t - 5.0) / .3));
    g.textAlign = 'center';
    if (tg > 0) { g.globalAlpha = tg; g.font = 'italic 500 32px Rubik'; g.fillStyle = '#c9d6ff'; g.fillText('Рисуем. Оживляем. Удивляем.', cx, 850); g.globalAlpha = 1; }
    const pr = clamp((t - 5.25) / .4);
    if (pr > 0) { g.globalAlpha = pr; g.font = '600 38px Rubik'; g.fillStyle = '#ffffff'; g.fillText('п р е д с т а в л я е т', cx, 860); g.globalAlpha = 1; }
    g.textAlign = 'left';
    // паучок на нити садится на точку над «i»
    if (iTop && t > 4.25 && t < 5.9) {
      const down = E.outBack(clamp((t - 4.3) / .55)), up = E.inQuad(clamp((t - 5.3) / .45));
      const sy = lerp(-30, iTop[1] - 46, down) - up * (iTop[1] + 80), sx = iTop[0] + 4 + Math.sin(t * 5) * 2;
      g.strokeStyle = 'rgba(220,240,255,.9)'; g.lineWidth = 2; g.beginPath(); g.moveTo(sx, 0); g.lineTo(sx, sy - 10); g.stroke();
      const wig = Math.sin(t * 24) * .2, land = clamp((t - 4.8) / .15) * (1 - up);
      g.save(); g.translate(sx, sy); g.scale(1.55, 1.55); g.translate(-sx, -sy);
      g.strokeStyle = '#05060a'; g.lineWidth = 3.5;
      for (const sd of [-1, 1]) for (let j = 0; j < 4; j++) {
        const a = (j - 1.5) * .45 + (j % 2 ? wig : -wig);
        const kx = sx + sd * (14 + j * 1.5), ky = sy - 4 + j * 4;
        g.beginPath(); g.moveTo(sx + sd * 6, sy + j * 3 - 4); g.lineTo(kx, ky - 10 + a * 10); g.lineTo(kx + sd * 8, ky + 8 + land * 4 + a * 6); g.stroke();
      }
      g.fillStyle = '#05060a'; g.beginPath(); g.ellipse(sx, sy + 6, 12, 14, 0, 0, 7); g.fill();
      g.beginPath(); g.arc(sx, sy - 10, 8, 0, 7); g.fill();
      g.fillStyle = '#3ff0ff'; g.beginPath(); g.arc(sx, sy + 6, 4, 0, 7); g.fill();       // знак на спинке
      g.fillStyle = '#fff'; for (const sd of [-1, 1]) { g.beginPath(); g.arc(sx + sd * 3.5, sy - 12, 2.6, 0, 7); g.fill(); }
      g.restore();
      if (t > 4.8 && t < 5.1) { const k = (t - 4.8) / .3; g.strokeStyle = `rgba(255,255,255,${1 - k})`; g.lineWidth = 3; g.beginPath(); g.arc(sx, sy + 28, 14 + k * 34, Math.PI * 1.1, Math.PI * 1.9); g.stroke(); }
    }
    // финальное затемнение
    g.globalAlpha = 1;
    const fo = clamp((t - (dur - .55)) / .5); if (fo > 0) { g.fillStyle = `rgba(0,0,0,${fo})`; g.fillRect(0, 0, W, H); }
    g.restore();
    O.vignette(.45);
  };

  // большой титр (имя серии, финальные карточки)
  O.title = (lines, a, o = {}) => {
    if (a <= 0) return;
    g.save(); g.globalAlpha = clamp(a); g.textAlign = 'center'; g.textBaseline = 'middle';
    for (const L of lines) {
      g.font = L.font; g.lineJoin = 'round';
      if (L.stroke) { g.lineWidth = L.stroke; g.strokeStyle = '#000'; g.strokeText(L.text, W / 2 + (L.dx || 0), L.y); }
      if (L.glow) { g.shadowColor = L.glow; g.shadowBlur = 30; }
      g.fillStyle = L.color || '#fff'; g.fillText(L.text, W / 2 + (L.dx || 0), L.y); g.shadowBlur = 0;
    }
    g.restore();
  };

  // заставка: паутина сплетается и в неё «врезается» логотип
  O.logo = (lt, o = {}) => {
    const cx = W / 2, cy = H / 2 - 30;
    g.save();
    const bg = g.createRadialGradient(cx, cy, 50, cx, cy, W * .7);
    bg.addColorStop(0, '#11283a'); bg.addColorStop(1, '#03050b');
    g.globalAlpha = o.bgAlpha ?? 1; g.fillStyle = bg; g.fillRect(0, 0, W, H); g.globalAlpha = 1;
    // паутина
    const spokes = 16, rings = 11, grow = E.outCubic(clamp(lt / 1.1));
    g.strokeStyle = 'rgba(127,248,255,.85)'; g.shadowColor = '#3ff0ff'; g.shadowBlur = 14; g.lineWidth = 2.5;
    const R = W * .62 * grow;
    for (let i = 0; i < spokes; i++) {
      const a = i / spokes * Math.PI * 2 + .1;
      g.beginPath(); g.moveTo(cx, cy); g.lineTo(cx + Math.cos(a) * R, cy + Math.sin(a) * R * .75); g.stroke();
    }
    for (let j = 1; j <= rings; j++) {
      const rr = j / rings * W * .6, k = clamp((lt - .15 - j * .06) / .3);
      if (k <= 0) continue;
      g.globalAlpha = k * (1 - j / rings * .5);
      g.beginPath();
      for (let i = 0; i <= spokes; i++) {
        const a0 = (i - 1) / spokes * Math.PI * 2 + .1, a1 = i / spokes * Math.PI * 2 + .1, am = (a0 + a1) / 2;
        const p1 = [cx + Math.cos(a1) * rr, cy + Math.sin(a1) * rr * .75];
        const pm = [cx + Math.cos(am) * rr * .88, cy + Math.sin(am) * rr * .75 * .88];
        if (i === 0) g.moveTo(...p1); else g.quadraticCurveTo(...pm, ...p1);
      }
      g.stroke();
    }
    g.globalAlpha = 1; g.shadowBlur = 0;
    // удар логотипа
    const s = lerp(2.6, 1, E.outExpo(clamp((lt - .55) / .45))), la = clamp((lt - .55) / .12);
    if (la > 0) {
      const sh = lt < 1.2 ? (Math.random() - .5) * 0 : 0;
      g.save(); g.translate(cx, cy); g.scale(s, s); g.globalAlpha = la;
      g.textAlign = 'center'; g.textBaseline = 'middle'; g.lineJoin = 'round';
      g.font = '900 190px Unbounded';
      g.lineWidth = 26; g.strokeStyle = '#000'; g.strokeText('ПАУК', 0, -95);
      g.fillStyle = '#e8343c'; g.fillText('ПАУК', 0, -95);
      g.font = '900 118px Unbounded';
      g.lineWidth = 20; g.strokeText('НОВОГРАДА', 0, 70);
      const gr = g.createLinearGradient(0, 20, 0, 120); gr.addColorStop(0, '#9ffcff'); gr.addColorStop(1, '#1fb8d8');
      g.fillStyle = gr; g.fillText('НОВОГРАДА', 0, 70);
      g.restore();
    }
    if (o.sub) {
      const sa = clamp((lt - 1.4) / .4);
      g.globalAlpha = sa; g.textAlign = 'center'; g.font = '700 46px Unbounded'; g.fillStyle = '#ffffff';
      g.lineWidth = 8; g.strokeStyle = '#000'; g.strokeText(o.sub, cx, cy + 250); g.fillText(o.sub, cx, cy + 250);
    }
    // вспышка удара
    const fl = Math.exp(-Math.pow((lt - .58) / .08, 2));
    g.globalAlpha = fl * .9; g.fillStyle = '#fff'; g.fillRect(0, 0, W, H);
    g.restore();
  };

  return O;
}

function roundRect(g, x, y, w, h, r) {
  g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();
}
