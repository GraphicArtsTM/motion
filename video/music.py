"""Саундтрек для промо-ролика Muhr: 32 секунды, 120 BPM, ре гармонический минор.

Всё синтезируется с нуля на numpy (без сэмплов): бочка, клэп, хэты, дойра,
щипковый «дутар» (Karplus–Strong), бас с сайдчейном, пэд, райзеры, удары и
звуки интерфейса, привязанные к событиям в кадре (см. motion.js).

    python3 music.py out/music.wav
"""
import sys
import wave
import numpy as np

SR = 44100
BPM = 120
BEAT = 60 / BPM          # 0,5 с
BAR = BEAT * 4           # 2 с
DUR = 32.0
N = int((DUR + 3.0) * SR)

L = np.zeros(N)
R = np.zeros(N)
BUS = {k: [np.zeros(N), np.zeros(N)] for k in ('drums', 'bass', 'music', 'fx')}
SEND = [np.zeros(N), np.zeros(N)]   # посыл на реверберацию
rs = np.random.default_rng(7)


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


# ---------- аранжировка ----------
D = 62  # ре первой октавы
HM = [0, 2, 3, 5, 7, 8, 11]            # гармонический минор
CH = {'Dm': [50, 53, 57], 'Bb': [46, 50, 53], 'Gm': [43, 46, 50], 'A': [45, 49, 52]}
DROP = ['Dm', 'Bb', 'Gm', 'A', 'Dm', 'Bb', 'Gm', 'A', 'Gm', 'A']   # такты 8–28 с
KICKS = []


