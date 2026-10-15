"""Саундтрек рилса Maxway: 35 с, 120 BPM, ля минор.

Синтезируется с нуля на numpy: хаус-бит (бочка, клэп, хэты), дойра, бас с
сайдчейном, суперсо-аккорды, щипковый «дутар» (Karplus–Strong), райзеры, удары.
Все акценты стоят на событиях монтажа (timeline.py) и сменах сцен ролика Maxway.

    python3 music.py out/music.wav
"""
import sys
import wave

import numpy as np

from timeline import BEAT, CUTS, DUR, T_BREAK0, T_BREAK1, T_DROP, T_DVA, T_LAND, T_WHIP, T_ZOOM0

SR = 44100
N = int((DUR + 3.0) * SR)
BUS = {k: [np.zeros(N), np.zeros(N)] for k in ('drums', 'bass', 'music', 'fx')}
SEND = [np.zeros(N), np.zeros(N)]
rs = np.random.default_rng(11)
KICKS = []


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def add(bus, sig, t0, gain=1.0, pan=0.0, rev=0.0):
    i = int(round(t0 * SR))
    if i >= N:
        return
    if i < 0:
        sig = sig[-i:]
        i = 0
    sig = sig[:N - i] * gain
    a = (pan + 1) * np.pi / 4
    gl, gr = np.cos(a), np.sin(a)
    b = BUS[bus]
    b[0][i:i + len(sig)] += sig * gl
    b[1][i:i + len(sig)] += sig * gr
    if rev:
        SEND[0][i:i + len(sig)] += sig * gl * rev
        SEND[1][i:i + len(sig)] += sig * gr * rev


def fft_filter(x, lo=None, hi=None, order=2):
    n = len(x)
    M = 1 << int(np.ceil(np.log2(max(n, 2) * 2)))
    X = np.fft.rfft(x, M)
    f = np.fft.rfftfreq(M, 1 / SR)
    Hh = np.ones_like(f)
    if hi:
        Hh /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        Hh /= np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(X * Hh, M)[:n]


def tv_filter(x, fc_at, kind='band', bw=0.6, block=2048):
    """Фильтр с меняющейся частотой среза (overlap-add)."""
    hop = block // 2
    win = np.hanning(block + 1)[:-1]
    out = np.zeros(len(x) + block)
    xp = np.concatenate([x, np.zeros(block)])
    f = np.fft.rfftfreq(block, 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    for s in range(0, len(x), hop):
        fc = fc_at((s + hop) / SR)
        if kind == 'band':
            Hh = np.exp(-0.5 * ((lf - np.log2(fc)) / bw) ** 2)
        else:  # lowpass
            Hh = 1 / np.sqrt(1 + (f / fc) ** 4)
        out[s:s + block] += np.fft.irfft(np.fft.rfft(xp[s:s + block] * win) * Hh, block)
    return out[:len(x)]


def noise(n):
    return rs.standard_normal(n)


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.1):
    t = tt(n)
    dur = n / SR
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    return e * np.clip((dur - t) / max(r, 1e-6), 0, 1)


# ---------- ударные ----------
def kick(amp=1.0, tail=0.42):
    n = int(tail * SR)
    t = tt(n)
    f = 48 + (190 - 48) * np.exp(-t * 32)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7.0)
    click = fft_filter(noise(n) * np.exp(-t * 900), lo=2500) * 0.4
    return np.tanh((body + click) * 1.7) * amp


def clap():
    n = int(0.38 * SR)
    t = tt(n)
    env = np.zeros(n)
    for k, d in enumerate((0.0, 0.010, 0.021, 0.030)):
        env += np.where(t >= d, np.exp(-(t - d) * (190 if k < 3 else 20)), 0)
    return fft_filter(noise(n), lo=900, hi=5200) * env * 0.9


