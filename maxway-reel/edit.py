"""Монтаж рилса «MAXWAY, посмотрите, что я сделал!» — 1080×1920, 60 fps.

Кадры рендерятся детерминированно функцией render(T) и пишутся в ffmpeg.
Источники — SDR-промежуточники (см. build.sh): селфи, монитор, ролик Maxway.

    python3 edit.py --src <папка с sdr> --track <track.json> --out frames.mp4 [--workers 4]
    python3 edit.py ... --stills 1.2,5.6,9.5      # стоп-кадры для проверки
"""
import argparse
import json
import math
import os
import subprocess
import sys
from multiprocessing import Process

import cv2
import numpy as np

import assets as A
from timeline import (BEAT, CUTS, DUR, FPS, H, K3_OFF, T_BREAK0, T_BREAK1, T_CARD0, T_CARD1,
                      T_DROP, T_DVA, T_LAND, T_WHIP, T_ZOOM0, W)

cv2.setNumThreads(1)

# ---------------------------------------------------------------- утилиты


def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def lerp(a, b, t):
    return a + (b - a) * t


def ease_out(t, p=3):
    t = clamp(t)
    return 1 - (1 - t) ** p


def ease_in(t, p=3):
    return clamp(t) ** p


def ease_io(t):
    t = clamp(t)
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def back_out(t, s=1.9):
    t = clamp(t) - 1
    return 1 + (s + 1) * t ** 3 + s * t ** 2


def elastic_out(t):
    t = clamp(t)
    if t in (0, 1):
        return t
    return 2 ** (-10 * t) * math.sin((t * 10 - 0.75) * 2 * math.pi / 3) + 1


def smooth(a, b, x):
    t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)


def hit(T, times, decay=8.0):
    """Сумма затухающих импульсов от событий times (0 до события)."""
    v = 0.0
    for t0 in times:
        d = T - t0
        if 0 <= d < 2.0:
            v += math.exp(-d * decay)
    return v


def comp(dst, src):
    """dst (BGR float) <- src (BGRA премультиплированный), in-place."""
    a = src[..., 3:4]
    dst *= 1 - a
    dst += src[..., :3]
    return dst


