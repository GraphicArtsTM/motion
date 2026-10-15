"""Цветокоррекция съёмок с iPhone — из 10-битного HDR-исходника.

HLG (BT.2020) → линейный свет 203 нит → тонмаппинг Mobius → BT.709, 16 бит на канал
(ffmpeg), дальше грейд во float:

  баланс белого (в линейном свете) → локальное высветление лица/теней
  (билатеральная база, без ореолов) → мягкая S-кривая с плавным плечом →
  тонирование → вибранс → сглаживание кожи → свечение светов → резкость →
  лёгкая виньетка.

Результат — «пластины» 60 fps, которые читает edit.py:
    python3 grade.py <исходник.MOV> <look> <out.mp4> [--ss 1.0 --to 5.2]
"""
import argparse
import subprocess

import cv2
import numpy as np

TONEMAP = ("zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,"
           "tonemap=mobius:param=0.3:desat=0,zscale=t=bt709:m=bt709:r=pc,format=rgb48le")

LOOKS = {
    # селфи: светлое чистое лицо на белой стене, тёплая натуральная кожа
    'selfie': dict(wb=(1.03, 1.0, 0.985), exposure=1.03, shadows=0.40, black=0.085, contrast=0.30,
                   shoulder=0.9, vib=0.16, sat=1.0, skin_warm=0.012, skin_smooth=0.22,
                   shadow_tint=(0.010, 0.002, -0.004), high_tint=(-0.006, 0.0, 0.004),
                   bloom=0.07, sharpen=0.28, vignette=0.10),
    # монитор: нейтральная стена вместо жёлтой, глубокий, но не «убитый» чёрный, свечение экрана
    'monitor': dict(wb=(1.10, 1.02, 0.92), exposure=0.98, shadows=0.25, black=0.02, contrast=0.30,
                    shoulder=0.9, vib=0.18, sat=1.0, skin_warm=0.0, skin_smooth=0.0,
                    shadow_tint=(0.012, 0.004, -0.004), high_tint=(-0.004, 0.0, 0.004),
                    bloom=0.10, sharpen=0.32, vignette=0.14),
}

_vig = {}


def _vignette(h, w, amt):
    key = (h, w, amt)
    if key not in _vig:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        r = ((xx - w / 2) / (w * 0.75)) ** 2 + ((yy - h * 0.45) / (h * 0.65)) ** 2
        _vig[key] = (1 - amt * np.clip(r, 0, 1) ** 2)[..., None]
    return _vig[key]


def _luma(x):
    return x[..., 0] * 0.0722 + x[..., 1] * 0.7152 + x[..., 2] * 0.2126


def _tone(y, black, contrast, shoulder):
    """Мягкая S-кривая: чёрная точка, контраст в средних, плавное плечо в светах."""
    y = np.clip((y - black) / (1 - black), 0, None)
    s = y * y * (3 - 2 * np.clip(y, 0, 1))
    y = y + (s - y) * contrast
    # плечо: всё, что выше shoulder, мягко сжимается к 1
    k = shoulder
    over = np.maximum(y - k, 0)
    y = np.where(y > k, k + (1 - k) * (1 - np.exp(-over / (1 - k))), y)
    return y


