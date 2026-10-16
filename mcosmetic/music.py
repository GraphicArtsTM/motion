"""Саундтрек ролика M Cosmetic «Mega chegirma»: 16 секунд, 120 BPM, фа-диез минор.

Всё синтезируется с нуля на numpy (без сэмплов): поп-хаус грув — бочка, клэп,
хэты, шейкер, бас, плаки и суперсо-аккорды, хук-мелодия на дропе, колокольчики
«блеска». Эффекты привязаны к событиям в кадре (см. motion.js): удары надписей,
перелистывание календаря, «поп» товаров, всасывание перед дропом, касса на −50%.
Музыка приглушается под голос (сайдчейн от огибающей голоса), голос подмешивается сюда же.

    python3 music.py assets/voice.wav out/soundtrack.wav
"""
import sys
import wave
import numpy as np

SR = 44100
BPM = 120
BEAT = 60 / BPM          # 0,5 с
BAR = BEAT * 4           # 2 с
G0 = 0.1                 # первая доля сетки (такты на 0,1 + 2n)
VO = 1.0                 # голос стартует с 1,0 с
DUR = 16.0
N = int((DUR + 2.0) * SR)

L = np.zeros(N)
R = np.zeros(N)
BUS = {k: [np.zeros(N), np.zeros(N)] for k in ('drums', 'bass', 'music', 'fx')}
SEND = [np.zeros(N), np.zeros(N)]   # посыл на реверберацию
rs = np.random.default_rng(25)


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


# ---------- новые голоса ----------
def pluck(m, len_=0.32, bright=4200, amp=1.0):
    """Поп-плак: пила с быстро закрывающимся фильтром."""
    n = int(len_ * SR)
    fc = 500 + bright * np.exp(-tt(n) * 16)
    x = saw_add(mtof(m), n, fc, voices=2, detune=12, maxh=36) * adsr(n, 0.002, 0.12, 0.25, 0.06)
    return x * amp


def supersaw(m, len_, fc=2600, a=0.01, r=0.3):
    n = int(len_ * SR)
    return saw_add(mtof(m), n, fc, voices=5, detune=22, maxh=30) * adsr(n, a, 0.4, 0.75, r)


def shaker():
    n = int(0.07 * SR)
    t = tt(n)
    return fft_filter(noise(n), lo=6000, order=2) * np.sin(np.pi * np.minimum(1, t / 0.07)) ** 2


def pop(f=600):
    """Мягкий «чпок» появления (товары, стикеры)."""
    n = int(0.12 * SR)
    t = tt(n)
    ff = f * (1 + 1.6 * np.exp(-t * 50))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t * 32)


def thump():
    """Удар надписи: короткий бас-пинок + щелчок."""
    n = int(0.3 * SR)
    t = tt(n)
    f = 60 + 140 * np.exp(-t * 35)
    return np.tanh(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 14) * 1.8) + fft_filter(noise(n), lo=2500) * np.exp(-t * 120) * 0.4


def page_flip():
    """Перелистывание листа календаря: шорох с трепетом."""
    n = int(0.28 * SR)
    t = tt(n)
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * 38 * t)
    env = np.sin(np.pi * t / 0.28) ** 1.2 * flutter
    return tv_band(noise(n), lambda s: 1500 + 5000 * s / 0.28, bw=0.9) * env


def ting(f=2800, len_=0.9):
    n = int(len_ * SR)
    t = tt(n)
    return sum(a * np.sin(2 * np.pi * f * k * t) * np.exp(-t * d) for k, a, d in ((1, 1, 5), (2.01, .35, 9), (3.98, .15, 14)))


def tick():
    n = int(0.03 * SR)
    t = tt(n)
    return np.sin(2 * np.pi * 2600 * t) * np.exp(-t * 260) + fft_filter(noise(n), lo=3000) * np.exp(-t * 400) * 0.4


def suck(len_=0.3):
    """Всасывание перед дропом: обратный шум с падающим фильтром."""
    n = int(len_ * SR)
    t = tt(n)
    x = tv_band(noise(n), lambda s: 8000 * (0.08 ** (s / len_)), bw=0.6)
    return x * (t / len_) ** 2


