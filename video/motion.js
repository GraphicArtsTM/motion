/* Muhr — промо-ролик 1080×1350.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Темп музыки 120 BPM: доля = 0,5 с, такт = 2 с. Сцены стоят на тактовой сетке. */
'use strict';

const W = 1080, H = 1350, DUR = 32;
const $ = s => document.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
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
  inOutExpo: x => x <= 0 ? 0 : x >= 1 ? 1 : x < .5 ? Math.pow(2, 20 * x - 10) / 2 : (2 - Math.pow(2, -20 * x + 10)) / 2,
  outBack: x => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outBackS: x => { const c1 = 2.4, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outElastic: x => x <= 0 ? 0 : x >= 1 ? 1 : Math.pow(2, -10 * x) * Math.sin((x * 10 - .75) * (2 * Math.PI) / 3) + 1,
};
const P = (t, t0, d) => clamp((t - t0) / d);
const tw = (t, t0, d, a, b, e = E.outExpo) => lerp(a, b, e(P(t, t0, d)));
/* ключевые кадры: [[t, v], [t, v, ease], ...] */
function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, e] = keys[i], [t0, v0] = keys[i - 1];
    if (t <= t1) return lerp(v0, v1, (e || E.outExpo)(P(t, t0, t1 - t0)));
  }
  return keys[keys.length - 1][1];
}

/* ---------- детерминированный рандом ---------- */
function rng(seed) {
  return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed);
    x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
}

/* ---------- трансформ элемента: (x, y) — центр элемента на кадре ---------- */
function S(el, o) {
  let tr = 'translate(-50%,-50%) translate3d(' + (o.x || 0).toFixed(2) + 'px,' + (o.y || 0).toFixed(2) + 'px,' + (o.z || 0).toFixed(2) + 'px)';
  if (o.rx) tr += ' rotateX(' + o.rx.toFixed(3) + 'deg)';
  if (o.ry) tr += ' rotateY(' + o.ry.toFixed(3) + 'deg)';
  if (o.r) tr += ' rotate(' + o.r.toFixed(3) + 'deg)';
  if (o.sk) tr += ' skewX(' + o.sk.toFixed(3) + 'deg)';
  const sx = o.sx != null ? o.sx : o.s != null ? o.s : 1, sy = o.sy != null ? o.sy : o.s != null ? o.s : 1;
  if (sx !== 1 || sy !== 1) tr += ' scale(' + sx.toFixed(4) + ',' + sy.toFixed(4) + ')';
  el.style.transform = tr;
  const op = o.o == null ? 1 : clamp(o.o);
  el.style.opacity = op;
  el.style.visibility = op <= 0.001 ? 'hidden' : 'visible';
  let f = '';
  if (o.b > .05) f += 'blur(' + o.b.toFixed(2) + 'px) ';
  if (o.br != null && o.br !== 1) f += 'brightness(' + o.br.toFixed(3) + ') ';
  if (o.f) f += o.f;
  el.style.filter = f || 'none';
}
/* сырой трансформ для вложенных элементов */
function T(el, tr, op) {
  el.style.transform = tr;
  if (op != null) { el.style.opacity = clamp(op); }
}

/* ---------- данные и иконки из прототипа Muhr ---------- */
const STAR_P = 'M12 2 L13.65 8.03 L19.07 4.93 L15.97 10.35 L22 12 L15.97 13.65 L19.07 19.07 L13.65 15.97 L12 22 L10.35 15.97 L4.93 19.07 L8.03 13.65 L2 12 L8.03 10.35 L4.93 4.93 L10.35 8.03 Z';
const SEAL_P = 'M50 4 L58.42 29.67 L82.53 17.47 L70.33 41.58 L96 50 L70.33 58.42 L82.53 82.53 L58.42 70.33 L50 96 L41.58 70.33 L17.47 82.53 L29.67 58.42 L4 50 L29.67 41.58 L17.47 17.47 L41.58 29.67 Z';
const I = {
  shield: '<path d="M12 2.5 4.5 5.5V12c0 4.6 3.1 8 7.5 9.5 4.4-1.5 7.5-4.9 7.5-9.5V5.5Z"/><path d="M9.4 12.2 11.3 14l3.4-3.6"/>',
  lock: '<rect x="4.5" y="10" width="15" height="11" rx="1.5"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  swap: '<path d="M4 8h15m-4-4 4 4-4 4"/><path d="M20 16H5m4 4-4-4 4-4"/>',
  chev: '<path d="m9 5 7 7-7 7"/>', chevL: '<path d="m15 5-7 7 7 7"/>',
  check: '<path d="m5 12.5 4.6 4.5L19 7"/>',
  scale: '<path d="M12 3v18M5 7h14M7 7l-3 7h6Zm10 0-3 7h6Z"/>',
  bell: '<path d="M18 9a6 6 0 1 0-12 0c0 5-2 6.5-2 6.5h16S18 14 18 9Z"/><path d="M13.7 19.5a2 2 0 0 1-3.4 0"/>',
  house: '<path d="M3.5 10.5 12 4l8.5 6.5"/><path d="M5.6 9.6V20h12.8V9.6"/><path d="M10.4 20v-5h3.2v5"/>',
  qr: '<rect x="3.5" y="3.5" width="7" height="7" rx="1"/><rect x="13.5" y="3.5" width="7" height="7" rx="1"/><rect x="3.5" y="13.5" width="7" height="7" rx="1"/><path d="M14 14h2.2M18.4 14h2.1M14 18.4h2.2M18.4 18.4h2.1"/>',
  wallet: '<path d="M3.5 8.5h17v11h-17Z"/><path d="M3.5 8.5 12 4l8.5 4.5"/><path d="M16.5 14h2.6"/>',
  user: '<circle cx="12" cy="8.4" r="3.9"/><path d="M4.6 20.2c1.3-3.6 4-5.4 7.4-5.4s6.1 1.8 7.4 5.4"/>',
};
const svg = (p, s, w) => '<svg aria-hidden="true" width="' + (s || 20) + '" height="' + (s || 20) + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + (w || 1.8) + '" stroke-linecap="round" stroke-linejoin="round">' + p + '</svg>';
function hueOf(id) { let h = 7; for (let i = 0; i < id.length; i++) h = (h * 131 + id.charCodeAt(i) * 17) % 997; return (h * 7) % 360; }
const avStyle = id => { const h = hueOf(id); return 'background:linear-gradient(150deg,hsl(' + h + ' 52% 52%),hsl(' + ((h + 42) % 360) + ' 48% 30%))'; };
const fmt = n => Math.round(n).toLocaleString('ru-RU').replace(/ /g, ' ');

