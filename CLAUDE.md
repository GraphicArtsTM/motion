# CLAUDE.md — студия «Паук Новограда» (GraphicArts Animation)

Этот файл — полная инструкция для новой сессии ИИ (и для человека). Если вам прислали этот проект архивом или
открыли репозиторий — прочитайте его целиком, потом `SERIES_BIBLE.md` (мир и персонажи) и `STORY.md` нужной серии.

**Что это:** анимационный сериал, который целиком рисуется кодом на Three.js: город, персонажи, интерьеры,
эффекты, комикс-надписи. Каждый кадр — детерминированная функция времени `renderAt(T)`; Playwright (headless
Chromium) снимает кадры, ffmpeg собирает видео. Музыка, шумы и обработка голосов синтезируются на Python.
Автор (пользователь) говорит по-русски и сам озвучивает персонажей; отвечать ему — по-русски, просто и по делу.

---

## 1. Структура

```
CLAUDE.md                 ← вы здесь
SERIES_BIBLE.md           ← библия: мир, правила сил, персонажи, кто такая Тень, план сезона, стиль
README.md                 ← для автора: как отрендерить серию одним кликом
index.html                ← страница рендера/просмотра (importmap: three, three/addons/, engine/)
render.mjs                ← кадры/стоп-кадры в headless Chromium  (node render.mjs --ep e02 --story --stills 10,20)
make-video.mjs            ← готовое видео серии со звуком (параллельно, на видеокарте)  (node make-video.mjs --ep e02)
preview.mjs               ← плеер в браузере со звуком (node preview.mjs e02)
RENDER_WINDOWS.bat / render_mac_linux.sh   ← «один клик»: ставит Node, Playwright, ffmpeg, спрашивает номер серии
package.json              ← playwright 1.56.1, ffmpeg-static 5.2.0
requirements.txt          ← Python для пересборки звука (numpy, numba, piper-tts) + RHVoice
engine/
  src/main.js             ← рантайм: мир, постобработка, таймлайн, renderAt(T); грузит episodes/<ep>/episode.js
  src/director.js         ← РЕЖИССЁРСКИЙ НАБОР для шотов новых серий (камера, лица, эффекты, дроны, позы драки)
  src/core.js             ← утилиты: kf (ключи), E (изинги), P, lerp, clamp, pulse, shake, noise, toon/glow/mesh, rimify
  src/rig.js              ← персонажи: makeCharacter(kind), POSE (библиотека поз), seq/blend, ikArm, squash, springAt, makeSpider
  src/city.js             ← Новоград: небоскрёбы (шейдер окон), фасады, проспект, мост, башня «Аркада», дождь, молнии, машины, автобус, велосипед
  src/interiors.js        ← лаборатория, кухня деда (K.setDay — утро/ночь), логово Тени, кабина автобуса, осколки
  src/school.js           ← лицей «Новоград»: коридор со шкафчиками, класс физики, столовая (makeSchool)
  src/zaton.js            ← двор Старого Затона (пятиэтажка, подъезды, площадка, остановка «42») + фасад лицея; setTime
  src/props.js, crowd.js  ← прохожие, светофоры, реклама, полиция; толпа и полицейские на мосту
  src/dressing.js         ← «обвес» сцен: голограмма/пар/маячки лаборатории, обломки/дым/вертолёт моста, кот/часы/ТВ на кухне
  src/fx.js               ← паутина (webs), искры, кольца, вихрь нанонити, брызги
  src/overlay.js          ← 2D-слой: субтитры, комикс-надписи, плашки, титры, логотип, заставка студии, рамки, уведомление, радар
  src/post.js             ← цветокоррекция (GRADES), зерно/виньетка, накопитель motion blur
  audio/mix.py            ← звуковой движок: инструменты, сведение, липсинк; выполняет партитуру серии audio/cues.py
  audio/voices.py         ← голоса: запись автора (voice_user) или синтез RHVoice/Piper
  audio/align_voice.py    ← нарезка ОДНОЙ длинной записи всех реплик на реплики (VAD + MFCC/DTW + DP)
  vendor/                 ← three.js r169 (+ jsm); fonts/ — Unbounded, Rubik
episodes/
  index.json              ← список серий {id, title, file}, default
  _template/              ← заготовка новой серии (рабочий пример на 48 с)
  e01/  «Укус молнии»     ← готовая серия (shots.js написан до director.js — держит свои копии помощников)
  e02/  «Личная жизнь»    ← готовая серия на director.js (лицей, Маржон, Диёр, Азим, тизер ODILMAN), ИИ-голоса
    episode.js            ← title, buildShots, world(t), gradeAt(t), mblur
    shots.js              ← все шоты серии
    dialogue.json         ← реплики: {id, who, t, text, hint?, fx?, say?}
    timeline.json         ← intro (заставка студии, с), duration, story_duration, stretch, strikes (молнии)
    audio/cues.py         ← партитура: музыка по сценам, шумы, эффекты (сюжетное время)
    audio/voice_src/      ← длинная запись озвучки автора (+ <запись>.map.json — ручная раскладка)
    audio/voice_user/     ← реплики по одной (n1.wav, t5.m4a…) — генерируются нарезчиком или кладутся вручную
    assets/               ← soundtrack.m4a + lipsync.json (результат tools/audio.sh)
    STORY.md, VOICEOVER.md
tools/
  new-episode.mjs         ← node tools/new-episode.mjs 3 "Линия 0"  → episodes/e03 из шаблона
  audio.sh                ← tools/audio.sh e02: нарезка записи → голоса → сведение → soundtrack.m4a + lipsync.json
  voiceover.py            ← python3 tools/voiceover.py e02 → VOICEOVER.md (лист озвучки для автора)
  pack.py                 ← python3 tools/pack.py → out/PAUK_NOVOGRADA_STUDIO.zip (весь проект одним архивом)
```