def snare(amp=1.0):
    n = int(0.25 * SR)
    t = tt(n)
    tone = np.sin(2 * np.pi * 200 * t) * np.exp(-t * 30)
    nz = fft_filter(noise(n), lo=1500, hi=9000) * np.exp(-t * 22)
    return (tone * 0.5 + nz * 0.8) * amp


def hat(open_=False):
    n = int((0.3 if open_ else 0.05) * SR)
    t = tt(n)
    return fft_filter(noise(n), lo=7500, order=3) * np.exp(-t * (12 if open_ else 80))


def doira_dum():
    n = int(0.35 * SR)
    t = tt(n)
    f = 95 + 40 * np.exp(-t * 40)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11) + fft_filter(noise(n), hi=600) * np.exp(-t * 40) * 0.5


def doira_tak():
    n = int(0.12 * SR)
    t = tt(n)
    ring = np.sin(2 * np.pi * 420 * t) * np.exp(-t * 45) * 0.4
    return fft_filter(noise(n), lo=1800, hi=6000) * np.exp(-t * 60) + ring


def crash(len_=2.2):
    n = int(len_ * SR)
    t = tt(n)
    x = fft_filter(noise(n), lo=3500) * np.exp(-t * 2.2)
    sh = sum(np.sin(2 * np.pi * f * t + rs.random() * 6) for f in (3170, 4410, 5230, 6890)) * 0.05 * np.exp(-t * 3)
    return x + sh


def boom(len_=2.0):
    n = int(len_ * SR)
    t = tt(n)
    f = 30 + 70 * np.exp(-t * 6)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.7)
    body = fft_filter(noise(n), hi=400) * np.exp(-t * 5) * 0.7
    return np.tanh((sub + body) * 2.2)


def riser(len_, f0=300, f1=9000, amp=1.0):
    n = int(len_ * SR)
    t = tt(n)
    k = t / len_
    x = tv_filter(noise(n), lambda s: f0 * (f1 / f0) ** min(1, s / len_) ** 1.4, bw=0.5)
    tone_f = 200 + 1000 * k ** 2
    tone = np.sin(2 * np.pi * np.cumsum(tone_f) / SR + 3 * np.sin(2 * np.pi * 6 * t)) * 0.18
    return (x * 1.4 + tone) * k ** 2.2 * amp


def whoosh(len_=0.5, up=True):
    n = int(len_ * SR)
    t = tt(n)
    x = tv_filter(noise(n), lambda s: (350 * (14 ** (s / len_)) if up else 6000 * (0.08 ** (s / len_))), bw=0.7)
    return x * np.sin(np.pi * t / len_) ** 1.5


def blip(f=1320, len_=0.16):
    n = int(len_ * SR)
    t = tt(n)
    ff = f * (1 + 0.5 * np.exp(-t * 60))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR + 1.5 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 30)) * np.exp(-t * 26)


def click(f=3800):
    n = int(0.05 * SR)
    t = tt(n)
    return np.sin(2 * np.pi * f * t) * np.exp(-t * 260) + fft_filter(noise(n), lo=3000) * np.exp(-t * 400) * 0.6


def bell(f, len_=1.4):
    n = int(len_ * SR)
    t = tt(n)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.2 * np.exp(-t * 4)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 3.2) + 0.3 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 6)


def coin(f):
    n = int(0.3 * SR)
    t = tt(n)
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d) for r, a, d in ((1, 1, 14), (2.76, .5, 20), (5.4, .25, 30)))


def scratch(len_=0.35):
    """«Зачёркивание»: скрэтч вниз по частоте."""
    n = int(len_ * SR)
    t = tt(n)
    f = 1800 * np.exp(-t * 9) + 120
    saw = 2 * ((np.cumsum(f) / SR) % 1) - 1
    return fft_filter(saw + 0.4 * noise(n), lo=150, hi=5000) * np.sin(np.pi * t / len_) ** 0.6