/* печать-звезда с замком; дужка замка — отдельная группа, чтобы её «защёлкнуть» */
function sealSVG(id, kind) {
  const c = kind === 'jade' ? ['#9BE7BC', '#2FA771', '#12744C'] : ['#FFDD95', '#E0A21F', '#A8690F'];
  return '<svg viewBox="0 0 100 100" style="overflow:visible"><defs><radialGradient id="' + id + '" cx="34%" cy="30%" r="72%">' +
    '<stop offset="0" stop-color="' + c[0] + '"/><stop offset=".58" stop-color="' + c[1] + '"/><stop offset="1" stop-color="' + c[2] + '"/>' +
    '</radialGradient><radialGradient id="' + id + 'h" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="rgba(255,226,160,.55)"/><stop offset="1" stop-color="rgba(255,226,160,0)"/></radialGradient></defs>' +
    '<circle cx="50" cy="50" r="58" fill="url(#' + id + 'h)"/>' +
    '<path d="' + SEAL_P + '" fill="url(#' + id + ')"/>' +
    '<circle cx="50" cy="50" r="31" fill="none" stroke="rgba(255,255,255,.42)" stroke-width="1.6"/>' +
    '<circle cx="50" cy="50" r="26.5" fill="none" stroke="rgba(60,38,4,.38)" stroke-width="1" stroke-dasharray="2.5 3.5"/>' +
    '<g transform="translate(38 38)" fill="none" stroke="#4A2E03" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="4.5" y="10" width="15" height="11" rx="1.5"/><g class="shackle"><path d="M8 10V7a4 4 0 0 1 8 0v3"/></g></g></svg>';
}
function girih(states) { // states: 4 значения: '', 'on', 'fin', 'bad'
  let h = '';
  for (let i = 0; i < 4; i++) {
    h += '<svg aria-hidden="true" width="15" height="15" viewBox="0 0 24 24" style="overflow:visible"><path class="st ' + states[i] + '" d="' + STAR_P + '"/></svg>';
    if (i < 3) h += '<span class="ln' + (states[i + 1] && states[i + 1] !== '' ? ' on' : '') + '"></span>';
  }
  return '<div class="girih">' + h + '</div>';
}
function dealCard(d) {
  return `<div class="deal ${d.cls || ''}">
    <div class="deal-top"><span class="mini" style="${avStyle(d.whoId)}">${d.s}</span>
      <span class="code">${d.id}</span><span class="pill ${d.pill}">${d.label}</span></div>
    <h3>${d.title}</h3>
    <div class="who">${d.role}: ${d.who}</div>
    <div class="deal-foot"><span class="sum">${fmt(d.sum)}<s>сўм</s></span>${d.flag || ''}</div>
    ${girih(d.g)}</div>`;
}
const FLAG_TURN = '<span class="turnflag"><i class="tdot"></i>Ваш ход</span>';

/* ---------- разбиение текста на буквы и слова ---------- */
function splitChars(root) {
  const walk = (node, gold) => {
    [...node.childNodes].forEach(n => {
      if (n.nodeType === 3) {
        const frag = document.createDocumentFragment();
        for (const ch of n.textContent) {
          if (ch === '\n' || ch === '\t') continue;
          const s = document.createElement('span');
          if (ch === ' ') { s.className = 'sp'; s.innerHTML = '&nbsp;'; }
          else { s.className = 'ch' + (gold ? ' goldtxt' : ''); s.textContent = ch; }
          frag.appendChild(s);
        }
        n.replaceWith(frag);
      } else if (n.nodeType === 1) {
        const g = gold || n.classList.contains('goldtxt');
        n.classList.remove('goldtxt');
        walk(n, g);
      }
    });
  };
  walk(root, false);
}
function splitWords(root) {
  const words = root.textContent.trim().split(/\s+/);
  root.innerHTML = words.map(w => '<span class="word">' + w + '</span>').join(' ');
}
/* построчная анимация букв: вход снизу из маски, выход вверх */
function lines(t, el, ins, o = {}) {
  const lns = el._lns || (el._lns = $$('.ln', el).map(l => $$('.ch', l)));
  const dur = o.dur || .6, stg = o.stg == null ? .028 : o.stg, outT = o.out, outStg = o.outStg == null ? .018 : o.outStg;
  lns.forEach((chs, li) => {
    const t0 = ins[li] != null ? ins[li] : ins[ins.length - 1];
    chs.forEach((c, j) => {
      const pin = E.outExpo(P(t, t0 + j * stg, dur));
      let y = (1 - pin) * 115, r = (1 - pin) * (o.rot || 0), op = 1;
      if (outT != null) {
        const po = E.inCubic(P(t, outT + (li * 2 + j) * outStg, .35));
        y -= po * 125;
      }
      T(c, 'translateY(' + y.toFixed(2) + '%) rotate(' + r.toFixed(2) + 'deg)', op);
    });
  });
}
function words(t, el, t0, o = {}) {
  const ws = el._ws || (el._ws = $$('.word', el));
  const stg = o.stg || .045;
  ws.forEach((w, i) => {
    const p = E.outExpo(P(t, t0 + i * stg, .6));
    let y = (1 - p) * 40, op = p;
    if (o.out != null) { const q = E.inCubic(P(t, o.out + i * .012, .3)); y -= q * 40; op *= 1 - q; }
    T(w, 'translateY(' + y.toFixed(2) + 'px)', op);
    w.style.filter = p < 1 ? 'blur(' + ((1 - p) * 8).toFixed(2) + 'px)' : 'none';
  });
}

/* ---------- частицы и кольца ---------- */
function makeParts(host, n, seed, colors, cls = 'pt dia') {
  const r = rng(seed), arr = [];
  for (let i = 0; i < n; i++) {
    const el = document.createElement('div');
    el.className = cls;
    const sz = 6 + r() * 16;
    el.style.width = el.style.height = sz.toFixed(1) + 'px';
    const col = colors[Math.floor(r() * colors.length)];
    el.style.background = col;
    el.style.boxShadow = '0 0 ' + (sz * .9).toFixed(0) + 'px ' + col;
    host.appendChild(el);
    arr.push({ el, a: r() * Math.PI * 2, v: .35 + r() * .65, spin: (r() - .5) * 720, life: .9 + r() * .7 });
  }
  return arr;
}
function burst(t, parts, t0, cx, cy, dist) {
  parts.forEach(p => {
    const k = (t - t0) / p.life;
    if (k < 0 || k > 1) { p.el.style.visibility = 'hidden'; return; }
    const d = dist * p.v * E.outExpo(k);
    const x = cx + Math.cos(p.a) * d, y = cy + Math.sin(p.a) * d + 160 * k * k;
    p.el.style.visibility = 'visible';
    p.el.style.opacity = (1 - k * k).toFixed(3);
    p.el.style.transform = 'translate(' + x.toFixed(1) + 'px,' + y.toFixed(1) + 'px) translate(-50%,-50%) rotate(' + (p.spin * k).toFixed(1) + 'deg) scale(' + (1 - k * .6).toFixed(3) + ')';
  });
}
function makeRings(host, n, cls = '') {
  const arr = [];
  for (let i = 0; i < n; i++) { const d = document.createElement('div'); d.className = 'ring ' + cls; host.appendChild(d); arr.push(d); }
  return arr;
}
function ringBurst(t, rings, t0, cx, cy, s0, s1, life = .9, gap = .07) {
  rings.forEach((el, i) => {
    const k = P(t, t0 + i * gap, life);
    if (t < t0 + i * gap || k >= 1) { el.style.visibility = 'hidden'; return; }
    el.style.visibility = 'visible';
    const s = lerp(s0, s1 * (1 - i * .12), E.outExpo(k));
    el.style.transform = 'translate(' + cx + 'px,' + cy + 'px) translate(-50%,-50%) scale(' + s.toFixed(4) + ')';
    el.style.opacity = ((1 - k) * (1 - i * .2)).toFixed(3);
    el.style.borderWidth = (5 * (1 - k) + 1).toFixed(2) + 'px';
  });
}
function makeOrbit(host, n, size) {
  let h = '';
  for (let i = 0; i < n; i++) h += '<svg class="a" width="' + size + '" height="' + size + '" viewBox="0 0 24 24"><path d="' + STAR_P + '" fill="' + (i % 2 ? '#8FE3DD' : '#E5A93F') + '"/></svg>';
  host.innerHTML = h;
  return $$('svg', host);
}
function orbit(t, stars, t0, cx, cy, rad, rot, out) {
  stars.forEach((s, i) => {
    const p = E.outBack(P(t, t0 + i * .05, .5));
    let o = clamp(p), sc = p * (i % 2 ? .7 : 1);
    if (out != null) { const q = E.inCubic(P(t, out, .3)); sc *= 1 - q; o *= 1 - q; }
    const a = i / stars.length * Math.PI * 2 + rot * Math.PI / 180;
    const rr = rad * (0.6 + .4 * clamp(p));
    S(s, { x: cx + Math.cos(a) * rr, y: cy + Math.sin(a) * rr, r: rot * 2 + i * 20, s: sc, o });
  });
}

