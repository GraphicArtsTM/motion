"""Сервер мастера настройки. Открывается setup.bat → http://localhost:8765."""

from __future__ import annotations

import asyncio
import base64
import io
import json
import os
import secrets
from pathlib import Path
from typing import Any

import pyotp
import qrcode
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from src.admin.auth import hash_password
from src.setup_wizard.checks import fleet_check, telegram_chats, telegram_check
from src.setup_wizard.envfile import read_env, write_env

WORKSPACE = Path(os.environ.get("WORKSPACE", "."))
ENV_PATH = WORKSPACE / ".env"
CONFIG_DIR = WORKSPACE / "config"
NGINX_TEMPLATE = WORKSPACE / "deploy" / "nginx.conf.template"
NGINX_OUT = WORKSPACE / "deploy" / "nginx.generated.conf"
PAGE = Path(__file__).with_name("page.html")
DEFAULT_FLEET_URL = "https://fleet-api.taxi.yandex.net"
DEFAULT_CONTACTS = ("<b>Таксопарк</b>\nТелефон: +998 __ ___ __ __\nАдрес: ...\nМенеджер: @...\n"
                    "Часы работы: 09:00–18:00")

app = FastAPI(title="Мастер настройки", docs_url=None, redoc_url=None)
app.state.server = None


def mask(value: str) -> str:
    return f"{value[:4]}…{value[-4:]}" if len(value) > 12 else ("•••" if value else "")


class TokenIn(BaseModel):
    token: str = ""


class FleetIn(BaseModel):
    base_url: str = DEFAULT_FLEET_URL
    client_id: str = ""
    api_key: str = ""
    park_id: str = ""


class TotpVerifyIn(BaseModel):
    secret: str
    code: str


class SaveIn(BaseModel):
    bot_token: str = ""
    bot_username: str = ""
    admin_ids: list[int] = []
    admin_chat_id: int | None = None
    mode: str = "polling"
    domain: str = ""
    fleet_provider: str = "api"
    fleet_base_url: str = DEFAULT_FLEET_URL
    fleet_client_id: str = ""
    fleet_api_key: str = ""
    fleet_park_id: str = ""
    fleet_category_id: str = ""
    fleet_categories: list[dict[str, Any]] = []
    can_payout: bool = True
    withdrawal_mode: str = "auto"
    park_contacts: str = ""
    panel_login: str = ""
    panel_password: str = ""
    panel_telegram_id: int | None = None
    totp_secret: str = ""
    totp_code: str = ""


@app.get("/", response_class=HTMLResponse)
async def page() -> str:
    return PAGE.read_text(encoding="utf-8")


@app.get("/api/current")
async def current() -> dict[str, Any]:
    env = read_env(ENV_PATH)
    applied = CONFIG_DIR / "initial_settings.applied.json"
    prev: dict[str, Any] = {}
    if applied.exists():
        prev = json.loads(applied.read_text(encoding="utf-8")).get("settings", {})
    return {
        "exists": ENV_PATH.exists(),
        "bot_token_masked": mask(env.get("BOT_TOKEN", "")),
        "bot_username": env.get("BOT_USERNAME", ""),
        "admin_ids": [int(x) for x in env.get("ADMIN_TELEGRAM_IDS", "").replace(";", ",").split(",") if x.strip()],
        "admin_chat_id": env.get("ADMIN_NOTIFY_CHAT_ID", ""),
        "mode": env.get("BOT_MODE", "polling"),
        "domain": env.get("PUBLIC_DOMAIN", ""),
        "fleet_base_url": env.get("FLEET_API_BASE_URL", DEFAULT_FLEET_URL),
        "fleet_client_id": env.get("FLEET_CLIENT_ID", ""),
        "fleet_api_key_masked": mask(env.get("FLEET_API_KEY", "")),
        "fleet_park_id": env.get("FLEET_PARK_ID", ""),
        "park_contacts": prev.get("park_contacts", DEFAULT_CONTACTS),
        "withdrawal_mode": prev.get("withdrawal_mode", "auto"),
        "fleet_category_id": prev.get("fleet_transaction_category_id", ""),
    }


def _token(raw: str) -> str:
    return raw.strip() or read_env(ENV_PATH).get("BOT_TOKEN", "")


@app.post("/api/telegram/check")
async def tg_check(body: TokenIn) -> dict[str, Any]:
    return await telegram_check(_token(body.token))


@app.post("/api/telegram/chats")
async def tg_chats(body: TokenIn) -> dict[str, Any]:
    return await telegram_chats(_token(body.token))


@app.post("/api/fleet/check")
async def fl_check(body: FleetIn) -> dict[str, Any]:
    env = read_env(ENV_PATH)
    key = body.api_key.strip() or env.get("FLEET_API_KEY", "")
    return await fleet_check(body.base_url or DEFAULT_FLEET_URL, body.client_id, key, body.park_id)


@app.post("/api/totp/new")
async def totp_new(login: str = "admin") -> dict[str, str]:
    secret = pyotp.random_base32()
    uri = pyotp.TOTP(secret).provisioning_uri(name=login or "admin", issuer_name="Taxopark Referral")
    buf = io.BytesIO()
    qrcode.make(uri, box_size=6, border=2).save(buf, format="PNG")
    return {"secret": secret, "uri": uri, "qr": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()}


@app.post("/api/totp/verify")
async def totp_verify(body: TotpVerifyIn) -> dict[str, bool]:
    return {"ok": pyotp.TOTP(body.secret).verify(body.code.strip(), valid_window=1)}


