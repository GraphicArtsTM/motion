"""A17 — пересчёт закрытого периода (исправление E3)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import select

from src.core.admin.audit import audit_log
from src.core.billing.accruals import (
    cancel_accrual,
    count_accruals,
    create_accrual_if_not_exists,
    initial_accrual_status,
    sum_accruals,
)
from src.core.billing.bonus_rules import best_bonus_rule
from src.core.billing.debt import create_correction
from src.core.billing.qualification import (
    count_distinct_qualified_referrals_lifetime,
    get_qualification,
    upsert_qualification,
)
from src.core.billing.wallet import recalc_user_balances, sha256
from src.core.context import Ctx
from src.core.notifications.service import alert_admins, money, month, notify_user
from src.core.referral.queries import referrals_with_profiles
from src.core.scoring.points import achieved_percent, points_for_profiles
from src.db.models import Accrual, Period, User


@dataclass
class RecalcChange:
    direction: str  # up | down
    user_id: int
    referral_id: int
    amount: int
    old_points_x100: int
    new_points_x100: int


@dataclass
class RecalcResult:
    changes: list[RecalcChange] = field(default_factory=list)
    preview: bool = False

    def as_dict(self) -> dict[str, Any]:
        return {"preview": self.preview, "changes": [c.__dict__ for c in self.changes],
                "total_up": sum(c.amount for c in self.changes if c.direction == "up"),
                "total_down": sum(c.amount for c in self.changes if c.direction == "down")}


async def cancel_available_accruals(ctx: Ctx, user_id: int, referral_id: int, period_id: int, delta: int,
                                    types: list[str], reason: str) -> int:
    """Списывает переплату с ещё не выведенных начислений (available/hold), новые — первыми."""
    rows = (await ctx.session.execute(
        select(Accrual).where(Accrual.user_id == user_id, Accrual.referral_id == referral_id,
                              Accrual.period_id == period_id, Accrual.type.in_(types),
                              Accrual.status.in_(["available", "hold"]))
        .order_by(Accrual.created_at.desc(), Accrual.id.desc()).with_for_update()
    )).scalars().all()
    left = delta
    for acc in rows:
        if left <= 0:
            break
        left -= await cancel_accrual(ctx, acc, f"recalc: {reason}", min(left, acc.amount))
    return delta - left


async def recalculate_closed_period(ctx: Ctx, period: Period, reason: str, actor_id: int | None = None,
                                    *, preview: bool = False) -> RecalcResult:
    """Пересчёт по снимку периода. `preview=True` — только показать изменения (ничего не сохраняет)."""
    assert period.status == "closed", f"period {period.code} is not closed"
    threshold = period.threshold_points_x100
    result = RecalcResult(preview=preview)
    welcome_on = ctx.settings.bool("referred_bonus_enabled")
    max_p = ctx.settings.int("referred_bonus_max_periods")
    refs = await referrals_with_profiles(ctx)
    points = await points_for_profiles(ctx, period, [pid for _, pid in refs if pid])
    touched_users: set[int] = set()

    for ref, pid in refs:
        res = points.get(pid) if pid else None
        cnt, pts = (res.eligible_orders_count, res.points_x100) if res else (0, 0)
        old = await get_qualification(ctx, ref.id, period.id)
        old_pts = old.points_x100 if old else 0
        percent = achieved_percent(pts, threshold)
        if not preview:
            await upsert_qualification(ctx, referral_id=ref.id, period_id=period.id, eligible_orders_count=cnt,
                                       points_x100=pts, threshold_points_x100=threshold, achieved_percent=percent,
                                       is_qualified=pts >= threshold, breakdown=res.breakdown_json() if res else [])
            if pts >= threshold:
                ref.status = "qualified"
                ref.first_qualified_at = ref.first_qualified_at or ctx.now()
            elif pts > 0 and ref.status == "hired":
                ref.status = "active"

        for recipient, user_id, acc_type in (
            ("referrer", ref.referrer_user_id, "referral"),
            ("referred", ref.referred_user_id, "referred_welcome"),
        ):
            if acc_type == "referred_welcome" and not welcome_on:
                continue
            new_rule = await best_bonus_rule(ctx, percent, recipient) if pts >= threshold else None
            new_amount = new_rule.bonus_uzs if new_rule else 0
            paid = await sum_accruals(ctx, user_id=user_id, referral_id=ref.id, period_id=period.id,
                                      types=[acc_type, "adjustment"], exclude_status="cancelled")
            if acc_type == "referred_welcome" and new_amount > paid and paid == 0 and max_p:
                # лимит welcome-бонуса за первые N планов действует и при пересчёте (D-13)
                if await count_accruals(ctx, user_id=user_id, type="referred_welcome") >= max_p:
                    continue

            if new_amount > paid:  # ДОНАЧИСЛЕНИЕ
                delta = new_amount - paid
                result.changes.append(RecalcChange("up", user_id, ref.id, delta, old_pts, pts))
                if preview:
                    continue
                acc = await create_accrual_if_not_exists(
                    ctx, idempotency_key=sha256(f"adj:{user_id}:{ref.id}:{period.code}:{new_amount}"),
                    user_id=user_id, type="adjustment", referral_id=ref.id, period_id=period.id,
                    amount=delta, status=await initial_accrual_status(ctx, ref.id),
                    comment=f"Доначисление: {reason}")
                if acc:
                    await notify_user(ctx, user_id, "wallet.adjustment_up", month=month(period.code),
                                      amount=money(delta))
                touched_users.add(user_id)

            elif new_amount < paid:  # ПЕРЕПЛАТА
                delta = paid - new_amount
                result.changes.append(RecalcChange("down", user_id, ref.id, delta, old_pts, pts))
                if preview:
                    continue
                cancelled = await cancel_available_accruals(ctx, user_id, ref.id, period.id, delta,
                                                            [acc_type, "adjustment"], reason)
                if cancelled < delta:  # часть уже выведена → долг
                    await create_correction(ctx, user_id=user_id, amount=-(delta - cancelled),
                                            reason=f"Перерасчёт периода {period.code}: {reason}",
                                            created_by=actor_id, notify=False)
                await alert_admins(ctx, "period_recalc_overpaid", user_id=user_id, delta=money(delta),
                                   period=period.code)
                touched_users.add(user_id)

        if not preview:
            touched_users.update({ref.referrer_user_id, ref.referred_user_id})

    if preview:
        return result  # в режиме предпросмотра ничего не записывалось

    for uid in touched_users:
        await recalc_user_balances(ctx, uid)
        user = await ctx.session.get(User, uid)
        if user is not None:
            user.qualified_referrals_count = await count_distinct_qualified_referrals_lifetime(ctx, uid)
    period.recalculated_at = ctx.now()
    await audit_log(ctx, actor_id, "period_recalculated", "period", period.id,
                    new_value={"reason": reason, "changes": len(result.changes)})
    await ctx.session.commit()
    return result
