#!/usr/bin/env bash
# Полная сборка рилса: HDR→SDR → трекинг экрана → музыка → монтаж → mp4 1080×1920, 60 fps.
#
# Исходники кладутся в src/ (в git их нет — они тяжёлые):
#   src/IMG_6290.MOV   — кадр 1, реакция (селфи)
#   src/IMG_6298.MOV   — кадр 2, монитор с After Effects
#   src/k3.mp4         — кадр 3, сам моушн-ролик Maxway (1080×1920, 30 с)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out work/sdr

# 1) iPhone пишет в HDR (HLG, BT.2020) — переводим в SDR BT.709 с тонмаппингом Hable
TM="zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
for n in IMG_6290 IMG_6298; do
  [ -f work/sdr/$n.mp4 ] || ffmpeg -y -loglevel error -i src/$n.MOV -vf "$TM,fps=60" -c:v libx264 -crf 12 -preset veryfast -g 30 -an work/sdr/$n.mp4
done
[ -f work/sdr/k3.mp4 ] || ffmpeg -y -loglevel error -i src/k3.mp4 -c:v copy -an work/sdr/k3.mp4

# 2) трекинг окна композиции After Effects на мониторе
[ -f track_6298.json ] || python3 track_screen.py work/sdr/IMG_6298.mp4 track_6298.json

# 3) музыка, 4) монтаж
python3 music.py out/music.wav
python3 edit.py --src work/sdr --track track_6298.json --out out/frames.mp4 --workers "${WORKERS:-4}"

# 5) финальный файл: H.264 High, AAC, громкость −14 LUFS (норма Instagram)
ffmpeg -y -loglevel error -i out/frames.mp4 -i out/music.wav \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -profile:v high -level 4.2 \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -af "loudnorm=I=-14:TP=-1.0:LRA=9" -c:a aac -b:a 256k -ar 48000 \
  -shortest -movflags +faststart out/maxway-reel-1080x1920.mp4

# 6) вариант со звуком из самого ролика Maxway: наша музыка до влёта в экран (6 с),
#    дальше — оригинальная дорожка кадра 3 (k3_t = T − 5)
ffmpeg -y -loglevel error -i out/maxway-reel-1080x1920.mp4 -i src/k3.mp4 -filter_complex \
  "[0:a]afade=t=out:st=5.92:d=0.12[a0];\
   [1:a]atrim=start=0.92,asetpts=PTS-STARTPTS,adelay=5920|5920,afade=t=in:st=5.92:d=0.1,aresample=48000[a1];\
   [a0][a1]amix=inputs=2:normalize=0:duration=first,loudnorm=I=-14:TP=-1.0:LRA=9[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 256k -ar 48000 -movflags +faststart \
  out/maxway-reel-1080x1920_original-audio.mp4
echo "готово: out/maxway-reel-1080x1920.mp4"
