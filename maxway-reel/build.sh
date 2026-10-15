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

# 3) музыка для вступления (до влёта в экран; дальше звучит оригинал ролика Maxway)
python3 music.py out/music.wav

# 4) монтаж: хвост 6–35 с общий, вступление 0–6 с — на каждый вариант текста
TITLES="${TITLES:-reklama posmotrite rabota}"
python3 edit.py --src work/sdr --track track_6298.json --range 6:35 --out out/tail.mp4 --workers "${WORKERS:-4}"
for t in $TITLES; do
  python3 edit.py --src work/sdr --track track_6298.json --title "$t" --range 0:6 --out out/intro_$t.mp4 --workers "${WORKERS:-4}"
  printf "file '%s'\nfile '%s'\n" "$PWD/out/intro_$t.mp4" "$PWD/out/tail.mp4" > out/concat_$t.txt
  # 5) звук: наша музыка до 5,92 с, затем оригинальная дорожка кадра 3 (k3_t = T − 5);
  #    H.264 High, AAC, −14 LUFS (норма Instagram)
  ffmpeg -y -loglevel error -f concat -safe 0 -i out/concat_$t.txt -i out/music.wav -i src/k3.mp4 -filter_complex \
    "[1:a]afade=t=out:st=5.92:d=0.12,aresample=48000[a0];\
     [2:a]atrim=start=0.92,asetpts=PTS-STARTPTS,adelay=5920|5920,afade=t=in:st=5.92:d=0.1,aresample=48000[a1];\
     [a0][a1]amix=inputs=2:normalize=0:duration=longest,atrim=end=35,loudnorm=I=-14:TP=-1.0:LRA=9[a]" \
    -map 0:v -map "[a]" -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -profile:v high -level 4.2 \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 -c:a aac -b:a 256k -ar 48000 \
    -t 35 -movflags +faststart out/maxway-reel_$t.mp4
done
cp out/maxway-reel_reklama.mp4 out/maxway-reel-1080x1920.mp4
echo "готово: out/maxway-reel-1080x1920.mp4 (+ варианты out/maxway-reel_<текст>.mp4)"
