"""Саундтрек к ролику «Brend ruxsatnoma aksiyada»: 18,5 с, 128 BPM, ля гармонический минор.

Всё синтезируется на numpy, без сэмплов: хаус-грув (бочка, клэп, хэты, дойра),
офбит-бас с сайдчейном, стабы аккордов, щипковый «дутар» (Karplus–Strong),
а также звуки, привязанные к событиям в кадре (см. motion.js): проезд машины,
штампы, барабаны цифр, монеты, шорох документов, тиканье секундомера, звонок.
Озвучка сюда не входит — её кладёт поверх build.sh, приглушая музыку под голосом.

    python3 music.py out/music.wav
"""
import sys
import wave
import numpy as np

SR = 44100
BPM = 128
BEAT = 60 / BPM          # 0,469 с
BAR = BEAT * 4           # 1,875 с
DUR = 18.5
N = int((DUR + 2.0) * SR)

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


# ---------- аранжировка ----------
VO = 0.4                                    # озвучка стартует с 0,4 с
CH = {'Am': [57, 60, 64], 'F': [53, 57, 60], 'Dm': [50, 53, 57], 'E': [52, 56, 59]}
PROG = ['Am', 'F', 'Dm', 'E']
KICKS = []
MEL = [(0, 76, 1), (1, 77, .5), (1.5, 76, .5), (2, 72, 1), (3, 71, 1),
       (4, 72, .5), (4.5, 74, .5), (5, 76, 1), (6, 74, .5), (6.5, 72, .5), (7, 71, 1),
       (8, 69, 1), (9, 72, .5), (9.5, 71, .5), (10, 69, 1), (11, 68, 1),
       (12, 69, 1.5), (13.5, 71, .5), (14, 72, 1), (15, 68, 1)]


def groove(o, t1, lead=False, arp=True):
    """Хаус-грув от точки o (сильная доля) до t1."""
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
        # офбит-бас
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
        # стабы аккорда на синкопах (шестнадцатые 3 и 6 в такте)
        for step in ((3,) if b % 2 == 0 else (2,)):
            ts = tb + step * BEAT / 4
            if ts >= t1:
                continue
            n = int(0.22 * SR)
            fc = 900 + 3500 * np.exp(-tt(n) * 16)
            for m in CH[c]:
                x = saw_add(mtof(m + 12), n, fc, voices=3, detune=12, maxh=30) * adsr(n, 0.004, 0.09, 0.3, 0.06)
                add('music', x, ts, 0.075, pan=rs.uniform(-0.5, 0.5), rev=0.3)
        # арпеджио дутара восьмыми
        if arp:
            tones = [CH[c][0] + 12, CH[c][2] + 12, CH[c][1] + 12, CH[c][0] + 24]
            for h in range(2):
                th = tb + h * BEAT / 2
                if th < t1:
                    add('music', dutar(mtof(tones[(b * 2 + h) % 4]), 0.4, 0.65, 0.993), th, 0.2, pan=0.35 * (1 if h else -1), rev=0.3)
        # пэд на такт
        if b == 0:
            ln = min(BAR, t1 - tb)
            for m in CH[c]:
                n = int((ln + 0.3) * SR)
                x = saw_add(mtof(m + 12), n, 1600, voices=3, detune=16, maxh=22) * adsr(n, 0.06, 0.5, 0.7, 0.3)
                add('music', x, tb, 0.035, pan=rs.uniform(-0.6, 0.6), rev=0.4)
        k += 1
    if lead:
        for bt, m, ln in MEL:
            ts = o + bt * BEAT
            if ts < t1:
                add('music', dutar(mtof(m), ln * BEAT + 0.5, 0.75, 0.9975), ts, 0.34, pan=0.05, rev=0.45)
                add('music', dutar(mtof(m - 12), ln * BEAT + 0.3, 0.5, 0.996), ts + 0.012, 0.13, pan=-0.3, rev=0.3)


