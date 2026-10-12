"""Звук серии: музыка, шумы, эффекты и голоса синтезируются и сводятся здесь (общий движок для всех серий).

    python3 engine/audio/voices.py e01      # сначала голоса (ваша запись или синтез)
    python3 engine/audio/mix.py e01         # → episodes/e01/assets/soundtrack.wav, lipsync.json

Партитура конкретной серии — episodes/<ep>/audio/cues.py: она выполняется внутри этого файла и может
пользоваться всеми инструментами ниже (groove, melody, chord, hit, add, whoosh, impact, …).
Время событий в партитуре — сюжетное (как в shots.js); растяжки под озвучку учитываются сами (W).
Голоса обрабатываются по персонажам: металл в шлеме Кронова, эхо у Тени; эффекты отдельных реплик —
поле "fx" в dialogue.json ("phone" — телефон, "memory" — эхо-воспоминание, "radio" — рация).
Музыка приглушается под речью (сайдчейн по огибающей голоса).
"""
import json
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
STUDIO = os.path.dirname(os.path.dirname(HERE))
# какая серия: python3 engine/audio/mix.py e02  (или путь к папке серии)
_ep = sys.argv[1] if len(sys.argv) > 1 else json.load(open(os.path.join(STUDIO, 'episodes', 'index.json')))['default']
EPDIR = _ep if os.path.isdir(_ep) else os.path.join(STUDIO, 'episodes', _ep)
CUES = os.path.join(EPDIR, 'audio', 'cues.py')
SR = 44100
TL = json.load(open(os.path.join(EPDIR, 'timeline.json')))
DUR = TL['duration']                      # экранная длительность (с растяжками под озвучку)
N = int((DUR + 2) * SR)
STR = TL.get('stretch', [])


def W(t):
    """Сюжетное время (в нём расписаны события) → экранное."""
    return t + sum(e * min(max((t - a) / (b - a), 0), 1) for a, b, e in STR)
BPM = 126
BEAT = 60 / BPM
BAR = BEAT * 4
rs = np.random.default_rng(11)

BUS = {k: [np.zeros(N), np.zeros(N)] for k in ('drums', 'bass', 'music', 'fx', 'amb', 'vox')}
SEND = [np.zeros(N), np.zeros(N)]


# ---------------- утилиты ----------------
def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def noise(n):
    return rs.standard_normal(n)


def add(bus, sig, t0, gain=1.0, pan=0.0, rev=0.0, raw=False):
    """raw=True — t0 уже в экранном времени (ритм-секции, голоса)."""
    i = int(round((t0 if raw else W(t0)) * SR))
    if i >= N or len(sig) == 0:
        return
    if i < 0:
        sig = sig[-i:]; i = 0
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
    H = np.ones_like(f)
    if hi:
        H /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        H /= np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(X * H, M)[:n]


def tv_band(x, fc_at, bw=0.6, block=2048):
    hop = block // 2
    win = np.hanning(block + 1)[:-1]
    out = np.zeros(len(x) + block)
    xp = np.concatenate([x, np.zeros(block)])
    f = np.fft.rfftfreq(block, 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    for s in range(0, len(x), hop):
        fc = fc_at((s + hop) / SR)
        H = np.exp(-0.5 * ((lf - np.log2(fc)) / bw) ** 2)
        out[s:s + block] += np.fft.irfft(np.fft.rfft(xp[s:s + block] * win) * H, block)
    return out[:len(x)]


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.1):
    t = tt(n)
    dur = n / SR
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    return e * np.clip((dur - t) / max(r, 1e-6), 0, 1)


def saw_add(freq, n, fc, voices=1, detune=0.0, maxh=None, vib=0.0):
    t = tt(n)
    out = np.zeros(n)
    for v in range(voices):
        dv = (v - (voices - 1) / 2) * detune
        f = freq * 2 ** (dv / 1200)
        ph0 = rs.random() * 2 * np.pi
        phase = 2 * np.pi * f * t + (vib * np.sin(2 * np.pi * 5.2 * t) / 5.2 * 2 * np.pi * f / 100 if vib else 0)
        K = int(min(maxh or 60, (SR / 2.2) / f))
        for k in range(1, K + 1):
            g = 1 / np.sqrt(1 + (k * f / fc) ** 4)
            if np.isscalar(g) and g < 0.003:
                break
            out += g / k * np.sin(k * phase + ph0 * k)
    return out / max(1, voices) ** 0.6