/* ============================================================
   СБОРКА СЦЕН
   ============================================================ */
const R = {}; // ссылки на элементы и состояния

function buildPhone() {
  const bars = '<span class="bar" style="height:5px"></span><span class="bar" style="height:7px"></span><span class="bar" style="height:9px"></span><span class="bar" style="height:11px;opacity:.35"></span>';
  const tab = (ic, t, on) => '<button class="tab ' + (on ? 'on' : '') + '"><span class="ico">' + svg(ic, 21) + '</span><span>' + t + '</span></button>';
  const d1 = { id: 'PC-2001', s: 'ТС', whoId: 'PC-2277-49', pill: 'glaze', label: 'Передано', title: 'iPhone 13 Pro, 128 ГБ', role: 'Продавец', who: 'Тимур Саидов', sum: 8463000, flag: FLAG_TURN, cls: 'turn', g: ['on', 'on', 'on', ''] };
  const d2 = { id: 'PC-2002', s: 'ДР', whoId: 'PC-9034-12', pill: 'gold', label: 'Под замком', title: 'Дизайн лендинга для кофейни', role: 'Покупатель', who: 'Дилноза Рахимова', sum: 3546000, flag: FLAG_TURN, cls: 'turn', g: ['on', 'on', '', ''] };
  $('#phoneZoom').innerHTML = `
  <div class="device" id="dev" style="box-shadow:0 0 0 2px rgba(127,217,210,.22),0 80px 140px -30px rgba(0,0,0,.95),0 0 120px -20px rgba(47,191,192,.35)">
    <span class="glow"></span><span class="glow b"></span><span class="patt"></span>
    <div class="status"><span>23:48</span><div class="sig">${bars}<span style="margin:0 5px 0 3px;font-size:10px;font-weight:700">5G</span><span class="batt"><i></i></span></div></div>
    <div class="topbar">
      <span class="brandmark"><span class="bstar"><svg viewBox="0 0 24 24" width="30" height="30"><defs><linearGradient id="bg1" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFD98A"/><stop offset="1" stop-color="#A8690F"/></linearGradient></defs><path d="${STAR_P}" fill="url(#bg1)"/><rect x="9.5" y="9.5" width="5" height="5" transform="rotate(45 12 12)" fill="#062330"/></svg></span>
        <span class="bname">Muhr</span></span>
      <button class="bell">${svg(I.bell, 19)}<b>3</b></button>
      <button class="avatar">АК</button>
    </div>
    <main class="views"><div style="padding:0 18px">
      <div class="panno" id="phPanno"><div class="panno-in">
        <div class="wc-top"><span class="lbl">Доступно на кошельке</span></div>
        <div class="big" id="phBal">0<small>сўм</small></div>
        <div class="sealed" id="phSealed">
          <span class="sheen" id="phSheen" style="opacity:1"></span>
          <span class="lockbox">${svg(I.lock, 17)}</span>
          <span><span class="amt" id="phLock">0 сўм</span><span class="meta">Под замком у гаранта, 3 сделки</span></span>
          <span class="go">${svg(I.chev, 17)}</span>
        </div>
      </div></div>
      <div class="quick">
        <div class="qa"><span class="ic">${svg(I.swap, 19)}</span><span>Перевод</span></div>
        <div class="qa gold"><span class="ic">${svg(I.shield, 19)}</span><span>Гарант</span></div>
        <div class="qa"><span class="ic">${svg(I.qr, 19)}</span><span>QR</span></div>
        <div class="qa"><span class="ic">${svg(I.house, 19)}</span><span>Платежи</span></div>
      </div>
      <div class="sec" id="phSec"><svg class="mark" viewBox="0 0 24 24"><path d="${STAR_P}"/></svg><h2>Требует вашего внимания</h2><span class="count">2</span><span class="rule"></span></div>
      <div id="phDeals">${dealCard(d1)}${dealCard(d2)}</div>
    </div></main>
    <nav class="tabs">${tab(I.wallet, 'Кошелёк', 1)}${tab(I.shield, 'Сделки')}${tab(I.swap, 'Перевод')}${tab(I.user, 'Профиль')}</nav>
  </div>`;
  R.ph = {
    bal: $('#phBal').firstChild, lock: $('#phLock'), sheen: $('#phSheen'),
    qa: $$('#phoneZoom .qa'), deals: $$('#phDeals .deal'), sec: $('#phSec'),
    girih: $$('#phDeals .girih path'),
  };
}

function buildSteps() {
  const ST = [
    ['Договорились', 'Покупатель и продавец фиксируют<br>предмет, сумму и срок'],
    ['Деньги под замком', 'Покупатель вносит сумму гаранту —<br>продавец видит её, но не забирает'],
    ['Передача', 'Продавец отправляет товар<br>или выполняет работу'],
    ['Выплата', 'Покупатель подтверждает получение —<br>гарант платит продавцу'],
  ];
  $('#s5steps').innerHTML = ST.map((s, i) => `
    <div class="a" data-step style="display:flex;flex-direction:column;align-items:center;gap:0">
      <div class="stepbox ${i === 3 ? 'jade' : ''}">${i + 1}</div>
      <div class="steptitle" style="margin-top:56px">${s[0]}</div>
      <div class="stepdesc" style="margin-top:26px">${s[1]}</div>
    </div>`).join('');
  R.steps = $$('#s5steps [data-step]');
  let rib = '';
  for (let i = 0; i < 4; i++) {
    rib += '<div class="cell"><svg viewBox="0 0 24 24"><path class="o" d="' + STAR_P + '"/><path class="f" d="' + STAR_P + '" style="transform-box:fill-box;transform-origin:center"/></svg></div>';
    if (i < 3) rib += '<div class="ln"><i></i></div>';
  }
  $('#s5rib').innerHTML = rib;
  R.ribF = $$('#s5rib path.f');
  R.ribL = $$('#s5rib .ln i');
}

function buildDeals() {
  const cards = [
    { id: 'PC-2001', s: 'ТС', whoId: 'PC-2277-49', pill: 'glaze', label: 'Передано', title: 'iPhone 13 Pro, 128 ГБ', role: 'Продавец', who: 'Тимур Саидов', sum: 8463000, flag: FLAG_TURN, cls: 'turn', g: ['on', 'on', 'on', ''] },
    { id: 'PC-2002', s: 'ДР', whoId: 'PC-9034-12', pill: 'gold', label: 'Под замком', title: 'Дизайн лендинга для кофейни', role: 'Покупатель', who: 'Дилноза Рахимова', sum: 3546000, flag: '<span class="turnflag wait">Ждём покупателя</span>', cls: '', g: ['on', 'on', '', ''] },
    { id: 'PC-2005', s: 'МУ', whoId: 'PC-6612-08', pill: 'jade', label: 'Завершена', title: 'Ремонт ноутбука', role: 'Покупатель', who: 'Малика Усманова', sum: 250000, flag: '', cls: '', g: ['fin', 'fin', 'fin', 'fin'] },
  ];
  $('#s6cards').innerHTML = cards.map(c => '<div class="a" data-card><div class="ui" style="zoom:1.75;width:440px">' + dealCard(c) + '</div></div>').join('') +
    '<div class="a stamp2" id="s6stamp">' + sealSVG('stj', 'jade').replace(/<g transform="translate\(38 38\)"[\s\S]*<\/g><\/g>/, '') +
    '<div class="lab">' + svg(I.check, 46, 2.6) + '<b>ВЫПЛАЧЕНО</b></div></div>' +
    '<div class="a" id="s6rings"></div>';
  R.cards = $$('#s6cards [data-card]');
  R.c1 = R.cards[0].querySelector('.deal');
  R.cardPaths = R.cards.map(c => $$('.girih path', c));
  R.cardLines = R.cards.map(c => $$('.girih .ln', c));
}

