"""Антифрод (Раздел 12): правила, скоринг, реакции, clawback."""

from __future__ import annotations

from collections import Counter
from datetime import timedelta
from typing import Any

from sqlalchemy import exists, func, literal_column, select

from src.core.admin.audit import audit_log
from src.core.billing.accruals import cancel_accrual
from src.core.billing.debt import create_correction
from src.core.clock import prev_code, to_local
from src.core.context import Ctx
from src.core.notifications.service import alert_admins, money
from src.core.onboarding.registration import flag_fraud
from src.core.scoring.points import eligibility_filters
from src.db.models import (
    Accrual,
    Driver,
    DriverOnlineTime,
    FraudFlag,
    FraudWhitelist,
    Order,
    ParkDriverProfile,
    Period,
    Referral,
    User,
)

CRITICAL = "critical"


def _rule_cfg(ctx: Ctx, code: str) -> dict[str, Any]:
    return (ctx.settings.json("fraud_rules") or {}).get(code, {"severity": "medium", "score": 0})


async def _flag_exists(ctx: Ctx, referral_id: int, rule: str, period_id: int | None) -> bool:
    q = select(exists().where(FraudFlag.referral_id == referral_id, FraudFlag.rule_code == rule))
    if period_id is not None:
        q = select(exists().where(FraudFlag.referral_id == referral_id, FraudFlag.rule_code == rule,
                                  FraudFlag.period_id == period_id))
    return bool(await ctx.session.scalar(q))


async def _add_flag(ctx: Ctx, ref: Referral, rule: str, period: Period | None, details: dict[str, Any],
                    severity: str | None = None) -> FraudFlag | None:
    if await _flag_exists(ctx, ref.id, rule, period.id if period else None):
        return None
    flag = await flag_fraud(ctx, rule=rule, referral=ref, user_id=ref.referred_user_id, details=details)
    flag.period_id = period.id if period else None
    if severity:
        flag.severity = severity
    return flag


# ── правила по заказам периода ───────────────────────────────────────────────
async def _period_orders(ctx: Ctx, profile_id: str, period: Period) -> list[Order]:
    return list((await ctx.session.execute(
        select(Order).where(Order.driver_profile_id == profile_id, *eligibility_filters(ctx, period))
        .order_by(Order.ended_at))).scalars().all())


async def _coefficients(ctx: Ctx, period: Period) -> dict[str, int]:
    from src.core.scoring.snapshot import period_coefficients
    return await period_coefficients(ctx, period.id)


def _points(orders: list[Order], coefs: dict[str, int], default: int) -> int:
    return sum(coefs.get(o.tariff_class or "unknown", default) for o in orders)


async def check_impossible_hours(ctx: Ctx, ref: Referral, profile_id: str, period: Period,
                                 points_x100: int) -> FraudFlag | None:
    """E7: online_hours == 0 и points > 0 → critical; points/hour > порога → high."""
    rows, secs = (await ctx.session.execute(
        select(func.count(), func.coalesce(func.sum(DriverOnlineTime.online_seconds), 0)).where(
            DriverOnlineTime.driver_profile_id == profile_id,
            DriverOnlineTime.stat_date >= to_local(period.starts_at).date(),
            DriverOnlineTime.stat_date < to_local(period.ends_at).date()))).one()
    secs = int(secs)
    if points_x100 <= 0 or not rows:
        return None  # нет данных о времени на линии ≠ ноль часов (D-16)
    if secs == 0:
        return await _add_flag(ctx, ref, "IMPOSSIBLE_HOURS", period,
                               {"online_seconds": 0, "points_x100": points_x100}, severity=CRITICAL)
    limit = ctx.settings.int("impossible_hours_points_per_hour")
    # points / hours > limit  ⇔  points_x100 * 3600 > limit * 100 * secs  (целочисленно, R2)
    if points_x100 * 3600 > limit * 100 * secs:
        return await _add_flag(ctx, ref, "IMPOSSIBLE_HOURS", period,
                               {"online_seconds": secs, "points_x100": points_x100})
    return None


def check_burst(orders: list[Order], coefs: dict[str, int], default: int, threshold: int,
                days: int) -> dict[str, Any] | None:
    """BURST_QUALIFY: порог набран быстрее чем за N дней (окно скользит по заказам)."""
    window = timedelta(days=days)
    start = 0
    acc = 0
    for o in orders:
        acc += coefs.get(o.tariff_class or "unknown", default)
        while orders[start].ended_at and o.ended_at and o.ended_at - orders[start].ended_at >= window:
            acc -= coefs.get(orders[start].tariff_class or "unknown", default)
            start += 1
        if acc >= threshold:
            return {"from": str(orders[start].ended_at), "to": str(o.ended_at), "points_x100": acc}
    return None


