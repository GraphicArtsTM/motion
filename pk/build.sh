#!/usr/bin/env bash
# Собирает весь комплект ПК: ./build.sh  →  Рузибоев_Мухаммад/ + Рузибоев_Мухаммад.zip
set -euo pipefail
cd "$(dirname "$0")"
N=Рузибоев_Мухаммад
rm -rf build "$N" "$N.zip" для_себя
mkdir -p build/html build/pdf build/docx "$N"/{1_Резюме,2_CV_Europass,3_Объективка,4_Профили_hh_LinkedIn,5_Профиль_argos} для_себя

python3 src/gen_html.py build/html
python3 src/gen_guides.py build/html
node src/print.cjs build/html build/pdf
python3 src/gen_docx.py build/docx
soffice --headless --convert-to pdf --outdir build/docx build/docx/*.docx >/dev/null

cp build/pdf/resume_RU.pdf     "$N/1_Резюме/${N}_Резюме_RU.pdf"
cp build/pdf/resume_EN.pdf     "$N/1_Резюме/${N}_Resume_EN.pdf"
cp build/pdf/resume_UZ.pdf     "$N/1_Резюме/${N}_Rezyume_UZ.pdf"
cp build/pdf/europass_EN.pdf   "$N/2_CV_Europass/${N}_Europass_CV_EN.pdf"
cp build/pdf/europass_RU.pdf   "$N/2_CV_Europass/${N}_Europass_CV_RU.pdf"
cp build/docx/*.docx build/docx/*.pdf "$N/3_Объективка/"
[ -f screenshots/hh.uz.png ]    && cp screenshots/hh.uz.png screenshots/LinkedIn.png "$N/4_Профили_hh_LinkedIn/"
[ -f screenshots/argos.png ]    && cp screenshots/argos.png "$N/5_Профиль_argos/vacancy.argos.uz.png"
cp build/pdf/interview_script.pdf для_себя/Сценарий_видеоинтервью.pdf
cp build/pdf/profiles_guide.pdf   для_себя/Профили_что_заполнить.pdf

python3 - "$N" <<'PY'
import os, sys, zipfile
n = sys.argv[1]
with zipfile.ZipFile(n + ".zip", "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(n):
        for f in sorted(files):
            z.write(os.path.join(root, f))
PY
for f in "$N"/*/*.pdf; do printf '%-70s %s стр.\n' "$f" "$(pdfinfo "$f" | awk '/^Pages/{print $2}')"; done
