"""Саундтрек к ролику «Brend ruxsatnoma aksiyada» (Reels, 30 с): 128 BPM, ля гармонический минор.

Всё синтезируется на numpy, без сэмплов: хаус-грув (бочка, клэп, хэты, дойра),
офбит-бас с сайдчейном, стабы аккордов, щипковый «дутар» (Karplus–Strong),
а также звуки, привязанные к событиям в кадре (см. motion.js): проезд машины,
штампы, барабаны цифр, монеты, шорох документов, тиканье секундомера, звонок.
Пишет две дорожки: музыку (её build.sh приглушает под голосом) и звуковые эффекты
отдельно — эффекты не приглушаются, чтобы их было хорошо слышно.

    python3 music.py out/music.wav out/sfx.wav
"""
import sys
import wave
import numpy as np

SR = 44100
BPM = 128
BEAT = 60 / BPM          # 0,469 с
BAR = BEAT * 4           # 1,875 с
TA, G, RESUME = 8.3, 6.5, 8.6     # галерея фото брендирования (см. motion.js)
SH = TA + G - RESUME              # на столько сдвигается всё после галереи
DUR = 30.0 + SH                   # 36,2 с
N = int((DUR + 2.0) * SR)

L = np.zeros(N)
R = np.zeros(N)
BUS = {k: [np.zeros(N), np.zeros(N)] for k in ('drums', 'bass', 'music', 'fx')}
SEND = [np.zeros(N), np.zeros(N)]   # посыл на реверберацию (музыка)
SENDFX = [np.zeros(N), np.zeros(N)]  # посыл на реверберацию (эффекты)
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
        snd = SENDFX if bus == 'fx' else SEND
        snd[0][i:i + len(sig)] += sig * gl * rev
        snd[1][i:i + len(sig)] += sig * gr * rev


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


def paper():
    """Шорох листа: короткий шум с полосовым фильтром."""
    n = int(0.28 * SR)
    t = tt(n)
    return fft_filter(noise(n), lo=1800, hi=7000) * np.sin(np.pi * t / t[-1]) ** 2 * (1 + 0.6 * np.sin(2 * np.pi * 23 * t))


def tock(f=2200):
    """Тиканье секундомера."""
    n = int(0.06 * SR)
    t = tt(n)
    return np.sin(2 * np.pi * f * t) * np.exp(-t * 160) + fft_filter(noise(n), lo=4000) * np.exp(-t * 500) * 0.4


def ringtone(len_=0.45):
    """Трель телефонного звонка."""
    n = int(len_ * SR)
    t = tt(n)
    f = np.where(np.sin(2 * np.pi * 22 * t) > 0, 1320, 1660)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR)
    return np.tanh(x * 1.5) * np.minimum(1, (len_ - t) / 0.03) * np.minimum(1, t / 0.005)


def glitch(len_=0.14):
    n = int(len_ * SR)
    x = noise(n) * 0.6
    seg = int(0.012 * SR)
    for s in range(0, n, seg):           # «заикание»: повтор куска с понижением разрядности
        x[s:s + seg] = np.round(x[s % (seg * 3):s % (seg * 3) + len(x[s:s + seg])] * 4) / 4
    return fft_filter(x, lo=400, hi=6000)


def pop(f=900):
    """«Поп» появления: синус с быстрым падением высоты."""
    n = int(0.14 * SR)
    t = tt(n)
    ff = f * (0.55 + 1.2 * np.exp(-t * 45))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t * 28) + fft_filter(noise(n), lo=2500) * np.exp(-t * 220) * 0.25


def slap():
    """Хлопок наклейки/штампа: щелчок + плотный низ."""
    n = int(0.3 * SR)
    t = tt(n)
    body = np.sin(2 * np.pi * np.cumsum(70 + 120 * np.exp(-t * 40)) / SR) * np.exp(-t * 16)
    crack = fft_filter(noise(n), lo=800, hi=7000) * np.exp(-t * 55)
    return np.tanh((body * 1.1 + crack * 0.9) * 1.6)


