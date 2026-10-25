"""Корректировки и долг (A9, E2). Clawback: отрицательная корректировка → долг → вывод заблокирован."""

from __future__ import annotations

from src.core.billing.accruals import create_accrual_if_not_exists
from src.core.billing.wallet import consume_available, lock_user, sha256, write_ledger
from src.core.context import Ctx
from src.core.notifications.service import money, notify_user
from src.db.models import Correction


async def create_correction(ctx: Ctx, *, user_id: int, amount: int, reason: str, created_by: int | None,
                            notify: bool = False) -> Correction:
    """amount > 0 — ручное начисление (через accrual type='manual', сначала гасит долг);
    amount < 0 — списание: сначала из balance_available, остаток уходит в долг."""
    if amount == 0:
        raise ValueError("correction amount must be non-zero")
    user = await lock_user(ctx, user_id)
    corr = Correction(user_id=user_id, amount=amount, reason=reason, applied=True, created_by=created_by,
                      created_at=ctx.now())
    ctx.session.add(corr)
    await ctx.session.flush()

    if amount > 0:
        await create_accrual_if_not_exists(
            ctx, user_id=user_id, idempotency_key=sha256(f"corr:{corr.id}"), type="manual", amount=amount,
            status="available", comment=reason, created_by=created_by)
        return corr

    need = -amount
    take = min(user.balance_available, need)
    if take:
        taken = await consume_available(ctx, user, take, "cancelled", comment=f"correction:{corr.id}")
        user.balance_available -= taken
        take = taken
    debt_add = need - take
    user.debt += debt_add
    corr.debt_created = debt_add
    await write_ledger(ctx, user, "correction", -take, "correction", corr.id)
    if debt_add and notify:
        await notify_user(ctx, user_id, "wallet.debt_created", amount=money(user.debt))
    return corr


async def write_off_debt(ctx: Ctx, *, user_id: int, amount: int, reason: str, actor_id: int) -> Correction:
    """Погашение (списание) долга администратором."""
    user = await lock_user(ctx, user_id)
    amount = min(amount, user.debt)
    user.debt -= amount
    corr = Correction(user_id=user_id, amount=amount, reason=f"debt write-off: {reason}", applied=True,
                      debt_created=-amount, created_by=actor_id, created_at=ctx.now())
    ctx.session.add(corr)
    await ctx.session.flush()
    await write_ledger(ctx, user, "debt_writeoff", 0, "correction", corr.id)
    return corr
