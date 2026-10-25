"""TC-71…TC-86: кошелёк, долг, вывод и сверка. R15 — деньги не пропадают."""

from __future__ import annotations

import asyncio

import pytest
from sqlalchemy import func, select

from src.core.billing.accruals import create_accrual_if_not_exists, initial_accrual_status
from src.core.billing.debt import create_correction
from src.core.billing.wallet import sha256
from src.core.billing.withdrawal import (
    cancel_withdrawal,
    mark_paid_manually,
    request_withdrawal,
)
from src.core.context import RecordingQueue, make_ctx
from src.core.errors import BusinessError
from src.core.onboarding.registration import flag_fraud
from src.db.models import Accrual, User, Withdrawal
from tests.factories import (
    assert_wallet_invariants,
    counted_referral,
    create_user,
    outbox_keys,
    run_queue,
    with_profile,
)


async def credit(ctx, user, amount, n=1):
    for i in range(n):
        await create_accrual_if_not_exists(ctx, user_id=user.id, idempotency_key=sha256(f"t:{user.id}:{amount}:{i}:{n}"),
                                           type="manual", amount=amount, status="available")
    await ctx.session.commit()


async def fresh(ctx, user_id) -> User:
    return await ctx.session.get(User, user_id, populate_existing=True)


async def driver(ctx, **kw):
    u = await create_user(ctx, **kw)
    await with_profile(ctx, u)
    await ctx.session.commit()
    return u


async def test_accrual_available_immediately_tc71(ctx):
    assert await initial_accrual_status(ctx) == "available"


async def test_open_fraud_flag_holds_tc72(ctx):
    referrer, friend, ref, pid = await counted_referral(ctx)
    await flag_fraud(ctx, rule="SAME_CAR", referral=ref)
    assert await initial_accrual_status(ctx, ref.id) == "hold"


async def test_negative_correction_creates_debt_tc73(ctx):
    u = await driver(ctx)
    await credit(ctx, u, 10000)
    await create_correction(ctx, user_id=u.id, amount=-25000, reason="clawback", created_by=None)
    await ctx.session.commit()
    u = await fresh(ctx, u.id)
    assert (u.balance_available, u.debt) == (0, 15000)
    await assert_wallet_invariants(ctx, u.id)


async def test_debt_blocks_withdrawal_tc74(ctx):
    u = await driver(ctx)
    await credit(ctx, u, 10000)
    await create_correction(ctx, user_id=u.id, amount=-25000, reason="clawback", created_by=None)
    await ctx.session.commit()
    with pytest.raises(BusinessError) as e:
        await request_withdrawal(ctx, u.id)
    assert e.value.key == "err.has_debt" and e.value.params["amount"] == {"__money__": 15000}


async def test_new_accrual_pays_debt_first_tc75(ctx):
    u = await driver(ctx)
    await create_correction(ctx, user_id=u.id, amount=-12000, reason="clawback", created_by=None)
    await credit(ctx, u, 30000)
    u = await fresh(ctx, u.id)
    assert (u.debt, u.balance_available) == (0, 18000)
    await assert_wallet_invariants(ctx, u.id)


async def test_withdraw_reserves_accruals_tc76_tc77(ctx, fleet):
    u = await driver(ctx)
    await credit(ctx, u, 30000, n=14)
    w = await request_withdrawal(ctx, u.id)
    assert w.amount == 420000
    u = await fresh(ctx, u.id)
    assert u.balance_available == 0
    statuses = set((await ctx.session.execute(select(Accrual.status).where(Accrual.user_id == u.id))).scalars())
    assert statuses == {"reserved"}
    assert await run_queue(ctx) == ["completed"]
    w = await ctx.session.get(Withdrawal, w.id, populate_existing=True)
    assert w.status == "completed" and w.external_transaction_id == fleet.transactions[0].id
    assert fleet.transactions[0].amount == 420000 and w.marker in fleet.transactions[0].description
    await assert_wallet_invariants(ctx, u.id)


