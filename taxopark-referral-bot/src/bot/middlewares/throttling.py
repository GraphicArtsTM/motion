"""Rate limiting хендлеров бота (14.2 п.7)."""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable
from typing import Any

from aiogram import BaseMiddleware
from aiogram.types import CallbackQuery, TelegramObject

MIN_INTERVAL = 0.25  # сек на апдейт в окне
BURST = 8  # не более BURST апдейтов за MIN_INTERVAL × BURST сек


class ThrottlingMiddleware(BaseMiddleware):
    def __init__(self, enabled: bool = True) -> None:
        self._hits: dict[int, list[float]] = {}
        self.enabled = enabled

    async def __call__(self, handler: Callable[[TelegramObject, dict[str, Any]], Awaitable[Any]],
                       event: TelegramObject, data: dict[str, Any]) -> Any:
        user = data.get("event_from_user")
        if user is None or not self.enabled:
            return await handler(event, data)
        now = time.monotonic()
        hits = [h for h in self._hits.get(user.id, []) if now - h < MIN_INTERVAL * BURST]
        hits.append(now)
        self._hits[user.id] = hits
        if len(hits) > BURST:
            if isinstance(event, CallbackQuery):
                await event.answer()
            return None
        if len(self._hits) > 100_000:
            self._hits.clear()
        return await handler(event, data)