# ---------- тональные ----------
def dutar(freq, len_=1.2, bright=0.6, decay=0.9965):
    n = int(len_ * SR)
    p_true = SR / freq - 0.5
    P = int(p_true)
    rate = P / p_true
    m = int(n * rate) + P + 2
    y = np.zeros(m)
    exc = noise(P)
    exc = bright * exc + (1 - bright) * np.convolve(exc, np.ones(4) / 4, 'same')
    y[:P] = exc
    i = P
    while i < m:
        e = min(i + P, m)
        a = y[i - P:e - P]
        b = y[i - P - 1:e - P - 1] if i - P - 1 >= 0 else np.concatenate([[0], y[0:e - P - 1]])
        y[i:e] = decay * 0.5 * (a + b)
        i = e
    out = np.interp(np.arange(n) * rate, np.arange(m), y)
    body = fft_filter(out, lo=180, hi=5600)
    t = tt(n)
    return body * np.minimum(1, (len_ - t) / 0.05)


def saw_add(freq, n, fc, voices=1, detune=0.0, maxh=None):
    t = tt(n)
    out = np.zeros(n)
    for v in range(voices):
        dv = (v - (voices - 1) / 2) * detune
        f = freq * 2 ** (dv / 1200)
        ph0 = rs.random() * 2 * np.pi
        K = int(min(maxh or 60, (SR / 2.2) / f))
        for k in range(1, K + 1):
            g = 1 / np.sqrt(1 + (k * f / fc) ** 4)
            if np.isscalar(g) and g < 0.003:
                break
            out += g / k * np.sin(2 * np.pi * k * f * t + ph0 * k)
    return out / max(1, voices) ** 0.6


def stab(notes, len_=0.4, fc=3200, gain=1.0):
    n = int(len_ * SR)
    x = sum(saw_add(mtof(m), n, fc, voices=3, detune=18, maxh=40) for m in notes)
    return x * adsr(n, 0.003, 0.12, 0.35, 0.08) * gain


# ---------- гармония ----------
CH = {'Am': [57, 60, 64], 'F': [53, 57, 60], 'C': [55, 60, 64], 'G': [55, 59, 62], 'E': [52, 56, 59]}
ROOT = {'Am': 45, 'F': 41, 'C': 48, 'G': 43, 'E': 40}
CHORDS = [(0, 1, 'Am'), (1, 3, 'Am'), (3, 5, 'F'), (5, 7, 'E'),
          (7, 9, 'Am'), (9, 11, 'F'), (11, 13, 'C'), (13, 15, 'G'),
          (15, 17, 'Am'), (17, 19, 'F'), (19, 21, 'C'), (21, 23, 'G'), (23, 25, 'E'),
          (25, 27, 'Am'), (27, 29, 'F'), (29, 30, 'E'),
          (30, 32, 'Am'), (32, 34, 'F'), (34, 36, 'Am')]
# мелодия-хук на дутаре (восьмые, None — пауза), по аккорду
MEL = {'Am': [76, None, 72, 76, 79, None, 76, 72], 'F': [77, None, 72, 77, 81, None, 77, 72],
       'C': [79, None, 76, 79, 84, None, 79, 76], 'G': [79, None, 74, 79, 83, None, 81, 79],
       'E': [80, None, 76, 80, 83, None, 80, 76]}

DRUMS_ON = lambda t: (T_DROP <= t < T_BREAK0) or (T_BREAK1 <= t < 34.5)


def chord_at(t):
    for a, b, c in CHORDS:
        if a <= t < b:
            return c
    return 'Am'


# ================= аранжировка =================

# --- 0–1 с: хук. Заголовок врезается ---
add('fx', boom(1.4), 0.0, 0.8)
add('fx', whoosh(0.35, False), 0.0, 0.45, rev=0.2)
add('drums', kick(1.0), 0.0, 0.9); KICKS.append(0.0)
add('music', stab([57, 64, 69, 72], 0.5, 2600), 0.0, 0.32, rev=0.4)
for i in range(7):   # буквы приземляются
    add('fx', click(2600 + 260 * i), 0.11 + 0.05 * i, 0.22, pan=-0.6 + 0.2 * i)
