/* «Farqi nimada?» — reels 1080×1920.
   Всё движение детерминировано: renderAt(t) рисует кадр для момента t (секунды).
   Тайминги сцен и слов приходят из timeline.js (его пишет tts.py по реальной озвучке). */
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
  inOutExpo: x => x <= 0 ? 0 : x >= 1 ? 1 : x < .5 ? Math.pow(2, 20 * x - 10) / 2 : (2 - Math.pow(2, -20 * x + 10)) / 2,
  outBack: x => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outBackS: x => { const c1 = 2.6, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
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
  let tr = 'translate(-50%,-50%) translate3d(' + (o.x || 0).toFixed(2) + 'px,' + (o.y || 0).toFixed(2) + 'px,' + (o.z || 0).toFixed(2) + 'px)';
  if (o.rx) tr += ' rotateX(' + o.rx.toFixed(3) + 'deg)';
  if (o.ry) tr += ' rotateY(' + o.ry.toFixed(3) + 'deg)';
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
/* трансформ SVG-узла */
const G = (el, x, y, s = 1, r = 0, op) => {
  el.setAttribute('transform', `translate(${x.toFixed(2)} ${y.toFixed(2)}) rotate(${r.toFixed(2)}) scale(${(typeof s === 'number' ? s : s.join(' '))})`);
  if (op != null) el.setAttribute('opacity', clamp(op).toFixed(3));
};

function h(tag, cls, html, parent) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}
/* уменьшает шрифт, чтобы строка влезла в ширину */
function fit(el, maxW) {
  const fs = parseFloat(getComputedStyle(el).fontSize);
  const w = el.scrollWidth;
  if (w > maxW) el.style.fontSize = (fs * maxW / w).toFixed(1) + 'px';
}

/* ---------- иконки ---------- */
const ICO = {
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.6 4.5L19 7"/></svg>',
  save: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"><path d="M6 3.5h12v17l-6-4.2-6 4.2Z"/></svg>',
  share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"><path d="M21 3 10 14"/><path d="M21 3 14.5 21l-4-7.5L3 9.5Z"/></svg>',
  plus: '<svg viewBox="0 0 24 24" width="40" height="40" fill="none" stroke="currentColor" stroke-width="3.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
};
/* человечек, ступни в (0,0), рост 140 */
const MAN = '<circle cx="0" cy="-110" r="30"/><path d="M-48 0V-38a48 48 0 0 1 96 0V0Z"/>';
const man = (cls, fill) => `<g class="${cls}" fill="${fill}">${MAN}</g>`;
function gearPath(r1, r2, n) {
  let d = '';
  for (let i = 0; i < n; i++) {
    const a = i / n * Math.PI * 2, s = Math.PI * 2 / n;
    const pts = [[r1, a - s * .5], [r1, a - s * .22], [r2, a - s * .14], [r2, a + s * .14], [r1, a + s * .22]];
    for (const [r, b] of pts) d += (d ? 'L' : 'M') + (r * Math.cos(b)).toFixed(1) + ' ' + (r * Math.sin(b)).toFixed(1);
  }
  return d + 'Z';
}

