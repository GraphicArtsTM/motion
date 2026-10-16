#!/usr/bin/env bash
# Полная сборка ролика для Instagram Reels:
# озвучка с паузами → музыка и эффекты → кадры → сведение → out/yandex-aksiya-reels-1080x1920.mp4
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
python3 voice.py out/voice.wav
python3 music.py out/music.wav out/sfx.wav
node render.mjs --fps 30 --out out/frames.mp4
# голос — лёгкая компрессия; музыка приглушается под голосом (sidechain);
# эффекты идут отдельной дорожкой и приглушаются под голосом лишь слегка, чтобы их было слышно.
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/music.wav -i out/sfx.wav -i out/voice.wav -filter_complex "
  [3:a]aresample=48000,aformat=channel_layouts=stereo,highpass=f=80,
       acompressor=threshold=-22dB:ratio=3:attack=5:release=120:makeup=2,volume=1.6,asplit=3[vo][k1][k2];
  [1:a]aresample=48000,volume=0.22[mu];
  [mu][k1]sidechaincompress=threshold=0.02:ratio=8:attack=15:release=300[bed];
  [2:a]aresample=48000,volume=0.45[fx0];
  [fx0][k2]sidechaincompress=threshold=0.03:ratio=3:attack=5:release=200[fx];
  [bed][fx][vo]amix=inputs=3:duration=first:normalize=0,alimiter=limit=0.95:attack=3:release=60,
       loudnorm=I=-14:TP=-1.0:LRA=11[a]" \
  -map 0:v -map "[a]" -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -profile:v high -level 4.2 \
  -r 30 -g 60 -c:a aac -b:a 256k -ar 48000 -shortest -movflags +faststart out/yandex-aksiya-reels-1080x1920.mp4
echo "готово: out/yandex-aksiya-reels-1080x1920.mp4"
