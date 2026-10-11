"""Саундтрек для ролика Maxway — KLABJON 1+1: 30 секунд, 120 BPM, фа мажор.

Всё синтезируется с нуля на numpy (без сэмплов): хаус-грув (бочка, клэп, хэты),
офбит-бас с сайдчейном, синт-стэбы, щипковая мелодия-хук, райзеры и удары,
плюс звуки интерфейса, привязанные к событиям в кадре (см. motion.js).

    python3 music.py out/music.wav
"""
import sys
import wave
import numpy as np

SR = 44100
BPM = 120
BEAT = 60 / BPM          # 0,5 с
BAR = BEAT * 4           # 2 с
DUR = 30.0
N = int((DUR + 3.0) * SR)

L = np.zeros(N)
R = np.zeros(N)
BUS = {k: [np.zeros(N), np.zeros(N)] for k in ('drums', 'bass', 'music', 'fx')}
SEND = [np.zeros(N), np.zeros(N)]   # посыл на реверберацию
rs = np.random.default_rng(11)


# ---------- утилиты ----------
def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def add(bus, sig, t0, gain=1.0, pan=0.0, rev=0.0):
    """Кладёт моно-сигнал в шину с панорамой (-1..1) и посылом в ревер."""
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
    H = np.ones_like(f)
    if hi:
        H /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        H /= np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(X * H, M)[:n]


def tv_band(x, fc_at, bw=0.6, block=2048):
    """Полосовой фильтр с меняющейся частотой (overlap-add по блокам)."""
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


def noise(n):
    return rs.standard_normal(n)


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.1):
    t = tt(n)
    dur = n / SR
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip((dur - t) / max(r, 1e-6), 0, 1)
    return e * rel


# ---------- барабаны ----------
def kick(amp=1.0, tail=0.45):
    n = int(tail * SR)
    t = tt(n)
    f = 46 + (170 - 46) * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 7.5)
    click = fft_filter(noise(n) * np.exp(-t * 900), lo=2500) * 0.35
    return np.tanh((body + click) * 1.6) * amp


def clap():
    n = int(0.35 * SR)
    t = tt(n)
    env = np.zeros(n)
    for k, d in enumerate((0.0, 0.011, 0.022)):
        env += np.where(t >= d, np.exp(-(t - d) * (180 if k < 2 else 22)), 0)
    return fft_filter(noise(n), lo=900, hi=4200) * env * 0.9


def snare(amp=1.0):
    n = int(0.25 * SR)
    t = tt(n)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
    nz = fft_filter(noise(n), lo=1500, hi=9000) * np.exp(-t * 22)
    return (tone * 0.5 + nz * 0.8) * amp


def hat(open_=False):
    n = int((0.32 if open_ else 0.06) * SR)
    t = tt(n)
    return fft_filter(noise(n), lo=7000, order=3) * np.exp(-t * (11 if open_ else 70))


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
    x = fft_filter(noise(n), lo=3500, order=2) * np.exp(-t * 2.2)
    shimmer = sum(np.sin(2 * np.pi * f * t + rs.random() * 6) for f in (3170, 4410, 5230, 6890)) * 0.05 * np.exp(-t * 3)
    return x + shimmer


def boom(len_=2.0):
    n = int(len_ * SR)
    t = tt(n)
    f = 28 + 60 * np.exp(-t * 6)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.6)
    body = fft_filter(noise(n), hi=400) * np.exp(-t * 5) * 0.7
    return np.tanh((sub + body) * 2.2)


def riser(len_, f0=300, f1=9000, amp=1.0):
    n = int(len_ * SR)
    t = tt(n)
    k = t / len_
    x = tv_band(noise(n), lambda s: f0 * (f1 / f0) ** min(1, s / len_) ** 1.4, bw=0.5)
    tone_f = 180 + 900 * k ** 2
    tone = np.sin(2 * np.pi * np.cumsum(tone_f) / SR + 3 * np.sin(2 * np.pi * 6 * t)) * 0.18
    env = k ** 2.2
    return (x * 1.4 + tone) * env * amp


