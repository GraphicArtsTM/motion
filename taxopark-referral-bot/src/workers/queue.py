"""Очередь задач на ARQ (Redis)."""

from __future__ import annotations

from typing import Any

from arq import create_pool
from arq.connections import ArqRedis, RedisSettings

from src.config import get_config

_pool: ArqRedis | None = None


def redis_settings() -> RedisSettings:
    return RedisSettings.from_dsn(get_config().redis_url)


async def get_pool() -> ArqRedis:
    global _pool
    if _pool is None:
        _pool = await create_pool(redis_settings())
    return _pool


class ArqQueue:
    """TaskQueue поверх ARQ. job_id = имя + аргументы → повторная постановка той же задачи не дублирует её."""

    async def enqueue(self, func_name: str, *args: Any, delay_seconds: int = 0) -> None:
        pool = await get_pool()
        job_id = f"{func_name}:{':'.join(str(a) for a in args)}"
        await pool.enqueue_job(func_name, *args, _job_id=job_id, _defer_by=delay_seconds or None)