for j, m in enumerate((81, 84, 88, 93)):   # слова на плашке
    add('fx', blip(mtof(m) / 2, 0.14), 0.5 + 0.125 * j, 0.28, pan=-0.3 + 0.2 * j, rev=0.3)

# --- 1–3 с: селфи, приглушённый грув (как через стену) ---
intro = [np.zeros(N), np.zeros(N)]
for b in range(4):
    t0 = 1.0 + b * BEAT
    add('drums', kick(0.8), t0, 0.7); KICKS.append(t0)
for b in range(8):
    add('drums', hat(False), 1.0 + b * BEAT / 2 + BEAT / 2 * 0.5, 0.12, pan=0.3)
for i, m in enumerate([69, 72, 76, 72, 69, 72, 76, 79]):
    add('music', dutar(mtof(m), 0.7, 0.45), 1.0 + i * BEAT / 2, 0.28, pan=0.3 * (-1) ** i, rev=0.35)
for m in CH['Am']:
    n = int(2.4 * SR)
    add('music', saw_add(mtof(m), n, 700, voices=3, detune=14, maxh=20) * adsr(n, 0.2, 0.6, 0.8, 0.5), 1.0, 0.06, rev=0.4)
add('fx', bell(mtof(88), 1.2), 1.0, 0.12, pan=0.4, rev=0.6)   # блик на заголовке
# взгляд в камеру и «смотри туда» — панч
add('drums', kick(1.0), 2.0, 0.9); KICKS.append(2.0)
add('drums', clap(), 2.0, 0.6, rev=0.3)
add('fx', boom(0.8), 2.0, 0.4)
add('music', stab([57, 64, 69], 0.3, 2400), 2.0, 0.22, rev=0.3)
add('fx', whoosh(0.55, True), 2.45, 0.5, pan=-0.4, rev=0.15)
rc = crash(0.6)[::-1]
add('fx', rc, T_WHIP - len(rc) / SR, 0.35)
# вип-пан
add('fx', whoosh(0.45, False), T_WHIP - 0.05, 0.7, pan=0.5, rev=0.2)
add('fx', boom(0.9), T_WHIP, 0.45)

# --- 3–5 с: монитор, фильтр открывается ---
for b in range(4):
    t0 = 3.0 + b * BEAT
    add('drums', kick(0.95), t0, 0.85); KICKS.append(t0)
    add('drums', hat(True), t0 + BEAT / 2, 0.16, pan=0.3)
    if b % 2 == 1:
        add('drums', clap(), t0, 0.55, rev=0.25)
for i in range(8):
    tb = 3.0 + i * BEAT / 2
    m = ROOT['F'] + (12 if i % 2 else 0)
    n = int(0.22 * SR)
    x = saw_add(mtof(m), n, 500 + 200 * i, voices=2, detune=8, maxh=30) * adsr(n, 0.003, 0.1, 0.5, 0.04)
    add('bass', x, tb + BEAT / 4, 0.32)
for i, m in enumerate([77, 72, 77, 81, 77, 72, 77, 84]):
    add('music', dutar(mtof(m), 0.6, 0.55), 3.0 + i * BEAT / 2, 0.3, pan=0.35 * (-1) ** i, rev=0.35)
add('fx', blip(1480), 3.47, 0.3, pan=0.3, rev=0.3)    # HUD
add('fx', blip(1980), 3.55, 0.22, pan=-0.3, rev=0.3)
add('fx', click(3000), 3.75, 0.4)                     # плашка After Effects
add('fx', bell(mtof(88), 1.0), 4.0, 0.1, rev=0.6)

