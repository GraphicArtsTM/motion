"""Дополнительные ветки ядра: холды, сверка, CRUD правил, ручные действия, условия, атрибуция."""

from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import select

from src.core.billing.accruals import (
    cancel_accrual,
    create_accrual_if_not_exists,
    release_holds,
    sum_accruals,
)
from src.core.billing.bonus_rules import (
    best_rule,
    delete_rule,
    list_rules,
    referrer_bonus_amount,
    upsert_rule,
    welcome_bonus_amount,
)
from src.core.billing.debt import create_correction, write_off_debt
from src.core.billing.milestones import (
    all_milestones,
    disable_milestones,
    enable_milestones,
    upsert_milestone,
    user_milestones,
)
from src.core.billing.reconciliation import reconcile_withdrawals, retry_pending_withdrawals
from src.core.billing.wallet import recalc_user_balances, sha256, wallet_totals
from src.core.billing.withdrawal import (
    approve_withdrawal,
    cancel_withdrawal,
    request_withdrawal,
    retry_withdrawal,
)
from src.core.errors import BusinessError, PermissionDenied
from src.core.onboarding.terms import create_terms_draft, publish_terms, terms_stats, users_not_accepted
from src.core.onboarding.validation import format_phone, mask_phone, short_name, validate_full_name
from src.core.referral.attribution import admin_link_referral, admin_unlink_referral, set_is_counted
from src.core.referral.matching import admin_link_profile, admin_unlink_profile
from src.core.scoring.coefficients import delete_tariff, register_tariff_if_unknown, upsert_tariff
from src.db.models import Accrual, User, Withdrawal
from tests.factories import (
    add_profile,
    assert_wallet_invariants,
    counted_referral,
    create_user,
    current,
    outbox_keys,
    run_queue,
    with_profile,
)


async def _driver(ctx, amount=0, **kw):
    u = await create_user(ctx, **kw)
    await with_profile(ctx, u)
    if amount:
        await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key=sha256(f"x{u.id}{amount}"),
                                           type="manual", amount=amount, status="available")
    await ctx.session.commit()
    return u


async def test_hold_and_release(ctx, clock):
    await ctx.settings.set(ctx.session, "accrual_hold_days", 3, None)
    u = await _driver(ctx)
    acc = await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key="h1", type="manual", amount=5000,
                                             status="hold")
    await ctx.session.commit()
    assert acc.status == "hold" and (await ctx.session.get(User, u.id)).balance_hold == 5000
    assert await release_holds(ctx) == 0
    clock.advance(days=4)
    assert await release_holds(ctx) == 5000
    await assert_wallet_invariants(ctx, u.id)
    # повтор ключа — без дубля
    assert await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key="h1", type="manual",
                                              amount=5000, status="available") is None
    assert await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key="zero", type="manual",
                                              amount=0, status="available") is None


async def test_cancel_accrual_partial_and_hold(ctx):
    u = await _driver(ctx, 10000)
    acc = (await ctx.session.execute(select(Accrual).where(Accrual.user_id == u.id))).scalar_one()
    assert await cancel_accrual(ctx, acc, "test", 4000) == 4000
    held = await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key="hh", type="manual", amount=7000,
                                              status="hold")
    assert await cancel_accrual(ctx, held, "test") == 7000
    assert await cancel_accrual(ctx, held, "again") == 0
    await ctx.session.commit()
    assert await sum_accruals(ctx, user_id=u.id, exclude_status="cancelled") == 6000
    await recalc_user_balances(ctx, u.id)
    await assert_wallet_invariants(ctx, u.id)
    totals = await wallet_totals(ctx, u.id)
    assert totals["available"] == 6000 and totals["total_earned"] == 6000


async def test_balance_mismatch_alert(ctx):
    u = await _driver(ctx, 1000)
    (await ctx.session.get(User, u.id)).balance_available = 5
    await recalc_user_balances(ctx, u.id)
    assert "admin.alert.balance_mismatch" in await outbox_keys(ctx)


