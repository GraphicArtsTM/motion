#!/usr/bin/env bash
# Запуск одной командой на Linux/macOS-сервере: ./start.sh
set -euo pipefail
cd "$(dirname "$0")"
command -v docker >/dev/null || { echo "Установите Docker: https://docs.docker.com/engine/install/"; exit 1; }
[ -f .env ] || ./setup.sh
env_get() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | tr -d '"'; }
if [ "$(env_get BOT_MODE)" = "webhook" ]; then
  DOMAIN="$(env_get PUBLIC_DOMAIN)"
  if ! docker compose run --rm --no-deps --entrypoint sh certbot -c "test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem"; then
    echo "Получаю HTTPS-сертификат для $DOMAIN (домен должен указывать на этот сервер, порт 80 открыт)..."
    docker compose run --rm --no-deps -p 80:80 --entrypoint certbot certbot certonly --standalone -d "$DOMAIN" \
      --agree-tos --register-unsafely-without-email --non-interactive
  fi
fi
docker compose up -d --build --remove-orphans
echo "Жду готовности..."
for _ in $(seq 60); do
  if curl -fs http://localhost:8000/health >/dev/null; then
    echo "ГОТОВО. Состояние: http://localhost:8000/   Бот: https://t.me/$(env_get BOT_USERNAME)"
    exit 0
  fi
  sleep 3
done
echo "Сервисы долго не отвечают — docker compose logs -f"; exit 1
