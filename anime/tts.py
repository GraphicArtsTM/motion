"""Озвучка ЮЛДУЗ: RHVoice (русские голоса) → обработка → out/voices/*.wav + voice_data.js.

    python3 tts.py                 # все реплики
    python3 tts.py a4 b1           # только выбранные

Нужен собранный RHVoice (см. tools/build_rhvoice.sh): переменные RHVOICE_BIN и RHVOICE_DATA_PATH.
В тексте реплик «+» перед гласной — ударение.

Обработка:
  inner  — внутренний голос: лёгкая «комната», чуть мягче верх;
  spirit — птица Хумо: хорус, сияющий ревер;
  demon  — Дев: понижение, перегруз, двойник на октаву ниже, огромный ревер.
Огибающая громкости (24 к/с) пишется в voice_data.js — по ней двигаются губы персонажей.
"""
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out', 'voices')
SR = 48000
FPS = 24
BIN = os.environ.get('RHVOICE_BIN', os.path.join(HERE, 'tools', 'rhvoice', 'src', 'build', 'src', 'test', 'RHVoice-test'))
DATA = os.environ.get('RHVOICE_DATA_PATH', os.path.join(HERE, 'tools', 'rhvoice', 'src', 'data'))
rs = np.random.default_rng(3)


def read_wav(p):
    with wave.open(p) as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768
        if w.getnchannels() == 2:
            x = x.reshape(-1, 2).mean(1)
    return x, sr


def write_wav(p, x):
    y = np.clip(x, -1, 1)
    with wave.open(p, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y * 32767).astype(np.int16).tobytes())


def resample(x, ratio):
    """FFT-ресемплинг: длина × ratio."""
    n = len(x)
    m = int(round(n * ratio))
    X = np.fft.rfft(x)
    k = m // 2 + 1
    Y = np.zeros(k, complex)
    c = min(k, len(X))
    Y[:c] = X[:c]
    return np.fft.irfft(Y, m) * (m / n)


def fft_filter(x, lo=None, hi=None, order=2):
    n = len(x)
    M = 1 << int(np.ceil(np.log2(max(n, 2) * 2)))
    X = np.fft.rfft(x, M)
    f = np.fft.rfftfreq(M, 1 / SR)
    Hh = np.ones_like(f)
    if hi:
        Hh /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        Hh /= np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(X * Hh, M)[:n]


def conv(x, h):
    n = len(x) + len(h) - 1
    M = 1 << int(np.ceil(np.log2(n)))
    return np.fft.irfft(np.fft.rfft(x, M) * np.fft.rfft(h, M), M)[:n]


def ir(length, decay, bright=6000, pre=0.012):
    n = int(length * SR)
    t = np.arange(n) / SR
    h = rs.standard_normal(n) * np.exp(-t * 6.9 / decay)
    h = fft_filter(h, lo=180, hi=bright)
    h[:int(pre * SR)] = 0
    return h / np.sqrt((h ** 2).sum())


def chorus(x, depth=0.004, base=0.018, rate=0.7, voices=3):
    t = np.arange(len(x)) / SR
    out = np.zeros(len(x))
    for v in range(voices):
        d = (base + depth * np.sin(2 * np.pi * rate * (1 + .3 * v) * t + v * 2.1)) * SR
        idx = np.arange(len(x)) - d
        out += np.interp(idx, np.arange(len(x)), x, left=0, right=0)
    return out / voices


