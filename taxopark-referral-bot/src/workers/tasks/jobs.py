"""Фоновые задачи (Раздел 11). Каждая — идемпотентна, под блокировкой job_locks, с алертом при падении."""

from __future__ import annotations

import asyncio
import os
import shutil
from collections.abc import Awaitable, Callable
from datetime import timedelta
from pathlib import Path
from typing import Any

import structlog
from sqlalchemy import func, select, text

from src.config import get_config
from src.core.billing.accruals import release_holds as core_release_holds
from src.core.billing.periods import close_due_periods, ensure_current_period
from src.core.billing.reconciliation import reconcile_withdrawals as core_reconcile
from src.core.billing.reconciliation import retry_pending_withdrawals
from src.core.billing.withdrawal import process_withdrawal as core_process
from src.core.billing.withdrawal import verify_withdrawal as core_verify
from src.core.clock import prev_code
from src.core.context import Ctx
from src.core.fraud.engine import run_fraud_check
from src.core.notifications import progress as notif
from src.core.notifications.service import alert_admins, month, notify_user, sent_today
from src.core.onboarding.approval import expire_referrals as core_expire
from src.core.onboarding.approval import pending_approval_reminder as core_pending_reminder
from src.core.onboarding.terms import users_not_accepted
from src.core.referral.matching import match_pending_users
from src.core.sync.online_time import sync_driver_online_time as core_online
from src.core.sync.orders import sync_orders as core_sync_orders
from src.core.sync.park_profiles import sync_park_driver_profiles as core_sync_profiles
from src.core.sync.stats import rebuild_daily_stats as core_rebuild
from src.db import seeds
from src.db.models import Broadcast, Period, Referral, TariffCoefficient, User
from src.db.session import get_sessionmaker
from src.integrations.fleet.errors import FleetError
from src.runtime import open_ctx
from src.workers import locks

log = structlog.get_logger()
Job = Callable[[Ctx], Awaitable[Any]]


async def run_job(name: str, fn: Job, *, lock: bool = True) -> Any:
    async with get_sessionmaker()() as session:
        ctx = await open_ctx(session)
        if lock and not await locks.acquire(name, ctx.now()):
            log.info("job_skipped_locked", job=name)
            return "locked"
        try:
            result = await fn(ctx)
            await session.commit()
            log.info("job_done", job=name, result=str(result)[:200])
            return result
        except Exception as e:
            await session.rollback()
            log.exception("job_failed", job=name)
            await alert_admins(ctx, "job_failed", job=name, error=f"{type(e).__name__}: {str(e)[:200]}")
            await session.commit()
            if not isinstance(e, FleetError):
                raise
            return "fleet_error"
        finally:
            if lock:
                await locks.release(name)


# ── периоды и биллинг ───────────────────────────────────────────────────────
async def ensure_current_period_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("ensure_current_period", lambda c: ensure_current_period(c))


async def open_period_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("open_period", lambda c: ensure_current_period(c))


async def close_period_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("close_period", close_due_periods)


async def release_holds_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("release_holds", core_release_holds)


async def fraud_check_job(_: dict[str, Any], *__: Any) -> Any:
    async def fn(ctx: Ctx) -> Any:
        period = await ensure_current_period(ctx)
        last = (await ctx.session.execute(select(Period).where(Period.code == prev_code(period.code)))).scalar_one_or_none()
        return await run_fraud_check(ctx, last or period, apply_reactions=True)
    return await run_job("fraud_check", fn)


# ── синхронизация ───────────────────────────────────────────────────────────
async def sync_orders_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("sync_orders", core_sync_orders)


async def sync_park_driver_profiles_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("sync_park_driver_profiles", core_sync_profiles)


async def sync_driver_online_time_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("sync_driver_online_time", core_online)


async def match_pending_referrals_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("match_pending_referrals", match_pending_users)


async def rebuild_daily_stats_job(_: dict[str, Any], *__: Any) -> Any:
    async def fn(ctx: Ctx) -> Any:
        period = await ensure_current_period(ctx)
        await core_rebuild(ctx, period.starts_at)
    return await run_job("rebuild_daily_stats", fn)


# ── выводы ──────────────────────────────────────────────────────────────────
async def process_withdrawal(_: dict[str, Any], withdrawal_id: int, attempt: int = 0) -> Any:
    return await run_job(f"withdrawal:{withdrawal_id}", lambda c: core_process(c, withdrawal_id, attempt))


async def verify_withdrawal(_: dict[str, Any], withdrawal_id: int, attempt: int = 0) -> Any:
    return await run_job(f"withdrawal:{withdrawal_id}", lambda c: core_verify(c, withdrawal_id, attempt))


async def reconcile_withdrawals_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("reconcile_withdrawals", core_reconcile)


async def retry_failed_withdrawals_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("retry_failed_withdrawals", retry_pending_withdrawals)


# ── рефералы и уведомления ──────────────────────────────────────────────────
async def expire_referrals_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("expire_referrals", core_expire)


async def progress_notifications_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("progress_notifications", notif.progress_notifications)


async def deadline_reminders_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("deadline_reminders", notif.deadline_reminders)


async def inactive_friend_alert_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("inactive_friend_alert", notif.inactive_friend_alert)


async def pending_approval_reminder_job(_: dict[str, Any], *__: Any) -> Any:
    return await run_job("pending_approval_reminder", core_pending_reminder)


async def unknown_tariff_alert_job(_: dict[str, Any], *__: Any) -> Any:
    async def fn(ctx: Ctx) -> int:
        codes = (await ctx.session.execute(select(TariffCoefficient.code).where(
            TariffCoefficient.needs_setup.is_(True)))).scalars().all()
        if codes:
            await alert_admins(ctx, "unknown_tariffs", codes=", ".join(codes))
        return len(codes)
    return await run_job("unknown_tariff_alert", fn)