def pluck(freq, len_=1.2, bright=0.6, decay=0.9965):
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
    out = fft_filter(out, lo=120, hi=6000)
    return out * np.minimum(1, (len_ - tt(n)) / 0.05)


# ---------------- инструменты ----------------
def kick(amp=1.0, tail=0.45, low=46):
    n = int(tail * SR); t = tt(n)
    f = low + (170 - low) * np.exp(-t * 30)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7.5)
    click = fft_filter(noise(n) * np.exp(-t * 900), lo=2500) * 0.35
    return np.tanh((body + click) * 1.6) * amp


def snare(amp=1.0):
    n = int(0.28 * SR); t = tt(n)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 28)
    nz = fft_filter(noise(n), lo=1400, hi=9000) * np.exp(-t * 18)
    return (tone * 0.55 + nz * 0.85) * amp


def clap():
    n = int(0.35 * SR); t = tt(n)
    env = np.zeros(n)
    for k, d in enumerate((0.0, 0.011, 0.022)):
        env += np.where(t >= d, np.exp(-(t - d) * (180 if k < 2 else 22)), 0)
    return fft_filter(noise(n), lo=900, hi=4200) * env * 0.9


def hat(open_=False):
    n = int((0.3 if open_ else 0.06) * SR); t = tt(n)
    return fft_filter(noise(n), lo=7000, order=3) * np.exp(-t * (11 if open_ else 70))


def taiko(amp=1.0, f0=70):
    n = int(1.1 * SR); t = tt(n)
    f = f0 + 50 * np.exp(-t * 25)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 4.5)
    skin = fft_filter(noise(n), hi=900) * np.exp(-t * 18) * 0.6
    return np.tanh((body + skin) * 1.8) * amp


def tom(f0=110):
    n = int(0.5 * SR); t = tt(n)
    f = f0 + 60 * np.exp(-t * 30)
    return np.tanh(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 1.5 + fft_filter(noise(n), hi=1500) * np.exp(-t * 30) * .3)


def crash(len_=2.4):
    n = int(len_ * SR); t = tt(n)
    x = fft_filter(noise(n), lo=3500) * np.exp(-t * 2.0)
    return x + sum(np.sin(2 * np.pi * f * t + rs.random() * 6) for f in (3170, 4410, 5230, 6890)) * 0.05 * np.exp(-t * 3)


def boom(len_=2.0, amp=1.0):
    n = int(len_ * SR); t = tt(n)
    f = 28 + 60 * np.exp(-t * 6)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.6)
    body = fft_filter(noise(n), hi=400) * np.exp(-t * 5) * 0.7
    return np.tanh((sub + body) * 2.2) * amp


def riser(len_, f0=300, f1=9000):
    n = int(len_ * SR); t = tt(n); k = t / len_
    x = tv_band(noise(n), lambda s: f0 * (f1 / f0) ** min(1, s / len_) ** 1.4, bw=0.5)
    tone = np.sin(2 * np.pi * np.cumsum(180 + 900 * k ** 2) / SR + 3 * np.sin(2 * np.pi * 6 * t)) * 0.18
    return (x * 1.4 + tone) * k ** 2.2


def whoosh(len_=0.5, up=True, f0=400):
    n = int(len_ * SR); k = tt(n) / len_
    x = tv_band(noise(n), lambda s: (f0 * (12 ** (s / len_)) if up else f0 * 12 * (0.1 ** (s / len_))), bw=0.7)
    return x * np.sin(np.pi * k) ** 1.5


def bell(f, len_=1.4):
    n = int(len_ * SR); t = tt(n)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.2 * np.exp(-t * 4)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 3.2) + 0.3 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 6)


def brass(m, len_, amp=1.0, att=0.03):
    """Медь: пила с фильтром, раскрывающимся на атаке."""
    n = int((len_ + 0.25) * SR); t = tt(n)
    fc = 600 + 2600 * (1 - np.exp(-t / 0.06)) * np.exp(-t * 1.2) + 700
    x = saw_add(mtof(m), n, fc, voices=3, detune=10, maxh=40, vib=0.25)
    return x * adsr(n, att, 0.4, 0.75, 0.25) * amp


def strings(m, len_, amp=1.0, att=0.35):
    n = int((len_ + 0.6) * SR)
    x = saw_add(mtof(m), n, 2200, voices=4, detune=14, maxh=26, vib=0.18)
    return fft_filter(x, lo=150) * adsr(n, att, 1.0, 0.85, 0.6) * amp


