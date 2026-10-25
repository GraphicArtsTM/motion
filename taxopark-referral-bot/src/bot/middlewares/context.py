"""Сессия БД + контекст ядра + пользователь + переводчик для каждого апдейта; обработка ошибок."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

import structlog
from aiogram import BaseMiddleware
from aiogram.types import CallbackQuery, Message, TelegramObject

from src.bot.i18n import LANGS
from src.bot.render import translator_for
from src.config import get_config
from src.core.errors import BusinessError
from src.core.referral.codes import get_or_create_user
from src.db.session import get_sessionmaker
from src.runtime import open_ctx

log = structlog.get_logger()


def guess_language(code: str | None) -> str:
    if code and code.startswith("ru"):
        return "ru"
    return "uz_latn"


async def reply_text(event: TelegramObject, text: str) -> None:
    if isinstance(event, CallbackQuery):
        await event.answer(text[:200], show_alert=True)
    elif isinstance(event, Message):
        await event.answer(text)


class ContextMiddleware(BaseMiddleware):
    async def __call__(self, handler: Callable[[TelegramObject, dict[str, Any]], Awaitable[Any]],
                       event: TelegramObject, data: dict[str, Any]) -> Any:
        tg_user = data.get("event_from_user")
        async with get_sessionmaker()() as session:
            ctx = await open_ctx(session)
            data["ctx"] = ctx
            lang = "uz_latn"
            if tg_user is not None and not tg_user.is_bot:
                user, _created = await get_or_create_user(ctx, tg_user.id, username=tg_user.username,
                                                          language=guess_language(tg_user.language_code))
                user.bot_blocked = False
                if tg_user.id in get_config().admin_telegram_ids and user.role == "driver":
                    user.role = "superadmin"
                await session.commit()
                lang = user.language if user.language in LANGS else "uz_latn"
                data["user"] = user
            data["lang"] = lang
            data["t"] = translator_for(lang)
            try:
                result = await handler(event, data)
                await session.commit()
                return result
            except BusinessError as e:
                await session.rollback()
                await reply_text(event, data["t"](e.key, **e.params))
            except Exception:
                await session.rollback()
                log.exception("handler_failed", event_type=type(event).__name__)
                await reply_text(event, data["t"]("err.unexpected"))
        return None