function buildTransfer() {
  const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '000', '0', '‹'];
  $('#s7ui').innerHTML = `
    <div class="a" data-tp><div class="ui" style="zoom:1.9;width:440px"><div class="to">
      <span class="av" style="${avStyle('PC-9034-12')}">ДР</span>
      <span><span class="n">Дилноза Рахимова</span><span class="i">PC-9034-12 · 5,0 ★ · 64 сделки</span></span>
      <span style="margin-left:auto" class="pill jade">проверена</span></div></div></div>
    <div class="a" data-tp><div class="entry" style="padding:0"><div class="val" id="s7val" style="font-size:96px;letter-spacing:-4px;gap:16px">
      <span id="s7num">0</span><span class="caret" id="s7caret" style="height:70px;width:4px"></span><span class="cur" style="font-size:34px">сўм</span></div></div></div>
    <div class="a" data-tp><div class="ui" style="zoom:1.9;width:440px"><div class="fee-card" style="margin:0">
      <div class="fee-row"><span>Перевод</span><b id="s7a">0 сўм</b></div>
      <div class="fee-row"><span>Комиссия сервиса, 0,9%</span><b id="s7f">0 сўм</b></div>
      <div class="fee-row big"><span>Спишется с вас</span><b id="s7t">0 сўм</b></div></div></div></div>
    <div class="a" data-tp><div class="ui" style="zoom:1.9;width:440px"><div class="pad" style="margin:0;padding:0">
      ${keys.map(k => '<div class="key ' + (k === '000' || k === '‹' ? 'fn' : '') + ' keyx" style="display:grid;place-items:center" data-k="' + k + '">' + k + '</div>').join('')}</div></div></div>
    <div class="a" data-tp><div class="ui" style="zoom:1.9;width:440px"><div class="swipe" style="margin:0">
      <div class="fill" id="s7fill"></div><div class="lab" id="s7lab">Проведите, чтобы отправить</div>
      <div class="knob" id="s7knob">${svg(I.chev, 20, 2.2)}</div></div></div></div>`;
  R.tp = $$('#s7ui [data-tp]');
  R.keys = Object.fromEntries($$('#s7ui .key').map(k => [k.dataset.k, k]));
}

/* ============================================================
   СЦЕНЫ (глобальное время t)
   ============================================================ */
const SC = [];
const scene = (id, t0, t1, fn) => SC.push({ el: $('#' + id), t0, t1, fn });

/* 1. Хук: 0–4 с */
function s1(t) {
  const h = $('#s1h');
  S(h, { x: 540, y: kf(t, [[0, 640], [1.0, 640], [1.5, 215, E.outExpo]]), s: kf(t, [[0, 1.1], [1.0, 1.0, E.outCubic], [1.5, .78, E.outExpo]]) });
  lines(t, h, [0.02, 0.42], { dur: .55, stg: .03, out: 1.95 });
  // переписка
  const b1 = R.s1b1, b2 = R.s1b2;
  const left = 70;
  let y1 = kf(t, [[1.0, 520], [2.0, 520], [2.45, 250, E.outExpo]]), y2 = kf(t, [[1.5, 760], [2.0, 760], [2.45, 470, E.outExpo]]);
  const pop = (t0) => ({ s: lerp(.4, 1, E.outBack(P(t, t0, .45))), o: P(t, t0, .12), r: (1 - E.outBack(P(t, t0, .45))) * -8 });
  const g = glitch(t);
  const imp = E.inExpo(P(t, 3.45, .5));
  const toC = (x, y) => ({ x: lerp(x, 540, imp), y: lerp(y, 675, imp) });
  let p1 = pop(1.0), p2 = pop(1.5);
  S(b1, { ...toC(left + b1._w / 2 + g.x, y1), s: p1.s * (1 - imp * .95), r: p1.r + imp * 40, o: p1.o * (1 - imp), b: imp * 18, f: g.f });
  S(b2, { ...toC(left + b2._w / 2 - g.x, y2), s: p2.s * (1 - imp * .95), r: p2.r - imp * 40, o: p2.o * (1 - imp), b: imp * 18, f: g.f });
  // карточка риска
  const rk = $('#s1risk');
  const pr = E.outExpo(P(t, 2.0, .5));
  S(rk, { ...toC(540 + g.x * 1.5, 905 + (1 - pr) * 120), z: (1 - pr) * 700, rx: (1 - pr) * 35, o: P(t, 2.0, .1) * (1 - imp), s: 1 - imp * .95, r: imp * 25, b: imp * 18 + (1 - pr) * 6, f: g.f });
  R.s1dia.style.left = tw(t, 2.15, .8, 88, 14, E.outExpo).toFixed(2) + '%';
  T(R.s1lvl, 'scale(' + lerp(0, 1, E.outBackS(P(t, 2.5, .4))).toFixed(3) + ')');
  R.s1facts.forEach((f, i) => { const p = E.outExpo(P(t, 2.3 + i * .14, .5)); T(f, 'translateX(' + ((1 - p) * -30).toFixed(1) + 'px)', p); });
}
function glitch(t) {
  if (t < 3.0 || t > 3.55) return { x: 0, f: '' };
  const r = rng(Math.floor(t * 60) * 977)();
  const r2 = rng(Math.floor(t * 60) * 131 + 7)();
  const on = r > .3;
  const off = on ? (r2 - .5) * 26 : 0;
  return { x: off, f: on ? 'drop-shadow(' + (8 * r2).toFixed(1) + 'px 0 0 rgba(255,40,80,.75)) drop-shadow(' + (-8 * r).toFixed(1) + 'px 0 0 rgba(40,240,255,.65))' : '' };
}

