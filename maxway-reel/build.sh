#!/usr/bin/env bash
# Сборка трёх версий рилса на macOS/Linux (на Windows — RENDER.bat).
# Нужны Python 3 (numpy, opencv-python-headless, pillow) и ffmpeg с фильтром zscale.
set -euo pipefail
cd "$(dirname "$0")"
python3 render_all.py "$@"
