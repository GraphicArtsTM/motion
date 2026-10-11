#!/usr/bin/env bash
# Полная сборка: озвучка + таймлайн → музыка и микс → кадры → out/farq-reels-1080x1920.mp4
#   ./build.sh                 — движок голоса выбирается сам (edge → mbrola)
#   ./build.sh --engine edge   — принудительно нейроголос uz-UZ-SardorNeural
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
FPS=${FPS:-30}
python3 tts.py "$@"
python3 music.py
node render.mjs --fps "$FPS" --out out/frames.mp4
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/mix.wav \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 24 -maxrate 7M -bufsize 14M -pix_fmt yuv420p -profile:v high -level 4.2 \
  -af "loudnorm=I=-14:TP=-1.0:LRA=9" -c:a aac -b:a 256k -ar 48000 \
  -shortest -movflags +faststart out/farq-reels-1080x1920.mp4
echo "готово: out/farq-reels-1080x1920.mp4"