def pad(m, len_, amp=1.0, fc=1400):
    n = int((len_ + 1.0) * SR)
    x = saw_add(mtof(m), n, fc, voices=3, detune=18, maxh=20)
    return x * adsr(n, 0.8, 1.0, 0.9, 1.0) * amp


def sub(m, len_, amp=1.0):
    n = int(len_ * SR)
    return np.sin(2 * np.pi * mtof(m) * tt(n)) * adsr(n, 0.01, 0.3, 0.8, 0.2) * amp


def bassnote(m, len_, amp=1.0):
    n = int(len_ * SR)
    fc = 280 + 1400 * np.exp(-tt(n) * 16)
    x = saw_add(mtof(m), n, fc, voices=2, detune=8, maxh=40) * adsr(n, 0.003, 0.09, 0.6, 0.04)
    x += np.sin(2 * np.pi * mtof(m) * tt(n)) * adsr(n, 0.003, 0.2, 0.8, 0.04) * 0.8
    return x * amp


def heartbeat(amp=1.0):
    out = np.zeros(int(0.7 * SR))
    for d, a in ((0, 1), (0.24, .7)):
        k = kick(a, 0.35, low=38)
        k = fft_filter(k, hi=180)
        i = int(d * SR); out[i:i + len(k)] += k
    return out * amp


# ---------------- шумовые эффекты ----------------
def thunder(len_=6.0, crack=0.0, amp=1.0):
    n = int(len_ * SR); t = tt(n)
    env = np.exp(-t * 0.9) * (1 + 0.6 * np.sin(2 * np.pi * 1.3 * t + rs.random() * 6) ** 2) * np.minimum(1, t / 0.15)
    rum = fft_filter(noise(n), hi=160, order=2) * 3.0 * env
    rum += fft_filter(noise(n), lo=150, hi=900) * env * np.exp(-t * 1.5) * 0.6
    if crack:
        c = fft_filter(noise(n), lo=600, hi=8000) * np.exp(-t * 9) * crack
        rum += c + boom(len_, 0.8 * crack)
    return np.tanh(rum * 0.8) * amp


def thwip():
    n = int(0.32 * SR); t = tt(n)
    f = 2400 * np.exp(-t * 14) + 300
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10) * 0.5
    sw = tv_band(noise(n), lambda s: 6000 * np.exp(-s * 9) + 500, bw=0.5) * np.exp(-t * 7)
    return tone + sw * 1.4


def splat():
    n = int(0.25 * SR); t = tt(n)
    return fft_filter(noise(n), lo=200, hi=2500) * np.exp(-t * 25) + np.sin(2 * np.pi * 140 * t) * np.exp(-t * 30) * .6


def impact(amp=1.0, metal=0.0):
    n = int(1.2 * SR); t = tt(n)
    x = boom(1.2, 0.9) + fft_filter(noise(n), lo=300, hi=5000) * np.exp(-t * 14) * 0.9
    if metal:
        x += sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in ((523, 4), (811, 5), (1283, 6), (1907, 8))) * 0.25 * metal
    return np.tanh(x * 1.3) * amp


def glass(amp=1.0, len_=1.6):
    n = int(len_ * SR); t = tt(n)
    x = fft_filter(noise(n), lo=2500) * np.exp(-t * 6) * 0.8
    for _ in range(28):
        d = rs.random() * len_ * 0.7
        f = 2500 + rs.random() * 6000
        i = int(d * SR); m = n - i
        x[i:] += np.sin(2 * np.pi * f * tt(m)) * np.exp(-tt(m) * (20 + rs.random() * 30)) * 0.35
    return x * amp


def zap(len_=1.0, amp=1.0):
    n = int(len_ * SR); t = tt(n)
    buzz = np.sign(np.sin(2 * np.pi * (90 + 40 * np.sin(2 * np.pi * 7 * t)) * t)) * 0.4
    crackle = noise(n) * (rs.random(n) > 0.985) * 3
    x = fft_filter(buzz + crackle + fft_filter(noise(n), lo=2000) * 0.4, lo=150, hi=9000)
    return x * np.minimum(1, (len_ - t) / 0.2) * amp


def servo(len_=0.6, f0=300, f1=700):
    n = int(len_ * SR); t = tt(n); k = t / len_
    f = f0 + (f1 - f0) * np.sin(np.pi * k)
    x = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.2 + np.sin(2 * np.pi * np.cumsum(f * 2) / SR) * 0.2
    return fft_filter(x, hi=3000) * np.sin(np.pi * k) ** .5