async def test_write_off_debt_and_positive_correction(ctx):
    u = await _driver(ctx)
    await create_correction(ctx, user_id=u.id, amount=-10000, reason="c", created_by=None, notify=True)
    assert "wallet.debt_created" in await outbox_keys(ctx, u.id)
    admin = await create_user(ctx, role="admin")
    await write_off_debt(ctx, user_id=u.id, amount=4000, reason="ok", actor_id=admin.id)
    await create_correction(ctx, user_id=u.id, amount=8000, reason="bonus", created_by=admin.id)
    await ctx.session.commit()
    u = await ctx.session.get(User, u.id, populate_existing=True)
    assert (u.debt, u.balance_available) == (0, 2000)
    await assert_wallet_invariants(ctx, u.id)
    with pytest.raises(ValueError):
        await create_correction(ctx, user_id=u.id, amount=0, reason="x", created_by=None)


async def test_manual_mode_approve_flow(ctx, fleet):
    await ctx.settings.set(ctx.session, "withdrawal_mode", "manual", None)
    u = await _driver(ctx, 30000)
    w = await request_withdrawal(ctx, u.id)
    assert w.status == "awaiting_approval" and not w.requires_manual
    assert ctx.queue.pop_all() == []
    fin = await create_user(ctx, role="finance")
    await approve_withdrawal(ctx, w.id, fin.id)
    assert await run_queue(ctx) == ["completed"]
    with pytest.raises(BusinessError):
        await approve_withdrawal(ctx, w.id, fin.id)
    await assert_wallet_invariants(ctx, u.id)


async def test_reconcile_and_retry_jobs(ctx, fleet, clock):
    u = await _driver(ctx, 30000)
    fleet.tx_script.extend(["timeout"])
    w = await request_withdrawal(ctx, u.id)
    calls = ctx.queue.pop_all()
    from src.core.billing.withdrawal import process_withdrawal
    await process_withdrawal(ctx, *calls[0][1])
    ctx.queue.pop_all()
    fleet.unavailable = True
    clock.advance(minutes=15)
    assert await reconcile_withdrawals(ctx) == 1
    assert "admin.alert.withdrawal_verifying_stuck" in await outbox_keys(ctx)
    fleet.unavailable = False
    ctx.queue.pop_all()
    await reconcile_withdrawals(ctx)
    assert (await ctx.session.get(Withdrawal, w.id, populate_existing=True)).status == "completed"
    # зависший pending
    u2 = await _driver(ctx, 30000)
    w2 = await request_withdrawal(ctx, u2.id)
    ctx.queue.pop_all()  # «потеряли» задачу
    clock.advance(minutes=20)
    assert await retry_pending_withdrawals(ctx) == 1
    assert await run_queue(ctx) == ["completed"]
    # зависший processing → сначала сверка
    u3 = await _driver(ctx, 30000)
    w3 = await request_withdrawal(ctx, u3.id)
    ctx.queue.pop_all()
    (await ctx.session.get(Withdrawal, w3.id)).status = "processing"
    await ctx.session.commit()
    clock.advance(minutes=20)
    await retry_pending_withdrawals(ctx)
    assert ctx.queue.calls[0][0] == "verify_withdrawal"
    await run_queue(ctx)
    for uid in (u.id, u2.id, u3.id):
        await assert_wallet_invariants(ctx, uid)


async def test_admin_retry_and_cancel_verifying(ctx, fleet):
    u = await _driver(ctx, 30000)
    fin = await create_user(ctx, role="finance")
    fleet.tx_script.extend(["timeout"])
    w = await request_withdrawal(ctx, u.id)
    from src.core.billing.withdrawal import process_withdrawal
    await process_withdrawal(ctx, *ctx.queue.pop_all()[0][1])
    ctx.queue.pop_all()
    await retry_withdrawal(ctx, w.id, fin.id)
    assert ctx.queue.calls[-1][0] == "verify_withdrawal"
    ctx.queue.pop_all()
    with pytest.raises(BusinessError) as e:
        await cancel_withdrawal(ctx, w.id, fin.id, "ошибка")  # транзакция найдена по метке
    assert e.value.key == "err.withdrawal_already_paid"
    assert (await ctx.session.get(Withdrawal, w.id, populate_existing=True)).status == "completed"
    await assert_wallet_invariants(ctx, u.id)


