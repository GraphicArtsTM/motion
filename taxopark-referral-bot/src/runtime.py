"""Сборка контекста для бота, админки и воркеров."""

from __future__ import annotations

from typing import Any

import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from src.core.clock import Clock
from src.core.context import Ctx, TaskQueue
from src.core.settings.service import SettingsService
from src.db.models import ApiSyncLog
from src.db.session import get_sessionmaker
from src.integrations.fleet.base import FleetProvider
from src.integrations.fleet.factory import build_provider

log = structlog.get_logger()
_queue: TaskQueue | None = None
_fleet_override: FleetProvider | None = None
_clock: Clock = Clock()


async def api_log_sink(record: dict[str, Any]) -> None:
    """api_sync_log пишется в отдельной сессии, чтобы откат бизнес-транзакции не терял журнал."""
    try:
        async with get_sessionmaker()() as s:
            s.add(ApiSyncLog(**record))
            await s.commit()
    except Exception as e:  # noqa: BLE001
        log.warning("api_sync_log_failed", error=str(e))


def set_queue(queue: TaskQueue) -> None:
    global _queue
    _queue = queue


def get_queue() -> TaskQueue:
    global _queue
    if _queue is None:
        from src.workers.queue import ArqQueue
        _queue = ArqQueue()
    return _queue


def set_fleet(provider: FleetProvider | None) -> None:
    global _fleet_override
    _fleet_override = provider


def set_clock(clock: Clock | None) -> None:
    """Подмена часов (тесты)."""
    global _clock
    _clock = clock or Clock()


def fleet_for(settings: SettingsService) -> FleetProvider:
    if _fleet_override is not None:
        return _fleet_override
    return build_provider(settings.str("fleet_provider"), api_log_sink)


async def open_ctx(session: AsyncSession) -> Ctx:
    settings = await SettingsService.load(session)
    return Ctx(session=session, settings=settings, clock=_clock, fleet=fleet_for(settings), queue=get_queue())
