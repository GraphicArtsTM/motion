"""Озвучка персонажей: каждая реплика из dialogue.json синтезируется своим голосом.

Голоса — офлайн-TTS: RHVoice (русские дикторы) и Piper (нейросетевой голос ru-irinia).
Тембр персонажа задаётся профилем (диктор, высота, темп) и пост-обработкой в mix.py
(рация у деда, металл в шлеме Кронова, эхо у Тени).

    python3 audio/voices.py          # → audio/voice/<id>.wav + audio/voice/durations.json

Свои записи: положите файл с именем реплики в audio/voice_user/ (n1.wav, d1.m4a, t10.mp3 …,
любой формат, который понимает ffmpeg) — он заменит синтезированный голос. Список реплик с таймингом
и подсказками — VOICEOVER.md.
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'voice')
USER = os.path.join(HERE, 'voice_user')
EXTS = ('.wav', '.mp3', '.m4a', '.ogg', '.opus', '.flac', '.aac', '.webm', '.mp4')
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


def user_file(lid):
    for e in EXTS:
        p = os.path.join(USER, lid + e)
        if os.path.exists(p):
            return p
    return None


def from_user(src, path):
    """Запись пользователя → «студийная» обработка: срез гула, шумодав, EQ, де-эссер, компрессор."""
    chain = ('highpass=f=80,afftdn=nr=10:nf=-42,equalizer=f=250:t=q:w=1:g=-2,equalizer=f=3500:t=q:w=1.4:g=3,'
             'deesser=i=0.4,acompressor=threshold=-22dB:ratio=3:attack=5:release=90:makeup=3,alimiter=limit=0.9')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-ac', '1', '-ar', '44100',
                    '-af', chain, '-c:a', 'pcm_s16le', path], check=True)


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
    order = sorted(lines, key=lambda l: l['t'])
    nxt = {l['id']: (order[i + 1]['t'] if i + 1 < len(order) else 1e9) for i, l in enumerate(order)}
    dur = {}
    for ln in lines:
        p = os.path.join(OUT, ln['id'] + '.wav')
        src = user_file(ln['id'])
        if src:
            from_user(src, p)
        else:
            synth(ln['who'], ln.get('say', ln['text']), p)
        dur[ln['id']] = round(trim(p), 3)
        slot = nxt[ln['id']] - ln['t'] - .15
        warn = f'  ⚠ длиннее окна {slot:.2f}s' if dur[ln['id']] > slot else ''
        print(f"{ln['id']:>4} {ln['who']:>8} {'ЗАПИСЬ' if src else 'синтез':>6} {dur[ln['id']]:5.2f}s  {ln['text']}{warn}")
    json.dump(dur, open(os.path.join(OUT, 'durations.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
