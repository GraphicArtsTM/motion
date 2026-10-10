#!/usr/bin/env bash
# Полная сборка ролика: музыка → кадры → итоговый mp4 1080×1350, 60 fps, AAC.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
python3 music.py out/music.wav
node render.mjs --fps 60 --out out/frames.mp4
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/music.wav \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -profile:v high -level 4.2 \
  -af "loudnorm=I=-14:TP=-1.0:LRA=9" -c:a aac -b:a 256k -ar 48000 \
  -shortest -movflags +faststart out/muhr-promo-1080x1350.mp4
echo "готово: out/muhr-promo-1080x1350.mp4"