async def test_bonus_rules_crud(ctx):
    admin = await create_user(ctx, role="admin")
    assert await referrer_bonus_amount(ctx) == 30000 and await welcome_bonus_amount(ctx) == 0
    r = await upsert_rule(ctx, actor_id=admin.id, recipient="referrer", min_percent=200, bonus_uzs=50000)
    await upsert_rule(ctx, actor_id=admin.id, recipient="referrer", min_percent=200, bonus_uzs=55000, rule_id=r.id)
    assert len(await list_rules(ctx)) == 3
    with pytest.raises(BusinessError):
        await upsert_rule(ctx, actor_id=admin.id, recipient="x", min_percent=1, bonus_uzs=1)
    with pytest.raises(BusinessError):
        await upsert_rule(ctx, actor_id=admin.id, recipient="referrer", min_percent=0, bonus_uzs=1)
    await delete_rule(ctx, r.id, admin.id)
    await delete_rule(ctx, 9999, admin.id)
    rules = [{"recipient": "referrer", "min_percent": 100, "bonus_uzs": 1},
             {"recipient": "referrer", "min_percent": 150, "bonus_uzs": 2, "is_active": False}]
    assert best_rule(rules, 170, "referrer")["bonus_uzs"] == 1 and best_rule(rules, 50, "referrer") is None


async def test_bonus_rule_in_use_cannot_be_deleted(ctx):
    admin = await create_user(ctx, role="admin")
    rule = (await list_rules(ctx))[0]
    u = await _driver(ctx)
    await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key="r", type="manual", amount=1,
                                       status="available", bonus_rule_id=rule.id)
    with pytest.raises(BusinessError):
        await delete_rule(ctx, rule.id, admin.id)


async def test_milestones_crud_and_toggle(ctx):
    admin = await create_user(ctx, role="admin")
    m = await upsert_milestone(ctx, actor_id=admin.id, code="friends_5", name="5 друзей", required_count=5,
                               reward_uzs=10000, is_active=True, sort_order=0)
    await upsert_milestone(ctx, actor_id=admin.id, code="friends_5", name="5 друзей!", required_count=5,
                           reward_uzs=12000, is_active=True, sort_order=0)
    assert len(await all_milestones(ctx)) == 6 and m.reward_uzs == 12000
    with pytest.raises(BusinessError):
        await upsert_milestone(ctx, actor_id=admin.id, code="bad", name="x", required_count=0, reward_uzs=1,
                               is_active=True, sort_order=1)
    await enable_milestones(ctx, actor=admin, mode="from_now")
    with pytest.raises(BusinessError):
        await enable_milestones(ctx, actor=admin, mode="from_now")
    await disable_milestones(ctx, actor=admin)
    assert not ctx.settings.bool("milestones_enabled")
    with pytest.raises(BusinessError):
        await enable_milestones(ctx, actor=admin, mode="weird")
    assert await user_milestones(ctx, admin.id) == {}


async def test_tariff_crud(ctx, clock):
    from src.core.billing.periods import close_period
    admin = await create_user(ctx, role="admin")
    t = await upsert_tariff(ctx, code="night", actor_id=admin.id, name="Ночной", coefficient_x100=120)
    assert t.is_active
    with pytest.raises(BusinessError):
        await upsert_tariff(ctx, code="night", actor_id=admin.id, coefficient_x100=0)
    await delete_tariff(ctx, "night", admin.id)
    aug = await current(ctx)
    clock.set(aug.ends_at + timedelta(hours=2))
    await close_period(ctx, aug)
    with pytest.raises(BusinessError):
        await delete_tariff(ctx, "cargo", admin.id)
    assert await register_tariff_if_unknown(ctx, None) is False
    assert await register_tariff_if_unknown(ctx, "cargo") is False


