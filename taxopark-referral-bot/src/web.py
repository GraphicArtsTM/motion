"""Веб-приложение: /health, Telegram webhook, admin API, SQLAdmin.

Запуск: uvicorn src.web:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

from aiogram.types import Update
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse

from src.admin.api import business_error_handler
from src.admin.api import router as admin_router
from src.config import get_config
from src.core.errors import BusinessError
from src.db.session import get_sessionmaker
from src.runtime import open_ctx

state: dict[str, Any] = {}


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    from src.core.billing.periods import ensure_current_period
    from src.logging_setup import setup_logging

    setup_logging()
    cfg = get_config()
    async with get_sessionmaker()() as s:
        await ensure_current_period(await open_ctx(s))  # E4: открытый период при старте
    stop = asyncio.Event()
    if cfg.bot_token and cfg.bot_mode == "webhook" and cfg.environment != "test":
        # в режиме polling бот работает отдельным сервисом `bot` (python -m src.bot.main)
        from src.bot.dispatcher import run_dispatcher
        from src.bot.main import build_dispatcher, make_bot
        bot, dp = make_bot(), build_dispatcher()
        state.update(bot=bot, dp=dp)
        if cfg.webhook_url:
            await bot.set_webhook(cfg.webhook_url, secret_token=cfg.webhook_secret or None, max_connections=40,
                                  allowed_updates=dp.resolve_used_update_types())
        state["sender"] = asyncio.create_task(run_dispatcher(bot, stop))
    yield
    stop.set()
    if "sender" in state:
        await state["sender"]
    if "bot" in state:
        await state["bot"].session.close()


app = FastAPI(title="Taxopark Referral Bot", version="1.0.0", lifespan=lifespan)
app.add_exception_handler(BusinessError, business_error_handler)
app.include_router(admin_router)


STATUS_PAGE = """<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Реферальный бот — состояние</title>
<style>body{{font:16px/1.5 system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 16px;background:#f4f5f7;color:#1d2129}}
.c{{background:#fff;border-radius:12px;padding:20px;border:1px solid #e5e7eb;margin-bottom:16px}}
@media (prefers-color-scheme: dark){{body{{background:#111317;color:#e8eaed}}.c{{background:#1b1e24;border-color:#2c3038}}a{{color:#8ab4f8}}}}
li{{margin:6px 0}}</style></head><body><h1>🚕 Реферальный бот</h1>
<div class="c"><h3>Состояние</h3><ul>{checks}</ul></div>
<div class="c"><h3>Ссылки</h3><ul>{bot}<li><a href="/admin">Просмотр данных (SQLAdmin)</a></li>
<li><a href="/docs">Admin API — все действия панели</a></li></ul>
<p>Остановить — <b>stop.bat</b>, журнал — <b>logs.bat</b>, настройки — <b>setup.bat</b>,
резервная копия — <b>backup.bat</b>.</p></div></body></html>"""


@app.get("/", response_class=HTMLResponse)
async def status_page() -> str:
    from src.health import collect_health
    cfg = get_config()
    async with get_sessionmaker()() as s:
        result = await collect_health(await open_ctx(s))
    names = {"db": "База данных", "redis": "Redis (очереди)", "queue": "Очередь задач (в базе)",
             "fleet_api": "Fleet API"}
    checks = "".join(f"<li>{'✅' if ok else '❌'} {names.get(k, k)}</li>" for k, ok in result.items())
    checks += f"<li>{'✅' if cfg.bot_token else '❌'} Токен бота {'задан' if cfg.bot_token else 'не задан — запустите setup.bat'}</li>"
    checks += f"<li>ℹ️ Режим: {'webhook (сервер)' if cfg.bot_mode == 'webhook' else 'polling (этот компьютер)'}</li>"
    bot = (f'<li><a href="https://t.me/{cfg.bot_username}">Открыть бота @{cfg.bot_username}</a></li>'
           if cfg.bot_username else "")
    return STATUS_PAGE.format(checks=checks, bot=bot)


@app.get("/health")
async def health() -> JSONResponse:
    from src.health import collect_health
    async with get_sessionmaker()() as s:
        result = await collect_health(await open_ctx(s))
    return JSONResponse(result, status_code=200 if result.get("db") else 503)


@app.post("/webhook/telegram")
async def telegram_webhook(request: Request,
                           x_telegram_bot_api_secret_token: str | None = Header(default=None)) -> dict[str, bool]:
    cfg = get_config()
    if cfg.webhook_secret and x_telegram_bot_api_secret_token != cfg.webhook_secret:  # 14.2 п.9
        raise HTTPException(403, "bad secret token")
    if "dp" not in state:
        raise HTTPException(503, "bot is not configured")
    update = Update.model_validate(await request.json(), context={"bot": state["bot"]})
    await state["dp"].feed_update(state["bot"], update)
    return {"ok": True}


def _mount_admin_ui() -> None:
    try:
        from starlette.middleware.sessions import SessionMiddleware

        from src.admin.views.sqladmin_views import mount_sqladmin
        from src.db.session import make_engine
        cfg = get_config()
        app.add_middleware(SessionMiddleware, secret_key=cfg.admin_secret_key)
        mount_sqladmin(app, make_engine(), cfg.admin_secret_key)
    except Exception:  # noqa: BLE001 — панель просмотра не обязательна для работы API
        pass


_mount_admin_ui()
