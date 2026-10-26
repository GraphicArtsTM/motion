"""Расписание задач Раздела 11 (JOB_SCHEDULE из сидов): разворачивание в множества и сопоставление со временем.

Используется и воркером ARQ (Docker), и встроенным планировщиком локального режима (без Docker)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from src.db import seeds

HOURS_IN_DAY = 24
MINUTES_IN_HOUR = 60


def expand(value: Any, size: int, offset: int = 0) -> set[int] | None:
    """5 → {5}; {"every": 30} → {0, 30}; отсутствует → None (любое значение)."""
    if value is None:
        return None
    if isinstance(value, dict) and "every" in value:
        return set(range(offset, size, int(value["every"])))
    if isinstance(value, list | set | tuple):
        return {int(v) for v in value}
    return {int(value)}


@dataclass(frozen=True)
class Slot:
    name: str
    days: set[int] | None
    hours: set[int] | None
    minutes: set[int]

    def matches(self, local: datetime) -> bool:
        return ((self.days is None or local.day in self.days)
                and (self.hours is None or local.hour in self.hours)
                and local.minute in self.minutes)


def slots() -> list[Slot]:
    out = []
    for name, spec in seeds.JOB_SCHEDULE.items():
        offset = int(spec.get("offset", 0))
        out.append(Slot(name=name, days=expand(spec.get("day"), 32),
                        hours=expand(spec.get("hour"), HOURS_IN_DAY),
                        minutes=expand(spec.get("minute", 0), MINUTES_IN_HOUR, offset) or {0}))
    return out


def due(local: datetime) -> list[str]:
    return [s.name for s in slots() if s.matches(local)]
