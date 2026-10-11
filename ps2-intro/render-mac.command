#!/usr/bin/env bash
# macOS: двойной клик — установка библиотек и рендер обеих версий
cd "$(dirname "$0")" || exit 1
export PATH="$PWD/tools/node/bin:$PATH"
if ! command -v node >/dev/null 2>&1; then
  echo "=== Node.js не найден — скачиваю портативный Node.js 22 ==="
  OS=darwin; ARCH=$(uname -m); case "$ARCH" in arm64|aarch64) ARCH=arm64;; *) ARCH=x64;; esac
  V=v22.12.0; mkdir -p tools
  curl -fsSL "https://nodejs.org/dist/$V/node-$V-$OS-$ARCH.tar.gz" | tar xz -C tools && rm -rf tools/node && mv "tools/node-$V-$OS-$ARCH" tools/node
fi
command -v node >/dev/null 2>&1 || { echo "Установите Node.js с https://nodejs.org и запустите снова"; exit 1; }
if [ ! -f node_modules/playwright/package.json ] || [ ! -f node_modules/ffmpeg-static/package.json ]; then
  echo "=== Устанавливаю библиотеки (один раз, 1–3 минуты) ==="
  npm install --no-audit --no-fund --loglevel=error || exit 1
fi
node render-all.mjs "$@"
