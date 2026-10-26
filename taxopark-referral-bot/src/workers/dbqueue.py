"""Очередь задач и планировщик в PostgreSQL — замена ARQ/Redis для запуска без Docker.

* DbQueue.enqueue кладёт задачу в task_queue (повторная постановка той же задачи не дублирует её —
  частичный уникальный индекс по job_key среди queued/running).
* run_task_loop забирает созревшие задачи (FOR UPDATE SKIP LOCKED) и исполняет их.
* run_scheduler раз в минуту запускает задачи Раздела 11 по расписанию Asia/Tashkent.
Сами задачи те же, что у воркера ARQ (src/workers/tasks/jobs.py), с блокировками job_locks.
"""

from __future__ import annotations

import asyncio
import json
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from typing import Any

import structlog
from sqlalchemy import select, text, update
from sqlalchemy.dialects.postgresql import insert

from src.core.clock import Clock, to_local
from src.db.models import TaskQueueItem
from src.db.session import get_sessionmaker

log = structlog.get_logger()
POLL_SECONDS = 1.0
BATCH = 20


class DbQueue:
    async def enqueue(self, func_name: str, *args: Any, delay_seconds: int = 0) -> None:
        job_key = f"{func_name}:{':'.join(str(a) for a in args)}"
        run_at = datetime.now(UTC) + timedelta(seconds=delay_seconds)
        async with get_sessionmaker()() as s:
            await s.execute(insert(TaskQueueItem).values(func=func_name, args=json.loads(json.dumps(list(args))),
                                                         job_key=job_key, run_at=run_at)
                            .on_conflict_do_nothing(index_elements=["job_key"],
                                                    index_where=text("status IN ('queued', 'running')")))
            await s.commit()


def task_functions() -> dict[str, Callable[..., Awaitable[Any]]]:
    from src.workers.tasks import jobs
    return {"process_withdrawal": jobs.process_withdrawal, "verify_withdrawal": jobs.verify_withdrawal,
            **jobs.CRON_JOBS}


async def recover_running() -> int:
    """После аварийной остановки задачи в статусе running возвращаются в очередь."""
    async with get_sessionmaker()() as s:
        res = await s.execute(update(TaskQueueItem).where(TaskQueueItem.status == "running")
                              .values(status="queued"))
        await s.commit()
        return res.rowcount or 0


async def claim_due(limit: int, now: datetime | None = None) -> list[tuple[int, str, list[Any]]]:
    async with get_sessionmaker()() as s:
        items = (await s.execute(
            select(TaskQueueItem).where(TaskQueueItem.status == "queued",
                                        TaskQueueItem.run_at <= (now or datetime.now(UTC)))
            .order_by(TaskQueueItem.run_at, TaskQueueItem.id).limit(limit).with_for_update(skip_locked=True)
        )).scalars().all()
        for item in items:
            item.status = "running"
            item.attempts += 1
        await s.commit()
        return [(i.id, i.func, list(i.args or [])) for i in items]


async def execute(item_id: int, func: str, args: list[Any]) -> None:
    status, error = "done", None
    try:
        await task_functions()[func]({}, *args)
    except Exception as e:  # noqa: BLE001 — задача уже отправила алерт через run_job
        status, error = "failed", f"{type(e).__name__}: {str(e)[:500]}"
        log.warning("task_failed", func=func, error=error)
    async with get_sessionmaker()() as s:
        await s.execute(update(TaskQueueItem).where(TaskQueueItem.id == item_id).values(
            status=status, last_error=error, finished_at=datetime.now(UTC)))
        await s.commit()


async def run_due_tasks(now: datetime | None = None) -> int:
    """Исполняет все созревшие задачи (параллельно). Возвращает их количество."""
    batch = await claim_due(BATCH, now)
    await asyncio.gather(*(execute(*item) for item in batch))
    return len(batch)


async def cleanup(days: int = 30) -> None:
    async with get_sessionmaker()() as s:
        await s.execute(text("DELETE FROM task_queue WHERE status IN ('done', 'failed') AND finished_at < :t"),
                        {"t": datetime.now(UTC) - timedelta(days=days)})
        await s.commit()


async def run_task_loop(stop: asyncio.Event) -> None:
    """Задачи выполняются параллельно (до BATCH одновременно): долгая синхронизация не задерживает выводы."""
    await recover_running()
    running: set[asyncio.Task[None]] = set()
    while not stop.is_set():
        claimed = []
        try:
            free = BATCH - len(running)
            claimed = await claim_due(free) if free > 0 else []
        except Exception:  # noqa: BLE001
            log.exception("task_loop_failed")
        for item in claimed:
            task = asyncio.create_task(execute(*item))
            running.add(task)
            task.add_done_callback(running.discard)
        if not claimed:
            try:
                await asyncio.wait_for(stop.wait(), timeout=POLL_SECONDS)
            except TimeoutError:
                pass
    if running:
        await asyncio.wait(running, timeout=30)


async def run_scheduler(stop: asyncio.Event, clock: Clock | None = None) -> None:
    """Каждую минуту ставит в очередь задачи, чьё время наступило (по Asia/Tashkent)."""
    from src.workers.schedule import due

    clock = clock or Clock()
    queue = DbQueue()
    await queue.enqueue("ensure_current_period", clock.now().strftime("%Y%m%d%H%M"))  # при старте (E4)
    last_minute = ""
    while not stop.is_set():
        local = to_local(clock.now())
        minute_key = local.strftime("%Y%m%d%H%M")
        if minute_key != last_minute:
            last_minute = minute_key
            for name in due(local):
                await queue.enqueue(name, minute_key)
            if local.hour == 4 and local.minute == 45:
                await cleanup()
        try:
            await asyncio.wait_for(stop.wait(), timeout=max(1.0, 60 - local.second - local.microsecond / 1e6))
        except TimeoutError:
            pass
