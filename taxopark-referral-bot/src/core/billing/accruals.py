"""Начисления: создание с идемпотентностью (R5), статус (A8), холды, аннулирование."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

from sqlalchemy import exists, func, select

from src.core.billing.wallet import lock_user, make_available, sha256, take_from_accrual, write_ledger
from src.core.context import Ctx
from src.db.models import Accrual, FraudFlag

__all__ = ["sha256", "initial_accrual_status", "create_accrual_if_not_exists", "create_accrual",
           "release_holds", "cancel_accrual", "has_open_fraud_flag", "sum_accruals", "count_accruals"]


async def has_open_fraud_flag(ctx: Ctx, referral_id: int) -> bool:
    return bool(await ctx.session.scalar(select(exists().where(
        FraudFlag.referral_id == referral_id, FraudFlag.resolved.is_(False)))))


async def initial_accrual_status(ctx: Ctx, referral_id: int | None = None) -> str:
    """A8."""
    if ctx.settings.int("accrual_hold_days") > 0:
        return "hold"
    if referral_id and await has_open_fraud_flag(ctx, referral_id):
        return "hold"
    return "available"


async def create_accrual_if_not_exists(
    ctx: Ctx,
    *,
    user_id: int,
    idempotency_key: str,
    type: str,
    amount: int,
    status: str,
    referral_id: int | None = None,
    milestone_id: int | None = None,
    bonus_rule_id: int | None = None,
    period_id: int | None = None,
    comment: str | None = None,
    created_by: int | None = None,
) -> Accrual | None:
    """Создаёт начисление, если ключа ещё нет. Деньги — в той же транзакции под FOR UPDATE (R4)."""
    if amount <= 0:
        return None
    user = await lock_user(ctx, user_id)
    if await ctx.session.scalar(select(exists().where(Accrual.idempotency_key == idempotency_key))):
        return None
    acc = Accrual(idempotency_key=idempotency_key, user_id=user_id, type=type, amount=amount,
                  status="hold" if status == "hold" else "available", referral_id=referral_id,
                  milestone_id=milestone_id, bonus_rule_id=bonus_rule_id, period_id=period_id,
                  comment=comment, created_by=created_by, created_at=ctx.now())
    ctx.session.add(acc)
    await ctx.session.flush()
    if acc.status == "hold":
        hold_days = ctx.settings.int("accrual_hold_days")
        acc.hold_until = ctx.now() + timedelta(days=hold_days) if hold_days > 0 else None
        user.balance_hold += amount
    else:
        await make_available(ctx, user, acc)
    return acc


async def create_accrual(ctx: Ctx, **kw: Any) -> Accrual | None:
    return await create_accrual_if_not_exists(ctx, **kw)


async def release_accrual(ctx: Ctx, acc: Accrual) -> int:
    user = await lock_user(ctx, acc.user_id)
    if acc.status != "hold":
        return 0
    user.balance_hold -= acc.amount
    return await make_available(ctx, user, acc, ledger_type="hold_release")


async def release_holds(ctx: Ctx) -> int:
    """Снятие холдов по сроку (ежедневно 04:00). Начисления с открытым фрод-флагом остаются."""
    now = ctx.now()
    rows = (await ctx.session.execute(
        select(Accrual).where(Accrual.status == "hold", Accrual.hold_until.is_not(None),
                              Accrual.hold_until <= now).order_by(Accrual.id)
    )).scalars().all()
    released = 0
    for acc in rows:
        if acc.referral_id and await has_open_fraud_flag(ctx, acc.referral_id):
            continue
        released += await release_accrual(ctx, acc)
    await ctx.session.commit()
    return released


async def cancel_accrual(ctx: Ctx, acc: Accrual, comment: str, amount: int | None = None) -> int:
    """Аннулирует начисление (или его часть) в статусах available/hold. Возвращает сумму."""
    if acc.status not in ("available", "hold"):
        return 0
    user = await lock_user(ctx, acc.user_id)
    was = acc.status
    part, taken = await take_from_accrual(ctx, acc, amount or acc.amount, "cancelled", comment=comment)
    if was == "available":
        user.balance_available -= taken
        await write_ledger(ctx, user, "accrual_cancelled", -taken, "accrual", part.id)
    else:
        user.balance_hold -= taken
    return taken


async def sum_accruals(ctx: Ctx, *, user_id: int, referral_id: int | None = None, period_id: int | None = None,
                       types: list[str] | None = None, exclude_status: str | None = None) -> int:
    q = select(func.coalesce(func.sum(Accrual.amount), 0)).where(Accrual.user_id == user_id)
    if referral_id is not None:
        q = q.where(Accrual.referral_id == referral_id)
    if period_id is not None:
        q = q.where(Accrual.period_id == period_id)
    if types:
        q = q.where(Accrual.type.in_(types))
    if exclude_status:
        # долг, погашенный начислением, — это деньги, которые водитель получил (D-02)
        q = q.where((Accrual.status != exclude_status) | (Accrual.comment == "debt_repayment"))
    return int(await ctx.session.scalar(q) or 0)


async def count_accruals(ctx: Ctx, *, user_id: int, type: str) -> int:
    """Количество периодов с начислением данного типа (дробления не считаются)."""
    return int(await ctx.session.scalar(
        select(func.count(func.distinct(Accrual.period_id))).where(
            Accrual.user_id == user_id, Accrual.type == type, Accrual.parent_accrual_id.is_(None),
            (Accrual.status != "cancelled") | (Accrual.comment == "debt_repayment"))
    ) or 0)
