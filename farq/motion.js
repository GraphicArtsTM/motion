/* «Farqi nimada?» — reels 1080×1920.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Тайминги сцен и слов — из timeline.js (его пишет tts.py по реальной озвучке),
   рисованные сцены — scenes.js, персонажи и предметы — art.js. */
'use strict';

const W = 1080, H = 1920;
const TL = window.TL, DUR = TL.duration;
const $ = s => document.querySelector(s);
const clamp = (x, a = 0, b = 1) => x < a ? a : x > b ? b : x;
const lerp = (a, b, k) => a + (b - a) * k;

/* ---------- изинги ---------- */
const E = {
  lin: x => x,
  inQuad: x => x * x,
  outQuad: x => 1 - (1 - x) * (1 - x),
  inCubic: x => x * x * x,
  outCubic: x => 1 - Math.pow(1 - x, 3),
  inOutCubic: x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2,
  outQuint: x => 1 - Math.pow(1 - x, 5),
  inExpo: x => x <= 0 ? 0 : Math.pow(2, 10 * x - 10),
  outExpo: x => x >= 1 ? 1 : 1 - Math.pow(2, -10 * x),
  outBack: x => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outBackS: x => { const c1 = 2.6, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
};
const P = (t, t0, d) => clamp((t - t0) / d);
/* ключевые кадры: [[t, v], [t, v, ease], ...] */
function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, e] = keys[i], [t0, v0] = keys[i - 1];
    if (t <= t1) return lerp(v0, v1, (e || E.outExpo)(P(t, t0, Math.max(1e-6, t1 - t0))));
  }
  return keys[keys.length - 1][1];
}
/* всплеск 0→1→0 вокруг момента */
const pulse = (t, t0, up = .08, down = .5) => t < t0 - up || t > t0 + down ? 0 : t < t0 ? E.outQuad(P(t, t0 - up, up)) : 1 - E.outCubic(P(t, t0, down));
function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}

/* ---------- цвет ---------- */
const hex = c => [1, 3, 5].map(i => parseInt(c.slice(i, i + 2), 16));
const rgb = (a, al = 1) => `rgba(${a.map(v => Math.round(v)).join(',')},${al})`;
const mix = (a, b, k) => a.map((v, i) => lerp(v, b[i], k));
const lighten = (a, k) => mix(a, [255, 255, 255], k);

/* ---------- трансформ: (x, y) — центр элемента на кадре ---------- */
function S(el, o) {
  let tr = 'translate(-50%,-50%) translate3d(' + (o.x || 0).toFixed(2) + 'px,' + (o.y || 0).toFixed(2) + 'px,0)';
  if (o.ry) tr += ' perspective(1600px) rotateY(' + o.ry.toFixed(3) + 'deg)';
  if (o.r) tr += ' rotate(' + o.r.toFixed(3) + 'deg)';
  if (o.sk) tr += ' skewX(' + o.sk.toFixed(3) + 'deg)';
  const sx = o.sx != null ? o.sx : o.s != null ? o.s : 1, sy = o.sy != null ? o.sy : o.s != null ? o.s : 1;
  if (sx !== 1 || sy !== 1) tr += ' scale(' + sx.toFixed(4) + ',' + sy.toFixed(4) + ')';
  el.style.transform = tr;
  vis(el, o.o == null ? 1 : o.o);
  let f = '';
  if (o.b > .05) f += 'blur(' + o.b.toFixed(2) + 'px) ';
  if (o.br != null && o.br !== 1) f += 'brightness(' + o.br.toFixed(3) + ') ';
  el.style.filter = f || 'none';
}
function vis(el, op) {
  op = clamp(op);
  el.style.opacity = op;
  el.style.visibility = op <= .001 ? 'hidden' : 'visible';
}
/* полноэкранный слой (сцена): сдвиг, масштаб, размытие, яркость */
function layer(el, o) {
  el.style.transform = `translate3d(${(o.x || 0).toFixed(1)}px,${(o.y || 0).toFixed(1)}px,0) scale(${(o.s || 1).toFixed(4)})`;
  let f = '';
  if (o.b > .05) f += `blur(${o.b.toFixed(1)}px) `;
  if (o.br != null && o.br !== 1) f += `brightness(${o.br.toFixed(3)}) `;
  if (o.sat != null && o.sat !== 1) f += `saturate(${o.sat.toFixed(3)})`;
  el.style.filter = f || 'none';
  vis(el, o.o == null ? 1 : o.o);
}
function h(tag, cls, html, parent) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}
function fit(el, maxW) {
  const fs = parseFloat(getComputedStyle(el).fontSize);
  const w = el.scrollWidth;
  if (w > maxW) el.style.fontSize = (fs * maxW / w).toFixed(1) + 'px';
}
/* группа сцены; при сборке видима, чтобы fit() мог измерить текст */
function grp(parent) { const g = h('div', 'grp', null, parent); g.style.display = 'block'; return g; }
function sceneSvg(parent) {
  const d = h('div', 'scn', null, parent);
  const s = sv('svg', { viewBox: '0 0 1080 1920', width: 1080, height: 1920 }, d);
  return { d, s };
}