# — 0–0,4: вход —
add('fx', riser(0.4, 800, 9000), 0.0, 0.35)
add('fx', whoosh(0.8, True), 0.0, 0.55, pan=-0.5, rev=0.2)          # машина въезжает
# — 0,4–9,3: основной грув —
add('fx', boom(1.6), VO, 0.45)
add('fx', crash(2.0), VO, 0.25, rev=0.4)
groove(VO, 9.3, lead=False)
# — 9,3–10,92: брейк «muddati cheklangan» —
add('fx', boom(1.6), 9.3, 0.9)
add('fx', crash(1.8), 9.3, 0.4, rev=0.5)
add('drums', kick(1.1), 9.3, 0.9); KICKS.append(9.3)
for k in range(7):
    tk = 9.3 + k * 0.235
    add('fx', tock(2400 if k % 2 == 0 else 1900), tk, 0.45, pan=0.2 * (-1) ** k, rev=0.15)
n = int(1.7 * SR)
for m in CH['E'] + [64]:
    x = saw_add(mtof(m + 12), n, 900 + 1500 * tt(n) / 1.7, voices=3, detune=18, maxh=24) * adsr(n, 0.2, 0.6, 0.8, 0.2)
    add('music', x, 9.3, 0.05, pan=rs.uniform(-0.6, 0.6), rev=0.5)
add('bass', np.sin(2 * np.pi * mtof(28) * tt(n)) * adsr(n, 0.02, 1.0, 0.7, 0.2), 9.3, 0.5)
add('fx', boom(1.2), 10.16, 0.6)
add('drums', clap(), 10.16, 0.7, rev=0.4)
for k in range(12):
    add('drums', snare(0.25 + 0.75 * k / 11), 10.36 + k * (0.56 / 12), 0.42, pan=0.1 * (-1) ** k)
add('fx', riser(1.0, 400, 12000), 9.92, 0.5, rev=0.2)
rc = crash(0.9)[::-1]
add('fx', rc, 10.92 - len(rc) / SR, 0.45)
# — 10,92–16,0: второй куплет с мелодией —
add('fx', boom(1.8), 10.92, 0.9)
add('fx', crash(2.0), 10.92, 0.5, rev=0.5)
groove(10.92, 16.0, lead=True)
rc = crash(0.8)[::-1]
add('fx', rc, 16.0 - len(rc) / SR, 0.4)
add('fx', riser(1.0, 500, 11000), 15.0, 0.35, rev=0.2)
# — 16,0–18,5: финал —
add('fx', boom(2.4), 16.0, 1.0)
add('fx', crash(2.4), 16.0, 0.55, rev=0.6)
groove(16.0, DUR, lead=False, arp=True)
for i, m in enumerate([69, 72, 76, 81]):
    add('fx', bell(mtof(m + 12), 1.4), 16.05 + i * 0.07, 0.13, pan=-0.3 + 0.2 * i, rev=0.5)

# ---------- события в кадре ----------
# сцена 1: буквы, «BIZDA», штамп «AKSIYADA!», уезд машины, шторка
add('fx', whoosh(0.35, True), 0.7, 0.3, pan=-0.2)
add('fx', whoosh(0.4, False), 0.98, 0.3, pan=0.4)
add('fx', whoosh(0.25, True), 1.8, 0.35, pan=-0.4)
add('fx', boom(1.0), 2.26, 0.6)
add('drums', clap(), 2.26, 0.8, rev=0.4)
add('fx', crash(1.2), 2.26, 0.3, rev=0.3)
add('fx', whoosh(0.5, True), 2.5, 0.5, pan=0.6, rev=0.1)           # машина уезжает
add('fx', whoosh(0.45, False), 2.66, 0.55, pan=-0.3, rev=0.2)     # шторка
# сцена 2: «ATIGI», барабаны цифр, монеты, «MING SO'M»
add('fx', whoosh(0.3, True), 2.9, 0.3, pan=-0.5)


def reel_pos(t, fin, stop, st=3.1):
    k = min(max((t - st) / (stop - st), 0), 1)
    return fin * (1 - (1 - k) ** 3)


