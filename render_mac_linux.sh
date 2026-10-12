#!/usr/bin/env bash
# Паук Новограда: установка всего нужного и рендер серии одной командой.
#   ./render_mac_linux.sh              — спросит номер серии (Enter — серия по умолчанию)
#   ./render_mac_linux.sh e02          — серия 2, 1920×1080, 30 fps, высокое качество
#   ./render_mac_linux.sh e01 --fps 24 — любые параметры make-video.mjs
set -e
cd "$(dirname "$0")"
echo
echo "  ПАУК НОВОГРАДА — сборка видео серии"
echo

if ! command -v node >/dev/null 2>&1; then
  echo "  Node.js не найден — пробую установить…"
  if [ "$(uname)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then brew install node
  elif command -v apt-get >/dev/null 2>&1; then curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs
  else
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm install --lts
  fi
fi

EPARG=()
if [[ ! "${1:-}" =~ ^e[0-9]+$ ]]; then
  read -r -p "  Какую серию собрать? Номер (1, 2, …), Enter — по умолчанию: " N || true
  if [[ "$N" =~ ^[0-9]+$ ]]; then EPARG=(--ep "$(printf 'e%02d' "$N")"); fi
fi

echo "  [1/3] Устанавливаю библиотеки (Playwright, ffmpeg)…"
npm install --no-audit --no-fund
echo "  [2/3] Скачиваю браузер для рендера (один раз, ~150 МБ)…"
if [ "$(uname)" = "Linux" ]; then npx playwright install --with-deps chromium || npx playwright install chromium; else npx playwright install chromium; fi
echo "  [3/3] Рендер…"
node make-video.mjs "${EPARG[@]}" "$@"
echo
echo "  Готово! Видео лежит в папке out/"