def whoosh(len_=0.5, up=True):
    n = int(len_ * SR)
    t = tt(n)
    k = t / len_
    x = tv_band(noise(n), lambda s: (400 * (12 ** (s / len_)) if up else 5000 * (0.1 ** (s / len_))), bw=0.7)
    return x * np.sin(np.pi * k) ** 1.5


def click(f=3800):
    n = int(0.05 * SR)
    t = tt(n)
    return np.sin(2 * np.pi * f * t) * np.exp(-t * 260) + fft_filter(noise(n), lo=3000) * np.exp(-t * 400) * 0.6


def blip(f=1320):
    n = int(0.16 * SR)
    t = tt(n)
    ff = f * (1 + 0.5 * np.exp(-t * 60))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR + 1.5 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 30)) * np.exp(-t * 26)


def bell(f, len_=1.4):
    n = int(len_ * SR)
    t = tt(n)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.2 * np.exp(-t * 4)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 3.2) + 0.3 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 6)


def coin(f):
    n = int(0.3 * SR)
    t = tt(n)
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d) for r, a, d in ((1, 1, 14), (2.76, .5, 20), (5.4, .25, 30)))


def keytick():
    n = int(0.04 * SR)
    t = tt(n)
    return fft_filter(noise(n), lo=2000, hi=8000) * np.exp(-t * 300) + np.sin(2 * np.pi * 1900 * t) * np.exp(-t * 200) * .4


# ---------- тональные ----------
def dutar(freq, len_=1.2, bright=0.6, decay=0.9965):
    """Щипковая струна (Karplus–Strong) с дробной настройкой через ресемплинг."""
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
    body = fft_filter(out, lo=180, hi=5200)
    t = tt(n)
    return body * np.minimum(1, (len_ - t) / 0.05)


def saw_add(freq, n, fc, voices=1, detune=0.0, maxh=None):
    """Аддитивная пила с ограничением спектра (fc — массив или число)."""
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


# ---------- звуки интерфейса ----------
def pop(f=700):
    """Пузырьковый «поп» для всплывающих плашек."""
    n = int(0.12 * SR)
    t = tt(n)
    ff = f * (0.45 + 1.4 * np.exp(-t * 55))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t * 32)


def boing(f=190):
    n = int(0.6 * SR)
    t = tt(n)
    ff = f * (1 + 0.6 * np.exp(-t * 6) * np.sin(2 * np.pi * 14 * t)) * (1 + 0.5 * t)
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t * 5)


def fall_whistle():
    n = int(0.55 * SR)
    t = tt(n)
    ff = 1500 * np.exp(-t * 3.2)
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.minimum(1, t / 0.02) * np.exp(-t * 2) * 0.6


def squeak(len_=0.14):
    n = int(len_ * SR)
    t = tt(n)
    x = tv_band(noise(n), lambda s: 1800 + 5000 * s / len_, bw=0.25)
    return x * np.sin(np.pi * t / len_) * 1.6


def kaching():
    out = np.zeros(int(1.2 * SR))
    for i, f in enumerate((2637, 3136, 3951, 2637 * 2)):
        c = coin(f)
        out[int(i * 0.035 * SR):int(i * 0.035 * SR) + len(c)] += c * 0.5
    b = bell(1568, 1.1)
    out[:len(b)] += b * 0.5
    return out


# ---------- инструменты ----------
def stab(notes, len_=0.2, bright=3200, amp=1.0):
    n = int(len_ * SR)
    fc = 500 + bright * np.exp(-tt(n) * 16)
    x = sum(saw_add(mtof(m), n, fc, voices=2, detune=12, maxh=36) for m in notes)
    return x * adsr(n, 0.003, 0.08, 0.45, 0.05) * amp / len(notes) ** 0.5


