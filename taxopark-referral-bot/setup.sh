#!/usr/bin/env bash
# Мастер настройки: ./setup.sh → браузер http://localhost:8765
# На удалённом сервере сначала пробросьте порт: ssh -L 8765:localhost:8765 user@server
set -euo pipefail
cd "$(dirname "$0")"
docker compose --profile setup build setup
echo "Откройте в браузере: http://localhost:8765 — заполните шаги и нажмите «Сохранить»."
( sleep 5; command -v xdg-open >/dev/null && xdg-open http://localhost:8765 || command -v open >/dev/null && open http://localhost:8765 ) >/dev/null 2>&1 &
docker compose --profile setup run --rm --service-ports setup
if [ -n "$(docker compose ps -q web 2>/dev/null)" ]; then docker compose up -d --build --force-recreate --remove-orphans; fi