def share_percent(part: int, total: int) -> int:
    return part * 100 // total if total else 0


async def check_order_patterns(ctx: Ctx, ref: Referral, profile_id: str, period: Period) -> list[FraudFlag]:
    s = ctx.settings
    flags: list[FraudFlag | None] = []
    orders = await _period_orders(ctx, profile_id, period)
    coefs = await _coefficients(ctx, period)
    default = period.default_coefficient_x100
    points = _points(orders, coefs, default)

    flags.append(await check_impossible_hours(ctx, ref, profile_id, period, points))
    burst = check_burst(orders, coefs, default, period.threshold_points_x100, s.int("fraud_burst_days"))
    if burst:
        flags.append(await _add_flag(ctx, ref, "BURST_QUALIFY", period, burst))

    # TARIFF_ANOMALY: резкий рост доли высококоэффициентного тарифа к прошлому периоду
    prev = (await ctx.session.execute(select(Period).where(Period.code == prev_code(period.code)))).scalar_one_or_none()
    if prev is not None and orders:
        high = {code for code, k in coefs.items() if k > default}
        prev_orders = await _period_orders(ctx, profile_id, prev)
        if prev_orders:
            cur_share = share_percent(sum(1 for o in orders if (o.tariff_class or "") in high), len(orders))
            prev_share = share_percent(sum(1 for o in prev_orders if (o.tariff_class or "") in high), len(prev_orders))
            if cur_share - prev_share >= s.int("fraud_tariff_anomaly_jump_percent"):
                flags.append(await _add_flag(ctx, ref, "TARIFF_ANOMALY", period,
                                             {"prev_share": prev_share, "share": cur_share}))

    min_orders = s.int("fraud_min_orders_for_patterns")
    if len(orders) >= min_orders:
        # SHORT_RIDES: доля заказов на минимальной дистанции/длительности (до 2× порога)
        short = sum(1 for o in orders if o.distance_m < 2 * s.int("min_order_distance_m")
                    or o.duration_sec < 2 * s.int("min_order_duration_sec"))
        if share_percent(short, len(orders)) > s.int("fraud_short_rides_share_percent"):
            flags.append(await _add_flag(ctx, ref, "SHORT_RIDES", period, {"short": short, "total": len(orders)}))
        # SAME_ROUTE: повторяющиеся пары адресов
        routes = Counter((o.address_from, o.address_to) for o in orders if o.address_from and o.address_to)
        repeated = sum(c for c in routes.values() if c > 1)
        if share_percent(repeated, len(orders)) > s.int("fraud_same_route_share_percent"):
            flags.append(await _add_flag(ctx, ref, "SAME_ROUTE", period, {"repeated": repeated, "total": len(orders)}))
        # NIGHT_PATTERN: аномальная концентрация ночных заказов
        night_hours = set(s.list("fraud_night_hours"))
        night = sum(1 for o in orders if o.ended_at and to_local(o.ended_at).hour in night_hours)
        if share_percent(night, len(orders)) > s.int("fraud_night_share_percent"):
            flags.append(await _add_flag(ctx, ref, "NIGHT_PATTERN", period, {"night": night, "total": len(orders)}))
        # LOW_GMV: средний чек ниже среднего по тарифу парка
        flags.extend(await _check_low_gmv(ctx, ref, orders, period))
    return [f for f in flags if f is not None]


async def _check_low_gmv(ctx: Ctx, ref: Referral, orders: list[Order], period: Period) -> list[FraudFlag | None]:
    """Средний чек водителя ниже среднего по тарифу в парке более чем на N% (целочисленно)."""
    by_tariff: dict[str, list[int]] = {}
    for o in orders:
        by_tariff.setdefault(o.tariff_class or "unknown", []).append(o.price)
    low_pct = ctx.settings.int("fraud_low_gmv_percent")
    for tariff, prices in by_tariff.items():
        park_sum, park_cnt = (await ctx.session.execute(select(
            func.coalesce(func.sum(Order.price), 0), func.count()).where(
            func.coalesce(Order.tariff_class, literal_column("'unknown'")) == tariff, *eligibility_filters(ctx, period)))).one()
        if not park_cnt:
            continue
        # avg_driver < avg_park × (100 − low) / 100
        if sum(prices) * int(park_cnt) * 100 < int(park_sum) * len(prices) * (100 - low_pct):
            return [await _add_flag(ctx, ref, "LOW_GMV", period, {"tariff": tariff})]
    return []


