"""Контекст выполнения бизнес-операций: сессия БД, настройки, часы, Fleet, очередь задач."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import TYPE_CHECKING, Any, Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from src.core.clock import Clock
from src.core.settings.service import SettingsService

if TYPE_CHECKING:
    from src.integrations.fleet.base import FleetProvider


class TaskQueue(Protocol):
    async def enqueue(self, func_name: str, *args: Any, delay_seconds: int = 0) -> None: ...


class NullQueue:
    async def enqueue(self, func_name: str, *args: Any, delay_seconds: int = 0) -> None:
        return None


class RecordingQueue:
    """Очередь, которая только записывает вызовы (тесты, синхронный режим)."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple[Any, ...], int]] = []

    async def enqueue(self, func_name: str, *args: Any, delay_seconds: int = 0) -> None:
        self.calls.append((func_name, args, delay_seconds))

    def pop_all(self) -> list[tuple[str, tuple[Any, ...], int]]:
        calls, self.calls = self.calls, []
        return calls


@dataclass
class Ctx:
    session: AsyncSession
    settings: SettingsService
    clock: Clock = field(default_factory=Clock)
    fleet: FleetProvider | None = None
    queue: TaskQueue = field(default_factory=NullQueue)

    def now(self) -> datetime:
        return self.clock.now()


async def make_ctx(
    session: AsyncSession,
    *,
    clock: Clock | None = None,
    fleet: FleetProvider | None = None,
    queue: TaskQueue | None = None,
) -> Ctx:
    settings = await SettingsService.load(session)
    return Ctx(session=session, settings=settings, clock=clock or Clock(), fleet=fleet,
               queue=queue or NullQueue())
