# Баннер «O‘zbek tili — ma’naviyatimiz poydevori, do‘stlik va hamkorlik elchisi»

Приветственный экран 16:9 для праздничного мероприятия Jahon iqtisodiyoti va diplomatiya universiteti.

Готовые файлы: `out/uwed-ozbek-tili-1920x1080.png` и `out/uwed-ozbek-tili-3840x2160.png` (4K).

- Фон — глубокий синий (цвет сайта uwed.uz), тонкая золотая рамка, лента цветов флага по нижнему краю.
- Справа — реальное фото главного корпуса университета (слайдер uwed.uz) в синем дуотоне.
- Печать университета — векторная пересборка официальной узбекской версии с uwed.uz:
  глобус и здание взяты из оригинального логотипа (`img/seal-inner.png`), надписи по кругу
  «JAHON IQTISODIYOTI VA DIPLOMATIYA UNIVERSITETI», «TOSHKENT», «1992» набраны в SVG и не мылятся при любом размере.
- Шрифты: Cormorant Garamond и Montserrat (Google Fonts, SIL OFL), Liberation Serif (SIL OFL) для печати.

## Сборка

```bash
node render.mjs
```

Нужен Node.js с Playwright (Chromium). Текст и вёрстка — в `index.html`.
