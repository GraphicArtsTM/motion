"""Звук ЮЛДУЗ: саундтрек, шумы и сведение с голосами → out/mix.wav (48 кГц, стерео).

Всё синтезируется на numpy, без сэмплов: дутар (Karplus–Strong), дойра, карнай-брасс, най (флейта),
хор-пэд (форманты), струнные, колокольчики, барабаны. Тайминги берутся из out/cues.json
(node render.mjs --cues): реплики, звуковые события и музыкальные части. Музыка приглушается под голос.

    python3 audio.py
"""
import json
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 48000
cues = json.load(open(os.path.join(HERE, 'out', 'cues.json')))
DUR = cues['duration']
N = int((DUR + 2) * SR)
rs = np.random.default_rng(17)

BUS = {k: np.zeros((2, N)) for k in ('music', 'drums', 'sfx', 'voice')}
SEND = np.zeros((2, N))


# ---------------- утилиты ----------------
def tt(n):
    return np.arange(n) / SR


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def add(bus, sig, t0, gain=1.0, pan=0.0, rev=0.0):
    i = int(round(t0 * SR))
    if i >= N or len(sig) == 0:
        return
    if i < 0:
        sig = sig[-i:]
        i = 0
    sig = sig[:N - i] * gain
    a = (pan + 1) * np.pi / 4
    gl, gr = np.cos(a), np.sin(a)
    BUS[bus][0, i:i + len(sig)] += sig * gl
    BUS[bus][1, i:i + len(sig)] += sig * gr
    if rev:
        SEND[0, i:i + len(sig)] += sig * gl * rev
        SEND[1, i:i + len(sig)] += sig * gr * rev


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


def band(x, fc, q=4.0):
    n = len(x)
    M = 1 << int(np.ceil(np.log2(max(n, 2) * 2)))
    X = np.fft.rfft(x, M)
    f = np.fft.rfftfreq(M, 1 / SR)
    H = 1 / np.sqrt(1 + (q * (f / fc - fc / np.maximum(f, 1e-3))) ** 2)
    return np.fft.irfft(X * H, M)[:n]


def noise(n):
    return rs.standard_normal(n)


def env_adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    t = tt(n)
    dur = n / SR
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    return e * np.clip((dur - t) / max(r, 1e-6), 0, 1)


def conv(x, h):
    n = len(x) + len(h) - 1
    M = 1 << int(np.ceil(np.log2(n)))
    return np.fft.irfft(np.fft.rfft(x, M) * np.fft.rfft(h, M), M)[:n]


# ---------------- инструменты ----------------
def dutar(freq, len_=1.2, bright=0.6, decay=0.996):
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
    out = fft_filter(out, lo=150, hi=5500)
    return out * np.minimum(1, (len_ - tt(n)) / 0.05) * 0.9


def saw(freq, n, fc, voices=1, detune=0.0, maxh=40):
    t = tt(n)
    out = np.zeros(n)
    for v in range(voices):
        dv = (v - (voices - 1) / 2) * detune
        f = freq * 2 ** (dv / 1200)
        ph = rs.random() * 6.28
        K = int(min(maxh, (SR / 2.2) / f))
        for k in range(1, K + 1):
            g = 1 / np.sqrt(1 + (k * f / fc) ** 4) if np.isscalar(fc) else 1 / np.sqrt(1 + (k * f / fc) ** 4)
            if np.isscalar(g) and g < 0.004:
                break
            out += g / k * np.sin(2 * np.pi * k * f * t + ph * k)
    return out / max(1, voices) ** 0.6


def pad(m_list, len_, fc=1600, gain=1.0, att=0.6):
    n = int(len_ * SR)
    out = np.zeros(n)
    for m in m_list:
        out += saw(mtof(m), n, fc, voices=3, detune=14, maxh=24)
    return out * env_adsr(n, att, 0.8, 0.85, min(1.2, len_ * .4)) * gain / max(1, len(m_list)) ** .5


def choir(m_list, len_, vowel='a', gain=1.0):
    """Хор-пэд: пила через форманты гласной."""
    F = {'a': [(730, 1), (1090, .5), (2440, .25)], 'o': [(570, 1), (840, .5), (2410, .2)], 'u': [(300, 1), (870, .4), (2240, .15)]}[vowel]
    n = int(len_ * SR)
    t = tt(n)
    src = np.zeros(n)
    for m in m_list:
        f0 = mtof(m)
        vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t + rs.random() * 6)
        for v in range(3):
            ph = 2 * np.pi * np.cumsum(f0 * vib * 2 ** ((v - 1) * 9 / 1200)) / SR
            K = int((SR / 2.2) / f0)
            for k in range(1, min(K, 30) + 1):
                src += np.sin(k * ph + v) / k
    y = sum(band(src, fc, 6) * a for fc, a in F)
    return y * env_adsr(n, 0.8, 1, 0.9, min(1.5, len_ * .4)) * gain / (len(m_list) * 6)