def thump():
    n = int(0.25 * SR)
    t = tt(n)
    return np.sin(2 * np.pi * np.cumsum(55 + 90 * np.exp(-t * 30)) / SR) * np.exp(-t * 14) + fft_filter(noise(n), hi=900) * np.exp(-t * 40) * 0.3


def sparkle(f0=2600):
    """Блик: россыпь коротких колокольчиков."""
    out = np.zeros(int(0.7 * SR))
    for i, r in enumerate((1, 1.26, 1.5, 2.0, 1.68)):
        b = bell(f0 * r, 0.5) * 0.4
        s = int(i * 0.045 * SR)
        out[s:s + len(b)] += b[:len(out) - s]
    return out


# ---------- аранжировка ----------
CH = {'Am': [57, 60, 64], 'F': [53, 57, 60], 'Dm': [50, 53, 57], 'E': [52, 56, 59]}
PROG = ['Am', 'F', 'Dm', 'E']
KICKS = []
MEL = [(0, 76, 1), (1, 77, .5), (1.5, 76, .5), (2, 72, 1), (3, 71, 1),
       (4, 72, .5), (4.5, 74, .5), (5, 76, 1), (6, 74, .5), (6.5, 72, .5), (7, 71, 1),
       (8, 69, 1), (9, 72, .5), (9.5, 71, .5), (10, 69, 1), (11, 68, 1),
       (12, 69, 1.5), (13.5, 71, .5), (14, 72, 1), (15, 68, 1)]


def groove(o, t1, leads=()):
    """Хаус-грув от точки o (сильная доля) до t1; leads — номера тактов, с которых идёт мелодия."""
    k = 0
    while True:
        tb = o + k * BEAT
        if tb >= t1 - 1e-6:
            break
        bar, b = divmod(k, 4)
        c = PROG[bar % 4]
        root = CH[c][0] - 24
        add('drums', kick(1.0), tb, 0.9); KICKS.append(tb)
        if b in (1, 3):
            add('drums', clap(), tb, 0.75, rev=0.25)
        if tb + BEAT / 2 < t1:
            add('drums', hat(True), tb + BEAT / 2, 0.3, pan=0.3)
        for s in range(4):
            if s != 2 and tb + s * BEAT / 4 < t1:
                add('drums', hat(False), tb + s * BEAT / 4, 0.22 + 0.1 * (s == 1), pan=-0.25)
        if b == 2:
            add('drums', doira_dum(), tb + BEAT * 0.75, 0.32, pan=0.2)
        add('drums', doira_tak(), tb + BEAT * 0.25, 0.28, pan=-0.35)
        for h, oc in ((0.5, 0), (0.75, 12)):
            th = tb + h * BEAT
            if th >= t1:
                continue
            n = int(0.2 * SR)
            m = root + oc
            fc = 260 + 1600 * np.exp(-tt(n) * 22)
            x = saw_add(mtof(m), n, fc, voices=2, detune=9, maxh=40) * adsr(n, 0.003, 0.08, 0.55, 0.04)
            x += np.sin(2 * np.pi * mtof(m) * tt(n)) * adsr(n, 0.003, 0.16, 0.8, 0.04) * 0.9
            add('bass', x, th, 0.4 if oc == 0 else 0.26)
        ts = tb + (3 if b % 2 == 0 else 2) * BEAT / 4
        if ts < t1:
            n = int(0.22 * SR)
            fc = 900 + 3500 * np.exp(-tt(n) * 16)
            for m in CH[c]:
                x = saw_add(mtof(m + 12), n, fc, voices=3, detune=12, maxh=30) * adsr(n, 0.004, 0.09, 0.3, 0.06)
                add('music', x, ts, 0.075, pan=rs.uniform(-0.5, 0.5), rev=0.3)
        tones = [CH[c][0] + 12, CH[c][2] + 12, CH[c][1] + 12, CH[c][0] + 24]
        for h in range(2):
            th = tb + h * BEAT / 2
            if th < t1:
                add('music', dutar(mtof(tones[(b * 2 + h) % 4]), 0.4, 0.65, 0.993), th, 0.2, pan=0.35 * (1 if h else -1), rev=0.3)
        if b == 0:
            ln = min(BAR, t1 - tb)
            for m in CH[c]:
                n = int((ln + 0.3) * SR)
                x = saw_add(mtof(m + 12), n, 1600, voices=3, detune=16, maxh=22) * adsr(n, 0.06, 0.5, 0.7, 0.3)
                add('music', x, tb, 0.035, pan=rs.uniform(-0.6, 0.6), rev=0.4)
        k += 1
    for lb in leads:
        for bt, m, ln in MEL:
            ts = o + lb * BAR + bt * BEAT
            if ts < t1:
                add('music', dutar(mtof(m), ln * BEAT + 0.5, 0.75, 0.9975), ts, 0.3, pan=0.05, rev=0.45)
                add('music', dutar(mtof(m - 12), ln * BEAT + 0.3, 0.5, 0.996), ts + 0.012, 0.12, pan=-0.3, rev=0.3)


