"""TC-87…TC-94, TC-95, TC-99, TC-101, TC-108: экраны, уведомления, админка."""

from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import func, select

from src.core.admin.broadcasts import create_broadcast, refresh_stats, start_broadcast
from src.core.admin.dashboard import channels_report, dashboard
from src.core.admin.settings_admin import update_setting
from src.core.errors import BusinessError
from src.core.notifications.progress import (
    deadline_reminders,
    inactive_friend_alert,
    progress_notifications,
    remind_friend,
)
from src.core.progress.display import display_progress, friends_list, my_progress
from src.core.scoring.coefficients import tariff_table, upsert_tariff
from src.core.scoring.points import TariffPoints
from src.core.support.tickets import create_dispute
from src.db.models import NotificationOutbox, Referral, SettingsHistory, SupportTicket
from tests.factories import add_orders, counted_referral, create_user, current, outbox_keys, tashkent


async def test_my_progress_tc87_tc88(ctx):
    referrer, friend, ref, pid = await counted_referral(ctx, friend_name="Каримов Азиз")
    await add_orders(ctx, pid, 87, "cargo")
    p = await my_progress(ctx, friend)
    assert p.display == {"mode": "orders", "done": 87, "target": 100, "tariff": "cargo", "left": 13}
    assert p.points_x100 == 26100 and p.threshold_x100 == 30000
    assert p.friend_note == {"name": "Рустам", "bonus": 30000}  # «Рефереров Рустам»
    solo = await create_user(ctx)
    assert (await my_progress(ctx, solo)).friend_note is None


def _bp(tariff, orders, coef):
    return TariffPoints(tariff, orders, coef, orders * coef)


def test_display_modes_tc89():
    assert display_progress([_bp("cargo", 87, 300)], 30000, 90)["target"] == 100
    d = display_progress([_bp("econom", 190, 100)], 30000, 90)
    assert (d["mode"], d["done"], d["target"]) == ("orders", 190, 300)
    mixed = display_progress([_bp("cargo", 60, 300), _bp("econom", 38, 100)], 30000, 90)
    assert (mixed["mode"], mixed["done"], mixed["target"]) == ("points", 218, 300)


async def test_fired_friend_marked_tc90(ctx):
    referrer, friend, ref, pid = await counted_referral(ctx)
    from src.db.models import ParkDriverProfile
    (await ctx.session.get(ParkDriverProfile, pid)).work_status = "fired"
    await ctx.session.flush()
    rows, total = await friends_list(ctx, referrer, "fired")
    assert total == 1 and rows[0].fired


async def test_dispute_ticket_with_details_tc91(ctx):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await add_orders(ctx, pid, 50, "cargo")
    await current(ctx)
    t = await create_dispute(ctx, referrer, "не согласен")
    t = await ctx.session.get(SupportTicket, t.id)
    assert t.kind == "dispute"
    period = t.context["periods"][0]
    assert period["coefficients"]["cargo"] == 300
    assert period["friends"][0]["points_x100"] == 15000
    assert period["friends"][0]["breakdown"][0]["tariff_class"] == "cargo"
    assert "admin.support_dispute" in await outbox_keys(ctx)


