"""TC-102…TC-107: антифрод."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from src.core.billing.periods import close_period, open_period
from src.core.billing.withdrawal import request_withdrawal
from src.core.fraud.engine import run_fraud_check
from src.db.models import Accrual, DriverOnlineTime, FraudFlag, Referral, User
from tests.factories import add_orders, assert_wallet_invariants, counted_referral, current, run_queue, with_profile


async def _flags(ctx):
    return set((await ctx.session.execute(select(FraudFlag.rule_code))).scalars().all())


async def _online(ctx, pid, hours, period):
    day = period.starts_at.astimezone().date()
    ctx.session.add(DriverOnlineTime(driver_profile_id=pid, stat_date=day + timedelta(days=3),
                                     online_seconds=int(hours * 3600)))
    await ctx.session.flush()


async def test_burst_qualify_tc102(ctx):
    _, _, _, pid = await counted_referral(ctx)
    await add_orders(ctx, pid, 300, "econom", days=2)
    await run_fraud_check(ctx, await current(ctx), apply_reactions=False)
    assert "BURST_QUALIFY" in await _flags(ctx)


async def test_tariff_anomaly_tc103(ctx, clock):
    _, _, _, pid = await counted_referral(ctx)
    jul = await open_period(ctx, "2026-07")
    await add_orders(ctx, pid, 19, "econom", ended_at=jul.starts_at + timedelta(days=20))
    await add_orders(ctx, pid, 1, "cargo", ended_at=jul.starts_at + timedelta(days=21))
    aug = await current(ctx)
    await add_orders(ctx, pid, 18, "cargo")
    await add_orders(ctx, pid, 2, "econom")
    await run_fraud_check(ctx, aug, apply_reactions=False)
    flag = (await ctx.session.execute(select(FraudFlag).where(FraudFlag.rule_code == "TARIFF_ANOMALY"))).scalar_one()
    assert flag.details == {"prev_share": 5, "share": 90}


async def test_impossible_hours_tc104(ctx):
    _, _, ref, pid = await counted_referral(ctx)
    aug = await current(ctx)
    await add_orders(ctx, pid, 300, "econom")
    await _online(ctx, pid, 6, aug)
    await run_fraud_check(ctx, aug, apply_reactions=False)
    flag = (await ctx.session.execute(select(FraudFlag).where(FraudFlag.rule_code == "IMPOSSIBLE_HOURS"))).scalar_one()
    assert flag.severity == "high" and flag.score == 45


async def test_impossible_hours_zero_online_critical_tc105(ctx):
    _, _, ref, pid = await counted_referral(ctx)
    aug = await current(ctx)
    await add_orders(ctx, pid, 10, "econom")
    await _online(ctx, pid, 0, aug)
    await run_fraud_check(ctx, aug, apply_reactions=False)
    flag = (await ctx.session.execute(select(FraudFlag).where(FraudFlag.rule_code == "IMPOSSIBLE_HOURS"))).scalar_one()
    assert flag.severity == "critical"
    ref = await ctx.session.get(Referral, ref.id, populate_existing=True)
    assert ref.is_fraud and not ref.is_counted and ref.status == "fraud"


async def test_high_score_cancels_tc106(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    aug = await current(ctx)
    await add_orders(ctx, pid, 300, "econom", days=2)                 # BURST 35
    await _online(ctx, pid, 6, aug)                                    # IMPOSSIBLE_HOURS 45 → 80
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    acc = (await ctx.session.execute(select(Accrual))).scalar_one()
    assert acc.status == "hold"  # открытые флаги → hold при создании (A8)
    stats = await run_fraud_check(ctx, aug, apply_reactions=True)  # задача fraud_check
    await ctx.session.commit()
    acc = (await ctx.session.execute(select(Accrual).execution_options(populate_existing=True))).scalar_one()
    assert acc.status == "cancelled" and stats.get("cancelled") == 1
    assert (await ctx.session.get(Referral, ref.id)).risk_score == 80
    from tests.factories import outbox_keys
    assert "admin.alert.fraud_review" in await outbox_keys(ctx)
    await assert_wallet_invariants(ctx, referrer.id)


async def test_mid_score_holds(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    aug = await current(ctx)
    await add_orders(ctx, pid, 300, "econom", days=2)  # BURST 35 → hold
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    await run_fraud_check(ctx, aug, apply_reactions=True)
    acc = (await ctx.session.execute(select(Accrual))).scalar_one()
    assert acc.status == "hold"


async def test_clawback_after_payout_tc107(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await with_profile(ctx, referrer)
    aug = await current(ctx)
    await add_orders(ctx, pid, 300, "econom")
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    await request_withdrawal(ctx, referrer.id)
    assert await run_queue(ctx) == ["completed"]
    await _online(ctx, pid, 0, aug)
    await run_fraud_check(ctx, aug)
    await ctx.session.commit()
    user = await ctx.session.get(User, referrer.id, populate_existing=True)
    assert user.debt == 30000
    from src.core.billing.withdrawal import withdrawal_block_reason
    assert (await withdrawal_block_reason(ctx, user)).key == "err.has_debt"
    await assert_wallet_invariants(ctx, referrer.id)


async def test_same_car_and_velocity(ctx):
    from tests.factories import add_profile, link, create_user
    referrer = await create_user(ctx)
    p = await add_profile(ctx, car_id="car-1")
    await link(ctx, referrer, p)
    _, friend, ref, pid = await counted_referral(ctx, referrer)
    from src.db.models import ParkDriverProfile
    (await ctx.session.get(ParkDriverProfile, pid)).car_id = "car-1"
    await ctx.session.flush()
    await run_fraud_check(ctx, await current(ctx), apply_reactions=False)
    assert "SAME_CAR" in await _flags(ctx)