def shutter():
    """Щелчок затвора фотоаппарата."""
    n = int(0.16 * SR)
    t = tt(n)
    a = fft_filter(noise(n), lo=1500, hi=9000) * np.exp(-t * 90)
    b = np.roll(fft_filter(noise(n), lo=800, hi=6000) * np.exp(-t * 60), int(0.055 * SR))
    return a * 0.9 + b * 0.7 + np.sin(2 * np.pi * 2600 * t) * np.exp(-t * 200) * 0.3


# — 0–18,45(+SH): основной грув, мелодия — на галерее фото —
add('fx', crash(2.0), 0.0, 0.3, rev=0.4)
groove(0.0, 18.45 + SH, leads=(5,))
# — 18,45–21,32: брейк «muddati cheklangan»: тиканье секундомера, напряжение, раскатка —
add('drums', kick(1.1), (18.45 + SH), 0.9); KICKS.append((18.45 + SH))
n = int(2.9 * SR)
for m in CH['E'] + [64]:
    x = saw_add(mtof(m + 12), n, 700 + 1600 * tt(n) / 2.9, voices=3, detune=18, maxh=24) * adsr(n, 0.3, 0.8, 0.8, 0.2)
    add('music', x, (18.45 + SH), 0.05, pan=rs.uniform(-0.6, 0.6), rev=0.5)
add('bass', np.sin(2 * np.pi * mtof(28) * tt(n)) * adsr(n, 0.02, 1.5, 0.7, 0.2), (18.45 + SH), 0.5)
for k in range(16):
    add('drums', snare(0.2 + 0.8 * k / 15), (20.57 + SH) + k * (0.75 / 16), 0.42, pan=0.1 * (-1) ** k)
rc = crash(1.0)[::-1]
add('fx', rc, (21.32 + SH) - len(rc) / SR, 0.5)
# — 21,32–30: финальный дроп —
add('drums', crash(2.2), (21.32 + SH), 0.5, rev=0.5)
groove(21.32 + SH, DUR, leads=(3,))

# ---------- звуковые эффекты (события в кадре, см. motion.js) ----------
FX = []          # (момент, сигнал, громкость, панорама, ревер)
def fx(t0, sig, g, pan=0.0, rev=0.15):
    """Событие в «старом» времени сцен: всё после галереи сдвигается на SH."""
    FX.append((t0 + (SH if t0 >= 8.5 else 0), sig, g, pan, rev))


def gfx(t0, sig, g, pan=0.0, rev=0.15):
    """Событие галереи — в реальном времени."""
    FX.append((t0, sig, g, pan, rev))


# сцена 1
fx(0.0, whoosh(1.3, True), 0.8, -0.6, 0.2)            # такси въезжает
fx(0.4, pop(820), 0.6)
for i in range(5):
    fx(0.62 + i * 0.06 + 0.2, thump(), 0.35, -0.4 + i * 0.2)
