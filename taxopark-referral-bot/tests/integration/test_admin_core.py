"""Админские действия ядра (8.3)."""

from __future__ import annotations

import pytest

from src.core.admin.reports import REPORTS
from src.core.admin.users import (
    add_note,
    delete_personal_data,
    forgive_debt,
    log_photo_view,
    manual_adjustment,
    search_users,
    send_personal_message,
    set_access_status,
    set_payout_blocked,
    set_role,
    user_card,
)
from src.core.errors import BusinessError
from src.db.models import AuditLog
from tests.factories import counted_referral, create_user, outbox_keys, with_profile


async def test_user_card_and_search(ctx):
    referrer, friend, ref, pid = await counted_referral(ctx)
    assert [u.id for u in await search_users(ctx, friend.phone)] == [friend.id]
    assert friend.id in [u.id for u in await search_users(ctx, pid)]
    assert referrer.id in [u.id for u in await search_users(ctx, referrer.referral_code.lower())]
    card = await user_card(ctx, referrer.id)
    assert card["referrals"][0]["id"] == ref.id and card["wallet"]["available"] == 0
    fcard = await user_card(ctx, friend.id)
    assert fcard["profile"]["driver_profile_id"] == pid and fcard["invited_by"]["referral_id"] == ref.id


async def test_admin_actions_audited(ctx):
    admin = await create_user(ctx, role="admin")
    root = await create_user(ctx, role="superadmin")
    u = await create_user(ctx)
    await with_profile(ctx, u)
    await set_access_status(ctx, admin, u.id, "blocked", "spam")
    assert "account.blocked" in await outbox_keys(ctx, u.id)
    await set_access_status(ctx, admin, u.id, "approved")
    with pytest.raises(BusinessError):
        await set_access_status(ctx, admin, u.id, "weird")
    await set_payout_blocked(ctx, admin, u.id, True, "проверка")
    await manual_adjustment(ctx, admin, u.id, 5000, "конкурс")
    with pytest.raises(BusinessError):
        await manual_adjustment(ctx, admin, u.id, 5000, " ")
    await manual_adjustment(ctx, admin, u.id, -8000, "clawback")
    await forgive_debt(ctx, admin, u.id, 3000, "прощено")
    await add_note(ctx, admin, u.id, "звонил")
    await send_personal_message(ctx, admin, u.id, "привет")
    await set_role(ctx, root, u.id, "operator")
    with pytest.raises(BusinessError):
        await set_role(ctx, root, u.id, "god")
    front, back = await log_photo_view(ctx, admin, u.id)
    await delete_personal_data(ctx, admin, u.id)
    await ctx.session.flush()
    actions = {a.action for a in (await ctx.session.execute(__import__("sqlalchemy").select(AuditLog))).scalars()}
    assert {"access_status_changed", "payout_blocked_changed", "manual_adjustment", "debt_written_off",
            "role_changed", "license_photo_viewed", "personal_data_deleted"} <= actions


@pytest.mark.parametrize("name", sorted(REPORTS))
async def test_reports_build(ctx, name):
    await counted_referral(ctx)
    head, rows = await REPORTS[name](ctx)
    assert head and isinstance(rows, list)


async def test_release_budget_hold(ctx):
    from src.core.admin.users import release_accrual_by_admin
    from src.core.billing.accruals import create_accrual_if_not_exists
    from tests.factories import assert_wallet_invariants
    fin = await create_user(ctx, role="finance")
    u = await create_user(ctx)
    acc = await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key="bh", type="referral", amount=30000,
                                             status="hold")
    assert await release_accrual_by_admin(ctx, fin, acc.id) == 30000
    with pytest.raises(BusinessError):
        await release_accrual_by_admin(ctx, fin, acc.id)
    await ctx.session.commit()
    await assert_wallet_invariants(ctx, u.id)
