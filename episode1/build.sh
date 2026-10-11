#!/usr/bin/env bash
# Полная сборка серии: голоса → звук → кадры (параллельно) → итоговый mp4 1920×1080, 24 fps.
#   ./build.sh            — всё
#   JOBS=2 ./build.sh     — число параллельных рендеров Chromium (по умолчанию 2)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out/parts
JOBS=${JOBS:-2}
FPS=${FPS:-24}

# озвучка: если есть общая запись audio/voice_src/*.mp3 — нарезаем её на реплики (см. audio/align_voice.py)
for f in audio/voice_src/*.mp3 audio/voice_src/*.m4a audio/voice_src/*.wav; do [ -e "$f" ] && python3 audio/align_voice.py "$f"; done
python3 audio/voices.py
python3 audio/mix.py
ffmpeg -y -loglevel error -i assets/soundtrack.wav -af "loudnorm=I=-15:TP=-1.0:LRA=11" -c:a aac -b:a 256k -ar 48000 assets/soundtrack.m4a

DUR=$(python3 -c "import json;t=json.load(open('timeline.json'));print(t['duration']+t.get('intro',0))")
STEP=$(python3 -c "print($DUR/$JOBS)")
for i in $(seq 0 $((JOBS-1))); do
  FROM=$(python3 -c "print(round($i*$STEP*$FPS)/$FPS)")
  TO=$(python3 -c "print(round(($i+1)*$STEP*$FPS)/$FPS)")
  node render.mjs --fps "$FPS" --from "$FROM" --to "$TO" --out "out/parts/p$i.mp4" > "out/parts/p$i.log" 2>&1 &
done
wait
: > out/parts/list.txt
for i in $(seq 0 $((JOBS-1))); do echo "file 'p$i.mp4'" >> out/parts/list.txt; done
ffmpeg -y -loglevel error -f concat -safe 0 -i out/parts/list.txt -c copy out/frames.mp4

# два прохода x264 ~3 Мбит/с: файл ~85 МБ укладывается в лимит GitHub
ffmpeg -y -loglevel error -i out/frames.mp4 -c:v libx264 -preset slow -b:v 3000k -pass 1 -passlogfile out/x264 -an -f null /dev/null
ffmpeg -y -loglevel error -i out/frames.mp4 -i assets/soundtrack.wav -map 0:v -map 1:a \
  -c:v libx264 -preset slow -b:v 3000k -maxrate 6000k -bufsize 12000k -pass 2 -passlogfile out/x264 \
  -pix_fmt yuv420p -profile:v high -level 4.2 \
  -af "loudnorm=I=-15:TP=-1.0:LRA=11" -c:a aac -b:a 160k -ar 48000 \
  -shortest -movflags +faststart out/pauk-novograda-s01e01-1920x1080.mp4
echo "готово: out/pauk-novograda-s01e01-1920x1080.mp4"
