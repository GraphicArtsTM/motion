"""ARQ WorkerSettings: функции очереди и расписание Раздела 11 (Asia/Tashkent).

Запуск: arq src.workers.settings.WorkerSettings
"""

from __future__ import annotations

from typing import Any
from zoneinfo import ZoneInfo

from arq import cron
from arq.cron import CronJob

from src.config import get_config
from src.db import seeds
from src.workers.queue import redis_settings
from src.workers.schedule import slots
from src.workers.tasks.jobs import CRON_JOBS, process_withdrawal, verify_withdrawal

MINUTES_IN_HOUR = 60


def build_cron_jobs() -> list[CronJob]:
    jobs = []
    for slot in slots():
        kwargs: dict[str, Any] = {"name": slot.name, "run_at_startup": slot.name == "ensure_current_period",
                                  "unique": True, "timeout": seeds.JOB_LOCK_TTL_MINUTES * MINUTES_IN_HOUR,
                                  "minute": slot.minutes, "second": 0}
        if slot.days is not None:
            kwargs["day"] = slot.days if len(slot.days) > 1 else next(iter(slot.days))
        if slot.hours is not None:
            kwargs["hour"] = slot.hours if len(slot.hours) > 1 else next(iter(slot.hours))
        jobs.append(cron(CRON_JOBS[slot.name], **kwargs))
    return jobs


async def on_startup(_: dict[str, Any]) -> None:
    from src.logging_setup import setup_logging
    setup_logging()


class WorkerSettings:
    functions = [process_withdrawal, verify_withdrawal]
    cron_jobs = build_cron_jobs()
    redis_settings = redis_settings()
    timezone = ZoneInfo(get_config().tz_display)
    on_startup = on_startup
    max_jobs = 20
    job_timeout = seeds.JOB_LOCK_TTL_MINUTES * MINUTES_IN_HOUR
    keep_result = 3600