/* ---------- иллюстрации (viewBox 900×560, анимация по моментам ключевых слов) ---------- */
const ILL = {
  /* Kommunizm: классы-ступени выравниваются, частная собственность зачёркнута */
  equal: {
    svg: c => `
      <g class="cols">${[0, 1, 2].map(i => `<g class="c${i}"><rect class="col" x="-70" y="0" width="140" height="10" rx="18" fill="${rgb(c, .25 + i * .2)}"/>${man('m', i === 1 ? rgb(lighten(c, .15)) : '#F4F2FF')}</g>`).join('')}</g>
      <g class="eq"><circle r="58" fill="${rgb(c)}"/><path d="M-26 -12h52M-26 12h52" stroke="#0B0912" stroke-width="11" stroke-linecap="round"/></g>
      <g class="house"><path d="M-62 10 0-44 62 10V62H-62Z" fill="none" stroke="#F4F2FF" stroke-width="9" stroke-linejoin="round"/>
        <text x="0" y="48" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="54" fill="#F4F2FF">$</text>
        <path class="x" d="M-84 -60 84 90" stroke="${rgb(c)}" stroke-width="14" stroke-linecap="round" pathLength="1" stroke-dasharray="1 1"/></g>
      <path class="ground" d="M90 522H810" stroke="rgba(255,255,255,.22)" stroke-width="4" stroke-linecap="round"/>`,
    update(q, lt, k) {
      const eqk = E.outBack(P(lt, k[0] - .1, .7));
      const hs = [300, 190, 90].map(v => lerp(v, 160, eqk));
      q.c.forEach((g, i) => {
        const pop = E.outBackS(P(lt, .1 + i * .12, .5));
        const hh = hs[i] * pop;
        g.col.setAttribute('height', Math.max(10, hh).toFixed(1));
        g.col.setAttribute('y', (-Math.max(10, hh)).toFixed(1));
        G(g.m, 0, -hh - 4 + Math.sin(lt * 3 + i) * 3, .9 * pop);
        G(g.g, 270 + i * 180, 520);
      });
      const e = E.outBackS(P(lt, k[0] + .35, .5));
      G(q.eq, 450, 120 + (1 - e) * 30, e * (1 + .06 * pulse(lt, k[2], .05, .4)), (1 - e) * -90, e);
      const hp = E.outBackS(P(lt, k[1] - .15, .5));
      G(q.house, 790, 150, .8 * hp, 0, hp);
      q.x.setAttribute('stroke-dashoffset', (1 - E.outCubic(P(lt, k[1] + .45, .35))).toFixed(3));
    },
    init(svg) {
      return {
        c: [0, 1, 2].map(i => { const g = svg.querySelector('.c' + i); return { g, col: g.querySelector('.col'), m: g.querySelector('.m') }; }),
        eq: svg.querySelector('.eq'), house: svg.querySelector('.house'), x: svg.querySelector('.x'),
      };
    },
  },

  /* Sotsializm: общий ресурс в центре распределяется по кругу людей */
  share: {
    svg: c => `
      <ellipse class="ring" cx="450" cy="290" rx="300" ry="190" fill="none" stroke="${rgb(c, .5)}" stroke-width="4" stroke-dasharray="14 18"/>
      <g class="flow">${Array.from({ length: 18 }, () => `<circle r="9" fill="${rgb(lighten(c, .3))}"/>`).join('')}</g>
      <g class="core"><circle r="96" fill="${rgb(c)}"/><circle r="120" fill="none" stroke="${rgb(c, .35)}" stroke-width="6"/>
        ${[24, 0, -24].map(y => `<ellipse cx="0" cy="${y}" rx="44" ry="15" fill="#0B0912" opacity=".85"/><ellipse cx="0" cy="${y - 6}" rx="44" ry="15" fill="${rgb(lighten(c, .55))}"/>`).join('')}</g>
      <g class="ppl">${Array.from({ length: 6 }, (_, i) => man('p' + i, '#F4F2FF')).join('')}</g>`,
    init(svg) {
      return { ring: svg.querySelector('.ring'), flow: [...svg.querySelectorAll('.flow circle')], core: svg.querySelector('.core'),
        ppl: [...svg.querySelectorAll('.ppl g')] };
    },
    update(q, lt, k, c) {
      const cp = E.outBackS(P(lt, .05, .55));
      G(q.core, 450, 290, cp * (1 + .05 * Math.sin(lt * 5) + .1 * pulse(lt, k[0], .05, .45)), 0, cp);
      const pos = i => { const a = -Math.PI / 2 + i / 6 * Math.PI * 2; return [450 + 300 * Math.cos(a), 290 + 190 * Math.sin(a)]; };
      q.ppl.forEach((g, i) => {
        const p = E.outBackS(P(lt, .25 + i * .08, .45));
        const [x, y] = pos(i);
        const lit = P(lt, k[1] + i * .1, .25);
        g.setAttribute('fill', rgb(mix([244, 242, 255], lighten(c, .2), lit)));
        G(g, x, y + 60, .5 * p * (1 + .15 * pulse(lt, k[1] + i * .1, .05, .35)), 0, p);
      });
      q.flow.forEach((d, j) => {
        const i = j % 6, ph = ((lt - k[0]) * .9 + Math.floor(j / 6) / 3) % 1;
        const on = lt > k[0] + Math.floor(j / 6) * .33 / .9;
        const [x, y] = pos(i);
        const e = E.inOutCubic(ph);
        G(d, lerp(450, x, e), lerp(290, y + 10, e), 1 - .4 * e, 0, on ? Math.sin(Math.PI * ph) : 0);
      });
      const rp = P(lt, k[2] - .1, .5);
      q.ring.setAttribute('opacity', (.25 + .75 * rp).toFixed(3));
      q.ring.setAttribute('stroke-dashoffset', (-lt * 60).toFixed(1));
      q.ring.setAttribute('stroke-width', (4 + 4 * pulse(lt, k[2], .05, .5)).toFixed(2));
    },
  },

  /* Demokratiya: народ голосует, бюллетени падают в урну */
  ballot: {
    svg: c => `
      <g class="crowd">${[0, 1, 2, 3].map(i => man('cr' + i, i % 2 ? rgb(lighten(c, .35)) : '#F4F2FF')).join('')}</g>
      <g class="votes">${[0, 1, 2, 3, 4].map(() => `<g><rect x="-50" y="-66" width="100" height="132" rx="12" fill="#F4F2FF"/><path d="m-22 0 14 14 30-30" fill="none" stroke="${rgb(c)}" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/></g>`).join('')}</g>
      <g class="box"><rect x="-160" y="-40" width="320" height="230" rx="26" fill="${rgb(c)}"/><rect x="-160" y="-40" width="320" height="56" rx="20" fill="${rgb(lighten(c, .25))}"/>
        <rect x="-80" y="-18" width="160" height="14" rx="7" fill="#0B0912"/>
        <circle cx="0" cy="100" r="44" fill="#0B0912" opacity=".25"/><path d="m-20 100 13 13 27-27" fill="none" stroke="#F4F2FF" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/></g>
      <g class="ok"><circle r="52" fill="#F4F2FF"/><path d="m-22 2 14 14 30-30" fill="none" stroke="${rgb(c)}" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/></g>`,
    init(svg) {
      return { crowd: [...svg.querySelectorAll('.crowd g')], votes: [...svg.querySelectorAll('.votes > g')], box: svg.querySelector('.box'), ok: svg.querySelector('.ok') };
    },
    update(q, lt, k) {
      const bp = E.outBackS(P(lt, .05, .55));
      G(q.box, 450, 330, bp * (1 + .04 * pulse(lt, k[1], .05, .3)), 0, bp);
      const xs = [110, 230, 670, 790];
      q.crowd.forEach((g, i) => {
        const p = E.outBackS(P(lt, k[0] - .2 + i * .09, .45));
        G(g, xs[i], 525 + Math.sin(lt * 4 + i) * 2, .62 * p, 0, p);
      });
      q.votes.forEach((g, i) => {
        const start = .35 + i * .7;
        const ph = P(lt, start, .7);
        const y = lerp(-90, 300, E.inQuad(ph));
        const op = lt < start ? 0 : ph < 1 ? 1 : 0;
        G(g, 450 + (i % 2 ? 14 : -14) * (1 - ph), y, .9, (1 - ph) * (i % 2 ? 12 : -12), op);
      });
      const o = E.outBackS(P(lt, k[2] - .05, .5));
      G(q.ok, 735, 140, o, (1 - o) * -60, o);
    },
  },

  /* Respublika: корона зачёркнута, лидера выбирают голосованием */
  crown: {
    svg: c => `
      <g class="bld" opacity="0"><path d="M450 300 640 360H260Z" fill="none" stroke="rgba(255,255,255,.3)" stroke-width="7" stroke-linejoin="round"/>
        ${[300, 380, 460, 540, 600].map(x => `<rect x="${x - 14}" y="378" width="28" height="118" rx="6" fill="rgba(255,255,255,.18)"/>`).join('')}
        <rect x="240" y="502" width="420" height="22" rx="8" fill="rgba(255,255,255,.25)"/></g>
      <g class="crw"><path d="M-110 50-130-70-60-10 0-90 60-10 130-70 110 50Z" fill="#FFC93D" stroke="#0B0912" stroke-width="6" stroke-linejoin="round"/>
        <rect x="-112" y="50" width="224" height="34" rx="10" fill="#E3A21B"/>
        ${[-130, 0, 130].map((x, i) => `<circle cx="${x}" cy="${[-70, -90, -70][i]}" r="14" fill="#FFE59A"/>`).join('')}</g>
      <path class="cx" d="M140 90 400 360M400 90 140 360" stroke="#FF4D5E" stroke-width="20" stroke-linecap="round" pathLength="1" stroke-dasharray="1 1"/>
      <path class="arr" d="M410 230H520" stroke="${rgb(c)}" stroke-width="12" stroke-linecap="round" stroke-dasharray="1 1" pathLength="1"/>
      <path class="arrh" d="m500 200 34 30-34 30" fill="none" stroke="${rgb(c)}" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
      <g class="lead">${man('m', rgb(c))}<g class="st"><path d="M0-28 8-8 30-8 12 5 19 27 0 14-19 27-12 5-30-8-8-8Z" fill="#F4F2FF"/></g></g>
      <g class="vt"><rect x="-44" y="-56" width="88" height="112" rx="12" fill="#F4F2FF"/><path d="m-20 0 12 12 26-26" fill="none" stroke="${rgb(c)}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/></g>`,
    init(svg) {
      return { bld: svg.querySelector('.bld'), crw: svg.querySelector('.crw'), cx: svg.querySelector('.cx'), arr: svg.querySelector('.arr'), arrh: svg.querySelector('.arrh'),
        lead: svg.querySelector('.lead'), m: svg.querySelector('.lead .m'), st: svg.querySelector('.st'), vt: svg.querySelector('.vt') };
    },
    update(q, lt, k) {
      const cp = E.outBackS(P(lt, .05, .55));
      const fall = E.inOutCubic(P(lt, k[0] + .7, .6));
      G(q.crw, 270, 225 + fall * 30 + Math.sin(lt * 3) * 4 * (1 - fall), cp * (1 - .15 * fall), -fall * 14, cp * (1 - .55 * fall));
      q.cx.setAttribute('stroke-dashoffset', (1 - E.outCubic(P(lt, k[0] + .1, .45))).toFixed(3));
      q.arr.setAttribute('stroke-dashoffset', (1 - E.outCubic(P(lt, k[1] - .2, .35))).toFixed(3));
      q.arrh.setAttribute('opacity', P(lt, k[1] + .05, .15).toFixed(3));
      const lp = E.outBackS(P(lt, k[1] + .05, .55));
      G(q.lead, 660, 330 + (1 - lp) * 60, lp, 0, lp);
      G(q.m, 0, 0, 1.15);
      G(q.st, 0, -205, .9 + .12 * Math.sin(lt * 6), lt * 40);
      const vp = E.outBackS(P(lt, k[1] + .25, .45));
      G(q.vt, 790, 300 - Math.abs(Math.sin(lt * 4)) * 12 * vp, .8 * vp, 10, vp);
      const bp = E.outCubic(P(lt, k[2] - .1, .6));
      G(q.bld, 0, (1 - bp) * 80, 1, 0, bp);
    },
  },

  /* Millatchilik: флаг поднимается, щит защищает */
  shield: {
    svg: c => `
      <g class="rings">${[0, 1, 2].map(() => `<circle r="160" fill="none" stroke="${rgb(c)}" stroke-width="6"/>`).join('')}</g>
      <rect x="236" y="70" width="12" height="455" rx="6" fill="#F4F2FF"/><circle cx="242" cy="66" r="14" fill="#F4F2FF"/>
      <path class="flag" fill="${rgb(c)}"/>
      <path class="flag2" fill="rgba(255,255,255,.85)"/>
      <g class="sh"><path d="M0-150 125-104V-8c0 82-55 136-125 162C-70 128-125 74-125-8v-96Z" fill="${rgb(lighten(c, .1))}" stroke="#F4F2FF" stroke-width="10" stroke-linejoin="round"/>
        <path d="m-46 0 32 32 64-64" fill="none" stroke="#0B0912" stroke-width="18" stroke-linecap="round" stroke-linejoin="round"/></g>
      <g class="spk">${Array.from({ length: 8 }, () => `<path d="M0-16 4-4 16 0 4 4 0 16-4 4-16 0-4-4Z" fill="#F4F2FF"/>`).join('')}</g>`,
    init(svg) {
      return { flag: svg.querySelector('.flag'), flag2: svg.querySelector('.flag2'), sh: svg.querySelector('.sh'),
        rings: [...svg.querySelectorAll('.rings circle')], spk: [...svg.querySelectorAll('.spk path')] };
    },
    update(q, lt, k) {
      const up = E.outCubic(P(lt, .1, 1.1));
      const top = lerp(400, 84, up), fw = 250, fh = 150;
      const wave = (x, y) => y + Math.sin(x / 55 - lt * 6) * 10 * (x / fw);
      const band = (y0, y1) => {
        let d = '';
        for (let i = 0; i <= 20; i++) { const x = i / 20 * fw; d += (i ? 'L' : 'M') + (248 + x).toFixed(1) + ' ' + wave(x, top + y0).toFixed(1); }
        for (let i = 20; i >= 0; i--) { const x = i / 20 * fw; d += 'L' + (248 + x).toFixed(1) + ' ' + wave(x, top + y1).toFixed(1); }
        return d + 'Z';
      };
      q.flag.setAttribute('d', band(0, fh));
      q.flag2.setAttribute('d', band(fh * .42, fh * .58));
      const sp = E.outBackS(P(lt, k[2] - .1, .55));
      G(q.sh, 610, 330 + (1 - sp) * 80, sp * (1 + .04 * Math.sin(lt * 4)), (1 - sp) * 20, sp);
      q.rings.forEach((r, i) => {
        const ph = ((lt - k[2]) * .8 + i / 3) % 1;
        const on = lt > k[2] + i / 3 / .8;
        G(r, 610, 330, .9 + ph * .9, 0, on ? (1 - ph) * .6 : 0);
      });
      q.spk.forEach((s, i) => {
        const a = i / 8 * Math.PI * 2, p = P(lt, k[1], .8);
        G(s, 610 + Math.cos(a) * (60 + 170 * E.outCubic(p)), 300 + Math.sin(a) * (60 + 150 * E.outCubic(p)), 1.4 * (1 - p), p * 180, p > 0 && p < 1 ? 1 : 0);
      });
    },
  },

  /* Shovinizm: один на пьедестале, остальных принижают */
  podium: {
    svg: c => `
      <rect class="ped" x="-95" y="0" width="190" height="10" rx="16" fill="${rgb(c)}"/>
      <g class="hero">${man('m', rgb(lighten(c, .35)))}<path class="up" d="M0-210V-290M-30-262 0-292 30-262" fill="none" stroke="#F4F2FF" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/></g>
      <g class="sm">${[0, 1].map(i => `<g class="s${i}">${man('m', '#F4F2FF')}<path class="dn" d="M0-210V-150M-26-176 0-148 26-176" fill="none" stroke="#FF4D5E" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/></g>`).join('')}</g>
      <g class="warn"><path d="M0-62 64 50H-64Z" fill="#FF4D5E" stroke="#0B0912" stroke-width="6" stroke-linejoin="round"/><rect x="-6" y="-22" width="12" height="44" rx="6" fill="#0B0912"/><circle cx="0" cy="36" r="7.5" fill="#0B0912"/></g>
      <path d="M80 522H820" stroke="rgba(255,255,255,.22)" stroke-width="4" stroke-linecap="round"/>`,
    init(svg) {
      return { ped: svg.querySelector('.ped'), hero: svg.querySelector('.hero'), up: svg.querySelector('.up'), warn: svg.querySelector('.warn'),
        sm: [0, 1].map(i => { const g = svg.querySelector('.s' + i); return { g, m: g.querySelector('.m'), dn: g.querySelector('.dn') }; }) };
    },
    update(q, lt, k) {
      const rise = E.outBack(P(lt, k[0] - .25, .8));
      const ph = 40 + 220 * rise;
      q.ped.setAttribute('height', ph.toFixed(1));
      q.ped.setAttribute('y', (520 - ph).toFixed(1));
      q.ped.setAttribute('x', '355');
      const hp = E.outBackS(P(lt, .05, .5));
      G(q.hero, 450, 520 - ph - 4, hp * (.95 + .25 * rise), 0, hp);
      q.up.setAttribute('opacity', (P(lt, k[0] + .3, .3) * (.6 + .4 * Math.sin(lt * 6))).toFixed(3));
      const dim = E.outCubic(P(lt, k[1] - .1, .5));
      q.sm.forEach((s, i) => {
        const p = E.outBackS(P(lt, .2 + i * .1, .45));
        G(s.g, i ? 730 : 170, 520, p * (.85 - .25 * dim), 0, p * (1 - .45 * dim));
        s.dn.setAttribute('opacity', dim.toFixed(3));
        G(s.dn, 0, Math.sin(lt * 7 + i) * 6 * dim);
      });
      const w = E.outBackS(P(lt, k[1] + .2, .45));
      G(q.warn, 770, 120, w * (1 + .08 * Math.sin(lt * 8)), (1 - w) * 40, w);
    },
  },

  /* Kapitalizm: частный завод, рынок и гонка конкурентов */
  market: {
    svg: c => `
      <g class="fac"><path d="M0 0V-150L70-110V-150L140-110V-150L210-110V0Z" fill="#F4F2FF"/><rect x="150" y="-250" width="44" height="140" fill="#F4F2FF"/>
        ${[20, 85, 150].map(x => `<rect x="${x}" y="-80" width="36" height="36" rx="6" fill="#0B0912" opacity=".75"/>`).join('')}</g>
      <g class="smoke">${[0, 1, 2, 3].map(() => `<circle r="22" fill="rgba(255,255,255,.35)"/>`).join('')}</g>
      <g class="tag"><circle r="46" fill="${rgb(c)}"/><text y="18" text-anchor="middle" font-family="Unbounded" font-weight="900" font-size="54" fill="#0B0912">$</text></g>
      <g class="chart"><path d="M480 522H840" stroke="rgba(255,255,255,.3)" stroke-width="5" stroke-linecap="round"/>
        <rect class="b0" x="520" width="110" rx="16" fill="${rgb(c)}"/><rect class="b1" x="680" width="110" rx="16" fill="rgba(255,255,255,.85)"/></g>
      <path class="trend" fill="none" stroke="${rgb(lighten(c, .3))}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round" pathLength="1" stroke-dasharray="1 1" d="M490 300 570 240 640 270 720 170 820 110"/>
      <path class="trh" d="m780 96 44 10-14 42" fill="none" stroke="${rgb(lighten(c, .3))}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>`,
    init(svg) {
      return { fac: svg.querySelector('.fac'), smoke: [...svg.querySelectorAll('.smoke circle')], tag: svg.querySelector('.tag'),
        chart: svg.querySelector('.chart'), b: [svg.querySelector('.b0'), svg.querySelector('.b1')], trend: svg.querySelector('.trend'), trh: svg.querySelector('.trh') };
    },
    update(q, lt, k) {
      const fp = E.outBack(P(lt, .05, .6));
      G(q.fac, 90, 522, [1, fp], 0, fp > 0 ? 1 : 0);
      q.smoke.forEach((s, i) => {
        const ph = (lt * .55 + i / 4) % 1;
        G(s, 262 + ph * 40, 260 - ph * 200, .6 + ph * 1.4, 0, fp * (1 - ph) * .9);
      });
      const tp = E.outBackS(P(lt, k[0] - .1, .5));
      G(q.tag, 200, 300 - 40 * tp, tp * (1 + .08 * pulse(lt, k[0] + .3, .05, .4)), (1 - tp) * -120, tp);
      const cp = E.outCubic(P(lt, k[1] - .1, .5));
      q.chart.setAttribute('opacity', cp.toFixed(3));
      const race = P(lt, k[2] - .1, .3);
      q.b.forEach((b, i) => {
        const base = 120 + 60 * i;
        const hgt = cp * (base + race * (90 + 70 * Math.sin(lt * 4.2 + i * Math.PI)));
        b.setAttribute('height', Math.max(0, hgt).toFixed(1));
        b.setAttribute('y', (522 - hgt).toFixed(1));
      });
      q.trend.setAttribute('stroke-dashoffset', (1 - E.outCubic(P(lt, k[2] + .1, .8))).toFixed(3));
      q.trh.setAttribute('opacity', P(lt, k[2] + .8, .15).toFixed(3));
    },
  },

  /* Sotsializm (2): шестерня общего хозяйства, люди связаны с ней, государство в центре */
  gear: {
    svg: c => `
      <g class="lines">${Array.from({ length: 6 }, () => `<path stroke="${rgb(c, .7)}" stroke-width="6" stroke-linecap="round" stroke-dasharray="1 1" pathLength="1"/>`).join('')}</g>
      <g class="gear"><path d="${gearPath(118, 150, 12)}" fill="${rgb(c)}"/><circle r="84" fill="#0B0912" opacity=".35"/></g>
      <g class="gov"><path d="M0-58 56-28H-56Z" fill="#F4F2FF"/>${[-36, -12, 12, 36].map(x => `<rect x="${x - 7}" y="-20" width="14" height="48" rx="3" fill="#F4F2FF"/>`).join('')}<rect x="-60" y="32" width="120" height="14" rx="5" fill="#F4F2FF"/></g>
      <g class="ppl">${Array.from({ length: 6 }, (_, i) => man('p' + i, i % 2 ? rgb(lighten(c, .4)) : '#F4F2FF')).join('')}</g>`,
    init(svg) {
      return { gear: svg.querySelector('.gear'), gov: svg.querySelector('.gov'), lines: [...svg.querySelectorAll('.lines path')], ppl: [...svg.querySelectorAll('.ppl g')] };
    },
    update(q, lt, k) {
      const gp = E.outBackS(P(lt, .05, .6));
      G(q.gear, 450, 290, gp, lt * 40 + (1 - gp) * -90, gp);
      const pos = i => { const a = -Math.PI / 2 + (i + .5) / 6 * Math.PI * 2; return [450 + 330 * Math.cos(a), 290 + 205 * Math.sin(a)]; };
      q.ppl.forEach((g, i) => {
        const p = E.outBackS(P(lt, k[0] - .15 + i * .07, .45));
        const [x, y] = pos(i);
        G(g, x, y + 55, .5 * p, 0, p);
      });
      q.lines.forEach((l, i) => {
        const [x, y] = pos(i);
        const ang = Math.atan2(y - 290, x - 450);
        l.setAttribute('d', `M${(450 + 160 * Math.cos(ang)).toFixed(1)} ${(290 + 160 * Math.sin(ang)).toFixed(1)}L${(x - 50 * Math.cos(ang)).toFixed(1)} ${(y - 30 * Math.sin(ang)).toFixed(1)}`);
        l.setAttribute('stroke-dashoffset', (1 - E.outCubic(P(lt, k[1] - .1 + i * .06, .4))).toFixed(3));
      });
      const v = E.outBackS(P(lt, k[2] - .1, .5));
      G(q.gov, 450, 296, v * 1.05, 0, v);
    },
  },
};