def chord_at(t):
    if t < 8:
        return 'Dm' if t < 6 else 'Bb'
    if t >= 28:
        return 'Dm'
    return DROP[int((t - 8) // BAR)]


# — Хук 0–4 с: напряжение —
for b in range(8):
    t0 = b * BEAT
    if b in (0, 4):
        add('drums', kick(1.0), t0, 0.95); KICKS.append(t0)
    # пульс саб-баса восьмыми
    for h in (0, 0.25):
        n = int(0.2 * SR)
        f = mtof(38)
        add('bass', np.sin(2 * np.pi * f * tt(n)) * adsr(n, 0.004, 0.08, 0.4, 0.05), t0 + h, 0.5)
motif = [57, 58, 61, 62, 61, 58, 57, 55]  # A Bb C# D C# Bb A G
for i, m in enumerate(motif):
    add('music', dutar(mtof(m), 0.9, 0.5), i * BEAT, 0.42, pan=-0.25 + 0.5 * (i % 2), rev=0.35)
add('fx', boom(1.6), 2.0, 0.55)
add('drums', clap(), 2.0, 0.7, rev=0.3)
add('fx', riser(2.0, 250, 7000), 2.0, 0.45, rev=0.2)
# глитч 3,0–3,55: рубленые хэты и снейр
for k in range(9):
    add('drums', snare(0.6) * (1 if k % 2 else 0.6), 3.0 + k * BEAT / 8, 0.5, pan=(k % 3 - 1) * 0.5)
rev_cr = crash(1.2)[::-1]
add('fx', rev_cr, 4.0 - len(rev_cr) / SR, 0.5)

# — Раскрытие бренда 4–8 с —
add('fx', boom(2.4), 4.0, 1.0)
add('fx', crash(2.6), 4.0, 0.55, rev=0.5)
add('drums', kick(1.1), 4.0, 1.0); KICKS.append(4.0)
add('fx', click(4200), 4.62, 0.6, rev=0.3)
add('fx', click(1500), 4.66, 0.5)
for t0 in (6.0, 6.5, 7.0, 7.5):
    add('drums', kick(0.9), t0, 0.85); KICKS.append(t0)
for k in range(16):   # раскатка снейра к дропу
    tk = 7.0 + k * (1.0 / 16)
    add('drums', snare(0.25 + 0.75 * k / 15), tk, 0.45, pan=0.1 * ((-1) ** k))
add('fx', riser(2.0, 350, 11000), 6.0, 0.55, rev=0.2)
arp = [62, 69, 77, 76, 74, 69, 65, 64]
for i in range(16):
    t0 = 4.5 + i * BEAT / 2
    m = arp[i % 8] - (5 if t0 >= 6 else 0) + (0 if t0 < 6 else 1)
    add('music', dutar(mtof(m), 0.7, 0.55), t0, 0.28, pan=0.4 * np.sin(i), rev=0.4)
for c, t0, ln in (('Dm', 4.0, 2.0), ('Bb', 6.0, 2.0)):
    for m in CH[c] + [CH[c][0] + 12]:
        n = int((ln + 0.6) * SR)
        x = saw_add(mtof(m + 12), n, 2400, voices=3, detune=14, maxh=30) * adsr(n, 0.25, 0.6, 0.8, 0.6)
        add('music', x, t0, 0.07, pan=rs.uniform(-0.5, 0.5), rev=0.5)

# — Дроп 8–28 с —
for bi, c in enumerate(DROP):
    bar0 = 8 + bi * BAR
    root = CH[c][0] - 12
    for b in range(4):
        tb = bar0 + b * BEAT
        add('drums', kick(1.0), tb, 0.85); KICKS.append(tb)
        if b in (1, 3):
            add('drums', clap(), tb, 0.8, rev=0.22)
        add('drums', hat(True), tb + BEAT / 2, 0.34, pan=0.3)
        for s in range(4):
            if s != 2:
                add('drums', hat(False), tb + s * BEAT / 4, 0.26 + 0.1 * (s == 1), pan=-0.25)
        # дойра: дум-так
        if b == 0 or b == 2:
            add('drums', doira_dum(), tb + BEAT * 0.75, 0.35, pan=0.2)
        add('drums', doira_tak(), tb + BEAT * 0.25, 0.34, pan=-0.35)
        if b == 3:
            add('drums', doira_tak(), tb + BEAT * 0.625, 0.2, pan=0.35)
        # бас восьмыми, октавные скачки
        for h in range(2):
            m = root + (12 if (b * 2 + h) % 4 == 3 else 0)
            n = int(0.24 * SR)
            fc = 300 + 1500 * np.exp(-tt(n) * 18)
            x = saw_add(mtof(m), n, fc, voices=2, detune=8, maxh=40) * adsr(n, 0.003, 0.09, 0.6, 0.04)
            x += np.sin(2 * np.pi * mtof(m) * tt(n)) * adsr(n, 0.003, 0.2, 0.8, 0.04) * 0.8
            add('bass', x, tb + h * BEAT / 2, 0.36)
    # пэд аккорда
    for m in CH[c]:
        n = int((BAR + 0.4) * SR)
        x = saw_add(mtof(m + 12), n, 1800, voices=3, detune=16, maxh=24) * adsr(n, 0.08, 0.5, 0.75, 0.4)
        add('music', x, bar0, 0.045, pan=rs.uniform(-0.6, 0.6), rev=0.4)
    # арпеджио дутара шестнадцатыми
    tones = [CH[c][0] + 12, CH[c][1] + 12, CH[c][2] + 12, CH[c][0] + 24]
    pat = [0, 2, 3, 1, 2, 3, 1, 2]
    for s in range(16):
        ts = bar0 + s * BEAT / 2 if s < 8 else None
        if ts is None:
            break
        add('music', dutar(mtof(tones[pat[s]] + 0), 0.45, 0.65, 0.993), ts, 0.3, pan=0.35 * (1 if s % 2 else -1), rev=0.3)

# мелодия-хук (12–16 и 20–24 с)
MEL = [(0, 69, 1), (1, 70, .5), (1.5, 73, .5), (2, 74, 1.5), (3.5, 73, .5),
       (4, 70, 1), (5, 69, .5), (5.5, 67, .5), (6, 65, 1), (7, 64, .5), (7.5, 61, .5)]
for base in (12.0, 20.0):
    for bt, m, ln in MEL:
        add('music', dutar(mtof(m + 12), ln * BEAT + 0.6, 0.75, 0.9975), base + bt * BEAT, 0.46, pan=0.05, rev=0.45)
        add('music', dutar(mtof(m), ln * BEAT + 0.4, 0.5, 0.996), base + bt * BEAT + 0.012, 0.18, pan=-0.3, rev=0.3)

# события в кадре
add('fx', whoosh(0.55, True), 11.45, 0.5, pan=0.0, rev=0.2)
add('fx', crash(1.6), 12.0, 0.3, rev=0.3)
for i, t0 in enumerate((10.0, 10.5, 11.0)):
    add('fx', blip(1180 + 220 * i), t0, 0.3, pan=(-0.5, 0.5, -0.4)[i], rev=0.3)
for i in range(12):
    add('fx', coin(2400 + 180 * (i % 5)), 12.4 + i * 0.05 + 0.4, 0.07, pan=-0.6 + i * 0.05, rev=0.3)
add('fx', click(4000), 12.98, 0.7, rev=0.3)
add('fx', click(1400), 13.02, 0.6)
add('fx', boom(1.2), 13.0, 0.35)
add('fx', whoosh(0.5, True), 15.5, 0.5, pan=-0.3, rev=0.15)
for i, m in enumerate((74, 77, 81, 86)):
    add('fx', bell(mtof(m + 12) / 2, 1.2), 16.1 + i, 0.22, pan=-0.3 + 0.2 * i, rev=0.5)
add('fx', bell(mtof(86), 1.8), 19.3, 0.15, rev=0.6)
add('fx', whoosh(0.4, True), 19.75, 0.35)
add('fx', boom(1.0), 22.5, 0.5)
add('drums', clap(), 22.5, 0.6, rev=0.4)
add('fx', whoosh(0.45, False), 23.6, 0.4, pan=0.3)
for i in range(7):
    add('fx', keytick(), 24.5 + i * 0.25, 0.45, pan=-0.2 + 0.07 * i)
add('fx', whoosh(0.6, True), 26.05, 0.4, pan=-0.6)
for i, m in enumerate((69, 73, 76, 81)):
    add('fx', bell(mtof(m + 12), 1.4), 26.75 + i * 0.06, 0.16, pan=-0.3 + 0.2 * i, rev=0.5)
add('fx', riser(1.9, 300, 12000), 26.1, 0.5, rev=0.2)
for k in range(8):
    add('drums', snare(0.3 + 0.7 * k / 7), 27.5 + k * BEAT / 8, 0.42)
rev_cr = crash(1.0)[::-1]
add('fx', rev_cr, 28.0 - len(rev_cr) / SR, 0.45)

# — Финал 28–32 с —
add('fx', boom(3.0), 28.0, 1.0)
add('fx', crash(3.0), 28.0, 0.55, rev=0.6)
add('drums', kick(1.1), 28.0, 1.0); KICKS.append(28.0)
add('fx', click(4200), 28.55, 0.5, rev=0.3)
for t0 in (29.0, 29.5, 30.0, 30.5):
    add('drums', kick(0.8), t0, 0.6); KICKS.append(t0)
    add('drums', hat(True), t0 + 0.25, 0.14)
for m in CH['Dm'] + [62, 69]:
    n = int(4.5 * SR)
    x = saw_add(mtof(m + 12), n, 2000, voices=3, detune=14, maxh=28) * adsr(n, 0.05, 1.5, 0.7, 2.0)
    add('music', x, 28.0, 0.055, pan=rs.uniform(-0.6, 0.6), rev=0.6)
n = int(3.5 * SR)
add('bass', np.sin(2 * np.pi * mtof(38) * tt(n)) * adsr(n, 0.01, 1.2, 0.6, 1.5), 28.0, 0.5)
for i, m in enumerate([62, 65, 69, 74, 73, 69, 74]):
    add('music', dutar(mtof(m + 12), 1.4, 0.6, 0.998), 28.5 + i * BEAT / 2, 0.24, pan=0.4 * np.sin(i * 1.3), rev=0.55)
add('fx', bell(mtof(86), 2.5), 29.9, 0.12, rev=0.6)

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
fade = np.clip((DUR - t) / 0.6, 0, 1) ** 2      # затухание к концу ролика
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
