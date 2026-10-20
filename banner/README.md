# Баннер «Oʻzbek tili – maʼnaviyatimiz poydevori, doʻstlik va hamkorlik elchisi»

Приветственный экран 16:9 для праздничного мероприятия Jahon iqtisodiyoti va diplomatiya universiteti.

Готовые файлы: `out/uwed-ozbek-tili-1920x1080.png` и `out/uwed-ozbek-tili-3840x2160.png` (4K).

- Композиция — портал-пештак: стрельчатая арка в двойной золотой линии, пазухи и поля заполнены
  орнаментом гирих (восьмиконечные звёзды хатам), рамка с розетками по углам.
- Печать университета венчает арку как замковый камень. Это векторная пересборка официальной
  узбекской версии с uwed.uz: глобус и здание из оригинального логотипа (`img/seal-inner.png`),
  надписи по кругу набраны в SVG.
- Внутри арки — реальное фото главного корпуса университета (слайдер uwed.uz) в синем дуотоне.
- По нижним углам — флаги Узбекистана на золотых древках. Флаг нарисован по официальным
  пропорциям и свёрнут в волну скриптом `tools/make_flag.py` (numpy + Pillow).
- Тексты в официальной латинице: ʻ (U+02BB) в «Oʻzbek», «doʻstlik», ʼ (U+02BC) в «maʼnaviyatimiz».
- Шрифты: Cormorant Garamond и Montserrat (Google Fonts, SIL OFL), Liberation Serif (SIL OFL) для печати.

## Сборка

```bash
python3 tools/make_flag.py img/flag-wave.png   # только если меняется флаг
node render.mjs
```

Нужен Node.js с Playwright (Chromium). Текст и вёрстка — в `index.html`.