last = -1
for fin, stop in ((24, 3.6), (34, 3.75), (30, 3.9)):
    prev = 0
    for i in range(int(3.1 * SR / 100), int(stop * SR / 100) + 1):
        tc = i * 100 / SR
        p = int(reel_pos(tc, fin, stop))
        if p != prev:
            prev = p
            if tc - last > 0.018:
                add('fx', keytick(), tc, 0.22, pan=rs.uniform(-0.4, 0.4))
                last = tc
    add('fx', click(1500), stop, 0.7)
    add('fx', click(3600), stop + 0.004, 0.4)
add('fx', boom(1.2), 3.9, 0.7)
for i in range(14):
    add('fx', coin(2300 + 170 * (i % 6)), 3.92 + i * 0.045, 0.08, pan=-0.6 + i * 0.09, rev=0.3)
add('fx', whoosh(0.25, False), 4.22, 0.3)
add('drums', clap(), 4.48, 0.6, rev=0.3)
add('fx', boom(0.8), 4.48, 0.35)
add('fx', whoosh(0.45, True), 4.75, 0.45, rev=0.2)                  # ирис
# сцена 3: карточки, плюс, «QOLING!», переход вверх
add('fx', whoosh(0.35, False), 5.1, 0.35, pan=-0.5)
add('fx', blip(1320), 5.38, 0.3, rev=0.3)
add('fx', whoosh(0.35, False), 5.5, 0.35, pan=0.5)
add('fx', blip(1760), 5.86, 0.22, rev=0.3)
add('drums', clap(), 6.1, 0.5, rev=0.3)
add('fx', whoosh(0.4, True), 6.25, 0.5, rev=0.15)
# сцена 4: листы, «TEZ», «OSON», штамп, глитч
for i, t0 in enumerate((6.52, 6.64, 6.76)):
    add('fx', paper(), t0, 0.5, pan=(-0.4, 0.4, 0.0)[i])
add('fx', bell(mtof(88), 1.2), 7.5, 0.16, pan=-0.3, rev=0.5)
add('fx', bell(mtof(93), 1.2), 8.04, 0.16, pan=0.3, rev=0.5)
add('fx', whoosh(0.3, False), 8.4, 0.3, pan=0.5)
add('fx', boom(0.9), 8.62, 0.6)
add('drums', snare(1.0), 8.62, 0.5, rev=0.3)
add('fx', glitch(0.14), 9.16, 0.4)
# сцена 5: «AKSIYA» / «MUDDATI» влетают
add('fx', whoosh(0.3, False), 9.3, 0.3, pan=-0.5)
add('fx', whoosh(0.3, False), 9.76, 0.3, pan=0.5)
add('fx', whoosh(0.45, False), 10.74, 0.5, pan=0.3, rev=0.2)        # шторка
# сцена 6: «BATAFSIL», «HOZIROQ», кнопки, тап, звонок, «FAQAT BIZDA!», машина
add('fx', whoosh(0.3, True), 11.48, 0.3)
add('fx', whoosh(0.3, True), 12.0, 0.3)
add('drums', clap(), 12.28, 0.55, rev=0.35)
add('fx', boom(0.8), 12.78, 0.35)
add('fx', whoosh(0.4, False), 13.5, 0.4, pan=-0.5)
add('fx', blip(1480), 13.62, 0.25, rev=0.3)
add('fx', click(3200), 14.3, 0.6)
add('fx', blip(1980), 14.32, 0.18, rev=0.3)
add('fx', whoosh(0.4, False), 14.92, 0.4, pan=0.5)
add('fx', ringtone(0.42), 15.15, 0.1, rev=0.2)
add('fx', ringtone(0.42), 15.7, 0.08, rev=0.2)
add('fx', whoosh(0.8, True), 15.95, 0.5, pan=-0.6, rev=0.2)        # машина въезжает
for i, t0 in enumerate((16.5, 16.7, 17.6, 17.8)):
    add('fx', bell(mtof(100 - (i % 2) * 5), 0.6), t0 + 0.25, 0.05, pan=0.3 * (-1) ** i, rev=0.5)

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
fade = np.clip((DUR - t) / 0.9, 0, 1) ** 2     # затухание к концу ролика
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
