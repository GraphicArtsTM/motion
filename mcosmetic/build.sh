#!/usr/bin/env bash
# Полная сборка ролика: саундтрек (музыка + эффекты + голос) → кадры → итоговый mp4 1080×1920, 60 fps, AAC.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
python3 music.py assets/voice.wav out/soundtrack.wav
node render.mjs --fps 60 --out out/frames.mp4
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/soundtrack.wav \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high -level 4.2 \
  -af "loudnorm=I=-14:TP=-1.0:LRA=9" -c:a aac -b:a 256k -ar 48000 \
  -shortest -movflags +faststart out/mcosmetic-mega-chegirma-1080x1920.mp4
echo "готово: out/mcosmetic-mega-chegirma-1080x1920.mp4"
