"""A15 — симулятор изменения правил. Пересчёт периода по черновым правилам; ничего не сохраняет."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from sqlalchemy import select

from src.core.billing.bonus_rules import best_rule, rules_as_dicts
from src.core.billing.periods import get_period
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.referral.queries import referrals_with_profiles
from src.core.scoring.points import achieved_percent, points_for_profiles
from src.core.scoring.snapshot import period_coefficients
from src.db.models import Accrual, Milestone, Qualification, UserMilestone


@dataclass
class SimulationResult:
    qualified: int = 0
    referrer_payout: int = 0
    welcome_payout: int = 0
    milestone_payout: int = 0

    @property
    def total(self) -> int:
        return self.referrer_payout + self.welcome_payout + self.milestone_payout

    def as_dict(self) -> dict[str, int]:
        return {**asdict(self), "total": self.total}


async def current_draft(ctx: Ctx, period_code: str) -> dict[str, Any]:
    """Действующие правила в формате черновика — база для «Сейчас»."""
    period = await get_period(ctx, period_code)
    if period is None:
        raise BusinessError("err.not_found", entity="period", id=period_code)
    milestones = (await ctx.session.execute(select(Milestone))).scalars().all()
    return {
        "coefficients": await period_coefficients(ctx, period.id),
        "default_coefficient_x100": period.default_coefficient_x100,
        "threshold_points_x100": period.threshold_points_x100,
        "bonus_rules": await rules_as_dicts(ctx),
        "referred_bonus_enabled": ctx.settings.bool("referred_bonus_enabled"),
        "referred_bonus_max_periods": ctx.settings.int("referred_bonus_max_periods"),
        "milestones_enabled": ctx.settings.bool("milestones_enabled"),
        "milestones_activation_mode": ctx.settings.str("milestones_activation_mode"),
        "milestones": [{"id": m.id, "code": m.code, "required_count": m.required_count, "reward_uzs": m.reward_uzs,
                        "is_active": m.is_active} for m in milestones],
    }


async def simulate(ctx: Ctx, period_code: str, draft: dict[str, Any]) -> SimulationResult:
    period = await get_period(ctx, period_code)
    if period is None:
        raise BusinessError("err.not_found", entity="period", id=period_code)
    base = await current_draft(ctx, period_code)
    draft = {**base, **draft}
    threshold = int(draft["threshold_points_x100"])
    r = SimulationResult()
    refs = await referrals_with_profiles(ctx)
    pts = await points_for_profiles(ctx, period, [pid for _, pid in refs if pid], coefficients=draft["coefficients"],
                                    default_coefficient_x100=int(draft["default_coefficient_x100"]))
    qualified_now: dict[int, set[int]] = {}
    for ref, pid in refs:
        if not pid:
            continue
        p = pts[pid].points_x100
        percent = achieved_percent(p, threshold)
        if p < threshold:
            continue
        r.qualified += 1
        qualified_now.setdefault(ref.referrer_user_id, set()).add(ref.id)
        rule = best_rule(draft["bonus_rules"], percent, "referrer")
        r.referrer_payout += rule["bonus_uzs"] if rule else 0
        if draft.get("referred_bonus_enabled"):
            max_p = int(draft.get("referred_bonus_max_periods", 1))
            paid_before = await _welcome_periods_before(ctx, ref.referred_user_id, period.id)
            if max_p == 0 or paid_before < max_p:
                wrule = best_rule(draft["bonus_rules"], percent, "referred")
                r.welcome_payout += wrule["bonus_uzs"] if wrule else 0
    if draft.get("milestones_enabled"):
        r.milestone_payout = await simulate_milestones(ctx, draft["milestones"], draft["milestones_activation_mode"],
                                                       qualified_now, period.id)
    return r


async def _welcome_periods_before(ctx: Ctx, user_id: int, period_id: int) -> int:
    rows = (await ctx.session.execute(select(Accrual.period_id).where(
        Accrual.user_id == user_id, Accrual.type == "referred_welcome", Accrual.period_id != period_id,
        Accrual.status != "cancelled").distinct())).scalars().all()
    return len(rows)


async def simulate_milestones(ctx: Ctx, milestones: list[dict[str, Any]], mode: str,
                              qualified_now: dict[int, set[int]], period_id: int) -> int:
    active = sorted((m for m in milestones if m.get("is_active", True)), key=lambda m: m["required_count"])
    total = 0
    for referrer_id, now_ids in qualified_now.items():
        before = set((await ctx.session.execute(
            select(Qualification.referral_id).where(Qualification.is_qualified.is_(True), Qualification.period_id != period_id,
                   Qualification.referral_id.in_(select_referral_ids(referrer_id))))).scalars().all())
        n_before, n_after = len(before), len(before | now_ids)
        granted = set((await ctx.session.execute(select(UserMilestone.milestone_id).where(
            UserMilestone.user_id == referrer_id))).scalars().all())
        for m in active:
            if m.get("id") in granted or m["required_count"] > n_after:
                continue
            if mode == "from_now" and m["required_count"] <= n_before:
                continue  # при включении «только новые» такие ступени закрываются без выплаты
            total += int(m["reward_uzs"])
    return total


def select_referral_ids(referrer_id: int) -> Any:
    from src.db.models import Referral
    return select(Referral.id).where(Referral.referrer_user_id == referrer_id, Referral.is_counted.is_(True),
                                     Referral.is_fraud.is_(False))


async def compare(ctx: Ctx, period_code: str, draft: dict[str, Any]) -> dict[str, Any]:
    """«Сейчас / Станет / Разница» (8.2.6, TC-97)."""
    now = await simulate(ctx, period_code, {})
    new = await simulate(ctx, period_code, draft)
    a, b = now.as_dict(), new.as_dict()
    ratio_x100 = b["total"] * 100 // a["total"] if a["total"] else None
    return {"period": period_code, "current": a, "draft": b, "diff": {k: b[k] - a[k] for k in a},
            "ratio_x100": ratio_x100}