def bass_note(m, len_=0.22):
    n = int(len_ * SR)
    fc = 260 + 1300 * np.exp(-tt(n) * 20)
    x = saw_add(mtof(m), n, fc, voices=2, detune=6, maxh=40) * adsr(n, 0.003, 0.1, 0.6, 0.04)
    x += np.sin(2 * np.pi * mtof(m) * tt(n)) * adsr(n, 0.003, 0.25, 0.85, 0.04) * 0.9
    return x


def lead(m, len_):
    """Мелодия-хук: щипок + мягкая пила сверху."""
    n = int((len_ + 0.35) * SR)
    pl = dutar(mtof(m), len_ + 0.35, 0.75, 0.9975)
    sw = saw_add(mtof(m), n, 2600, voices=2, detune=10, maxh=20) * adsr(n, 0.01, 0.2, 0.5, 0.15)
    return pl * 0.8 + sw * 0.35


def pad(notes, len_):
    n = int(len_ * SR)
    x = sum(saw_add(mtof(m + 12), n, 1600, voices=3, detune=16, maxh=22) for m in notes)
    return x * adsr(n, 0.15, 0.6, 0.75, 0.5) / len(notes)


# ---------- аранжировка ----------
CH = {'F': [53, 57, 60], 'Dm': [50, 53, 57], 'Bb': [46, 50, 53], 'C': [48, 52, 55]}
PROG = ['F', 'Dm', 'Bb', 'C']
KICKS = []


