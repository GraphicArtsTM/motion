"""Саунд-дизайн для интро PS2: оригинальная музыка + синтезированные звуковые эффекты (только numpy).

  python sfx.py            — собирает audio/soundtrack.wav (Remake, 20 с) и audio/soundtrack_pro.wav (Director's Cut, 26 с)

Оригинальная дорожка (audio/original.wav) идёт без изменений. Всё остальное синтезируется:
низкие удары, гул, свисты пролётов, райзеры, мерцание, гранулярные искры, пэды, реверберация.
Время событий совпадает с js/intro.js: r — время оригинальной дорожки, в pro она сдвинута на OFF = 2.5 с.
"""
import sys, wave
from pathlib import Path
import numpy as np

SR = 48000
HERE = Path(__file__).resolve().parent
rng = np.random.default_rng(2000)

# ---------------------------------------------------------------- утилиты
def read_wav(path):
    with wave.open(str(path)) as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64) / 32768
    a = a.reshape(-1, ch)
    if ch == 1: a = np.repeat(a, 2, 1)
    if sr != SR:
        x = np.arange(len(a)) / sr; xi = np.arange(int(len(a) * SR / sr)) / SR
        a = np.stack([np.interp(xi, x, a[:, c]) for c in range(2)], 1)
    return a

def write_wav(path, a):
    a = np.clip(a, -1, 1)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((a * 32767).astype('<i2').tobytes())

def tt(dur): return np.arange(int(dur * SR)) / SR

def pan(m, p):
    """m — моно, p ∈ [-1, 1] (скаляр или массив) → стерео с равномощным панорамированием"""
    p = np.asarray(p); ang = (p + 1) * np.pi / 4
    return np.stack([m * np.cos(ang), m * np.sin(ang)], 1)

def stft_shape(x, gain_fn, nfft=2048, hop=512):
    """время-зависимая фильтрация: gain_fn(t_center, freqs) → множитель спектра"""
    win = np.hanning(nfft); n = len(x)
    pad = np.concatenate([np.zeros(nfft), x, np.zeros(nfft)])
    out = np.zeros_like(pad); norm = np.zeros_like(pad)
    fr = np.fft.rfftfreq(nfft, 1 / SR)
    for st in range(0, len(pad) - nfft, hop):
        seg = pad[st:st + nfft] * win
        tc = (st + nfft / 2 - nfft) / SR
        sp = np.fft.rfft(seg) * gain_fn(tc, fr)
        out[st:st + nfft] += np.fft.irfft(sp) * win; norm[st:st + nfft] += win ** 2
    return (out / np.maximum(norm, 1e-6))[nfft:nfft + n]

def band(fr, fc, oct_w):
    """гауссова полоса в октавах вокруг fc"""
    return np.exp(-0.5 * (np.log2(np.maximum(fr, 1) / fc) / oct_w) ** 2)

def lowpass_static(x, fc, order=2):
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(np.fft.rfft(x) / (1 + (fr / fc) ** (2 * order)) ** .5, len(x))

def highpass_static(x, fc, order=2):
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    g = (fr / fc) ** order / np.sqrt(1 + (fr / fc) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x) * g, len(x))

def noise(dur): return rng.standard_normal(int(dur * SR))

# ---------------------------------------------------------------- звуки
def boom(dur=3.0, f0=110, f1=32, k=9, dec=0.9, click=0.5):
    t = tt(dur)
    f = f1 + (f0 - f1) * np.exp(-t * k)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / dec) * np.minimum(1, t / .004)
    sub2 = np.sin(ph * .5) * np.exp(-t / (dec * 1.4)) * .35
    cl = lowpass_static(noise(dur), 2500) * np.exp(-t / .02) * click
    return np.tanh((body + sub2) * 1.6) * .9 + cl

def impact(dur=2.5, bright=1.0):
    t = tt(dur); n = noise(dur)
    crack = stft_shape(n, lambda tc, fr: band(fr, 1800 * bright, 1.6) * np.exp(-max(tc, 0) / .12)) * 1.2
    body = lowpass_static(n, 400) * np.exp(-t / .25) * .8
    return crack + body

def whoosh(dur, f_from, f_to, peak=.5, width=.7, sharp=2.0):
    """свист пролёта: полосовой шум, центр едет f_from→f_to, пик громкости в доле peak"""
    n = noise(dur)
    def g(tc, fr):
        p = np.clip(tc / dur, 0, 1); fc = f_from * (f_to / f_from) ** p
        return band(fr, fc, width)
    x = stft_shape(n, g)
    t = tt(dur) / dur
    e = np.where(t < peak, (t / peak) ** sharp, np.exp(-(t - peak) / (1 - peak) * 4))
    return x * e