`video/` в корне репозитория — отдельный старый проект (промо-ролик), к сериалу не относится.

---

## 2. Быстрый старт (проверено в облачной сессии Claude Code)

```bash
npm install                                   # playwright + ffmpeg-static
npx playwright install chromium               # если браузер не найден (в облаке уже есть: /opt/pw-browsers)
node render.mjs --ep e02 --story --stills 52,111,162     # стоп-кадры → out/stills/t*.png (смотреть через Read)
node make-video.mjs --ep e02 --fast --from 100 --to 104 --jobs 1   # кусочек видео со звуком
tools/audio.sh e02                            # пересобрать звук серии (нужны python3+numpy, ffmpeg, RHVoice; piper для Веры)
```

- В облаке рендер идёт через SwiftShader (без видеокарты): ~1–4 с на кадр в быстром режиме. Полную серию
  рендерит **автор у себя** (`RENDER_WINDOWS.bat` / `render_mac_linux.sh`) — на видеокарте, в высоком качестве.
- **Проверяйте работу стоп-кадрами**: рендерьте 6–30 кадров, склеивайте в контакт-лист ffmpeg-ом
  (`-filter_complex xstack` или `-vf tile=4x4`) и смотрите картинку. Так найдены почти все баги.
- `--story` — время по сюжету (как в shots.js); без него — время ролика (с заставкой и растяжками).
- `--q "&q=high"` — высокое качество (MSAA, тени, DOF, motion blur) — медленно на CPU, используйте точечно.

---

## 3. Время: сюжетное и экранное

- Шоты, реплики (`dialogue.json`), партитура (`cues.py`) и `gradeAt/world/mblur` — в **сюжетном** времени `t`.
- Живая озвучка длиннее/короче синтеза → в `timeline.json` есть `stretch: [[s0, s1, +секунды], …]`: участок
  сюжета растягивается на экране. `toFilm(s)` в main.js и `W(t)` в mix.py пересчитывают время сами.
- Перед серией идёт заставка студии (`timeline.intro` = 6,5 с): видео = intro + duration.
- Если реплика автора не влезает: добавьте stretch на участок перед следующей репликой (а не двигайте все шоты).

## 4. Как устроена серия

`episode.js` экспортирует:
```js
export default {
  title: 'Серия 2 · Сигнал',
  buildShots,                                  // (C) => [{t0, t1, run(lt, t), noSubs?, noFlash?, flashK?}, …]
  world: t => ({ police, crowd, bridge, alarm }),   // какие «живые» части общего мира включены
  gradeAt: t => 'night' | 'street' | 'lab' | …,     // цветокоррекция (engine/src/post.js GRADES)
  mblur: [[a, b], …],                          // где motion blur (только q=high)
};
```
`C` (контекст) содержит: `city, lab, kitchen, lair, cab, school, zaton, ch` (персонажи), `props` (bike, bus, busPivot, spider,
webs, sparks, sparks2, rings, spray, swirl, shards), `camera, overlay, U` (униформы: flash, sense, rainTime, tint…),
`bolts, lines, mouthOf, shapeOf, fricOf, kitchenD, labD, bridgeD, crowd, life, EP`.
Шот каждый кадр выставляет **всё заново** (персонажи скрываются в resetFrame) и возвращает сцену:
`C.city.scene` (город, лаборатория внутри башни), `C.kitchen.scene`, `C.lair.scene`, `C.cab.scene`,
`C.school.corridor/classroom/canteen.scene`, `C.zaton.scene` (двор и лицей).
`world(t)` может вернуть `kitchen: {day: 0…1, hour, tick, rec}` — утро/вечер на кухне, часы, бегущая строка ТВ.

