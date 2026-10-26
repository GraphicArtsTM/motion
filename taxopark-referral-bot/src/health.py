"""Проверка здоровья: БД, Redis, Fleet API (circuit breaker), бот."""

from __future__ import annotations

from typing import Any

from sqlalchemy import text

from src.config import get_config
from src.core.context import Ctx


async def collect_health(ctx: Ctx) -> dict[str, Any]:
    out: dict[str, Any] = {}
    try:
        await ctx.session.execute(text("SELECT 1"))
        out["db"] = True
    except Exception:  # noqa: BLE001
        out["db"] = False
    if get_config().queue_backend == "db":
        out["queue"] = out["db"]  # очередь в PostgreSQL (запуск без Docker)
        breaker = getattr(ctx.fleet, "breaker", None)
        out["fleet_api"] = not breaker.is_open if breaker is not None else True
        return out
    try:
        from redis.asyncio import from_url
        r = from_url(get_config().redis_url)
        out["redis"] = bool(await r.ping())
        await r.aclose()
    except Exception:  # noqa: BLE001
        out["redis"] = False
    breaker = getattr(ctx.fleet, "breaker", None)
    out["fleet_api"] = not breaker.is_open if breaker is not None else True
    return out