/* 2. Раскрытие бренда: 4–8 с */
function s2(t) {
  const cx = 540, cy = 560;
  const seal = $('#s2seal');
  const ps = P(t, 4.0, .6);
  const grow = E.inExpo(P(t, 7.4, .6));
  S(seal, { x: cx, y: cy, s: lerp(2.8, 1, E.outBack(ps)) * (1 + tw(t, 4.6, 3, 0, .06, E.outCubic)) * lerp(1, 13, grow),
    r: lerp(-80, 0, E.outBack(ps)) + tw(t, 4.6, 3.2, 0, 14, E.inOutCubic) + grow * 90, o: P(t, 4.0, .08), b: (1 - E.outExpo(P(t, 4.0, .3))) * 24 });
  // дужка замка защёлкивается на 4,6 с
  const sh = tw(t, 4.62, .1, -3.2, 0, E.inQuad);
  R.s2shackle.setAttribute('transform', 'translate(0 ' + sh.toFixed(3) + ')');
  ringBurst(t, R.s2rings, 4.0, cx, cy, .3, 3.4, 1.0, .08);
  ringBurst(t, R.s2ring2, 4.65, cx, cy, .6, 1.6, .6);
  burst(t, R.s2parts, 4.0, cx, cy, 760);
  orbit(t, R.s2orbit, 4.9, cx, cy, 300, t * 22, 7.3);
  const w = $('#s2word');
  S(w, { x: 540, y: 905, s: tw(t, 4.6, 3, 1, 1.04, E.outCubic) });
  lines(t, w, [4.62], { dur: .7, stg: .06, out: 7.3, outStg: .03 });
  const sub = $('#s2sub');
  const pp = E.outExpo(P(t, 5.1, 1.1));
  S(sub, { x: 540, y: 1030 + (1 - pp) * 26, o: pp * (1 - P(t, 7.3, .2)) });
  sub.style.letterSpacing = lerp(.42, .02, pp).toFixed(3) + 'em';
}

/* 3. Телефон: 8–12 с */
function s3(t) {
  const sec = $('#s3');
  const wh = E.inExpo(P(t, 11.45, .55));
  sec.style.transformOrigin = '540px 560px';
  sec.style.transform = 'scale(' + lerp(1, 3.2, wh).toFixed(4) + ')';
  sec.style.filter = wh > .02 ? 'blur(' + (wh * 16).toFixed(2) + 'px)' : 'none';
  const h = $('#s3h');
  S(h, { x: 540, y: 175 });
  lines(t, h, [8.0, 8.22], { dur: .6, stg: .025 });
  const ph = $('#s3phone');
  const pin = E.outExpo(P(t, 8.0, 1.0));
  const idle = E.inOutCubic(P(t, 8.9, 2.6));
  S(ph, { x: 540, y: lerp(2200, 1010, pin) - idle * 15, rx: lerp(62, 9, pin) - idle * 3, ry: lerp(0, -13, pin) + idle * 22, r: lerp(-16, -2, pin) + idle * 3.5, s: 1 });
  // наполнение экрана
  R.ph.bal.textContent = fmt(Math.round(tw(t, 8.35, 1.1, 0, 5200000, E.outCubic) / 1000) * 1000);
  R.ph.lock.textContent = fmt(Math.round(tw(t, 8.9, 1.0, 0, 13218000, E.outCubic) / 1000) * 1000) + ' сўм';
  const sw = P(t, 10.0, .9);
  R.ph.sheen.style.left = lerp(-60, 132, E.inOutCubic(sw)).toFixed(2) + '%';
  R.ph.sheen.style.opacity = sw > 0 && sw < 1 ? 1 : 0;
  R.ph.qa.forEach((q, i) => { const p = E.outBack(P(t, 8.55 + i * .06, .45)); T(q, 'scale(' + lerp(.5, 1, p).toFixed(3) + ')', clamp(p * 2)); });
  T(R.ph.sec, 'translateX(' + ((1 - E.outExpo(P(t, 8.85, .6))) * 40).toFixed(1) + 'px)', P(t, 8.85, .3));
  R.ph.deals.forEach((d, i) => { const p = E.outExpo(P(t, 9.0 + i * .14, .7)); T(d, 'translateY(' + ((1 - p) * 70).toFixed(1) + 'px)', p); });
  R.ph.girih.forEach((g, i) => { const k = i % 4, card = Math.floor(i / 4); const p = E.outBack(P(t, 9.4 + card * .14 + k * .09, .4)); g.style.transform = 'scale(' + lerp(.2, 1, p).toFixed(3) + ') rotate(' + ((1 - p) * -45).toFixed(1) + 'deg)'; });
  // всплывающие плашки-фичи
  [[R.s3t[0], 10.0, 300, 590, -5], [R.s3t[1], 10.5, 690, 830, 4], [R.s3t[2], 11.0, 320, 1070, -3]].forEach(([el, t0, x, y, r]) => {
    const p = E.outBackS(P(t, t0, .5));
    S(el, { x: x + (1 - p) * (x < 540 ? -60 : 60), y: y + Math.sin((t - t0) * 2.4) * 6, z: 120, s: lerp(.3, 1, p), r: r * p, o: clamp(P(t, t0, .1)) });
  });
}

/* 4. Деньги под замком: 12–16 с */
function s4(t) {
  const sec = $('#s4');
  const ent = E.outExpo(P(t, 11.95, .5)), ex = E.inExpo(P(t, 15.5, .42));
  sec.style.transformOrigin = '540px 640px';
  sec.style.transform = 'translateX(' + (-ex * 1150).toFixed(1) + 'px) scale(' + lerp(2.2, 1, ent).toFixed(4) + ')';
  const bl = (1 - ent) * 14 + ex * 22;
  sec.style.filter = bl > .1 ? 'blur(' + bl.toFixed(2) + 'px)' : 'none';
  const h = $('#s4h');
  S(h, { x: 540, y: 215 });
  lines(t, h, [12.05, 12.3], { dur: .6, stg: .035 });
  const pb = E.outBack(P(t, 12.2, .5)), psl = E.outBack(P(t, 12.3, .5));
  S($('#s4buyer'), { x: 180, y: 650, s: pb, o: clamp(pb) });
  S($('#s4seller'), { x: 900, y: 650, s: psl, o: clamp(psl) });
  const pv = E.outBack(P(t, 12.1, .55));
  const click = Math.exp(-Math.max(0, t - 13.0) * 9) * (t >= 13 ? 1 : 0);
  S($('#s4vault'), { x: 540, y: 620, s: pv * (1 + click * .1), r: (1 - pv) * -60, o: clamp(pv) });
  R.s4shackle.setAttribute('transform', 'translate(0 ' + tw(t, 12.96, .08, -3.4, 0, E.inQuad).toFixed(3) + ')');
  ringBurst(t, R.s4rings, 13.03, 540, 620, .7, 2.6, .8, .08);
  // монеты летят от покупателя в сейф
  R.s4coins.forEach((c, i) => {
    const k = P(t, 12.4 + i * .05, .42);
    if (k <= 0 || k >= 1) { c.style.visibility = 'hidden'; return; }
    c.style.visibility = 'visible';
    const e = E.inOutCubic(k);
    const x = lerp(260, 540, e), y = lerp(640, 620, e) - Math.sin(e * Math.PI) * (150 + (i % 3) * 30);
    c.style.transform = 'translate(' + x.toFixed(1) + 'px,' + y.toFixed(1) + 'px) translate(-50%,-50%) rotate(' + (k * 360).toFixed(0) + 'deg) scale(' + (1 - k * .5).toFixed(3) + ')';
    c.style.opacity = k > .85 ? ((1 - k) / .15).toFixed(3) : 1;
  });
  const ps = E.outExpo(P(t, 13.1, .6));
  S($('#s4sealed'), { x: 540, y: 965 + (1 - ps) * 90, o: ps });
  R.s4amt.textContent = fmt(Math.round(tw(t, 13.1, .9, 0, 8463000, E.outCubic) / 1000) * 1000) + ' сўм';
  const sw = P(t, 14.0, .9);
  R.s4sheen.style.left = lerp(-60, 132, E.inOutCubic(sw)).toFixed(2) + '%';
  R.s4sheen.style.opacity = sw > 0 && sw < 1 ? 1 : 0;
  S($('#s4sub'), { x: 540, y: 1170 });
  R.s4subW.forEach((el, i) => words(t, el, 14.05 + i * .25, { stg: .05 }));
}

