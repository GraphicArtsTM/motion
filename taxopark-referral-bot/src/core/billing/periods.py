"""Расчётные периоды: открытие и снимок (A4), ensure_current_period (E4), закрытие (A6)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from src.core.billing.accruals import count_accruals, create_accrual_if_not_exists, initial_accrual_status
from src.core.billing.bonus_rules import best_bonus_rule
from src.core.billing.budget import BudgetTracker, period_spent
from src.core.billing.milestones import (
    active_milestones_ordered_asc,
    record_user_milestone,
    user_has_milestone,
)
from src.core.billing.qualification import (
    count_distinct_qualified_referrals_lifetime,
    qualifications_for_referrer,
    upsert_qualification,
    users_with_counted_referrals,
)
from src.core.billing.wallet import recalc_user_balances, sha256
from src.core.clock import month_code, period_bounds
from src.core.context import Ctx
from src.core.notifications.service import alert_admins, money, month, notify_user, sent_ever
from src.core.referral.queries import referrals_with_profiles
from src.core.scoring.points import achieved_percent, points_for_profiles
from src.core.scoring.snapshot import has_snapshot, take_snapshot
from src.db.models import Accrual, Period, Referral, User

COUNTED_STATUSES = ("hired", "active", "qualified")


async def get_period(ctx: Ctx, code: str, *, for_update: bool = False) -> Period | None:
    q = select(Period).where(Period.code == code)
    if for_update:
        q = q.with_for_update()
    return (await ctx.session.execute(q.execution_options(populate_existing=True))).scalar_one_or_none()


async def get_open_period(ctx: Ctx, code: str) -> Period | None:
    return (await ctx.session.execute(
        select(Period).where(Period.code == code, Period.status == "open"))).scalar_one_or_none()


async def period_of(ctx: Ctx, dt: Any) -> Period | None:
    if dt is None:
        return None
    return (await ctx.session.execute(
        select(Period).where(Period.starts_at <= dt, Period.ends_at > dt))).scalar_one_or_none()


async def open_period(ctx: Ctx, code: str) -> Period:
    """A4. Идемпотентно и безопасно при параллельных вызовах: период создаётся один раз
    (INSERT … ON CONFLICT), снимок — под блокировкой строки периода."""
    starts, ends = period_bounds(code)
    await ctx.session.execute(
        pg_insert(Period).values(code=code, starts_at=starts, ends_at=ends, status="open",
                                 threshold_points_x100=ctx.settings.int("qualification_threshold_points_x100"),
                                 default_coefficient_x100=ctx.settings.int("default_tariff_coefficient_x100"))
        .on_conflict_do_nothing(index_elements=["code"]))
    p = await get_period(ctx, code, for_update=True)
    assert p is not None
    if not await has_snapshot(ctx, p.id):
        await take_snapshot(ctx, p)
    await ctx.session.commit()
    return p


async def ensure_current_period(ctx: Ctx) -> Period:
    """E4. Вызывается при старте приложения и перед любым расчётом."""
    code = month_code(ctx.now())
    p = await get_period(ctx, code)
    if p is None or not await has_snapshot(ctx, p.id):
        p = await open_period(ctx, code)
    return p


async def current_period(ctx: Ctx) -> Period:
    return await ensure_current_period(ctx)


@dataclass
class CloseStats:
    qualified: int = 0
    accruals: int = 0
    amount: int = 0
    held_by_budget: int = 0
    welcome: int = 0
    milestones: int = 0
    new_welcome_users: set[int] = field(default_factory=set)


async def force_sync_orders(ctx: Ctx) -> None:
    from src.core.sync.orders import sync_orders
    from src.integrations.fleet.errors import FleetError

    if ctx.fleet is None:
        return
    try:
        await sync_orders(ctx, recalc_closed=False)
    except FleetError as e:
        await alert_admins(ctx, "fleet_sync_failed", job="close_period", error=str(e)[:200])
        await ctx.session.commit()


async def close_period(ctx: Ctx, period: Period) -> CloseStats:
    """A6. Порядок шагов критичен. Повторный запуск безопасен (идемпотентные ключи)."""
    assert period.status in ("open", "calculating"), f"period {period.code} is {period.status}"
    await force_sync_orders(ctx)
    period = await get_period(ctx, period.code, for_update=True)  # type: ignore[assignment]
    assert period is not None
    period.status = "calculating"
    await ctx.session.commit()

    threshold = period.threshold_points_x100
    budget = BudgetTracker(budget=ctx.settings.int("monthly_program_budget"),
                           spent=await period_spent(ctx, period.id))
    per_ref_limit = ctx.settings.int("max_payout_per_referrer_per_month")
    welcome_on = ctx.settings.bool("referred_bonus_enabled")
    milestones_on = ctx.settings.bool("milestones_enabled")
    stats = CloseStats()

    async def emit(user_id: int, **kw: Any) -> tuple[Accrual | None, bool]:
        """Создание начисления с учётом бюджета (N7). Возвращает (начисление, уже_было)."""
        existing = (await ctx.session.execute(
            select(Accrual).where(Accrual.idempotency_key == kw["idempotency_key"]))).scalar_one_or_none()
        if existing is not None:
            return existing, True
        over = budget.is_over(kw["amount"])
        status = "hold" if over else await initial_accrual_status(ctx, kw.get("referral_id"))
        acc = await create_accrual_if_not_exists(ctx, user_id=user_id, status=status, **kw)
        if acc:
            budget.spent += kw["amount"]
            stats.accruals += 1
            stats.amount += kw["amount"]
            if over:
                stats.held_by_budget += 1
                if not budget.alerted:
                    budget.alerted = True
                    await alert_admins(ctx, "budget_exceeded", period=period.code, budget=money(budget.budget),
                                       spent=money(budget.spent))
        return acc, False

    # ── ШАГ 1: баллы и квалификации ──────────────────────────────────
    refs = await referrals_with_profiles(ctx, statuses=COUNTED_STATUSES)
    points = await points_for_profiles(ctx, period, [pid for _, pid in refs if pid])
    for ref, pid in refs:
        res = points.get(pid) if pid else None
        cnt, pts = (res.eligible_orders_count, res.points_x100) if res else (0, 0)
        percent = achieved_percent(pts, threshold)
        await upsert_qualification(ctx, referral_id=ref.id, period_id=period.id, eligible_orders_count=cnt,
                                   points_x100=pts, threshold_points_x100=threshold, achieved_percent=percent,
                                   is_qualified=pts >= threshold, breakdown=res.breakdown_json() if res else [])
        if pts > 0 and ref.status == "hired":
            ref.status = "active"
        if pts >= threshold:
            stats.qualified += 1
            ref.status = "qualified"
            if ref.first_qualified_at is None:
                ref.first_qualified_at = ctx.now()
    await ctx.session.flush()

    # ── ШАГ 1.5: антифрод до выплат (D-12) ───────────────────────────
    from src.core.fraud.engine import run_fraud_check
    await run_fraud_check(ctx, period, apply_reactions=False)

    # ── ШАГ 2: бонусы пригласившим + welcome-бонусы друзьям ──────────
    for referrer_id in await users_with_counted_referrals(ctx):
        referrer_paid = 0
        for q in await qualifications_for_referrer(ctx, period.id, referrer_id, only_qualified=True):
            ref = await ctx.session.get(Referral, q.referral_id)
            assert ref is not None
            rule = await best_bonus_rule(ctx, q.achieved_percent, "referrer")
            key = sha256(f"ref:{referrer_id}:{q.referral_id}:{period.code}")
            if rule:
                existing = (await ctx.session.execute(
                    select(Accrual).where(Accrual.idempotency_key == key))).scalar_one_or_none()
                if existing is not None:
                    referrer_paid += rule.bonus_uzs
                elif not (per_ref_limit and referrer_paid + rule.bonus_uzs > per_ref_limit):
                    acc, _ = await emit(referrer_id, idempotency_key=key, type="referral", referral_id=q.referral_id,
                                        period_id=period.id, bonus_rule_id=rule.id, amount=rule.bonus_uzs)
                    referrer_paid += rule.bonus_uzs
                    if acc:
                        friend = await ctx.session.get(User, ref.referred_user_id)
                        await notify_user(ctx, referrer_id, "friends.qualified",
                                          name=friend.full_name if friend else "", amount=money(rule.bonus_uzs))

            if welcome_on:  # N1
                paid_before = await count_accruals(ctx, user_id=ref.referred_user_id, type="referred_welcome")
                max_p = ctx.settings.int("referred_bonus_max_periods")
                wkey = sha256(f"wel:{ref.referred_user_id}:{period.code}")
                if max_p == 0 or paid_before < max_p:
                    wrule = await best_bonus_rule(ctx, q.achieved_percent, "referred")
                    if wrule:
                        acc, existed = await emit(ref.referred_user_id, idempotency_key=wkey, type="referred_welcome",
                                                  referral_id=ref.id, period_id=period.id,
                                                  bonus_rule_id=wrule.id, amount=wrule.bonus_uzs)
                        if acc and not existed:
                            stats.welcome += 1
                            stats.new_welcome_users.add(ref.referred_user_id)
                            await notify_user(ctx, ref.referred_user_id, "welcome.bonus_paid",
                                              amount=money(wrule.bonus_uzs))

    # ── ШАГ 3: счётчик друзей + награды (ТОЛЬКО ПОСЛЕ ШАГА 1) ────────
    milestones = await active_milestones_ordered_asc(ctx) if milestones_on else []
    for referrer_id in await users_with_counted_referrals(ctx):
        n = await count_distinct_qualified_referrals_lifetime(ctx, referrer_id)
        referrer = await ctx.session.get(User, referrer_id)
        assert referrer is not None
        referrer.qualified_referrals_count = n  # считаем ВСЕГДА

        for m in milestones:
            if n >= m.required_count and not await user_has_milestone(ctx, referrer_id, m.id):
                acc, _ = await emit(referrer_id, idempotency_key=sha256(f"ms:{referrer_id}:{m.code}"),
                                    type="milestone", milestone_id=m.id, period_id=period.id, amount=m.reward_uzs)
                await record_user_milestone(ctx, referrer_id, m.id, accrual_id=acc.id if acc else None,
                                            granted_without_payment=False)
                stats.milestones += 1
                await notify_user(ctx, referrer_id, "milestone.achieved", name=m.name, reward=money(m.reward_uzs))

        await recalc_user_balances(ctx, referrer_id)
        await notify_period_result(ctx, referrer_id, period)

    for uid in stats.new_welcome_users:
        await recalc_user_balances(ctx, uid)

    period.status = "closed"
    period.closed_at = ctx.now()
    await ctx.session.commit()
    return stats


async def notify_period_result(ctx: Ctx, referrer_id: int, period: Period) -> None:
    """Итоги месяца рефереру (один раз на период)."""
    if await sent_ever(ctx, referrer_id, "period_result", period.id):
        return
    accs = (await ctx.session.execute(
        select(Accrual).where(Accrual.user_id == referrer_id, Accrual.period_id == period.id,
                              Accrual.type.in_(["referral", "milestone"]), Accrual.parent_accrual_id.is_(None))
    )).scalars().all()
    referral_accs = [a for a in accs if a.type == "referral"]
    total = sum(a.amount for a in accs)
    unit = referral_accs[0].amount if referral_accs else 0
    await notify_user(ctx, referrer_id, "period.result" if total else "period.result_empty",
                      kind="period_result", subject_id=period.id, month=month(period.code),
                      count=len(referral_accs), unit=money(unit), total=money(total))


async def close_due_periods(ctx: Ctx) -> list[str]:
    """Задача close_period: закрывает все открытые периоды, чей месяц закончился."""
    rows = (await ctx.session.execute(
        select(Period).where(Period.status.in_(["open", "calculating"]), Period.ends_at <= ctx.now())
        .order_by(Period.starts_at))).scalars().all()
    closed = []
    for p in rows:
        await close_period(ctx, p)
        closed.append(p.code)
    return closed
