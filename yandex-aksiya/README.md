# Yandex Go taksopark — «Brend ruxsatnoma aksiyada» (1080×1920, 18,5 с, 60 fps)

Вертикальный (9:16) моушн-ролик для акции таксопарка: брендовая разрешительная (ruxsatnoma)
за 440 000 сум, остаток оплачивает таксопарк. Информация взята из старой версии ролика,
визуал и анимация сделаны заново. Озвучка на узбекском — `audio/voice.mp3` (ElevenLabs).

Готовое видео: `out/yandex-aksiya-1080x1920.mp4`.

## Сценарий (синхронизирован с озвучкой, голос стартует с 0,4 с)

| Время | Голос | Что в кадре |
|---|---|---|
| 0–2,85 с | «Endi brend ruxsatnomasi bizda aksiyada» | Ирис на жёлтый, такси въезжает по дороге, BREND / RUXSATNOMA собираются по буквам, плашка BIZDA, штамп «AKSIYADA!» |
| 2,85–4,9 с | «Atigi 440 ming so'mga» | Шторка в чёрное, барабаны цифр докручиваются до 440, взрыв конфетти, «MING SO’M», «brend ruxsatnoma uchun» |
| 4,9–6,4 с | «Aksiyadan foydalanib qoling» | Ирис в белый: «AKSIYADAN FOYDALANIB QOLING!», карточки «Siz to’laysiz 440 000 so’m» + «Qolgan summani taksopark to’laydi!», «FAQAT BIZDA!» |
| 6,4–9,3 с | «Hujjatlaringizni tez va oson rasmiylashtiring» | Документы веером, чипы TEZ ✓ / OSON ✓, штамп «TAYYOR ✓», условие «Sharti: bizning taksoparkda ishlash kifoya!», глитч |
| 9,3–10,9 с | «Aksiya muddati cheklangan» | Предупредительные ленты, секундомер истекает, «AKSIYA MUDDATI CHEKLANGAN!» |
| 10,9–18,5 с | «Batafsil ma'lumot uchun hoziroq murojaat qiling, Telegramdan yozing yoki qo'ng'iroq qiling» | «HOZIROQ MUROJAAT QILING!», кнопка Telegram @YANDEXDASTURCHI с тапом, кнопка +998 90 375 44 06 со звонком, финал с такси и «FAQAT BIZDA!» |

Тайминги слов получены из озвучки распознаванием (Whisper); при замене голоса сдвиньте
моменты в `motion.js` (сцены и `HITS`) и события в `music.py`.

## Звук

`music.py` синтезирует трек на numpy, без сэмплов: 128 BPM, ля гармонический минор, хаус-грув
с дойрой, офбит-бас, стабы, щипковый «дутар», брейк с тиканьем секундомера и звуки событий
(проезд машины, штампы, барабаны цифр, монеты, шорох листов, тап, звонок).
`build.sh` кладёт озвучку поверх и приглушает музыку под голосом (sidechain), итог −14 LUFS.

## Сборка

Нужны Node.js с Playwright (Chromium), Python 3 с numpy и ffmpeg.

```bash
./build.sh                                   # музыка → кадры → сведение → out/yandex-aksiya-1080x1920.mp4
node render.mjs --stills 2.5,4.7,8.8,16.3    # стоп-кадры для проверки в out/stills/
```

Предпросмотр в браузере: `index.html` (проигрывается по кругу, без звука) или `index.html?t=12.5` (стоп-кадр).

Шрифты Unbounded и Rubik — Google Fonts, лицензия SIL Open Font License.
