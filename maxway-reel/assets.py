"""Графика для монтажа: 3D-текст, плашки, искры и вырезанные сэндвичи.

Все спрайты возвращаются как float32 BGRA с премультиплицированной альфой (0..1),
чтобы их можно было честно вращать/масштабировать и класть друг на друга.
"""
import os

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, '..', 'video', 'fonts')

# палитра Maxway из самого ролика
PURPLE = (124, 96, 214)        # RGB фона «max way»
PURPLE_D = (58, 30, 140)
PURPLE_DD = (30, 14, 82)
YELLOW = (255, 210, 31)
YELLOW_D = (214, 158, 0)
INK = (27, 15, 59)
WHITE = (255, 255, 255)


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, f'{name}.ttf'), size)


def to_premul(img):
    """PIL RGBA -> float32 BGRA (премультипликация)."""
    a = np.asarray(img).astype(np.float32) / 255.0
    rgb = a[..., :3] * a[..., 3:4]
    return np.dstack([rgb[..., ::-1], a[..., 3]]).astype(np.float32)


def _grad(w, h, top, bot):
    t = np.linspace(0, 1, h)[:, None, None]
    g = np.array(top, np.float32) * (1 - t) + np.array(bot, np.float32) * t
    return Image.fromarray(np.repeat(g, w, axis=1).astype(np.uint8), 'RGB')


def extruded_text(text, fnt, face_top, face_bot, ext_top, ext_bot, depth=16,
                  ddx=0.55, ddy=1.0, stroke=0, stroke_col=WHITE, pad=60, shadow=0.45):
    """Текст с объёмной экструзией вниз-вправо, градиентом лица и мягкой тенью.

    Возвращает (sprite, face_alpha, origin), где origin — смещение левого верхнего
    угла bbox текста внутри спрайта.
    """
    l, t, r, b = fnt.getbbox(text, stroke_width=stroke)
    w = r - l + 2 * pad + int(depth * ddx) + 4
    h = b - t + 2 * pad + int(depth * ddy) + 4
    ox, oy = pad - l, pad - t

    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).text((ox, oy), text, font=fnt, fill=255, stroke_width=stroke, stroke_fill=255)

    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    # мягкая падающая тень
    if shadow:
        sh = mask.copy().filter(ImageFilter.GaussianBlur(14))
        sh_layer = Image.new('RGBA', (w, h), (10, 4, 30, 0))
        sh_layer.putalpha(sh.point(lambda v: int(v * shadow)))
        out.alpha_composite(sh_layer, (int(depth * ddx) + 6, int(depth * ddy) + 14))
    # экструзия: слои от дальнего к ближнему
    for i in range(depth, 0, -1):
        k = i / depth
        col = tuple(int(ext_top[c] * (1 - k) + ext_bot[c] * k) for c in range(3))
        layer = Image.new('RGBA', (w, h), col + (0,))
        layer.putalpha(mask)
        out.alpha_composite(layer, (int(round(i * ddx)), int(round(i * ddy))))
    # лицо
    face = _grad(w, h, face_top, face_bot).convert('RGBA')
    if stroke:
        inner = Image.new('L', (w, h), 0)
        ImageDraw.Draw(inner).text((ox, oy), text, font=fnt, fill=255)
        st = Image.new('RGBA', (w, h), stroke_col + (0,))
        st.putalpha(mask)
        out.alpha_composite(st)
        face.putalpha(inner)
        face_mask = inner
    else:
        face.putalpha(mask)
        face_mask = mask
    out.alpha_composite(face)
    return to_premul(out), np.asarray(face_mask).astype(np.float32) / 255.0, (ox, oy)