def stomp(amp=1.0):
    return (kick(0.8, 0.4, low=40) + impact(0.3, metal=.5)[:int(0.4 * SR)]) * amp


def horn(len_=0.5, f=420):
    n = int(len_ * SR); t = tt(n)
    x = sum(np.sign(np.sin(2 * np.pi * f * r * t)) * a for r, a in ((1, .5), (1.26, .4)))
    return fft_filter(x, lo=200, hi=2500) * adsr(n, 0.01, 0.1, 0.9, 0.05)


def screech(len_=0.8):
    n = int(len_ * SR); t = tt(n)
    f = 2100 + 300 * np.sin(2 * np.pi * 11 * t)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.4 + fft_filter(noise(n), lo=1500, hi=6000) * 0.5
    return x * np.sin(np.pi * t / len_) ** .6


def metal_groan(len_=2.0, f0=70):
    n = int(len_ * SR); t = tt(n)
    f = f0 * (1 + 0.15 * np.sin(2 * np.pi * 0.7 * t)) + 8 * noise(n).cumsum() / SR
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 2.71) / SR) + 0.3 * np.sin(2 * np.pi * np.cumsum(f * 5.3) / SR)
    x *= (1 + 0.8 * np.sin(2 * np.pi * 9 * t)) * 0.5
    return fft_filter(x, hi=2500) * np.sin(np.pi * t / len_) ** .7


def siren(len_, f0=650, f1=950, rate=0.35):
    n = int(len_ * SR); t = tt(n)
    f = f0 + (f1 - f0) * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(2 * np.pi * np.cumsum(f * 2) / SR)
    return fft_filter(x, hi=1800) * np.minimum(1, t / 1.0) * np.minimum(1, (len_ - t) / 1.0)


def tinnitus(len_=4.0):
    n = int(len_ * SR); t = tt(n)
    return np.sin(2 * np.pi * 3600 * t) * np.exp(-t * 0.9) * np.minimum(1, t / 0.05)


def ring_tone(len_=1.6):
    out = np.zeros(int(len_ * SR))
    for i, m in enumerate([88, 84, 91, 88, 84, 91]):
        b = bell(mtof(m) / 2, 0.3)
        j = int(i * 0.13 * SR) + (int(0.45 * SR) if i > 2 else 0)
        out[j:j + len(b)] += b[:len(out) - j]
    return out


def thud(amp=1.0):
    n = int(0.6 * SR); t = tt(n)
    return np.tanh((kick(1, 0.6, low=50) + fft_filter(noise(n), hi=700) * np.exp(-t * 20)) * 1.2) * amp


def footstep(amp=1.0):
    n = int(0.15 * SR); t = tt(n)
    return fft_filter(noise(n), lo=150, hi=2500) * np.exp(-t * 40) * amp


def scrape(len_=1.5):
    n = int(len_ * SR); t = tt(n)
    x = tv_band(noise(n), lambda s: 900 + 600 * np.sin(s * 9), bw=0.4) * 1.5 + metal_groan(len_, 140) * 0.3
    return x * np.sin(np.pi * t / len_) ** .5


def tape_stop(x_len=0.6):
    """«Остановка плёнки»: глиссандо вниз у баса/аккорда."""
    n = int(x_len * SR); t = tt(n); k = t / x_len
    f = mtof(50) * (1 - k) ** 2 + 20
    return fft_filter(np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sign(np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR)), hi=1200) * (1 - k)


# ---------------- музыка ----------------
# тема героя (ре минор): D F A G F E D A
HERO = [62, 65, 69, 67, 65, 64, 62, 57]
CH = {'Dm': [50, 53, 57], 'Bb': [46, 50, 53], 'F': [53, 57, 60], 'C': [48, 52, 55], 'Gm': [43, 46, 50],
      'A': [45, 49, 52], 'Eb': [51, 55, 58], 'Dsus': [50, 55, 57]}
PROG = ['Dm', 'Bb', 'F', 'C']
KICKS = []


