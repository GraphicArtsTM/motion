"""Чтение и запись .env (порядок и комментарии — для человека, который откроет файл)."""

from __future__ import annotations

from pathlib import Path

SECTIONS: list[tuple[str, list[str]]] = [
    ("Режим запуска", ["BOT_MODE", "COMPOSE_PROFILES", "ENVIRONMENT"]),
    ("Telegram", ["BOT_TOKEN", "BOT_USERNAME", "ADMIN_TELEGRAM_IDS", "ADMIN_NOTIFY_CHAT_ID", "WEBHOOK_URL",
                  "WEBHOOK_SECRET"]),
    ("Яндекс Fleet API", ["FLEET_API_BASE_URL", "FLEET_CLIENT_ID", "FLEET_API_KEY", "FLEET_PARK_ID"]),
    ("Хранилища (заполнено автоматически)", ["POSTGRES_PASSWORD", "DATABASE_URL", "REDIS_URL", "QUEUE_BACKEND"]),
    ("Веб-панель", ["ADMIN_SECRET_KEY", "ADMIN_BASE_URL", "PUBLIC_DOMAIN"]),
    ("Прочее", ["SENTRY_DSN", "LOG_LEVEL", "TZ_DISPLAY", "S3_BACKUP_BUCKET", "BACKUP_DIR"]),
]


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values


def write_env(path: Path, values: dict[str, str]) -> None:
    lines = ["# Создано мастером настройки (setup.bat). Можно править вручную; после правки — stop.bat и start.bat.",
             "# Не публикуйте этот файл: в нём токен бота и ключ API таксопарка.", ""]
    used: set[str] = set()
    for title, keys in SECTIONS:
        lines.append(f"# ── {title} ──")
        for key in keys:
            lines.append(f"{key}={_quote(values.get(key, ''))}")
            used.add(key)
        lines.append("")
    extra = [k for k in values if k not in used]
    if extra:
        lines.append("# ── Дополнительно ──")
        lines += [f"{k}={_quote(values[k])}" for k in extra]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _quote(value: str) -> str:
    value = str(value).replace("\n", " ")
    return f'"{value}"' if any(c in value for c in " #'") else value
