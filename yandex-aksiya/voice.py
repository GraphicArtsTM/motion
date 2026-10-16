"""Раскладка озвучки по таймлайну ролика.

Исходная озвучка (audio/voice.mp3, 15,6 с) идёт без пауз — для Reels это слишком быстро:
зритель не успевает прочитать текст. Режем её по тишине между фразами и ставим каждую
фразу на свою сцену, оставляя паузу, чтобы кадр успел «дочитаться».

    python3 voice.py out/voice.wav
"""
import subprocess
import sys
import wave
import numpy as np

SR = 48000
DUR = 30.0
# (начало в исходнике, конец в исходнике, момент в ролике) — разрезы приходятся на паузы
SEGMENTS = [
    (0.00, 2.53, 0.5),     # Endi brend ruxsatnomasi bizda aksiyada
    (2.53, 4.50, 4.8),     # Atigi 440 ming so'mga
    (4.50, 6.10, 8.8),     # Aksiyadan foydalanib qoling
    (6.10, 8.86, 13.4),    # Hujjatlaringizni tez va oson rasmiylashtiring
    (8.86, 10.51, 18.6),   # Aksiya muddati cheklangan
    (10.51, 13.14, 21.5),  # Batafsil ma'lumot uchun hoziroq murojaat qiling
    (13.14, 15.60, 24.3),  # Telegramdan yozing yoki qo'ng'iroq qiling
]

src = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', 'audio/voice.mp3', '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'],
                     check=True, capture_output=True).stdout
x = np.frombuffer(src, np.float32).astype(np.float64)
out = np.zeros(int(DUR * SR))
fade = int(0.012 * SR)
for a, b, at in SEGMENTS:
    seg = x[int(a * SR):int(b * SR)].copy()
    seg[:fade] *= np.linspace(0, 1, fade)
    seg[-fade:] *= np.linspace(1, 0, fade)
    i = int(at * SR)
    out[i:i + len(seg)] += seg[:len(out) - i]

pcm = (np.clip(out, -1, 1) * 32767).astype('<i2')
with wave.open(sys.argv[1] if len(sys.argv) > 1 else 'voice.wav', 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('готово:', sys.argv[1] if len(sys.argv) > 1 else 'voice.wav')