### Режиссёрский набор `engine/src/director.js`
```js
const D = makeDirector(C);
D.shot(t0, t1, (lt, t) => { …; return D.S; }, { noSubs, noFlash });
D.look(pos, at, fov, roll)            // камера (fov ≤ 38 и близко → глубина резкости на видеокарте)
D.move(t, [[t, pos, at, fov], …])     // проезд камеры по ключам
D.place(ch, parent, [x,y,z], yaw)     // yaw = 0 → смотрит в +Z; yawTo(a, b) — повернуться к точке
D.face(ch, 'timur', t, {brow, smile, squint, wide, look:[x,y], dim, energy, at, atK})  // липсинк, моргание, дыхание;
                                      // at — точка/Vector3, куда повернуть голову (собеседник, событие), atK — сила
D.impact(t, t0, {zoom, shake, color}) // «кадр удара»
D.comic('БАМ!', x, y, t - t0, {size, color, rot, dur})  ·  D.caption('Соседняя крыша…', x, y, t - t0)
D.panel(i, k, [x,y,w,h], scene, pos, at, fov)   // комикс-панель со вторым ракурсом
D.web(TI, 'R', [x,y,z], t, t0)  ·  D.sparks(pos, dt)  ·  D.ring(pos, r, a)  ·  D.sense(t, k, t0)  // паучье чутьё
D.drone(i, pos, yaw, t, {walk, pitch, roll, scale, parent})   // чёрные дроны Тени (6 шт.)
D.kronovFX(t, {damaged, core})  ·  D.cabCall(t, k)  ·  D.rideBike(t, x, z, {pose})  ·  D.labBase(t, {broken})
D.handW / headW / footW(ch)           // мировые координаты руки/головы/ступни
D.onReset(fn)                         // сброс своего реквизита перед каждым кадром
FIGHT.guard/leanBack/load/dropKick/kickR/tuck/zip/shootBoth/eat/tired   HEAVY.windUp/swing(k)/hitBack/slump
```

### Персонажи (`C.ch`)
`timur, ded, vera, kronov, shadow`, лицей: `marjon, diyor, azim, teacher`, злодей `odilman`, школьники `s0…s23`,
бабушки во дворе `granny0/granny1` (`makeCharacter('granny', {variant})` — платок, кофта)
(`makeCharacter('student', {variant})`, s8/s9 — дружки Азима). Маржон: `sketch` (скетчбук с комиксом), `tail` (хвост);
Азим: `gum`; учительница: `chalk`; ODILMAN: `lensList` (белые глаза — цвет = свечение), `ribbons` + `wind` (ленты маски). У каждого: `root` (Group), `J` (суставы: hips, spine, chest, neck, head,
armL/R, foreL/R, handL/R, legL/R, shinL/R, footL/R), `pose(p)`, `setFace(f)`, `d.k` (масштаб: Кронов 1.6),
`d.hipY`. Тимур: `setSuit(true/false)`, `mats.hand.emissive` (свечение запястий). Вера: `tablet`. Тень: `redEyes`.
Кронов: `arachna` (ядро в груди), `stolen` (ядро в руке).
**Поза** — объект `{joint: [x, y, z], hy, hz, grip, gripL/R, spiderL/R}`: `arm*` x < 0 — рука вперёд/вверх,
z — отвести в сторону (зеркально для L/R); `leg*` x < 0 — нога вперёд; `shin*` > 0 — согнуть колено;
`spine` x > 0 — наклон вперёд, y — поворот корпуса; `hy` — присесть (в долях роста).
`seq(t - t0, [[0, позаИлиФункция], [1.2, …, длительностьПерехода]])` — последовательность с «перелётом».
Готовые позы — `POSE` в rig.js: stand, talk, walk, run, heavyWalk, bike, crouch, spiderCrouch, heroLand, lie,
sitUp, fall, shootUp, shootFwd, swing, flip, pull, hangUpside, sitChair, punch, roar, dodge, strained, collapse,
phone, reach, hold, pointFinger, adjustGlasses, fistShake, shrug, lookUp.

