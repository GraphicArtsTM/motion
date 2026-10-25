"""Блокировки фоновых задач через job_locks: задача не выполняется параллельно на двух воркерах."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import text

from src.db import seeds
from src.db.session import get_sessionmaker

ACQUIRE_SQL = text("""
INSERT INTO job_locks (job_name, locked_at, locked_until) VALUES (:name, :now, :until)
ON CONFLICT (job_name) DO UPDATE SET locked_at = EXCLUDED.locked_at, locked_until = EXCLUDED.locked_until
WHERE job_locks.locked_until < :now
RETURNING job_name
""")


async def acquire(name: str, now: datetime, ttl_minutes: int = seeds.JOB_LOCK_TTL_MINUTES) -> bool:
    async with get_sessionmaker()() as s:
        row = (await s.execute(ACQUIRE_SQL, {"name": name, "now": now,
                                             "until": now + timedelta(minutes=ttl_minutes)})).first()
        await s.commit()
        return row is not None


async def release(name: str) -> None:
    async with get_sessionmaker()() as s:
        await s.execute(text("DELETE FROM job_locks WHERE job_name = :name"), {"name": name})
        await s.commit()