async def test_custom_amount_splits_fifo(ctx):
    u = await driver(ctx)
    await credit(ctx, u, 30000, n=2)
    await request_withdrawal(ctx, u.id, 45000)
    await run_queue(ctx)
    u = await fresh(ctx, u.id)
    assert u.balance_available == 15000
    await assert_wallet_invariants(ctx, u.id)


async def test_timeout_goes_verifying_no_blind_retry_tc78_tc79(ctx, fleet):
    u = await driver(ctx)
    await credit(ctx, u, 30000)
    fleet.tx_script.extend(["timeout"])
    w = await request_withdrawal(ctx, u.id)
    calls = ctx.queue.pop_all()
    from src.core.billing.withdrawal import process_withdrawal, verify_withdrawal
    assert await process_withdrawal(ctx, *calls[0][1]) == "verifying"
    nxt = ctx.queue.pop_all()
    assert [c[0] for c in nxt] == ["verify_withdrawal"]  # TC-78: не process_withdrawal
    assert len(fleet.transactions) == 1  # транзакция прошла, но ответ потерян
    assert await verify_withdrawal(ctx, *nxt[0][1]) == "completed"  # TC-79/80
    assert len(fleet.transactions) == 1  # двойной выплаты нет
    await assert_wallet_invariants(ctx, u.id)


async def test_verify_by_marker_tc80(ctx, fleet):
    u = await driver(ctx)
    await credit(ctx, u, 30000)
    fleet.tx_script.extend(["timeout"])
    fleet.status_lookup_supported = False
    w = await request_withdrawal(ctx, u.id)
    assert await run_queue(ctx) == ["verifying", "completed"]
    w = await ctx.session.get(Withdrawal, w.id, populate_existing=True)
    assert w.external_transaction_id == fleet.transactions[0].id


async def test_verify_not_found_allows_retry_tc81(ctx, fleet):
    u = await driver(ctx)
    await credit(ctx, u, 30000)
    fleet.tx_script.extend(["timeout"])
    fleet.lose_tx_on_timeout = True
    await request_withdrawal(ctx, u.id)
    assert await run_queue(ctx) == ["verifying", "pending", "completed"]
    assert len(fleet.transactions) == 1
    await assert_wallet_invariants(ctx, u.id)


async def test_500_five_times_fails_and_refunds_tc82(ctx, fleet):
    u = await driver(ctx)
    await credit(ctx, u, 30000)
    fleet.tx_script.extend(["500"] * 6)
    await request_withdrawal(ctx, u.id)
    results = await run_queue(ctx)
    assert results == ["pending"] * 5 + ["failed"]
    u = await fresh(ctx, u.id)
    assert u.balance_available == 30000
    assert "admin.alert.withdrawal_failed" in await outbox_keys(ctx)
    assert "wallet.failed" in await outbox_keys(ctx, u.id)
    await assert_wallet_invariants(ctx, u.id)


async def test_400_fails_immediately_tc83(ctx, fleet):
    u = await driver(ctx)
    await credit(ctx, u, 30000)
    fleet.tx_script.extend(["400"])
    await request_withdrawal(ctx, u.id)
    assert await run_queue(ctx) == ["failed"]
    assert (await fresh(ctx, u.id)).balance_available == 30000
    await assert_wallet_invariants(ctx, u.id)


async def test_double_press_one_withdrawal_tc84(sessionmaker, clock, fleet):
    async with sessionmaker() as s:
        ctx = await make_ctx(s, clock=clock, fleet=fleet, queue=RecordingQueue())
        u = await driver(ctx)
        await credit(ctx, u, 30000)
        uid = u.id

    async def press():
        async with sessionmaker() as s:
            c = await make_ctx(s, clock=clock, fleet=fleet, queue=RecordingQueue())
            try:
                return await request_withdrawal(c, uid)
            except BusinessError as e:
                return e.key

    results = await asyncio.gather(press(), press())
    async with sessionmaker() as s:
        n = await s.scalar(select(func.count()).select_from(Withdrawal).where(Withdrawal.user_id == uid))
        assert n == 1
        assert sum(isinstance(r, Withdrawal) for r in results) == 1
        ctx = await make_ctx(s, clock=clock, fleet=fleet)
        await assert_wallet_invariants(ctx, uid)