# --- 5–7 с: КУПИ / ОДИН / ПОЛУЧИ / ДВА + влёт в экран ---
for k, (t0, chord) in enumerate(((5.0, [52, 59, 64, 68]), (5.5, [52, 59, 64, 71]),
                                 (T_LAND, [57, 64, 69, 72]), (T_DVA, [57, 64, 69, 76]))):
    add('music', stab(chord, 0.42, 2600 + 900 * k), t0, 0.34 + 0.05 * k, rev=0.35)
    add('drums', kick(1.0), t0, 0.85); KICKS.append(t0)
add('drums', clap(), 5.5, 0.6, rev=0.3)
add('drums', clap(), T_DVA, 0.6, rev=0.3)
for k in range(28):   # раскатка малого, ускоряется
    tk = 5.0 + 1.75 * (k / 28) ** 0.85
    add('drums', snare(0.25 + 0.75 * k / 27), tk, 0.36, pan=0.12 * (-1) ** k)
add('fx', riser(1.95, 300, 12000), 4.95, 0.55, rev=0.2)
add('fx', whoosh(0.75, True), T_ZOOM0, 0.65, rev=0.2)
add('fx', boom(1.2), T_LAND, 0.75)
add('fx', crash(1.2), T_LAND, 0.35, rev=0.4)
rc = crash(0.5)[::-1]
add('fx', rc, T_DROP - len(rc) / SR, 0.55)

# --- основной грув с 7 с ---
t = 7.0
while t < 34.5 - 1e-6:
    tb = round(t, 4)
    if DRUMS_ON(tb):
        add('drums', kick(1.0), tb, 0.88); KICKS.append(tb)
        beat_in_bar = int(round((tb - 1.0) / BEAT)) % 4
        if beat_in_bar in (1, 3):
            add('drums', clap(), tb, 0.75, rev=0.22)
        add('drums', hat(True), tb + BEAT / 2, 0.3, pan=0.3)
        for s in range(4):
            if s != 2:
                add('drums', hat(False), tb + s * BEAT / 4, 0.2 + 0.08 * (s == 1), pan=-0.25)
        if beat_in_bar in (0, 2):
            add('drums', doira_dum(), tb + BEAT * 0.75, 0.3, pan=0.2)
        add('drums', doira_tak(), tb + BEAT * 0.25, 0.28, pan=-0.35)
        # бас «качелями»: офбит + шестнадцатая
        c = chord_at(tb)
        for h, g in ((0.5, 1.0), (0.75, 0.6)):
            m = ROOT[c] + (12 if h == 0.75 else 0)
            n = int(0.2 * SR)
            fc = 300 + 1800 * np.exp(-tt(n) * 16)
            x = saw_add(mtof(m), n, fc, voices=2, detune=8, maxh=40) * adsr(n, 0.003, 0.08, 0.6, 0.04)
            x += np.sin(2 * np.pi * mtof(m) * tt(n)) * adsr(n, 0.003, 0.2, 0.8, 0.04) * 0.9
            add('bass', x, tb + h * BEAT, 0.4 * g)
    t += BEAT

# аккорды и мелодия по сегментам
for a, b, c in CHORDS:
    if b <= T_DROP or a >= 35:
        continue
    a = max(a, T_DROP)
    ln = b - a
    for m in CH[c]:
        n = int((ln + 0.3) * SR)
        x = saw_add(mtof(m + 12), n, 2600, voices=3, detune=16, maxh=26) * adsr(n, 0.02, 0.5, 0.8, 0.3)
        add('music', x, a, 0.05, pan=rs.uniform(-0.6, 0.6), rev=0.4)
    if T_BREAK0 <= a < T_BREAK1:
        continue
    mel = MEL[c]
    steps = int(round(ln / (BEAT / 2)))
    for s in range(steps):
        m = mel[s % 8]
        ts = a + s * BEAT / 2
        if m is None or (T_BREAK0 <= ts < T_BREAK1) or ts >= 34.5:
            continue
        add('music', dutar(mtof(m), 0.55, 0.7, 0.9955), ts, 0.34, pan=0.25 * (-1) ** s, rev=0.35)
        add('music', dutar(mtof(m - 12), 0.45, 0.5, 0.994), ts + 0.01, 0.12, pan=-0.3, rev=0.2)

