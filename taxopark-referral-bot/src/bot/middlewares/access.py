"""access-gate + terms-gate (3.7, N3). Экран обработчика задаётся флагом `screen`."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

from aiogram import BaseMiddleware
from aiogram.dispatcher.flags import get_flag
from aiogram.types import TelegramObject

from src.core.onboarding.access import screen_allowed
from src.core.onboarding.terms import has_accepted_current_terms


class AccessGateMiddleware(BaseMiddleware):
    async def __call__(self, handler: Callable[[TelegramObject, dict[str, Any]], Awaitable[Any]],
                       event: TelegramObject, data: dict[str, Any]) -> Any:
        screen = get_flag(data, "screen")
        user = data.get("user")
        if screen is None or user is None or screen == "admin":
            return await handler(event, data)
        terms_ok = await has_accepted_current_terms(data["ctx"], user.id)
        allowed, redirect = screen_allowed(user.access_status, terms_ok, screen)
        if allowed:
            return await handler(event, data)
        from src.bot.handlers.common import show_screen
        await show_screen(event, data, redirect or "menu")
        return None