/* ---------- караоке ---------- */
const nrm = w => w.toLowerCase().replace(/[^\p{L}\p{N}‘’ʻʼ']/gu, '');
function karaoke(box, words, keys = []) {
  const kset = new Set(keys.flat());
  const ws = words.map((w, i) => {
    const el = h('span', 'w', '<span class="mk"></span><span class="wt"></span>', box);
    el.querySelector('.wt').textContent = w.w;
    box.appendChild(document.createTextNode(' '));
    return { el, mk: el.querySelector('.mk'), t0: w.t0, t1: w.t1, key: kset.has(i) };
  });
  return ws;
}
/* style: 'cap' — субтитр, текущее слово цветом; 'def' — определение, ключевые слова с маркером */
function drawKaraoke(ws, t, col, style) {
  const ink = [244, 242, 255];
  for (const w of ws) {
    const p = E.outCubic(P(t, w.t0 - .05, .2));
    const cur = t >= w.t0 - .03 && t < w.t1 + .03;
    let c, op, s = 1;
    if (style === 'cap') {
      op = lerp(.34, 1, p);
      c = cur ? lighten(col, .1) : ink;
      s = 1 + .07 * pulse(t, w.t0 + .04, .06, .3);
    } else {
      op = lerp(.26, 1, p);
      c = w.key && p > 0 ? mix(ink, lighten(col, .25), p) : ink;
      s = 1 + (w.key ? .06 : .025) * pulse(t, w.t0 + .04, .06, .35);
    }
    w.el.style.transform = `translateY(${((1 - p) * 10).toFixed(2)}px) scale(${s.toFixed(4)})`;
    w.el.style.opacity = op.toFixed(3);
    w.el.style.color = rgb(c);
    if (w.key) {
      w.mk.style.background = rgb(col, .26);
      w.mk.style.transform = `scaleX(${E.outExpo(P(t, w.t0, .35)).toFixed(4)})`;
    }
  }
}

/* ---------- сборка сцен ---------- */
const root = $('#root'), cam = $('#cam'), L = $('#L');
const PAL0 = ['#FF4D5E', '#FFB020'];
let SC = [], fxc, fx, grainEl;
const scenes = TL.scenes;
const pairs = scenes.filter(s => s.type === 'pair');
const allTerms = pairs.flatMap(p => [p.a.term, p.b.term]);

function buildIntro(sc) {
  const el = h('div', 'pair', null, L);
  const marq = h('div', '', null, el); marq.id = 'marq';
  const rows = [];
  for (let i = 0; i < 7; i++) {
    const words = allTerms.slice(i % 8).concat(allTerms).slice(0, 8);
    const r = h('div', 'mrow outline', (words.join(' · ') + ' · ').repeat(2), marq);
    r.style.top = (90 + i * 260) + 'px';
    rows.push(r);
  }
  const tag = h('div', 'tag a', TL.title, el);
  const t1 = h('div', 'dis a', '2 SO‘Z', el); t1.id = 't1';
  const t2 = h('div', 'dis a grad', '1 FARQ', el); t2.id = 't2';
  fit(t1, 960); fit(t2, 960);
  const flip = h('div', 'a', null, el);
  flip.style.cssText = 'width:940px;height:120px;overflow:hidden;border-radius:60px;background:rgba(255,255,255,.07);border:2px solid rgba(255,255,255,.14)';
  const fl = pairs.map(p => {
    const d = h('div', 'recap', `<span style="color:${p.colors[0]}">${p.a.term}</span><em>≠</em><span style="color:${p.colors[1]}">${p.b.term}</span>`, flip);
    d.style.cssText = 'left:0;top:0;width:100%;height:100%;background:none;border:0;position:absolute';
    return d;
  });
  const caps = sc.lines.map(ln => {
    const box = h('div', 'cap a', null, el);
    return { box, ln, ws: karaoke(box, ln.words) };
  });
  return { sc, el, rows, tag, t1, t2, flip, fl, caps };
}

function buildPair(sc) {
  const [cA, cB] = sc.colors.map(hex);
  const el = h('div', 'pair', null, L);
  const clash = h('div', 'full', null, el);
  const num = h('div', 'num a', String(sc.i + 1).padStart(2, '0'), clash);
  const wA = h('div', 'dis a', sc.a.term, clash), wB = h('div', 'dis a', sc.b.term, clash);
  wA.style.cssText = `font-size:150px;color:${sc.colors[0]}`;
  wB.style.cssText = `font-size:150px;color:${sc.colors[1]}`;
  fit(wA, 940); fit(wB, 940);
  const vs = h('div', 'vs a', `<svg viewBox="-110 -110 220 220"><path fill="#F4F2FF" d="${(() => {
    let d = ''; for (let i = 0; i < 24; i++) { const a = i / 24 * Math.PI * 2, r = i % 2 ? 72 : 104; d += (i ? 'L' : 'M') + (r * Math.cos(a)).toFixed(1) + ' ' + (r * Math.sin(a)).toFixed(1); } return d + 'Z'; })()}"/></svg><b>VS</b>`, clash);
  const qbox = h('div', 'cap a', null, clash);
  const qws = karaoke(qbox, sc.q.words);

  const card = (k, c, idx) => {
    const d = sc[k];
    const cd = h('div', 'card a', null, el);
    const glow = h('div', 'glow', null, cd);
    glow.style.background = `radial-gradient(closest-side,${rgb(c, .55)},${rgb(c, 0)})`;
    const ill = ILL[d.icon];
    const svgBox = h('div', 'ill', `<svg viewBox="0 0 900 560" width="900" height="560">${ill.svg(c)}</svg>`, cd);
    const lbl = h('div', 'lbl', `${idx}-tushuncha`, cd);
    const term = h('div', 'term', d.term, cd); term.style.color = rgb(c);
    const bar = h('div', 'bar', null, cd); bar.style.background = `linear-gradient(90deg,${rgb(c)},${rgb(c, 0)})`;
    const def = h('div', 'def', null, cd);
    const ws = karaoke(def, d.line.words.slice(1), d.keys);
    return { d, c, cd, glow, ill, q: ill.init(svgBox.querySelector('svg')), lbl, term, bar, def, ws, termW: d.line.words[0] };
  };
  const A = card('a', cA, 1), B = card('b', cB, 2);
  fit(A.term, 860); fit(B.term, 860);

  // итоговое сравнение
  const sum = h('div', 'full', null, el);
  const st = h('div', 'sumt a', 'Qisqa farq', sum);
  const blk = (d, c) => {
    const b = h('div', 'blk a', null, sum);
    b.style.background = `linear-gradient(135deg,${rgb(c, .2)},rgba(255,255,255,.04) 60%)`;
    b.style.borderColor = rgb(c, .45);
    const bt = h('div', 'bt', d.term, b); bt.style.color = rgb(c);
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
  return { sc, cA, cB, el, clash, num, wA, wB, vs, qbox, qws, A, B, sum, st, bA, bB, neq };
}

function buildOutro(sc) {
  const el = h('div', 'pair', null, L);
  const tag = h('div', 'sumt a', 'Eslab qoling', el);
  const rec = pairs.map(p => h('div', 'recap a', `<span style="color:${p.colors[0]}">${p.a.term}</span><em>≠</em><span style="color:${p.colors[1]}">${p.b.term}</span>`, el));
  rec.forEach(r => fit(r, 900));
  const act = (ico, txt) => { const a = h('div', 'act a', `<div class="ic">${ico}</div><span>${txt}</span>`, el); return { a, ic: a.querySelector('.ic') }; };
  const sv = act(ICO.save, 'Saqlang'), sh = act(ICO.share, 'Ulashing');
  const fol = h('div', 'a', `${ICO.plus}<span>Obuna bo‘ling</span>`, el); fol.id = 'follow';
  const caps = sc.lines.map(ln => { const box = h('div', 'cap a', null, el); return { box, ln, ws: karaoke(box, ln.words) }; });
  const wt = re => { for (const c of caps) for (const w of c.ws) if (re.test(nrm(w.el.textContent))) return w.t0; return sc.t0 + 1; };
  return { sc, el, tag, rec, sv, sh, fol, caps, tSave: wt(/^saqlab/), tShare: wt(/^ulashing/), tFol: wt(/^obuna/) };
}

/* ---------- фон: частицы и искры ---------- */
const R = rng(11);
const DOTS = Array.from({ length: 70 }, () => ({ x: R() * W, y: R() * H, v: 20 + R() * 70, r: 1.5 + R() * 5, ph: R() * 6.28, k: R() < .5 ? 0 : 1, a: .15 + R() * .45 }));
const BURSTS = [];
function drawFx(t, pal) {
  fx.clearRect(0, 0, W, H);
  for (const d of DOTS) {
    const y = ((d.y - d.v * t) % (H + 80) + H + 80) % (H + 80) - 40;
    const x = d.x + Math.sin(t * .6 + d.ph) * 30;
    fx.fillStyle = rgb(lighten(pal[d.k], .2), d.a * (.6 + .4 * Math.sin(t * 2 + d.ph)));
    fx.beginPath(); fx.arc(x, y, d.r, 0, 6.283); fx.fill();
  }
  for (const b of BURSTS) {
    const lt = t - b.t;
    if (lt < 0 || lt > 1.1) continue;
    const rr = rng(b.seed);
    for (let i = 0; i < b.n; i++) {
      const a = rr() * 6.283, sp = b.sp * (.4 + rr() * .9), len = 18 + rr() * 40;
      const dist = sp * E.outCubic(clamp(lt / 1.1));
      const x = b.x + Math.cos(a) * dist, y = b.y + Math.sin(a) * dist + 120 * lt * lt;
      fx.strokeStyle = rgb(i % 3 ? [255, 255, 255] : b.c, (1 - lt / 1.1) * .9);
      fx.lineWidth = 3 + rr() * 3;
      fx.beginPath(); fx.moveTo(x, y); fx.lineTo(x - Math.cos(a) * len * (1 - lt), y - Math.sin(a) * len * (1 - lt)); fx.stroke();
    }
  }
}

function init() {
  fxc = $('#fx'); fx = fxc.getContext('2d');
  // зерно
  const g = document.createElement('canvas'); g.width = g.height = 256;
  const gx = g.getContext('2d'), id = gx.createImageData(256, 256), gr = rng(5);
  for (let i = 0; i < id.data.length; i += 4) { const v = gr() * 255; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255; }
  gx.putImageData(id, 0, 0);
  grainEl = $('#grain'); grainEl.style.backgroundImage = `url(${g.toDataURL()})`;
  // HUD
  $('#brand span').textContent = TL.title;
  pairs.forEach(() => h('div', '', '<i></i>', $('#bars')));
  // сцены
  SC = scenes.map(sc => sc.type === 'intro' ? buildIntro(sc) : sc.type === 'pair' ? buildPair(sc) : buildOutro(sc));
  // искры на столкновениях и итогах
  pairs.forEach((p, i) => {
    BURSTS.push({ t: p.t0 + .3, x: 540, y: 920, c: hex(p.colors[0]), n: 26, sp: 520, seed: 100 + i });
    BURSTS.push({ t: p.sum + .4, x: 540, y: 905, c: hex(p.colors[1]), n: 18, sp: 380, seed: 200 + i });
  });
  const out = scenes[scenes.length - 1];
  BURSTS.push({ t: SC[SC.length - 1].tFol, x: 540, y: 1290, c: hex(PAL0[0]), n: 24, sp: 460, seed: 300 });
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
/* шторка между сценами: (k: −1…1, 0 — полностью закрыто) */
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

  // камера: удары
  let shake = 0;
  for (const p of pairs) shake += pulse(t, p.t0 + .3, .01, .5) * 18 + pulse(t, p.sum + .35, .01, .35) * 8;
  const sr = rng(Math.floor(t * 60));
  const zoom = 1 + .012 * Math.sin(t * .7);
  cam.style.transform = `translate(${((sr() - .5) * shake).toFixed(2)}px,${((sr() - .5) * shake).toFixed(2)}px) scale(${zoom.toFixed(4)})`;

  // фон
  S($('#bgA'), { x: 260 + Math.sin(t * .4) * 120, y: 420 + Math.cos(t * .33) * 140, s: 1 + .08 * Math.sin(t * .9) });
  $('#bgA').style.background = `radial-gradient(closest-side,${rgb(pal[0], .34)},${rgb(pal[0], 0)})`;
  S($('#bgB'), { x: 820 + Math.cos(t * .37) * 120, y: 1500 + Math.sin(t * .29) * 160, s: 1 + .08 * Math.cos(t * .8) });
  $('#bgB').style.background = `radial-gradient(closest-side,${rgb(pal[1], .3)},${rgb(pal[1], 0)})`;
  S($('#grid'), { x: 540, y: 960 - (t * 18) % 60, o: 1 });
  drawFx(t, pal);
  const gr = rng(Math.floor(t * 30) + 1);
  grainEl.style.backgroundPosition = `${Math.floor(gr() * 256)}px ${Math.floor(gr() * 256)}px`;

  // вспышка
  let fl = 0;
  for (const p of pairs) fl += pulse(t, p.t0 + .3, .02, .3) * .55;
  fl += pulse(t, .18, .02, .35) * .7;
  vis($('#flash'), fl);

  // HUD
  const first = pairs[0], last = pairs[pairs.length - 1];
  const hudOp = P(t, first.t0, .5) * (1 - P(t, last.t1, .4));
  const cur = pairs.reduce((a, p, i) => t >= p.t0 - .01 ? i : a, 0);
  vis($('#hud'), hudOp);
  $('#hud').style.transform = `translateY(${((1 - E.outCubic(P(t, first.t0, .6))) * -40).toFixed(1)}px)`;
  $('#count').innerHTML = `<b>${cur + 1}</b><span>/${pairs.length}</span>`;
  [...$('#bars').children].forEach((b, i) => { b.firstChild.style.width = (P(t, pairs[i].t0, pairs[i].t1 - pairs[i].t0) * 100).toFixed(2) + '%'; });

  for (const s of SC) {
    const on = t >= s.sc.t0 - .01 && t < s.sc.t1;
    s.el.style.display = on ? 'block' : 'none';
    if (!on) continue;
    if (s.sc.type === 'intro') drawIntro(s, t, pal);
    else if (s.sc.type === 'pair') drawPair(s, t);
    else drawOutro(s, t, pal);
  }

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

function drawCaps(caps, t, col, y) {
  caps.forEach((c, i) => {
    const nx = caps[i + 1];
    const tIn = c.ln.t0 - .22, tOut = nx ? Math.max(c.ln.t1, nx.ln.t0 - .42) : c.ln.t1 + 99;
    const pin = E.outExpo(P(t, tIn, .35)), pout = E.inCubic(P(t, tOut, .2));
    S(c.box, { x: 540, y: y + (1 - pin) * 50 - pout * 30, o: pin * (1 - pout), s: .96 + .04 * pin });
    if (pin > 0 && pout < 1) drawKaraoke(c.ws, t, col, 'cap');
  });
}

function drawIntro(s, t, pal) {
  const end = s.sc.t1;
  const out = E.inCubic(P(t, end - .45, .45));
  s.rows.forEach((r, i) => {
    const dir = i % 2 ? 1 : -1, w = r.scrollWidth / 2;
    const x = ((dir * t * (90 + i * 12)) % w + w) % w;
    r.style.transform = `translateX(${(-x).toFixed(1)}px)`;
    r.style.opacity = (.12 * P(t, .1 + i * .05, .5)).toFixed(3);
  });
  const a1 = P(t, .12, .32), a2 = P(t, .5, .32);
  S(s.t1, { x: 540 + Math.sin(t * 2) * 4, y: 640 - out * 120, s: lerp(2.6, 1, E.outExpo(a1)) * (1 + out * .4), o: (a1 > 0 ? 1 : 0) * (1 - out), b: (1 - E.outCubic(a1)) * 20 + out * 14 });
  S(s.t2, { x: 540, y: 900 - out * 60, s: lerp(2.6, 1, E.outExpo(a2)) * (1 + out * .5), o: (a2 > 0 ? 1 : 0) * (1 - out), b: (1 - E.outCubic(a2)) * 20 + out * 14 });
  S(s.tag, { x: 540, y: 430 - (1 - E.outCubic(P(t, .9, .5))) * 30, o: P(t, .9, .4) * (1 - out) });
  const fp = E.outBackS(P(t, 1.1, .5));
  S(s.flip, { x: 540, y: 1140, s: fp, o: fp * (1 - out) });
  // карусель пар
  const step = .62, raw = Math.max(0, t - 1.4) / step, n = s.fl.length;
  const ph = Math.floor(raw) + E.inOutCubic(clamp((raw % 1) / .45));
  s.fl.forEach((d, i) => {
    const rel = ((i - ph) % n + n) % n;     // 0 — в окне
    const k = rel > n - 1 ? rel - n : rel;
    const y = k * 120;
    d.style.transform = `translateY(${y.toFixed(1)}px)`;
    d.style.opacity = clamp(1 - Math.abs(k)).toFixed(3);
  });
  drawCaps(s.caps, t, pal[0], 1420);
  s.caps.forEach(c => { c.box.style.opacity = (parseFloat(c.box.style.opacity) * (1 - out)).toFixed(3); });
}

function drawCard(C, t, tin, tout, from, to, active) {
  const pin = P(t, tin - .05, .6), pout = P(t, tout - .05, .5);
  const ei = E.outExpo(pin), eo = E.inOutCubic(pout);
  const base = { x: 540, y: 316 + 625, o: 1 };
  const o = Object.assign({}, base);
  o.x += from.x * (1 - ei) + to.x * eo;
  o.y += from.y * (1 - ei) + to.y * eo;
  o.ry = (from.ry || 0) * (1 - ei) + (to.ry || 0) * eo;
  o.rx = (from.rx || 0) * (1 - ei);
  o.s = 1 - (to.s || 0) * eo;
  o.o = (pin > 0 ? 1 : 0) * (1 - (to.fade ? eo : 0));
  S(C.cd, o);
  if (!(pin > 0 && pout < 1)) return;
  const lt = t - tin;
  const kt = C.d.kt.map(x => x - tin);
  C.ill.update(C.q, lt, kt, C.c);
  // термин звучит — подпрыгивает
  const tp = E.outExpo(P(t, tin + .15, .5));
  const bump = pulse(t, C.termW.t0 + .05, .06, .4);
  C.term.style.transform = `translateX(${((1 - tp) * -60).toFixed(1)}px) scale(${(1 + .06 * bump).toFixed(4)})`;
  C.term.style.opacity = tp.toFixed(3);
  C.lbl.style.opacity = (.6 * P(t, tin + .1, .4)).toFixed(3);
  C.bar.style.transform = `scaleX(${E.outExpo(P(t, tin + .35, .6)).toFixed(4)})`;
  C.glow.style.transform = `translate(${(Math.sin(t * .8) * 40).toFixed(1)}px,${(Math.cos(t * .6) * 30).toFixed(1)}px)`;
  drawKaraoke(C.ws, t, C.c, 'def');
}

function drawPair(s, t) {
  const sc = s.sc, T0 = sc.t0, TA = sc.a.t0, TB = sc.b.t0, TS = sc.sum, T1 = sc.t1;
  // — столкновение —
  const hit = T0 + .3;
  if (t < TA + .6) {
    s.clash.style.display = 'block';
    const out = E.inCubic(P(t, TA - .1, .4));
    const np = E.outBackS(P(t, T0 + .05, .5));
    S(s.num, { x: 540, y: 470 - out * 80, s: np * (1 - out * .3), r: (1 - np) * -120, o: np * (1 - out) });
    s.num.style.color = rgb(s.cA);
    const appr = E.inQuad(P(t, T0, .3));
    const rec = pulse(t, hit, .001, .45);
    const fl = Math.sin(t * 2.2) * 6;
    S(s.wA, { x: lerp(-700, 540, appr) - rec * 40, y: 760 + fl - out * 160, sk: rec * -12, s: 1 - out * .2, o: (t >= T0 ? 1 : 0) * (1 - out), b: out * 10 });
    S(s.wB, { x: lerp(1780, 540, appr) + rec * 40, y: 1080 - fl - out * 160, sk: rec * 12, s: 1 - out * .2, o: (t >= T0 ? 1 : 0) * (1 - out), b: out * 10 });
    const vp = E.outBackS(P(t, hit, .45));
    S(s.vs, { x: 540, y: 920 - out * 160, s: vp * (1 + .05 * Math.sin(t * 9)) * (1 - out * .4), r: (1 - vp) * -25, o: vp * (1 - out) });
    s.vs.querySelector('svg').style.transform = `rotate(${((1 - vp) * 200 + t * 20).toFixed(2)}deg)`;
    s.vs.querySelector('svg path').setAttribute('fill', rgb(mix(s.cA, s.cB, .5 + .5 * Math.sin(t * 3))));
    drawCaps([{ box: s.qbox, ln: sc.q, ws: s.qws }], t, s.cB, 1330);
    s.qbox.style.opacity = (parseFloat(s.qbox.style.opacity) * (1 - out)).toFixed(3);
  } else s.clash.style.display = 'none';

  // — карточки —
  drawCard(s.A, t, TA, TB, { x: 0, y: 1300, rx: -30 }, { x: -1250, y: 0, ry: 35 });
  drawCard(s.B, t, TB, TS, { x: 1250, y: 0, ry: -35 }, { x: 0, y: -200, s: .12, fade: true });

  // — итог —
  if (t >= TS - .05) {
    s.sum.style.display = 'block';
    const hA = s.bA.b.offsetHeight, hB = s.bB.b.offsetHeight;
    const gap = 120, top = Math.max(400, 990 - (hA + gap + hB) / 2);
    const yA = top + hA / 2, yB = top + hA + gap + hB / 2;
    const pA = E.outExpo(P(t, TS + .05, .6)), pB = E.outExpo(P(t, TS + .2, .6));
    S(s.st, { x: 540, y: 380, o: P(t, TS + .1, .3) });
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
}

function drawOutro(s, t, pal) {
  const T0 = s.sc.t0;
  S(s.tag, { x: 540, y: 380, o: P(t, T0 + .2, .4) });
  s.rec.forEach((r, i) => {
    const p = E.outExpo(P(t, T0 + .25 + i * .12, .6));
    S(r, { x: 540 + (1 - p) * (i % 2 ? 1100 : -1100), y: 480 + i * 124, o: p > 0 ? 1 : 0 });
  });
  const pop = (o, t0, x) => {
    const p = E.outBackS(P(t, t0 - .15, .5));
    const b = pulse(t, t0 + .1, .05, .45);
    S(o.a, { x, y: 1085, s: p * (1 + .12 * b), o: p });
    o.ic.style.borderColor = rgb(pal[0], .3 + .7 * clamp(b + P(t, t0, .3) * .4));
    o.ic.style.color = rgb(mix([244, 242, 255], lighten(pal[0], .2), P(t, t0, .3)));
  };
  pop(s.sv, s.tSave, 380);
  pop(s.sh, s.tShare, 700);
  const fp = E.outBackS(P(t, s.tFol - .15, .5));
  S(s.fol, { x: 540, y: 1300, s: fp * (1 + .04 * Math.sin((t - s.tFol) * 7) * P(t, s.tFol + .4, .3)), o: fp });
  drawCaps(s.caps, t, pal[1], 1500);
  // финальное затемнение
  vis($('#flash'), 0);
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