fx(0.88, whoosh(0.45, False), 0.55, 0.5)
fx(1.86, whoosh(0.35, True), 0.5, -0.4)
fx(2.3, slap(), 0.9); fx(2.3, boom(1.2), 0.6); fx(2.3, crash(1.4), 0.35, 0, 0.4)
fx(2.42, sparkle(2400), 0.35, 0.3, 0.5)
fx(4.05, whoosh(0.6, True), 0.7, 0.6, 0.2)             # такси уезжает
fx(4.3, whoosh(0.8, False), 0.8, -0.3, 0.2)            # шторка
# сцена 2
fx(4.88, whoosh(0.45, False), 0.5, -0.5)


def reel_pos(t, fin, stop, st=4.95):
    k = min(max((t - st) / (stop - st), 0), 1)
    return fin * (1 - (1 - k) ** 3)


last = -1
for fin, stop in ((24, 5.4), (34, 5.58), (30, 5.78)):
    prev = 0
    for i in range(int(4.95 * SR / 100), int(stop * SR / 100) + 1):
        tc = i * 100 / SR
        p = int(reel_pos(tc, fin, stop))
        if p != prev:
            prev = p
            if tc - last > 0.025:
                fx(tc, keytick(), 0.16, rs.uniform(-0.4, 0.4), 0.0)
                last = tc
    fx(stop, click(1500), 0.6, 0, 0.1)
fx(5.78, boom(1.4), 0.5); fx(5.78, slap(), 0.4)
for i in range(16):
    fx(5.8 + i * 0.05, coin(2300 + 170 * (i % 6)), 0.12, -0.6 + i * 0.08, 0.3)
fx(6.1, thump(), 0.4)
fx(6.3, slap(), 0.55)
fx(6.45, whoosh(0.4, True), 0.35, 0.4)
fx(6.75, sparkle(3000), 0.25, -0.3, 0.5)
fx(TA - 0.32, whoosh(0.8, False), 0.8, 0.3, 0.2)       # шторка в галерею
# галерея «Mashinangiz shunday brendlanadi!»
for i in range(11):
    gfx(TA + 0.3 + i * 0.04 + 0.2, pop(650 + 40 * i), 0.18, -0.5 + 0.1 * i)
gfx(TA + 0.85, slap(), 0.75)
for i in range(5):
    tc = TA + 1.1 + i * 1.05
    gfx(tc - 0.1, whoosh(0.5, False), 0.6, 0.6, 0.15)
    gfx(tc + 0.3, shutter(), 0.8, -0.2 + 0.1 * i, 0.1)
    gfx(tc + 0.3, thump(), 0.35)
gfx(TA + 1.7, whoosh(0.4, True), 0.4, -0.4)
gfx(TA + 1.9, sparkle(2600), 0.25, 0.3, 0.5)
gfx(TA + G - 0.32, whoosh(0.8, False), 0.8, -0.3, 0.2)  # шторка в «foydalanib qoling»
# сцена 3
fx(8.86, pop(700), 0.35, -0.2)
fx(9.38, pop(860), 0.35, 0.2)
fx(9.98, slap(), 0.6)
fx(10.4, whoosh(0.5, False), 0.6, -0.6)
fx(10.95, pop(1100), 0.6)
fx(11.25, whoosh(0.5, False), 0.6, 0.6)
fx(11.6, thump(), 0.4)
fx(11.95, pop(950), 0.55)
fx(13.0, whoosh(0.75, True), 0.8, 0, 0.2)              # переход вверх
# сцена 4
for i, t0 in enumerate((13.6, 13.78, 13.96)):
    fx(t0, paper(), 0.8, (-0.4, 0.4, 0.0)[i], 0.1)
fx(14.36, pop(900), 0.45); fx(14.42, bell(mtof(88), 1.0), 0.3, -0.3, 0.4)
fx(14.9, pop(1000), 0.45); fx(14.96, bell(mtof(93), 1.0), 0.3, 0.3, 0.4)
fx(15.3, whoosh(0.45, False), 0.55, 0.5)
fx(15.82, slap(), 0.95); fx(15.82, boom(1.0), 0.5)
fx(16.12, whoosh(0.55, True), 0.6, 0, 0.2)
fx(16.45, pop(800), 0.55)
fx(16.6, whoosh(0.35, True), 0.4, -0.3)
fx(17.05, slap(), 0.8)
for i, m in enumerate((81, 84, 88)):
    fx(17.3 + i * 0.07, bell(mtof(m), 1.2), 0.25, -0.3 + 0.3 * i, 0.5)
