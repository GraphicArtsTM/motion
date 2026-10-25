"""Фоновые задачи: блокировки job_locks, алерт при падении, расписание."""

from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import select

from src.core.context import RecordingQueue
from src.db.models import NotificationOutbox
from src.runtime import set_clock, set_fleet, set_queue
from src.workers import locks
from src.workers.tasks import jobs


@pytest.fixture(autouse=True)
def runtime(sessionmaker, fleet, clock):
    set_fleet(fleet)
    set_clock(clock)
    set_queue(RecordingQueue())
    yield
    set_fleet(None)
    set_clock(None)


async def test_lock_prevents_parallel_run(clock):
    assert await locks.acquire("x", clock.now())
    assert not await locks.acquire("x", clock.now())
    assert await jobs.run_job("x", lambda c: None) == "locked"
    await locks.release("x")
    assert await locks.acquire("x", clock.now() + timedelta(hours=1))


async def test_failed_job_alerts(sessionmaker):
    async def boom(ctx):
        raise RuntimeError("kaput")
    with pytest.raises(RuntimeError):
        await jobs.run_job("boom", boom)
    async with sessionmaker() as s:
        keys = (await s.execute(select(NotificationOutbox.template_key))).scalars().all()
    assert "admin.alert.job_failed" in keys
    assert await locks.acquire("boom", __import__("datetime").datetime.now(__import__("datetime").UTC))


@pytest.mark.parametrize("name", sorted(set(jobs.CRON_JOBS) - {"db_backup"}))
async def test_every_cron_job_runs(name, sessionmaker, clock):
    result = await jobs.CRON_JOBS[name]({})
    assert result != "locked"


def test_schedule_matches_section_11():
    from src.workers.settings import build_cron_jobs
    cron = {j.name: j for j in build_cron_jobs()}
    assert cron["close_period"].day == 1 and cron["close_period"].hour == 2
    assert cron["sync_orders"].minute == {0, 30}
    assert cron["reconcile_withdrawals"].minute == set(range(0, 60, 5 * 2))
    assert set(cron) == set(jobs.CRON_JOBS)
