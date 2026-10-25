"""TC-57…TC-70: welcome-бонус (N1) и награды за достижения."""

from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import func, select, update

from src.core.billing.milestones import delete_milestone, enable_milestones
from src.core.billing.periods import close_period, open_period
from src.core.clock import next_code
from src.core.errors import BusinessError, PermissionDenied
from src.core.simulation.simulator import compare
from src.db.models import Accrual, BonusRule, Milestone, Qualification, Referral, User, UserMilestone
from tests.factories import add_orders, counted_referral, create_user, current, outbox_keys


async def _enable_welcome(ctx, max_periods=1):
    await ctx.settings.set(ctx.session, "referred_bonus_enabled", True, None)
    await ctx.settings.set(ctx.session, "referred_bonus_max_periods", max_periods, None)
    await ctx.session.execute(update(BonusRule).where(BonusRule.recipient == "referred").values(is_active=True))
    await ctx.session.commit()


async def _run_months(ctx, clock, pid, months, points=300):
    code = (await current(ctx)).code
    for _ in range(months):
        p = await open_period(ctx, code)
        await add_orders(ctx, pid, points, "econom", ended_at=p.starts_at + timedelta(days=20))
        clock.set(p.ends_at + timedelta(hours=2))
        await close_period(ctx, p)
        code = next_code(code)


async def _sum(ctx, user_id, type_):
    return await ctx.session.scalar(select(func.coalesce(func.sum(Accrual.amount), 0)).where(
        Accrual.user_id == user_id, Accrual.type == type_))


async def test_welcome_disabled_tc57(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await _run_months(ctx, clock, pid, 1)
    assert await _sum(ctx, friend.id, "referred_welcome") == 0


async def test_welcome_first_plan_tc58_tc59(ctx, clock):
    await _enable_welcome(ctx)
    referrer, friend, ref, pid = await counted_referral(ctx)
    await _run_months(ctx, clock, pid, 2)
    assert await _sum(ctx, friend.id, "referred_welcome") == 20000  # только первый раз
    assert await _sum(ctx, referrer.id, "referral") == 60000
    assert "welcome.bonus_paid" in await outbox_keys(ctx, friend.id)


async def test_welcome_every_month_tc60(ctx, clock):
    await _enable_welcome(ctx, max_periods=0)
    referrer, friend, ref, pid = await counted_referral(ctx)
    await _run_months(ctx, clock, pid, 3)
    assert await _sum(ctx, friend.id, "referred_welcome") == 60000


async def test_welcome_without_referrer_tc61(ctx, clock):
    await _enable_welcome(ctx)
    from tests.factories import add_profile, link
    solo = await create_user(ctx)
    p = await add_profile(ctx)
    await link(ctx, solo, p)
    await _run_months(ctx, clock, p.driver_profile_id, 1)
    assert await _sum(ctx, solo.id, "referred_welcome") == 0


async def test_simulator_shows_welcome_cost_tc62_tc97(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await _run_months(ctx, clock, pid, 1)
    rules = [{"recipient": "referrer", "min_percent": 100, "bonus_uzs": 30000, "is_active": True},
             {"recipient": "referred", "min_percent": 100, "bonus_uzs": 20000, "is_active": True}]
    before = await ctx.session.scalar(select(func.count()).select_from(Accrual))
    res = await compare(ctx, "2026-08", {"referred_bonus_enabled": True, "bonus_rules": rules})
    assert res["current"]["welcome_payout"] == 0 and res["draft"]["welcome_payout"] == 20000
    assert res["diff"]["total"] == 20000
    assert await ctx.session.scalar(select(func.count()).select_from(Accrual)) == before  # ничего не сохранено
    lowered = await compare(ctx, "2026-08", {"threshold_points_x100": 20000, "coefficients": {"econom": 100}})
    assert lowered["draft"]["qualified"] == 1


async def _referrer_with_qualified(ctx, n):
    """Реферер с n уникальными друзьями, хотя бы раз выполнившими план."""
    referrer = await create_user(ctx, name="Топ Реферер")
    p = await open_period(ctx, "2026-07")
    for _ in range(n):
        _, friend, ref, pid = await counted_referral(ctx, referrer)
        ctx.session.add(Qualification(referral_id=ref.id, period_id=p.id, threshold_points_x100=30000,
                                      points_x100=30000, achieved_percent=100, is_qualified=True))
    await ctx.session.commit()
    return referrer


async def _activate_milestones(ctx):
    await ctx.session.execute(update(Milestone).values(is_active=True))
    await ctx.session.commit()


async def test_milestones_disabled_tc63_tc64(ctx, clock):
    referrer = await _referrer_with_qualified(ctx, 20)
    await _activate_milestones(ctx)
    aug = await current(ctx)
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    assert await _sum(ctx, referrer.id, "milestone") == 0
    assert (await ctx.session.get(User, referrer.id, populate_existing=True)).qualified_referrals_count == 20


async def test_from_now_mode_tc66(ctx, clock):
    referrer = await _referrer_with_qualified(ctx, 40)
    await _activate_milestones(ctx)
    admin = await create_user(ctx, role="admin")
    res = await enable_milestones(ctx, actor=admin, mode="from_now")
    await ctx.session.commit()
    assert res["granted_without_payment"] == 4 and res["paid"] == 0
    assert await _sum(ctx, referrer.id, "milestone") == 0
    # ещё 10 друзей выполнили план → только награда за 50
    aug = await current(ctx)
    for _ in range(10):
        _, _, _, pid = await counted_referral(ctx, referrer)
        await add_orders(ctx, pid, 300, "econom")
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    accs = (await ctx.session.execute(select(Accrual.amount).where(
        Accrual.user_id == referrer.id, Accrual.type == "milestone"))).scalars().all()
    assert accs == [200000]


async def test_retroactive_only_superadmin_tc67(ctx):
    referrer = await _referrer_with_qualified(ctx, 20)
    await _activate_milestones(ctx)
    admin = await create_user(ctx, role="admin")
    with pytest.raises(PermissionDenied):
        await enable_milestones(ctx, actor=admin, mode="retroactive")
    root = await create_user(ctx, role="superadmin")
    res = await enable_milestones(ctx, actor=root, mode="retroactive")
    await ctx.session.commit()
    assert res["paid"] == 2 and await _sum(ctx, referrer.id, "milestone") == 90000


async def test_friend_counted_once_tc69(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await _run_months(ctx, clock, pid, 6)
    assert (await ctx.session.get(User, referrer.id, populate_existing=True)).qualified_referrals_count == 1


async def test_milestone_with_rewards_cannot_be_deleted_tc70(ctx):
    referrer = await _referrer_with_qualified(ctx, 10)
    await _activate_milestones(ctx)
    root = await create_user(ctx, role="superadmin")
    await enable_milestones(ctx, actor=root, mode="from_now")
    await ctx.session.commit()
    m = (await ctx.session.execute(select(Milestone).where(Milestone.code == "friends_10"))).scalar_one()
    with pytest.raises(BusinessError) as e:
        await delete_milestone(ctx, m.id, root.id)
    assert e.value.key == "err.milestone_in_use"
    m50 = (await ctx.session.execute(select(Milestone).where(Milestone.code == "friends_50"))).scalar_one()
    await delete_milestone(ctx, m50.id, root.id)  # без выданных наград — можно