async def test_terms_admin(ctx):
    admin = await create_user(ctx, role="admin")
    lazy = await create_user(ctx, accept_terms=False)
    with pytest.raises(BusinessError):
        await create_terms_draft(ctx, actor_id=admin.id, text_ru="x", text_uz_latn="", text_uz_cyrl="y")
    draft = await create_terms_draft(ctx, actor_id=admin.id, text_ru="a", text_uz_latn="b", text_uz_cyrl="c")
    assert draft.version == 2
    await publish_terms(ctx, draft.id, admin.id)
    with pytest.raises(BusinessError):
        await publish_terms(ctx, draft.id, admin.id)
    with pytest.raises(BusinessError):
        await publish_terms(ctx, 999, admin.id)
    stats = await terms_stats(ctx)
    assert stats["version"] == 2 and stats["accepted"] == 0
    assert lazy.id in {u.id for u in await users_not_accepted(ctx)}


def test_validation_helpers():
    assert validate_full_name("Каримов Азиз") == "Каримов Азиз"
    assert validate_full_name("Азиз") is None
    assert validate_full_name("A B C D") is None
    assert validate_full_name("Иван 2Петров") is None
    assert validate_full_name(None) is None
    assert format_phone("+998901234567") == "+998 90 123 45 67"
    assert mask_phone("+998911234589") == "+998 91 *** ** 89"
    assert short_name("Каримов Азиз Бахтиёрович") == "Каримов А." and short_name(None) == ""


async def test_admin_referral_link_unlink(ctx):
    admin = await create_user(ctx, role="moderator")
    referrer = await create_user(ctx)
    friend = await create_user(ctx)
    await add_profile(ctx, phone=friend.phone)
    ref = await admin_link_referral(ctx, referred_user_id=friend.id, referrer_code=referrer.referral_code,
                                    actor_id=admin.id, counted=True)
    assert ref.status == "hired" and ref.is_counted
    with pytest.raises(BusinessError):
        await admin_link_referral(ctx, referred_user_id=friend.id, referrer_code=referrer.referral_code,
                                  actor_id=admin.id, counted=True)
    with pytest.raises(BusinessError):
        await admin_link_referral(ctx, referred_user_id=friend.id, referrer_code="NOPE99", actor_id=admin.id,
                                  counted=True)
    await admin_unlink_referral(ctx, ref.id, admin.id)
    assert not ref.is_counted and ref.status == "rejected"
    await set_is_counted(ctx, ref.id, True, admin.id)
    assert ref.is_counted and ref.status == "hired"
    with pytest.raises(BusinessError):
        await set_is_counted(ctx, 999, True, admin.id)


async def test_admin_profile_link(ctx):
    admin = await create_user(ctx, role="moderator")
    referrer, friend, ref, pid = await counted_referral(ctx)
    await admin_unlink_profile(ctx, friend.id, admin.id)
    await ctx.session.flush()
    ref.status = "registered"
    await admin_link_profile(ctx, friend.id, pid, admin.id)
    assert ref.status == "hired"
    other = await create_user(ctx)
    with pytest.raises(BusinessError):
        await admin_link_profile(ctx, other.id, pid, admin.id)  # профиль уже привязан
    with pytest.raises(BusinessError):
        await admin_link_profile(ctx, other.id, "nope", admin.id)
    await admin_unlink_profile(ctx, other.id, admin.id)


async def test_admin_roles_enforced(ctx):
    from src.core.admin.users import manual_adjustment, set_role
    op = await create_user(ctx, role="operator")
    u = await _driver(ctx)
    with pytest.raises(PermissionDenied):
        await manual_adjustment(ctx, op, u.id, 1000, "x")
    with pytest.raises(PermissionDenied):
        await set_role(ctx, op, u.id, "admin")
    ro = await create_user(ctx, role="readonly")
    from src.core.admin.roles import has_role
    assert has_role("readonly", "operator") and not has_role("readonly", "operator", write=True)
