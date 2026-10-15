"""Цветокоррекция съёмок с iPhone (после тонмаппинга HDR→SDR).

Порядок как в Resolve: баланс белого → уровни → плёночная S-кривая по яркости
(без сдвига оттенков) → микроконтраст → раздельное тонирование → вибранс →
резкость → виньетка. Кадр — float32 BGR 0..1.
"""
import cv2
import numpy as np

LOOKS = {
    # селфи: убрать «молочные» тени, чистая стена, живая кожа
    'selfie': dict(wb=(0.985, 1.0, 1.0), black=0.09, white=0.975, gamma=0.95, contrast=0.45,
                   clarity=0.35, vib=0.28, sat=1.0, shadow_tint=(0.018, 0.006, -0.012),
                   high_tint=(-0.012, 0.0, 0.010), sharpen=0.45, vignette=0.22),
    # монитор: убрать жёлтый свет комнаты, глубокий чёрный интерфейса, сочный экран
    'monitor': dict(wb=(1.13, 1.02, 0.93), black=0.02, white=0.96, gamma=0.95, contrast=0.6,
                    clarity=0.4, vib=0.3, sat=1.03, shadow_tint=(0.02, 0.004, -0.01),
                    high_tint=(-0.006, 0.0, 0.006), sharpen=0.5, vignette=0.3),
}

_cache = {}


def _vignette(h, w, amt):
    key = (h, w, amt)
    if key not in _cache:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        r = ((xx - w / 2) / (w * 0.72)) ** 2 + ((yy - h * 0.46) / (h * 0.6)) ** 2
        _cache[key] = (1 - amt * np.clip(r, 0, 1) ** 1.5)[..., None]
    return _cache[key]


def _curve(y, contrast):
    """Плёночная S-кривая: тени мягко уходят в чёрный, света — мягкий плечевой спад."""
    s = y * y * (3 - 2 * y)
    s2 = s * s * (3 - 2 * s)
    return y + (s + (s2 - s) * 0.35 - y) * contrast


def grade(img, look='selfie'):
    p = LOOKS[look]
    x = img * np.array(p['wb'], np.float32)
    x = np.clip((x - p['black']) / (p['white'] - p['black']), 0, 1.2)
    if p['gamma'] != 1:
        x = np.power(np.maximum(x, 0), p['gamma'])
    # яркость (Rec.709) и кривая только по ней — оттенки не уезжают
    Y = x[..., 0] * 0.0722 + x[..., 1] * 0.7152 + x[..., 2] * 0.2126
    Yc = _curve(np.clip(Y, 0, 1), p['contrast'])
    # микроконтраст: деталь относительно сильно размытой яркости (считаем в 1/4)
    h, w = Y.shape
    small = cv2.resize(Yc, (w // 4, h // 4), interpolation=cv2.INTER_AREA)
    low = cv2.resize(cv2.GaussianBlur(small, (0, 0), 9), (w, h), interpolation=cv2.INTER_LINEAR)
    mid = 4 * Yc * (1 - Yc)                     # не трогаем глубокие тени и пересветы
    Yc = Yc + (Yc - low) * p['clarity'] * mid
    ratio = (Yc + 1e-4) / (Y + 1e-4)
    x = x * ratio[..., None]
    # раздельное тонирование
    Yn = np.clip(Yc, 0, 1)[..., None]
    x += np.array(p['shadow_tint'], np.float32) * (1 - Yn) ** 2
    x += np.array(p['high_tint'], np.float32) * Yn ** 2
    # вибранс: сильнее поднимает приглушённые цвета, яркие не пережигает
    mx = x.max(2, keepdims=True)
    mn = x.min(2, keepdims=True)
    sat = (mx - mn) / (mx + 1e-4)
    Yl = (x[..., 0:1] * 0.0722 + x[..., 1:2] * 0.7152 + x[..., 2:3] * 0.2126)
    k = p['sat'] + p['vib'] * (1 - np.clip(sat * 1.6, 0, 1))
    x = Yl + (x - Yl) * k
    # резкость (unsharp mask)
    if p['sharpen']:
        bl = cv2.GaussianBlur(x, (0, 0), 1.3)
        x = x + (x - bl) * p['sharpen']
    x *= _vignette(h, w, p['vignette'])
    return np.clip(x, 0, 1)
