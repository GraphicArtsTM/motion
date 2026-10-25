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
from fastapi.responses import JSONResponse

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
    if cfg.bot_token and cfg.environment != "test":
        from src.bot.dispatcher import run_dispatcher
        from src.bot.main import build_dispatcher, make_bot
        bot, dp = make_bot(), build_dispatcher()
        state.update(bot=bot, dp=dp)
        if cfg.webhook_url:
            await bot.set_webhook(cfg.webhook_url, secret_token=cfg.webhook_secret or None,
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