def pill(text, fnt, fill=YELLOW, edge=YELLOW_D, ink=INK, padx=40, pady=22, depth=10, pad=40):
    """Плашка-«таблетка» с объёмным нижним краем и тенью."""
    l, t, r, b = fnt.getbbox(text)
    tw, th = r - l, b - t
    pw, ph = tw + 2 * padx, th + 2 * pady
    w, h = pw + 2 * pad, ph + 2 * pad + depth
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    sh = Image.new('L', (w, h), 0)
    ImageDraw.Draw(sh).rounded_rectangle((pad + 6, pad + depth + 12, pad + pw + 6, pad + ph + depth + 12), ph // 2, fill=130)
    sh = sh.filter(ImageFilter.GaussianBlur(12))
    shl = Image.new('RGBA', (w, h), (10, 4, 30, 0))
    shl.putalpha(sh)
    img.alpha_composite(shl)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((pad, pad + depth, pad + pw, pad + ph + depth), ph // 2, fill=edge + (255,))
    d.rounded_rectangle((pad, pad, pad + pw, pad + ph), ph // 2, fill=fill + (255,))
    # блик сверху
    hl = Image.new('L', (w, h), 0)
    ImageDraw.Draw(hl).rounded_rectangle((pad + ph // 3, pad + 5, pad + pw - ph // 3, pad + ph * 0.42), ph // 5, fill=70)
    hl = hl.filter(ImageFilter.GaussianBlur(4))
    hll = Image.new('RGBA', (w, h), (255, 255, 255, 0))
    hll.putalpha(hl)
    img.alpha_composite(hll)
    tx, ty = pad + padx - l, pad + pady - t
    return img, (tx, ty), (pad, pad, pw, ph)


def pill_text_layers(text, fnt, **kw):
    """Плашка отдельно и слова отдельно (для поочерёдного появления слов)."""
    img, (tx, ty), box = pill(text, fnt, **kw)
    ink = kw.get('ink', INK)
    words = []
    x = 0
    parts = text.split(' ')
    for i, wd in enumerate(parts):
        prefix = ' '.join(parts[:i]) + (' ' if i else '')
        x = fnt.getlength(prefix)
        lay = Image.new('RGBA', img.size, (0, 0, 0, 0))
        ImageDraw.Draw(lay).text((tx + x, ty), wd, font=fnt, fill=ink + (255,))
        bb = fnt.getbbox(wd)
        cx = tx + x + (bb[0] + bb[2]) / 2
        cy = ty + (bb[1] + bb[3]) / 2
        words.append((to_premul(lay), (cx, cy)))
    return to_premul(img), words, box


def sparkle(size, color=WHITE, glow=True):
    """Четырёхлучевая искра (как звёздочки в ролике Maxway)."""
    s = size * 3
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    c = s / 2
    r = size / 2
    pts = []
    for k in range(8):
        ang = np.pi / 4 * k - np.pi / 2
        rr = r if k % 2 == 0 else r * 0.2
        pts.append((c + rr * np.cos(ang), c + rr * np.sin(ang)))
    lay = Image.new('RGBA', (s, s), color + (0,))
    m = Image.new('L', (s, s), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    lay.putalpha(m)
    if glow:
        g = m.filter(ImageFilter.GaussianBlur(size * 0.18))
        gl = Image.new('RGBA', (s, s), color + (0,))
        gl.putalpha(g.point(lambda v: int(v * 0.8)))
        img.alpha_composite(gl)
    img.alpha_composite(lay)
    return to_premul(img)


def key_sandwiches(frame_bgr):
    """Вырезает пару сэндвичей с фиолетового фона финальной сцены ролика (t≈27 с).

    Возвращает (пара, правый с бантом) как премультиплированные BGRA.
    """
    hsv = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    h, s, _ = cv2.split(hsv)
    pur = np.clip(1 - np.abs(h - 131) / 14, 0, 1) * np.clip((s - 40) / 40, 0, 1)
    alpha = cv2.GaussianBlur(1 - np.clip(pur * 1.6, 0, 1), (3, 3), 0)
    y0, y1 = 1100, 1640
    a = alpha[y0:y1]
    img = frame_bgr[y0:y1].astype(np.float32) / 255
    n, lbl, st, _ = cv2.connectedComponentsWithStats((a > 0.5).astype(np.uint8))
    k = 1 + int(np.argmax(st[1:, 4]))
    a = np.where(lbl == k, a, 0)
    x, y, w, hh = st[k][:4]
    a = a[y:y + hh, x:x + w]
    img = img[y:y + hh, x:x + w]
    col = (a > 0.5).sum(0)
    lo, hi = int(w * 0.35), int(w * 0.65)
    cut = lo + int(np.argmin(col[lo:hi]))
    pair = np.dstack([img * a[..., None], a]).astype(np.float32)
    right = pair[:, cut - 2:].copy()
    # мягкий край по линии разреза
    ramp = np.clip(np.arange(right.shape[1]) / 14.0, 0, 1)[None, :, None]
    right *= ramp
    return pair, right


def resize_sprite(sp, width):
    h, w = sp.shape[:2]
    k = width / w
    return cv2.resize(sp, (int(round(w * k)), int(round(h * k))), interpolation=cv2.INTER_AREA)