def put(frame, sp, cx, cy, scale=1.0, rot=0.0, alpha=1.0, blur=0.0, anchor=None):
    """Кладёт спрайт с поворотом/масштабом в точку (cx, cy) кадра."""
    if alpha <= 0.003 or scale <= 0.01:
        return
    h, w = sp.shape[:2]
    ax, ay = anchor if anchor is not None else (w / 2, h / 2)
    M = cv2.getRotationMatrix2D((ax, ay), rot, scale)
    M[0, 2] += cx - ax
    M[1, 2] += cy - ay
    corners = np.array([[0, 0, 1], [w, 0, 1], [w, h, 1], [0, h, 1]], np.float64) @ M.T
    pad = int(blur * 3) + 2
    x0 = int(max(0, math.floor(corners[:, 0].min()) - pad))
    y0 = int(max(0, math.floor(corners[:, 1].min()) - pad))
    x1 = int(min(frame.shape[1], math.ceil(corners[:, 0].max()) + pad))
    y1 = int(min(frame.shape[0], math.ceil(corners[:, 1].max()) + pad))
    if x1 <= x0 or y1 <= y0:
        return
    M2 = M.copy()
    M2[0, 2] -= x0
    M2[1, 2] -= y0
    out = cv2.warpAffine(sp, M2, (x1 - x0, y1 - y0), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    if blur > 0.3:
        out = cv2.GaussianBlur(out, (0, 0), blur)
    if alpha < 1:
        out *= alpha
    comp(frame[y0:y1, x0:x1], out)


def hblur(img, L):
    """Горизонтальный смаз движения длиной L пикселей."""
    L = int(L)
    if L < 3:
        return img
    k = np.ones((1, L), np.float32) / L
    return cv2.filter2D(img, -1, k, borderType=cv2.BORDER_REFLECT)


def chroma(img, amt):
    """Хроматическая аберрация: R и B разъезжаются от центра."""
    if amt < 0.4:
        return img
    out = img.copy()
    for ch, k in ((2, 1.0), (0, -1.0)):
        s = 1 + k * amt / 900
        M = cv2.getRotationMatrix2D((W / 2, H / 2), 0, s)
        out[..., ch] = cv2.warpAffine(img[..., ch], M, (W, H), borderMode=cv2.BORDER_REFLECT)
    return out


def affine(img, scale=1.0, rot=0.0, dx=0.0, dy=0.0, cx=W / 2, cy=H / 2, border=cv2.BORDER_REFLECT):
    if abs(scale - 1) < 1e-4 and abs(rot) < 1e-4 and abs(dx) < 0.05 and abs(dy) < 0.05:
        return img
    M = cv2.getRotationMatrix2D((cx, cy), rot, scale)
    M[0, 2] += dx
    M[1, 2] += dy
    return cv2.warpAffine(img, M, (W, H), flags=cv2.INTER_LINEAR, borderMode=border)


def shake(T, amp, seed=0.0):
    x = math.sin(T * 61 + seed) * 0.6 + math.sin(T * 97 + 2.1 + seed) * 0.4
    y = math.sin(T * 73 + 1.3 + seed) * 0.6 + math.sin(T * 41 + 0.4 + seed) * 0.4
    return x * amp, y * amp


def rot3(rx, ry, rz):
    rx, ry, rz = map(math.radians, (rx, ry, rz))
    Rx = np.array([[1, 0, 0], [0, math.cos(rx), -math.sin(rx)], [0, math.sin(rx), math.cos(rx)]])
    Ry = np.array([[math.cos(ry), 0, math.sin(ry)], [0, 1, 0], [-math.sin(ry), 0, math.cos(ry)]])
    Rz = np.array([[math.cos(rz), -math.sin(rz), 0], [math.sin(rz), math.cos(rz), 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def project_plane(w, h, cx, cy, rx, ry, rz, f=2600.0):
    """Углы прямоугольника w×h, повёрнутого в 3D, в экранных координатах."""
    R = rot3(rx, ry, rz)
    pts = np.array([[-w / 2, -h / 2, 0], [w / 2, -h / 2, 0], [w / 2, h / 2, 0], [-w / 2, h / 2, 0]]) @ R.T
    z = f / (f + pts[:, 2])
    return np.stack([cx + pts[:, 0] * z, cy + pts[:, 1] * z], 1).astype(np.float32)


# ---------------------------------------------------------------- источники


class Clip:
    """Последовательное чтение кадров с кешем и подмешиванием соседних кадров."""

    def __init__(self, path, offset=0.0):
        self.path = path
        self.offset = offset   # время источника, с которого начинается файл
        self.cap = None
        self.pos = -1
        self.cache = {}
        c = cv2.VideoCapture(path)
        self.n = int(c.get(cv2.CAP_PROP_FRAME_COUNT))
        self.fps = c.get(cv2.CAP_PROP_FPS)
        c.release()

    def _read(self, i):
        i = int(min(max(i, 0), self.n - 1))
        if i in self.cache:
            return self.cache[i]
        if self.cap is None or i < self.pos or i > self.pos + 90:
            if self.cap is not None:
                self.cap.release()
            self.cap = cv2.VideoCapture(self.path)
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, i)
            self.pos = i - 1
        last = None
        while self.pos < i:
            ok, fr = self.cap.read()
            if not ok:
                break
            self.pos += 1
            if self.pos >= i - 3:
                last = fr.astype(np.float32) / 255.0
                self.cache[self.pos] = last
        for k in [k for k in self.cache if k < i - 4]:
            del self.cache[k]
        if i in self.cache:
            return self.cache[i]
        return last if last is not None else self.cache[max(self.cache)]

    def at(self, s):
        """Кадр на время s (секунды источника), с подмешиванием между кадрами."""
        x = (s - self.offset) * self.fps
        i0 = int(math.floor(x))
        k = x - i0
        a = self._read(i0)
        if k < 0.08 or i0 + 1 >= self.n:
            return a.copy()
        if k > 0.92:
            return self._read(i0 + 1).copy()
        return cv2.addWeighted(a, 1 - k, self._read(i0 + 1), k, 0)


# ---------------------------------------------------------------- цвет


_yy, _xx = np.mgrid[0:H, 0:W].astype(np.float32)
VIGNETTE = (1 - 0.32 * np.clip(((_xx - W / 2) / (W * 0.75)) ** 2 + ((_yy - H * 0.45) / (H * 0.62)) ** 2, 0, 1) ** 1.4)[..., None]


# ---------------------------------------------------------------- заголовок

HW, HH = 1080, 380


TITLES = {
    'posmotreli': 'ВЫ ПОСМОТРЕЛИ ЭТО?',
    'posmotrite': 'ПОСМОТРИТЕ, ЧТО Я СДЕЛАЛ!',
    'reklama': 'Я СДЕЛАЛ ВАМ РЕКЛАМУ',
}


class Header:
    """3D-заголовок «MAXWAY, / <фраза>» с побуквенной анимацией."""

    def __init__(self, title='reklama', layout='full'):
        self.layout = layout
        f1 = A.font('Unbounded-900', 128)
        word = 'MAXWAY,'
        total = f1.getlength(word)
        self.letters = []
        x0 = (HW - total) / 2 - 6
        bb = f1.getbbox(word)
        y0 = 34 - bb[1]
        for i, ch in enumerate(word):
            sp, face, (ox, oy) = A.extruded_text(
                ch, f1, A.WHITE, (236, 230, 255), A.PURPLE, A.PURPLE_DD, depth=18, ddx=0.5, ddy=1.0, pad=50)
            adv = f1.getlength(word[:i])
            lb = f1.getbbox(ch)
            # центр буквы на холсте заголовка
            cx = x0 + adv + (lb[0] + lb[2]) / 2
            cy = y0 + (bb[1] + bb[3]) / 2
            ax = ox + (lb[0] + lb[2]) / 2
            ay = oy + (bb[1] + bb[3]) / 2
            self.letters.append((sp, (cx, cy), (ax, ay)))
        # маска лица всего слова в покое — для блика
        _, face_all, (ox, oy) = A.extruded_text(word, f1, A.WHITE, A.WHITE, A.PURPLE, A.PURPLE_DD, depth=18, pad=50)
        fm = np.zeros((HH, HW), np.float32)
        px, py = int(round(x0 - ox)), int(round(y0 - oy))
        hh, ww = face_all.shape
        sx0, sy0 = max(0, -px), max(0, -py)
        dx0, dy0 = max(0, px), max(0, py)
        cw, ch_ = min(ww - sx0, HW - dx0), min(hh - sy0, HH - dy0)
        fm[dy0:dy0 + ch_, dx0:dx0 + cw] = face_all[sy0:sy0 + ch_, sx0:sx0 + cw]
        self.face = fm
        text = TITLES.get(title, title)
        size = min(66, int(58 * 880 / A.font('Rubik-900', 58).getlength(text)))
        f2 = A.font('Rubik-900', size)
        self.pill, self.words, box = A.pill_text_layers(text, f2, depth=10, padx=38, pady=20)
        self.pill_c = (HW / 2, 262)
        ph, pw = self.pill.shape[:2]
        self.pill_anchor = (box[0] + box[2] / 2, box[1] + box[3] / 2)
        self._yy, self._xx = np.mgrid[0:HH, 0:HW].astype(np.float32)

    def canvas(self, T, t0):
        cv = np.zeros((HH, HW, 4), np.float32)
        c3 = cv  # пишем прямо в 4 канала
        # плашка
        tp = (T - (t0 + 0.32)) / 0.45
        if tp > 0:
            sx = elastic_out(tp)
            sy = back_out(tp * 1.3)
            sp = self.pill
            h, w = sp.shape[:2]
            ax, ay = self.pill_anchor
            M = np.array([[sx * math.cos(math.radians(2.5)), sx * math.sin(math.radians(2.5)), 0],
                          [-sy * math.sin(math.radians(2.5)), sy * math.cos(math.radians(2.5)), 0]], np.float64)
            M[:, 2] = np.array(self.pill_c) - M[:, :2] @ np.array([ax, ay])
            out = cv2.warpAffine(sp, M, (HW, HH))
            comp_rgba(c3, out)
            for j, (wl, (wx, wy)) in enumerate(self.words):
                tw = (T - (t0 + 0.5 + j * 0.125)) / 0.28
                if tw <= 0:
                    continue
                s = lerp(1.7, 1.0, ease_out(tw, 4))
                a = clamp(tw * 2.5)
                # слово масштабируется вокруг своего центра, затем вместе с плашкой
                Mw = cv2.getRotationMatrix2D((wx, wy), 0, s)
                Mf = np.vstack([M, [0, 0, 1]]) @ np.vstack([Mw, [0, 0, 1]])
                out = cv2.warpAffine(wl, Mf[:2], (HW, HH)) * a
                comp_rgba(c3, out)
        # буквы
        for i, (sp, (cx, cy), (ax, ay)) in enumerate(self.letters):
            tl = (T - (t0 - 0.14 + i * 0.05)) / 0.42
            if tl <= 0:
                continue
            s = lerp(0.15, 1.0, back_out(tl, 2.2))
            dy = -(1 - ease_out(tl, 3)) * 160
            rot = (1 - ease_out(tl, 3)) * (28 if i % 2 else -28)
            a = clamp(tl * 3)
            M = cv2.getRotationMatrix2D((ax, ay), rot, s)
            M[0, 2] += cx - ax
            M[1, 2] += cy - ay + dy
            out = cv2.warpAffine(sp, M, (HW, HH))
            if a < 1:
                out *= a
            comp_rgba(c3, out)
        # блик по лицу букв
        for ts in (1.0, 4.0, 9.9, 15.0, 21.0, 25.0, 30.0, 33.0):
            p = (T - ts) / 0.55
            if 0 < p < 1 and T > t0 + 0.8:
                pos = lerp(-200, HW + 300, ease_io(p))
                band = np.exp(-(((self._xx + self._yy * 0.6) - pos) / 46) ** 2) * 0.85
                add = band * self.face
                c3[..., :3] += add[..., None] * (1 - c3[..., :3])
        return c3

    def layer(self, T):
        """Возвращает премультиплированный BGRA-слой во весь кадр (или None)."""
        if T < T_WHIP:
            t0, S, top, alpha = 0.0, 0.92, 248, 1.0
        elif T < T_ZOOM0:
            k = ease_io((T - T_WHIP) / 0.35)
            t0, S, top, alpha = 0.0, lerp(0.92, 0.8, k), lerp(248, 258, k), 1.0
        elif T < T_LAND:
            k = ease_in((T - T_ZOOM0) / 0.4, 2)
            t0, S, top, alpha = 0.0, 0.8 * (1 + 1.1 * k), 258 - 200 * k, 1 - k
        elif self.layout == 'full' or T < T_CARD0 + 0.2:
            return None
        else:
            t0, S, top, alpha = T_CARD0 + 0.3, 0.86, 176, 1.0
        if alpha <= 0.01:
            return None
        # пульс на сильные доли
        beats = [b * BEAT for b in range(int(T / BEAT) - 3, int(T / BEAT) + 1)] if T > T_DROP else [1.0, 1.5, 2.0, 3.0]
        S *= 1 + 0.03 * hit(T, beats, 10)
        cvs = self.canvas(T, t0)
        rx = 6 * math.sin(2 * math.pi * T / 3.1 + 0.7)
        ry = 9 * math.sin(2 * math.pi * T / 4.3)
        rz = 1.2 * math.sin(2 * math.pi * T / 5.7)
        dst = project_plane(HW * S, HH * S, W / 2, top + HH * S / 2, rx, ry, rz, f=1900)
        src = np.float32([[0, 0], [HW, 0], [HW, HH], [0, HH]])
        Hm = cv2.getPerspectiveTransform(src, dst)
        out = cv2.warpPerspective(cvs, Hm, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
        if alpha < 1:
            out *= alpha
            if T > T_ZOOM0:
                out = cv2.GaussianBlur(out, (0, 0), 1 + 10 * (1 - alpha))
        return out


def comp_rgba(dst, src):
    a = src[..., 3:4]
    dst *= 1 - a
    dst += src


# ---------------------------------------------------------------- монтаж


class Edit:
    def __init__(self, src, track, title='reklama', layout='full'):
        self.layout = layout
        # пластины уже с цветокоррекцией из 10-битного исходника (grade.py)
        self.c1 = Clip(os.path.join(src, 'IMG_6290_graded.mp4'), offset=1.6)
        self.c2 = Clip(os.path.join(src, 'IMG_6298_graded.mp4'))
        self.k3 = Clip(os.path.join(src, 'k3.mp4'))
        self.header = Header(title, layout)
        tr = json.load(open(track))
        q = np.array([r['quad'] if r['quad'] is not None else [[np.nan] * 2] * 4 for r in tr], np.float64)
        # заполняем пропуски и сглаживаем трек (окно 7 кадров)
        for c in range(4):
            for d in range(2):
                v = q[:, c, d]
                ok = ~np.isnan(v)
                v[~ok] = np.interp(np.flatnonzero(~ok), np.flatnonzero(ok), v[ok])
                k = np.ones(7) / 7
                vp = np.pad(v, 3, mode='edge')
                q[:, c, d] = np.convolve(vp, k, 'valid')
        self.quads = q
        # спрайты
        k3_end = self.k3.at(27.0)
        pair, right = A.key_sandwiches((k3_end * 255).astype(np.uint8))
        f11 = A.font('Unbounded-900', 92)
        p11, _, _ = A.pill_text_layers('1+1', f11, depth=14, padx=46, pady=26)
        self.sprites = {
            'pair': A.resize_sprite(pair, 430),
            'sand': A.resize_sprite(right, 330),
            'p11': A.resize_sprite(p11, 270),
            'spark_w': A.sparkle(90, A.WHITE),
            'spark_y': A.sparkle(110, A.YELLOW),
        }
        lab_font = A.font('Rubik-700', 34)
        lab, lw, _ = A.pill_text_layers('сделано в After Effects', lab_font, fill=(24, 14, 46), edge=(10, 6, 22),
                                        ink=A.WHITE, depth=6, padx=30, pady=16)
        for wl, _ in lw:
            comp_rgba(lab, wl)
        self.label = lab
        rm = np.zeros((H, W), np.float32)
        cv2.rectangle(rm, (0, 0), (W, H), 1.0, -1)
        r = 64
        rm[:r, :r] = 0
        rm[:r, -r:] = 0
        rm[-r:, :r] = 0
        rm[-r:, -r:] = 0
        for (x, y) in ((r, r), (W - r - 1, r), (r, H - r - 1), (W - r - 1, H - r - 1)):
            cv2.circle(rm, (x, y), r, 1.0, -1, lineType=cv2.LINE_AA)
        self.round_mask = rm
        # элементы вокруг карточки: (спрайт, x, y, масштаб, поворот, слой, размытие, задержка, откуда)
        self.elements = [
            ('sand', 95, 700, 1.00, -14, 'back', 1.5, 0.00, (-1, 0)),
            ('p11', 1000, 600, 0.85, 12, 'back', 1.0, 0.08, (1, -0.3)),
            ('pair', 960, 1570, 1.00, -8, 'back', 2.0, 0.14, (1, 0.5)),
            ('spark_y', 70, 1240, 0.9, 0, 'back', 0.0, 0.20, (-1, 0)),
            ('spark_w', 1030, 980, 0.7, 0, 'back', 0.0, 0.26, (1, 0)),
            ('p11', 90, 1760, 0.65, -16, 'back', 2.5, 0.30, (-1, 1)),
            ('sand', 1010, 1210, 0.80, 18, 'front', 5.5, 0.18, (1, 0)),
            ('spark_y', 150, 520, 0.55, 0, 'front', 0.0, 0.34, (-1, -1)),
            ('spark_w', 975, 500, 0.45, 0, 'front', 0.0, 0.40, (1, -1)),
        ]

    # --- части ---------------------------------------------------------

    def selfie(self, T):
        s = 1.95 + T
        fr = self.c1.at(s)
        z = 1.03 + 0.012 * T
        if T >= 1.95:
            z += 0.07 * ease_out((T - 1.95) / 0.16, 4) - 0.025 * ease_io((T - 2.1) / 0.6)
        dx = 0.0
        if T > 2.8:
            p = (T - 2.8) / (T_WHIP - 2.8)
            dx = -ease_in(p, 2) * 420
            z += 0.06 * ease_in(p, 2)
        fr = affine(fr, z, 0, dx, 0, cx=540, cy=760)
        if T > 2.8:
            fr = hblur(fr, 6 + 190 * ease_in((T - 2.8) / 0.2, 2))
        return fr

    def c2_time(self, T):
        knots = [(3.0, 1.30), (3.3, 1.80), (5.0, 3.62), (5.5, 4.12), (6.0, 4.55)]
        for (ta, sa), (tb, sb) in zip(knots, knots[1:]):
            if T <= tb:
                return lerp(sa, sb, (T - ta) / (tb - ta))
        return knots[-1][1]

    def quad_at(self, s):
        x = s * 60
        i0 = int(clamp(math.floor(x), 0, len(self.quads) - 2))
        k = clamp(x - i0)
        return (self.quads[i0] * (1 - k) + self.quads[i0 + 1] * k).astype(np.float32)

    def monitor_raw(self, T):
        """Кадр монитора с влётом в окно композиции (без размытия движения)."""
        s = self.c2_time(T)
        fr = self.c2.at(s)
        q = self.quad_at(s)
        full = np.float32([[0, 0], [W, 0], [W, H], [0, H]])
        e = ease_in((T - T_ZOOM0) / (T_LAND - T_ZOOM0), 3) if T > T_ZOOM0 else 0.0
        # лёгкий наезд-«вдох» перед рывком
        pre = 0.04 * ease_io((T - 4.4) / 0.9) if T < T_ZOOM0 + 0.1 else 0.04
        c = q.mean(0)
        qz = c + (q - c) * 1.0
        d = q + (full - q) * e
        if e < 1:
            Mp = cv2.getRotationMatrix2D((float(c[0]), float(c[1])), 0, 1 + pre * (1 - e))
            d = (np.hstack([d, np.ones((4, 1), np.float32)]) @ Mp.T).astype(np.float32)
        G = cv2.getPerspectiveTransform(qz, d)
        out = cv2.warpPerspective(fr, G, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
        # подмена окна чистым роликом Maxway
        a = smooth(T_ZOOM0 + 0.05, T_ZOOM0 + 0.5, T)
        if a > 0:
            k3 = self.k3.at(max(0.0, T - K3_OFF))
            Hk = cv2.getPerspectiveTransform(full, d)
            kw = cv2.warpPerspective(k3, Hk, (W, H), flags=cv2.INTER_LINEAR)
            m = cv2.warpPerspective(np.ones((H, W), np.float32), Hk, (W, H), flags=cv2.INTER_LINEAR)[..., None] * a
            out = out * (1 - m) + kw * m
        return out, d, e

    def monitor(self, T):
        if T > T_ZOOM0 + 0.3:
            # честное размытие движения: среднее нескольких под-кадров
            n = 6
            acc = None
            dt = 1 / FPS * 0.6
            for k in range(n):
                f, d, e = self.monitor_raw(T - dt * k / (n - 1))
                acc = f if acc is None else acc + f
            out = acc / n
            _, d, e = self.monitor_raw(T)
        else:
            out, d, e = self.monitor_raw(T)
        # вход после вип-пана
        if T < T_WHIP + 0.28:
            p = (T - T_WHIP) / 0.28
            out = affine(out, 1.06 - 0.06 * ease_out(p), 0, 420 * (1 - ease_out(p, 2)), 0)
            out = hblur(out, 190 * (1 - ease_out(p, 2)) ** 2 + 2)
        # HUD-уголки вокруг окна композиции
        hud = smooth(3.45, 3.7, T) * (1 - smooth(T_ZOOM0, T_ZOOM0 + 0.25, T))
        if hud > 0.01:
            self.draw_brackets(out, d, hud, T)
        lab = smooth(3.7, 3.95, T) * (1 - smooth(T_ZOOM0 - 0.05, T_ZOOM0 + 0.15, T))
        if lab > 0.01:
            bl = d[3]
            sp = self.label
            put(out, sp, float(bl[0]) + sp.shape[1] / 2 - 36, float(bl[1]) + 70, back_out(lab, 2.5) * 0.95, 2, lab)
        return out

    def draw_brackets(self, img, d, a, T):
        c = d.mean(0)
        L = 70
        col = tuple(float(v) for v in (31 / 255, 210 / 255, 255 / 255))
        grow = back_out((T - 3.45) / 0.35, 2.0)
        pts = c + (d - c) * (1.0 + 0.06 * (1 - clamp(grow)) + 0.025)
        ov = img.copy()
        for i in range(4):
            p = pts[i]
            for j in (i - 1, (i + 1) % 4):
                v = pts[j] - p
                v = v / (np.linalg.norm(v) + 1e-6) * L * clamp(grow)
                cv2.line(ov, (int(p[0] * 16), int(p[1] * 16)), (int((p[0] + v[0]) * 16), int((p[1] + v[1]) * 16)),
                         col, 8, cv2.LINE_AA, 4)
        cv2.addWeighted(ov, a, img, 1 - a, 0, img)

    def fullscreen(self, T):
        fr = self.k3.at(min(T - K3_OFF, 29.99))
        hits = [(T_LAND, 1.0), (T_DVA, 0.55), (T_DROP, 1.35)]
        e = sum(w * math.exp(-(T - t0) * 9) for t0, w in hits if T >= t0)
        sx, sy = shake(T, 26 * e)
        z = 1.0 + 0.07 * e
        rot = 1.6 * e * math.sin(T * 40)
        fr = affine(fr, z, rot, sx, sy)
        fr = chroma(fr, 22 * e)
        # вспышки
        fl = 0.8 * hit(T, [T_LAND], 14) + 0.5 * hit(T, [T_DROP], 12) + 0.25 * hit(T, [T_DVA], 16)
        if fl > 0.01:
            fr = fr + (1 - fr) * min(1.0, fl)
        # ударная волна на дропе
        p = (T - T_DROP) / 0.65
        if 0 <= p < 1:
            ring = np.zeros((H // 2, W // 2), np.float32)
            r = int((60 + 1300 * ease_out(p, 3)) / 2)
            cv2.circle(ring, (W // 4, int(H * 0.27)), r, 1.0, max(1, int(26 * (1 - p))), cv2.LINE_AA)
            ring = cv2.GaussianBlur(ring, (0, 0), 3)
            ring = cv2.resize(ring, (W, H))[..., None] * (1 - p) * 0.8
            fr = fr + (1 - fr) * ring
        return fr

    def card(self, T):
        k3 = self.k3.at(min(T - K3_OFF, 29.99))
        p = ease_io((T - T_CARD0) / (T_CARD1 - T_CARD0))
        # фон: размытый и затемнённый сам ролик
        small = cv2.resize(k3, (54, 96), interpolation=cv2.INTER_AREA)
        small = cv2.GaussianBlur(small, (0, 0), 5)
        bg = cv2.resize(small, (W, H), interpolation=cv2.INTER_CUBIC)
        luma = bg.mean(2, keepdims=True)
        bg = (luma + (bg - luma) * 1.35) * 0.5
        bg = np.clip(bg, 0, 1) * VIGNETTE
        # параметры карточки
        sc_card = 0.735
        cy_card = 1172
        cuts = [c for c in CUTS if c <= T]
        punch = hit(T, CUTS, 7)
        kick_dir = (-1) ** len(cuts)
        beats = [b * BEAT for b in range(int(T / BEAT) - 2, int(T / BEAT) + 1)]
        breathe = 0.006 * hit(T, beats, 9) if not (T_BREAK0 <= T < T_BREAK1) else 0
        sc = sc_card * (1 + 0.035 * punch + breathe)
        rx = 3.2 * math.sin(2 * math.pi * T / 5.3 + 1) + 2.0 * punch
        ry = 5.5 * math.sin(2 * math.pi * T / 7.0) + 3.0 * punch * kick_dir
        rz = 0.7 * math.sin(2 * math.pi * T / 9.0) + 1.3 * punch * kick_dir
        cy = cy_card + 8 * math.sin(2 * math.pi * T / 3.7)
        sc = lerp(1.0, sc, p)
        cy = lerp(H / 2, cy, p)
        rx, ry, rz = rx * p, ry * p, rz * p
        dst = project_plane(W * sc, H * sc, W / 2, cy, rx, ry, rz)
        src = np.float32([[0, 0], [W, 0], [W, H], [0, H]])
        Hm = cv2.getPerspectiveTransform(src, dst)
        # тень
        sm = cv2.warpPerspective(self.round_mask[::4, ::4], cv2.getPerspectiveTransform(src / 4, ((dst + [0, 46]) / 4).astype(np.float32)),
                                 (W // 4, H // 4))
        sm = cv2.GaussianBlur(sm, (0, 0), 14)
        bg *= (1 - 0.7 * cv2.resize(sm, (W, H))[..., None] * p)
        # свет за карточкой
        glow = np.exp(-(((_xx - W / 2) / 520) ** 2 + ((_yy - cy) / 900) ** 2))[..., None]
        bg += glow * 0.10 * p * (1 + 1.5 * punch)
        # элементы позади
        self.draw_elements(bg, T, 'back')
        mask = cv2.warpPerspective(self.round_mask, Hm, (W, H), flags=cv2.INTER_LINEAR)
        cardimg = cv2.warpPerspective(k3, Hm, (W, H), flags=cv2.INTER_LINEAR)
        m = mask[..., None]
        out = bg * (1 - m) + cardimg * m
        # стеклянный кант и блик
        rim = np.clip(m - cv2.erode(m, np.ones((5, 5), np.uint8))[..., None], 0, 1)
        out += rim * 0.28
        for ts in (T_CARD1, 15.0, 21.0, 30.0, 33.0):
            q = (T - ts) / 0.7
            if 0 < q < 1:
                pos = lerp(-600, W + 1400, ease_io(q))
                band = np.exp(-(((_xx + _yy * 0.45) - pos) / 90) ** 2)[..., None] * 0.22
                out += band * m
        self.draw_elements(out, T, 'front')
        # при переходе — вспышка и смаз
        if T < T_CARD1 + 0.1:
            w = math.sin(math.pi * clamp((T - T_CARD0) / (T_CARD1 - T_CARD0)))
            out = chroma(out, 14 * w)
        return out

    def draw_elements(self, img, T, layer):
        t_in = T_CARD0 + 0.15
        for i, (name, x, y, s, r0, lay, blur, delay, (fx, fy)) in enumerate(self.elements):
            if lay != layer:
                continue
            q = (T - t_in - delay) / 0.55
            if q <= 0:
                continue
            k = back_out(q, 1.8)
            ph = i * 1.7
            bob = 16 * math.sin(2 * math.pi * T / (3.2 + i * 0.37) + ph)
            sway = 9 * math.sin(2 * math.pi * T / (4.1 + i * 0.29) + ph)
            beat = 0.04 * hit(T, [b * BEAT for b in range(int(T / BEAT) - 2, int(T / BEAT) + 1)], 9)
            pulse = 0.08 * hit(T, CUTS, 8)
            ox = fx * 520 * (1 - ease_out(q, 3))
            oy = fy * 520 * (1 - ease_out(q, 3))
            sc = s * k * (1 + beat + pulse)
            rot = r0 + sway + (1 - ease_out(q)) * 120 * (-1) ** i
            if name.startswith('spark'):
                sc *= 0.8 + 0.35 * abs(math.sin(2 * math.pi * T / 1.6 + ph))
                rot = (T * 40 + ph * 30) % 360
            put(img, self.sprites[name], x + ox, y + bob + oy, sc, rot, 1.0, blur)

    # --- кадр ------------------------------------------------------------

    def render(self, T):
        if T < T_WHIP:
            fr = self.selfie(T)
            # световой прорыв на вип-пане
            fl = smooth(2.86, T_WHIP, T)
            if fl > 0:
                leak = np.clip((_xx / W) * 1.4 - 0.2, 0, 1)[..., None] * np.array([0.85, 0.55, 1.0], np.float32)
                fr += leak * 0.3 * fl
        elif T < T_LAND:
            fr = self.monitor(T)
            fl = 1 - smooth(T_WHIP, T_WHIP + 0.18, T)
            if fl > 0:
                leak = np.clip((1 - _xx / W) * 1.4 - 0.2, 0, 1)[..., None] * np.array([0.85, 0.55, 1.0], np.float32)
                fr += leak * 0.3 * fl
            # нарастающая белая засветка к приземлению
            wf = smooth(T_LAND - 0.12, T_LAND, T)
            fr = fr + (1 - fr) * wf * 0.75
        elif T < T_CARD0 or self.layout == 'full':
            fr = self.fullscreen(T)
        else:
            fr = self.card(T)
        hl = self.header.layer(T)
        if hl is not None:
            comp(fr, hl)
        return np.clip(fr, 0, 1)


# ---------------------------------------------------------------- запуск


def worker(args, f0, f1, path):
    ed = Edit(args.src, args.track, args.title, args.layout)
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{W}x{H}',
           '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-preset', 'medium', '-crf', '12', '-pix_fmt', 'yuv420p',
           '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', path]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for f in range(f0, f1):
        T = f / FPS
        fr = ed.render(T)
        p.stdin.write((fr * 255 + 0.5).astype(np.uint8).tobytes())
        if (f - f0) % 60 == 0:
            print(f'[{os.getpid()}] {T:5.2f}s', flush=True)
    p.stdin.close()
    p.wait()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--track', required=True)
    ap.add_argument('--out', default='out/frames.mp4')
    ap.add_argument('--workers', type=int, default=4)
    ap.add_argument('--stills', default='')
    ap.add_argument('--range', default='')
    ap.add_argument('--title', default='reklama', help='posmotreli | posmotrite | reklama | свой текст')
    ap.add_argument('--layout', default='full', help='full — кадр 3 на весь экран, card — 3D-карточка')
    args = ap.parse_args()
    if args.stills:
        ed = Edit(args.src, args.track, args.title, args.layout)
        os.makedirs('out/stills', exist_ok=True)
        for s in args.stills.split(','):
            T = float(s)
            cv2.imwrite(f'out/stills/{T:05.2f}.jpg', (ed.render(T) * 255).astype(np.uint8), [cv2.IMWRITE_JPEG_QUALITY, 90])
        print('стоп-кадры в out/stills/')
        return
    n = int(round(DUR * FPS))
    a, b = 0, n
    if args.range:
        a, b = (int(round(float(x) * FPS)) for x in args.range.split(':'))
    tmp = args.out + '.parts'
    os.makedirs(tmp, exist_ok=True)
    k = args.workers
    bounds = [a + (b - a) * i // k for i in range(k + 1)]
    procs = []
    parts = []
    for i in range(k):
        path = os.path.join(tmp, f'part{i}.mp4')
        parts.append(path)
        pr = Process(target=worker, args=(args, bounds[i], bounds[i + 1], path))
        pr.start()
        procs.append(pr)
    for pr in procs:
        pr.join()
        if pr.exitcode != 0:
            sys.exit('рендер упал')
    lst = os.path.join(tmp, 'list.txt')
    with open(lst, 'w') as fh:
        for pth in parts:
            fh.write(f"file '{os.path.abspath(pth)}'\n")
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', args.out],
                   check=True)
    print('готово:', args.out)


if __name__ == '__main__':
    main()