/* 5. Как работает гарант: 16–20 с */
function s5(t) {
  const sec = $('#s5');
  const ent = E.outExpo(P(t, 15.8, .55)), ex = E.inExpo(P(t, 19.75, .35));
  sec.style.transformOrigin = '540px 675px';
  sec.style.transform = 'translateX(' + ((1 - ent) * 1150).toFixed(1) + 'px) scale(' + lerp(1, .82, ex).toFixed(4) + ')';
  const bl = (1 - ent) * 20 + ex * 18;
  sec.style.filter = bl > .1 ? 'blur(' + bl.toFixed(2) + 'px)' : 'none';
  sec.style.opacity = 1 - ex;
  S($('#s5sec'), { x: 540, y: 140, o: P(t, 15.95, .3) });
  // активный шаг
  const step = clamp(Math.floor(t - 16), 0, 3);
  R.steps.forEach((el, i) => {
    const tin = 16 + i - (i === 0 ? .2 : .05), tout = 16.92 + i;
    const pin = E.outExpo(P(t, tin, .5)), pout = i === 3 ? 0 : E.inCubic(P(t, tout, .2));
    const x = 540 + (1 - pin) * 1000 - pout * 1100;
    S(el, { x, y: 625, o: (t >= tin ? 1 : 0) * (1 - pout), b: (1 - pin) * 10 + pout * 14 });
    const box = el.firstElementChild;
    const pb = E.outBackS(P(t, tin + .05, .45));
    T(box, 'scale(' + lerp(.3, 1, pb).toFixed(3) + ') rotate(' + ((1 - pb) * -30).toFixed(1) + 'deg)');
  });
  const num = $('#s5num');
  num.textContent = '0' + (step + 1);
  const ph = t - 16 - step;
  S(num, { x: 560 + (1 - E.outExpo(P(ph, 0, .7))) * 260, y: 640, o: .9 * P(t, 15.9, .4) });
  // лента гирих
  S($('#s5rib'), { x: 540, y: 1065, o: P(t, 15.95, .3) });
  R.ribF.forEach((f, i) => {
    const p = E.outBackS(P(t, 16.1 + i, .45));
    f.style.transform = 'scale(' + p.toFixed(3) + ') rotate(' + ((1 - p) * -90).toFixed(1) + 'deg)';
    f.style.fill = t >= 19.1 ? '#4FB07A' : '#E5A93F';
    f.style.filter = 'drop-shadow(0 0 ' + (8 + 14 * Math.exp(-Math.max(0, t - 16.1 - i) * 4)).toFixed(1) + 'px ' + (t >= 19.1 ? 'rgba(79,176,122,.7)' : 'rgba(229,169,63,.7)') + ')';
  });
  R.ribL.forEach((l, i) => { l.style.transform = 'scaleX(' + E.inOutCubic(P(t, 16.45 + i, .6)).toFixed(3) + ')'; l.style.background = t >= 19.1 ? 'var(--jade)' : 'var(--ochre)'; });
  const pd = E.outBackS(P(t, 19.3, .45));
  S($('#s5done'), { x: 540, y: 1195, s: pd, o: clamp(pd) });
}

/* 6. Сделки: 20–24 с */
function s6(t) {
  const h = $('#s6h');
  S(h, { x: 540, y: 150 });
  lines(t, h, [20.0, 20.2], { dur: .6, stg: .025, out: 23.55 });
  const ys = [495, 812, 1129], xs = [-14, 16, -8], rs = [-1.6, 1.3, -1.0];
  const fx = [-320, 320, -240], fr = [-26, 22, -16];
  R.cards.forEach((c, i) => {
    const t0 = 20.15 + i * .2;
    const p = E.outExpo(P(t, t0, .75));
    const ex = E.inExpo(P(t, 23.6 + i * .07, .4));
    const bump = i === 0 ? Math.exp(-Math.max(0, t - 22.5) * 10) * (t >= 22.5 ? 1 : 0) : 0;
    S(c, { x: 540 + lerp(fx[i], xs[i], p), y: ys[i] + Math.sin(t * 2 + i * 1.7) * 5 - ex * 1500, z: lerp(-2200, 0, p) + bump * 60,
      rx: lerp(-50, 0, p), r: lerp(fr[i], rs[i], p), o: P(t, t0, .12), b: ex * 12 + (1 - p) * 4 });
    // клетки гирих зажигаются
    R.cardPaths[i].forEach((g, k) => { const q = E.outBack(P(t, 20.9 + i * .12 + k * .1, .4)); g.style.transform = 'scale(' + lerp(.2, 1, q).toFixed(3) + ') rotate(' + ((1 - q) * -45).toFixed(1) + 'deg)'; });
  });
  // печать «Выплачено» на iPhone-сделке
  const done = t >= 22.55;
  if (R.c1._done !== done) {
    R.c1._done = done;
    R.c1.classList.toggle('turn', !done);
    const pill = R.c1.querySelector('.pill');
    pill.className = 'pill ' + (done ? 'jade' : 'glaze'); pill.textContent = done ? 'Завершена' : 'Передано';
    R.c1.querySelector('.turnflag').style.visibility = done ? 'hidden' : 'visible';
    R.cardPaths[0].forEach(g => g.setAttribute('class', 'st ' + (done ? 'fin' : g.dataset.cls)));
    R.cardLines[0].forEach(l => l.classList.toggle('on', true));
    R.c1.style.background = done ? 'rgba(79,176,122,.5)' : '';
  }
  const st = $('#s6stamp');
  const k = P(t, 22.5, .38);
  const sc = k < .62 ? lerp(2.4, .94, E.inQuad(k / .62)) : lerp(.94, 1, E.outQuad((k - .62) / .38));
  const rr = k < .62 ? lerp(-52, -7, E.inQuad(k / .62)) : lerp(-7, -11, (k - .62) / .38);
  const ex = E.inExpo(P(t, 23.6, .4));
  S(st, { x: 850, y: 445 - ex * 1500, s: sc, r: rr, o: clamp(k * 2.5) });
  ringBurst(t, R.s6rings, 22.62, 850, 445, .5, 2.2, .7, .08);
}

