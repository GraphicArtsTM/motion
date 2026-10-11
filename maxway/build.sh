#!/usr/bin/env bash
# Полная сборка ролика: музыка → кадры → итоговый mp4 1080×1920 (9:16), 60 fps, AAC.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
python3 music.py out/music.wav
node render.mjs --fps 60 --out out/frames.mp4
# два прохода на 16 Мбит/с: с зерном плёнки CRF раздувает файл, а так он помещается в лимиты соцсетей и GitHub
ffmpeg -y -loglevel error -i out/frames.mp4 -c:v libx264 -preset slow -b:v 16M -maxrate 24M -bufsize 32M \
  -pix_fmt yuv420p -profile:v high -level 4.2 -pass 1 -passlogfile out/x264 -an -f mp4 /dev/null
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/music.wav \
  -map 0:v -map 1:a -c:v libx264 -preset slow -b:v 16M -maxrate 24M -bufsize 32M -pix_fmt yuv420p -profile:v high -level 4.2 \
  -pass 2 -passlogfile out/x264 \
  -af "loudnorm=I=-14:TP=-1.0:LRA=9" -c:a aac -b:a 256k -ar 48000 \
  -shortest -movflags +faststart out/maxway-klabjon-1080x1920.mp4
echo "готово: out/maxway-klabjon-1080x1920.mp4"
