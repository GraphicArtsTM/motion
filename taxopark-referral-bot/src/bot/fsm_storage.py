"""Хранилище состояний диалогов aiogram в PostgreSQL (режим без Redis): незаконченная регистрация
переживает перезапуск бота."""

from __future__ import annotations

from typing import Any

from aiogram.fsm.state import State
from aiogram.fsm.storage.base import BaseStorage, StateType, StorageKey
from sqlalchemy.dialects.postgresql import insert

from src.db.models import FsmState
from src.db.session import get_sessionmaker


def key_of(key: StorageKey) -> str:
    return ":".join(str(x) for x in (key.bot_id, key.chat_id, key.user_id, key.thread_id or "",
                                     key.business_connection_id or "", key.destiny))


class DbStorage(BaseStorage):
    async def _upsert(self, key: StorageKey, **values: Any) -> None:
        async with get_sessionmaker()() as s:
            stmt = insert(FsmState).values(key=key_of(key), **values)
            await s.execute(stmt.on_conflict_do_update(index_elements=["key"],
                                                       set_={**values, "updated_at": stmt.excluded.updated_at}))
            await s.commit()

    async def set_state(self, key: StorageKey, state: StateType = None) -> None:
        value = state.state if isinstance(state, State) else state
        await self._upsert(key, state=value)

    async def get_state(self, key: StorageKey) -> str | None:
        async with get_sessionmaker()() as s:
            row = await s.get(FsmState, key_of(key))
            return row.state if row else None

    async def set_data(self, key: StorageKey, data: dict[str, Any]) -> None:
        await self._upsert(key, data=dict(data))

    async def get_data(self, key: StorageKey) -> dict[str, Any]:
        async with get_sessionmaker()() as s:
            row = await s.get(FsmState, key_of(key))
            return dict(row.data) if row else {}

    async def close(self) -> None:
        return None
