"""Саундтрек и финальное сведение для «Farqi nimada?».

Трек синтезируется на numpy (без сэмплов) по таймлайну из out/timeline.json:
120 BPM, ля минор (Am–F–C–G), энергия меняется по сценам — удар на столкновении слов,
лёгкий грув под определениями, полный бит на итогах, райзеры перед шторками.
Звуки привязаны к событиям в кадре (motion.js): свайпы карточек, ключевые слова, чипы.
Музыка приглушается под голос по огибающей речи (сайдчейн).

    python3 music.py      → out/music.wav, out/mix.wav (голос + музыка)
"""
import json
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
SR = 48000
BPM = 120
BEAT = 60 / BPM
BAR = BEAT * 4
TL = json.load(open(os.path.join(OUT, 'timeline.json'), encoding='utf-8'))
DUR = TL['duration']
N = int((DUR + 2.0) * SR)
BUS = {k: [np.zeros(N), np.zeros(N)] for k in ('drums', 'bass', 'music', 'fx')}
SEND = [np.zeros(N), np.zeros(N)]
rs = np.random.default_rng(3)
SCN = TL['scenes']
PAIRS = [s for s in SCN if s['type'] == 'pair']
INTRO, OUTRO = SCN[0], SCN[-1]


# ---------- утилиты ----------
def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def add(bus, sig, t0, gain=1.0, pan=0.0, rev=0.0):
    i = int(round(t0 * SR))
    if i >= N:
        return
    if i < 0:
        sig, i = sig[-i:], 0
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
        H = np.exp(-0.5 * ((lf - np.log2(fc_at((s + hop) / SR))) / bw) ** 2)
        out[s:s + block] += np.fft.irfft(np.fft.rfft(xp[s:s + block] * win) * H, block)
    return out[:len(x)]


def noise(n):
    return rs.standard_normal(n)


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.1):
    t = tt(n)
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    return e * np.clip((n / SR - t) / max(r, 1e-6), 0, 1)


# ---------- звуки (кэшируются: один и тот же удар не синтезируем дважды) ----------
_cache = {}


def cached(fn):
    def w(*a):
        k = (fn.__name__,) + a
        if k not in _cache:
            _cache[k] = fn(*a)
        return _cache[k]
    return w


@cached
def kick(amp=1.0):
    n = int(0.45 * SR)
    t = tt(n)
    f = 44 + (165 - 44) * np.exp(-t * 32)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7.0)
    click = fft_filter(noise(n) * np.exp(-t * 900), lo=2500) * 0.3
    return np.tanh((body + click) * 1.7) * amp


@cached
def clap():
    n = int(0.35 * SR)
    t = tt(n)
    env = sum(np.where(t >= d, np.exp(-(t - d) * (180 if k < 2 else 20)), 0) for k, d in enumerate((0.0, 0.011, 0.022)))
    return fft_filter(noise(n), lo=900, hi=5000) * env * 0.9


@cached
def snare(amp=1.0):
    n = int(0.25 * SR)
    t = tt(n)
    return (np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.5 + fft_filter(noise(n), lo=1500, hi=9000) * np.exp(-t * 22) * 0.8) * amp


@cached
def hat(open_=False):
    n = int((0.3 if open_ else 0.06) * SR)
    return fft_filter(noise(n), lo=7500, order=3) * np.exp(-tt(n) * (12 if open_ else 75))


@cached
def crash(len_=2.4):
    n = int(len_ * SR)
    t = tt(n)
    return fft_filter(noise(n), lo=3500) * np.exp(-t * 2.2) + sum(np.sin(2 * np.pi * f * t) for f in (3170, 4410, 5230, 6890)) * 0.05 * np.exp(-t * 3)


@cached
def boom(len_=2.0):
    n = int(len_ * SR)
    t = tt(n)
    f = 30 + 60 * np.exp(-t * 6)
    return np.tanh((np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.7) + fft_filter(noise(n), hi=400) * np.exp(-t * 5) * 0.7) * 2.2)


@cached
def riser(len_, f0=300, f1=9000):
    n = int(len_ * SR)
    t = tt(n)
    k = t / len_
    x = tv_band(noise(n), lambda s: f0 * (f1 / f0) ** min(1, s / len_) ** 1.4, bw=0.5)
    tone = np.sin(2 * np.pi * np.cumsum(200 + 900 * k ** 2) / SR + 3 * np.sin(2 * np.pi * 6 * t)) * 0.16
    return (x * 1.4 + tone) * k ** 2.2