def groove(t0, t1, prog=PROG, intensity=1.0, hats=True, toms=False, arp=True, half=False):
    """Ритм-секция: бочка, малый, хэты, бас восьмыми, аккорд-пэд, арпеджио.
    Сетка долей строится в экранном времени, чтобы растяжки не ломали темп."""
    t0, t1 = W(t0), W(t1)
    nb = int((t1 - t0) / BAR + 0.999)
    for bi in range(nb):
        b0 = t0 + bi * BAR
        c = prog[bi % len(prog)]
        root = CH[c][0] - 12
        for b in range(4):
            tb = b0 + b * BEAT
            if tb >= t1:
                break
            if not half or b % 2 == 0:
                add('drums', kick(1.0), tb, 0.85 * intensity, raw=True); KICKS.append(tb)
            if b in (1, 3):
                add('drums', snare(1.0), tb, 0.55 * intensity, rev=0.2, raw=True)
                add('drums', clap(), tb, 0.3 * intensity, rev=0.2, raw=True)
            if hats:
                for s in range(4):
                    add('drums', hat(s == 2), tb + s * BEAT / 4, (0.14 + 0.07 * (s == 2)) * intensity, pan=0.3 * (-1) ** s, raw=True)
            if toms and b == 3 and bi % 2 == 1:
                for k, f in enumerate((140, 115, 90)):
                    add('drums', tom(f), tb + k * BEAT / 3, 0.45 * intensity, pan=0.4 - 0.4 * k, raw=True)
            for h in range(2):
                m = root + (12 if (b * 2 + h) % 4 == 3 else 0)
                add('bass', bassnote(m, 0.22), tb + h * BEAT / 2, 0.34 * intensity, raw=True)
        for m in CH[c]:
            add('music', pad(m + 12, BAR, fc=1600), b0, 0.03 * intensity, pan=rs.uniform(-.6, .6), rev=0.4, raw=True)
        if arp:
            tones = [CH[c][0] + 24, CH[c][1] + 24, CH[c][2] + 24, CH[c][0] + 36]
            for s, p in enumerate([0, 2, 3, 1, 2, 3, 1, 2]):
                ts = b0 + s * BEAT / 2
                if ts < t1:
                    add('music', pluck(mtof(tones[p]), 0.45, 0.65, 0.993), ts, 0.16 * intensity, pan=0.35 * (1 if s % 2 else -1), rev=0.3, raw=True)


def melody(notes, t0, step, inst='brass', amp=0.3, oct=0, ln=None):
    t0 = W(t0)
    for i, m in enumerate(notes):
        if m is None:
            continue
        L = (ln[i] if ln else 1) * step
        if inst == 'brass':
            add('music', brass(m + oct, L), t0 + i * step, amp, rev=0.35, raw=True)
        elif inst == 'strings':
            add('music', strings(m + oct, L, att=0.12), t0 + i * step, amp, rev=0.45, raw=True)
        else:
            add('music', pluck(mtof(m + oct), L + 0.6, 0.6, 0.997), t0 + i * step, amp, pan=0.1, rev=0.4, raw=True)


def chord(c, t0, len_, inst='strings', amp=0.05, oct=12):
    for m in CH[c]:
        x = strings(m + oct, len_) if inst == 'strings' else brass(m + oct, len_) if inst == 'brass' else pad(m + oct, len_)
        add('music', x, t0, amp, pan=rs.uniform(-.5, .5), rev=0.5)


def hit(t, amp=1.0, c='Dm'):
    add('fx', boom(2.4, 1.0), t, 0.9 * amp)
    add('fx', crash(2.6), t, 0.4 * amp, rev=0.5)
    add('drums', taiko(1.0, 60), t, 0.8 * amp, rev=0.3)
    chord(c, t, 1.4, 'brass', 0.09 * amp, oct=0)
    chord(c, t, 1.4, 'brass', 0.06 * amp, oct=12)


# ---------------- общие приёмы для партитур серий ----------------
def walla(len_, excite=0.5, seed=0):
    """Гул толпы: несколько «голосов» — шум через плавающие форманты с рваной огибающей слогов."""
    g = np.random.default_rng(seed); n = int(len_ * SR); t = tt(n); out = np.zeros(n)
    for v in range(10):
        f1 = g.uniform(350, 800) * (1 + excite * 0.5); rate = g.uniform(3, 6) * (1 + excite * 0.6)
        x = tv_band(g.standard_normal(n), lambda s, f1=f1, ph=g.random() * 6: f1 * (1 + 0.35 * np.sin(s * 2.3 + ph)), bw=0.45)
        syl = np.clip(np.sin(2 * np.pi * rate * t + g.random() * 6) + g.uniform(-.2, .5), 0, 1) ** 1.5
        out += x * syl * g.uniform(.5, 1)
    return out * np.minimum(1, t * 2) * np.minimum(1, (len_ - t) * 1.5)