async def test_fired_driver_goes_manual_tc85(ctx, fleet):
    u = await create_user(ctx)
    await with_profile(ctx, u, work_status="fired")
    await credit(ctx, u, 30000)
    w = await request_withdrawal(ctx, u.id)
    assert w.status == "awaiting_approval" and w.requires_manual
    assert ctx.queue.pop_all() == []  # в Fleet не отправляется
    assert "wallet.manual_review" in await outbox_keys(ctx, u.id)
    assert "admin.withdrawal_approval" in await outbox_keys(ctx)
    admin = await create_user(ctx, role="finance")
    await mark_paid_manually(ctx, w.id, admin.id, proof_file_id="file-proof", reference="CASH-1")
    w = await ctx.session.get(Withdrawal, w.id, populate_existing=True)
    assert w.status == "completed" and w.proof_file_id == "file-proof"
    await assert_wallet_invariants(ctx, u.id)


async def test_cancel_refunds(ctx):
    await ctx.settings.set(ctx.session, "withdrawal_mode", "manual", None)
    u = await driver(ctx)
    await credit(ctx, u, 30000)
    w = await request_withdrawal(ctx, u.id)
    admin = await create_user(ctx, role="finance")
    await cancel_withdrawal(ctx, w.id, admin.id, "по просьбе водителя")
    assert (await fresh(ctx, u.id)).balance_available == 30000
    await assert_wallet_invariants(ctx, u.id)


async def test_antiflood_and_limits(ctx, clock, fleet):
    u = await driver(ctx)
    await credit(ctx, u, 30000)
    fleet.tx_script.extend(["400"])
    await request_withdrawal(ctx, u.id, 10000)
    await run_queue(ctx)
    with pytest.raises(BusinessError) as e:
        await request_withdrawal(ctx, u.id, 10000)
    assert e.value.key == "err.too_fast"
    clock.advance(seconds=31)
    for key, value, err in (("min_withdrawal_amount", 20000, "err.amount_too_small"),
                            ("withdrawal_enabled", False, "err.withdrawal_disabled")):
        await ctx.settings.set(ctx.session, key, value, None)
        with pytest.raises(BusinessError) as e:
            await request_withdrawal(ctx, u.id, 10000)
        assert e.value.key == err
    await ctx.settings.set(ctx.session, "withdrawal_enabled", True, None)
    await ctx.settings.set(ctx.session, "min_withdrawal_amount", 0, None)
    with pytest.raises(BusinessError) as e:
        await request_withdrawal(ctx, u.id, 40000)
    assert e.value.key == "err.insufficient_funds"


async def test_not_approved_and_no_terms(ctx):
    u = await create_user(ctx, access_status="pending_approval")
    await with_profile(ctx, u)
    with pytest.raises(BusinessError) as e:
        await request_withdrawal(ctx, u.id)
    assert e.value.key == "err.account_not_approved"
    u2 = await create_user(ctx, accept_terms=False)
    with pytest.raises(BusinessError) as e:
        await request_withdrawal(ctx, u2.id)
    assert e.value.key == "err.terms_not_accepted"


@pytest.mark.parametrize("script", [["ok"], ["timeout"], ["500", "ok"], ["400"], ["429", "timeout", "ok"],
                                    ["connect", "connect", "connect", "connect", "connect", "connect"]])
async def test_money_never_lost_tc86(ctx, fleet, script):
    u = await driver(ctx)
    await credit(ctx, u, 30000, n=3)
    fleet.tx_script.extend(script)
    await request_withdrawal(ctx, u.id, 50000)
    await run_queue(ctx)
    u = await fresh(ctx, u.id)
    w = (await ctx.session.execute(select(Withdrawal))).scalar_one()
    paid = sum(t.amount for t in fleet.transactions)
    assert paid in (0, 50000) and len(fleet.transactions) <= 1  # не дважды
    assert u.balance_available + paid == 90000  # не пропали
    assert (w.status == "completed") == (paid == 50000)
    await assert_wallet_invariants(ctx, u.id)