### Карта мира (метры, Y — вверх)
- Неоновый проспект — вдоль оси Z, x ≈ 0; кварталы 80 м; рекламные щиты на крышах, напр. «БЫСТРО» (−40, ~79, 200).
- Башня «Аркада» — (40, 0, −440); **лаборатория**: пол на y = 258.82, `L2W(x, y, z)` — из координат лаборатории
  в мир; капсулы x ±9, z −8/−2/4, главная — (0, −11); стеклянная стена с разбитым окном — x ≈ 24, y ≈ 9.
- Северный мост — полотно x 300…640, z −412…−388, пилоны x 390 и 550; крыша у моста — y 74.1, (256…308, −387…−337).
- Кухня деда: стол (0, 0, −0.6); дед на стуле (−0.55, 0, −1.45) yaw 0; Тимур (0.55, 0, 0.25) yaw π; ТВ — `kitchenD.tvPos`.
- Лицей (school.js, у каждой сцены пол y = 0): коридор x −21…21, шкафчики z ≈ −2 (дверцы `doorD` x −1.25, `doorM` x 6.25),
  окна/батареи z ≈ 2.5, табличка `wetSign`, вмятина `dent`; класс: доска z −4.5, парты 3×4 (x = −3 + 2.7c, z = −1.6 + 1.6r),
  стул ±0.32 по x и +0.55 по z от парты, смотрят yaw π; столовая: столы x −3.2/2.8, z −2.2/0.8/3.8, табуретки ±0.85 по z,
  ТВ на стене x = 8 (`drawTV(t)`), поднос Тимура `timurTray`.
- Затон (zaton.js): фасад дома z = 0, подъезды x −16.5/−4.5 (Тимур)/4.5 (Маржон)/16.5, лавочки z 2.4 (±2.3 от подъезда),
  окно мамы Маржон `momWin/momSash/momSil` (10.5, 5.35), двор z 4…16, тротуар 16…19.5, дорога 19.5…27, остановка (22, 0, 18.2),
  `bus`, `oranges`, `bag`, голуби `pigeons` (вспорхнут, если в шоте задать `Z.scareAt = t0`), стая птиц, листопад, облака в небе;
  лицей — группа `school` в (600, 0, 0): ворота x ±4 на z = 16, двери z ≈ 3. `setTime('morning'|'sunset'|'dusk')`
  или смесь `setTime(a, b, k)` — вызывать в каждом шоте этой сцены.
- Логово Тени: кресло (0, 0, −0.3), Тень (0, 0.02, 0.2) yaw 0, стена мониторов по дуге за креслом.

---

## 5. Звук и озвучка

1. Реплики — `dialogue.json` (`id`: буква персонажа + номер; `who`: timur, narrator, ded, vera, kronov, shadow,
   crowd, news, drone, sokol, mgla; `fx`: phone | memory | radio | tv; `say` — как произносить синтезу; `hint` — подсказка актёру).
2. `python3 tools/voiceover.py <ep>` → `VOICEOVER.md` для автора (с максимальной длиной каждой реплики).
3. Автор записывает **все реплики подряд одним файлом** → `episodes/<ep>/audio/voice_src/` → `tools/audio.sh <ep>`.
   Нарезчик сравнивает запись с синтезом тех же фраз и раскладывает по репликам; если ошибся —
   `<запись>.map.json`: `{"t14": [51, 52]}` (номера участков речи печатает нарезчик). Потом пересобрать.
4. Партитура — `audio/cues.py`: `add(bus, сигнал, t, gain, pan, rev)`, `groove(t0, t1, prog, intensity)`,
   `melody(notes, t0, step, inst, amp)`, `chord('Dm', t0, len)`, `hit(t, amp, chord)`, инструменты
   (kick, snare, taiko, pad, pluck, brass, strings, bell…), шумы (whoosh, impact, thwip, splat, zap, glass,
   servo, stomp, siren, screech…), `walla` (гул толпы), `rain_bed/seg` (дождь по сценам), `strikes_thunder()`.
   Тема героя `HERO` (ре минор), аккорды `CH`, `BEAT/BAR` (126 BPM).
5. Голос новых персонажей — профиль в `engine/audio/voices.py` (PROFILES) или `episodes/<ep>/audio/voices.json`.