def rain_bed():
    x = fft_filter(noise(N), lo=500, hi=7000) * 0.25
    x += fft_filter(noise(N), hi=400) * 0.15
    drips = (rs.random(N) > 0.9996) * noise(N) * 2
    x += fft_filter(drips, lo=2000, hi=8000)
    return x


def seg(a, b, v, fade=0.4):
    a, b = W(a), W(b)
    m = (T >= a - fade) & (T < b + fade)
    k = np.clip(np.minimum((T - (a - fade)) / fade, ((b + fade) - T) / fade), 0, 1)
    lvl[m] = lvl[m] * (1 - k[m]) + v * k[m]


def strikes_thunder():
    """Гром на каждую молнию из timeline.json (дальние — тише и с задержкой)."""
    for s in TL['strikes']:
        if s['k'] <= 0:
            continue
        far = s['k'] < 1.2
        delay = 0.9 if far else 0.05
        add('amb', thunder(6.0 if far else 7.0, crack=0.0 if far else 1.0), s['t'] + delay, (0.35 if far else 0.75) * min(1.2, s['k']), pan=rs.uniform(-.4, .4), rev=0.3)


# ---------------- партитура серии ----------------
exec(compile(open(CUES, encoding='utf-8').read(), CUES, 'exec'), globals())

# ---------------- голоса ----------------
def load_wav(p):
    w = wave.open(p); sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float) / 32768
    w.close()
    n = int(len(x) * SR / sr)
    return np.interp(np.arange(n) * sr / SR, np.arange(len(x)), x)


def comb(x, d, g):
    y = x.copy(); k = int(d * SR)
    for _ in range(3):
        y[k:] += g * y[:-k]
    return y


def process(who, fx, x):
    x = x / (np.max(np.abs(x)) + 1e-9)
    if fx == 'phone':                                  # телефон
        x = np.tanh(fft_filter(x, lo=350, hi=3200, order=3) * 2.5) * 0.7
    elif fx == 'radio':                                # рация: уже телефона и с хрипом
        x = np.tanh(fft_filter(x, lo=500, hi=2600, order=3) * 4.0) * 0.6 + noise(len(x)) * 0.01
    elif fx == 'memory':                               # воспоминание: эхо
        y = x.copy()
        for i, g in enumerate((0.5, 0.3, 0.18)):
            k = int((i + 1) * 0.28 * SR); y = np.concatenate([y, np.zeros(int(0.3 * SR))]); y[k:k + len(x)] += x * g
        x = fft_filter(y, lo=200, hi=5000)
    elif who == 'kronov':                              # шлем: металл + низ
        t = tt(len(x))
        x = comb(x, 0.0042, 0.35) * 0.6 + x * 0.5
        x = x * (1 + 0.15 * np.sin(2 * np.pi * 55 * t))
        x = np.tanh(x * 1.6) + fft_filter(x, hi=250) * 0.5
    elif who == 'shadow':
        x = comb(x, 0.007, 0.3) + fft_filter(x, hi=300) * 0.6
    elif who == 'crowd':
        x = fft_filter(x, lo=300, hi=3500)
    return x / (np.max(np.abs(x)) + 1e-9)


