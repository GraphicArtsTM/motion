#!/usr/bin/env bash
# Полная сборка Reels: кадры исходников → трекинг ладоней → музыка → кадры ролика → mp4 1080×1920, 60 fps.
# Исходники кладутся в src/: IMG_6384.MOV (дубль с руками), «old video.mp4», «new video.mp4».
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out frames/take frames/old frames/new

# HLG (HDR с iPhone) → SDR bt709 с тональной компрессией
TM="zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
[ -f frames/take/0000.jpg ] || ffmpeg -v error -y -i src/IMG_6384.MOV -vf "$TM" -fps_mode passthrough -q:v 2 -start_number 0 frames/take/%04d.jpg
[ -f frames/new/0000.jpg ] || ffmpeg -v error -y -i "src/new video.mp4" -q:v 2 -start_number 0 frames/new/%04d.jpg
[ -f frames/old/0000.jpg ] || ffmpeg -v error -y -i "src/old video.mp4" -vf scale=1080:1920:flags=lanczos -q:v 2 -start_number 0 frames/old/%04d.jpg

# трекинг ладоней (нужны mediapipe и opencv; hands.js уже лежит в репозитории)
# python3 track_hands.py hand_landmarker.task frames/take hands.js

ffmpeg -v error -y -i "src/new video.mp4" -vn -ac 2 -ar 44100 out/new.wav
python3 sound.py out/new.wav out/music.wav
node render.mjs --fps 60 --out out/frames.mp4
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/music.wav \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 18 -maxrate 14M -bufsize 28M -pix_fmt yuv420p -profile:v high -level 4.2 \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -af "loudnorm=I=-14:TP=-1.0:LRA=9" -c:a aac -b:a 256k -ar 48000 \
  -shortest -movflags +faststart out/mcosmetic-reels-1080x1920.mp4
echo "готово: out/mcosmetic-reels-1080x1920.mp4"
