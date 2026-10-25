"""Фоновая сверка выводов: reconcile_withdrawals (verifying) и retry_failed_withdrawals (pending)."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from src.core.context import Ctx
from src.core.notifications.service import alert_admins, money
from src.db.models import Withdrawal


async def reconcile_withdrawals(ctx: Ctx) -> int:
    """Каждые 10 минут: сверка выводов в verifying; алерт, если висит дольше порога."""
    from src.core.billing.withdrawal import verify_withdrawal

    alert_after = timedelta(minutes=ctx.settings.int("withdrawal_verifying_alert_minutes"))
    rows = (await ctx.session.execute(
        select(Withdrawal).where(Withdrawal.status == "verifying").order_by(Withdrawal.id))).scalars().all()
    handled = 0
    for w in rows:
        stuck = ctx.now() - w.requested_at > alert_after
        result = await verify_withdrawal(ctx, w.id, max(w.attempts - 1, 0))
        handled += 1
        if result == "verifying" and stuck:
            await alert_admins(ctx, "withdrawal_verifying_stuck", withdrawal_id=w.id, amount=money(w.amount))
            await ctx.session.commit()
    return handled


async def retry_pending_withdrawals(ctx: Ctx) -> int:
    """Каждые 30 минут: повторная постановка зависших выводов (задача потеряна, воркер упал).

    pending    → снова в очередь исполнения (тот же idempotency_token);
    processing → исход вызова неизвестен, поэтому сначала сверка, а не повтор."""
    stale_after = timedelta(minutes=ctx.settings.int("withdrawal_verifying_alert_minutes"))
    delays = [int(x) for x in ctx.settings.list("withdrawal_retry_delays_seconds")]
    rows = (await ctx.session.execute(
        select(Withdrawal).where(Withdrawal.status.in_(["pending", "processing"]),
                                 Withdrawal.requested_at < ctx.now() - stale_after)
        .order_by(Withdrawal.id).with_for_update(skip_locked=True))).scalars().all()
    for w in rows:
        if w.status == "processing":
            w.status = "verifying"
            await ctx.session.commit()
            await ctx.queue.enqueue("verify_withdrawal", w.id, max(w.attempts - 1, 0))
        elif w.attempts <= len(delays):
            await ctx.queue.enqueue("process_withdrawal", w.id, w.attempts)
    await ctx.session.commit()
    return len(rows)