VOX_GAIN = {**{'narrator': 0.85, 'timur': 0.9, 'ded': 0.9, 'vera': 0.85, 'kronov': 0.95, 'shadow': 0.95, 'crowd': 0.4}, **globals().get('EXTRA_VOX_GAIN', {})}
VOX_REV = {**{'narrator': 0.05, 'timur': 0.08, 'ded': 0.1, 'vera': 0.12, 'kronov': 0.15, 'shadow': 0.6, 'crowd': 0.5}, **globals().get('EXTRA_VOX_REV', {})}
lines = json.load(open(os.path.join(EPDIR, 'dialogue.json'), encoding='utf-8'))['lines']
FPS = 30
lips = {'fps': FPS, 'durations': {}, 'env': {}, 'shape': {}, 'fric': {}}
vox_env = np.zeros(N)
for ln in lines:
    p = os.path.join(EPDIR, 'audio', 'voice', ln['id'] + '.wav')
    dry = load_wav(p)
    x = process(ln['who'], ln.get('fx'), dry)
    # мягкая компрессия: выравниваем громкость фраз
    e = np.sqrt(np.convolve(x ** 2, np.ones(1024) / 1024, 'same'))
    x = x / (0.25 + 0.75 * e / (e.max() + 1e-9))
    x /= np.max(np.abs(x)) + 1e-9
    pan = {'ded': -0.1, 'vera': 0.15, 'kronov': 0.1, 'crowd': 0.4}.get(ln['who'], 0.0)
    t0 = W(ln['t'])
    add('vox', x, t0, VOX_GAIN[ln['who']], pan=pan, rev=VOX_REV[ln['who']], raw=True)
    i = int(t0 * SR)
    ev = np.abs(x)
    vox_env[i:i + len(ev)] = np.maximum(vox_env[i:i + len(ev)], np.convolve(ev, np.ones(2048) / 2048, 'same')[:N - i])
    # липсинк по «сухому» голосу: открытие рта (RMS) и форма (спектральный центроид: низкий — «о/у», высокий — «и/э»)
    hop = SR // FPS
    op, cen, fri = [], [], []
    for k in range(0, len(dry), hop):
        fr_ = dry[k:k + hop]
        op.append(float(np.sqrt(np.mean(fr_ ** 2))))
        S = np.abs(np.fft.rfft(fr_ * np.hanning(len(fr_)), 2048)); f = np.fft.rfftfreq(2048, 1 / SR)
        band = (f > 250) & (f < 4000)
        cen.append(float((S[band] * f[band]).sum() / (S[band].sum() + 1e-9)))
        hiE, loE = (S[f > 4000] ** 2).sum(), (S[(f > 100) & (f < 1500)] ** 2).sum()
        fri.append(float(hiE / (hiE + loE + 1e-9)))     # шипящие/свистящие: «с», «ф», «ш» — зубы видны, рот почти закрыт
    op = np.array(op); op = op / (np.percentile(op, 95) + 1e-9)
    op = np.clip(np.convolve(op, [.25, .5, .25], 'same'), 0, 1)
    cen = np.array(cen); voiced = op > .2
    lo, hi = (np.percentile(cen[voiced], 10), np.percentile(cen[voiced], 90)) if voiced.sum() > 4 else (800, 2000)
    shape = np.clip((hi - cen) / max(hi - lo, 1), 0, 1) * (op > .1)
    shape = np.convolve(shape, [.25, .5, .25], 'same')
    lips['durations'][ln['id']] = round(len(dry) / SR, 3)
    lips['env'][ln['id']] = [round(float(v), 2) for v in op]
    lips['shape'][ln['id']] = [round(float(v), 2) for v in shape]
    fri = np.clip((np.array(fri) - .25) / .4, 0, 1) * (op > .08)
    lips['fric'][ln['id']] = [round(float(v), 2) for v in fri]

# ---------------- сведение ----------------
side = np.ones(N)
for k in KICKS:
    i = int(k * SR); m = min(N - i, int(0.35 * SR))
    if m > 0:
        side[i:i + m] = np.minimum(side[i:i + m], 1 - 0.6 * np.exp(-tt(m) / 0.09))
duck = 1 - 0.55 * np.clip(np.convolve(vox_env, np.ones(8192) / 8192, 'same') * 6, 0, 1)
for ch in (0, 1):
    BUS['bass'][ch] *= side * duck
    BUS['music'][ch] *= (0.6 + 0.4 * side) * duck
    BUS['drums'][ch] *= 0.75 + 0.25 * duck
    BUS['amb'][ch] *= 0.6 + 0.4 * duck
    BUS['fx'][ch] *= 0.8 + 0.2 * duck


def reverb(xl, xr, length=2.6, damp=5500):
    n = int(length * SR); tr = tt(n); out = []
    for x, seed in ((xl, 1), (xr, 2)):
        g = np.random.default_rng(seed)
        ir = g.standard_normal(n) * np.exp(-tr * 6.9 / length)
        ir = fft_filter(ir, lo=250, hi=damp); ir[:int(0.015 * SR)] = 0
        M = 1 << int(np.ceil(np.log2(len(x) + n)))
        y = np.fft.irfft(np.fft.rfft(x, M) * np.fft.rfft(ir, M), M)[:len(x)]
        out.append(y / np.sqrt(np.sum(ir ** 2)) * 0.5)
    return out


