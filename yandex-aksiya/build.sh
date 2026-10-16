#!/usr/bin/env bash
# Полная сборка: музыка → кадры → сведение с озвучкой → out/yandex-aksiya-1080x1920.mp4 (60 fps, AAC).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
python3 music.py out/music.wav
node render.mjs --fps 60 --out out/frames.mp4
# озвучка: задержка 0,4 с, лёгкая компрессия; музыка приглушается под голосом (sidechain)
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/music.wav -i audio/voice.mp3 -filter_complex "
  [2:a]aresample=48000,aformat=channel_layouts=stereo,highpass=f=80,
       acompressor=threshold=-22dB:ratio=3:attack=5:release=120:makeup=2,volume=1.4,
       adelay=400|400,apad,asplit=2[vo][key];
  [1:a]aresample=48000,volume=0.3[mu];
  [mu][key]sidechaincompress=threshold=0.03:ratio=5:attack=20:release=280[bed];
  [bed][vo]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-14:TP=-1.0:LRA=11[a]" \
  -map 0:v -map "[a]" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high -level 4.2 \
  -c:a aac -b:a 256k -ar 48000 -shortest -movflags +faststart out/yandex-aksiya-1080x1920.mp4
echo "готово: out/yandex-aksiya-1080x1920.mp4"