def riser(dur, f0=200, f1=2400, shepard=True):
    t = tt(dur); p = t / dur
    n = noise(dur)
    x = stft_shape(n, lambda tc, fr: band(fr, f0 * (f1 / f0) ** np.clip(tc / dur, 0, 1), .9)) * p ** 2.2
    if shepard:   # бесконечно растущий тон
        tone = np.zeros_like(t)
        for k in range(6):
            fk = 55 * 2 ** ((k + 2.2 * p) % 6)
            amp = np.exp(-0.5 * ((np.log2(fk / 55) - 3) / 1.2) ** 2)
            tone += np.sin(2 * np.pi * np.cumsum(fk) / SR) * amp
        x = x + tone * .12 * p ** 1.6
    return x

def shimmer(dur, base=1400, n=18, att=.4, dec=1.2, seed=0):
    r = np.random.default_rng(seed); t = tt(dur); out = np.zeros((len(t), 2))
    for k in range(n):
        f = base * (1 + r.random() * 3.5); a = r.random() ** 2
        ph = r.random() * 6.28; lfo = 1 + .5 * np.sin(2 * np.pi * (0.5 + r.random() * 3) * t + ph)
        m = np.sin(2 * np.pi * f * t + ph) * a * lfo
        out += pan(m, r.random() * 2 - 1)
    e = np.minimum(1, t / att) * np.exp(-np.maximum(0, t - att) / dec)
    return out * e[:, None] / n * 3

def bell(dur, f, dec=1.5, ratio=(1, 2.76, 5.4, 8.93), amps=(1, .5, .25, .12)):
    t = tt(dur); x = sum(a * np.sin(2 * np.pi * f * r_ * t) * np.exp(-t / (dec / (1 + i * .8))) for i, (r_, a) in enumerate(zip(ratio, amps)))
    return x * np.minimum(1, t / .002)

def sparkle(dur, density, seed=1, fmin=2500, fmax=9000):
    """гранулярные искры: короткие пинги, density(t) — зёрен в секунду"""
    r = np.random.default_rng(seed); n = int(dur * SR); out = np.zeros((n, 2))
    g = tt(.06); t = 0.0
    while t < dur:
        d = max(density(t), .5); t += r.exponential(1 / d)
        if t >= dur: break
        f = fmin * (fmax / fmin) ** r.random()
        gr = np.sin(2 * np.pi * f * g) * np.exp(-g / (.006 + r.random() * .02)) * (0.3 + r.random() * .7)
        i = int(t * SR); m = min(len(gr), n - i)
        out[i:i + m] += pan(gr[:m], r.random() * 2 - 1)
    return out

def pad(dur, freqs, att=1.5, rel=2.0, cutoff=900, detune=.18, seed=3):
    r = np.random.default_rng(seed); t = tt(dur); out = np.zeros((len(t), 2))
    for f in freqs:
        for v in range(4):
            fv = f * 2 ** ((r.random() - .5) * detune / 12)
            saw = sum(np.sin(2 * np.pi * fv * h * t + r.random() * 6.28) / h for h in range(1, 14) if fv * h < cutoff * 3)
            out += pan(saw, (v / 1.5 - 1) * .8)
    out[:, 0] = lowpass_static(out[:, 0], cutoff); out[:, 1] = lowpass_static(out[:, 1], cutoff)
    e = np.minimum(1, t / att) * np.minimum(1, np.maximum(0, dur - t) / rel)
    return out * e[:, None] / (len(freqs) * 4)

def rumble(dur, att=1.5, rel=1.5, fc=70):
    t = tt(dur); n = lowpass_static(noise(dur), fc, 3)
    e = np.minimum(1, t / att) ** 2 * np.minimum(1, np.maximum(0, dur - t) / rel)
    return n * e * 2.2

def tremolo_whoosh(dur, rate_fn, f0=500, f1=2500):
    """спиральные пролёты: шум с ускоряющейся пульсацией и панорамой по кругу"""
    t = tt(dur); n = noise(dur)
    x = stft_shape(n, lambda tc, fr: band(fr, f0 * (f1 / f0) ** np.clip(tc / dur, 0, 1), .8))
    ph = 2 * np.pi * np.cumsum(rate_fn(t)) / SR
    am = (.5 + .5 * np.sin(ph)) ** 2
    return pan(x * am, np.sin(ph * .5) * .8)

def reverb_ir(dur=3.0, dec=1.1, seed=9):
    r = np.random.default_rng(seed); t = tt(dur)
    ir = r.standard_normal((len(t), 2)) * np.exp(-t / dec)[:, None]
    for c in range(2): ir[:, c] = lowpass_static(ir[:, c], 6000)
    ir[:int(.01 * SR)] *= np.linspace(0, 1, int(.01 * SR))[:, None]
    return ir / np.sqrt((ir ** 2).sum(0))