@cached
def whoosh(len_=0.5, up=True):
    n = int(len_ * SR)
    k = tt(n) / len_
    x = tv_band(noise(n), lambda s: (400 * 12 ** (s / len_)) if up else (5000 * 0.1 ** (s / len_)), bw=0.7)
    return x * np.sin(np.pi * k) ** 1.5


@cached
def blip(f=1320):
    n = int(0.16 * SR)
    t = tt(n)
    ff = f * (1 + 0.5 * np.exp(-t * 60))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR + 1.5 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 30)) * np.exp(-t * 26)


@cached
def pop(f=900):
    n = int(0.09 * SR)
    t = tt(n)
    ff = f * (0.6 + 0.8 * np.exp(-t * 80))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t * 45)


@cached
def bell(f, len_=1.4):
    n = int(len_ * SR)
    t = tt(n)
    return np.sin(2 * np.pi * f * t + np.sin(2 * np.pi * f * 3.5 * t) * 2.0 * np.exp(-t * 4)) * np.exp(-t * 3.2)


@cached
def pluck(m, len_=0.45, bright=1.0):
    """Синт-пиццикато: пила с быстро закрывающимся фильтром."""
    n = int(len_ * SR)
    f = mtof(m)
    t = tt(n)
    fc = 500 + 5000 * bright * np.exp(-t * 14)
    out = np.zeros(n)
    for k in range(1, int(min(40, SR / 2.2 / f)) + 1):
        out += np.sin(2 * np.pi * k * f * t) / k / np.sqrt(1 + (k * f / fc) ** 4)
    return out * adsr(n, 0.002, 0.12, 0.25, 0.08)


@cached
def pad(m, len_):
    n = int(len_ * SR)
    t = tt(n)
    out = np.zeros(n)
    for dv in (-12, 0, 12):
        f = mtof(m) * 2 ** (dv / 1200)
        ph = rs.random() * 6.28
        for k in range(1, 14):
            out += np.sin(2 * np.pi * k * f * t + ph * k) / k / np.sqrt(1 + (k * f / 1600) ** 4)
    return out * adsr(n, 0.35, 0.8, 0.8, 0.5) / 2


@cached
def bassnote(m, len_=0.24):
    n = int(len_ * SR)
    t = tt(n)
    f = mtof(m)
    fc = 250 + 1200 * np.exp(-t * 16)
    x = sum(np.sin(2 * np.pi * k * f * t) / k / np.sqrt(1 + (k * f / fc) ** 4) for k in range(1, 24))
    return (x * 0.7 + np.sin(2 * np.pi * f * t) * 0.9) * adsr(n, 0.003, 0.15, 0.7, 0.04)


# ---------- гармония ----------
CH = {'Am': [57, 60, 64], 'F': [53, 57, 60], 'C': [48, 52, 55], 'G': [55, 59, 62]}
PROG = ['Am', 'F', 'C', 'G']