/* 7. Перевод: 24–28 с */
const SEQ = ['1', '5', '0', '0', '0', '0', '0'];
function s7(t) {
  const sec = $('#s7');
  const ex = E.inExpo(P(t, 27.55, .45));
  sec.style.transformOrigin = '540px 560px';
  sec.style.transform = 'scale(' + lerp(1, 4, ex).toFixed(4) + ')';
  sec.style.filter = ex > .02 ? 'blur(' + (ex * 14).toFixed(2) + 'px)' : 'none';
  sec.style.opacity = 1 - E.inCubic(P(t, 27.75, .25));
  const h = $('#s7h');
  const dn = E.outExpo(P(t, 26.7, .5));
  S(h, { x: 540, y: 150, o: 1 - dn });
  lines(t, h, [24.0, 24.15], { dur: .6, stg: .025 });
  const ys = [345, 500, 660, 965, 1245];
  R.tp.forEach((el, i) => {
    const p = E.outExpo(P(t, 24.05 + i * .07, .65));
    S(el, { x: 540, y: ys[i] + (1 - p) * 170, o: clamp(p * 1.5) * (1 - dn), s: 1 - dn * .12, b: dn * 10 });
  });
  // набор суммы
  let n = 0, s = '';
  SEQ.forEach((k, i) => { if (t >= 24.5 + i * .25) { s += k; n++; } });
  const amount = s ? parseInt(s, 10) : 0;
  R.s7num.textContent = fmt(amount);
  $('#s7val').classList.toggle('empty', !amount);
  R.s7caret.style.opacity = (Math.floor(t * 2.2) % 2 === 0 || t < 26) ? 1 : 0;
  Object.values(R.keys).forEach(k => { k.classList.remove('on'); k.style.transform = ''; });
  SEQ.forEach((k, i) => {
    const t0 = 24.5 + i * .25, d = t - t0;
    if (d >= 0 && d < .16) { const el = R.keys[k]; el.classList.add('on'); el.style.transform = 'scale(' + lerp(.9, 1, d / .16).toFixed(3) + ')'; }
  });
  const fee = Math.round(amount * .009);
  R.s7a.textContent = fmt(amount) + ' сўм'; R.s7f.textContent = fmt(fee) + ' сўм'; R.s7t.textContent = fmt(amount + fee) + ' сўм';
  // свайп
  const sw = E.inOutCubic(P(t, 26.1, .55));
  R.s7knob.style.left = lerp(4, 386, sw).toFixed(1) + 'px';
  R.s7fill.style.width = lerp(58, 440, sw).toFixed(1) + 'px';
  R.s7lab.style.opacity = 1 - sw;
  // успех
  const box = $('#s7done');
  S(box, { x: 540, y: 700, o: P(t, 26.75, .15) });
  const tk = E.outBackS(P(t, 26.75, .55));
  T(R.s7tick, 'scale(' + lerp(.3, 1, tk).toFixed(3) + ') rotate(' + ((1 - tk) * -20).toFixed(1) + 'deg)');
  [R.s7h2, R.s7p].forEach((el, i) => { const p = E.outExpo(P(t, 26.95 + i * .1, .6)); T(el, 'translateY(' + ((1 - p) * 40).toFixed(1) + 'px)', p); });
  ringBurst(t, R.s7rings, 26.75, 540, 560, .5, 3, .9, .08);
  burst(t, R.s7parts, 26.75, 540, 560, 620);
}

/* 8. Финал: 28–32 с */
function s8(t) {
  const cx = 540, cy = 470;
  const ps = P(t, 28.0, .65);
  S($('#s8seal'), { x: cx, y: cy, s: lerp(3, 1, E.outBack(ps)) * (1 + tw(t, 28.6, 3.4, 0, .05, E.outCubic)), r: lerp(-75, 0, E.outBack(ps)) + tw(t, 28.6, 3.4, 0, 10, E.inOutCubic), o: P(t, 28.0, .08), b: (1 - E.outExpo(P(t, 28.0, .3))) * 24 });
  R.s8shackle.setAttribute('transform', 'translate(0 ' + tw(t, 28.55, .1, -3.2, 0, E.inQuad).toFixed(3) + ')');
  ringBurst(t, R.s8rings, 28.0, cx, cy, .3, 3.2, 1.0, .08);
  burst(t, R.s8parts, 28.0, cx, cy, 720);
  orbit(t, R.s8orbit, 28.5, cx, cy, 262, t * 20);
  const w = $('#s8word');
  S(w, { x: 540, y: 790 });
  lines(t, w, [28.3], { dur: .7, stg: .06 });
  const sub = $('#s8sub');
  const pp = E.outExpo(P(t, 28.75, 1.1));
  S(sub, { x: 540, y: 905 + (1 - pp) * 24, o: pp });
  sub.style.letterSpacing = lerp(.42, .02, pp).toFixed(3) + 'em';
  S($('#s8tag'), { x: 540, y: 1055 });
  R.s8tagW.forEach((el, i) => words(t, el, 29.2 + i * .3, { stg: .04 }));
  const pc = E.outBackS(P(t, 29.9, .5));
  S($('#s8cta'), { x: 540, y: 1225, s: lerp(.5, 1, pc), o: clamp(pc * 2) });
  R.s8shine.style.left = lerp(-60, 140, E.inOutCubic(P(t, 30.5, .8))).toFixed(1) + '%';
}

/* ---------- фон, камера, вспышки ---------- */
const HITS = [ // [время, сила тряски]
  [2.0, 16], [3.0, 6], [3.25, 6], [4.0, 30], [4.65, 8], [8.0, 18], [12.0, 14], [13.0, 14], [16.0, 10], [17.0, 6], [18.0, 6], [19.0, 6],
  [20.0, 10], [22.5, 18], [24.0, 10], [26.75, 12], [28.0, 28], [28.55, 6]];
const FLASH = [ // [время, сила, затухание, цвет]
  [3.95, .9, .22, '#FFF4DA'], [8.0, .85, .3, '#FFD98A'], [12.0, .55, .25, '#C9FFFA'], [13.0, .35, .18, '#FFE3A3'],
  [16.0, .25, .2, '#C9FFFA'], [20.0, .3, .2, '#FFFFFF'], [22.55, .22, .15, '#D6FFE6'], [24.0, .25, .2, '#C9FFFA'],
  [26.75, .4, .25, '#D6FFE6'], [28.0, .9, .35, '#FFF4DA']];

function background(t) {
  $('#patt').style.transform = 'translate3d(0,' + ((t * 26) % 124).toFixed(2) + 'px,0) rotate(0deg)';
  $('#patt').style.opacity = (.07 + .05 * Math.exp(-((t * 2) % 1) * 5) * (t >= 8 && t < 28 ? 1 : 0)).toFixed(3);
  const gold = Math.max(kf(t, [[3.9, 0], [4.1, .3], [7.6, .3], [8.0, 0, E.lin]]), kf(t, [[11.9, 0], [12.3, .45], [15.6, .45], [16.0, 0, E.lin]]), kf(t, [[27.9, 0], [28.2, .3]]));
  $('#pattGold').style.opacity = gold.toFixed(3);
  $('#pattGold').style.transform = 'scale(' + (1 + t * .01).toFixed(4) + ') rotate(' + (t * 1.5).toFixed(2) + 'deg)';
  S($('#blobA'), { x: 540 + Math.sin(t * .5) * 260, y: 420 + Math.cos(t * .37) * 220, s: 1 + .08 * Math.sin(t * 1.3) });
  S($('#blobB'), { x: 640 + Math.cos(t * .42) * 300, y: 980 + Math.sin(t * .31) * 200, s: 1 + .1 * Math.cos(t * 1.1),
    o: .7 + .3 * Math.max(gold / .45, 0) });
  const rays = Math.max(kf(t, [[3.95, 0], [4.15, .95], [7.4, .8], [8.0, 0, E.lin]]), kf(t, [[27.95, 0], [28.2, .9]]));
  const ry = t < 16 ? 560 : 470;
  S($('#rays'), { x: 540, y: ry, r: t * 14, o: rays, s: 1 + .05 * Math.sin(t * 3) });
  const tint = kf(t, [[1.8, 0], [2.1, .35], [3.0, .4], [3.9, 0, E.inCubic]]) + (t >= 3.0 && t < 3.55 ? .3 * rng(Math.floor(t * 60))() : 0);
  $('#tint').style.opacity = clamp(tint).toFixed(3);
}
function camera(t, frame) {
  let x = 0, y = 0, r = 0;
  HITS.forEach(([h, a], i) => {
    if (t < h) return;
    const d = t - h, k = Math.exp(-d * 10) * a;
    if (k < .05) return;
    x += Math.sin(d * 62 + i) * k; y += Math.cos(d * 55 + i * 2) * k * .8; r += Math.sin(d * 40 + i) * k * .025;
  });
  // пульс на каждую долю в основной части
  let s = 1;
  if (t >= 8 && t < 27.9) s += .014 * Math.exp(-((t % .5)) * 12);
  s += .03 * kf(t, [[0, 0], [4, 1, E.lin], [4.01, 0, E.lin]]); // медленный наезд в хуке
  $('#cam').style.transform = 'translate(' + x.toFixed(2) + 'px,' + y.toFixed(2) + 'px) rotate(' + r.toFixed(3) + 'deg) scale(' + s.toFixed(4) + ')';
  let fl = 0, col = '#fff';
  FLASH.forEach(([h, a, d, c]) => { if (t >= h - .02) { const v = a * Math.exp(-(t - h) / d) * clamp((t - h + .02) / .02); if (v > fl) { fl = v; col = c; } } });
  const fe = $('#flash'); fe.style.opacity = clamp(fl).toFixed(3); fe.style.background = col;
  $('#fade').style.opacity = Math.max(1 - P(t, 0, .25), E.inCubic(P(t, 31.55, .45))).toFixed(3);
  const g = rng(frame * 7919 + 13);
  $('#grain').style.backgroundPosition = Math.floor(g() * 256) + 'px ' + Math.floor(g() * 256) + 'px';
}

