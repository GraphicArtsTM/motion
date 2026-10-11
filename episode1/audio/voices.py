"""Озвучка персонажей: каждая реплика из dialogue.json синтезируется своим голосом.

Голоса — офлайн-TTS: RHVoice (русские дикторы) и Piper (нейросетевой голос ru-irinia).
Тембр персонажа задаётся профилем (диктор, высота, темп) и пост-обработкой в mix.py
(рация у деда, металл в шлеме Кронова, эхо у Тени).

    python3 audio/voices.py          # → audio/voice/<id>.wav + audio/voice/durations.json
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'voice')
PIPER_MODEL = os.environ.get('PIPER_MODEL', '/opt/voices/ru-irinia-medium.onnx')

# диктор, высота %, темп %
PROFILES = {
    'timur':    ('rhv', 'aleksandr-hq', 112, 112),
    'narrator': ('rhv', 'aleksandr-hq', 104, 100),
    'ded':      ('rhv', 'yuriy', 76, 90),
    'kronov':   ('rhv', 'pavel', 80, 96),
    'vera':     ('piper', None, 0, 1.0),
    'shadow':   ('rhv', 'vitaliy', 62, 84),
    'crowd':    ('rhv', 'anna', 115, 120),
}


def synth(speaker, text, path):
    kind, voice, pitch, rate = PROFILES[speaker]
    if kind == 'rhv':
        subprocess.run(['RHVoice-test', '-p', voice, '-t', str(pitch), '-r', str(rate), '-o', path],
                       input=text.encode(), check=True, capture_output=True)
    else:
        subprocess.run([sys.executable, '-m', 'piper', '-m', PIPER_MODEL, '--length-scale', str(rate), '-f', path],
                       input=text.encode(), check=True, capture_output=True)


def trim(path):
    """Срезает тишину по краям, чтобы реплики вставали точно в тайминг."""
    w = wave.open(path)
    sr, n = w.getframerate(), w.getnframes()
    x = np.frombuffer(w.readframes(n), np.int16)
    w.close()
    env = np.abs(x.astype(float))
    thr = env.max() * 0.02
    idx = np.nonzero(env > thr)[0]
    a, b = max(idx[0] - int(.02 * sr), 0), min(idx[-1] + int(.06 * sr), len(x))
    x = x[a:b]
    w = wave.open(path, 'wb')
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(x.tobytes())
    w.close()
    return len(x) / sr


def main():
    lines = json.load(open(os.path.join(HERE, 'dialogue.json'), encoding='utf-8'))['lines']
    os.makedirs(OUT, exist_ok=True)
    dur = {}
    for ln in lines:
        p = os.path.join(OUT, ln['id'] + '.wav')
        synth(ln['who'], ln.get('say', ln['text']), p)
        dur[ln['id']] = round(trim(p), 3)
        print(f"{ln['id']:>4} {ln['who']:>8} {dur[ln['id']]:5.2f}s  {ln['text']}")
    json.dump(dur, open(os.path.join(OUT, 'durations.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
