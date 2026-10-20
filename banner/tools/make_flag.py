"""Развевающийся флаг Узбекистана → img/flag-wave.png (прозрачный фон).

Плоский флаг рисуется по официальным пропорциям 1:2, затем сворачивается в волну:
каждый столбец смещается по синусоиде, амплитуда растёт от древка, складки затеняются.
"""
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

W, H = 2000, 1000           # плоский флаг
BLUE, WHITE, GREEN, RED = (0, 153, 181), (255, 255, 255), (30, 181, 58), (206, 17, 38)


def star(d, cx, cy, r, fill):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.382
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)


def flat():
    im = Image.new('RGB', (W, H), WHITE)
    d = ImageDraw.Draw(im)
    u = H / 250                                   # 250 частей по высоте: 80 + 5 + 80 + 5 + 80
    d.rectangle((0, 0, W, 80 * u), fill=BLUE)
    d.rectangle((0, 80 * u, W, 85 * u), fill=RED)
    d.rectangle((0, 165 * u, W, 170 * u), fill=RED)
    d.rectangle((0, 170 * u, W, H), fill=GREEN)
    # полумесяц
    cx, cy, r = 52 * u, 40 * u, 30 * u
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE)
    cx2, r2 = cx + 9 * u, 26 * u
    d.ellipse((cx2 - r2, cy - r2, cx2 + r2, cy + r2), fill=BLUE)
    # 12 звёзд: 3, 4, 5 в рядах, выровнены вправо
    step, sr = 16 * u, 6 * u
    x_right = 150 * u
    for row, n in enumerate((3, 4, 5)):
        y = (16 + row * 16) * u + 8 * u
        for k in range(n):
            star(d, x_right - k * step, y, sr, WHITE)
    return np.asarray(im).astype(np.float32) / 255


def wave(src, out_w=1800, out_h=1100, amp=70, waves=1.6, phase=0.6):
    h, w, _ = src.shape
    pad = (out_h - h * out_w / w) / 2
    xs = np.arange(out_w)
    t = xs / out_w
    a = amp * (0.15 + 0.85 * t)                   # у древка ткань почти неподвижна
    arg = 2 * math.pi * waves * t + phase
    dy = a * (np.sin(arg) + 0.3 * np.sin(2.3 * arg + 1.1))
    slope = np.gradient(dy)                       # наклон поверхности → свет и тень
    s = slope / np.abs(slope).max()
    shade = 0.9 + 0.26 * s
    gloss = np.clip(s, 0, 1) ** 5 * 0.16          # блик на гребнях
    sy = h / (out_h - 2 * pad)
    out = np.zeros((out_h, out_w, 4), np.float32)
    ys = np.arange(out_h)[:, None]
    src_y = (ys - pad - dy[None, :]) * sy
    src_x = np.broadcast_to((xs * w / out_w)[None, :], src_y.shape)
    inside = (src_y >= 0) & (src_y < h - 1)
    y0 = np.clip(np.floor(src_y).astype(int), 0, h - 2)
    fy = (src_y - y0)[..., None]
    x0 = np.clip(src_x.astype(int), 0, w - 1)
    col = src[y0, x0] * (1 - fy) + src[y0 + 1, x0] * fy
    col = np.clip(col * shade[None, :, None] + gloss[None, :, None], 0, 1)
    out[..., :3] = col
    # мягкие края по верху и низу
    edge = np.minimum(src_y, (h - 1) - src_y) / 1.5
    out[..., 3] = np.clip(edge, 0, 1) * inside
    return out


if __name__ == '__main__':
    dst = sys.argv[1] if len(sys.argv) > 1 else 'img/flag-wave.png'
    img = wave(flat())
    Image.fromarray((img * 255).astype(np.uint8), 'RGBA').save(dst)
    print(dst)