function render(t, frame) {
  SC.forEach(sc => {
    const on = t >= sc.t0 && t < sc.t1;
    sc.el.style.display = on ? 'block' : 'none';
    if (on) sc.fn(t);
  });
  background(t);
  camera(t, frame == null ? Math.round(t * 60) : frame);
}

/* ---------- инициализация ---------- */
async function init() {
  const loads = [];
  [400, 500, 600, 700, 800, 900].forEach(w => { loads.push(document.fonts.load(w + ' 40px Unbounded', 'Мuhr')); loads.push(document.fonts.load(w + ' 40px Rubik', 'Мuhr')); });
  await Promise.all(loads);
  await document.fonts.ready;

  // аватары и иконки
  $$('[data-av]').forEach(el => el.setAttribute('style', (el.getAttribute('style') || '') + ';' + avStyle(el.dataset.av)));
  $$('[data-ic]').forEach(el => {
    const ic = svg(I[el.dataset.ic], +(el.dataset.icSize || 26), el.dataset.icW || 2);
    if (el.textContent.trim()) el.insertAdjacentHTML(el.dataset.ic === 'chev' ? 'beforeend' : 'afterbegin', ic); else el.innerHTML = ic;
  });
  $$('[data-star]').forEach(el => el.innerHTML = '<path d="' + STAR_P + '"/>');
  $$('[data-split]').forEach(splitChars);
  $$('[data-words]').forEach(splitWords);

  buildPhone(); buildSteps(); buildDeals(); buildTransfer();
  R.cardPaths.forEach(arr => arr.forEach(g => g.dataset.cls = g.getAttribute('class').replace('st ', '').trim()));

  // печати
  $('#s2seal').innerHTML = sealSVG('sg2'); R.s2shackle = $('#s2seal .shackle');
  $('#s8seal').innerHTML = sealSVG('sg8'); R.s8shackle = $('#s8seal .shackle');
  $('#s4vault').innerHTML = '<svg width="150" height="150" viewBox="0 0 24 24" fill="none" stroke="#E5A93F" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="4.5" y="10" width="15" height="11" rx="1.5" fill="rgba(229,169,63,.16)"/><g class="shackle"><path d="M8 10V7a4 4 0 0 1 8 0v3"/></g><circle cx="12" cy="15" r="1.4" fill="#E5A93F" stroke="none"/><path d="M12 16.2v2"/></svg>';
  R.s4shackle = $('#s4vault .shackle');

  R.s1b1 = $('#s1b1'); R.s1b2 = $('#s1b2');
  [R.s1b1, R.s1b2].forEach(el => { el.style.display = 'block'; });
  R.s1dia = $('#s1dia'); R.s1lvl = $('#s1lvl'); R.s1facts = $$('#s1risk [data-f]');
  R.s2rings = makeRings($('#s2rings'), 3); R.s2ring2 = makeRings($('#s2rings'), 1);
  R.s2parts = makeParts($('#s2parts'), 46, 11, ['#FFD98A', '#E5A93F', '#8FE3DD', '#FFF3D6']);
  R.s2orbit = makeOrbit($('#s2orbit'), 10, 40);
  R.s3t = [$('#s3t1'), $('#s3t2'), $('#s3t3')];
  R.s4rings = makeRings($('#s4ring'), 3);
  R.s4coins = []; for (let i = 0; i < 12; i++) { const c = document.createElement('div'); c.className = 'coin'; $('#s4coins').appendChild(c); R.s4coins.push(c); }
  R.s4amt = $('#s4amt'); R.s4sheen = $('#s4sheen'); R.s4subW = $$('#s4sub [data-words]');
  R.s6rings = makeRings($('#s6rings'), 2, 'jade');
  R.s7num = $('#s7num'); R.s7caret = $('#s7caret'); R.s7a = $('#s7a'); R.s7f = $('#s7f'); R.s7t = $('#s7t');
  R.s7knob = $('#s7knob'); R.s7fill = $('#s7fill'); R.s7lab = $('#s7lab');
  R.s7tick = $('#s7done .tick'); R.s7h2 = $('#s7done h2'); R.s7p = $('#s7done p');
  R.s7rings = makeRings($('#s7rings'), 3, 'jade');
  R.s7parts = makeParts($('#s7parts'), 34, 77, ['#8CE0AF', '#4FB07A', '#E8F5F3', '#8FE3DD']);
  R.s8rings = makeRings($('#s8rings'), 3);
  R.s8parts = makeParts($('#s8parts'), 46, 99, ['#FFD98A', '#E5A93F', '#8FE3DD', '#FFF3D6']);
  R.s8orbit = makeOrbit($('#s8orbit'), 10, 36);
  R.s8tagW = $$('#s8tag [data-words]'); R.s8shine = $('#s8shine');

  // зерно плёнки
  const cv = document.createElement('canvas'); cv.width = cv.height = 256;
  const cx = cv.getContext('2d'), id = cx.createImageData(256, 256), r = rng(4242);
  for (let i = 0; i < id.data.length; i += 4) { const v = r() * 255; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255; }
  cx.putImageData(id, 0, 0);
  $('#grain').style.backgroundImage = 'url(' + cv.toDataURL() + ')';

  // замер элементов, позиционируемых по левому краю
  $('#s1').style.display = 'block';
  [R.s1b1, R.s1b2].forEach(el => { el._w = el.offsetWidth; el._h = el.offsetHeight; });

  scene('s1', 0, 4.0, s1);
  scene('s2', 3.95, 8.02, s2);
  scene('s3', 8.0, 12.0, s3);
  scene('s4', 11.95, 15.95, s4);
  scene('s5', 15.8, 20.1, s5);
  scene('s6', 19.95, 24.1, s6);
  scene('s7', 23.95, 28.0, s7);
  scene('s8', 27.95, 32.01, s8);
}

window.DURATION = DUR;
window.ready = init().then(() => { render(0, 0); return true; });
window.renderAt = (t, frame) => { render(t, frame); return true; };

/* предпросмотр в браузере: ?t=12.5 — стоп-кадр, без параметра — проигрывание */
window.ready.then(() => {
  if (navigator.webdriver) return;
  const q = new URLSearchParams(location.search);
  if (q.has('t')) { render(parseFloat(q.get('t'))); return; }
  const start = performance.now();
  (function loop(now) { render(((now - start) / 1000) % DUR); requestAnimationFrame(loop); })(start);
});