def nay(freq, len_, gain=1.0):
    """Най (флейта): синус с вибрато + дыхание."""
    n = int(len_ * SR)
    t = tt(n)
    vib = 1 + 0.012 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.4, 0, 1)
    ph = 2 * np.pi * np.cumsum(freq * vib) / SR
    y = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    br = band(noise(n), freq * 2, 3) * 0.25
    return (y + br) * env_adsr(n, 0.08, 0.3, 0.85, 0.15) * gain * 0.5


def karnay(freq, len_, gain=1.0):
    """Карнай-брасс: пила с открывающимся фильтром."""
    n = int(len_ * SR)
    t = tt(n)
    fc = 500 + 2600 * (1 - np.exp(-t * 8)) * np.exp(-t * 0.6)
    y = saw(freq, n, 2200, voices=2, detune=8, maxh=30)
    y = fft_filter(y, hi=3200) + 0.4 * np.sin(2 * np.pi * freq * t)
    return np.tanh(y * 1.4) * env_adsr(n, 0.04, 0.25, 0.8, 0.1) * gain * 0.6 * (0.6 + 0.4 * np.clip(fc / 3100, 0, 1))


def bell(f, len_=2.0, gain=1.0):
    n = int(len_ * SR)
    t = tt(n)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2 * np.exp(-t * 3)
    return (np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 2.4) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 5)) * gain


def pluck_str(freq, len_=0.3, gain=1.0):
    n = int(len_ * SR)
    y = saw(freq, n, 2600, voices=2, detune=6, maxh=30)
    return y * env_adsr(n, 0.003, 0.12, 0.2, 0.05) * gain


def kick(amp=1.0, tail=0.45):
    n = int(tail * SR)
    t = tt(n)
    f = 45 + 130 * np.exp(-t * 30)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    click = fft_filter(noise(n) * np.exp(-t * 900), lo=2500) * 0.3
    return np.tanh((body + click) * 1.6) * amp


def snare(amp=1.0):
    n = int(0.25 * SR)
    t = tt(n)
    return (np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * .5 + fft_filter(noise(n), lo=1500, hi=9000) * np.exp(-t * 20) * .8) * amp


def hat(open_=False):
    n = int((0.3 if open_ else 0.05) * SR)
    return fft_filter(noise(n), lo=7000, order=3) * np.exp(-tt(n) * (10 if open_ else 80))


def doira_dum():
    n = int(0.35 * SR)
    t = tt(n)
    f = 92 + 40 * np.exp(-t * 40)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10) + fft_filter(noise(n), hi=600) * np.exp(-t * 40) * 0.5


def doira_tak():
    n = int(0.12 * SR)
    t = tt(n)
    return fft_filter(noise(n), lo=1800, hi=6000) * np.exp(-t * 60) + np.sin(2 * np.pi * 420 * t) * np.exp(-t * 45) * 0.4


def doira_jingle():
    n = int(0.25 * SR)
    t = tt(n)
    return sum(np.sin(2 * np.pi * f * t + rs.random() * 6) for f in (5200, 6900, 8300, 9700)) * np.exp(-t * 18) * 0.15 + fft_filter(noise(n), lo=6000) * np.exp(-t * 25) * .3


def taiko(amp=1.0):
    n = int(1.2 * SR)
    t = tt(n)
    f = 58 + 50 * np.exp(-t * 14)
    return np.tanh((np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 3.5) + fft_filter(noise(n), hi=900) * np.exp(-t * 18) * .6) * 2) * amp


def crash(len_=2.4):
    n = int(len_ * SR)
    t = tt(n)
    return fft_filter(noise(n), lo=3000) * np.exp(-t * 2) + sum(np.sin(2 * np.pi * f * t + rs.random() * 6) for f in (3170, 4410, 5230, 6890)) * 0.04 * np.exp(-t * 3)


def boom(len_=2.5):
    n = int(len_ * SR)
    t = tt(n)
    f = 26 + 60 * np.exp(-t * 6)
    return np.tanh((np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.4) + fft_filter(noise(n), hi=400) * np.exp(-t * 4) * .7) * 2.2)


