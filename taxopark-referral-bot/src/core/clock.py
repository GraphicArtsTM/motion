"""Время и расчётные периоды.

Хранение — UTC timezone-aware, отображение и границы периодов — Asia/Tashkent (2.12).
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from src.config import get_config


def display_tz() -> ZoneInfo:
    return ZoneInfo(get_config().tz_display)


class Clock:
    """Источник текущего времени. В тестах подменяется на FrozenClock."""

    def now(self) -> datetime:
        return datetime.now(UTC)


class FrozenClock(Clock):
    def __init__(self, at: datetime) -> None:
        if at.tzinfo is None:
            raise ValueError("FrozenClock requires timezone-aware datetime")
        self.at = at.astimezone(UTC)

    def now(self) -> datetime:
        return self.at

    def set(self, at: datetime) -> None:
        self.at = at.astimezone(UTC)

    def advance(self, **kw: float) -> None:
        self.at = self.at + timedelta(**kw)


def to_local(dt: datetime) -> datetime:
    return dt.astimezone(display_tz())


def local_date(dt: datetime) -> date:
    return to_local(dt).date()


def month_code(dt: datetime) -> str:
    """'2026-08' — код периода по Asia/Tashkent."""
    local = to_local(dt)
    return f"{local.year:04d}-{local.month:02d}"


def parse_code(code: str) -> tuple[int, int]:
    year, month = code.split("-")
    return int(year), int(month)


def next_code(code: str) -> str:
    y, m = parse_code(code)
    y, m = (y + 1, 1) if m == 12 else (y, m + 1)
    return f"{y:04d}-{m:02d}"


def prev_code(code: str) -> str:
    y, m = parse_code(code)
    y, m = (y - 1, 12) if m == 1 else (y, m - 1)
    return f"{y:04d}-{m:02d}"


def period_bounds(code: str) -> tuple[datetime, datetime]:
    """[начало, конец) периода в UTC. Конец — исключающая граница (D-03)."""
    tz = display_tz()
    y, m = parse_code(code)
    start = datetime(y, m, 1, tzinfo=tz)
    ny, nm = parse_code(next_code(code))
    end = datetime(ny, nm, 1, tzinfo=tz)
    return start.astimezone(UTC), end.astimezone(UTC)


def days_left_in_period(now: datetime, code: str) -> int:
    """Сколько календарных дней осталось до конца периода, включая сегодняшний."""
    _, end = period_bounds(code)
    end_local = to_local(end).date()
    return max(0, (end_local - local_date(now)).days)


def ceil_div(a: int, b: int) -> int:
    return -(-a // b)
