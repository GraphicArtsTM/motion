#!/usr/bin/env bash
# Сборка звука серии: нарезка вашей записи → голоса → музыка/эффекты/сведение → soundtrack.m4a + lipsync.json
#   tools/audio.sh e02
# Нужно: python3 + numpy (+ numba для нарезки записи), ffmpeg; для синтеза голосов — RHVoice (и piper для Веры).
set -euo pipefail
cd "$(dirname "$0")/.."
EP=${1:-$(python3 -c "import json;print(json.load(open('episodes/index.json'))['default'])")}
D=episodes/$EP
[ -d "$D" ] || { echo "нет папки $D"; exit 1; }
# одна длинная запись всех реплик подряд → нарезка по репликам (правки раскладки: <запись>.map.json)
for f in "$D"/audio/voice_src/*.mp3 "$D"/audio/voice_src/*.m4a "$D"/audio/voice_src/*.wav; do
  [ -e "$f" ] && python3 engine/audio/align_voice.py "$EP" "$f"
done
python3 engine/audio/voices.py "$EP"
python3 engine/audio/mix.py "$EP"
ffmpeg -y -loglevel error -i "$D/assets/soundtrack.wav" -af "loudnorm=I=-15:TP=-1.0:LRA=11" -c:a aac -b:a 256k -ar 48000 "$D/assets/soundtrack.m4a"
echo "готово: $D/assets/soundtrack.m4a"