def riser(len_, f0=300, f1=9000):
    n = int(len_ * SR)
    t = tt(n)
    k = t / len_
    x = noise(n)
    # дискретный «свип» блоками
    out = np.zeros(n)
    B = 4096
    for s in range(0, n, B):
        fc = f0 * (f1 / f0) ** ((s + B / 2) / n) ** 1.3
        out[s:s + B] = band(x[s:s + B], fc, 2)[:len(out[s:s + B])]
    tone = np.sin(2 * np.pi * np.cumsum(180 + 900 * k ** 2) / SR) * 0.15
    return (out * 1.5 + tone) * k ** 2


def whoosh(len_=0.5, up=True):
    n = int(len_ * SR)
    k = tt(n) / len_
    out = np.zeros(n)
    x = noise(n)
    B = 2048
    for s in range(0, n, B):
        u = (s + B / 2) / n
        fc = 400 * 12 ** u if up else 5000 * 0.1 ** u
        out[s:s + B] = band(x[s:s + B], fc, 1.5)[:len(out[s:s + B])]
    return out * np.sin(np.pi * k) ** 1.5 * 1.6


def gong(f=110, len_=6.0):
    n = int(len_ * SR)
    t = tt(n)
    y = sum(a * np.sin(2 * np.pi * f * r * t + rs.random() * 6) * np.exp(-t * d) for r, a, d in ((1, 1, .6), (1.48, .6, .8), (2.03, .5, 1.1), (2.74, .4, 1.4), (3.6, .3, 2), (4.9, .2, 3)))
    sweep = np.sin(2 * np.pi * np.cumsum(f * 1.5 * (1 + .1 * np.exp(-t))) / SR) * np.exp(-t * .8) * .3
    return (y + sweep) * np.clip(t / .01, 0, 1) * 0.5


