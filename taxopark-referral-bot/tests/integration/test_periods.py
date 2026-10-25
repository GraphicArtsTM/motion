"""TC-37…TC-42, TC-51…TC-55: периоды, заморозка, пересчёт, бонусы."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import func, select

from src.core.billing.bonus_rules import upsert_rule
from src.core.billing.periods import close_period, ensure_current_period, get_period, open_period
from src.core.billing.recalculation import recalculate_closed_period
from src.core.billing.withdrawal import request_withdrawal
from src.core.clock import next_code
from src.core.errors import BusinessError
from src.core.scoring.coefficients import upsert_tariff
from src.core.scoring.snapshot import period_coefficients
from src.core.sync.orders import sync_orders
from src.db.models import Accrual, Period, User
from src.integrations.fleet.base import FleetOrder
from tests.factories import (
    add_orders,
    assert_wallet_invariants,
    counted_referral,
    create_user,
    current,
    outbox_keys,
    run_queue,
    tashkent,
    with_profile,
)


async def test_first_start_mid_month_creates_period_tc37(ctx):
    assert await ctx.session.scalar(select(func.count()).select_from(Period)) == 0
    p = await ensure_current_period(ctx)
    assert p.code == "2026-08" and p.status == "open"
    assert p.threshold_points_x100 == ctx.settings.int("qualification_threshold_points_x100")


async def test_snapshot_on_open_tc38(ctx):
    p = await open_period(ctx, "2026-08")
    coefs = await period_coefficients(ctx, p.id)
    assert coefs["cargo"] == 300 and coefs["econom"] == 100
    again = await open_period(ctx, "2026-08")
    assert again.id == p.id and await period_coefficients(ctx, p.id) == coefs


async def test_coefficient_change_mid_month_tc39_tc40(ctx, clock):
    admin = await create_user(ctx, role="admin")
    referrer, friend, ref, pid = await counted_referral(ctx)
    aug = await current(ctx)
    await upsert_tariff(ctx, code="cargo", actor_id=admin.id, coefficient_x100=400)
    await ctx.session.commit()
    assert (await period_coefficients(ctx, aug.id))["cargo"] == 300  # TC-39
    await add_orders(ctx, pid, 99, "cargo")
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    assert await ctx.session.scalar(select(func.count()).select_from(Accrual)) == 0  # 297 баллов по снимку
    sep = await open_period(ctx, next_code(aug.code))
    assert (await period_coefficients(ctx, sep.id))["cargo"] == 400  # TC-40
    await add_orders(ctx, pid, 75, "cargo", ended_at=sep.starts_at + timedelta(days=12))
    clock.set(sep.ends_at + timedelta(hours=2))
    await close_period(ctx, sep)
    assert await ctx.session.scalar(select(func.sum(Accrual.amount))) == 30000


async def test_late_order_triggers_adjustment_tc41(ctx, clock, fleet):
    referrer, friend, ref, pid = await counted_referral(ctx)
    aug = await current(ctx)
    await add_orders(ctx, pid, 290, "econom")
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    assert await ctx.session.scalar(select(func.count()).select_from(Accrual)) == 0
    clock.set(aug.ends_at + timedelta(hours=48))
    for i in range(20):  # заказы августа, пришедшие через 48 часов
        fleet.add_order(FleetOrder(id=f"late{i}", driver_profile_id=pid, status="complete", price=20000,
                                   distance_m=5000, duration_sec=900, tariff_class="econom",
                                   ended_at=aug.ends_at - timedelta(hours=3, minutes=i)))
    res = await sync_orders(ctx)
    assert res["recalculated"] == ["2026-08"]
    accs = (await ctx.session.execute(select(Accrual).where(Accrual.user_id == referrer.id))).scalars().all()
    assert [(a.type, a.amount) for a in accs] == [("adjustment", 30000)]
    assert "wallet.adjustment_up" in await outbox_keys(ctx, referrer.id)
    await assert_wallet_invariants(ctx, referrer.id)


async def test_recalc_down_after_withdrawal_creates_debt_tc42(ctx, clock, fleet):
    referrer, friend, ref, pid = await counted_referral(ctx)
    aug = await current(ctx)
    await add_orders(ctx, pid, 300, "econom")
    await with_profile(ctx, referrer)
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    await request_withdrawal(ctx, referrer.id)
    assert await run_queue(ctx) == ["completed"]
    # отмена части заказов (статус изменился) → друг ниже порога
    from src.db.models import Order
    orders = (await ctx.session.execute(select(Order).where(Order.driver_profile_id == pid).limit(20))).scalars().all()
    for o in orders:
        o.status = "cancelled"
    await ctx.session.commit()
    period = await get_period(ctx, aug.code)
    await recalculate_closed_period(ctx, period, reason="manual")
    user = await ctx.session.get(User, referrer.id, populate_existing=True)
    assert user.debt == 30000 and user.balance_available == 0
    try:
        await request_withdrawal(ctx, referrer.id, 1000)
        raise AssertionError("withdrawal must be blocked with debt")
    except BusinessError as e:
        assert e.key == "err.has_debt"
    admin_alerts = await outbox_keys(ctx)
    assert "admin.alert.period_recalc_overpaid" in admin_alerts
    assert "wallet.debt_created" not in await outbox_keys(ctx, referrer.id)  # сначала разбирается админ
    await assert_wallet_invariants(ctx, referrer.id)


async def test_new_bonus_step_tc51(ctx, clock):
    admin = await create_user(ctx, role="admin")
    await upsert_rule(ctx, actor_id=admin.id, recipient="referrer", min_percent=150, bonus_uzs=40000)
    referrer, friend, ref, pid = await counted_referral(ctx)
    await add_orders(ctx, pid, 150, "cargo")  # 450 баллов
    aug = await current(ctx)
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    assert await ctx.session.scalar(select(func.sum(Accrual.amount))) == 40000


async def test_reference_scenario_tc52_tc53(ctx, clock):
    """Эталон п.2.6: 360 → 30 000; 150 → 0; 315 → 30 000; 294 → 0; 600 → 30 000. Итого 90 000."""
    clock.set(tashkent(2026, 1, 10, 12))
    referrer, friend, ref, pid = await counted_referral(ctx)
    code = "2026-01"
    for points in (360, 150, 315, 294, 600):
        p = await open_period(ctx, code)
        await add_orders(ctx, pid, points, "econom", ended_at=p.starts_at + timedelta(days=20))
        clock.set(p.ends_at + timedelta(hours=2))
        await close_period(ctx, p)
        code = next_code(code)
    total = await ctx.session.scalar(select(func.sum(Accrual.amount)).where(Accrual.user_id == referrer.id))
    assert total == 90000
    # TC-53: через 24 месяца бессрочность сохраняется
    for _ in range(19):
        p = await open_period(ctx, code)
        clock.set(p.ends_at + timedelta(hours=2))
        await close_period(ctx, p)
        code = next_code(code)
    p = await open_period(ctx, code)
    await add_orders(ctx, pid, 300, "econom", ended_at=p.starts_at + timedelta(days=12))
    clock.set(p.ends_at + timedelta(hours=2))
    await close_period(ctx, p)
    assert await ctx.session.scalar(select(func.sum(Accrual.amount)).where(Accrual.user_id == referrer.id)) == 120000


async def test_not_counted_referral_no_accrual_tc54(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    ref.is_counted = False
    await add_orders(ctx, pid, 600, "econom")
    aug = await current(ctx)
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    assert await ctx.session.scalar(select(func.count()).select_from(Accrual)) == 0


async def test_repeat_close_no_duplicates_tc55(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await add_orders(ctx, pid, 300, "econom")
    aug = await current(ctx)
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    aug.status = "calculating"  # идемпотентный перезапуск закрытия
    await ctx.session.commit()
    await close_period(ctx, aug)
    assert await ctx.session.scalar(select(func.count()).select_from(Accrual)) == 1
    assert (await outbox_keys(ctx, referrer.id)).count("period.result") == 1


async def test_budget_exceeded_tc100(ctx, clock):
    await ctx.settings.set(ctx.session, "monthly_program_budget", 45000, None)
    referrer, *_ , pid1 = await counted_referral(ctx)
    _, _, _, pid2 = await counted_referral(ctx, referrer)
    for pid in (pid1, pid2):
        await add_orders(ctx, pid, 300, "econom")
    aug = await current(ctx)
    clock.set(aug.ends_at + timedelta(hours=2))
    stats = await close_period(ctx, aug)
    statuses = sorted((await ctx.session.execute(select(Accrual.status))).scalars().all())
    assert statuses == ["available", "hold"] and stats.held_by_budget == 1
    assert "admin.alert.budget_exceeded" in await outbox_keys(ctx)