# ── правила по рефереру ──────────────────────────────────────────────────────
async def check_referrer_rules(ctx: Ctx, ref: Referral, period: Period | None) -> list[FraudFlag]:
    s = ctx.settings
    out: list[FraudFlag | None] = []
    # SAME_CAR
    rows = (await ctx.session.execute(
        select(Driver.user_id, ParkDriverProfile.car_id)
        .join(ParkDriverProfile, ParkDriverProfile.driver_profile_id == Driver.driver_profile_id)
        .where(Driver.user_id.in_([ref.referrer_user_id, ref.referred_user_id])))).all()
    cars = {uid: car for uid, car in rows}
    car_a, car_b = cars.get(ref.referrer_user_id), cars.get(ref.referred_user_id)
    if car_a and car_a == car_b:
        out.append(await _add_flag(ctx, ref, "SAME_CAR", None, {"car_id": car_a}))
    # VELOCITY: > N рефералов за сутки у реферера
    day_ago = ref.created_at - timedelta(days=1)
    velocity = int(await ctx.session.scalar(select(func.count()).where(
        Referral.referrer_user_id == ref.referrer_user_id, Referral.created_at >= day_ago,
        Referral.created_at <= ref.created_at)) or 0)
    if velocity > s.int("fraud_velocity_per_day"):
        out.append(await _add_flag(ctx, ref, "VELOCITY", None, {"count": velocity}))
    # PHONE_CLUSTER: телефоны рефералов идут подряд
    phones = sorted(int(p[1:]) for p in (await ctx.session.execute(
        select(User.phone).join(Referral, Referral.referred_user_id == User.id)
        .where(Referral.referrer_user_id == ref.referrer_user_id, User.phone.is_not(None)))).scalars().all() if p)
    run, best = 1, 1
    for a, b in zip(phones, phones[1:]):
        run = run + 1 if b - a == 1 else 1
        best = max(best, run)
    if best >= s.int("fraud_phone_cluster_size"):
        out.append(await _add_flag(ctx, ref, "PHONE_CLUSTER", None, {"run": best}))
    return [f for f in out if f is not None]


# ── скоринг и реакции ────────────────────────────────────────────────────────
async def open_score(ctx: Ctx, referral_id: int) -> tuple[int, bool]:
    rows = (await ctx.session.execute(select(FraudFlag.score, FraudFlag.severity).where(
        FraudFlag.referral_id == referral_id, FraudFlag.resolved.is_(False)))).all()
    return min(100, sum(score for score, _ in rows)), any(sev == CRITICAL for _, sev in rows)


async def apply_reaction(ctx: Ctx, ref: Referral, period: Period | None) -> str:
    """0–29 → авто-одобрение; 30–69 → hold; 70–99 → cancelled + задача модератору;
    critical → реферал fraud, is_counted=FALSE, начисления cancelled, clawback."""
    s = ctx.settings
    score, critical = await open_score(ctx, ref.id)
    ref.risk_score = score
    if critical:
        await mark_fraud(ctx, ref, actor_id=None, reason="critical fraud flag")
        return "fraud"
    if score < s.int("fraud_autoapprove_below"):
        flags = (await ctx.session.execute(select(FraudFlag).where(
            FraudFlag.referral_id == ref.id, FraudFlag.resolved.is_(False)))).scalars().all()
        for f in flags:
            f.resolved, f.resolved_at = True, ctx.now()
        return "auto_approved"
    accs = await _referral_accruals(ctx, ref, period)
    if score >= s.int("fraud_autoreject_above"):
        for acc in accs:
            await cancel_accrual(ctx, acc, f"fraud score {score}")
        await alert_admins(ctx, "fraud_review", referral_id=ref.id, score=score)
        return "cancelled"
    for acc in accs:
        if acc.status == "available":
            await _to_hold(ctx, acc)
    return "hold"


async def _to_hold(ctx: Ctx, acc: Accrual) -> None:
    from src.core.billing.wallet import lock_user, write_ledger
    user = await lock_user(ctx, acc.user_id)
    acc.status = "hold"
    acc.hold_until = None
    user.balance_available -= acc.amount
    user.balance_hold += acc.amount
    await write_ledger(ctx, user, "accrual_hold", -acc.amount, "accrual", acc.id)