async def terms_acceptance_reminder_job(_: dict[str, Any], *__: Any) -> Any:
    async def fn(ctx: Ctx) -> int:
        users = await users_not_accepted(ctx)
        for u in users:
            if not await sent_today(ctx, u.id, "terms_reminder", None):
                await notify_user(ctx, u.id, "terms.updated", kind="terms_reminder")
        if users:
            await alert_admins(ctx, "terms_not_accepted", count=len(users))
        return len(users)
    return await run_job("terms_acceptance_reminder", fn)


async def monthly_digest_job(_: dict[str, Any], *__: Any) -> Any:
    """1-го числа: дайджест всем подтверждённым водителям (итоги прошедшего месяца)."""
    async def fn(ctx: Ctx) -> int:
        period = await ensure_current_period(ctx)
        code = prev_code(period.code)
        users = (await ctx.session.execute(select(User.id).where(
            User.access_status == "approved", User.role == "driver", User.bot_blocked.is_(False)))).scalars().all()
        qualified = dict((await ctx.session.execute(
            select(Referral.referrer_user_id, func.count()).where(
                Referral.is_counted.is_(True), Referral.status == "qualified").group_by(Referral.referrer_user_id))).all())
        for uid in users:
            await notify_user(ctx, uid, "digest.monthly", kind="digest", month=month(code),
                              friends=int(qualified.get(uid, 0)))
        return len(users)
    return await run_job("monthly_digest", fn)


async def leaderboard_update_job(_: dict[str, Any], *__: Any) -> Any:
    from src.core.progress.display import leaderboard
    return await run_job("leaderboard_update", lambda c: leaderboard(c))


async def run_scheduled_broadcasts_job(_: dict[str, Any], *__: Any) -> Any:
    from src.core.admin.broadcasts import refresh_stats, run_scheduled_broadcasts

    async def fn(ctx: Ctx) -> int:
        started = await run_scheduled_broadcasts(ctx)
        for bid in (await ctx.session.execute(select(Broadcast.id).where(Broadcast.status == "sending"))).scalars():
            await refresh_stats(ctx, bid)
        return started
    return await run_job("run_scheduled_broadcasts", fn)


# ── инфраструктура ──────────────────────────────────────────────────────────
async def db_backup_job(_: dict[str, Any], *__: Any) -> Any:
    """pg_dump + S3, retention 30 дней (RPO 24 ч)."""
    async def fn(ctx: Ctx) -> str:
        cfg = get_config()
        target = Path(cfg.backup_dir)
        target.mkdir(parents=True, exist_ok=True)
        name = target / f"referral-{ctx.now():%Y%m%d-%H%M}.dump"
        url = cfg.sync_database_url.replace("+psycopg2", "")
        proc = await asyncio.create_subprocess_exec("pg_dump", "--format=custom", f"--file={name}", url,
                                                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        _, err = await proc.communicate()
        if proc.returncode != 0:
            raise RuntimeError(f"pg_dump failed: {err.decode()[:200]}")
        if cfg.s3_backup_bucket and shutil.which("aws"):
            up = await asyncio.create_subprocess_exec("aws", "s3", "cp", str(name), f"s3://{cfg.s3_backup_bucket}/")
            await up.wait()
        border = ctx.now() - timedelta(days=seeds.BACKUP_RETENTION_DAYS)
        for old in target.glob("referral-*.dump"):
            if old.stat().st_mtime < border.timestamp():
                os.remove(old)
        return str(name)
    return await run_job("db_backup", fn)


async def health_check_job(_: dict[str, Any], *__: Any) -> Any:
    from src.health import collect_health

    async def fn(ctx: Ctx) -> dict[str, Any]:
        health = await collect_health(ctx)
        problems = [k for k, v in health.items() if v is False]
        if problems and not await _recently_alerted(ctx):
            await alert_admins(ctx, "health", problems=", ".join(problems))
        return health
    return await run_job("health_check", fn)


async def _recently_alerted(ctx: Ctx) -> bool:
    row = await ctx.session.scalar(text(
        "SELECT 1 FROM notification_outbox WHERE template_key = 'admin.alert.health' AND created_at > :t LIMIT 1"),
        {"t": ctx.now() - timedelta(hours=1)})
    return row is not None


CRON_JOBS: dict[str, Callable[[dict[str, Any]], Awaitable[Any]]] = {
    "ensure_current_period": ensure_current_period_job,
    "open_period": open_period_job,
    "close_period": close_period_job,
    "sync_orders": sync_orders_job,
    "sync_park_driver_profiles": sync_park_driver_profiles_job,
    "sync_driver_online_time": sync_driver_online_time_job,
    "match_pending_referrals": match_pending_referrals_job,
    "reconcile_withdrawals": reconcile_withdrawals_job,
    "retry_failed_withdrawals": retry_failed_withdrawals_job,
    "expire_referrals": expire_referrals_job,
    "rebuild_daily_stats": rebuild_daily_stats_job,
    "release_holds": release_holds_job,
    "fraud_check": fraud_check_job,
    "progress_notifications": progress_notifications_job,
    "deadline_reminders": deadline_reminders_job,
    "inactive_friend_alert": inactive_friend_alert_job,
    "pending_approval_reminder": pending_approval_reminder_job,
    "unknown_tariff_alert": unknown_tariff_alert_job,
    "terms_acceptance_reminder": terms_acceptance_reminder_job,
    "monthly_digest": monthly_digest_job,
    "leaderboard_update": leaderboard_update_job,
    "db_backup": db_backup_job,
    "health_check": health_check_job,
    "run_scheduled_broadcasts": run_scheduled_broadcasts_job,
}
