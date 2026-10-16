"""Раскладка озвучки по таймлайну ролика.

Исходная озвучка (audio/voice.mp3, 17,4 с) идёт без пауз — для Reels это слишком быстро:
зритель не успевает прочитать текст. Режем её по тишине между фразами и ставим каждую
фразу на свою сцену, оставляя паузу, чтобы кадр успел «дочитаться».
Между «…ming so'm to'lang» и «qolgan summani…» — 6,5 с галереи фото брендирования без голоса.

    python3 voice.py out/voice.wav
"""
import subprocess
import sys
import wave
import numpy as np

SR = 48000
DUR = 36.2
# (начало в исходнике, конец в исходнике, момент в ролике) — разрезы приходятся на паузы
SEGMENTS = [
    (0.00, 2.74, 0.3),     # Endi brend ruxsatnomasi bizda aksiyada!
    (2.74, 4.77, 4.8),     # Atigi 440 ming so'm to'lang,
    (4.77, 7.30, 14.89),   # qolgan summani biz — taksopark — to'lab beramiz.
    (7.30, 10.67, 20.25),  # Yagona shartimiz — bizning taksoparkda ishlashingiz kifoya.
    (10.67, 12.37, 24.69), # Aksiya muddati cheklangan.
    (12.37, 14.93, 27.70), # Batafsil ma'lumot uchun hoziroq murojaat qiling.
    (14.93, 17.40, 30.49), # Telegramdan yozing yoki qo'ng'iroq qiling.
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
