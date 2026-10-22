"""Саундтрек Reels «старое / моё видео»: 29 секунд, 120 BPM — в темп нового видео.

Основа — музыка самого нового видео (кадр 3), поэтому всё синхронно:
  0–5 с    приглушённый (лоу-пасс) фрагмент того же трека + синтезированные барабаны
           на той же сетке; «G‘ALATI» — заикание и остановка плёнки, звон стекла;
  6,378 с  стартует звук нового видео — сначала узкой полосой, как из голограммы,
           и раскрывается до полного звука к удару на 9,0 с (видео на весь экран);
  22,4 с   финал «1 или 2?»: тот же трек приглушённо, барабаны, «✕» и «✓»;
  25 с     фильтр раскрывается на «победителе», 27 с — последний удар и звенящий хвост.
Ударные и эффекты синтезируются на numpy (утилиты как в ../video/music.py).

    python3 sound.py src/new.wav out/music.wav
"""
import sys
import wave
import numpy as np

SR = 44100
BEAT = 0.5               # 120 BPM; доли ролика лежат ровно на 0, 0,5, 1, …
N0 = 6.378               # старт нового видео (см. motion.js)
LAND = 9.0
OUT = 22.4
DUR = 29.0
N = int((DUR + 1.0) * SR)

L = np.zeros(N)
R = np.zeros(N)
BUS = {k: [np.zeros(N), np.zeros(N)] for k in ('track', 'drums', 'fx')}
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



def glass(len_=0.9):
    """Разбитое стекло: треск + россыпь коротких «динь» на высоких частотах."""
    n = int(len_ * SR)
    t = tt(n)
    x = fft_filter(noise(n), lo=1800, hi=12000) * np.exp(-t * 9) * 0.8
    for _ in range(70):
        t0 = rs.random() ** 2 * len_ * 0.8
        f = rs.uniform(2500, 9500)
        i = int(t0 * SR)
        m = n - i
        tk = tt(m)
        x[i:] += np.sin(2 * np.pi * f * tk) * np.exp(-tk * rs.uniform(25, 60)) * rs.uniform(0.05, 0.22)
    return x


def buzzer(len_=0.32, f=150):
    """Ошибка: жужжащий «квадрат» с биением."""
    n = int(len_ * SR)
    t = tt(n)
    sq = np.sign(np.sin(2 * np.pi * f * t)) + np.sign(np.sin(2 * np.pi * f * 1.06 * t))
    return fft_filter(sq, hi=2200) * adsr(n, 0.004, 0.2, 0.8, 0.05) * 0.4


def zap(len_=0.5, f0=120, f1=2400):
    """Включение голограммы: свип вверх с FM и шипением."""
    n = int(len_ * SR)
    t = tt(n)
    k = t / len_
    f = f0 * (f1 / f0) ** (k ** 0.7)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR + 2.5 * np.sin(2 * np.pi * f * 1.5 * t / 1.0) * (1 - k))
    hiss = tv_band(noise(n), lambda s: 600 * 12 ** min(1, s / len_), bw=0.6) * 0.6
    return (tone * 0.5 + hiss) * np.sin(np.pi * np.minimum(1, k * 1.3)) ** 0.8


def glitch_burst(len_=0.06):
    n = int(len_ * SR)
    x = noise(n)
    x = np.round(x * 3) / 3                       # грубый битовый шум
    hold = rs.integers(4, 30)
    x = np.repeat(x[::hold], hold)[:n]            # понижение частоты дискретизации
    return fft_filter(x, lo=400, hi=9000) * np.hanning(n)


# ---------- трек нового видео ----------
def load(path):
    with wave.open(path) as w:
        assert w.getframerate() == SR and w.getnchannels() == 2
        x = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(float) / 32768
    return x.reshape(-1, 2).T


TRK = load(sys.argv[1])


def track_at(pos):
    """Сэмплы трека в моменты pos (секунды трека), с интерполяцией; вне трека — тишина."""
    i = pos * SR
    out = []
    for ch in TRK:
        y = np.interp(i, np.arange(len(ch)), ch, left=0, right=0)
        out.append(y)
    return out


def put(bus, lr, t0, gain=1.0):
    i = int(round(t0 * SR))
    for ch in (0, 1):
        x = lr[ch][:N - i] * gain
        BUS[bus][ch][i:i + len(x)] += x


def env_at(t, keys):
    return np.interp(t, [k[0] for k in keys], [k[1] for k in keys])