def build_env(body: SaveIn, old: dict[str, str]) -> dict[str, str]:
    """Новые значения + сохранение секретов, которые нельзя менять (пароль БД уже записан в том Postgres)."""
    pg_password = old.get("POSTGRES_PASSWORD") or secrets.token_urlsafe(18)
    webhook = body.mode == "webhook" and body.domain.strip()
    domain = body.domain.strip().removeprefix("https://").removeprefix("http://").strip("/")
    return {
        "BOT_MODE": "webhook" if webhook else "polling",
        "COMPOSE_PROFILES": "webhook" if webhook else "polling",
        "ENVIRONMENT": "production",
        "BOT_TOKEN": body.bot_token.strip() or old.get("BOT_TOKEN", ""),
        "BOT_USERNAME": body.bot_username.strip().lstrip("@") or old.get("BOT_USERNAME", ""),
        "ADMIN_TELEGRAM_IDS": ",".join(str(i) for i in body.admin_ids),
        "ADMIN_NOTIFY_CHAT_ID": str(body.admin_chat_id or ""),
        "WEBHOOK_URL": f"https://{domain}/webhook/telegram" if webhook else "",
        "WEBHOOK_SECRET": old.get("WEBHOOK_SECRET") or secrets.token_urlsafe(24),
        "FLEET_API_BASE_URL": body.fleet_base_url.strip() or DEFAULT_FLEET_URL,
        "FLEET_CLIENT_ID": body.fleet_client_id.strip(),
        "FLEET_API_KEY": body.fleet_api_key.strip() or old.get("FLEET_API_KEY", ""),
        "FLEET_PARK_ID": body.fleet_park_id.strip(),
        "POSTGRES_PASSWORD": pg_password,
        "DATABASE_URL": f"postgresql+asyncpg://referral:{pg_password}@postgres:5432/referral",
        "REDIS_URL": "redis://redis:6379/0",
        "ADMIN_SECRET_KEY": old.get("ADMIN_SECRET_KEY") or secrets.token_urlsafe(32),
        "ADMIN_BASE_URL": f"https://{domain}/admin" if webhook else "http://localhost:8000/admin",
        "PUBLIC_DOMAIN": domain if webhook else "",
        "SENTRY_DSN": old.get("SENTRY_DSN", ""),
        "LOG_LEVEL": old.get("LOG_LEVEL", "INFO"),
        "TZ_DISPLAY": old.get("TZ_DISPLAY", "Asia/Tashkent"),
        "S3_BACKUP_BUCKET": old.get("S3_BACKUP_BUCKET", ""),
        "BACKUP_DIR": "/backups",
    }


def build_initial_settings(body: SaveIn) -> dict[str, Any]:
    has_fleet = body.fleet_provider == "api" and body.fleet_client_id and body.fleet_park_id
    settings: dict[str, Any] = {
        "fleet_provider": "api" if has_fleet else body.fleet_provider if body.fleet_provider in ("manual", "mock")
        else "manual",
        # без доступа к созданию транзакций автоматический вывод невозможен — только ручные выплаты
        "withdrawal_mode": body.withdrawal_mode if (has_fleet and body.can_payout) else "manual",
    }
    if body.park_contacts.strip():
        settings["park_contacts"] = body.park_contacts.strip()
    if body.fleet_category_id:
        settings["fleet_transaction_category_id"] = body.fleet_category_id
    if body.fleet_categories:
        settings["fleet_transaction_categories"] = body.fleet_categories
    data: dict[str, Any] = {"settings": settings}
    tg_id = body.panel_telegram_id or (body.admin_ids[0] if body.admin_ids else None)
    if body.panel_login and body.panel_password and tg_id:
        data["admin"] = {"telegram_id": tg_id, "login": body.panel_login.strip(), "role": "superadmin",
                         "password_hash": hash_password(body.panel_password), "totp_secret": body.totp_secret or None}
    return data


def validate(body: SaveIn, old: dict[str, str]) -> list[str]:
    errors = []
    if not (body.bot_token.strip() or old.get("BOT_TOKEN")):
        errors.append("Укажите токен бота от @BotFather.")
    if not body.admin_ids:
        errors.append("Укажите хотя бы один Telegram ID администратора.")
    if body.mode == "webhook" and not body.domain.strip():
        errors.append("Для режима «Сервер с доменом» укажите домен.")
    if body.panel_password and len(body.panel_password) < 8:
        errors.append("Пароль веб-панели — не короче 8 символов.")
    if body.panel_login and body.panel_password:
        if not body.totp_secret or not pyotp.TOTP(body.totp_secret).verify(body.totp_code.strip(), valid_window=1):
            errors.append("Подтвердите двухфакторный вход: введите 6 цифр из приложения-аутентификатора.")
    return errors


@app.post("/api/save")
async def save(body: SaveIn) -> dict[str, Any]:
    old = read_env(ENV_PATH)
    errors = validate(body, old)
    if errors:
        return {"ok": False, "errors": errors}
    env = build_env(body, old)
    write_env(ENV_PATH, env)
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    (CONFIG_DIR / "initial_settings.json").write_text(
        json.dumps(build_initial_settings(body), ensure_ascii=False, indent=2), encoding="utf-8")
    if env["BOT_MODE"] == "webhook" and NGINX_TEMPLATE.exists():
        NGINX_OUT.write_text(NGINX_TEMPLATE.read_text(encoding="utf-8").replace("__DOMAIN__", env["PUBLIC_DOMAIN"]),
                             encoding="utf-8")
    asyncio.get_running_loop().call_later(1.5, _shutdown)
    return {"ok": True, "mode": env["BOT_MODE"], "admin_url": env["ADMIN_BASE_URL"],
            "bot_link": f"https://t.me/{env['BOT_USERNAME']}" if env["BOT_USERNAME"] else ""}


def _shutdown() -> None:
    server = app.state.server
    if server is not None:
        server.should_exit = True
