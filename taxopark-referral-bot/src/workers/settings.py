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
from src.workers.tasks.jobs import CRON_JOBS, process_withdrawal, verify_withdrawal

HOURS_IN_DAY = 24
MINUTES_IN_HOUR = 60


def _expand(value: Any, size: int, offset: int = 0) -> Any:
    if isinstance(value, dict) and "every" in value:
        return set(range(offset, size, int(value["every"])))
    return value


def build_cron_jobs() -> list[CronJob]:
    jobs = []
    for name, spec in seeds.JOB_SCHEDULE.items():
        fn = CRON_JOBS[name]
        offset = int(spec.get("offset", 0))
        kwargs: dict[str, Any] = {"name": name, "run_at_startup": name == "ensure_current_period",
                                  "unique": True, "timeout": seeds.JOB_LOCK_TTL_MINUTES * MINUTES_IN_HOUR}
        if "day" in spec:
            kwargs["day"] = spec["day"]
        if "hour" in spec:
            kwargs["hour"] = _expand(spec["hour"], HOURS_IN_DAY)
        kwargs["minute"] = _expand(spec.get("minute", 0), MINUTES_IN_HOUR, offset)
        kwargs["second"] = 0
        jobs.append(cron(fn, **kwargs))
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