# --- события в кадре ---
add('fx', boom(2.0), T_DROP, 1.0)
add('fx', crash(2.4), T_DROP, 0.5, rev=0.5)
add('music', stab([57, 64, 69, 72, 76], 0.6, 4200), T_DROP, 0.32, rev=0.4)
add('fx', whoosh(0.5, False), 8.75, 0.55, pan=-0.3, rev=0.2)          # в карточку
for cut in CUTS:
    if cut in (T_BREAK0,):
        continue
    add('fx', crash(1.4), cut, 0.16, pan=rs.uniform(-0.4, 0.4), rev=0.3)
    add('fx', whoosh(0.3, True), cut - 0.3, 0.22, pan=rs.uniform(-0.5, 0.5))
# брейк «клаб-сэндвич?» — зачёркивание — KLABJON
add('music', stab([55, 62, 67], 0.35, 2200), T_BREAK0, 0.3, rev=0.5)
add('fx', bell(mtof(79), 0.9), T_BREAK0 + 0.25, 0.12, rev=0.6)
add('fx', scratch(0.38), T_BREAK0 + 0.5, 0.5, pan=0.2, rev=0.2)
add('fx', riser(0.5, 800, 10000), T_BREAK1 - 0.5, 0.4)
add('fx', boom(1.4), T_BREAK1, 0.8)
add('fx', crash(2.0), T_BREAK1, 0.4, rev=0.5)
# приложение: тапы и «+1 в подарок»
for tk in (16.6, 17.2):
    add('fx', click(3400), tk, 0.35, pan=0.2)
add('fx', blip(1760), 18.0, 0.3, rev=0.3)
add('fx', coin(2600), 18.05, 0.12, rev=0.3)
# корзина: конфетти, «0 сум», галочка
for i in range(10):
    add('fx', coin(2300 + 210 * (i % 5)), 19.7 + i * 0.06, 0.07, pan=-0.6 + i * 0.13, rev=0.35)
add('fx', boom(1.0), 21.0, 0.55)
for i, m in enumerate((81, 85, 88)):
    add('fx', bell(mtof(m), 1.0), 22.0 + i * 0.07, 0.12, pan=-0.3 + 0.3 * i, rev=0.5)
# «1» и «+1»
add('music', stab([45, 57, 64], 0.3, 2400), 23.5, 0.3, rev=0.3)
add('music', stab([47, 59, 68], 0.3, 3200), 24.0, 0.34, rev=0.3)
add('fx', blip(1320), 24.0, 0.3, rev=0.3)
for k in range(16):
    add('drums', snare(0.3 + 0.7 * k / 15), 24.0 + k / 16, 0.34, pan=0.1 * (-1) ** k)
add('fx', riser(2.0, 300, 11000), 23.0, 0.45, rev=0.2)
rc = crash(0.6)[::-1]
add('fx', rc, 25.0 - len(rc) / SR, 0.45)
add('fx', boom(1.8), 25.0, 0.9)
add('fx', crash(2.2), 25.0, 0.45, rev=0.5)
# карта «40 мин»: маршрут — тиканье
add('fx', whoosh(0.6, True), 27.0, 0.35, pan=-0.4)
for i in range(12):
    add('fx', click(2200 + 90 * i), 27.3 + i * 0.125, 0.14, pan=-0.5 + i * 0.08)
