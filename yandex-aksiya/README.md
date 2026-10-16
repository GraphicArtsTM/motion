# Yandex Go taksopark — «Brend ruxsatnoma aksiyada» (Instagram Reels, 1080×1920, 30 с, 30 fps)

Вертикальный (9:16) моушн-ролик для акции таксопарка: брендовая разрешительная (ruxsatnoma)
за 440 000 сум, остаток оплачивает таксопарк. Информация взята из старой версии ролика,
визуал и анимация сделаны заново. Озвучка на узбекском — `audio/voice.mp3` (ElevenLabs).

Готовое видео: `out/yandex-aksiya-reels-1080x1920.mp4`.

## Под Reels

- **Темп.** Озвучка (15,6 с) записана без пауз, поэтому `voice.py` режет её по тишине между фразами
  и ставит каждую фразу на свою сцену с паузой. Каждый текст появляется на своём слове и держится
  в кадре 1,5–3 с после того, как сказан. Появления — 0,5–0,8 с, переходы — 0,5–0,8 с, тряска камеры мягкая.
- **Безопасные зоны.** Весь текст в полосе y 300…1450: сверху ~220 px занимает интерфейс Reels,
  снизу ~420 px — подпись и кнопки. Всё, что ниже y 1050, сдвинуто влево (центр x 520, ширина ≤ 860),
  чтобы не залезать под лайк/коммент/репост справа. Низ кадра — только декор (дорога, шашечки).
- **Формат.** H.264 High, 30 fps, AAC 48 кГц 256 кбит/с, громкость −14 LUFS, faststart.

## Сценарий

| Время | Голос | Что в кадре |
|---|---|---|
| 0–4,6 с | «Endi brend ruxsatnomasi bizda aksiyada» | Такси въезжает, BREND / RUXSATNOMA собираются по буквам, плашка BIZDA, наклейка «AKSIYADA!» |
| 4,6–8,5 с | «Atigi 440 ming so'mga» | Шторка в чёрное, барабаны цифр докручиваются до 440, конфетти, «MING SO’M», «brend ruxsatnoma uchun» |
| 8,5–13,1 с | «Aksiyadan foydalanib qoling» | Ирис в белый: «AKSIYADAN FOYDALANIB QOLING!», затем карточки «Siz to’laysiz 440 000 so’m» + «Qolgan summani taksopark to’laydi!», «FAQAT BIZDA!» |
| 13,1–16,2 с | «Hujjatlaringizni tez va oson rasmiylashtiring» | Документы веером, TEZ ✓ / OSON ✓, «RASMIYLASHTIRING», штамп «TAYYOR ✓» |
| 16,2–18,4 с | — | Условие: «SHARTI: bizning taksoparkda ISHLASH KIFOYA!» |
| 18,4–21,3 с | «Aksiya muddati cheklangan» | Предупредительные ленты, секундомер истекает, «AKSIYA MUDDATI CHEKLANGAN!» |
| 21,3–30 с | «Batafsil ma'lumot uchun hoziroq murojaat qiling. Telegramdan yozing yoki qo'ng'iroq qiling» | «HOZIROQ MUROJAAT QILING!», кнопка Telegram @YANDEXDASTURCHI с тапом, кнопка +998 90 375 44 06 со звонком, такси и «FAQAT BIZDA!»; финал держится ~3 с |

Моменты фраз — в `voice.py` (`SEGMENTS`); слова размечены Whisper. При замене голоса поправьте
`SEGMENTS`, тайминги сцен в `motion.js` и события `fx(...)` в `music.py`.

## Звук

`music.py` синтезирует всё на numpy, без сэмплов, и пишет две дорожки:

- `out/music.wav` — хаус 128 BPM в ля гармоническом миноре: бочка, клэп, хэты, дойра, офбит-бас
  с сайдчейном, стабы, щипковый «дутар», мелодия; брейк с тиканьем на сцене «muddati cheklangan».
- `out/sfx.wav` — эффекты под каждое событие в кадре: проезд такси, «поп» появления, хлопки наклеек
  и штампов, удары, щелчки барабанов цифр, монеты, шорох листов, колокольчики TEZ/OSON, глитч,
  тиканье секундомера, тап по кнопке, звонок, блики.

`build.sh` приглушает музыку под голосом, а эффекты кладёт отдельно без приглушения — так их слышно.

## Сборка

Нужны Node.js с Playwright (Chromium), Python 3 с numpy и ffmpeg.

```bash
./build.sh                                   # голос → музыка/эффекты → кадры → out/yandex-aksiya-reels-1080x1920.mp4
node render.mjs --stills 2.5,7.5,12.5,17.8   # стоп-кадры для проверки в out/stills/
```

Предпросмотр в браузере: `index.html` (проигрывается по кругу, без звука) или `index.html?t=12.5` (стоп-кадр).

Шрифты Unbounded и Rubik — Google Fonts, лицензия SIL Open Font License.
