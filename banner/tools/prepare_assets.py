"""Подготовка материалов из интернета (Wikimedia Commons) для баннера.

python3 tools/prepare_assets.py <папка с исходниками>

Исходники и лицензии — в CREDITS.md. Скрипт тонирует фото под палитру баннера
и вырезает мотивы сюзане в золотые PNG с прозрачным фоном.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

SRC = sys.argv[1]
DST = os.path.join(os.path.dirname(__file__), '..', 'img')


def src(name):
    return Image.open(os.path.join(SRC, name))


def save(im, name, **kw):
    path = os.path.join(DST, name)
    im.save(path, **kw)
    print(path, im.size)


def tritone(im, stops):
    """Тонирование по яркости через несколько цветовых опор."""
    lum = np.asarray(ImageOps.grayscale(im)).astype(np.float32) / 255
    xs = np.array([s[0] for s in stops])
    out = np.stack([np.interp(lum, xs, [s[1][c] for s in stops]) for c in range(3)], -1)
    return Image.fromarray(out.astype(np.uint8), 'RGB')


# Регистан ночью: тёмно-синие тени, золотая подсветка
reg = ImageEnhance.Contrast(src('registan2.jpg').convert('RGB')).enhance(1.1)
save(tritone(reg, [(0, (5, 16, 32)), (.22, (18, 48, 84)), (.5, (92, 104, 118)), (.78, (226, 190, 124)), (1, (255, 240, 205))]),
     'registan-night.jpg', quality=90)

# Портрет Алишера Навои (миниатюра, Герат, кон. XV в.) — как есть, чуть мягче по цвету
por = src('navoi-portrait.jpg').convert('RGB')
por = ImageEnhance.Color(por).enhance(.92)
save(por, 'navoi-portrait.jpg', quality=92)

# Рукопись Навои: убрать зелёный отлив витрины, тон пергамента
ms = src('navoi-manuscript.jpg').convert('RGB').crop((90, 250, 1210, 1440))
ms = ImageEnhance.Contrast(ms).enhance(1.25)
save(tritone(ms, [(0, (28, 16, 8)), (.3, (86, 58, 30)), (.62, (196, 164, 112)), (1, (248, 232, 196))]),
     'navoi-manuscript.jpg', quality=90)

# Мотивы сюзане: чёрный рисунок → золото на прозрачном фоне
sheet = ImageOps.grayscale(src('suzani3.jpg'))
MOTIFS = {
    'motif-palmette.png': (1455, 318, 1740, 572),
    'motif-pomegranate.png': (1068, 808, 1368, 1112),
}
for name, box in MOTIFS.items():
    g = np.asarray(sheet.crop(box).filter(ImageFilter.GaussianBlur(.6))).astype(np.float32)
    alpha = np.clip((185 - g) / 95, 0, 1)
    h, w = alpha.shape
    yy = np.linspace(0, 1, h)[:, None]
    gold = np.empty((h, w, 4), np.float32)
    # вертикальный перелив золота
    for c, (a, b) in enumerate(((246, 176), (226, 140), (170, 82))):
        gold[..., c] = a + (b - a) * (0.5 + 0.5 * np.sin(yy * 5.5 + 0.6))
    gold[..., 3] = alpha * 255
    save(Image.fromarray(gold.astype(np.uint8), 'RGBA'), name)