const ICO = {
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.6 4.5L19 7"/></svg>',
  save: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"><path d="M6 3.5h12v17l-6-4.2-6 4.2Z"/></svg>',
  share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"><path d="M21 3 10 14"/><path d="M21 3 14.5 21l-4-7.5L3 9.5Z"/></svg>',
  plus: '<svg viewBox="0 0 24 24" width="40" height="40" fill="none" stroke="currentColor" stroke-width="3.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
};

/* ---------- субтитры: по 2–3 слова, текущее слово на плашке ---------- */
const nrm = w => w.toLowerCase().replace(/[^\p{L}\p{N}‘’ʻʼ']/gu, '');
function chunksOf(words) {
  const out = []; let cur = [];
  for (const w of words) {
    cur.push(w);
    const len = cur.map(x => x.w).join(' ').length;
    if (cur.length >= 3 || len >= 14 || /[,.!?;:]$/.test(w.w)) { out.push(cur); cur = []; }
  }
  if (cur.length) out.push(cur);
  return out;
}
function makeCap(parent, line, keyIdx = [], skip = 0) {
  const box = h('div', 'ccap a', null, parent);
  const kset = new Set(keyIdx.flat().map(i => i + skip));
  let wi = 0;
  const cs = chunksOf(line.words).map(ch => {
    const el = h('div', 'chunk', null, box);
    const ws = ch.map(w => {
      const s = h('span', 'cw', null, el);
      s.textContent = w.w.replace(/[.,!?;:]+$/, '');
      el.appendChild(document.createTextNode(' '));
      return { el: s, t0: w.t0, t1: w.t1, key: kset.has(wi++) };
    });
    el.style.width = 'max-content';
    const wpx = el.offsetWidth;
    el.style.width = '';
    if (wpx > 930) el.style.fontSize = (84 * 930 / wpx).toFixed(1) + 'px';
    return { el, ws, t0: ch[0].t0 };
  });
  return { box, cs, line };
}
function drawCap(c, t, col, y, fade = 1) {
  S(c.box, { x: 540, y, o: fade });
  const n = c.cs.length;
  c.cs.forEach((ch, i) => {
    const t0 = ch.t0 - .08, t1 = i + 1 < n ? c.cs[i + 1].t0 - .08 : c.line.t1 + .45;
    const on = t >= t0 && t < t1;
    ch.el.style.display = on ? 'block' : 'none';
    if (!on) return;
    const p = E.outBackS(P(t, t0, .2));
    ch.el.style.transform = `translateY(${((1 - p) * 30).toFixed(1)}px) scale(${(.75 + .25 * p).toFixed(4)}) rotate(${((1 - p) * (i % 2 ? 3 : -3)).toFixed(2)}deg)`;
    ch.el.style.opacity = clamp(p * 2).toFixed(3);
    for (const w of ch.ws) {
      const cur = t >= w.t0 - .04 && t < w.t1 + .02;
      const said = t >= w.t0 - .04;
      w.el.style.background = cur ? rgb(col) : 'transparent';
      w.el.style.color = cur ? '#0B0912' : w.key && said ? rgb(lighten(col, .15)) : said ? '#fff' : 'rgba(255,255,255,.62)';
      w.el.style.transform = `scale(${(1 + .1 * pulse(t, w.t0 + .03, .05, .25)).toFixed(4)})`;
      w.el.style.textShadow = cur ? 'none' : '';
    }
  });
}

/* ---------- сборка ---------- */
const root = $('#root'), cam = $('#cam'), L = $('#L'), OV = $('#OV');
const PAL0 = ['#FF4D5E', '#FFB020'];
let SC = [], grainEl;
const scenes = TL.scenes;
const pairs = scenes.filter(s => s.type === 'pair');

function buildIntro(sc) {
  const el = grp(L);
  const art = sceneSvg(el); const scene = SCENES.intro(art.s);
  const ov = grp(OV);
  const tag = h('div', 'tag a', TL.title, ov);
  const t1 = h('div', 'dis a', '2 SO‘Z', ov); t1.id = 't1';
  const t2 = h('div', 'dis a grad', '1 FARQ', ov); t2.id = 't2';
  fit(t1, 960); fit(t2, 960);
  const caps = sc.lines.map(ln => makeCap(ov, ln));
  return { sc, el, ov, art, scene, tag, t1, t2, caps };
}

function buildPair(sc) {
  const [cA, cB] = sc.colors.map(hex);
  const el = grp(L);
  const ov = grp(OV);
  // столкновение
  const clash = grp(el);
  const cbg = sceneSvg(clash);
  cbg.s.innerHTML = `<rect x="0" y="0" width="1080" height="1920" fill="#0B0912"/>
    <path d="M0 0 H1080 V700 L0 1220Z" fill="${sc.colors[0]}" opacity=".9"/><path d="M0 1220 L1080 700 V1920 H0Z" fill="${sc.colors[1]}" opacity=".9"/>`;
  const rays = svh(RAYS('rgba(255,255,255,.12)', 22, 1600), cbg.s);
  const halftone = svh(`<rect width="1080" height="1920" fill="${pattern(22, 22, '<circle cx="11" cy="11" r="3.2" fill="#000" opacity=".22"/>')}"/>`, cbg.s);
  const lines = svh(Array.from({ length: 18 }, (_, i) => `<rect class="sl" x="0" y="${60 + i * 105}" width="${200 + (i * 137) % 300}" height="${6 + i % 3 * 3}" rx="4" fill="#fff" opacity=".35"/>`).join(''), cbg.s);
  const num = h('div', 'num a', String(sc.i + 1).padStart(2, '0'), ov);
  const wA = h('div', 'dis a ex', sc.a.term, ov), wB = h('div', 'dis a ex', sc.b.term, ov);
  wA.style.cssText = 'font-size:150px;color:#fff'; wB.style.cssText = 'font-size:150px;color:#fff';
  fit(wA, 960); fit(wB, 960);
  const vs = h('div', 'vs a', `<svg viewBox="-110 -110 220 220"><path fill="#FFE94A" stroke="#0B0912" stroke-width="7" stroke-linejoin="round" d="${(() => {
    let d = ''; for (let i = 0; i < 24; i++) { const a = i / 24 * Math.PI * 2, r = i % 2 ? 70 : 104; d += (i ? 'L' : 'M') + (r * Math.cos(a)).toFixed(1) + ' ' + (r * Math.sin(a)).toFixed(1); } return d + 'Z'; })()}"/></svg><b>VS</b>`, ov);
  const q = makeCap(ov, sc.q);
  // сцены
  const mkScene = (key, c, idx) => {
    const d = sc[key];
    const art = sceneSvg(el);
    const scene = SCENES[d.icon](art.s, sc.colors[idx - 1], c);
    const ban = h('div', 'ban a', `<i>${idx}-tushuncha</i><b>${d.term}</b>`, ov);
    ban.querySelector('b').style.background = rgb(c);
    fit(ban.querySelector('b'), 900);
    const cap = makeCap(ov, d.line, d.keys, 1);
    const stk = d.keys.map((ki, j) => {
      const txt = ki.map(i => d.line.words[i + 1].w.replace(/[.,!?;:]+$/, '')).join(' ');
      const s = h('div', 'stk a', txt.toLocaleUpperCase('uz'), ov);
      s.style.color = rgb(mix(c, [0, 0, 0], .15));
      s.style.boxShadow = `10px 12px 0 ${rgb(c)}`;
      fit(s, 900);
      return { s, t0: d.kt[j], j };
    });
    return { d, c, art, scene, ban, cap, stk };
  };
  const A = mkScene('a', cA, 1), B = mkScene('b', cB, 2);
  // итог
  const sum = grp(ov);
  const st = h('div', 'sumt a', 'Qisqa farq', sum);
  const blk = (d, c) => {
    const b = h('div', 'blk a', null, sum);
    b.style.background = `linear-gradient(135deg,${rgb(c, .32)},rgba(20,16,32,.92) 62%)`;
    b.style.borderColor = rgb(c, .6);
    const bt = h('div', 'bt', d.term, b); bt.style.color = rgb(lighten(c, .1));
    const chips = h('div', 'chips', null, b);
    const cs = d.chips.map(x => {
      const ch = h('div', 'chip', `<i>${ICO.check}</i>${x}`, chips);
      ch.querySelector('i').style.cssText = `background:${rgb(c)};color:#0B0912`;
      return ch;
    });
    return { b, bt, cs };
  };
  const bA = blk(sc.a, cA), bB = blk(sc.b, cB);
  const neq = h('div', 'neq a', '≠', sum);
  return { sc, cA, cB, el, ov, clash, rays, lines, halftone, num, wA, wB, vs, q, A, B, sum, st, bA, bB, neq };
}

function buildOutro(sc) {
  const el = grp(L);
  const art = sceneSvg(el); const scene = SCENES.outro(art.s);
  const ov = grp(OV);
  const tag = h('div', 'sumt a', 'Eslab qoling', ov);
  const rec = pairs.map(p => h('div', 'recap a', `<span style="color:${p.colors[0]}">${p.a.term}</span><em>≠</em><span style="color:${p.colors[1]}">${p.b.term}</span>`, ov));
  rec.forEach(r => fit(r, 900));
  const act = (ico, txt) => { const a = h('div', 'act a', `<div class="ic">${ico}</div><span>${txt}</span>`, ov); return { a, ic: a.querySelector('.ic') }; };
  const sv_ = act(ICO.save, 'Saqlang'), sh = act(ICO.share, 'Ulashing');
  const fol = h('div', 'a', `${ICO.plus}<span>Obuna bo‘ling</span>`, ov); fol.id = 'follow';
  const caps = sc.lines.map(ln => makeCap(ov, ln));
  const wt = re => { for (const ln of sc.lines) for (const w of ln.words) if (re.test(nrm(w.w))) return w.t0; return sc.t0 + 1; };
  return { sc, el, ov, art, scene, tag, rec, sv: sv_, sh, fol, caps, tSave: wt(/^saqlab/), tShare: wt(/^ulashing/), tFol: wt(/^obuna/) };
}

function init() {
  DEFS = $('#defs');
  const g = document.createElement('canvas'); g.width = g.height = 256;
  const gx = g.getContext('2d'), id = gx.createImageData(256, 256), gr = rng(5);
  for (let i = 0; i < id.data.length; i += 4) { const v = gr() * 255; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255; }
  gx.putImageData(id, 0, 0);
  grainEl = $('#grain'); grainEl.style.backgroundImage = `url(${g.toDataURL()})`;
  $('#brand span').textContent = TL.title;
  pairs.forEach(() => h('div', '', '<i></i>', $('#bars')));
  SC = scenes.map(sc => sc.type === 'intro' ? buildIntro(sc) : sc.type === 'pair' ? buildPair(sc) : buildOutro(sc));
}

/* ---------- палитра во времени ---------- */
function palette(t) {
  let pal = PAL0.map(hex);
  for (const p of pairs) {
    const k = E.inOutCubic(P(t, p.t0 - .3, .6)) - E.inOutCubic(P(t, p.t1 - .3, .6));
    if (k > 0) pal = pal.map((c, i) => mix(c, hex(p.colors[i]), k));
  }
  return pal;
}
const CUTS = scenes.slice(1).map(s => s.t0);
function wipeAt(t) {
  for (const c of CUTS) if (t > c - .42 && t < c + .42) return [c, (t - c) / .42];
  return null;
}

/* ---------- кадр ---------- */
function renderAt(t) {
  const pal = palette(t);
  root.style.setProperty('--A', rgb(pal[0]));
  root.style.setProperty('--B', rgb(pal[1]));
  // удары камеры
  let shake = 0;
  for (const p of pairs) shake += pulse(t, p.t0 + .3, .01, .5) * 22 + pulse(t, p.sum + .35, .01, .35) * 8;
  const sr = rng(Math.floor(t * 60));
  cam.style.transform = `translate(${((sr() - .5) * shake).toFixed(2)}px,${((sr() - .5) * shake).toFixed(2)}px)`;
  const gr = rng(Math.floor(t * 30) + 1);
  grainEl.style.backgroundPosition = `${Math.floor(gr() * 256)}px ${Math.floor(gr() * 256)}px`;
  let fl = 0;
  for (const p of pairs) fl += pulse(t, p.t0 + .3, .02, .3) * .6;
  fl += pulse(t, .18, .02, .35) * .7;
  vis($('#flash'), fl);
  // HUD
  const first = pairs[0], last = pairs[pairs.length - 1];
  vis($('#hud'), P(t, first.t0, .5) * (1 - P(t, last.t1, .4)));
  const cur = pairs.reduce((a, p, i) => t >= p.t0 - .01 ? i : a, 0);
  $('#count').innerHTML = `<b>${cur + 1}</b><span>/${pairs.length}</span>`;
  [...$('#bars').children].forEach((b, i) => { b.firstChild.style.width = (P(t, pairs[i].t0, pairs[i].t1 - pairs[i].t0) * 100).toFixed(2) + '%'; });
  // затемнения сверху/снизу под текст
  let sT = 0, sB = 0;
  for (const s of SC) {
    const on = t >= s.sc.t0 - .01 && t < s.sc.t1;
    s.el.style.display = on ? 'block' : 'none';
    s.ov.style.display = on ? 'block' : 'none';
    if (!on) continue;
    if (s.sc.type === 'intro') { drawIntro(s, t, pal); sT = 1; sB = 1; }
    else if (s.sc.type === 'pair') { const r = drawPair(s, t); sT = r[0]; sB = r[1]; }
    else { drawOutro(s, t, pal); sT = .7; sB = 1; }
  }
  vis($('#scrimT'), sT); vis($('#scrimB'), sB);
  // шторка
  const wp = wipeAt(t), wipe = $('#wipe');
  if (wp) {
    const [c, k] = wp;
    const nxt = scenes.find(s => s.t0 === c);
    const cols = nxt.type === 'pair' ? nxt.colors : PAL0;
    $('#wA').style.cssText = `top:0;height:1560px;background:${cols[0]}`;
    $('#wB').style.cssText = `top:1560px;height:1560px;background:${cols[1]}`;
    const y = k < 0 ? lerp(H / 2 + 3300, H / 2, E.outCubic(k + 1)) : lerp(H / 2, H / 2 - 3300, E.inCubic(k));
    S(wipe, { x: W / 2, y, r: -12 });
  } else vis(wipe, 0);
}

function drawIntro(s, t, pal) {
  const end = s.sc.t1, out = E.inCubic(P(t, end - .45, .45));
  s.scene.update(t, [], end, t);
  layer(s.art.d, { s: 1 + out * .2, b: out * 12, o: 1 });
  const a1 = P(t, .12, .32), a2 = P(t, .5, .32);
  S(s.t1, { x: 540 + Math.sin(t * 2) * 4, y: 470 - out * 120, s: lerp(2.6, 1, E.outExpo(a1)) * (1 + out * .4), o: (a1 > 0 ? 1 : 0) * (1 - out), b: (1 - E.outCubic(a1)) * 20 + out * 14 });
  S(s.t2, { x: 540, y: 690 - out * 60, s: lerp(2.6, 1, E.outExpo(a2)) * (1 + out * .5), o: (a2 > 0 ? 1 : 0) * (1 - out), b: (1 - E.outCubic(a2)) * 20 + out * 14 });
  S(s.tag, { x: 540, y: 300 - (1 - E.outCubic(P(t, .9, .5))) * 30, o: P(t, .9, .4) * (1 - out) });
  s.caps.forEach(c => drawCap(c, t, pal[0], 1560, 1 - out));
}

function drawScene(C, t, tin, tout) {
  const lt = t - tin;
  C.scene.update(lt, C.d.kt.map(x => x - tin), tout - tin, t);
  // баннер термина
  const bp = E.outBackS(P(t, tin + .1, .5));
  const bump = pulse(t, C.d.line.words[0].t0 + .05, .06, .4);
  S(C.ban, { x: 540, y: 400 - (1 - bp) * 160, s: (.9 + .1 * bp) * (1 + .07 * bump), o: P(t, tin + .1, .2), r: (1 - bp) * -6 });
  // стикеры ключевых слов
  C.stk.forEach((k, j) => {
    const nx = C.stk[j + 1];
    const t1 = nx ? Math.min(k.t0 + 1.5, nx.t0 - .05) : k.t0 + 1.5;
    const p = E.outBackS(P(t, k.t0 - .05, .35)), o = E.inCubic(P(t, t1 - .15, .15));
    const rot = [-4, 3, -2][j % 3];
    S(k.s, { x: 540 + [-30, 40, 0][j % 3], y: 610, s: lerp(1.8, 1, p) * (1 - o * .3), r: rot + (1 - p) * rot * 3, o: clamp(p * 3) * (1 - o) });
  });
  drawCap(C.cap, t, C.c, 1560);
}

function drawPair(s, t) {
  const sc = s.sc, T0 = sc.t0, TA = sc.a.t0, TB = sc.b.t0, TS = sc.sum;
  const hit = T0 + .3;
  // — столкновение —
  const cOut = E.inCubic(P(t, TA - .1, .4));
  if (t < TA + .4) {
    s.clash.style.display = 'block';
    layer(s.clash, { s: 1 + cOut * .5, b: cOut * 10, o: 1 - cOut });
    s.rays.setAttribute('transform', `translate(540 960) rotate(${(t * 25).toFixed(1)}) scale(${(1 + .1 * pulse(t, hit, .02, .5)).toFixed(3)})`);
    [...s.lines.children].forEach((l, i) => l.setAttribute('x', (((t * (900 + i * 60) + i * 230) % 1600) - 400).toFixed(1)));
    const np = E.outBackS(P(t, T0 + .05, .5));
    S(s.num, { x: 540, y: 470 - cOut * 80, s: np * (1 - cOut * .3), r: (1 - np) * -120, o: np * (1 - cOut) });
    const appr = E.inQuad(P(t, T0, .3)), rec = pulse(t, hit, .001, .45), fl = Math.sin(t * 2.2) * 6;
    const zp = 1 + .08 * pulse(t, hit, .01, .6);
    S(s.wA, { x: lerp(-700, 540, appr) - rec * 40, y: 760 + fl, sk: rec * -14, s: zp, o: (t >= T0 ? 1 : 0) * (1 - cOut), r: -4 });
    S(s.wB, { x: lerp(1780, 540, appr) + rec * 40, y: 1090 - fl, sk: rec * 14, s: zp, o: (t >= T0 ? 1 : 0) * (1 - cOut), r: -4 });
    const vp = E.outBackS(P(t, hit, .45));
    S(s.vs, { x: 540, y: 925, s: vp * (1 + .06 * Math.sin(t * 9)) * (1 - cOut * .4), r: (1 - vp) * -25, o: vp * (1 - cOut) });
    s.vs.querySelector('svg').style.transform = `rotate(${((1 - vp) * 200 + t * 30).toFixed(2)}deg)`;
    drawCap(s.q, t, s.cB, 1400, 1 - cOut);
  } else { s.clash.style.display = 'none'; [s.num, s.wA, s.wB, s.vs, s.q.box].forEach(e => vis(e, 0)); }

  // — сцена A: въезжает зумом, уезжает хлёстким панорамированием —
  const wip = P(t, TB - .18, .45);
  const aOn = t >= TA - .12 && t < TB + .3;
  s.A.art.d.style.display = aOn ? 'block' : 'none';
  if (aOn) {
    const zin = E.outExpo(P(t, TA - .12, .55));
    layer(s.A.art.d, { s: lerp(1.35, 1, zin), b: (1 - zin) * 16 + wip * 40, x: -E.inCubic(wip) * 1150, o: clamp(zin * 2) });
    drawScene(s.A, t, TA, TB);
  }
  const showA = t >= TA - .1 && t < TB + .1;
  [s.A.ban, s.A.cap.box, ...s.A.stk.map(k => k.s)].forEach(e => { if (!showA) vis(e, 0); });
  if (showA && t > TB - .2) { const o = 1 - P(t, TB - .2, .25); [s.A.ban, s.A.cap.box].forEach(e => vis(e, parseFloat(e.style.opacity) * o)); }

  // — сцена B; на итоге уходит в размытый фон —
  const bOn = t >= TB - .18;
  s.B.art.d.style.display = bOn ? 'block' : 'none';
  const sumP = E.inOutCubic(P(t, TS - .1, .5));
  if (bOn) {
    layer(s.B.art.d, { x: (1 - E.outCubic(wip)) * 1150, b: (1 - wip) * 40 + sumP * 18, s: 1 + sumP * .06, br: 1 - .55 * sumP, sat: 1 - .4 * sumP });
    if (t < TS + .6) drawScene(s.B, t, TB, TS);
    else s.B.scene.update(t - TB, s.B.d.kt.map(x => x - TB), TS - TB, t);
  }
  const showB = t >= TB + .05 && t < TS + .2;
  [s.B.ban, s.B.cap.box, ...s.B.stk.map(k => k.s)].forEach(e => { if (!showB) vis(e, 0); });
  if (showB && t > TS - .15) { const o = 1 - P(t, TS - .15, .25); [s.B.ban, s.B.cap.box, ...s.B.stk.map(k => k.s)].forEach(e => vis(e, parseFloat(e.style.opacity) * o)); }

  // — итог —
  if (t >= TS - .05) {
    s.sum.style.display = 'block';
    const hA = s.bA.b.offsetHeight, hB = s.bB.b.offsetHeight;
    const gap = 120, top = Math.max(420, 990 - (hA + gap + hB) / 2);
    const yA = top + hA / 2, yB = top + hA + gap + hB / 2;
    const pA = E.outExpo(P(t, TS + .05, .6)), pB = E.outExpo(P(t, TS + .2, .6));
    S(s.st, { x: 540, y: top - 50, o: P(t, TS + .1, .3) });
    S(s.bA.b, { x: 540 + (1 - pA) * -1100, y: yA, r: (1 - pA) * -8, o: pA > 0 ? 1 : 0 });
    S(s.bB.b, { x: 540 + (1 - pB) * 1100, y: yB, r: (1 - pB) * 8, o: pB > 0 ? 1 : 0 });
    const np = E.outBackS(P(t, TS + .35, .5));
    S(s.neq, { x: 540, y: top + hA + gap / 2, s: np * (1 + .05 * Math.sin(t * 6)), r: (1 - np) * -180, o: np });
    const chipAnim = (cs, t0) => cs.forEach((c, i) => {
      const p = E.outBackS(P(t, t0 + i * .12, .45));
      c.style.transform = `translateY(${((1 - p) * 30).toFixed(1)}px) scale(${p.toFixed(4)})`;
      c.style.opacity = clamp(p * 1.5).toFixed(3);
    });
    chipAnim(s.bA.cs, TS + .45);
    chipAnim(s.bB.cs, TS + .7);
  } else s.sum.style.display = 'none';
  const inScene = t >= TA && t < TS;
  return [inScene ? 1 : t >= TS ? .4 : 0, inScene ? 1 : t < TA ? .6 : 0];
}

function drawOutro(s, t, pal) {
  const T0 = s.sc.t0;
  s.scene.update(t - T0, [], s.sc.t1 - T0, t);
  S(s.tag, { x: 540, y: 380, o: P(t, T0 + .2, .4) });
  s.rec.forEach((r, i) => {
    const p = E.outExpo(P(t, T0 + .25 + i * .12, .6));
    S(r, { x: 540 + (1 - p) * (i % 2 ? 1100 : -1100), y: 480 + i * 124, o: p > 0 ? 1 : 0 });
  });
  const pop_ = (o, t0, x) => {
    const p = E.outBackS(P(t, t0 - .15, .5)), b = pulse(t, t0 + .1, .05, .45);
    S(o.a, { x, y: 1085, s: p * (1 + .12 * b), o: p });
    o.ic.style.borderColor = rgb(pal[0], .3 + .7 * clamp(b + P(t, t0, .3) * .4));
    o.ic.style.color = rgb(mix([244, 242, 255], lighten(pal[0], .2), P(t, t0, .3)));
  };
  pop_(s.sv, s.tSave, 380);
  pop_(s.sh, s.tShare, 700);
  const fp = E.outBackS(P(t, s.tFol - .15, .5));
  S(s.fol, { x: 540, y: 1300, s: fp * (1 + .04 * Math.sin((t - s.tFol) * 7) * P(t, s.tFol + .4, .3)), o: fp });
  s.caps.forEach(c => drawCap(c, t, pal[1], 1490));
}

window.DURATION = DUR;
window.renderAt = renderAt;
window.ready = document.fonts.ready.then(() => Promise.all([...document.fonts].map(f => f.load()))).then(() => {
  init();
  renderAt(0);
});

/* предпросмотр: index.html — по кругу, index.html?t=12.5 — стоп-кадр */
if (!navigator.webdriver) {
  window.ready.then(() => {
    const q = new URLSearchParams(location.search);
    if (q.has('t')) return renderAt(+q.get('t'));
    const t0 = performance.now();
    const loop = () => { renderAt(((performance.now() - t0) / 1000) % DUR); requestAnimationFrame(loop); };
    loop();
  });
}
