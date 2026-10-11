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
