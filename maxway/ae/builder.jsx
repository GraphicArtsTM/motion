// MAXWAY — KLABJON 1+1 · сборка проекта After Effects (1080×1920, 60 fps, 30 с)
//
// Как запустить:
//   1. Установите шрифты из папки fonts (Unbounded и Rubik) и перезапустите After Effects.
//   2. After Effects 2025 → File → New → New Project.
//   3. File → Scripts → Run Script File… → выберите этот файл (папку не переносите отдельно от footage/ и audio/).
// Скрипт создаст папку «MAXWAY KLABJON 1+1» с главной композицией, прекомпами сцен, телефоном, картой и лентами.
//
// Файл создан ae/export.mjs из HTML-версии ролика: движение каждого элемента записано по кадрам
// и прорежено до опорных ключей, поэтому анимация совпадает с роликом кадр в кадр.
(function () {
    var DATA = /*__DATA__*/null;
    if (!DATA) { alert('В скрипте нет данных проекта.'); return; }

    var BASE = new File($.fileName).parent;
    var warns = [];
    function warn(m) { if (warns.length < 40) warns.push(m); }

    /* ---------- утилиты ---------- */
    function isTrack(v) { return v !== null && typeof v === 'object' && !(v instanceof Array) && v.t !== undefined; }
    function setTrack(prop, v, map) {
        if (v === undefined || v === null) return;
        if (isTrack(v)) {
            var vals = [];
            for (var i = 0; i < v.v.length; i++) vals.push(map ? map(v.v[i]) : v.v[i]);
            prop.setValuesAtTimes(v.t, vals);
        } else {
            prop.setValue(map ? map(v) : v);
        }
    }
    function c4(c) { return [c[0], c[1], c[2], 1]; }

    /* ---------- проверка шрифтов ---------- */
    function checkFonts() {
        var need = {}, miss = [], i, f;
        for (i = 0; i < DATA.layers.length; i++) if (DATA.layers[i].text) need[DATA.layers[i].text.font] = 1;
        try {
            if (app.fonts && app.fonts.getFontsByPostScriptName) {
                for (f in need) {
                    var r = app.fonts.getFontsByPostScriptName(f);
                    if (!r || r.length === 0) miss.push(f);
                }
            }
        } catch (e) { return true; }
        if (miss.length) {
            return confirm('Не установлены шрифты:\n  ' + miss.join('\n  ') +
                '\n\nУстановите их из папки fonts рядом со скриптом и перезапустите After Effects.' +
                '\nПродолжить сейчас? (текст будет другим шрифтом)');
        }
        return true;
    }
    if (!checkFonts()) return;

    /* ---------- прогресс ---------- */
    var win = null, bar = null, lbl = null;
    try {
        win = new Window('palette', 'Maxway KLABJON → After Effects');
        lbl = win.add('statictext', undefined, 'Сборка проекта…'); lbl.preferredSize = [360, 20];
        bar = win.add('progressbar', undefined, 0, DATA.layers.length); bar.preferredSize = [360, 12];
        win.show();
    } catch (e) { win = null; }
    function progress(i, name) {
        if (!win) return;
        bar.value = i; lbl.text = name; win.update();
    }

    app.beginUndoGroup('Maxway KLABJON 1+1');

    /* ---------- папки, футаж, композиции ---------- */
    var P = app.project;
    var fRoot = P.items.addFolder('MAXWAY KLABJON 1+1');
    var fPre = P.items.addFolder('Прекомпы'); fPre.parentFolder = fRoot;
    var fFoot = P.items.addFolder('Футаж'); fFoot.parentFolder = fRoot;
    var fFonts = null;

    var FOOT = {};
    function footage(rel) {
        if (FOOT[rel]) return FOOT[rel];
        var f = new File(BASE.absoluteURI + '/' + rel);
        if (!f.exists) throw new Error('не найден файл ' + rel);
        var it = P.importFile(new ImportOptions(f));
        it.parentFolder = fFoot;
        FOOT[rel] = it;
        return it;
    }

    var C = {}, i;
    for (i = 0; i < DATA.comps.length; i++) {
        var d = DATA.comps[i];
        var comp = P.items.addComp(d.name, d.w, d.h, 1, d.dur, DATA.fps);
        comp.bgColor = d.bg;
        comp.parentFolder = d.id === 'MAIN' ? fRoot : fPre;
        C[d.id] = comp;
    }
    var main = C.MAIN;

    // нуль камеры: тряска и удары в такт (все сцены и телефон привязаны к нему)
    var cam = main.layers.addNull(main.duration);
    cam.name = 'CAM · удары и тряска';
    cam.label = 9;
    cam.property('ADBE Transform Group').property('ADBE Anchor Point').setValue([0, 0]);
    cam.property('ADBE Transform Group').property('ADBE Position').setValue([540, 960]);

    /* ---------- текст ---------- */
    var JUST = { L: ParagraphJustification.LEFT_JUSTIFY, C: ParagraphJustification.CENTER_JUSTIFY, R: ParagraphJustification.RIGHT_JUSTIFY };
    function styleDoc(td, T, str, color) {
        td.text = str;
        try { td.font = T.font; } catch (e) { warn('Шрифт ' + T.font + ': ' + e.toString()); }
        td.fontSize = T.size;
        td.applyFill = true;
        td.fillColor = color;
        td.applyStroke = false;
        td.tracking = T.tracking;
        td.justification = JUST[T.just];
        if (T.leading) { try { td.autoLeading = false; td.leading = T.leading; } catch (e2) { } }
        return td;
    }
    function colorRange(lyr, R) {
        try {
            var grp = function () { return lyr.property('ADBE Text Properties').property('ADBE Text Animators'); };
            var an = grp().addProperty('ADBE Text Animator');
            var idx = an.propertyIndex;
            grp().property(idx).name = 'Цвет ' + R[0] + '–' + R[1];
            grp().property(idx).property('ADBE Text Animator Properties').addProperty('ADBE Text Fill Color');
            grp().property(idx).property('ADBE Text Animator Properties').property('ADBE Text Fill Color').setValue(c4(R[2]));
            var sels = grp().property(idx).property('ADBE Text Selectors');
            if (sels.numProperties === 0) sels.addProperty('ADBE Text Selector');
            var sel = grp().property(idx).property('ADBE Text Selectors').property(1);
            sel.property('ADBE Text Range Advanced').property('ADBE Text Range Units').setValue(2);
            sel = grp().property(idx).property('ADBE Text Selectors').property(1);
            sel.property('ADBE Text Index Start').setValue(R[0]);
            sel.property('ADBE Text Index End').setValue(R[1]);
        } catch (e) { warn('Цвет части текста «' + lyr.name + '»: ' + e.toString()); }
    }
    function makeText(comp, L) {
        var T = L.text;
        var lyr = comp.layers.addText(T.str);
        var sp = lyr.property('ADBE Text Properties').property('ADBE Text Document');
        sp.setValue(styleDoc(sp.value, T, T.str, T.color));
        if (T.dyn) {
            for (var k = 0; k < T.dyn.length; k++) {
                var dk = T.dyn[k];
                sp.setValueAtTime(dk[0], styleDoc(sp.value, T, dk[1], dk[2]));
            }
        }
        for (var r = 0; r < T.ranges.length; r++) colorRange(lyr, T.ranges[r]);
        return lyr;
    }

    /* ---------- фигуры ---------- */
    function mkShape(flat, closed) {
        var s = new Shape(), v = [];
        for (var k = 0; k + 1 < flat.length; k += 2) v.push([flat[k], flat[k + 1]]);
        s.vertices = v;
        s.closed = !!closed;
        return s;
    }
    function makeShape(comp, L) {
        var S = L.shape;
        var lyr = comp.layers.addShape();
        var g = lyr.property('ADBE Root Vectors Group').addProperty('ADBE Vector Group');
        g.name = L.n;
        var gi = g.propertyIndex;
        var G = function () { return lyr.property('ADBE Root Vectors Group').property(gi).property('ADBE Vectors Group'); };
        var last = function () { return G().property(G().numProperties); };
        if (S.type === 'rect') {
            G().addProperty('ADBE Vector Shape - Rect');
            setTrack(last().property('ADBE Vector Rect Size'), S.size);
            last().property('ADBE Vector Rect Roundness').setValue(S.round || 0);
        } else if (S.type === 'ellipse') {
            G().addProperty('ADBE Vector Shape - Ellipse');
            setTrack(last().property('ADBE Vector Ellipse Size'), S.size);
        } else if (S.type === 'path') {
            G().addProperty('ADBE Vector Shape - Group');
            var pp = last().property('ADBE Vector Shape');
            if (isTrack(S.path)) {
                var shapes = [];
                for (var k = 0; k < S.path.v.length; k++) shapes.push(mkShape(S.path.v[k], S.closed));
                pp.setValuesAtTimes(S.path.t, shapes);
            } else pp.setValue(mkShape(S.path, S.closed));
        }
        if (S.trim !== undefined) {
            G().addProperty('ADBE Vector Filter - Trim');
            setTrack(last().property('ADBE Vector Trim End'), S.trim);
        }
        if (S.stroke) {
            G().addProperty('ADBE Vector Graphic - Stroke');
            last().property('ADBE Vector Stroke Color').setValue(c4(S.stroke.color));
            last().property('ADBE Vector Stroke Width').setValue(S.stroke.w);
            if (S.stroke.cap) last().property('ADBE Vector Stroke Line Cap').setValue(S.stroke.cap);
            if (S.stroke.join) last().property('ADBE Vector Stroke Line Join').setValue(S.stroke.join);
        }
        if (S.fill) {
            G().addProperty('ADBE Vector Graphic - Fill');
            last().property('ADBE Vector Fill Color').setValue(c4(S.fill));
        }
        return lyr;
    }

    /* ---------- эффекты ---------- */
    function addFx(lyr, match) { return lyr.property('ADBE Effect Parade').addProperty(match); }
    function blur(lyr, v) {
        var fx = addFx(lyr, 'ADBE Gaussian Blur 2');
        fx.name = 'Размытие движения';
        setTrack(fx.property(1), v);
    }
    function shadow(lyr, sh) {
        var fx = addFx(lyr, 'ADBE Drop Shadow');
        fx.property(1).setValue(c4(sh.color));
        try { fx.property(2).setValue(sh.alpha * 255); } catch (e) { fx.property(2).setValue(sh.alpha * 100); }
        fx.property(3).setValue(sh.dir);
        fx.property(4).setValue(sh.dist);
        fx.property(5).setValue(sh.soft);
    }
    function grain(lyr) {
        var fx = addFx(lyr, 'ADBE Noise');
        fx.property(1).setValue(6);
        try { fx.property(2).setValue(0); } catch (e) { }
    }

    /* ---------- трансформ ---------- */
    function transform(lyr, L) {
        var T = lyr.property('ADBE Transform Group'), tr = L.tr, d3 = !!L.d3;
        if (L.an) T.property('ADBE Anchor Point').setValue(d3 ? [L.an[0], L.an[1], 0] : L.an);
        T.property('ADBE Position').dimensionsSeparated = true;
        setTrack(T.property('ADBE Position_0'), tr.x);
        setTrack(T.property('ADBE Position_1'), tr.y);
        if (d3) T.property('ADBE Position_2').setValue(0);
        setTrack(T.property('ADBE Scale'), tr.s, d3 ? function (v) { return [v[0], v[1], 100]; } : null);
        setTrack(T.property('ADBE Rotate Z'), tr.r);
        setTrack(T.property('ADBE Opacity'), tr.o);
        if (d3) {
            setTrack(T.property('ADBE Rotate X'), tr.rx);
            setTrack(T.property('ADBE Rotate Y'), tr.ry);
        }
    }

    /* ---------- слой ---------- */
    function build(L) {
        var comp = C[L.c], lyr;
        if (L.k === 'png' || L.k === 'img') lyr = comp.layers.add(footage(L.src));
        else if (L.k === 'comp') lyr = comp.layers.add(C[L.src]);
        else if (L.k === 'text') lyr = makeText(comp, L);
        else if (L.k === 'solid') lyr = comp.layers.addSolid(L.solid.color, L.n, L.solid.w, L.solid.h, 1, comp.duration);
        else if (L.k === 'adj') { lyr = comp.layers.addSolid([0.5, 0.5, 0.5], L.n, comp.width, comp.height, 1, comp.duration); lyr.adjustmentLayer = true; }
        else if (L.k === 'shape') lyr = makeShape(comp, L);
        else throw new Error('неизвестный тип ' + L.k);
        lyr.name = L.n;
        if (L.lbl) lyr.label = L.lbl;
        if (L.d3) lyr.threeDLayer = true;
        if (L.st !== undefined) lyr.startTime = L.st;
        lyr.outPoint = L.out;
        lyr.inPoint = L['in'];
        if (L.cam) lyr.parent = cam;
        transform(lyr, L);
        if (L.sh) shadow(lyr, L.sh);
        if (L.tr.b !== undefined) blur(lyr, L.tr.b);
        if (L.k === 'adj') grain(lyr);
        return lyr;
    }

    for (i = 0; i < DATA.layers.length; i++) {
        var L = DATA.layers[i];
        if (i % 10 === 0) progress(i, L.n);
        try { build(L); } catch (e) { warn(L.n + ': ' + e.toString() + (e.line ? ' (строка ' + e.line + ')' : '')); }
    }

    /* ---------- камера-нуль, 3D-камера, музыка ---------- */
    try {
        var CT = cam.property('ADBE Transform Group');
        CT.property('ADBE Position').dimensionsSeparated = true;
        setTrack(CT.property('ADBE Position_0'), DATA.cam.x);
        setTrack(CT.property('ADBE Position_1'), DATA.cam.y);
        setTrack(CT.property('ADBE Scale'), DATA.cam.s);
        setTrack(CT.property('ADBE Rotate Z'), DATA.cam.r);
        cam.moveToBeginning();
    } catch (e) { warn('CAM: ' + e.toString()); }
    try {
        var cm = main.layers.addCamera('Камера · перспектива телефона', DATA.camera.poi);
        cm.property('ADBE Transform Group').property('ADBE Position').setValue([DATA.camera.poi[0], DATA.camera.poi[1], DATA.camera.z]);
        cm.property('ADBE Camera Options Group').property('ADBE Camera Zoom').setValue(DATA.camera.zoom);
        cm.moveToBeginning();
    } catch (e) { warn('Камера: ' + e.toString()); }
    try {
        var au = main.layers.add(footage(DATA.audio));
        au.name = 'Музыка · 120 BPM';
        au.label = 3;
        au.moveToEnd();
    } catch (e) { warn('Музыка: ' + e.toString()); }

    main.workAreaStart = 0;
    main.workAreaDuration = main.duration;
    app.endUndoGroup();
    if (win) win.close();
    main.openInViewer();

    var msg = 'Готово: ' + DATA.layers.length + ' слоёв, ' + DATA.comps.length + ' композиций.\n' +
        'Главная композиция: «' + main.name + '».\nСохраните проект: File → Save As.';
    if (warns.length) msg += '\n\nЗамечания:\n' + warns.join('\n');
    alert(msg);
})();
