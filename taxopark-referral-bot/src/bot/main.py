"""Сборка бота: роутеры, middleware, хранилище FSM; запуск в режиме polling (разработка)."""

from __future__ import annotations

import asyncio

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.fsm.storage.base import BaseStorage
from aiogram.fsm.storage.memory import MemoryStorage

from src.bot.handlers import admin, menu, onboarding, wallet
from src.bot.middlewares.access import AccessGateMiddleware
from src.bot.middlewares.context import ContextMiddleware
from src.bot.middlewares.throttling import ThrottlingMiddleware
from src.config import get_config


def make_storage() -> BaseStorage:
    cfg = get_config()
    if cfg.environment == "test" or not cfg.redis_url:
        return MemoryStorage()
    from aiogram.fsm.storage.redis import RedisStorage
    return RedisStorage.from_url(cfg.redis_url)


def make_bot(token: str | None = None) -> Bot:
    return Bot(token or get_config().bot_token, default=DefaultBotProperties(parse_mode=ParseMode.HTML))


def build_dispatcher(storage: BaseStorage | None = None) -> Dispatcher:
    dp = Dispatcher(storage=storage or make_storage())
    throttling = ThrottlingMiddleware(enabled=get_config().environment != "test")
    context = ContextMiddleware()
    for observer in (dp.message, dp.callback_query, dp.inline_query):
        observer.outer_middleware(throttling)
    dp.message.outer_middleware(context)
    dp.callback_query.outer_middleware(context)
    gate = AccessGateMiddleware()
    for r in (admin.router, onboarding.router, wallet.router, menu.router):
        r.message.middleware(gate)
        r.callback_query.middleware(gate)
        dp.include_router(r)
    return dp


async def main_polling() -> None:
    from src.bot.dispatcher import run_dispatcher
    from src.core.billing.periods import ensure_current_period
    from src.db.session import get_sessionmaker
    from src.logging_setup import setup_logging
    from src.runtime import open_ctx

    setup_logging()
    async with get_sessionmaker()() as s:
        await ensure_current_period(await open_ctx(s))  # E4
    bot = make_bot()
    dp = build_dispatcher()
    stop = asyncio.Event()
    sender = asyncio.create_task(run_dispatcher(bot, stop))
    try:
        await bot.delete_webhook(drop_pending_updates=False)
        await dp.start_polling(bot)
    finally:
        stop.set()
        await sender


if __name__ == "__main__":
    asyncio.run(main_polling())