# ---------- аранжировка ----------
b = lambda k: G0 + k * BEAT           # доля k
CH = {'F#m': [54, 57, 61], 'D': [54, 57, 62], 'A': [52, 57, 61], 'E': [52, 56, 59]}
ROOT = {'F#m': 30, 'D': 26, 'A': 33, 'E': 28}
PROG = ['F#m', 'D', 'A', 'E', 'F#m', 'D', 'A', 'E']     # такты 0,1 / 2,1 / … / 14,1
KICKS = []


def chord(t):
    return PROG[min(7, max(0, int((t - G0) // BAR)))]


def groove(t0, t1, full=False):
    """Грув по долям в интервале [t0, t1)."""
    k0 = int(np.ceil((t0 - G0) / BEAT - 1e-6))
    k = k0
    while b(k) < t1 - 1e-6:
        tb = b(k)
        c = chord(tb)
        bi = k % 4
        add('drums', kick(1.0), tb, 0.9); KICKS.append(tb)
        if bi in (1, 3):
            add('drums', clap(), tb, 0.75, rev=0.25)
        add('drums', hat(False), tb + BEAT / 2, 0.32, pan=0.25)
        if full:
            add('drums', hat(True), tb + BEAT / 2, 0.22, pan=-0.2)
            for s in (1, 3):
                add('drums', hat(False), tb + s * BEAT / 4, 0.16, pan=-0.3)
        add('drums', shaker(), tb + BEAT / 4, 0.18, pan=0.45)
        add('drums', shaker(), tb + 3 * BEAT / 4, 0.14, pan=0.45)
        # бас: восьмые на слабую, октава на 4-ю
        m = ROOT[c] + 12 + (12 if bi == 3 and full else 0)
        n = int(0.22 * SR)
        x = saw_add(mtof(m), n, 300 + 1300 * np.exp(-tt(n) * 20), voices=2, detune=8, maxh=40) * adsr(n, 0.003, 0.08, 0.6, 0.04)
        x += np.sin(2 * np.pi * mtof(m) * tt(n)) * adsr(n, 0.003, 0.2, 0.8, 0.04) * 0.9
        add('bass', x, tb + BEAT / 2, 0.42)
        # плаки-аккорды на офф-биты
        for j, mm in enumerate(CH[c]):
            add('music', pluck(mm + 12, 0.3, 3800 if full else 2600), tb + BEAT / 2, 0.075, pan=(j - 1) * 0.45, rev=0.25)
        k += 1


# — интро 0–0,6: подсос в первый удар —
add('fx', riser(0.6, 400, 9000), 0.0, 0.5)
rc = crash(0.8)[::-1]
add('fx', rc, 0.6 - len(rc) / SR, 0.35)
add('fx', whoosh(0.35, False), 0.15, 0.35, pan=0.1)
add('fx', pop(520), 0.62, 0.0)

# — сцена 2: 0,6–4,1 —
add('fx', boom(1.8), 0.6, 0.9)
add('fx', crash(2.2), 0.6, 0.5, rev=0.5)
add('fx', thump(), 0.6, 0.6)
add('fx', thump(), 0.85, 0.45)
add('drums', snare(0.8), 0.85, 0.4, rev=0.3)
groove(0.6, 3.85)
for c, t0 in (('F#m', 0.6), ('D', 2.1)):            # пэд под первым куплетом
    for mm in CH[c]:
        add('music', supersaw(mm + 12, 2.0 if t0 > 1 else 1.5, 1800, 0.12, 0.5), t0, 0.03, pan=rs.uniform(-.6, .6), rev=0.5)
add('fx', whoosh(0.35, True), 1.05, 0.3, pan=-0.2)
for t0 in (1.6, 2.6):                                  # календарь «25», «26»
    add('fx', page_flip(), t0 - 0.06, 0.5, pan=0.15 if t0 > 2 else -0.15, rev=0.15)
    add('fx', thump(), t0, 0.5)
    add('fx', bell(mtof(85 if t0 < 2 else 88), 0.9), t0, 0.1, rev=0.5)
add('fx', whoosh(0.3, False), 3.3, 0.35)
add('fx', thump(), 3.6, 0.6)
add('fx', boom(1.0), 3.6, 0.45)
for k in range(4):                                     # сбивка на переход
    add('drums', snare(0.5 + 0.15 * k), 3.85 + k * BEAT / 4, 0.45, pan=0.15 * (-1) ** k)
add('fx', whoosh(0.3, True), 3.82, 0.55, rev=0.2)

# — сцена 3: 4,1–6,85 — бренд —
add('fx', boom(1.6), 4.1, 0.7)
add('fx', crash(2.0), 4.1, 0.4, rev=0.6)
for i, mm in enumerate((73, 76, 78, 81, 85, 88)):   # блеск логотипа
    add('fx', bell(mtof(mm + 12) / 2, 1.2), 4.15 + i * 0.06, 0.13, pan=-0.5 + 0.2 * i, rev=0.6)
groove(4.1, 6.85)
for mm in CH['A']:
    add('music', supersaw(mm + 12, 2.2, 2000, 0.05, 0.6), 4.1, 0.03, pan=rs.uniform(-.6, .6), rev=0.5)
for i in range(4):                                     # товары влетают
    add('fx', whoosh(0.22, True), 4.42 + i * 0.09, 0.18, pan=(-0.6, 0.6, -0.4, 0.4)[i])
    add('fx', pop(480 + 60 * i), 4.62 + i * 0.09, 0.3, pan=(-0.6, 0.6, -0.4, 0.4)[i], rev=0.2)
for t0 in (4.96, 5.32, 5.64):                          # SIZGA / MAXSUS / NARXLAR
    add('fx', thump(), t0, 0.42)
for t0, f in ((4.45, 3100), (4.62, 3500), (4.85, 2900), (5.7, 3300)):
    add('fx', ting(f), t0, 0.07, pan=rs.uniform(-.6, .6), rev=0.6)
# мелодическая фраза над словами
for i, (bt, mm) in enumerate([(0, 69), (0.5, 73), (1, 76), (1.5, 78), (2.5, 76), (3, 73), (3.5, 76)]):
    add('music', pluck(mm + 12, 0.5, 5200), 5.1 + bt * BEAT, 0.11, pan=0.2 * np.sin(i), rev=0.45)

# — сцена 4: 6,85–8,1 — билд —
add('fx', whoosh(0.45, True), 6.75, 0.55, pan=0.0, rev=0.2)
groove(6.1, 7.85)
add('fx', riser(1.75, 300, 12000), 6.25, 0.6, rev=0.2)
add('fx', thump(), 6.94, 0.45)
add('fx', thump(), 7.56, 0.45)
for i in range(7):                                     # стикеры «%»
    add('fx', pop(700 + 70 * i), 7.0 + i * 0.06 + 0.05, 0.22, pan=-0.6 + 0.2 * i)
roll = [7.1 + k * 0.125 for k in range(4)] + [7.6 + k * 0.0625 for k in range(4)]
for k, tk in enumerate(roll):
    add('drums', snare(0.35 + 0.65 * k / len(roll)), tk, 0.45, pan=0.1 * (-1) ** k)
for mm in CH['E']:
    n = int(1.8 * SR)
    fc = 800 + 5000 * np.linspace(0, 1, n) ** 2
    x = saw_add(mtof(mm + 12), n, fc, voices=4, detune=20, maxh=30) * adsr(n, 0.3, 1.0, 0.9, 0.05)
    add('music', x, 6.1, 0.035, pan=rs.uniform(-.6, .6), rev=0.4)
add('fx', suck(0.28), 7.82, 0.6)
rc = crash(0.6)[::-1]
add('fx', rc, 8.1 - len(rc) / SR, 0.4)

# — дроп 8,1–12,1 —
add('fx', boom(2.4), 8.1, 1.0)
add('fx', crash(2.8), 8.1, 0.6, rev=0.6)
for i, mm in enumerate((78, 81, 85, 90)):              # «касса»
    add('fx', bell(mtof(mm + 12), 1.2), 8.14 + i * 0.03, 0.12, pan=-0.3 + 0.2 * i, rev=0.5)
for i in range(10):
    add('fx', coin(2300 + 170 * (i % 5)), 8.2 + i * 0.045, 0.06, pan=-0.5 + 0.1 * i, rev=0.3)
for i in range(9):                                     # счётчик 0→50
    add('fx', tick(), 8.1 + 0.42 * (1 - (1 - i / 9) ** 0.35), 0.25, pan=0.1)
groove(8.1, 12.1, full=True)
for c, t0 in (('F#m', 8.1), ('D', 10.1)):
    for mm in CH[c] + [CH[c][0] + 12]:
        add('music', supersaw(mm + 12, 2.0, 2600, 0.01, 0.3), t0, 0.032, pan=rs.uniform(-.7, .7), rev=0.45)
HOOK = [(0, 73, .5), (.5, 73, .5), (1, 71, .5), (1.5, 69, .5), (2, 71, 1), (3, 69, .5), (3.5, 66, .5),
        (4, 69, .5), (4.5, 69, .5), (5, 68, .5), (5.5, 66, .5), (6, 68, 1), (7, 64, .5), (7.5, 66, .5)]
for base in (8.1, 10.1):
    for bt, mm, ln in HOOK:
        if base == 10.1 and bt >= 4:
            mm = {69: 69, 68: 69, 66: 66, 64: 64}.get(mm, mm)
        add('music', pluck(mm + 12, ln * BEAT + 0.15, 5600), base + bt * BEAT, 0.16, pan=0.1, rev=0.4)
        add('music', bell(mtof(mm + 24), 0.5), base + bt * BEAT, 0.025, pan=-0.2, rev=0.5)
add('fx', thump(), 9.04, 0.55)
add('fx', boom(1.0), 9.04, 0.4)
add('drums', clap(), 9.04, 0.5, rev=0.4)
add('fx', whoosh(0.3, True), 9.92, 0.4, pan=0.3)
add('fx', whoosh(0.45, False), 10.05, 0.45, pan=-0.4, rev=0.2)
for i in range(7):                                     # полка с товарами
    add('fx', pop(560 + 50 * i), 10.15 + i * 0.05, 0.18, pan=-0.6 + 0.2 * i)
for t0, f in ((8.42, 3400), (8.58, 3000), (9.3, 3200), (11.2, 3100), (11.6, 3500)):
    add('fx', ting(f), t0, 0.06, pan=rs.uniform(-.6, .6), rev=0.6)

# — финал 12,1–16 —
groove(12.1, 14.1, full=True)
add('fx', whoosh(0.4, True), 12.25, 0.5, rev=0.2)
add('fx', boom(2.2), 12.6, 0.6)
add('fx', crash(2.6), 12.6, 0.5, rev=0.6)
for i, mm in enumerate((69, 73, 76, 81, 85, 88)):
    add('fx', bell(mtof(mm + 12) / 2, 1.3), 12.68 + i * 0.05, 0.12, pan=-0.5 + 0.2 * i, rev=0.6)
for mm in CH['A'] + [57 + 12]:
    add('music', supersaw(mm + 12, 1.6, 2400, 0.01, 0.4), 12.1, 0.03, pan=rs.uniform(-.6, .6), rev=0.5)
add('fx', thump(), 12.95, 0.45)
add('fx', whoosh(0.4, True), 13.45, 0.3, pan=0.5)
add('fx', pop(420), 13.6, 0.4, pan=0.5, rev=0.2)
add('fx', pop(640), 13.9, 0.35, rev=0.2)
for t0, f in ((13.15, 3300), (13.45, 2900), (14.1, 3600), (14.8, 3100)):
    add('fx', ting(f), t0, 0.06, pan=rs.uniform(-.6, .6), rev=0.6)
add('fx', click(3400), 14.9, 0.45, rev=0.2)
# финальный аккорд A (вместо E в 8-м такте — разрешение)
add('drums', kick(1.1), 14.1, 0.95); KICKS.append(14.1)
add('fx', boom(2.0), 14.1, 0.45)
add('fx', crash(2.4), 14.1, 0.4, rev=0.7)
for mm in [45, 52, 57, 61, 64, 69]:
    add('music', supersaw(mm + 12, 2.0, 2200, 0.02, 1.2), 14.1, 0.032, pan=rs.uniform(-.7, .7), rev=0.7)
n = int(1.9 * SR)
add('bass', np.sin(2 * np.pi * mtof(33) * tt(n)) * adsr(n, 0.01, 0.8, 0.6, 1.0), 14.1, 0.55)
for i, mm in enumerate([69, 73, 76, 81, 76, 81, 85]):
    add('music', pluck(mm + 12, 0.6, 5000), 14.1 + i * BEAT / 2, 0.12, pan=0.4 * np.sin(i * 1.3), rev=0.6)
for k, tk in enumerate((14.6, 15.1, 15.6)):
    add('drums', kick(0.6), tk, 0.5); KICKS.append(tk)
    add('drums', hat(True), tk + 0.25, 0.12)

# ---------- голос ----------
voice_path = sys.argv[1] if len(sys.argv) > 1 else 'assets/voice.wav'
with wave.open(voice_path, 'rb') as w:
    vs = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float) / 32768
    if w.getnchannels() == 2:
        vs = vs.reshape(-1, 2).mean(1)
    assert w.getframerate() == SR
vs = fft_filter(vs, lo=85, order=2)
# лёгкая компрессия: огибающая 10 мс, кнее −24 дБ, 3:1
env = np.sqrt(np.convolve(vs ** 2, np.ones(441) / 441, 'same')) + 1e-6
db = 20 * np.log10(env)
gr = np.where(db > -24, (db + 24) * (1 - 1 / 3), 0)
vs = vs * 10 ** (-gr / 20)
vs /= np.max(np.abs(vs)) + 1e-9
VOICE = np.zeros(N)
i0 = int(VO * SR)
VOICE[i0:i0 + len(vs)] = vs[:N - i0]

# ---------- сведение ----------
t = tt(N)
side = np.ones(N)
for k in KICKS:
    i = int(k * SR)
    seg = np.arange(N - i) / SR
    m = min(len(seg), int(0.4 * SR))
    side[i:i + m] = np.minimum(side[i:i + m], 1 - 0.7 * np.exp(-seg[:m] / 0.09))
for ch in (0, 1):
    BUS['bass'][ch] *= side
    BUS['music'][ch] *= 0.6 + 0.4 * side

# приглушение под голос: сглаженная огибающая голоса (атака 30 мс, спад 250 мс)
venv = np.abs(VOICE)
blk = 441
e = venv[:len(venv) // blk * blk].reshape(-1, blk).max(1)
sm = np.zeros_like(e)
for j in range(1, len(e)):
    a = 0.55 if e[j] > sm[j - 1] else 0.04
    sm[j] = sm[j - 1] + a * (e[j] - sm[j - 1])
sm = np.clip(sm / (np.percentile(sm[sm > 0.01], 90) + 1e-9), 0, 1)
duck = np.ones(N)
duck[:len(sm) * blk] = 1 - 0.5 * np.repeat(sm, blk)    # до −6 дБ
duck_fx = 1 - 0.35 * (1 - duck) / 0.5                    # эффекты приглушаем слабее


def reverb(xl, xr, length=2.2, damp=6000):
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
gains = {'drums': 1.0, 'bass': 0.8, 'music': 1.6, 'fx': 0.85}
for ch, o in ((0, L), (1, R)):
    for k, g in gains.items():
        o += BUS[k][ch] * g * (duck_fx if k == 'fx' else duck)
    o += (rl, rr)[ch] * 0.55 * duck

mus = np.stack([fft_filter(L, lo=28), fft_filter(R, lo=28)])
mus /= np.max(np.abs(mus)) + 1e-9
mus = np.tanh(mus * 1.6) / np.tanh(1.6)
mix = mus * 0.42 + VOICE[None, :] * 0.62                # голос впереди
fade = np.clip((DUR - t) / 0.8, 0, 1) ** 2
mix *= fade
mix = mix[:, :int(DUR * SR)]
mix *= 0.89 / np.max(np.abs(mix))

out = sys.argv[2] if len(sys.argv) > 2 else 'out/soundtrack.wav'
pcm = (mix.T * 32767).astype('<i2')
with wave.open(out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('готово:', out)