async def _referral_accruals(ctx: Ctx, ref: Referral, period: Period | None) -> list[Accrual]:
    q = select(Accrual).where(Accrual.referral_id == ref.id, Accrual.status.in_(["available", "hold"]))
    if period is not None:
        q = q.where(Accrual.period_id == period.id)
    return list((await ctx.session.execute(q.order_by(Accrual.id))).scalars().all())


async def mark_fraud(ctx: Ctx, ref: Referral, actor_id: int | None, reason: str) -> None:
    """Реферал признан фродом: аннулирование начислений; уже выведенное — clawback в долг."""
    ref.is_fraud, ref.is_counted, ref.status = True, False, "fraud"
    accs = (await ctx.session.execute(select(Accrual).where(
        Accrual.referral_id == ref.id, Accrual.status != "cancelled"))).scalars().all()
    clawback: dict[int, int] = {}
    for acc in accs:
        if acc.status in ("available", "hold"):
            await cancel_accrual(ctx, acc, f"fraud: {reason}")
        elif acc.status in ("withdrawn", "reserved") and acc.comment != "debt_repayment":
            clawback[acc.user_id] = clawback.get(acc.user_id, 0) + acc.amount
    for user_id, amount in clawback.items():
        await create_correction(ctx, user_id=user_id, amount=-amount, reason=f"Clawback: реферал #{ref.id} — фрод",
                                created_by=actor_id, notify=True)
    await audit_log(ctx, actor_id, "referral_marked_fraud", "referral", ref.id,
                    new_value={"reason": reason, "clawback": sum(clawback.values())})
    await alert_admins(ctx, "referral_fraud", referral_id=ref.id, clawback=money(sum(clawback.values())))


async def run_fraud_check(ctx: Ctx, period: Period, *, apply_reactions: bool = True) -> dict[str, int]:
    """Прогон правил по засчитанным рефералам периода. В close_period — до выплат (D-12):
    флаги ставят новые начисления в hold через A8, реакции применяются задачей fraud_check."""
    from src.core.referral.queries import referrals_with_profiles

    whitelist = set((await ctx.session.execute(select(FraudWhitelist.user_id))).scalars().all())
    stats = Counter[str]()
    for ref, pid in await referrals_with_profiles(ctx):
        if ref.referred_user_id in whitelist or ref.referrer_user_id in whitelist:
            continue
        new_flags = await check_referrer_rules(ctx, ref, period)
        if pid:
            new_flags += await check_order_patterns(ctx, ref, pid, period)
        stats["flags"] += len(new_flags)
        score, critical = await open_score(ctx, ref.id)
        ref.risk_score = score
        if not score and not critical:
            continue
        # critical и «низкий риск» решаются сразу; hold/cancel — в задаче fraud_check
        if apply_reactions or critical or score < ctx.settings.int("fraud_autoapprove_below"):
            stats[await apply_reaction(ctx, ref, period)] += 1
    await ctx.session.flush()
    return dict(stats)


async def resolve_flag(ctx: Ctx, flag_id: int, actor_id: int, *, confirm_fraud: bool) -> None:
    flag = await ctx.session.get(FraudFlag, flag_id)
    if flag is None:
        return
    flag.resolved, flag.resolved_by, flag.resolved_at = True, actor_id, ctx.now()
    await audit_log(ctx, actor_id, "fraud_flag_resolved", "fraud_flag", flag_id,
                    new_value={"confirm_fraud": confirm_fraud})
    if flag.referral_id is None:
        return
    ref = await ctx.session.get(Referral, flag.referral_id)
    assert ref is not None
    if confirm_fraud:
        await mark_fraud(ctx, ref, actor_id, f"confirmed {flag.rule_code}")
        return
    score, _ = await open_score(ctx, ref.id)
    ref.risk_score = score
    if score == 0:
        # снятие холда с начислений реферала
        from src.core.billing.accruals import release_accrual
        accs = (await ctx.session.execute(select(Accrual).where(
            Accrual.referral_id == ref.id, Accrual.status == "hold"))).scalars().all()
        for acc in accs:
            if acc.hold_until is None or acc.hold_until <= ctx.now():
                await release_accrual(ctx, acc)


async def whitelist_user(ctx: Ctx, user_id: int, actor_id: int, reason: str) -> None:
    if await ctx.session.get(FraudWhitelist, user_id) is None:
        ctx.session.add(FraudWhitelist(user_id=user_id, reason=reason, created_by=actor_id))
        await audit_log(ctx, actor_id, "fraud_whitelist_added", "user", user_id, new_value={"reason": reason})