async def test_deadline_beats_threshold_tc92_tc93(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    clock.set(tashkent(2026, 8, 28, 10))
    await add_orders(ctx, pid, 275, "econom")  # 91%, 4 дня до конца
    await progress_notifications(ctx)
    await deadline_reminders(ctx)
    keys = await outbox_keys(ctx, referrer.id)
    assert "friends.deadline" in keys and "friends.progress_threshold" not in keys
    assert "progress.deadline_self" in await outbox_keys(ctx, friend.id)
    await deadline_reminders(ctx)
    assert (await outbox_keys(ctx, referrer.id)).count("friends.deadline") == 1


async def test_threshold_once_per_day_tc93(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await add_orders(ctx, pid, 160, "econom")  # 53%
    await progress_notifications(ctx)
    await add_orders(ctx, pid, 85, "econom")   # 81% в тот же день
    await progress_notifications(ctx)
    assert (await outbox_keys(ctx, referrer.id)).count("friends.progress_threshold") == 1
    clock.advance(days=1)
    await progress_notifications(ctx)
    assert (await outbox_keys(ctx, referrer.id)).count("friends.progress_threshold") == 2
    clock.advance(days=1)
    await progress_notifications(ctx)  # тот же порог 80% повторно не шлём
    assert (await outbox_keys(ctx, referrer.id)).count("friends.progress_threshold") == 2


async def test_inactive_friend_tc94(ctx, clock):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await add_orders(ctx, pid, 5, "econom", ended_at=clock.now() - timedelta(days=8), days=1)
    assert await inactive_friend_alert(ctx) == 1
    assert await inactive_friend_alert(ctx) == 0
    item = (await ctx.session.execute(select(NotificationOutbox).where(
        NotificationOutbox.template_key == "referral.friend_inactive"))).scalar_one()
    assert item.buttons[0][0]["callback"] == f"remind:{ref.id}"
    await remind_friend(ctx, referrer, ref.id)
    assert "reminder.from_friend" in await outbox_keys(ctx, friend.id)
    with pytest.raises(BusinessError):
        await remind_friend(ctx, referrer, ref.id)


async def test_orders_to_plan_recomputed_tc95_tc99(ctx):
    admin = await create_user(ctx, role="admin")
    table = {r["code"]: r["orders_to_plan"] for r in await tariff_table(ctx)}
    assert table["cargo"] == 100 and table["delivery"] == 429
    await upsert_tariff(ctx, code="cargo", actor_id=admin.id, coefficient_x100=250)
    table = {r["code"]: r["orders_to_plan"] for r in await tariff_table(ctx)}
    assert table["cargo"] == 120
    h = (await ctx.session.execute(select(SettingsHistory).where(SettingsHistory.entity == "tariff"))).scalar_one()
    assert h.changed_by == admin.id and h.effective_from.isoformat() == "2026-09-01"


async def test_threshold_change_next_period_tc96(ctx, clock):
    admin = await create_user(ctx, role="admin")
    aug = await current(ctx)
    await update_setting(ctx, admin, "qualification_threshold_points_x100", 25000)
    await ctx.session.commit()
    assert aug.threshold_points_x100 == 30000
    from src.core.billing.periods import open_period
    sep = await open_period(ctx, "2026-09")
    assert sep.threshold_points_x100 == 25000


async def test_welcome_toggle_requires_simulation(ctx):
    admin = await create_user(ctx, role="admin")
    with pytest.raises(BusinessError):
        await update_setting(ctx, admin, "referred_bonus_enabled", True)
    await update_setting(ctx, admin, "referred_bonus_enabled", True, simulated=True)


async def test_channels_dashboard_tc101(ctx):
    referrer = await create_user(ctx)
    for tag, counted in (("wa", True), ("wa", False), ("qr", True)):
        friend = await create_user(ctx, access_status="onboarding")
        ctx.session.add(Referral(referrer_user_id=referrer.id, referred_user_id=friend.id,
                                 referral_code=referrer.referral_code, source_tag=tag, is_counted=counted,
                                 registered_at=ctx.now(), status="hired" if counted else "rejected"))
    await ctx.session.flush()
    rows = {r["source_tag"]: r for r in await channels_report(ctx)}
    assert rows["wa"]["clicked"] == 2 and rows["wa"]["approved"] == 1
    assert rows["wa"]["conversion"]["registered->approved"] == 50
    d = await dashboard(ctx)
    assert d["funnel"]["clicked"] == 3 and {c["source_tag"] for c in d["channels"]} == {"wa", "qr"}


async def test_broadcast_5000_tc108(ctx):
    admin = await create_user(ctx, role="admin")
    from src.db.models import User
    ctx.session.add_all([User(telegram_id=900000 + i, referral_code=f"BC{i:05d}", access_status="approved")
                         for i in range(5000)])
    await ctx.session.flush()
    b = await create_broadcast(ctx, admin, title="Акция", text_="Текст", segment={"access_status": "approved"})
    total = await start_broadcast(ctx, b.id, admin.id)
    assert total == 5001
    from sqlalchemy import update
    await ctx.session.execute(update(NotificationOutbox).where(NotificationOutbox.template_key == "broadcast.raw",
                                                                NotificationOutbox.id % 100 == 0).values(status="blocked"))
    await ctx.session.execute(update(NotificationOutbox).where(NotificationOutbox.template_key == "broadcast.raw",
                                                                NotificationOutbox.status == "queued").values(status="sent"))
    stats = await refresh_stats(ctx, b.id)
    assert stats["sent"] + stats["blocked"] == 5001 and stats["blocked"] == 50 and stats["queued"] == 0