def grade(rgb, look):
    """rgb: float32 RGB 0..1 (BT.709 гамма). Возвращает float32 BGR 0..1.
    Кортежи wb/tint в LOOKS заданы в порядке B, G, R."""
    p = LOOKS[look]
    h, w = rgb.shape[:2]
    # 1) баланс белого и экспозиция в линейном свете
    lin = np.power(np.clip(rgb, 0, 1), 2.4) * np.array(p['wb'][::-1], np.float32) * p['exposure']
    x = np.power(np.clip(lin, 0, None), 1 / 2.4)
    # 2) локальное высветление теней: база — билатерально сглаженная яркость (без ореолов)
    Y = _luma(x[..., ::-1])
    ys = cv2.resize(Y, (w // 4, h // 4), interpolation=cv2.INTER_AREA)
    base = cv2.bilateralFilter(ys, 0, 0.12, 14)
    base = cv2.resize(base, (w, h), interpolation=cv2.INTER_LINEAR)
    # высветляем средние тени (лицо), но не глубокий чёрный (волосы, оправа)
    keep_black = np.clip((Y - 0.06) / 0.22, 0, 1) ** 1.5
    lift = 1 + p['shadows'] * np.clip(1 - base / 0.62, 0, 1) ** 1.6 * keep_black
    Y2 = Y * lift
    # 3) тональная кривая по яркости (оттенки не уезжают)
    Yt = _tone(Y2, p['black'], p['contrast'], p['shoulder'])
    x = x * ((Yt + 1e-4) / (Y + 1e-4))[..., None]
    # 4) тонирование
    Yn = np.clip(Yt, 0, 1)[..., None]
    x += np.array(p['shadow_tint'][::-1], np.float32) * (1 - Yn) ** 3
    x += np.array(p['high_tint'][::-1], np.float32) * Yn ** 3
    # 5) вибранс
    mx, mn = x.max(2, keepdims=True), x.min(2, keepdims=True)
    sat = (mx - mn) / (mx + 1e-4)
    Yl = _luma(x[..., ::-1])[..., None]
    x = Yl + (x - Yl) * (p['sat'] + p['vib'] * (1 - np.clip(sat * 1.8, 0, 1)))
    x = np.clip(x, 0, 1.2)
    bgr = np.ascontiguousarray(x[..., ::-1])
    # 6) кожа: маска по YCrCb, лёгкое сглаживание и тепло
    if p['skin_smooth'] or p['skin_warm']:
        ycc = cv2.cvtColor(np.clip(bgr, 0, 1), cv2.COLOR_BGR2YCrCb)
        cr, cb = ycc[..., 1], ycc[..., 2]
        m = np.clip((cr - 0.535) / 0.03, 0, 1) * np.clip((0.70 - cr) / 0.03, 0, 1) \
            * np.clip((cb - 0.36) / 0.03, 0, 1) * np.clip((0.515 - cb) / 0.03, 0, 1) \
            * np.clip((ycc[..., 0] - 0.18) / 0.1, 0, 1)
        m = cv2.GaussianBlur(m, (0, 0), 6)[..., None]
        if p['skin_smooth']:
            half = cv2.resize(bgr, (w // 2, h // 2), interpolation=cv2.INTER_AREA)
            sm = cv2.bilateralFilter(half, 0, 0.06, 6)
            sm = cv2.resize(sm, (w, h), interpolation=cv2.INTER_LINEAR)
            bgr = bgr + (sm - bgr) * m * p['skin_smooth']
        if p['skin_warm']:
            bgr = bgr + m * np.array([-p['skin_warm'], 0.0, p['skin_warm']], np.float32)
    # 7) свечение светов (бережная «халация»)
    if p['bloom']:
        hi = np.clip((bgr - 0.78) / 0.22, 0, 1)
        q = cv2.resize(hi, (w // 8, h // 8), interpolation=cv2.INTER_AREA)
        q = cv2.GaussianBlur(q, (0, 0), 6)
        glow = cv2.resize(q, (w, h), interpolation=cv2.INTER_LINEAR)
        bgr = 1 - (1 - bgr) * (1 - glow * p['bloom'])
    # 8) резкость только по яркости, мелкий радиус
    if p['sharpen']:
        Yb = _luma(bgr[..., ::-1].copy())
        det = Yb - cv2.GaussianBlur(Yb, (0, 0), 0.9)
        bgr = bgr + (det * p['sharpen'])[..., None]
    bgr *= _vignette(h, w, p['vignette'])
    return np.clip(bgr, 0, 1)


def read_frames(src, ss=None, to=None, w=1080, h=1920):
    cmd = ['ffmpeg', '-loglevel', 'error']
    if ss is not None:
        cmd += ['-ss', str(ss)]
    cmd += ['-i', src]
    if to is not None:
        cmd += ['-t', str(to - (ss or 0))]
    cmd += ['-vf', TONEMAP.replace(',format=rgb48le', '') + ',fps=60,format=rgb48le', '-f', 'rawvideo', '-']
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    n = w * h * 3 * 2
    while True:
        buf = p.stdout.read(n)
        if len(buf) < n:
            break
        yield np.frombuffer(buf, '<u2').reshape(h, w, 3).astype(np.float32) / 65535.0
    p.wait()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('look')
    ap.add_argument('out')
    ap.add_argument('--ss', type=float)
    ap.add_argument('--to', type=float)
    a = ap.parse_args()
    enc = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'bgr48le',
                            '-s', '1080x1920', '-r', '60', '-i', '-', '-c:v', 'libx264', '-preset', 'medium',
                            '-crf', '8', '-g', '30', '-pix_fmt', 'yuv420p', '-color_primaries', 'bt709',
                            '-color_trc', 'bt709', '-colorspace', 'bt709', a.out], stdin=subprocess.PIPE)
    n = 0
    for fr in read_frames(a.src, a.ss, a.to):
        out = grade(fr, a.look)
        enc.stdin.write((out * 65535 + 0.5).astype('<u2').tobytes())
        n += 1
    enc.stdin.close()
    enc.wait()
    print(a.out, n, 'кадров')


if __name__ == '__main__':
    main()