rl, rr = reverb(*SEND)
gains = {'drums': 0.9, 'bass': 0.85, 'music': 1.0, 'fx': 0.9, 'amb': 0.8, 'vox': 1.6}
L = np.zeros(N); R = np.zeros(N)
for ch, o in ((0, L), (1, R)):
    for k, g in gains.items():
        o += BUS[k][ch] * g
    o += (rl, rr)[ch] * 0.55
mix = np.stack([fft_filter(L, lo=28), fft_filter(R, lo=28)])
mix /= np.max(np.abs(mix)) + 1e-9
mix = np.tanh(mix * 1.6) / np.tanh(1.6)
fade = np.clip((DUR - tt(N)) / 1.0, 0, 1) ** 2
mix *= fade
mix = mix[:, :int(DUR * SR)]


# ---------------- заставка студии GraphicArts Animation ----------------
def make_intro(n):
    """Перо рисует монограмму (шуршание + искры), всплеск краски, музыкальный логотип в ре миноре,
    паучок на нити спускается на точку над «i» и уезжает обратно."""
    L, R = np.zeros(n + 3 * SR), np.zeros(n + 3 * SR)

    def put(sig, t0, g=1.0, pan=0.0):
        i = int(t0 * SR); sig = sig[:len(L) - i] * g; a = (pan + 1) * np.pi / 4
        L[i:i + len(sig)] += sig * np.cos(a); R[i:i + len(sig)] += sig * np.sin(a)
    put(riser(0.8, 300, 6000), 0.0, 0.18)
    m = int(1.9 * SR); t = tt(m)
    pen = tv_band(noise(m), lambda s: 3200 + 1800 * np.sin(s * 11), bw=0.35) * (0.5 + 0.5 * np.abs(np.sin(t * 17))) * np.minimum(1, t * 6) * np.minimum(1, (1.9 - t) * 4)
    put(pen, 0.55, 0.22, -0.3)
    put(np.sin(2 * np.pi * np.cumsum(900 + 700 * t / 1.9) / SR) * 0.12 * np.minimum(1, t * 4) * np.minimum(1, (1.9 - t) * 4), 0.55, 0.5, 0.3)
    g = np.random.default_rng(5)
    for k in range(9):
        put(bell(mtof([86, 89, 93, 96, 98][k % 5]), 0.6), 0.65 + k * 0.2 + g.random() * 0.05, 0.06, g.uniform(-.7, .7))
    put(crash(0.55)[::-1].copy(), 1.85, 0.3)
    put(boom(2.2), 2.4, 0.75); put(splat(), 2.4, 0.7); put(crash(2.6), 2.42, 0.22)
    for m_ in (50, 57, 62, 65, 69, 76):
        put(pad(m_, 2.9, fc=1800), 2.45, 0.05, (m_ - 63) / 20)
    for i, m_ in enumerate((62, 65, 69, 74)):
        put(pluck(mtof(m_), 1.6, bright=0.75), 2.95 + i * 0.17, 0.32, -0.3 + 0.2 * i)
    put(bell(mtof(86), 2.2), 3.66, 0.2); put(bell(mtof(81), 2.2), 3.68, 0.12, 0.4)
    put(whoosh(0.5, False, 900), 4.3, 0.22, 0.2)
    b = int(0.14 * SR); tb = tt(b)
    put(np.sin(2 * np.pi * np.cumsum(1700 * np.exp(-tb * 18) + 500) / SR) * np.exp(-tb * 22), 4.84, 0.25, 0.2)
    put(thwip(), 5.3, 0.3, 0.2)
    rl, rr = reverb(L, R, 2.2)
    L += rl * 0.6; R += rr * 0.6
    out = np.stack([L, R])[:, :n]
    out *= np.clip((INTRO - tt(n)) / 0.7, 0, 1) ** 1.5
    return out


INTRO = TL.get('intro', 0)
if INTRO > 0:
    intro = make_intro(int(INTRO * SR))
    intro *= 0.8 * np.max(np.abs(mix)) / (np.max(np.abs(intro)) + 1e-9)
    mix = np.concatenate([intro, mix], axis=1)
mix *= 0.89 / np.max(np.abs(mix))

os.makedirs(os.path.join(EPDIR, 'assets'), exist_ok=True)
out = os.path.join(EPDIR, 'assets', 'soundtrack.wav')
with wave.open(out, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix.T * 32767).astype('<i2').tobytes())
json.dump(lips, open(os.path.join(EPDIR, 'assets', 'lipsync.json'), 'w'), separators=(',', ':'))
print('готово:', out)
