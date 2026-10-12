/* Выполняется внутри index.html (Playwright, см. export.mjs).
   Описывает слои будущего проекта After Effects и по кадрам записывает их движение.
   Два способа записи:
     'S' — элемент двигается функцией S() из motion.js: берём её параметры (x, y, s, r, o, b, rx, ry) как есть;
     'G' — вложенный элемент: перемножаем CSS-трансформы по цепочке родителей до корня композиции. */
(function () {
  'use strict';
  const q = s => document.querySelector(s);
  const qa = s => [...document.querySelectorAll(s)];

  /* ---------- композиции: корень DOM, масштаб (px композиции на CSS px), окно во времени ---------- */
  const SCN = [[0, 2], [2, 4], [4, 8], [8, 10], [10, 14], [14, 18], [18, 22], [22, 25], [25, 30]];
  const COMPS = {
    MAIN: { name: 'MAXWAY KLABJON 1+1 · 1080×1920', root: '#root', u: 1, w: 1080, h: 1920, start: 0, dur: 30, bg: [118, 105, 175] },
    PHONE: { name: 'Телефон · приложение Maxway', root: '#phone', u: 2, w: 828, h: 1736, start: 10, dur: 8.1 },
    MAP: { name: 'Карта доставки', root: '#map', u: 2, w: 2000, h: 2200, start: 22, dur: 3 },
    TAPEA: { name: 'Лента · АКЦИЯ 1+1', root: '#tapeA', u: 2, w: 5200, h: 240, start: 2, dur: 2 },
    TAPEB: { name: 'Лента · ВТОРОЙ В ПОДАРОК', root: '#tapeB', u: 2, w: 5200, h: 240, start: 2, dur: 2 },
    TAPEN: { name: 'Лента · только на доставку', root: '#tapeB', u: 2, w: 5200, h: 240, start: 24, dur: 1 },
  };
  const SNAME = ['01 Хук · КУПИ ОДИН', '02 Пилюля 1+1', '03 Продукт KLABJON', '04 Не клаб-сэндвич', '05 Приложение · главная',
    '06 Корзина · 0 сум', '07 Один + один', '08 Доставка 40 мин', '09 Финал'];
  SCN.forEach(([a, b], i) => COMPS['S' + (i + 1)] = { name: SNAME[i], root: '#sc' + (i + 1), u: 1, w: 1080, h: 1920, start: a, dur: b - a });

  /* ---------- шрифты: CSS → PostScript-имена для AE ---------- */
  const PS = {
    Unbounded: { 700: 'Unbounded-Bold', 800: 'Unbounded-ExtraBold', 900: 'Unbounded-Black' },
    Rubik: { 400: 'Rubik-Regular', 500: 'Rubik-Medium', 600: 'Rubik-SemiBold', 700: 'Rubik-Bold', 800: 'Rubik-ExtraBold' },
  };
  const rgb = s => { const m = /rgba?\(([^)]+)\)/.exec(s); if (!m) return [0, 0, 0, 0]; const p = m[1].split(',').map(parseFloat); return [p[0], p[1], p[2], p[3] == null ? 1 : p[3]]; };

  /* ---------- список слоёв ---------- */
  const SPECS = [];
  let uid = 0;
  function L(comp, kind, name, el, o = {}) {
    if (typeof el === 'string') el = q(el);
    if (!el && !o.virtual) throw new Error('нет элемента для ' + name);
    const s = Object.assign({ id: ++uid, comp, kind, name, el, mode: 'G', cap: {} }, o);
    SPECS.push(s);
    return s;
  }
  const ins = (comp) => COMPS[comp];

  // MAIN — фон
  L('MAIN', 'bgsolids', 'Фон', null, { virtual: true, special: 'bg' });
  L('MAIN', 'png', 'Точки · белые', '#dots', { special: 'dots', variant: 'white', cap: { prep: el => { el.style.backgroundImage = 'radial-gradient(circle,#ffffff 2.6px,transparent 3.2px)'; } } });
  L('MAIN', 'png', 'Точки · фиолетовые', '#dots', { special: 'dots', variant: 'purple', cap: { prep: el => { el.style.backgroundImage = 'radial-gradient(circle,#7669AF 2.6px,transparent 3.2px)'; } } });
  L('MAIN', 'png', 'Лучи', '#rays', { mode: 'S', dsf: 1 });
  for (let i = 1; i <= 9; i++) L('MAIN', 'comp', COMPS['S' + i].name, null, { virtual: true, src: 'S' + i, cam: 1 });
  L('MAIN', 'comp', COMPS.PHONE.name, '#phone', { mode: 'S', src: 'PHONE', cam: 1, threeD: 1,
    shadow: { color: [20, 10, 50], alpha: .35, dist: 30, soft: 60 } });
  L('MAIN', 'png', 'Наклейка · 40 000 сум', '#st40', { mode: 'S', cam: 1 });
  L('MAIN', 'png', 'Наклейка · +1 в подарок', '#stGift', { mode: 'S', cam: 1 });
  L('MAIN', 'png', 'Наклейка · экономия', '#stSave', { mode: 'S', cam: 1 });
  qa('#conf .conf').forEach((el, i) => {
    const cs = getComputedStyle(el);
    L('MAIN', 'shape', 'Конфетти ' + (i + 1), el, { mode: 'S', cam: 1,
      shape: { type: 'rect', size: [parseFloat(cs.width), parseFloat(cs.height)], round: cs.borderRadius === '50%' ? 10 : 4, fill: rgb(cs.backgroundColor) } });
  });
  L('MAIN', 'comp', COMPS.TAPEA.name, '#tapeA', { mode: 'S', src: 'TAPEA', cam: 1, win: [2, 4], shadow: { color: [30, 15, 60], alpha: .18, dist: 14, soft: 0 } });
  L('MAIN', 'comp', COMPS.TAPEB.name, '#tapeB', { mode: 'S', src: 'TAPEB', cam: 1, win: [2, 4], shadow: { color: [30, 15, 60], alpha: .18, dist: 14, soft: 0 } });
  L('MAIN', 'comp', COMPS.TAPEN.name, '#tapeB', { mode: 'S', src: 'TAPEN', cam: 1, win: [24, 25], shadow: { color: [30, 15, 60], alpha: .18, dist: 14, soft: 0 } });
  qa('.wb').forEach((el, i) => L('MAIN', 'solid', 'Шторка ' + (i + 1), el, { mode: 'S', split: 'bg', size: [parseFloat(getComputedStyle(el).width), 2720] }));
  qa('#hud span').forEach(el => L('MAIN', 'text', 'HUD · ' + el.textContent, el,
    { just: el.classList.contains('tr') || el.classList.contains('br') ? 'R' : 'L', dyn: el.id === 'hudT' ? 'text+color' : 'color' }));
  L('MAIN', 'solid', 'Вспышка', '#flash', { special: 'flash', color: [255, 255, 255] });
  L('MAIN', 'adj', 'Зерно плёнки', null, { virtual: true });
  L('MAIN', 'png', 'Виньетка', '#vig', { dsf: 1, special: 'static' });

  // 1. Хук: по слову на долю, контурные эхо
  qa('#sc1 .big.outline').forEach((el, j) => L('S1', 'png', 'Эхо ' + (j % 2 ? '↓' : '↑') + ((j >> 1) + 1), el,
    { mode: 'S', split: 'text', keepf: 1, dedupe: 'echo' }));
  L('S1', 'text', 'Слово', '#w1', { mode: 'S', split: 'text' });

  // 2. 1+1
  L('S2', 'png', 'Пилюля 1+1', '#pill', { mode: 'S', cap: { hide: ['.pc'] } });
  qa('#pill .pc').forEach((el, i) => L('S2', 'text', 'Пилюля · ' + ['1', '+', '1'][i], el));
  L('S2', 'text', 'при покупке KLABJON', '#s2a', { mode: 'S' });
  L('S2', 'text', 'второй — в подарок', '#s2b', { mode: 'S' });

  // 3. Продукт
  qa('#kTitle .ch').forEach(el => el.classList.contains('badgeL')
    ? L('S3', 'png', 'KLABJON · значок L', el)
    : L('S3', 'text', 'KLABJON · ' + el.textContent, el));
  const lines = qa('#kLines line'), dots = qa('#kLines circle');
  lines.forEach((ln, i) => {
    L('S3', 'line', 'Выноска · линия ' + (i + 1), ln, { special: 'line' });
    L('S3', 'shape', 'Выноска · точка ' + (i + 1), dots[i], { special: 'dot', shape: { type: 'ellipse', size: [20, 20], fill: [255, 255, 255, 1] } });
  });
  L('S3', 'png', 'Тень сэндвича', '#kShadow', { mode: 'S' });
  L('S3', 'img', 'Сэндвич KLABJON', '#kSand', { mode: 'S' });
  L('S3', 'png', 'Штамп 385 г', '#kStamp', { mode: 'S' });
  L('S3', 'png', 'Рейтинг 4.0', '#kRate', { mode: 'S' });
  L('S3', 'png', 'Новинка в Maxway', '#kNew', { mode: 'S' });
  qa('#sc3 .call').forEach(el => L('S3', 'png', 'Подпись · ' + el.textContent, el, { mode: 'S' }));

  // 4. Не клаб-сэндвич
  L('S4', 'text', 'все знают', '#cl0', { mode: 'S' });
  L('S4', 'text', 'КЛАБ-', '#cl1', { mode: 'S' });
  L('S4', 'text', 'СЭНДВИЧ?', '#cl2', { mode: 'S' });
  ['#stk1', '#stk2'].forEach((s, i) => L('S4', 'shape', 'Маркер ' + (i + 1), s, { mode: 'S', special: 'strike',
    shape: { type: 'rect', size: [0, 34], round: 17, fill: [224, 49, 43, 1] } }));
  L('S4', 'text', 'KLABJON', '#kj .tx');
  L('S4', 'png', 'KLABJON · значок L', '#kj .badgeL');
  L('S4', 'png', 'альтернатива клаб-сэндвичу', '#alt', { mode: 'S' });
  L('S4', 'text', 'только в Maxway', '#alt2', { mode: 'S' });

  // 5. Приложение (фон)
  qa('#mq .mrow').forEach((el, i) => L('S5', 'png', 'Бегущая строка ' + (i + 1), el, { keepf: 1, part: 'mq' }));
  L('S5', 'text', 'ЗАКАЖИ', '#h5a', { mode: 'S' });
  L('S5', 'text', 'В ПРИЛОЖЕНИИ', '#h5b', { mode: 'S' });

  // 6. Корзина (фон)
  L('S6', 'shape', 'Оранжевый круг', '#orCirc', { mode: 'S', shape: { type: 'ellipse', size: [200, 200], fill: [237, 107, 47, 1] } });
  L('S6', 'text', 'ВТОРОЙ', '#z1', { mode: 'S' });
  L('S6', 'text', '0 СУМ', '#z2', { mode: 'S' });

  // 7. Один + один
  L('S7', 'text', 'ВТОРОЙ', '#t7a', { mode: 'S' });
  L('S7', 'text', 'В ПОДАРОК', '#t7b', { mode: 'S' });
  L('S7', 'text', 'KLABJON', '#h7 .tx');
  L('S7', 'png', 'KLABJON · значок L', '#h7 .badgeL');
  L('S7', 'text', 'при покупке KLABJON второй в подарок', '#h7s', { mode: 'S' });
  L('S7', 'img', 'Ключевой визуал с бантом', '#hero', { mode: 'S' });
  L('S7', 'png', 'Пилюля 1+1 (малая)', '#heroPill', { mode: 'S' });
  L('S7', 'png', 'Тень 1', '#sh7a', { mode: 'S' });
  L('S7', 'png', 'Тень 2', '#sh7b', { mode: 'S' });
  ['#g3', '#g2', '#g1'].forEach((s, i) => L('S7', 'img', 'Шлейф ' + (3 - i), s, { mode: 'S' }));
  L('S7', 'img', 'Сэндвич 1', '#sA', { mode: 'S' });
  L('S7', 'img', 'Сэндвич 2 (подарок)', '#sB', { mode: 'S' });
  L('S7', 'png', 'Бант', '#bow', { mode: 'S' });
  L('S7', 'png', 'Бирка БЕСПЛАТНО', '#tag', { mode: 'S' });
  L('S7', 'text', '1', '#n1', { mode: 'S' });
  L('S7', 'text', '+1', '#n2', { mode: 'S' });

  // 8. Доставка
  L('S8', 'text', '40 МИН', '#m40', { mode: 'S', dyn: 'text' });
  L('S8', 'text', 'и KLABJON у тебя дома', '#m40s', { mode: 'S' });
  L('S8', 'comp', COMPS.MAP.name, '#map', { mode: 'S', src: 'MAP', shadow: { color: [20, 10, 50], alpha: .25, dist: 40, soft: 0 } });

  // 9. Финал
  qa('#rings9 .ring').forEach((el, i) => L('S9', 'shape', 'Волна ' + (i + 1), el, { mode: 'S', shape: { type: 'ellipse', size: [192, 192], stroke: { color: [255, 255, 255, 1], w: 8 } } }));
  L('S9', 'img', 'Логотип maxway', '#logo', { mode: 'S' });
  qa('#fT .ch').forEach(el => el.classList.contains('badgeL')
    ? L('S9', 'png', 'KLABJON · значок L', el)
    : L('S9', 'text', 'KLABJON · ' + el.textContent, el));
  L('S9', 'png', 'Пилюля 1+1 (малая)', '#fPill', { mode: 'S' });
  L('S9', 'png', 'Тень', '#fSh', { mode: 'S' });
  L('S9', 'img', 'Сэндвич 1', '#fSa', { mode: 'S' });
  L('S9', 'img', 'Сэндвич 2 (подарок)', '#fSb', { mode: 'S' });
  L('S9', 'png', 'Бант', '#fBow', { mode: 'S' });
  L('S9', 'png', 'Кнопка', '#cta', { mode: 'S', cap: { hide: ['#cta span'] } });
  L('S9', 'png', 'Кнопка · нажатие', '#cta', { mode: 'S', special: 'ctaTap', cap: { hide: ['#cta span'], prep: el => { el.style.background = '#FFD502'; } } });
  L('S9', 'text', 'Заказать в приложении', '#cta span');
  L('S9', 'text', 'maxway.delever.uz', '#url', { mode: 'S' });
  L('S9', 'text', '*Акция действует только на доставку', '#note', { mode: 'S' });

  // Телефон (порядок по z-index интерфейса)
  L('PHONE', 'png', 'Корпус телефона', '#phone', { cap: { hide: ['.scr > *'], noShadow: 1 }, special: 'static', pad: 0 });
  L('PHONE', 'png', 'Шапка · адрес', '#home .hdr');
  L('PHONE', 'png', 'Баннер KLABJON 1+1', '#home .bnr');
  L('PHONE', 'png', 'Категории', '#home .chips', { cap: { hide: ['#chipA'] } });
  L('PHONE', 'png', 'Категория · Акция', '#chipA');
  L('PHONE', 'png', 'Заголовок · Акция', qa('#home .h2')[0]);
  L('PHONE', 'png', 'Карточка KLABJON L', '#card1', { cap: { hide: ['#addBtn'] } });
  L('PHONE', 'png', 'Кнопка Добавить · фон', '#addBtn', { cap: { hide: ['#addTxt', '#stepper'] } });
  L('PHONE', 'png', 'Кнопка Добавить · текст', '#addTxt');
  L('PHONE', 'png', 'Счётчик − 1 +', '#stepper');
  L('PHONE', 'png', 'Карточка Супер Бокс', qa('#home .card')[1]);
  L('PHONE', 'png', 'Заголовок · Новинка', qa('#home .h2')[1]);
  L('PHONE', 'png', 'Таббар', '.tabbar', { cap: { hide: ['#badge'] } });
  L('PHONE', 'png', 'Бейдж корзины', '#badge', { split: 'text' });
  L('PHONE', 'png', 'Статус-бар', '.stat');
  L('PHONE', 'solid', 'Затемнение', '#dim', { color: [15, 10, 30], alpha: .45 });
  L('PHONE', 'png', 'Корзина · шторка', '#sheet', { cap: { hide: ['.row', '.pay'] } });
  L('PHONE', 'png', 'Корзина · KLABJON L', '#r1');
  L('PHONE', 'png', 'Корзина · Крафт пакет', '#r2');
  L('PHONE', 'shape', 'Корзина · подсветка подарка', '#r3', { special: 'r3bg', shape: { type: 'rect', size: null, round: 0, fill: [255, 213, 2, 1] } });
  L('PHONE', 'png', 'Корзина · KLABJON L в подарок', '#r3', { cap: { hide: ['#gp'] } });
  L('PHONE', 'text', 'Цена подарка', '#gpv', { just: 'L', dyn: 'text+color' });
  L('PHONE', 'shape', 'Зачёркивание цены', '#gps', { shape: { type: 'rect', size: null, round: 0, fill: [224, 49, 43, 1] } });
  L('PHONE', 'png', 'Кнопка К оплате', '#payBtn');
  L('PHONE', 'img', 'Товар летит в корзину', '#fly');
  L('PHONE', 'solid', 'Заказ оформлен · фон', '#ok', { color: [30, 20, 60], special: 'okbg' });
  L('PHONE', 'png', 'Заказ оформлен · галочка', '#ok .okc');
  L('PHONE', 'png', 'Заказ оформлен · текст', '#ok b');
  L('PHONE', 'png', 'Палец · касание', '#touch i');
  L('PHONE', 'shape', 'Палец · волна', '#touch', { special: 'ripple', shape: { type: 'ellipse', size: [57, 57], stroke: { color: [118, 105, 175, 1], w: 3 } } });

  // Карта
  L('MAP', 'png', 'Карта · подложка', '#map', { cap: { hide: ['#route', '#routeBg', '.pin', '.bubble', '#mapRings'], noShadow: 1 }, special: 'static', pad: 0 });
  L('MAP', 'route', 'Маршрут · обводка', '#routeBg', { special: 'route', stroke: { color: [255, 255, 255, 1], w: 30 } });
  L('MAP', 'route', 'Маршрут', '#route', { special: 'route', stroke: { color: [118, 105, 175, 1], w: 16 } });
  L('MAP', 'png', 'Пин Maxway', '#pinStore');
  L('MAP', 'png', 'Пин дома', '#pinHome');
  L('MAP', 'png', 'Курьер', '#courier');
  L('MAP', 'png', 'Время доставки 40 мин', '#bubble');
  qa('#mapRings .ring').forEach((el, i) => L('MAP', 'shape', 'Волна пина ' + (i + 1), el, { mode: 'S', shape: { type: 'ellipse', size: [194, 194], stroke: { color: [239, 75, 67, 1], w: 6 } } }));

  // Ленты (внутри — фон и бегущий текст)
  for (const [c, sel, col] of [['TAPEA', '#tapeA', [118, 105, 175]], ['TAPEB', '#tapeB', [255, 213, 2]], ['TAPEN', '#tapeB', [255, 213, 2]]]) {
    L(c, 'solid', 'Фон ленты', sel, { color: col, special: 'static' });
    L(c, 'png', 'Текст ленты', q(sel + ' .tt'), { part: 'tape', state: c });
  }

  /* ---------- раскладка в покое (без трансформов): для цепочек 'G' ---------- */
  const REST = new Map();
  function measureRest() {
    document.documentElement.classList.add('__rest');
    for (const s of SPECS) {
      if (!s.el) continue;
      const root = q(COMPS[s.comp].root);
      for (let n = s.el; n; n = n.parentElement) {
        if (!REST.has(n)) { const r = n.getBoundingClientRect(); REST.set(n, { x: r.left, y: r.top, w: r.width, h: r.height }); }
        if (n === root) break;
      }
    }
    document.documentElement.classList.remove('__rest');
  }

  /* ---------- трансформ элемента относительно корня композиции ---------- */
  function chainSample(el, root, left) {
    const chain = [];
    for (let n = el; n && n !== root; n = n.parentElement) chain.push(n);
    let M = new DOMMatrix(), op = 1, blur = 0;
    for (let i = chain.length - 1; i >= 0; i--) {
      const n = chain[i], p = n.parentElement, rn = REST.get(n), rp = REST.get(p);
      const cs = getComputedStyle(n);
      let T = new DOMMatrix().translate(rn.x - rp.x, rn.y - rp.y);
      if (cs.transform && cs.transform !== 'none') {
        const [ox, oy] = cs.transformOrigin.split(' ').map(parseFloat);
        T = T.translate(ox, oy).multiply(new DOMMatrix(cs.transform)).translate(-ox, -oy);
      }
      M = M.multiply(T);
      op *= parseFloat(cs.opacity);
      const m = /blur\(([\d.]+)px\)/.exec(cs.filter); if (m) blur = Math.max(blur, +m[1]);
    }
    const r = REST.get(el);
    const cx0 = left ? 0 : r.w / 2;
    const c = M.transformPoint(new DOMPoint(cx0, r.h / 2));
    const px = M.transformPoint(new DOMPoint(cx0 + 1, r.h / 2)), py = M.transformPoint(new DOMPoint(cx0, r.h / 2 + 1));
    const vx = [px.x - c.x, px.y - c.y], vy = [py.x - c.x, py.y - c.y];
    const det = vx[0] * vy[1] - vx[1] * vy[0];
    if (getComputedStyle(el).visibility === 'hidden' || el.getClientRects().length === 0) op = 0;
    return { x: c.x, y: c.y, sx: Math.hypot(vx[0], vx[1]), sy: Math.hypot(vy[0], vy[1]) * (det < 0 ? -1 : 1),
      r: Math.atan2(vx[1], vx[0]) * 180 / Math.PI, o: op, b: blur };
  }

  /* ---------- запись параметров S() ---------- */
  const LAST = new Map();
  window.__rec = (el, o) => {
    if (o.o === 0 && Object.keys(o).length === 1) { const p = LAST.get(el); LAST.set(el, Object.assign({}, p || {}, { o: 0 })); return; }
    LAST.set(el, { x: o.x || 0, y: o.y || 0, sx: o.sx != null ? o.sx : o.s != null ? o.s : 1, sy: o.sy != null ? o.sy : o.s != null ? o.s : 1,
      r: o.r || 0, o: o.o == null ? 1 : Math.max(0, Math.min(1, o.o)), b: o.b > .05 ? o.b : 0, rx: o.rx || 0, ry: o.ry || 0 });
  };
  function sSample(el) {
    const v = LAST.get(el);
    if (!v || el.getClientRects().length === 0) return { x: 0, y: 0, sx: 1, sy: 1, r: 0, o: 0, b: 0, rx: 0, ry: 0 };
    const out = Object.assign({}, v);
    if (out.sx === 0 && out.sy === 0) out.o = 0;
    return out;
  }

  /* ---------- текст: шрифт, цвет, диапазоны цвета, базовая линия ---------- */
  function textInfo(el, just) {
    document.documentElement.classList.add('__rest');
    const cs = getComputedStyle(el);
    const fam = cs.fontFamily.split(',')[0].replace(/['"]/g, '').trim();
    const w = +cs.fontWeight;
    const base = rgb(cs.color);
    let str = '';
    const ranges = [];
    (function walk(n) {
      for (const c of n.childNodes) {
        if (c.nodeType === 3) {
          const t = c.nodeValue.replace(/\s+/g, ' ');
          const col = rgb(getComputedStyle(c.parentElement).color);
          if (t && col.join() !== base.join()) ranges.push([str.length, str.length + t.length, col]);
          str += t;
        } else if (c.nodeName === 'BR') str += '\r';
        else if (c.nodeType === 1 && getComputedStyle(c).display !== 'none') walk(c);
      }
    })(el);
    const lead = str.length - str.replace(/^ +/, '').length;
    str = str.replace(/^ +| +$/g, '');
    ranges.forEach(r => { r[0] -= lead; r[1] -= lead; });
    const pr = document.createElement('span');
    pr.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
    el.insertBefore(pr, el.firstChild);
    const er = el.getBoundingClientRect(), bt = pr.getBoundingClientRect().top - er.top;
    pr.remove();
    const fs = parseFloat(cs.fontSize), ls = cs.letterSpacing === 'normal' ? 0 : parseFloat(cs.letterSpacing);
    const lh = cs.lineHeight === 'normal' ? null : parseFloat(cs.lineHeight);
    let shadow = null;
    const sm = /rgba?\(([^)]+)\)\s+([-\d.]+)px\s+([-\d.]+)px\s+([-\d.]+)px/.exec(cs.textShadow);
    if (sm) { const c = sm[1].split(',').map(parseFloat); shadow = { color: c.slice(0, 3), alpha: c[3] == null ? 1 : c[3], dist: Math.hypot(+sm[2], +sm[3]), soft: +sm[4] }; }
    document.documentElement.classList.remove('__rest');
    const ax = just === 'L' ? er.width / 2 : just === 'R' ? -er.width / 2 : 0;
    return { str, font: (PS[fam] || {})[w] || fam, size: fs, tracking: Math.round(ls / fs * 1000), leading: str.indexOf('\r') >= 0 ? lh : null,
      color: base, ranges, shadow, just: just || 'C', anchor: [ax, er.height / 2 - bt] };
  }

  /* ---------- особые каналы (кадр за кадром) ---------- */
  function special(s, t) {
    const el = s.el;
    switch (s.special) {
      case 'bg': return { color: getComputedStyle(q('#bg')).backgroundColor };
      case 'dots': {
        const m = /translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(el.style.transform) || [0, 0, 0];
        const purple = /#7669AF|118,\s*105,\s*175/i.test(el.style.backgroundImage);
        const on = (s.variant === 'purple') === purple;
        return { x: 540 + +m[1], y: 960 + +m[2], sx: 1, sy: 1, r: 0, o: on ? +el.style.opacity : 0, b: 0 };
      }
      case 'flash': return { x: 540, y: 960, o: +el.style.opacity || 0 };
      case 'line': return { p: [+el.getAttribute('x1'), +el.getAttribute('y1'), +el.getAttribute('x2'), +el.getAttribute('y2')], o: +(el.style.opacity || 0) };
      case 'dot': { const r = +el.getAttribute('r'); return { x: +el.getAttribute('cx'), y: +el.getAttribute('cy'), d: 2 * r, o: r > .05 ? 1 : 0 }; }
      case 'strike': return Object.assign(sSample(el), { w: parseFloat(el.style.width) || 0 });
      case 'route': {
        const L0 = el.getTotalLength(), off = parseFloat(el.style.strokeDashoffset) || 0;
        return { trim: 100 * (1 - off / L0) };
      }
      case 'ripple': {
        const g = chainSample(el, q(COMPS[s.comp].root));
        const rs = parseFloat(el.style.getPropertyValue('--rs')) || 1, ro = parseFloat(el.style.getPropertyValue('--ro')) || 0;
        return Object.assign(g, { sx: g.sx * rs, sy: g.sy * rs, o: g.o * ro });
      }
      case 'r3bg': { const g = chainSample(el, q(COMPS[s.comp].root)); return Object.assign(g, { o: g.o * rgb(el.style.background || 'rgba(0,0,0,0)')[3] }); }
      case 'okbg': { const g = chainSample(el, q(COMPS[s.comp].root)); return Object.assign(g, { o: g.o * rgb(el.style.background || 'rgba(0,0,0,0)')[3] }); }
      case 'ctaTap': { const v = sSample(el); return Object.assign(v, { o: /255, 213, 2|#FFD502/i.test(el.style.background) ? v.o : 0 }); }
    }
    return null;
  }

  function sample(s, t) {
    let v;
    if (s.special && s.special !== 'static') v = special(s, t);
    else if (s.mode === 'S') v = sSample(s.el);
    else v = chainSample(s.el, q(COMPS[s.comp].root), !!s.part);
    if (s.special === 'static') v.o = 1;
    if (s.kind === 'solid' && s.alpha != null) v.o *= s.alpha;
    if (s.split === 'text' || s.dyn) v.text = s.el.textContent;
    if (s.kind === 'text' && (s.split || s.dyn)) v.color = rgb(getComputedStyle(s.el).color);
    if (s.split === 'bg') v.key = getComputedStyle(s.el).backgroundColor;
    return v;
  }

  /* ---------- снимки PNG ---------- */
  const CAPCSS = `
    html.__rest *, html.__rest *::before, html.__rest *::after { transform: none !important; }
    html.__rest .sc, html.__rest #phL { display: block !important; }
    html.__cap *, html.__cap *::before, html.__cap *::after { visibility: hidden !important; opacity: 1 !important; box-shadow: none; }
    html.__cap *:not(.__c *) { transform: none !important; }
    html.__cap *:not(.__c):not(.__c *)::before, html.__cap *:not(.__c):not(.__c *)::after { transform: none !important; }
    html.__cap *:not(.__keepf) { filter: none !important; }
    html.__cap .__c, html.__cap .__c *, html.__cap .__c::before, html.__cap .__c::after, html.__cap .__c *::before, html.__cap .__c *::after { visibility: visible !important; }
    html.__cap .__h, html.__cap .__h * { visibility: hidden !important; }
    html.__cap, html.__cap body { overflow: visible !important; background: transparent !important; width: auto !important; height: auto !important; }
    html.__cap #root { overflow: visible !important; background: transparent !important; margin: 300px; }
    html.__cap .sc, html.__cap #phL { display: block !important; }
    html.__cap .tape { overflow: visible !important; }
    html.__cap .__c.__shadow { box-shadow: var(--__bs) !important; }`;
  const st = document.createElement('style'); st.textContent = CAPCSS; document.head.appendChild(st);

  let capUndo = [];
  function capBegin(id, variant) {
    const s = SPECS.find(x => x.id === id);
    const el = s.el;
    capUndo = [];
    const save = (e, k) => capUndo.push([e, k, e.style[k]]);
    if (s.cap.prep) { save(el, 'backgroundImage'); save(el, 'background'); s.cap.prep(el); }
    if (variant != null) {
      if (s.split === 'text') { save(el, 'textContent'); el.textContent = variant.text; }
      if (s.keepf && variant.filter) { save(el, 'filter'); el.style.filter = variant.filter; }
    }
    if (s.part === 'tape') {
      const tt = el; capUndo.push([tt, '__html', tt.innerHTML]);
      tt.innerHTML = Array(14).fill('<span>' + (s.state === 'TAPEA' ? 'АКЦИЯ ✦ 1+1 ✦ KLABJON ✦' : s.state === 'TAPEB' ? 'KLABJON L ✦ ВТОРОЙ В ПОДАРОК ✦' : '*Акция действует только на доставку ✦') + '</span>').join('');
    }
    // тень элемента (кроме телефона/карты — там тень делается эффектом AE)
    const bs = getComputedStyle(el).boxShadow;
    if (bs && bs !== 'none' && !s.cap.noShadow) { el.style.setProperty('--__bs', bs); el.classList.add('__shadow'); }
    el.classList.add('__c');
    if (s.keepf) el.classList.add('__keepf');
    (s.cap.hide || []).forEach(h => qa(h).forEach(e => { if (el.contains(e) || e === el) e.classList.add('__h'); }));
    document.documentElement.classList.add('__cap');
    const r = el.getBoundingClientRect();
    let u = { l: r.left, t: r.top, r: r.right, b: r.bottom };
    if (!s.part) for (const d of el.querySelectorAll('*')) {
      if (getComputedStyle(d).visibility !== 'visible') continue;
      const b = d.getBoundingClientRect(); if (!b.width || !b.height) continue;
      u = { l: Math.min(u.l, b.left), t: Math.min(u.t, b.top), r: Math.max(u.r, b.right), b: Math.max(u.b, b.bottom) };
    }
    let pad = s.pad != null ? s.pad : 40;
    let clip = { x: u.l - pad, y: u.t - pad, w: u.r - u.l + 2 * pad, h: u.b - u.t + 2 * pad };
    if (s.part === 'mq' || s.part === 'tape') {
      const unit = s.part === 'mq' ? el.scrollWidth / 8 : el.firstChild.offsetWidth;
      clip.w = Math.min(clip.w, 2 * unit + (s.part === 'mq' ? 1080 : 2600) + 2 * pad + 40);
    }
    clip = { x: Math.floor(clip.x), y: Math.floor(clip.y), w: Math.ceil(clip.w), h: Math.ceil(clip.h) };
    const center = { x: s.part ? r.left : r.left + r.width / 2, y: r.top + r.height / 2 };
    return { clip, anchor: [center.x - clip.x, center.y - clip.y], size: [r.width, r.height] };
  }
  function capEnd() {
    document.documentElement.classList.remove('__cap');
    qa('.__c,.__h,.__keepf,.__shadow').forEach(e => e.classList.remove('__c', '__h', '__shadow'));
    qa('.__keepf').forEach(e => { if (!e.classList.contains('mrow') && !e.classList.contains('outline')) e.classList.remove('__keepf'); });
    for (const [e, k, v] of capUndo.reverse()) { if (k === '__html') e.innerHTML = v; else if (k === 'textContent') e.textContent = v; else e.style[k] = v; }
  }

  /* ---------- API для export.mjs ---------- */
  window.__ae = {
    COMPS,
    specs: () => SPECS.map(s => {
      const o = Object.assign({}, s); delete o.el; delete o.cap;
      o.hasEl = !!s.el; o.capHide = s.cap.hide || null;
      if (s.kind === 'img') { o.src = s.el.getAttribute('src'); o.nat = [s.el.naturalWidth, s.el.naturalHeight]; }
      return o;
    }),
    prep() {
      measureRest();
      const out = {};
      for (const s of SPECS) {
        if (s.kind === 'text') out[s.id] = textInfo(s.el, s.just);
        if (s.el && REST.get(s.el)) out[s.id] = Object.assign(out[s.id] || {}, { rest: REST.get(s.el) });
        if (s.kind === 'route') out[s.id] = { d: s.el.getAttribute('d') };
        if (s.shape && s.shape.size === null) { const r = REST.get(s.el); s.shape.size = [r.w, r.h]; out[s.id] = Object.assign(out[s.id] || {}, { size: [r.w, r.h] }); }
      }
      return out;
    },
    // записывает кадр: для каждого слоя, чьё окно содержит t
    frame(t, f) {
      window.renderAt(t, f);
      const res = {};
      for (const s of SPECS) {
        const c = COMPS[s.comp], win = s.win || (s.src && COMPS[s.src] ? [COMPS[s.src].start, COMPS[s.src].start + COMPS[s.src].dur] : [c.start, c.start + c.dur]);
        if (t < win[0] - 1e-6 || t >= win[1] - 1e-6) continue;
        if (s.virtual && s.special !== 'bg') continue;
        res[s.id] = sample(s, t);
      }
      res.cam = Object.assign({}, window.__cam);
      return res;
    },
    capBegin, capEnd,
  };
})();