def chord_at(t):
    return PROG[int(t // BAR) % 4]


def energy(t):
    """0 — тишина, 1 — грув под голосом, 2 — полный бит."""
    if t < INTRO['t1']:
        return 1 if t > 1.0 else 0
    for p in PAIRS:
        if p['t0'] <= t < p['t1']:
            if t < p['a']['t0']:
                return 2
            if t >= p['sum']:
                return 2
            return 1
    if t >= OUTRO['t0']:
        return 2 if t < OUTRO['t1'] - 2.0 else 0
    return 1


KICKS = []
nb = int(DUR / BEAT)
for b in range(nb):
    t0 = b * BEAT
    e = energy(t0 + 0.01)
    if e == 0:
        continue
    pos = b % 4
    c = chord_at(t0)
    # барабаны
    if e == 2 or pos in (0, 2):
        add('drums', kick(), t0, 0.9 if e == 2 else 0.7); KICKS.append(t0)
    if pos in (1, 3):
        add('drums', clap(), t0, 0.75 if e == 2 else 0.45, rev=0.2)
    add('drums', hat(e == 2), t0 + BEAT / 2, 0.3 if e == 2 else 0.22, pan=0.3)
    for s in (1, 3):
        add('drums', hat(False), t0 + s * BEAT / 4, 0.16, pan=-0.3)
    # бас восьмыми
    root = CH[c][0] - 24 if CH[c][0] >= 52 else CH[c][0] - 12
    for hh in range(2):
        add('bass', bassnote(root + (12 if (pos * 2 + hh) % 4 == 3 and e == 2 else 0)), t0 + hh * BEAT / 2, 0.42 if e == 2 else 0.32)
    # арпеджио
    tones = [CH[c][0] + 12, CH[c][1] + 12, CH[c][2] + 12, CH[c][1] + 24]
    for hh in range(2):
        idx = (pos * 2 + hh) % 4
        add('music', pluck(tones[[0, 2, 3, 1][idx]], 0.4, 1.0 if e == 2 else 0.6), t0 + hh * BEAT / 2, 0.16, pan=0.4 * (1 if hh else -1), rev=0.3)
    # пэд на сильную долю такта
    if pos == 0:
        for m in CH[c]:
            add('music', pad(m + 12, BAR + 0.4), t0, 0.05, pan=rs.uniform(-0.5, 0.5), rev=0.4)

# лид-хук на итогах и в финале
HOOK = [(0, 76, 1), (1, 74, .5), (1.5, 72, .5), (2, 71, 1), (3, 72, 1), (4, 69, 1.5), (5.5, 71, .5), (6, 72, 1), (7, 74, 1)]
for t0 in [p['sum'] for p in PAIRS] + [OUTRO['t0'] + 0.5]:
    for bt, m, ln in HOOK:
        tb = t0 + bt * BEAT
        add('music', pluck(m + 12, ln * BEAT + 0.3, 1.2), tb, 0.2, pan=0.1, rev=0.45)
        add('music', bell(mtof(m + 12), 0.8), tb, 0.05, pan=-0.2, rev=0.5)

# ---------- события в кадре ----------
add('fx', boom(2.2), 0.15, 0.9)
add('fx', crash(), 0.15, 0.4, rev=0.4)
add('drums', kick(1.2), 0.15, 1.0); KICKS.append(0.15)
add('fx', boom(1.4), 0.5, 0.5)
for i in range(4):
    add('fx', blip(1200 + 160 * i), 1.4 + i * 0.62, 0.12, pan=(-0.3, 0.3)[i % 2], rev=0.3)

cuts = [s['t0'] for s in SCN[1:]]
for c in cuts:
    add('fx', riser(1.8, 300, 10000), c - 1.8, 0.32, rev=0.2)
    add('fx', whoosh(0.7, True), c - 0.45, 0.6, rev=0.15)
    r = crash(1.0)[::-1]
    add('fx', r, c - len(r) / SR, 0.25)
    for k in range(8):
        add('drums', snare(0.3 + 0.7 * k / 7), c - 1.0 + k * BEAT / 4, 0.28, pan=0.1 * (-1) ** k)

for p in PAIRS:
    hit = p['t0'] + 0.3
    add('fx', boom(2.0), hit, 0.9)
    add('fx', crash(), hit, 0.45, rev=0.5)
    add('drums', kick(1.2), hit, 0.9); KICKS.append(hit)
    add('fx', whoosh(0.35, True), p['t0'] - 0.02, 0.35, pan=-0.6)
    add('fx', whoosh(0.35, True), p['t0'] - 0.02, 0.35, pan=0.6)
    add('fx', blip(900), p['t0'] + 0.05, 0.2, rev=0.3)          # номер пары
    for key, pan in (('a', -0.3), ('b', 0.3)):
        c = p[key]
        add('fx', whoosh(0.5, key == 'a'), c['t0'] - 0.1, 0.45, pan=pan, rev=0.2)
        for i, kt in enumerate(c['kt']):                          # ключевые слова
            add('fx', blip(1500 + 200 * i), kt, 0.07, pan=pan * 0.5, rev=0.35)
    add('fx', whoosh(0.45, False), p['sum'] - 0.1, 0.4, rev=0.2)
    add('fx', boom(1.0), p['sum'] + 0.35, 0.45)
    for i in range(3):
        add('fx', pop(800 + 120 * i), p['sum'] + 0.45 + i * 0.12, 0.35, pan=-0.3)
        add('fx', pop(1000 + 120 * i), p['sum'] + 0.7 + i * 0.12, 0.35, pan=0.3)

o0 = OUTRO['t0']
add('fx', boom(2.4), o0, 0.7)
add('fx', crash(3.0), o0, 0.4, rev=0.6)
for i in range(4):
    add('fx', pop(700 + 100 * i), o0 + 0.25 + i * 0.12, 0.3, pan=(-0.4, 0.4)[i % 2])
lines = OUTRO['lines']
for ln in lines:
    for w in ln['words']:
        if w['w'].lower().startswith(('saqlab', 'ulashing', 'obuna')):
            add('fx', bell(mtof(88), 1.2), w['t0'], 0.12, rev=0.5)
            add('fx', pop(1100), w['t0'] - 0.1, 0.4)
add('fx', bell(mtof(81), 3.0), OUTRO['t1'] - 2.0, 0.15, rev=0.7)
n = int(3.0 * SR)
for m in CH['Am']:
    add('music', pad(m + 12, 3.2), OUTRO['t1'] - 2.0, 0.07, rev=0.6)

# ---------- сведение ----------
side = np.ones(N)
for k in KICKS:
    i = int(k * SR)
    m = min(N - i, int(0.35 * SR))
    seg = np.arange(m) / SR
    side[i:i + m] = np.minimum(side[i:i + m], 1 - 0.7 * np.exp(-seg / 0.09))
for ch in (0, 1):
    BUS['bass'][ch] *= side
    BUS['music'][ch] *= 0.6 + 0.4 * side


def read_voice():
    with wave.open(os.path.join(OUT, 'voice.wav')) as w:
        assert w.getframerate() == SR
        x = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(np.float64) / 32768
    v = np.zeros(N)
    v[:min(N, len(x))] = x[:N]
    return v


voice = read_voice()
# огибающая речи: атака 15 мс, спад 350 мс
hop = int(0.005 * SR)
rms = np.sqrt(np.convolve(voice ** 2, np.ones(hop * 4) / (hop * 4), 'same'))[::hop]
rms = np.clip(rms / (np.percentile(rms[rms > 1e-4], 75) + 1e-9), 0, 1)
env = np.zeros_like(rms)
a_up, a_dn = np.exp(-0.005 / 0.015), np.exp(-0.005 / 0.35)
for i in range(1, len(rms)):
    a = a_up if rms[i] > env[i - 1] else a_dn
    env[i] = a * env[i - 1] + (1 - a) * rms[i]
env = np.interp(np.arange(N), np.arange(len(env)) * hop, env)
duck = 1 - 0.5 * np.clip(env * 1.3, 0, 1)


def reverb(xl, xr, length=2.2, damp=5000):
    n = int(length * SR)
    tr = tt(n)
    out = []
    for x, seed in ((xl, 1), (xr, 2)):
        g = np.random.default_rng(seed)
        ir = fft_filter(g.standard_normal(n) * np.exp(-tr * 6.9 / length), lo=250, hi=damp)
        ir[:int(0.012 * SR)] = 0
        M = 1 << int(np.ceil(np.log2(len(x) + n)))
        y = np.fft.irfft(np.fft.rfft(x, M) * np.fft.rfft(ir, M), M)[:len(x)]
        out.append(y / np.sqrt(np.sum(ir ** 2)) * 0.5)
    return out


rl, rr = reverb(*SEND)
gains = {'drums': 0.95, 'bass': 0.9, 'music': 0.9, 'fx': 0.8}
mus = np.zeros((2, N))
for ch in (0, 1):
    for k, g in gains.items():
        mus[ch] += BUS[k][ch] * g * (duck if k != 'fx' else 0.55 + 0.45 * duck)
    mus[ch] += (rl, rr)[ch] * 0.55
mus = np.stack([fft_filter(mus[0], lo=30), fft_filter(mus[1], lo=30)])
mus /= np.max(np.abs(mus)) + 1e-9
mus = np.tanh(mus * 1.6) / np.tanh(1.6)
t = tt(N)
mus *= np.clip((DUR - t) / 1.2, 0, 1) ** 2
mus = mus[:, :int(DUR * SR)]
voice = voice[:int(DUR * SR)]


def write(path, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.89
    with wave.open(path, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x.T * 32767).astype('<i2').tobytes())


write(os.path.join(OUT, 'music.wav'), mus)
v = voice / (np.max(np.abs(voice)) + 1e-9)
write(os.path.join(OUT, 'mix.wav'), mus * 0.42 + np.stack([v, v]) * 0.82)
print('готово: out/music.wav, out/mix.wav')