# — 0–5,1 с: тот же трек, приглушённый; заикание и остановка плёнки —
# фаза трека: доли трека на 0,122 + 0,5·n совпадают с долями ролика при pos = t + 5,622
t = np.arange(int(5.1 * SR)) / SR
pos = t + 5.622
st = (t >= 4.5) & (t < 4.8)
pos[st] = 4.5 + 5.622 + (t[st] - 4.5) % (BEAT / 8)            # заикание шестнадцатыми
ts = t >= 4.8
d = t[ts] - 4.8
pos[ts] = 4.8 + 5.622 + d - d * d / 0.6                        # остановка плёнки за 0,3 с
bed = track_at(pos)
g = env_at(t, [(0, 0.0), (0.02, 1.0), (4.95, 1.0), (5.1, 0.0)])
bed = [fft_filter(x, hi=520, order=2) * g * 1.05 for x in bed]
put('track', bed, 0.0)

# барабаны на той же сетке (сильные доли — нечётные секунды)
for k in range(10):
    tb = k * BEAT
    add('drums', kick(1.0), tb, 0.75)
    add('drums', hat(False), tb + BEAT / 2, 0.22, pan=0.3)
    if k % 2 == 1 and tb >= 1.5:
        add('drums', clap(), tb, 0.55, rev=0.25)
for k in range(8):
    add('drums', hat(False), 2.0 + k * BEAT / 2 + BEAT / 4, 0.12, pan=-0.3)

# хук
add('fx', boom(1.6), 0.0, 0.9)
add('fx', crash(2.0), 0.0, 0.45, rev=0.4)
add('fx', whoosh(0.35, False), 0.45, 0.4, pan=-0.2)
add('fx', boom(1.0), 1.06, 0.6)
add('drums', snare(1.0), 1.06, 0.6, rev=0.35)
add('fx', click(4200), 1.06, 0.4)

# голограмма «старое» и подпись
add('fx', zap(0.55, 140, 1600), 1.45, 0.4, pan=0.4, rev=0.3)
for i, f in enumerate((1180, 1580)):
    add('fx', blip(f), 2.0 + i * 0.07, 0.22, pan=-0.2, rev=0.3)

# «G‘ALATI»: удар, ошибка, глитч
add('fx', boom(1.2), 4.0, 0.8)
add('drums', kick(1.2), 4.0, 0.9)
add('fx', buzzer(0.22), 4.02, 0.55, pan=0.3)
add('fx', buzzer(0.34, 118), 4.28, 0.55, pan=0.3)
for k in range(12):
    tk = 4.1 + rs.random() * 0.85
    add('fx', glitch_burst(rs.uniform(0.03, 0.09)), tk, 0.35, pan=rs.uniform(-0.7, 0.7))

# осколки
add('fx', glass(1.0), 5.0, 0.75, pan=0.35, rev=0.4)
add('fx', boom(1.5), 5.0, 0.8)
add('fx', crash(1.2), 5.0, 0.25, rev=0.4)

# вайп
add('fx', whoosh(0.6, True), 5.35, 0.75, pan=-0.4, rev=0.2)
rev_cr = crash(0.9)[::-1]
add('fx', rev_cr, 6.0 - len(rev_cr) / SR, 0.35)

# голограмма «моё»
add('fx', zap(0.5, 200, 3200), 5.98, 0.4, pan=-0.4, rev=0.35)
FS = 46.25          # фа-диез
for i, m in enumerate((5, 6, 6.585, 7)):      # фа-диез, октавы и квинта — нейтрально к гармонии трека
    add('fx', bell(FS * 2 ** m / 2, 1.4), 6.05 + i * 0.07, 0.1, pan=-0.5 + 0.3 * i, rev=0.6)

# — 6,378 с: звук нового видео, из «голограммы» в полный —
t = np.arange(int(16.0 * SR)) / SR
seg = [ch[:len(t)] for ch in TRK]
wet = [fft_filter(x, lo=700, hi=3200, order=2) * 1.6 for x in seg]
k = np.clip((t + N0 - 6.9) / (LAND - 6.9), 0, 1) ** 2.2
k[t + N0 >= LAND] = 1
mixd = [w * (1 - k) + x * k for w, x in zip(wet, seg)]
put('track', mixd, N0)

add('fx', bell(FS * 2 ** 6, 1.6), 7.5, 0.18, pan=-0.3, rev=0.6)        # золотая галочка
add('fx', bell(FS * 2 ** 6.585, 1.6), 7.56, 0.12, pan=0.0, rev=0.6)
add('fx', blip(1580), 6.5, 0.18, pan=0.3, rev=0.3)                   # подпись «МОЁ»
add('fx', whoosh(0.3, False), 8.0, 0.35)                               # замах
add('fx', riser(0.95, 300, 12000), 8.05, 0.55, rev=0.25)
for k_ in range(8):
    add('drums', snare(0.3 + 0.7 * k_ / 7), 8.5 + k_ * BEAT / 8, 0.32, pan=0.1 * (-1) ** k_)
rev_cr = crash(0.8)[::-1]
add('fx', rev_cr, LAND - len(rev_cr) / SR, 0.35)
add('fx', boom(2.2), LAND, 0.7)
add('fx', crash(2.2), LAND, 0.3, rev=0.5)