def process(x, fx, shout=False):
    pad = np.zeros(int(0.05 * SR))
    if fx == 'inner':
        x = fft_filter(x, lo=90, hi=9000)
        wet = conv(x, ir(0.9, 0.7, 5000))
        x = np.concatenate([x, np.zeros(len(wet) - len(x))]) + wet * 0.16
    elif fx == 'spirit':
        c = chorus(x)
        wet = conv(x + c, ir(3.2, 2.6, 7000, 0.03))
        y = x * 0.75 + c * 0.45
        x = np.concatenate([y, np.zeros(len(wet) - len(y))]) + wet * 0.42
        x = fft_filter(x, lo=140)
    elif fx == 'demon':
        lowr = resample(x, 1 / 0.80)          # ниже и медленнее
        sub = resample(x, 1 / 0.80)
        # «двойник» ниже: грубый сдвиг за счёт кольцевой модуляции + фильтр
        t = np.arange(len(sub)) / SR
        sub = fft_filter(sub * np.sin(2 * np.pi * 55 * t), hi=900) * 0.9
        y = np.tanh((lowr * 2.2 + sub) * 1.6) * 0.6
        y = fft_filter(y, lo=60, hi=5200)
        wet = conv(y, ir(3.8, 3.2, 3000, 0.04))
        x = np.concatenate([y, np.zeros(len(wet) - len(y))]) + wet * 0.5
    if shout:
        x = np.tanh(x * 2.4) * 0.8
        wet = conv(x, ir(2.4, 2.0, 6000, 0.02))
        x = np.concatenate([x, np.zeros(len(wet) - len(x))]) + wet * 0.3
    x = np.concatenate([pad, x])
    # обрезаем хвост тишины
    a = np.abs(x)
    nz = np.nonzero(a > 2e-3)[0]
    if len(nz):
        x = x[:min(len(x), nz[-1] + int(0.08 * SR))]
    return x / (np.max(np.abs(x)) + 1e-9) * 0.89


def envelope(x):
    hop = SR // FPS
    n = int(np.ceil(len(x) / hop))
    env = np.zeros(n)
    for i in range(n):
        s = x[i * hop:(i + 1) * hop]
        env[i] = np.sqrt((s ** 2).mean()) if len(s) else 0
    env = env / (np.percentile(env, 95) + 1e-9)
    return np.clip(env, 0, 1)


def synth(text, voice, pitch, rate):
    env = dict(os.environ, RHVOICE_DATA_PATH=DATA, RHVOICE_CONFIG_PATH=os.path.join(HERE, 'tools'))
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        tmp = f.name
    subprocess.run([BIN, '-p', voice, '-t', str(pitch), '-r', str(rate), '-o', tmp], input=text.encode(), env=env, check=True)
    x, sr = read_wav(tmp)
    os.unlink(tmp)
    return resample(x, SR / sr)


def main():
    spec = json.load(open(os.path.join(HERE, 'script.json'), encoding='utf-8'))
    only = set(sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    data_path = os.path.join(HERE, 'voice_data.js')
    data = {}
    if os.path.exists(data_path) and only:
        txt = open(data_path, encoding='utf-8').read()
        data = json.loads(txt[txt.index('{'):txt.rindex('}') + 1])
    for ln in spec['lines']:
        if only and ln['id'] not in only:
            continue
        v = spec['voices'][ln['who']]
        x = synth(ln['text'], v['voice'], v.get('pitch', 100), v.get('rate', 100))
        x = process(x, v.get('fx'), ln.get('shout', False))
        write_wav(os.path.join(OUT, ln['id'] + '.wav'), x)
        env = envelope(x)
        data[ln['id']] = {'who': ln['who'], 'dur': round(len(x) / SR, 3), 'sub': ln['sub'],
                          'env': [round(float(e), 2) for e in env]}
        print(f"{ln['id']:4s} {ln['who']:8s} {len(x) / SR:5.2f} с  {ln['sub']}")
    order = [l['id'] for l in spec['lines'] if l['id'] in data]
    names = {k: {'name': v['name'], 'color': v['color']} for k, v in spec['voices'].items()}
    with open(data_path, 'w', encoding='utf-8') as f:
        f.write('/* сгенерировано tts.py: длительности реплик и огибающие для синхронизации губ (24 к/с) */\n')
        f.write('window.SPEAKERS = ' + json.dumps(names, ensure_ascii=False) + ';\n')
        f.write('window.VOICE = ' + json.dumps({k: data[k] for k in order}, ensure_ascii=False, separators=(',', ':')) + ';\n')


if __name__ == '__main__':
    main()