def convolve(x, ir):
    n = len(x) + len(ir); nf = 1 << (n - 1).bit_length()
    return np.stack([np.fft.irfft(np.fft.rfft(x[:, c], nf) * np.fft.rfft(ir[:, c], nf), nf)[:len(x)] for c in range(2)], 1)

# ---------------------------------------------------------------- микшер
class Mix:
    def __init__(self, dur):
        self.n = int(dur * SR); self.dry = np.zeros((self.n, 2)); self.wet = np.zeros((self.n, 2))
    def add(self, t0, x, g=1.0, p=0.0, send=0.3):
        if x.ndim == 1: x = pan(x, p)
        i = int(round(t0 * SR));
        if i < 0: x = x[-i:]; i = 0
        m = min(len(x), self.n - i)
        if m <= 0: return
        self.dry[i:i + m] += x[:m] * g; self.wet[i:i + m] += x[:m] * g * send
    def render(self, ir):
        return self.dry + convolve(self.wet, ir) * 1.4

def build(pro):
    OFF = 2.5 if pro else 0.0
    DUR = 26.0 if pro else 20.0
    HIT = 14.36
    S = .85 if pro else .55                   # общая громкость эффектов относительно музыки
    mx = Mix(DUR)
    R = lambda r: r + OFF                     # время оригинала → абсолютное

    # ---- пролог (только Director's Cut)
    if pro:
        mx.add(0.05, rumble(1.0, att=.9, rel=.2, fc=55), .3 * S)
        mx.add(0.30, riser(.32, 300, 3000, shepard=False), .25 * S, send=.5)               # всасывание перед зажиганием
        mx.add(0.62, boom(3.5, 140, 30, 10, 1.1, .6), .6 * S, send=.25)
        mx.add(0.62, bell(4.0, 587.3, 2.4) * .5 + bell(4.0, 880, 1.8) * .3, .25 * S, send=.7)
        mx.add(0.62, shimmer(3.0, 2200, 14, .05, 1.0, seed=4), .35 * S, send=.6)
        for k, (t0, p) in enumerate([(0.70, -.8), (0.74, .8), (0.78, -.3), (0.82, .3)]):
            mx.add(t0, whoosh(1.6, 5000, 900, peak=.12, width=.5, sharp=1.2), .2 * S, p=p, send=.4)
            mx.add(t0, bell(.4, 2000 + 600 * k, .08) * .4, .3 * S, p=p, send=.5)
        mx.add(0.66, whoosh(1.8, 120, 60, peak=.1, width=.8) * 2, .3 * S, send=.3)      # волна по полу
        for t0 in (1.45, 1.70, 2.25, 2.50):
            mx.add(t0, boom(1.2, 80, 40, 14, .25, .05), .3 * S, send=.15)                # «сердцебиение»
        mx.add(1.0, pad(11.0, [73.42, 110.0, 146.83, 220.0], att=2.5, rel=4.0, cutoff=600), .2 * S, send=.4)

    # ---- поле башен
    mx.add(R(.50), boom(3.0, 120, 34, 8, 1.0, .3), .4 * S, send=.3)
    mx.add(R(.45), rumble(5.6, att=2.0, rel=2.0, fc=90), .2 * S)
    for r0, g in [(1.55, .3), (2.30, .26), (4.40, .24), (7.20, .3)]:
        mx.add(R(r0), boom(1.6, 90, 38, 12, .35, .15), g * S, send=.25)
    for r0 in (3.10, 6.00):    # световые волны по башням
        mx.add(R(r0), whoosh(1.6, 300, 2500, peak=.25, width=.6), .14 * S, send=.6)
        mx.add(R(r0), shimmer(2.2, 1800, 12, .08, .7, seed=int(r0 * 10)), .14 * S, send=.6)
    mx.add(R(1.30), shimmer(2.8, 1600, 20, .35, 1.0, seed=7), .18 * S, send=.7)           # надпись
    mx.add(R(2.05), whoosh(1.3, 3000, 9000, peak=.5, width=.5), .12 * S, send=.6)
    for r0, p0, p1 in [(2.4, -.9, .9), (3.9, .9, -.9), (5.3, -.6, .8), (6.6, .7, -.7), (7.7, -.8, .6)]:
        d = 1.4; w = whoosh(d, 700, 2200, peak=.45, width=.55)
        mx.add(R(r0), pan(w, np.linspace(p0, p1, len(w))), .16 * S, send=.35)
    # нырок
    mx.add(R(7.25), riser(9.38 - 7.25, 250, 4500), .4 * S, send=.4)
    mx.add(R(8.75), whoosh(.75, 400, 3000, peak=.85, width=.8, sharp=3), .6 * S, send=.3)
    mx.add(R(9.38), boom(3.5, 150, 30, 9, 1.0, .7), .9 * S, send=.3)
    mx.add(R(9.38), impact(2.5, 1.2), .5 * S, send=.5)

    # ---- гиперпространство
    mx.add(R(9.40), whoosh(2.2, 4000, 400, peak=.05, width=1.0, sharp=1) * 1.5, .4 * S, send=.4)
    mx.add(R(9.50), pad(5.0, [55.0, 82.41, 110.0, 164.81], att=1.2, rel=.8, cutoff=600, seed=5), .55 * S, send=.4)
    mx.add(R(9.70), tremolo_whoosh(HIT - 9.70, lambda t: 1.0 + 11 * (t / (HIT - 9.7)) ** 2.5), .28 * S, send=.4)
    mx.add(R(11.6), riser(HIT - .06 - 11.6, 180, 6000), .6 * S, send=.35)
    mx.add(R(12.4), sparkle(HIT - .06 - 12.4, lambda t: 4 + 60 * (t / (HIT - 12.46)) ** 3, seed=11, fmin=1500, fmax=7000), .25 * S, send=.4)
    mx.add(R(HIT - .9), whoosh(.84, 6000, 300, peak=.97, width=.9, sharp=4), .45 * S, send=.2)   # «вдох» перед ударом

    # ---- удар логотипа
    mx.add(R(HIT), boom(5.0, 160, 28, 8, 1.5, .5), .75 * S, send=.3)
    mx.add(R(HIT), impact(3.0, 1.0), (.14 if pro else .22) * S, send=.6)
    mx.add(R(HIT), shimmer(4.5, 2600, 26, .03, 1.8, seed=21), (.12 if pro else .2) * S, send=.8)
    if pro:
        u = lambda x: R(HIT) + x
        mx.add(u(.3), sparkle(1.3, lambda t: 140 * np.exp(-t * 1.5) + 30, seed=31, fmin=3000, fmax=11000), .16 * S, send=.5)
        mx.add(u(.25), whoosh(1.2, 1500, 7000, peak=.85, width=.8, sharp=2), .1 * S, send=.4)      # частицы летят в форму
        mx.add(u(1.30), boom(2.0, 90, 45, 14, .4, .3), .4 * S, send=.3)                          # логотип «защёлкнулся»
        mx.add(u(1.30), bell(4.0, 1567.98, 2.0) * .4 + bell(4.0, 2349.3, 1.6) * .25, .12 * S, send=.8)
        for s0, d in [(1.3, 1.8), (4.4, 1.6)]:                                                    # блики по логотипу
            w = whoosh(d, 2500, 12000, peak=.5, width=.5)
            mx.add(u(s0), pan(w, np.linspace(-.7, .7, len(w))), .15 * S, send=.7)
        mx.add(u(.2), tremolo_whoosh(4.0, lambda t: 1.2 + 0 * t, 1200, 2400), .08 * S, send=.5)   # огни облетают логотип
        mx.add(u(1.8), pad(DUR - u(1.8), [98.0, 146.83, 220.0, 293.66], att=3.0, rel=3.5, cutoff=900, seed=8), .3 * S, send=.5)
        mx.add(u(1.0), rumble(DUR - u(1.0), att=1.5, rel=4, fc=50), .15 * S)
    else:
        mx.add(R(HIT + .5), whoosh(1.5, 2500, 11000, peak=.5, width=.5), .12 * S, send=.7)
        mx.add(R(HIT + 2.6), whoosh(1.4, 2500, 11000, peak=.5, width=.5), .1 * S, send=.7)

    sfx = mx.render(reverb_ir(3.5, 1.2))
    sfx[:, 0] = highpass_static(sfx[:, 0], 22); sfx[:, 1] = highpass_static(sfx[:, 1], 22)

    # ---- оригинальная музыка
    orig = read_wav(HERE / 'audio' / 'original.wav')
    music = np.zeros_like(sfx); i = int(OFF * SR); m = min(len(orig), len(music) - i)
    music[i:i + m] = orig[:m]

    out = music * 1.35 + sfx
    t = np.arange(len(out)) / SR
    out0 = 23.9 if pro else 18.3
    fade = np.clip(1 - (t - (out0 + .3)) / (DUR - out0 - .3), 0, 1) ** 1.5
    out *= fade[:, None]
    out = np.tanh(out * 1.1) / np.tanh(1.1)                       # мягкий лимитер
    out *= 0.89 / np.abs(out).max()                               # пик −1 dBFS
    return out

if __name__ == '__main__':
    for pro, name in [(False, 'soundtrack.wav'), (True, 'soundtrack_pro.wav')]:
        a = build(pro); write_wav(HERE / 'audio' / name, a)
        rms = 20 * np.log10(np.sqrt((a ** 2).mean()) + 1e-9)
        print(f'audio/{name}: {len(a) / SR:.1f} с, RMS {rms:.1f} dBFS')
