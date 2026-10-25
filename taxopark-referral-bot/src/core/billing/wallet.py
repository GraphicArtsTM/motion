"""Кошелёк: блокировка пользователя, леджер, переходы статусов начислений, долг (A9, E2).

Модель денег (D-02):
* `users.balance_available` == Σ accruals(status='available') — всегда, и == SUM(wallet_ledger.amount).
* Начисление делится (split), когда нужна только его часть: резерв под вывод
  произвольной суммы, погашение долга, частичное списание.
* Часть начисления, ушедшая на погашение долга или списанная корректировкой,
  получает статус `cancelled` с комментарием — так total_earned остаётся «чистым».
"""

from __future__ import annotations

import hashlib
from collections.abc import Sequence

from sqlalchemy import func, select

from src.core.context import Ctx
from src.db.models import Accrual, User, WalletLedger

DEBT_REPAYMENT_COMMENT = "debt_repayment"


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


async def lock_user(ctx: Ctx, user_id: int) -> User:
    """SELECT ... FOR UPDATE по строке пользователя (R4)."""
    user = (await ctx.session.execute(
        select(User).where(User.id == user_id).with_for_update().execution_options(populate_existing=True)
    )).scalar_one()
    return user


async def write_ledger(ctx: Ctx, user: User, type_: str, amount: int, ref_type: str | None = None,
                       ref_id: int | None = None) -> None:
    ctx.session.add(WalletLedger(user_id=user.id, type=type_, amount=amount,
                                 balance_after=user.balance_available, debt_after=user.debt,
                                 ref_type=ref_type, ref_id=ref_id, created_at=ctx.now()))


async def split_accrual(ctx: Ctx, acc: Accrual, part: int, status: str, *, comment: str | None = None,
                        withdrawal_id: int | None = None) -> Accrual:
    """Отделяет от начисления часть `part` с новым статусом. Возвращает новую часть."""
    assert 0 < part < acc.amount, "split part must be strictly inside the accrual amount"
    n = await ctx.session.scalar(select(func.count()).where(Accrual.parent_accrual_id == acc.id)) or 0
    child = Accrual(
        idempotency_key=sha256(f"split:{acc.id}:{n + 1}"), user_id=acc.user_id, type=acc.type,
        referral_id=acc.referral_id, milestone_id=acc.milestone_id, bonus_rule_id=acc.bonus_rule_id,
        period_id=acc.period_id, withdrawal_id=withdrawal_id, amount=part, status=status,
        hold_until=acc.hold_until, comment=comment or acc.comment, created_by=acc.created_by,
        parent_accrual_id=acc.id, created_at=acc.created_at,
    )
    acc.amount -= part
    ctx.session.add(child)
    await ctx.session.flush()
    return child


async def take_from_accrual(ctx: Ctx, acc: Accrual, amount: int, status: str, *, comment: str | None = None,
                            withdrawal_id: int | None = None) -> tuple[Accrual, int]:
    """Переводит `amount` из начисления (целиком или частью) в статус `status`.
    Возвращает (затронутая часть, взятая сумма)."""
    if amount >= acc.amount:
        taken = acc.amount
        acc.status = status
        if comment:
            acc.comment = comment
        if withdrawal_id is not None:
            acc.withdrawal_id = withdrawal_id
        return acc, taken
    part = await split_accrual(ctx, acc, amount, status, comment=comment, withdrawal_id=withdrawal_id)
    return part, amount


async def make_available(ctx: Ctx, user: User, acc: Accrual, ledger_type: str = "accrual") -> int:
    """Начисление становится доступным. Сначала гасит долг (A9 п.2). Возвращает сумму,
    попавшую в balance_available. Пользователь должен быть заблокирован."""
    acc.status = "available"
    acc.released_at = ctx.now() if ledger_type == "hold_release" else acc.released_at
    pay = min(user.debt, acc.amount)
    if pay:
        await take_from_accrual(ctx, acc, pay, "cancelled", comment=DEBT_REPAYMENT_COMMENT)
        user.debt -= pay
    net = acc.amount if acc.status == "available" else 0
    user.balance_available += net
    await write_ledger(ctx, user, ledger_type, net, "accrual", acc.id)
    return net


async def available_accruals_fifo(ctx: Ctx, user_id: int) -> Sequence[Accrual]:
    return (await ctx.session.execute(
        select(Accrual).where(Accrual.user_id == user_id, Accrual.status == "available")
        .order_by(Accrual.created_at, Accrual.id).with_for_update()
    )).scalars().all()


async def consume_available(ctx: Ctx, user: User, amount: int, status: str, *, comment: str | None = None,
                            withdrawal_id: int | None = None) -> int:
    """Снимает `amount` с доступных начислений FIFO (резерв под вывод / списание).
    Баланс пользователя не трогает — это делает вызывающий код."""
    left = amount
    for acc in await available_accruals_fifo(ctx, user.id):
        if left <= 0:
            break
        _, taken = await take_from_accrual(ctx, acc, left, status, comment=comment, withdrawal_id=withdrawal_id)
        left -= taken
    return amount - left


async def settle_debt_from_balance(ctx: Ctx, user: User) -> int:
    """Если одновременно есть долг и доступный баланс — гасим долг из баланса."""
    pay = min(user.debt, user.balance_available)
    if pay <= 0:
        return 0
    taken = await consume_available(ctx, user, pay, "cancelled", comment=DEBT_REPAYMENT_COMMENT)
    user.balance_available -= taken
    user.debt -= taken
    await write_ledger(ctx, user, "debt_repayment", -taken, "user", user.id)
    return taken


async def sums_by_status(ctx: Ctx, user_id: int) -> dict[str, int]:
    rows = (await ctx.session.execute(
        select(Accrual.status, func.coalesce(func.sum(Accrual.amount), 0))
        .where(Accrual.user_id == user_id).group_by(Accrual.status)
    )).all()
    return {status: int(total) for status, total in rows}


async def recalc_user_balances(ctx: Ctx, user_id: int) -> User:
    """Сверяет денормализованные балансы с начислениями.

    balance_hold пересчитывается из начислений. balance_available меняется только
    транзакционно через леджер; расхождение — инцидент, о нём сообщается админам."""
    from src.core.notifications.service import alert_admins

    user = await lock_user(ctx, user_id)
    s = await sums_by_status(ctx, user_id)
    user.balance_hold = s.get("hold", 0)
    if s.get("available", 0) != user.balance_available:
        await alert_admins(ctx, "balance_mismatch", user_id=user_id, expected=s.get("available", 0),
                           actual=user.balance_available)
    return user


async def wallet_totals(ctx: Ctx, user_id: int) -> dict[str, int]:
    """Сводка для экрана кошелька (A9)."""
    from src.db.models import Withdrawal

    s = await sums_by_status(ctx, user_id)
    user = await ctx.session.get(User, user_id)
    assert user is not None
    withdrawn = await ctx.session.scalar(
        select(func.coalesce(func.sum(Withdrawal.amount), 0))
        .where(Withdrawal.user_id == user_id, Withdrawal.status == "completed")
    )
    total_earned = sum(v for k, v in s.items() if k != "cancelled")
    return {
        "available": user.balance_available,
        "hold": s.get("hold", 0),
        "reserved": s.get("reserved", 0),
        "debt": user.debt,
        "total_earned": total_earned,
        "total_withdrawn": int(withdrawn or 0),
    }
