"""TC-28…TC-36, TC-43…TC-50, TC-56: заказы, тарифы, баллы, квалификация."""

from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import func, select

from src.core.billing.periods import close_period
from src.core.scoring.points import count_points
from src.core.sync.orders import sync_orders
from src.db.models import Accrual, NotificationOutbox, Order, TariffCoefficient
from src.integrations.fleet.base import FleetOrder
from tests.factories import add_orders, add_profile, counted_referral, current


async def _close(ctx, clock, period):
    clock.set(period.ends_at + timedelta(hours=2))
    return await close_period(ctx, period)


async def _referral_accrual(ctx, ref_id):
    return (await ctx.session.execute(select(Accrual).where(Accrual.referral_id == ref_id,
                                                            Accrual.type == "referral"))).scalars().all()


@pytest.mark.parametrize("orders, expected_points, bonus", [
    ([("cargo", 100)], 30000, 30000),                       # TC-43
    ([("cargo", 99)], 29700, 0),                            # TC-44
    ([("econom", 300)], 30000, 30000),                      # TC-45
    ([("econom", 290)], 29000, 0),                          # TC-46
    ([("comfort", 300)], 30000, 30000),                     # TC-47
    ([("cargo", 60), ("econom", 120)], 30000, 30000),       # TC-48
    ([("cargo", 50), ("econom", 100)], 25000, 0),           # TC-49
    ([("cargo", 200)], 60000, 30000),                       # TC-50: 600 баллов при одной ступени
])
async def test_qualification_matrix(ctx, clock, orders, expected_points, bonus):
    referrer, friend, ref, pid = await counted_referral(ctx)
    for tariff, n in orders:
        await add_orders(ctx, pid, n, tariff)
    period = await current(ctx)
    _, pts, _ = await count_points(ctx, pid, period)
    assert pts == expected_points
    assert isinstance(pts, int)  # TC-56
    await _close(ctx, clock, period)
    accs = await _referral_accrual(ctx, ref.id)
    assert sum(a.amount for a in accs) == bonus


async def test_tariff_coefficients_tc29(ctx):
    _, _, _, pid = await counted_referral(ctx)
    period = await current(ctx)
    for tariff, expected in (("cargo", 300), ("econom", 100), ("comfort", 100), ("delivery", 70)):
        p = await add_profile(ctx)
        await add_orders(ctx, p.driver_profile_id, 1, tariff)
        _, pts, _ = await count_points(ctx, p.driver_profile_id, period)
        assert pts == expected, tariff


async def test_order_filters_tc33_35_36(ctx):
    _, _, _, pid = await counted_referral(ctx)
    period = await current(ctx)
    s = ctx.settings
    await add_orders(ctx, pid, 1, "econom", price=s.int("min_order_price") - 1)            # TC-33
    await add_orders(ctx, pid, 1, "econom", status="cancelled")                            # TC-35
    await add_orders(ctx, pid, 1, "econom", duration_sec=s.int("min_order_duration_sec") - 1)  # TC-36
    await add_orders(ctx, pid, 1, "econom", distance_m=s.int("min_order_distance_m") - 1)
    cnt, pts, _ = await count_points(ctx, pid, period)
    assert (cnt, pts) == (0, 0)
    await add_orders(ctx, pid, 1, "econom")
    assert (await count_points(ctx, pid, period))[:2] == (1, 100)


async def test_order_outside_period_not_counted(ctx):
    _, _, _, pid = await counted_referral(ctx)
    period = await current(ctx)
    await add_orders(ctx, pid, 1, "econom", ended_at=period.starts_at - timedelta(seconds=1))
    await add_orders(ctx, pid, 1, "econom", ended_at=period.ends_at)
    assert (await count_points(ctx, pid, period))[1] == 0


def _fo(i, pid, tariff, ended, **kw):
    return FleetOrder(id=f"F{i}", driver_profile_id=pid, status="complete", price=kw.get("price", 20000),
                      distance_m=5000, duration_sec=900, ended_at=ended, tariff_class=tariff)


async def test_sync_orders_idempotent_tc28(ctx, fleet, clock):
    _, _, _, pid = await counted_referral(ctx)
    for i in range(5):
        fleet.add_order(_fo(i, pid, "econom", clock.now() - timedelta(hours=i + 1)))
    await sync_orders(ctx)
    await sync_orders(ctx)
    assert await ctx.session.scalar(select(func.count()).select_from(Order)) == 5


async def test_unknown_tariff_tc30(ctx, fleet, clock):
    _, _, _, pid = await counted_referral(ctx)
    fleet.add_order(_fo(1, pid, "ultima", clock.now() - timedelta(hours=1)))
    await sync_orders(ctx)
    t = await ctx.session.get(TariffCoefficient, "ultima")
    assert t is not None and t.needs_setup and not t.is_active
    period = await current(ctx)
    assert (await count_points(ctx, pid, period))[1] == ctx.settings.int("default_tariff_coefficient_x100")
    alerts = (await ctx.session.execute(select(NotificationOutbox.template_key)
                                        .where(NotificationOutbox.audience == "admins"))).scalars().all()
    assert "admin.alert.unknown_tariff" in alerts


async def test_tariff_from_car_tc31_and_default_tc32(ctx, fleet, clock):
    p_car = await add_profile(ctx, car_category="cargo")
    p_none = await add_profile(ctx)
    fleet.add_order(_fo(1, p_car.driver_profile_id, None, clock.now() - timedelta(hours=1)))
    fleet.add_order(_fo(2, p_none.driver_profile_id, None, clock.now() - timedelta(hours=1)))
    await sync_orders(ctx)
    o1 = (await ctx.session.execute(select(Order).where(Order.external_order_id == "F1"))).scalar_one()
    o2 = (await ctx.session.execute(select(Order).where(Order.external_order_id == "F2"))).scalar_one()
    assert (o1.tariff_class, o1.tariff_source) == ("cargo", "car")
    assert (o2.tariff_class, o2.tariff_source) == (None, "default")
    from src.core.scoring.coefficients import unknown_tariff_orders_count
    assert await unknown_tariff_orders_count(ctx) == 1


async def test_price_field_is_order_cost_tc34():
    """E9: используется стоимость заказа (`price`), а не заработок водителя."""
    from src.integrations.fleet.api import _map_order
    o = _map_order({"id": "1", "status": "complete", "price": "23400.5000", "driver_profile": {"id": "d"},
                    "driver_income": "15000", "category": "econom", "mileage": "4200",
                    "booked_at": "2026-08-10T10:00:00+0000", "ended_at": "2026-08-10T10:20:00+0000"})
    assert o.price == 23401 and o.distance_m == 4200 and o.duration_sec == 1200 and o.tariff_class == "econom"