def chord_at(t):
    return PROG[int((t - 4) // BAR) % 4] if t >= 4 else 'F'


def groove_bar(bar0, drums=True, bass=True, stabs=True, hats=True, clap_on=True, padv=0.0, kick_amp=1.0):
    c = chord_at(bar0 + 0.01)
    root = CH[c][0] - 12
    for b in range(4):
        tb = bar0 + b * BEAT
        if drums:
            add('drums', kick(kick_amp), tb, 0.9); KICKS.append(tb)
            if clap_on and b in (1, 3):
                add('drums', clap(), tb, 0.75, rev=0.25)
        if hats:
            add('drums', hat(True), tb + BEAT / 2, 0.3, pan=0.3)
            for s in (1, 3):
                add('drums', hat(False), tb + s * BEAT / 4, 0.22, pan=-0.25)
        if bass:
            add('bass', bass_note(root + 12 if b % 2 else root), tb + BEAT / 2, 0.42)
            if b == 3:
                add('bass', bass_note(root + 12, 0.12), tb + BEAT * 0.75, 0.25)
    if stabs:
        notes = [m + 12 for m in CH[c]]
        for bt in (0.5, 1.5, 2.5, 3.25):
            add('music', stab(notes, 0.18), bar0 + bt * BEAT, 0.34, pan=0.25 if bt % 1 else -0.25, rev=0.2)
    if padv:
        add('music', pad(CH[c], BAR + 0.3), bar0, padv, rev=0.4)


MEL = [(0, 72, .5), (.5, 77, .5), (1, 79, .5), (1.5, 81, .75), (2.5, 79, .5), (3, 77, .5), (3.5, 74, .5),
       (4, 77, 1), (5, 72, .5), (5.5, 74, .5), (6, 77, .5), (6.5, 79, .5), (7, 81, .5), (7.5, 84, .5)]


def melody(t0, gain=0.42, upto=8):
    for bt, m, ln in MEL:
        if bt < upto:
            add('music', lead(m, ln * BEAT), t0 + bt * BEAT, gain, pan=0.08, rev=0.35)


# — Хук 0–2 с: КУПИ / ОДИН / ПОЛУЧИ / ДВА —
for i, (c, amp) in enumerate((('F', 1), ('F', 1), ('Bb', 1.1), ('C', 1.3))):
    t0 = i * BEAT
    add('drums', kick(1.05), t0, 0.95); KICKS.append(t0)
    add('music', stab([m + 12 for m in CH[c]] + [CH[c][0] + 24], 0.32, 4200), t0, 0.5 * amp, rev=0.3)
    n = int(0.4 * SR)
    add('bass', np.sin(2 * np.pi * mtof(CH[c][0] - 12) * tt(n)) * adsr(n, 0.003, 0.2, 0.5, 0.1), t0, 0.55)
    add('fx', fft_filter(noise(int(0.08 * SR)), lo=3000) * np.exp(-tt(int(0.08 * SR)) * 60), t0, 0.25)
for k in range(8):   # раскатка к 1+1
    add('drums', snare(0.3 + 0.7 * k / 7), 1.5 + k * BEAT / 8, 0.45, pan=0.15 * (-1) ** k)
add('fx', riser(0.5, 400, 9000), 1.5, 0.5)

# — 1+1 2–4 с: удар и полутемп —
add('fx', boom(2.0), 2.0, 1.0)
add('fx', crash(2.4), 2.0, 0.5, rev=0.4)
add('drums', kick(1.1), 2.0, 1.0); KICKS.append(2.0)
for i, t0 in enumerate((2.0, 2.25, 2.5)):
    add('fx', pop(620 + 180 * i), t0 + 0.04, 0.55, pan=(-0.3, 0, 0.3)[i])
for t0 in (2.75, 3.0, 3.25):
    add('drums', kick(0.8), t0, 0.7); KICKS.append(t0)
add('drums', clap(), 3.0, 0.7, rev=0.3)
add('music', pad(CH['F'], 2.0), 2.0, 0.22, rev=0.5)
for i in range(4):
    add('bass', bass_note(41 + (12 if i % 2 else 0), 0.3), 2.0 + i * BEAT, 0.4)
add('fx', whoosh(0.4, True), 2.72, 0.35, pan=-0.4)
add('fx', whoosh(0.4, True), 2.97, 0.35, pan=0.4)
add('fx', riser(1.0, 300, 11000), 3.0, 0.55)
for k in range(8):
    add('drums', snare(0.25 + 0.75 * k / 7), 3.5 + k * BEAT / 8, 0.45)
rc = crash(1.0)[::-1]
add('fx', rc, 4.0 - len(rc) / SR, 0.4)

# — Грув: 4–8, 10–22, 22–25 (тише), 25–28 —
for bar0 in (4, 6):
    groove_bar(bar0, padv=0.0)
melody(4.0, 0.42)
add('fx', boom(1.5), 4.0, 0.8)
add('fx', crash(2.2), 4.0, 0.45, rev=0.4)
for k in range(7):
    add('fx', blip(1400 + 120 * k), 4.0 + k * 0.05, 0.12, pan=-0.6 + 0.2 * k)
add('fx', whoosh(0.5, True), 4.3, 0.4)
for i in range(7):
    add('fx', pop(560 + 70 * i), 5.06 + i * 0.25, 0.42, pan=(-0.45 if i % 2 == 0 else 0.45))
add('fx', boom(0.7), 6.75, 0.5)
add('fx', pop(900), 6.85, 0.4)
add('fx', whoosh(0.45, False), 7.55, 0.45)
add('fx', riser(0.5, 500, 9000), 7.5, 0.35)

# — 8–10: брейк «КЛАБ-СЭНДВИЧ?» → удар KLABJON —
add('music', pad(CH['Dm'], 1.0), 8.0, 0.28, rev=0.5)
for k in range(4):
    add('drums', hat(False), 8.0 + k * BEAT / 2, 0.2)
add('drums', kick(0.8), 8.0, 0.6); KICKS.append(8.0)
add('fx', squeak(0.14), 8.5, 0.5, pan=-0.2)
add('fx', squeak(0.14), 8.62, 0.5, pan=0.2)
add('fx', fall_whistle(), 8.72, 0.5)
add('fx', boom(1.6), 9.0, 1.0)
add('fx', crash(2.0), 9.0, 0.5, rev=0.4)
add('drums', kick(1.1), 9.0, 1.0); KICKS.append(9.0)
add('music', stab([65, 69, 72, 77], 0.4, 4800), 9.0, 0.55, rev=0.35)
add('drums', kick(0.85), 9.5, 0.8); KICKS.append(9.5)
add('drums', clap(), 9.5, 0.6, rev=0.3)
add('fx', pop(800), 9.24, 0.45)
add('fx', riser(0.5, 400, 10000), 9.5, 0.4)
for k in range(4):
    add('drums', snare(0.4 + 0.6 * k / 3), 9.75 + k * BEAT / 4, 0.4)

for bar0 in (10, 12):
    groove_bar(bar0, padv=0.12)
for bar0 in (14, 16):
    groove_bar(bar0)
melody(14.0, 0.4)
for bar0 in (18, 20):
    groove_bar(bar0, padv=0.1)
for bar0 in (22,):
    groove_bar(bar0, stabs=False, padv=0.18)
groove_bar(24, stabs=False, clap_on=False)

# события 10–14 (приложение)
add('fx', whoosh(0.6, True), 9.85, 0.4)
add('fx', click(4200), 11.0, 0.6, rev=0.2); add('fx', click(1600), 11.03, 0.4)
add('fx', pop(700), 11.58, 0.5, pan=-0.5)
add('fx', click(4200), 12.0, 0.65, rev=0.2); add('fx', click(1500), 12.03, 0.45)
add('fx', whoosh(0.4, True), 12.05, 0.3, pan=-0.2)
add('fx', coin(2637), 12.5, 0.3, pan=-0.2, rev=0.3)
add('fx', bell(1568, 1.0), 13.0, 0.2, pan=0.4, rev=0.4)
add('fx', pop(840), 13.02, 0.5, pan=0.5)
add('fx', riser(0.45, 500, 11000), 13.55, 0.45)
add('fx', whoosh(0.45, True), 13.6, 0.4)
# 14–18 (корзина)
add('fx', crash(1.4), 14.0, 0.3, rev=0.3)
add('fx', whoosh(0.4, True), 14.05, 0.35)
add('fx', pop(600), 14.32, 0.4, pan=-0.3); add('fx', pop(680), 14.57, 0.4, pan=0.3)
add('fx', pop(900), 15.0, 0.5)
for i, m in enumerate((84, 88, 91, 96)):
    add('fx', bell(mtof(m), 1.0), 15.05 + i * 0.06, 0.12, pan=-0.4 + 0.25 * i, rev=0.5)
for i in range(8):
    add('fx', keytick(), 15.5 + i * 0.05, 0.35, pan=0.1 * (i % 3 - 1))
add('fx', kaching(), 15.9, 0.5, rev=0.3)
add('fx', boom(0.9), 15.9, 0.45)
add('fx', pop(760), 16.12, 0.45, pan=0.4)
add('fx', click(4200), 16.75, 0.6, rev=0.2); add('fx', click(1500), 16.78, 0.4)
add('fx', bell(1047, 1.0), 17.0, 0.18, rev=0.4); add('fx', bell(1568, 1.0), 17.1, 0.18, rev=0.4)
add('fx', whoosh(0.45, True), 17.55, 0.4)
# 18–22 (1+1 и бант)
add('fx', boom(0.8), 18.38, 0.6)
add('fx', whoosh(0.35, True), 18.48, 0.45, pan=0.5)
add('fx', pop(620), 18.57, 0.45, pan=-0.4); add('fx', pop(820), 18.72, 0.45, pan=0.4)
add('fx', boing(200), 19.3, 0.4, pan=0.3)
add('fx', pop(700), 19.27, 0.35, pan=0.4)
for t0 in (19.5, 19.75):
    add('music', stab([m + 12 for m in CH['Bb']] + [70], 0.25, 4000), t0, 0.4)
add('fx', whoosh(0.3, True), 19.85, 0.35)
add('fx', boom(1.8), 20.0, 0.9)
add('fx', crash(2.2), 20.0, 0.5, rev=0.4)
add('fx', pop(760), 20.32, 0.5, pan=-0.4)
add('fx', whoosh(0.45, False), 21.55, 0.45)
# 22–25 (доставка)
add('fx', whoosh(0.45, True), 21.85, 0.35)
add('fx', boom(0.5), 22.4, 0.45, pan=-0.3); add('fx', blip(900), 22.4, 0.2)
add('fx', boom(0.5), 22.55, 0.45, pan=0.3); add('fx', blip(1200), 22.55, 0.2)
for i in range(16):
    add('fx', keytick(), 22.4 + i * 0.056, 0.28, pan=0.3 * np.sin(i))
add('fx', bell(1760, 1.2), 23.72, 0.22, rev=0.5); add('fx', pop(820), 23.78, 0.4)
add('fx', whoosh(0.5, True), 23.95, 0.4, pan=0.5)
add('fx', riser(1.0, 300, 12000), 24.0, 0.55)
for k in range(8):
    add('drums', snare(0.3 + 0.7 * k / 7), 24.5 + k * BEAT / 8, 0.42)
rc = crash(1.0)[::-1]
add('fx', rc, 25.0 - len(rc) / SR, 0.45)

# — Финал 25–30 —
add('fx', boom(2.5), 25.0, 1.0)
add('fx', crash(3.0), 25.0, 0.55, rev=0.5)
for bar0 in (25.0, 27.0):
    groove_bar(bar0, padv=0.12)
melody(25.0, 0.4, upto=6)
for k in range(7):
    add('fx', blip(1500 + 120 * k), 25.5 + k * 0.04, 0.1, pan=-0.6 + 0.2 * k)
add('fx', pop(700), 25.92, 0.5)
add('fx', whoosh(0.45, True), 25.95, 0.35)
add('fx', boing(210), 26.65, 0.35, pan=0.3)
add('fx', pop(800), 26.62, 0.45)
add('fx', click(4200), 27.2, 0.6, rev=0.2); add('fx', click(1500), 27.23, 0.4)
add('drums', kick(1.0), 29.0, 0.9); KICKS.append(29.0)
add('music', stab([65, 69, 72, 77, 81], 1.4, 3000), 29.0, 0.5, rev=0.6)
add('fx', crash(2.0), 29.0, 0.35, rev=0.5)
n = int(1.4 * SR)
add('bass', np.sin(2 * np.pi * mtof(29) * tt(n)) * adsr(n, 0.005, 0.6, 0.5, 0.6), 29.0, 0.5)

# ---------- сведение ----------
t = tt(N)
side = np.ones(N)
for k in KICKS:
    i = int(k * SR)
    seg = np.arange(N - i) / SR
    m = min(len(seg), int(0.4 * SR))
    side[i:i + m] = np.minimum(side[i:i + m], 1 - 0.75 * np.exp(-seg[:m] / 0.09))
for ch in (0, 1):
    BUS['bass'][ch] *= side
    BUS['music'][ch] *= 0.55 + 0.45 * side


def reverb(xl, xr, length=2.4, damp=5000):
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


rl, rr = reverb(*SEND)
gains = {'drums': 1.0, 'bass': 0.95, 'music': 0.9, 'fx': 0.85}
for ch, o in ((0, L), (1, R)):
    for k, g in gains.items():
        o += BUS[k][ch] * g
    o += (rl, rr)[ch] * 0.6

mix = np.stack([L, R])
mix = fft_filter(mix[0], lo=28), fft_filter(mix[1], lo=28)
mix = np.stack(mix)
mix /= np.max(np.abs(mix)) + 1e-9
mix = np.tanh(mix * 1.8) / np.tanh(1.8)       # мягкая сатурация на мастере
fade = np.clip((DUR - t) / 0.5, 0, 1) ** 2      # затухание к концу ролика
mix *= fade
mix = mix[:, :int(DUR * SR)]
mix *= 0.89 / np.max(np.abs(mix))

out = sys.argv[1] if len(sys.argv) > 1 else 'music.wav'
pcm = (mix.T * 32767).astype('<i2')
with wave.open(out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('готово:', out)