# логотип max way — финальный удар
add('fx', whoosh(0.5, True), 29.5, 0.45)
add('fx', riser(1.0, 500, 12000), 29.0, 0.4)
add('fx', boom(2.4), 30.0, 1.0)
add('fx', crash(2.8), 30.0, 0.5, rev=0.6)
add('music', stab([57, 64, 69, 72, 76], 0.7, 4500), 30.0, 0.34, rev=0.5)
add('fx', click(4200), 32.5, 0.5, rev=0.3)      # кнопка «Заказать в приложении»
add('fx', blip(1760), 32.55, 0.25, rev=0.3)
# финал
add('drums', kick(1.1), 34.5, 0.9); KICKS.append(34.5)
add('fx', boom(2.0), 34.5, 0.8)
add('music', stab([45, 57, 64, 69, 72, 76], 0.9, 3800), 34.5, 0.4, rev=0.6)
add('fx', crash(2.0), 34.5, 0.4, rev=0.6)

# ---------- сведение ----------
side = np.ones(N)
for k in KICKS:
    i = int(k * SR)
    m = min(N - i, int(0.4 * SR))
    seg = np.arange(m) / SR
    side[i:i + m] = np.minimum(side[i:i + m], 1 - 0.75 * np.exp(-seg / 0.09))
for ch in (0, 1):
    BUS['bass'][ch] *= side
    BUS['music'][ch] *= 0.5 + 0.5 * side

# интро 1–3 с «через стену»: фильтр, открывающийся к 5 с
def intro_lp(x):
    def fc(s):
        if s < 1.0:
            return 18000
        if s < T_WHIP:
            return 900
        return 900 * (16000 / 900) ** min(1, (s - T_WHIP) / 2.0)
    head = int(7.0 * SR)
    y = x.copy()
    y[:head] = tv_filter(x[:head], fc, kind='low')
    return y


for bus in ('drums', 'bass', 'music'):
    for ch in (0, 1):
        BUS[bus][ch] = intro_lp(BUS[bus][ch])


def reverb(xl, xr, length=2.2, damp=5500):
    n = int(length * SR)
    tr = tt(n)
    out = []
    for x, seed in ((xl, 1), (xr, 2)):
        g = np.random.default_rng(seed)
        ir = g.standard_normal(n) * np.exp(-tr * 6.9 / length)
        ir = fft_filter(ir, lo=250, hi=damp)
        ir[:int(0.012 * SR)] = 0
        M = 1 << int(np.ceil(np.log2(len(x) + n)))
        y = np.fft.irfft(np.fft.rfft(x, M) * np.fft.rfft(ir, M), M)[:len(x)]
        out.append(y / np.sqrt(np.sum(ir ** 2)) * 0.5)
    return out


# автоматизация громкости: вступление тише, чтобы дроп «выстрелил»
_t = tt(N)
AUTO = np.interp(_t, [0, 0.9, 1.0, 2.9, 3.0, 4.9, 5.0, 6.7, 6.95, 7.0, 40],
                 [0.95, 0.8, 0.5, 0.55, 0.62, 0.66, 0.72, 0.85, 0.5, 1.0, 1.0])
for bus in BUS:
    for ch in (0, 1):
        BUS[bus][ch] *= AUTO
SEND[0] *= AUTO
SEND[1] *= AUTO

rl, rr = reverb(*SEND)
L = np.zeros(N)
R = np.zeros(N)
gains = {'drums': 1.0, 'bass': 0.95, 'music': 0.85, 'fx': 0.85}
for ch, o in ((0, L), (1, R)):
    for k, g in gains.items():
        o += BUS[k][ch] * g
    o += (rl, rr)[ch] * 0.55

mix = np.stack([fft_filter(L, lo=28), fft_filter(R, lo=28)])
mix /= np.max(np.abs(mix)) + 1e-9
mix = np.tanh(mix * 1.8) / np.tanh(1.8)
t = tt(N)
mix *= np.clip((DUR - t) / 0.35, 0, 1)
mix = mix[:, :int(DUR * SR)]
mix *= 0.89 / np.max(np.abs(mix))

out = sys.argv[1] if len(sys.argv) > 1 else 'music.wav'
with wave.open(out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((mix.T * 32767).astype('<i2').tobytes())
print('готово:', out)
