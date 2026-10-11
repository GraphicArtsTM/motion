# «Farqi nimada?» — reels 1080×1920 (9:16)

Информативный моушн-ролик для Instagram Reels на узбекском: четыре пары терминов, которые часто путают,
и разница между ними. Озвучка на узбекском, динамичная музыка, караоке-субтитры, анимированные иллюстрации.

Готовое видео: `out/farq-reels-1080x1920.mp4` (~110 с, 30 fps, H.264 + AAC, −14 LUFS).

## Структура ролика

| Сцена | Что происходит |
|---|---|
| Интро | Удар «2 SO‘Z / 1 FARQ», бегущие строки терминов, карусель пар, голос: «Bu so‘zlarni ko‘pchilik adashtiradi…» |
| Пара ×4 | Шторка в цветах пары → номер, два слова сталкиваются, «VS» со вспышкой и искрами, вопрос «… farqi nimada?» |
| | Карточка 1: анимированная иллюстрация, термин, определение подсвечивается по словам синхронно с голосом, ключевые слова — маркером |
| | Карточка 2 уезжает вбок, приходит вторая; иллюстрация реагирует на ключевые слова |
| | «Qisqa farq»: две плашки с чипами-тезисами и знак ≠ |
| Финал | «Eslab qoling» — список всех пар, иконки «Saqlang», «Ulashing», кнопка «Obuna bo‘ling» на соответствующих словах |

Пары: Kommunizm ≠ Sotsializm · Demokratiya ≠ Respublika · Millatchilik ≠ Shovinizm · Kapitalizm ≠ Sotsializm.

Иллюстрации: классы-ступени выравниваются (kommunizm), ресурс распределяется по кругу людей (sotsializm),
бюллетени в урне (demokratiya), зачёркнутая корона и выборный лидер (respublika), флаг и щит (millatchilik),
пьедестал и принижение других (shovinizm), завод, рынок и гонка конкурентов (kapitalizm), шестерня общего хозяйства (sotsializm).

## Текст

Весь текст — в `script.json`. Исправления относительно исходника:

- Kommunizm: «xususiy ishlab chiqarish mulki bo‘lmagan» → «ishlab chiqarish vositalari xususiy mulk bo‘lmagan» (точнее и по-узбекски естественнее).
- Respublika: «davlat boshlig‘i monarx kabi meros orqali emas, saylov yo‘li bilan hokimiyatga keladigan davlat shakli» — порядок слов и уточнение.
- Kapitalizm: определение оформлено одним предложением «… muhim rol o‘ynaydigan iqtisodiy tizim».
- Sotsializm (4): «ijtimoiy manfaatlar va resurslarni … boshqarishga» → «ijtimoiy manfaatlarga hamda resurslarni …» (убрана двусмысленность).
- Пункту 4 добавлен вопрос «Kapitalizm va sotsializm farqi nimada?», как у остальных.
- В первой паре определения идут в порядке вопроса: сначала kommunizm, потом sotsializm.

## Сборка

```bash
./build.sh                    # голос → музыка и микс → кадры → out/farq-reels-1080x1920.mp4
./build.sh --engine edge      # принудительно нейроголос Microsoft uz-UZ-SardorNeural
FPS=60 ./build.sh             # 60 fps
node render.mjs --stills 12,27.5   # стоп-кадры в out/stills/
```

Нужны: Python 3 + numpy, Node.js + Playwright (Chromium), ffmpeg; для голоса — `pip install edge-tts`
(онлайн) или `espeak-ng` + `mbrola` + `mbrola-tr1` (офлайн).

- `tts.py` — синтез реплик, раскладка по сетке 120 BPM, время каждого слова и ключевых слов → `timeline.js`, `out/voice.wav`.
  Движок `edge` (нейроголос, нужен доступ к speech.platform.bing.com) пробуется первым; без сети — `mbrola`:
  espeak-ng + диктор MBROLA tr1, узбекская латиница переводится в близкую по звучанию турецкую орфографию.
- `music.py` — трек на numpy (кик, клэп, хэты, бас, пиццикато, пэды, лид-хук, райзеры, удары), энергия по сценам,
  звуки на событиях кадра, сайдчейн по огибающей голоса → `out/music.wav`, `out/mix.wav`.
- `index.html` + `motion.js` — сцена; `renderAt(t)` детерминированно рисует кадр. Предпросмотр: открыть `index.html`
  (по кругу) или `index.html?t=20` (стоп-кадр).
- `render.mjs` — покадровый рендер через Chromium в ffmpeg.

Если поменять текст в `script.json`, тайминги, анимация и музыка перестроятся сами.

Шрифты Unbounded и Rubik (`../video/fonts`) — Google Fonts, SIL Open Font License.