fx(18.31, glitch(0.14), 0.7)
# сцена 5
fx(18.45, boom(1.8), 0.85); fx(18.45, crash(1.6), 0.35, 0, 0.5)
for k in range(6):
    fx(18.45 + k * 0.5, tock(2400 if k % 2 == 0 else 1900), 0.7, 0.2 * (-1) ** k, 0.15)
fx(18.68, whoosh(0.45, False), 0.55, -0.6)
fx(19.08, whoosh(0.45, False), 0.55, 0.6)
fx(19.48, slap(), 0.9); fx(19.48, boom(1.0), 0.5)
fx(20.3, riser(1.02, 400, 12000), 0.6, 0, 0.2)
fx(21.0, whoosh(0.8, False), 0.8, 0.3, 0.2)            # шторка
# сцена 6
fx(21.32, boom(1.8), 0.85)
fx(21.6, thump(), 0.5)
fx(22.1, slap(), 0.7)
fx(22.5, whoosh(0.5, True), 0.5)
for i in range(7):
    fx(22.85 + i * 0.05 + 0.2, pop(700 + 60 * i), 0.22, -0.4 + 0.13 * i)
fx(23.36, slap(), 0.8)
fx(24.3, whoosh(0.6, False), 0.65, -0.6)
fx(24.98, click(3200), 0.9); fx(25.0, pop(1300), 0.45)
fx(25.66, whoosh(0.6, False), 0.65, 0.6)
fx(25.95, ringtone(0.42), 0.35, 0, 0.2)
fx(26.5, ringtone(0.42), 0.3, 0, 0.2)
fx(26.7, whoosh(1.2, True), 0.75, -0.6, 0.2)           # такси въезжает
fx(26.85, slap(), 0.9); fx(26.85, boom(1.4), 0.6); fx(26.85, crash(1.8), 0.35, 0, 0.5)
for t0 in (27.8, 28.0, 29.0, 29.2):
    fx(t0 + 0.2, sparkle(2800), 0.2, 0.3, 0.5)

for t0, sig, g, pan, rv in FX:
    add('fx', sig, t0, g, pan=pan, rev=rv)

# ---------- сведение ----------
t = tt(N)
side = np.ones(N)
for k in KICKS:
    i = int(k * SR)
    seg = np.arange(N - i) / SR
    m = min(len(seg), int(0.35 * SR))
    side[i:i + m] = np.minimum(side[i:i + m], 1 - 0.75 * np.exp(-seg[:m] / 0.08))
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


def master(stems, send, path, drive, tail):
    lr = [np.zeros(N), np.zeros(N)]
    rv = reverb(*send)
    for ch in (0, 1):
        for k, g in stems.items():
            lr[ch] += BUS[k][ch] * g
        lr[ch] += rv[ch] * 0.6
    mix = np.stack([fft_filter(lr[0], lo=28), fft_filter(lr[1], lo=28)])
    mix /= np.max(np.abs(mix)) + 1e-9
    mix = np.tanh(mix * drive) / np.tanh(drive)
    mix *= np.clip((DUR - t) / tail, 0, 1) ** 2
    mix = mix[:, :int(DUR * SR)]
    mix *= 0.89 / np.max(np.abs(mix))
    pcm = (mix.T * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print('готово:', path)


master({'drums': 1.0, 'bass': 0.95, 'music': 0.9}, SEND, sys.argv[1] if len(sys.argv) > 1 else 'music.wav', 1.8, 1.4)
master({'fx': 1.0}, SENDFX, sys.argv[2] if len(sys.argv) > 2 else 'sfx.wav', 2.5, 0.4)