# — финал 22,4–29 с —
WIN, FINAL = 25.0, 27.0
add('fx', whoosh(0.5, False), 22.35, 0.5, pan=0.3, rev=0.2)
add('fx', blip(1400), 22.9, 0.2, rev=0.3)
# тот же трек: приглушённо, на «победителе» (25 с) фильтр раскрывается, после 27 с — затухание
t = np.arange(int((DUR - 23.0) * SR)) / SR
bed = track_at(t + 23.0 - 16.378)
open_ = np.clip((t + 23.0 - (WIN - 0.25)) / 0.25, 0, 1)
g = env_at(t + 23.0, [(23.0, 0.0), (23.03, 1.0), (FINAL + 0.3, 1.0), (DUR - 0.2, 0.0)])
bed = [(fft_filter(x, hi=900, order=2) * (1 - open_) * 1.2 + fft_filter(x, hi=4000, order=2) * open_ * 0.95) * g for x in bed]
put('track', bed, 23.0)
add('fx', boom(2.0), 23.0, 0.85)
add('fx', crash(2.0), 23.0, 0.35, rev=0.5)
for k_ in range(8):                                    # 23–27 с: бочка на каждую долю
    tb = 23.0 + k_ * BEAT
    add('drums', kick(0.9), tb, 0.75)
    add('drums', hat(True), tb + BEAT / 2, 0.16, pan=0.3)
    if k_ % 2 == 1:
        add('drums', clap(), tb, 0.45, rev=0.3)
    if tb >= WIN:                                      # после «победителя» — шестнадцатые хэты
        for q in (1, 3):
            add('drums', hat(False), tb + q * BEAT / 4, 0.12, pan=-0.3)
add('fx', blip(1300), 23.25, 0.16, pan=-0.4, rev=0.3)                     # подписи под карточками
add('fx', blip(1560), 23.4, 0.16, pan=0.4, rev=0.3)
add('fx', buzzer(0.18, 160), 23.5, 0.35, pan=-0.4)                       # ✕ на карточке 1
add('fx', bell(FS * 2 ** 6, 1.8), 24.0, 0.2, pan=0.4, rev=0.6)           # ✓ на карточке 2
add('fx', bell(FS * 2 ** 7, 1.8), 24.05, 0.1, pan=0.4, rev=0.6)
for i in range(10):
    add('fx', coin(2600 + 220 * (i % 4)), 24.0 + i * 0.045, 0.05, pan=0.2 + 0.05 * i, rev=0.3)
add('fx', blip(1180), 24.5, 0.2, rev=0.3)
rev_cr = crash(0.8)[::-1]
add('fx', rev_cr, WIN - len(rev_cr) / SR, 0.3)
add('fx', boom(1.6), WIN, 0.6)
add('fx', crash(2.0), WIN, 0.3, rev=0.5)
for k_ in range(8):                                    # раскатка к последнему удару
    add('drums', snare(0.25 + 0.6 * k_ / 7), FINAL - BEAT + k_ * BEAT / 8, 0.3, pan=0.1 * (-1) ** k_)
add('fx', boom(2.6), FINAL, 0.9)
add('drums', kick(1.1), FINAL, 0.85)
add('fx', crash(2.8), FINAL, 0.4, rev=0.7)
for i, m in enumerate((5, 6, 6.585, 7, 7.585)):        # звенящий аккорд фа-диез на хвосте
    add('fx', bell(FS * 2 ** m / 2, 2.4), FINAL + i * 0.05, 0.12, pan=-0.5 + 0.25 * i, rev=0.7)


# ---------- сведение ----------
def reverb(xl, xr, length=2.0, damp=5000):
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
# пока играет полный трек (9–22,4 с), синтезированные эффекты стихают
t = tt(N)
fxg = 1 - 0.6 * ((t > LAND + 1.5) & (t < OUT - 0.1))
gains = {'track': 1.0, 'drums': 0.8, 'fx': 0.75}
for ch, o in ((0, L), (1, R)):
    for k_, g_ in gains.items():
        o += BUS[k_][ch] * g_ * (fxg if k_ != 'track' else 1)
    o += (rl, rr)[ch] * 0.5

mix = np.stack([fft_filter(L, lo=25), fft_filter(R, lo=25)])
fade = np.clip((DUR - t) / 0.9, 0, 1) ** 2
mix = mix * fade
mix = mix[:, :int(DUR * SR)]
mix /= np.max(np.abs(mix)) + 1e-9
mix = np.tanh(mix * 1.3) / np.tanh(1.3)       # мягкая сатурация на мастере
mix *= 0.89 / np.max(np.abs(mix))

out = sys.argv[2] if len(sys.argv) > 2 else 'music.wav'
pcm = (mix.T * 32767).astype('<i2')
with wave.open(out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('готово:', out)