# ---------------- шумы ----------------
def sfx(kind):
    if kind == 'wind':
        n = int(12 * SR)
        x = fft_filter(noise(n), lo=200, hi=900) * (0.6 + 0.4 * np.sin(2 * np.pi * .15 * tt(n)))
        return x * env_adsr(n, 2, 1, 1, 3) * .5, 0.4
    if kind == 'whoosh':
        return whoosh(0.6), 0.6
    if kind == 'dash':
        n = int(.45 * SR)
        z = np.sin(2 * np.pi * np.cumsum(2000 + 4000 * tt(n) / .45) / SR) * np.exp(-tt(n) * 8) * .2
        return whoosh(0.45)[:n] + z, 0.7
    if kind == 'swish':
        return whoosh(0.3), 0.35
    if kind == 'impact':
        b = boom(1.8)
        c = crash(1.8)
        n = max(len(b), len(c))
        return np.pad(b, (0, n - len(b))) + np.pad(c, (0, n - len(c))) * .6, 1.0
    if kind == 'boom':
        return boom(4.0) * 1.2, 1.0
    if kind == 'gong':
        return gong(98, 6), 0.7
    if kind == 'riser':
        return riser(2.2), 0.5
    if kind == 'birds':
        n = int(5 * SR)
        y = np.zeros(n)
        for i in range(10):
            s0 = int(rs.random() * (n - SR // 2))
            m = int(.12 * SR)
            tc = tt(m)
            f = 3200 + 1500 * np.sin(2 * np.pi * (8 + rs.random() * 6) * tc) + rs.random() * 800
            y[s0:s0 + m] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tc / .12) * .25
        return y, 0.35
    if kind == 'steps':
        n = int(3.6 * SR)
        y = np.zeros(n)
        for i in range(8):
            s0 = int(i * .45 * SR)
            m = int(.12 * SR)
            y[s0:s0 + m] += fft_filter(noise(m), lo=200, hi=2500) * np.exp(-tt(m) * 40) * (.7 + .3 * (i % 2))
        return y, 0.35
    if kind == 'pencil':
        n = int(2.6 * SR)
        x = fft_filter(noise(n), lo=2500, hi=7000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 3 * tt(n))))
        return x * env_adsr(n, .1, 1, 1, .3) * .25, 0.4
    if kind == 'bell':
        n = int(2.2 * SR)
        t = tt(n)
        y = sum(np.sin(2 * np.pi * f * t) for f in (1380, 1720, 2950)) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 22 * t)))
        return y * env_adsr(n, .01, 1, 1, .4) * .12, 0.5
    if kind == 'boing':
        n = int(.5 * SR)
        f = 300 + 500 * np.exp(-tt(n) * 6) * (1 + .3 * np.sin(2 * np.pi * 14 * tt(n)))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt(n) * 5) * .35, 0.5
    if kind == 'sparkle':
        n = int(1.6 * SR)
        y = np.zeros(n)
        for i, m in enumerate((86, 90, 93, 98, 102, 105)):
            b = bell(mtof(m), 1.0, .2)
            s0 = int(i * .07 * SR)
            y[s0:s0 + len(b)] += b[:n - s0]
        return y, 0.4
    if kind == 'heart':
        n = int(1.8 * SR)
        y = np.zeros(n)
        for s in (0, .28, .9, 1.18):
            k = kick(.8, .3)
            i0 = int(s * SR)
            y[i0:i0 + len(k)] += fft_filter(k, hi=200)[:n - i0]
        return y, 0.8
    if kind == 'sting':
        n = int(2.0 * SR)
        y = np.zeros(n)
        for m in (38, 39, 50, 51):
            y += saw(mtof(m), n, 1500, voices=2, detune=10) * env_adsr(n, .01, .4, .6, .8)
        return y * .25 + np.pad(taiko(1), (0, max(0, n - int(1.2 * SR))))[:n] * .6, 0.7
    if kind == 'tear':
        n = int(.9 * SR)
        x = fft_filter(noise(n), lo=1200, hi=8000)
        crack = (rs.random(n) > .985).astype(float) * rs.standard_normal(n) * 3
        return (x * .4 + fft_filter(crack, lo=800)) * env_adsr(n, .02, .5, .8, .2) * .6, 0.7
    if kind == 'thud':
        return kick(1.0, .6) * .8, 0.8
    if kind == 'paper':
        n = int(.7 * SR)
        return fft_filter(noise(n), lo=1500, hi=6000) * env_adsr(n, .02, .2, .3, .2) * .4, 0.4
    if kind == 'sad':
        n = int(4 * SR)
        y = bell(mtof(62), 4, .5) + bell(mtof(65), 4, .3) * .6
        return y[:n], 0.4
    if kind == 'crickets':
        n = int(10 * SR)
        t = tt(n)
        y = np.sin(2 * np.pi * 4300 * t) * (np.sin(2 * np.pi * 30 * t) > .3) * (np.sin(2 * np.pi * .9 * t) > .2) * .05
        y += np.sin(2 * np.pi * 4700 * t) * (np.sin(2 * np.pi * 26 * t + 1) > .4) * (np.sin(2 * np.pi * .7 * t + 2) > .3) * .04
        return y * env_adsr(n, 1, 1, 1, 2), 0.4
    if kind == 'swell':
        c = crash(2.5)[::-1]
        return c * .6, 0.6
    if kind == 'chime':
        n = int(2.4 * SR)
        y = np.zeros(n)
        for i, m in enumerate((81, 86, 88, 93)):
            b = bell(mtof(m), 2.0, .25)
            s0 = int(i * .09 * SR)
            y[s0:s0 + len(b)] += b[:n - s0]
        return y, 0.7
    if kind == 'magic':
        n = int(3.5 * SR)
        y = np.zeros(n)
        for i in range(18):
            m = [74, 78, 81, 86, 90, 93][i % 6] + 12 * (i // 6)
            b = bell(mtof(m), 1.2, .14)
            s0 = int(i * .1 * SR)
            y[s0:s0 + len(b)] += b[:n - s0]
        return y + riser(3.5, 800, 12000)[:n] * .3, 0.7
    if kind in ('quake', 'rumble'):
        n = int((6 if kind == 'quake' else 4) * SR)
        x = fft_filter(noise(n), hi=120, order=3) * 6
        x += fft_filter(noise(n), lo=200, hi=1500) * (rs.random(n) > .998) * 4
        return np.tanh(x) * env_adsr(n, .3, 1, 1, 1.5) * .9, 0.0
    if kind == 'roar':
        n = int(3.2 * SR)
        t = tt(n)
        f = 70 + 20 * np.sin(2 * np.pi * 3 * t) + 25 * np.exp(-t)
        ph = 2 * np.pi * np.cumsum(f) / SR
        y = sum(np.sin(k * ph) / k for k in range(1, 30))
        y = np.tanh(y * 3) + fft_filter(noise(n), lo=100, hi=1200) * .8
        y = fft_filter(y, hi=2200)
        return y * env_adsr(n, .2, 1, .9, 1.2) * .6, 0.5
    if kind == 'cloth':
        n = int(.6 * SR)
        return fft_filter(noise(n), lo=800, hi=4000) * env_adsr(n, .05, .2, .5, .2) * .3, 0.3
    if kind == 'crack':
        n = int(1.2 * SR)
        y = np.zeros(n)
        for i in range(14):
            s0 = int(rs.random() * .5 * SR)
            m = int(.03 * SR)
            y[s0:s0 + m] += fft_filter(noise(m), lo=500) * np.exp(-tt(m) * 120) * 2
        return y + fft_filter(noise(n), hi=300) * np.exp(-tt(n) * 4) * .8, 0.6
    if kind == 'glass':
        n = int(2.5 * SR)
        y = np.zeros(n)
        for i in range(40):
            s0 = int(rs.random() * 1.2 * SR)
            b = bell(3000 + rs.random() * 6000, .4, .1)
            y[s0:s0 + len(b)] += b[:n - s0]
        return y, 0.8
    return np.zeros(10), 0


# ---------------- музыка по частям ----------------
D = 50   # ре малой октавы
SEC = {s['name']: (s['a'], s['b']) for s in cues['sections']}


def beats(a, b, bpm):
    bt = 60 / bpm
    k = 0
    while a + k * bt < b - 1e-6:
        yield k, a + k * bt
        k += 1


def music_prologue():
    a, b = SEC['prologue']
    add('music', pad([38, 45, 50], b - a + 1, 700, .8, 2.0), a, .5, rev=.4)
    add('music', choir([62, 65, 69], 9, 'u', 1.0), 0.5, .5, rev=.6)
    for k, t in beats(a, 9, 60):
        add('drums', taiko(.9), t, .55 if k % 2 == 0 else .35, pan=(-.2, .2)[k % 2], rev=.3)
    # титр: героический мотив карная
    for i, (m, ln) in enumerate([(62, .3), (69, .3), (67, .2), (69, .9), (74, 1.4)]):
        add('music', karnay(mtof(m), ln + .3), 9.0 + sum(x[1] for x in [(62, .3), (69, .3), (67, .2), (69, .9), (74, 1.4)][:i]), .5, rev=.35)
    add('music', pad([50, 57, 62, 66], 4, 2400, 1.0, .05), 9.0, .45, rev=.5)
    for k in range(16):
        add('drums', doira_tak(), 11.0 + k * .1, .2 + .3 * k / 15, pan=.2 * (-1) ** k)


DORIAN = [0, 2, 3, 5, 7, 9, 10]


def music_morning():
    a, b = SEC['morning']
    bpm = 92
    bt = 60 / bpm
    prog = [(50, [62, 65, 69]), (48, [60, 64, 67]), (46, [58, 62, 65]), (48, [60, 64, 67])]
    bar = 4 * bt
    nb = int((b - a) / bar) + 1
    mel = [74, 72, 69, 67, 69, 72, 74, 76, 74, 69, 67, 65, 67, 69, 72, 69]
    for i in range(nb):
        t0 = a + i * bar
        root, ch = prog[i % 4]
        add('music', pad(ch, bar + .5, 1400, 1, .3), t0, .16, rev=.4)
        add('music', saw(mtof(root - 12), int((bar) * SR), 400, 1, 0, 10) * env_adsr(int(bar * SR), .02, .3, .6, .2), t0, .22)
        for s in range(8):
            m = ch[[0, 1, 2, 1, 2, 0, 1, 2][s]] + 12
            add('music', dutar(mtof(m), .6, .55, .993), t0 + s * bt / 2, .22, pan=.4 * (-1) ** s, rev=.25)
        # лёгкая дойра
        add('drums', doira_dum(), t0, .3)
        add('drums', doira_tak(), t0 + bt * 1.5, .22, pan=-.3)
        add('drums', doira_dum(), t0 + bt * 2, .22)
        add('drums', doira_tak(), t0 + bt * 3, .22, pan=.3)
        add('drums', doira_jingle(), t0 + bt * 3.5, .2, pan=.3)
        # най-мелодия на чётных тактах до романтической части
        if t0 < 30 and i % 2 == 0:
            for j in range(4):
                add('music', nay(mtof(mel[(i * 2 + j) % 16]), bt * .95), t0 + j * bt, .22, pan=-.1, rev=.45)
    # романтика 31–47.6: колокольчики
    for k, t in beats(31, 47, 92 / 2):
        add('music', bell(mtof([81, 79, 76, 74, 76, 79, 81, 84][k % 8]), 1.6, .12), t, 1, pan=.2, rev=.6)


def music_bully():
    a, b = SEC['bully']
    bpm = 88
    bt = 60 / bpm
    for k, t in beats(a, 66.8, bpm):
        add('drums', kick(.9), t, .5 if k % 4 in (0, 2) else 0)
        if k % 4 in (1, 3):
            add('drums', snare(.8), t, .35, rev=.15)
        add('drums', hat(), t + bt / 2, .12, pan=.3)
        root = [38, 38, 41, 36][(k // 4) % 4]
        add('music', pluck_str(mtof(root), .25, 1), t, .35)
        add('music', pluck_str(mtof(root + 12), .2, 1), t + bt / 2, .18, pan=-.2)
    add('music', pad([50, 53, 57], 66.8 - a, 900, 1, 1), a, .14, rev=.4)
    # грусть 67–71.5
    add('music', pad([50, 53, 57, 60], 5, 1200, 1, 1.0), 67, .18, rev=.6)
    for i, m in enumerate([74, 72, 69, 65, 64, 62]):
        add('music', bell(mtof(m), 2.4, .22), 67.2 + i * .7, 1, pan=.1, rev=.6)


def music_night():
    a, b = SEC['night']
    add('music', pad([50, 57, 64], 10.5, 900, 1, 2.0), a, .2, rev=.6)
    add('music', choir([62, 69, 74], 10, 'o'), a + .5, .4, rev=.7)
    for k in range(int((80 - a) / .45)):
        t = a + 1 + k * .45
        add('music', bell(mtof([86, 81, 88, 83, 90, 86][k % 6]), 1.2, .06), t, 1, pan=.6 * np.sin(k), rev=.7)
    # Хумо: тема ная поверх хора
    add('music', choir([62, 66, 69, 74], 18.5, 'a', 1.2), 82, .45, rev=.7)
    add('music', pad([50, 57, 62, 66], 18.5, 1600, 1, 1.5), 82, .16, rev=.5)
    theme = [(74, 1), (76, .5), (78, .5), (81, 1.5), (78, .5), (76, 1), (74, 1), (73, .5), (74, 2.5)]
    t = 83.5
    for m, ln in theme:
        add('music', nay(mtof(m), ln * .6 + .1), t, .32, rev=.5)
        t += ln * .6
    t = 92.5
    for m, ln in theme:
        add('music', nay(mtof(m + 0), ln * .6 + .1), t, .3, rev=.5)
        t += ln * .6
    for k in range(32):
        add('music', dutar(mtof([62, 66, 69, 74][k % 4] + 12), .5, .6, .994), 93.5 + k * .2, .14, pan=.3 * (-1) ** k, rev=.4)


def music_transform():
    a, b = SEC['transform']
    add('music', riser(2.2, 300, 12000), a, .4)
    for k in range(18):
        add('drums', taiko(.5 + .5 * k / 17), a + k * 2.2 / 18, .4)
    add('music', choir([62, 66, 69, 74, 78], b - 102.6 + 1, 'a', 1.5), 102.6, .5, rev=.6)
    add('music', pad([50, 57, 62, 66, 69], b - 102.6 + 1, 3000, 1, .05), 102.6, .3, rev=.5)
    for i, m in enumerate([62, 69, 74, 78, 81]):
        add('music', karnay(mtof(m), 1.4 - i * .1), 102.7 + i * .12, .3, pan=-.3 + .15 * i, rev=.4)


def music_crisis():
    a, b = SEC['crisis']
    add('music', pad([38, 39, 45], b - a + 1, 600, 1, 1), a, .4, rev=.4)
    for k, t in beats(a + 1, b, 70):
        add('drums', taiko(1), t, .5 if k % 2 == 0 else .3)
        if k % 4 == 3:
            for m in (50, 51, 57):
                add('music', karnay(mtof(m), .5), t, .2, rev=.3)
    add('music', choir([50, 51, 57], 8, 'u', 1), 110, .45, rev=.7)


PHR = [0, 1, 4, 5, 7, 8, 10]   # фригийский доминантный лад (хиджаз)


def music_battle():
    a, b = SEC['battle']
    bpm = 150
    bt = 60 / bpm
    soft = (137.6, 145.0)
    mel = [(74, 2), (75, 1), (78, 1), (79, 2), (78, 1), (75, 1), (74, 3), (72, 1), (74, 2), (75, 1), (78, 1), (81, 2), (79, 1), (78, 1), (74, 4)]
    for k, t in beats(a, b, bpm):
        if soft[0] <= t < soft[1]:
            continue
        intense = 1.0 if t > 145 else 0.8
        bk = k % 16
        if k % 4 == 0 or (bk in (10,)):
            add('drums', kick(1), t, .55 * intense)
        if k % 4 == 2:
            add('drums', snare(1), t, .32, rev=.2)
        add('drums', doira_tak(), t + bt / 2, .22, pan=.3 * (-1) ** k)
        if k % 2 == 0:
            add('drums', doira_dum(), t + bt * .25, .2, pan=-.2)
        add('drums', doira_jingle(), t + bt * .75, .12, pan=.4)
        root = D - 12 + [0, 0, 1, 0][(k // 16) % 4]
        add('music', pluck_str(mtof(root + (12 if k % 2 else 0)), .16, 1), t, .3)
        add('music', pluck_str(mtof(root + 12 + PHR[[0, 2, 4, 2][k % 4]]), .12, 1), t + bt / 2, .12, pan=.3)
    # мелодия карная (две проводки)
    for start in (126.0, 148.0):
        t = start
        for m, ln in mel:
            if t >= b - .5:
                break
            add('music', karnay(mtof(m), ln * bt * 2 * .95), t, .32, pan=-.05, rev=.3)
            add('music', karnay(mtof(m - 12), ln * bt * 2 * .95), t, .14, pan=.1, rev=.2)
            t += ln * bt * 2
    add('music', pad([50, 51, 54, 57], soft[0] - a, 1500, 1, .5), a, .12, rev=.4)
    # романтическая пауза: луна и Нилуфар
    add('music', pad([50, 54, 57, 62], soft[1] - soft[0] + .5, 1800, 1, 1.2), soft[0], .2, rev=.6)
    add('music', choir([62, 66, 69], soft[1] - soft[0], 'a'), soft[0], .4, rev=.7)
    t = soft[0] + .5
    for m, ln in [(78, 1), (76, .5), (74, .5), (73, 1.5), (74, 2.5)]:
        add('music', nay(mtof(m), ln * .9 + .1), t, .3, rev=.6)
        t += ln * .9
    # финальный набор
    add('music', choir([62, 63, 66, 69, 74], 4.5, 'a', 1.5), 157.8, .3, rev=.6)
    add('music', riser(2.3, 400, 14000), 157.8, .3)


def music_dawn():
    a, b = SEC['dawn']
    for m_list, t0 in (([50, 57, 62, 66, 69], a), ([55, 59, 62, 67, 71], a + 2.0), ([50, 57, 62, 66, 69, 74], a + 4.0)):
        add('music', choir(m_list, 2.6 if t0 < a + 4 else 4.5, 'a', 1.4), t0, .55, rev=.7)
        add('music', pad(m_list, 2.6 if t0 < a + 4 else 4.5, 2600, 1, .3), t0, .3, rev=.5)
    for i, m in enumerate([74, 78, 81, 86, 90]):
        add('music', bell(mtof(m), 2.5, .2), a + .2 + i * .25, 1, pan=-.4 + .2 * i, rev=.7)
    t = a + 4.2
    for m, ln in [(74, .5), (78, .5), (81, 1), (86, 2)]:
        add('music', karnay(mtof(m), ln + .3), t, .3, rev=.5)
        t += ln


def music_epilogue():
    a, b = SEC['epilogue']
    bpm = 96
    bt = 60 / bpm
    bar = 4 * bt
    prog = [(50, [62, 66, 69]), (55, [59, 62, 67]), (52, [61, 64, 69]), (50, [62, 66, 69])]
    nb = int((b - a) / bar) + 1
    for i in range(nb):
        t0 = a + i * bar
        if t0 >= b:
            break
        root, ch = prog[i % 4]
        warm = t0 >= 176
        add('music', pad(ch, bar + .5, 1600 if warm else 2200, 1, .2), t0, .15, rev=.45)
        add('music', saw(mtof(root - 12), int(bar * SR), 380, 1, 0, 10) * env_adsr(int(bar * SR), .02, .3, .6, .2), t0, .2)
        for s in range(8):
            add('music', dutar(mtof(ch[[0, 1, 2, 1][s % 4]] + 12), .5, .6, .994), t0 + s * bt / 2, .2, pan=.35 * (-1) ** s, rev=.3)
        if not warm:
            add('drums', doira_dum(), t0, .3)
            add('drums', doira_tak(), t0 + bt, .25, pan=-.3)
            add('drums', doira_dum(), t0 + bt * 2, .25)
            add('drums', doira_tak(), t0 + bt * 3, .25, pan=.3)
    t = 188.0
    for m, ln in [(74, 1), (76, .5), (78, .5), (81, 1.5), (78, .5), (76, 1), (74, 2)]:
        add('music', nay(mtof(m), ln * .7 + .1), t, .28, rev=.5)
        t += ln * .7


def music_end():
    a, b = SEC['end']
    add('music', choir([50, 57, 62, 66, 69, 74], 6.5, 'a', 1.4), a, .5, rev=.7)
    add('music', pad([50, 57, 62, 66, 69], 6.5, 2600, 1, .05), a, .35, rev=.5)
    for i, (m, ln) in enumerate([(62, .3), (69, .3), (67, .2), (69, .6), (74, 2.4)]):
        add('music', karnay(mtof(m), ln + .3), a + [0, .3, .6, .8, 1.4][i], .45, rev=.4)
    add('drums', taiko(1.2), a, .7, rev=.4)


for fn in (music_prologue, music_morning, music_bully, music_night, music_transform, music_crisis, music_battle, music_dawn, music_epilogue, music_end):
    fn()
    print('музыка:', fn.__name__)

for ev in cues['sfx']:
    x, rv = sfx(ev['type'])
    gain = {'quake': .8, 'rumble': .6, 'roar': .5, 'impact': .9, 'boom': .9, 'gong': .55, 'wind': .5, 'crickets': .6}.get(ev['type'], .6)
    add('sfx', x, ev['t'], gain, pan=0, rev=rv * .5)
print('шумы:', len(cues['sfx']))


# ---------------- голоса ----------------
def read_wav(p):
    with wave.open(p) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768
    return x


vox_env = np.zeros(N)
for ln in cues['lines']:
    p = os.path.join(HERE, 'out', 'voices', ln['id'] + '.wav')
    if not os.path.exists(p):
        print('нет голоса', ln['id'])
        continue
    x = read_wav(p)
    pan = {'nilufar': .12, 'bahodir': -.12, 'sardor': -.25, 'humo': 0, 'dev': 0}.get(ln['who'], 0)
    g = {'jasurVO': .95, 'dev': 1.05, 'humo': 1.0}.get(ln['who'], 1.0) * (1.45 if ln['id'] == 'd10' else 1.0)
    add('voice', x, ln['t'], g, pan=pan)
    i0 = int(ln['t'] * SR)
    vox_env[i0:i0 + len(x)] = np.maximum(vox_env[i0:i0 + len(x)], 1)

# ---------------- сведение ----------------
# ревербератор
ir_n = int(2.8 * SR)
ir = rs.standard_normal(ir_n) * np.exp(-tt(ir_n) * 2.6)
ir = fft_filter(ir, lo=200, hi=6500)
ir /= np.sqrt((ir ** 2).sum())
wetL = conv(SEND[0], ir)[:N]
wetR = conv(SEND[1], np.roll(ir, 211))[:N]

# дакинг музыки под голос: сглаженная огибающая
k = int(0.25 * SR)
sm = np.convolve(vox_env, np.ones(k) / k, 'same')
duck = 1 - 0.62 * np.clip(sm, 0, 1)
mus = (BUS['music'] + BUS['drums'] * 0.9) * duck
mus[0] += wetL * 0.45 * duck
mus[1] += wetR * 0.45 * duck
fx = BUS['sfx'] * (1 - 0.5 * np.clip(sm, 0, 1))
mix = mus * 0.62 + fx * 0.8 + BUS['voice'] * 1.15
# контроль: насколько голос громче фона в репликах
bg = mus * 0.62 + fx * 0.8
vo = BUS['voice'] * 1.15
rat = []
for ln in cues['lines']:
    a_, b_ = int(ln['t'] * SR), int((ln['t'] + ln['dur']) * SR)
    rv = np.sqrt((vo[:, a_:b_] ** 2).mean()) + 1e-9
    rb = np.sqrt((bg[:, a_:b_] ** 2).mean()) + 1e-9
    rat.append((20 * np.log10(rv / rb), ln['id']))
rat.sort()
print('голос/фон, дБ (худшие):', ', '.join(f'{i} {r:.1f}' for r, i in rat[:6]), '| медиана', f'{np.median([r for r, _ in rat]):.1f}')
# мягкий лимитер
peak = np.max(np.abs(mix))
mix = np.tanh(mix / max(peak, 1e-9) * 1.6) / np.tanh(1.6) * 0.95
mix = mix[:, :int(DUR * SR)]
fade = int(1.5 * SR)
mix[:, -fade:] *= np.linspace(1, 0, fade)
out = os.path.join(HERE, 'out', 'mix.wav')
with wave.open(out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(mix.T, -1, 1) * 32767).astype(np.int16).tobytes())
print('готово:', out)
