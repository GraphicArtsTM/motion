"""SettingsService: типизированный доступ к таблице `settings` с кешем и инвалидацией."""

from __future__ import annotations

import time
from datetime import date
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.db import seeds
from src.db.models import AuditLog, Setting, SettingsHistory

_cache: dict[str, Any] | None = None
_cache_at: float = 0.0
_ttl: float = float(seeds.SETTINGS_CACHE_TTL_SECONDS)


def configure_cache(ttl_seconds: float) -> None:
    global _ttl
    _ttl = ttl_seconds
    invalidate()


def invalidate() -> None:
    global _cache, _cache_at
    _cache = None
    _cache_at = 0.0


class SettingsService:
    def __init__(self, values: dict[str, Any]) -> None:
        self._values = values

    # ── загрузка ───────────────────────────────────────────────────────────
    @classmethod
    async def load(cls, session: AsyncSession) -> SettingsService:
        global _cache, _cache_at
        if _cache is not None and _ttl > 0 and time.monotonic() - _cache_at < _ttl:
            return cls(dict(_cache))
        rows = (await session.execute(select(Setting.key, Setting.value))).all()
        values = {k: v for k, v in rows}
        _cache, _cache_at = values, time.monotonic()
        return cls(dict(values))

    async def reload(self, session: AsyncSession) -> None:
        invalidate()
        fresh = await SettingsService.load(session)
        self._values = fresh._values

    # ── чтение ────────────────────────────────────────────────────────────
    def get(self, key: str, default: Any = None) -> Any:
        if key not in self._values:
            if default is not None:
                return default
            raise KeyError(f"setting '{key}' is not defined")
        return self._values[key]

    def bool(self, key: str) -> bool:
        return bool(self.get(key))

    def int(self, key: str) -> int:
        value = self.get(key)
        return int(value) if value is not None else 0

    def str(self, key: str) -> str:
        value = self.get(key)
        return "" if value is None else str(value)

    def list(self, key: str) -> list[Any]:
        value = self.get(key)
        return list(value) if value else []

    def json(self, key: str) -> Any:
        return self.get(key)

    def all(self) -> dict[str, Any]:
        return dict(self._values)

    def override(self, **values: Any) -> None:
        """Локальное переопределение (без записи в БД) — для симулятора и тестов."""
        self._values.update(values)

    # ── запись ────────────────────────────────────────────────────────────
    async def set(
        self,
        session: AsyncSession,
        key: str,
        value: Any,
        actor_id: int | None,
        effective_from: date | None = None,
    ) -> None:
        row = await session.get(Setting, key, with_for_update=True)
        if row is None:
            raise KeyError(f"setting '{key}' is not defined")
        old = row.value
        if old == value:
            return
        row.value = value
        row.updated_by = actor_id
        session.add(SettingsHistory(entity="settings", key=key, old_value=old, new_value=value,
                                    effective_from=effective_from, changed_by=actor_id))
        session.add(AuditLog(actor_user_id=actor_id, action="setting_changed", entity_type="setting",
                             old_value={"key": key, "value": old}, new_value={"key": key, "value": value}))
        self._values[key] = value
        invalidate()
