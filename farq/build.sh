#!/usr/bin/env bash
# Полная сборка: озвучка + таймлайн → музыка и микс → кадры (параллельно) → out/farq-reels-1080x1920.mp4
#   ./build.sh                  — голос выбирается сам: edge → piper → mbrola
#   ./build.sh --engine edge    — нейроголос Microsoft uz-UZ-SardorNeural (нужна сеть)
#   ./build.sh --engine piper   — офлайн-нейроголос Piper (модель скачается в models/)
#   FPS=60 JOBS=8 ./build.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
FPS=${FPS:-30}
JOBS=${JOBS:-4}
python3 tts.py "$@"
python3 music.py
DUR=$(python3 -c "import json;print(json.load(open('out/timeline.json'))['duration'])")
rm -f out/part_*.mp4 out/parts.txt
for i in $(seq 0 $((JOBS - 1))); do
  A=$(python3 -c "print(round($DUR*$i/$JOBS*$FPS)/$FPS)"); B=$(python3 -c "print(round($DUR*($i+1)/$JOBS*$FPS)/$FPS)")
  node render.mjs --fps "$FPS" --from "$A" --to "$B" --out "out/part_$i.mp4" > "out/render_$i.log" 2>&1 &
  echo "file 'part_$i.mp4'" >> out/parts.txt
done
wait
ffmpeg -y -loglevel error -f concat -safe 0 -i out/parts.txt -c copy out/frames.mp4
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/mix.wav \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 22 -maxrate 9M -bufsize 18M -pix_fmt yuv420p -profile:v high -level 4.2 \
  -af "loudnorm=I=-14:TP=-1.0:LRA=9" -c:a aac -b:a 256k -ar 48000 \
  -shortest -movflags +faststart out/farq-reels-1080x1920.mp4
echo "готово: out/farq-reels-1080x1920.mp4"