## 6. Как сделать новую серию (порядок работы)

1. Сюжет — по плану сезона в `SERIES_BIBLE.md` §6. `node tools/new-episode.mjs N "Название"`.
2. `STORY.md`: идея, сцены с таймингом (сюжетное время), кадр/камера/звук. Потом `dialogue.json` (25–35 реплик).
3. `tools/audio.sh eNN` с синтезом (черновые голоса) → можно ставить шоты под реальные длины реплик.
4. `shots.js` сцена за сценой; после каждой сцены — 4–8 стоп-кадров и контакт-лист; правка.
5. `episode.js`: gradeAt, world, mblur. Добавить серию в `episodes/index.json` (new-episode делает сам).
6. `VOICEOVER.md` → автор записывает → `tools/audio.sh eNN` → проверить синхрон (stretch при необходимости).
7. Коммит, пуш, `python3 tools/pack.py` → отдать архив; автор рендерит у себя.

---

## 7. Уроки и подводные камни (выучено на серии 1)

- **Каждое действие — причина и следствие в одном кадре** (удар → отлёт → что задел). Иначе зритель «не понимает».
- **Правило 180°:** в сцене драки герой слева, противник справа — камера не перепрыгивает линию.
- Комикс-надписи и плашки — **не поверх главного действия**.
- Камера не должна «гнаться» за очень быстрой целью (motion blur размоет весь кадр); motion blur сам берёт
  до 24 подкадров при быстрой проводке. Резкие развороты персонажа (yaw скачком) → «лесенка» в смазе: поворачивать плавно (kf).
- Тун-материал + точечный свет = жёсткое «пятно-диск». Для больших поверхностей под прожектором — Lambert.
- Белые машины/объекты пересвечиваются в bloom — брать средние тона.
- Камера не должна стоять внутри перил, столбов, персонажей (проверять стоп-кадром).
- Персонажи на крышах: у «особых» домов (`SPEC` в city.js) нет парапета — на них стоят герои.
- Руки на руле/предметах — через `ikArm` (полюс сгиба назад-вниз), иначе руки перекрещиваются.
- Озвучка: короткие реплики (1–2 слова) нарезчик путает — проверять `alignment.json` и править `map.json`.
- Длинные фоновые команды: не ждать `sleep`-ом, `pgrep -f` находит сам себя — ждать по файлу-флагу.
- `RENDER_WINDOWS.bat` должен быть в CRLF (pack.py делает сам).
- Модели и голоса TTS в облаке: RHVoice `/usr/bin/RHVoice-test`, Piper-модель `/opt/voices/ru-irinia-medium.onnx`.

### Выучено на серии 2
- Боковой ракурс драки (камера на одной стороне линии) часто перекрывают фигуранты между камерой и героями —
  расставлять толпу **за** дерущимися и проверять каждый ракурс стоп-кадром.
- Паучье чутьё в интерьерах: городские шейдеры не синеют — нужен синий грейд + заливка кадра (см. `sense` в e02/shots.js).
- Комикс-надписи рядом с лицами смещать в угол кадра; буквы «в воздухе» — по бокам, не на лбу.
- Предмет в руке, который должен «смотреть» в камеру (скетчбук, телефон), — `obj.lookAt(camera.position)` после `look`.
- В e02/shots.js есть помощники, которые стоит копировать в новые серии: `walk` (ходьба по ломаной), `talking`
  (жест говорящего поверх любой позы), `close`/`ots` (крупный план и «через плечо»), `extra` (фигуранты с манерами:
  перенос веса, руки на поясе/за спиной, кивки), `stroll` (фон ходит туда-обратно), `speakerAt` (смотреть на того, кто
  говорит), `LIFE` (позы массовки: talk, listen, laugh, wow, cheer, film, eat, write, yawn, chin…), `hold/put` (реквизит).
- Персонажи «оживают», когда смотрят друг на друга: у каждого в кадре должен быть `at` (собеседник, событие, ТВ).
- Случайность только детерминированная (`rng(seed)`), иначе при рендере в несколько потоков кадры «прыгают».

## 8. Git

Работа ведётся в ветке, указанной в задаче; коммит + push после каждого законченного шага.
Готовые `soundtrack.m4a`/`lipsync.json` коммитятся (автору не нужен Python). `soundtrack.wav`, `audio/voice*`
(кроме voice_src и map.json), `out/`, `node_modules/` — в .gitignore.
