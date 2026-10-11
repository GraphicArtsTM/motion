#!/usr/bin/env bash
# Полная сборка аниме ЮЛДУЗ: голоса → тайминги → музыка и микс → кадры → out/yulduz-1920x1080.mp4
#   ./build.sh            — всё, кроме озвучки (берутся готовые out/voices, если есть)
#   ./build.sh --tts      — заново синтезировать голоса (нужен RHVoice: tools/build_rhvoice.sh)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
if [[ "${1:-}" == "--tts" || ! -d out/voices ]]; then
  [[ -x tools/rhvoice/src/build/src/test/RHVoice-test ]] || tools/build_rhvoice.sh
  python3 tts.py
fi
node render.mjs --cues
python3 audio.py
node render.mjs --jobs "${JOBS:-4}" --out out/frames.mp4
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/mix.wav \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -profile:v high -level 4.1 \
  -af "loudnorm=I=-15:TP=-1.0:LRA=11" -c:a aac -b:a 224k -ar 48000 \
  -shortest -movflags +faststart out/yulduz-1920x1080.mp4
echo "готово: out/yulduz-1920x1080.mp4"
