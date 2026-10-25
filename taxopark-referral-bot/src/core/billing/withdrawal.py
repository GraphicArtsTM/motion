"""Вывод средств: запрос (A10), исполнение со сверкой (A11), ручные выплаты (E6).

Гарантия R15: деньги не пропадают и не уходят дважды. idempotency_token сохраняется
в БД до вызова API; при неизвестном исходе сначала выясняем результат (статус
транзакции → поиск по метке REFBOT-W{id}), и только потом повторяем.
"""

from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy import exists, func, select
from sqlalchemy.exc import IntegrityError

from src.core.admin.audit import audit_log
from src.core.billing.wallet import consume_available, lock_user, settle_debt_from_balance, write_ledger
from src.core.context import Ctx
from src.core.errors import BusinessError, require
from src.core.notifications.service import alert_admins, button, money, notify_admins, notify_user
from src.core.onboarding.terms import has_accepted_current_terms
from src.db import seeds
from src.db.models import Accrual, Driver, User, Withdrawal
from src.integrations.fleet.errors import (
    FleetError,
    NonRetryableFleetError,
    RetryableFleetError,
    UnknownOutcomeError,
)

ACTIVE_STATUSES = ("pending", "awaiting_approval", "processing", "verifying")


async def get_withdrawal(ctx: Ctx, withdrawal_id: int, *, for_update: bool = False) -> Withdrawal:
    q = select(Withdrawal).where(Withdrawal.id == withdrawal_id).execution_options(populate_existing=True)
    if for_update:
        q = q.with_for_update()
    return (await ctx.session.execute(q)).scalar_one()


async def has_active_withdrawal(ctx: Ctx, user_id: int) -> bool:
    return bool(await ctx.session.scalar(select(exists().where(
        Withdrawal.user_id == user_id, Withdrawal.status.in_(ACTIVE_STATUSES)))))


async def _seconds_since_last_request(ctx: Ctx, user_id: int) -> float:
    last = await ctx.session.scalar(select(func.max(Withdrawal.requested_at)).where(Withdrawal.user_id == user_id))
    return float("inf") if last is None else (ctx.now() - last).total_seconds()


async def withdrawal_block_reason(ctx: Ctx, user: User) -> BusinessError | None:
    """Проверки, не зависящие от суммы — для экрана кошелька."""
    s = ctx.settings
    checks: list[tuple[bool, str, dict[str, object]]] = [
        (s.bool("withdrawal_enabled"), "err.withdrawal_disabled", {}),
        (user.access_status == "approved", "err.account_not_approved", {}),
        (await has_accepted_current_terms(ctx, user.id), "err.terms_not_accepted", {}),
        (not user.payout_blocked, "err.payout_blocked", {}),
        (user.debt == 0, "err.has_debt", {"amount": money(user.debt)}),
    ]
    for ok, key, params in checks:
        if not ok:
            return BusinessError(key, **params)
    return None


async def _create_withdrawal(ctx: Ctx, user_id: int, amount: int | None) -> tuple[Withdrawal, User, bool]:
    s = ctx.settings
    user = await lock_user(ctx, user_id)  # R4
    blocked = await withdrawal_block_reason(ctx, user)
    if blocked:
        raise blocked

    driver = (await ctx.session.execute(select(Driver).where(Driver.user_id == user_id))).scalar_one_or_none()
    require(driver is not None and driver.driver_profile_id, "err.no_driver_profile")
    assert driver is not None
    require(not await has_active_withdrawal(ctx, user_id), "err.withdrawal_in_progress")

    amount = amount or user.balance_available
    require(amount > 0, "err.nothing_to_withdraw")
    require(amount >= s.int("min_withdrawal_amount"), "err.amount_too_small",
            amount=money(s.int("min_withdrawal_amount")))
    max_amount = s.int("max_withdrawal_amount")
    require(not max_amount or amount <= max_amount, "err.amount_too_large", amount=money(max_amount))
    require(amount <= user.balance_available, "err.insufficient_funds")
    since_last = await _seconds_since_last_request(ctx, user_id)
    require(since_last >= seeds.ANTIFLOOD_SECONDS, "err.too_fast")
    cooldown = s.int("withdrawal_cooldown_hours")
    require(not cooldown or since_last >= cooldown * 3600, "err.cooldown", hours=cooldown)
    per_day = s.int("max_withdrawals_per_day")
    if per_day:
        today = await ctx.session.scalar(select(func.count()).where(
            Withdrawal.user_id == user_id, Withdrawal.requested_at >= ctx.now() - timedelta(days=1),
            Withdrawal.status != "cancelled"))
        require((today or 0) < per_day, "err.daily_limit")

    # ── E6: уволенный НЕ теряет деньги ──────────────
    profile_status = driver.work_status
    if profile_status is None:
        from src.db.models import ParkDriverProfile
        profile_status = await ctx.session.scalar(select(ParkDriverProfile.work_status).where(
            ParkDriverProfile.driver_profile_id == driver.driver_profile_id))
    fired = profile_status == "fired"
    manual_provider = s.str("fleet_provider") in ("csv", "manual")
    mode = "manual" if manual_provider else s.str("withdrawal_mode")
    status = "awaiting_approval" if (fired or mode == "manual") else "pending"

    w = Withdrawal(user_id=user_id, driver_profile_id=driver.driver_profile_id, amount=amount, status=status,
                   requires_manual=fired or manual_provider, idempotency_token=uuid.uuid4(),
                   requested_at=ctx.now())
    ctx.session.add(w)
    await ctx.session.flush()  # частичный уникальный индекс отсекает второй активный вывод
    w.marker = f"REFBOT-W{w.id}"

    reserved = await consume_available(ctx, user, amount, "reserved", withdrawal_id=w.id)  # FIFO
    assert reserved == amount, "reserved amount must match requested amount"
    user.balance_available -= amount
    await write_ledger(ctx, user, "withdrawal_reserve", -amount, "withdrawal", w.id)
    return w, user, fired


async def request_withdrawal(ctx: Ctx, user_id: int, amount: int | None = None) -> Withdrawal:
    """A10."""
    try:
        # SAVEPOINT: при отказе откатывается только операция вывода (и её FOR UPDATE),
        # объекты вызывающего кода не «протухают».
        async with ctx.session.begin_nested():
            w, user, fired = await _create_withdrawal(ctx, user_id, amount)
    except IntegrityError as e:
        raise BusinessError("err.withdrawal_in_progress") from e
    await ctx.session.commit()

    if w.status == "pending":
        await ctx.queue.enqueue("process_withdrawal", w.id, 0)
    else:
        await notify_admins(ctx, "admin.withdrawal_approval", withdrawal_id=w.id, user_id=user_id,
                            name=user.full_name, amount=money(w.amount), fired=fired,
                            buttons=_admin_withdrawal_buttons(w))
        await notify_user(ctx, user_id, "wallet.manual_review" if fired else "wallet.awaiting_approval",
                          amount=money(w.amount))
        await ctx.session.commit()
    return w


def _admin_withdrawal_buttons(w: Withdrawal) -> list[list[dict[str, object]]]:
    if w.requires_manual:
        return [[button("admin.btn.paid_manually", f"wd:paid:{w.id}")],
                [button("admin.btn.cancel_refund", f"wd:cancel:{w.id}")]]
    return [[button("admin.btn.approve_payout", f"wd:approve:{w.id}")],
            [button("admin.btn.cancel_refund", f"wd:cancel:{w.id}")]]


# ── A11: исполнение ──────────────────────────────────────────────────────────
def retry_delays(ctx: Ctx) -> list[int]:
    return [int(x) for x in ctx.settings.list("withdrawal_retry_delays_seconds")]


async def process_withdrawal(ctx: Ctx, withdrawal_id: int, attempt: int = 0) -> str:
    w = await get_withdrawal(ctx, withdrawal_id, for_update=True)
    if w.status not in ("pending", "processing", "verifying"):
        await ctx.session.commit()
        return w.status  # идемпотентность
    assert ctx.fleet is not None, "Fleet provider is required to process withdrawals"
    w.status = "processing"
    w.attempts = attempt + 1
    await ctx.session.commit()

    delays = retry_delays(ctx)
    try:
        resp = await ctx.fleet.create_driver_transaction(
            driver_profile_id=w.driver_profile_id, amount=w.amount,
            category_id=ctx.settings.str("fleet_transaction_category_id"),
            description=f"{ctx.settings.str('payout_description')} {w.marker}",
            idempotency_token=str(w.idempotency_token))
        await complete_withdrawal(ctx, w.id, resp.transaction_id)
        return "completed"

    except UnknownOutcomeError as e:  # таймаут, обрыв связи
        w = await get_withdrawal(ctx, withdrawal_id, for_update=True)
        w.status = "verifying"
        w.last_error = str(e)[:500]
        await ctx.session.commit()
        await ctx.queue.enqueue("verify_withdrawal", w.id, attempt,
                                delay_seconds=ctx.settings.int("withdrawal_verify_delay_seconds"))
        return "verifying"

    except NonRetryableFleetError as e:  # 400, 401, 403, 404
        await fail_withdrawal(ctx, w.id, str(e))
        return "failed"

    except RetryableFleetError as e:  # 429, 5xx с явным ответом
        if attempt < len(delays):
            w = await get_withdrawal(ctx, withdrawal_id, for_update=True)
            w.status = "pending"
            w.last_error = str(e)[:500]
            await ctx.session.commit()
            await ctx.queue.enqueue("process_withdrawal", w.id, attempt + 1, delay_seconds=delays[attempt])
            return "pending"
        await fail_withdrawal(ctx, w.id, str(e))
        return "failed"


async def verify_withdrawal(ctx: Ctx, withdrawal_id: int, attempt: int) -> str:
    w = await get_withdrawal(ctx, withdrawal_id)
    if w.status != "verifying":
        return w.status
    assert ctx.fleet is not None
    delays = retry_delays(ctx)

    if w.external_transaction_id:  # источник 1: прямой статус
        try:
            st = await ctx.fleet.get_transaction_status(w.external_transaction_id)
            if st.is_success:
                await complete_withdrawal(ctx, w.id, w.external_transaction_id)
                return "completed"
            if st.is_failed:
                await fail_withdrawal(ctx, w.id, "transaction rejected by Fleet")
                return "failed"
        except NonRetryableFleetError:
            pass

    try:  # источник 2: поиск по метке
        found = await ctx.fleet.find_driver_transaction(
            driver_profile_id=w.driver_profile_id, from_dt=w.requested_at - timedelta(minutes=5),
            to_dt=ctx.now(), marker=w.marker or "")
    except FleetError:
        # сверка невозможна — остаёмся в verifying, reconcile_withdrawals повторит
        await ctx.queue.enqueue("verify_withdrawal", w.id, attempt,
                                delay_seconds=ctx.settings.int("withdrawal_verify_delay_seconds"))
        return "verifying"
    if found:
        await complete_withdrawal(ctx, w.id, found.transaction_id)
        return "completed"

    if attempt < len(delays):  # транзакции не было — можно повторить
        w = await get_withdrawal(ctx, withdrawal_id, for_update=True)
        w.status = "pending"
        await ctx.session.commit()
        await ctx.queue.enqueue("process_withdrawal", w.id, attempt + 1, delay_seconds=delays[attempt])
        return "pending"
    await fail_withdrawal(ctx, w.id, "unknown outcome, not found after verification")
    return "failed"


async def complete_withdrawal(ctx: Ctx, withdrawal_id: int, external_transaction_id: str | None, *,
                              processed_by: int | None = None, proof_file_id: str | None = None) -> None:
    w = await get_withdrawal(ctx, withdrawal_id, for_update=True)
    if w.status == "completed":
        await ctx.session.commit()
        return
    user = await lock_user(ctx, w.user_id)
    w.status = "completed"
    w.external_transaction_id = external_transaction_id
    w.completed_at = ctx.now()
    w.processed_by = processed_by
    w.proof_file_id = proof_file_id
    accs = (await ctx.session.execute(
        select(Accrual).where(Accrual.withdrawal_id == w.id, Accrual.status == "reserved"))).scalars().all()
    for acc in accs:
        acc.status = "withdrawn"
    await write_ledger(ctx, user, "withdrawal_complete", 0, "withdrawal", w.id)
    await notify_user(ctx, w.user_id, "wallet.success", amount=money(w.amount),
                      tx_id=external_transaction_id or w.marker)
    await ctx.session.commit()


async def fail_withdrawal(ctx: Ctx, withdrawal_id: int, error: str, *, status: str = "failed",
                          actor_id: int | None = None) -> None:
    """Возврат зарезервированных денег в кошелёк (R15)."""
    w = await get_withdrawal(ctx, withdrawal_id, for_update=True)
    user = await lock_user(ctx, w.user_id)
    if w.status in ("failed", "completed", "cancelled"):
        await ctx.session.commit()
        return
    w.status = status
    w.last_error = error[:500]
    w.failed_at = ctx.now()
    w.processed_by = actor_id
    accs = (await ctx.session.execute(
        select(Accrual).where(Accrual.withdrawal_id == w.id, Accrual.status == "reserved"))).scalars().all()
    for acc in accs:
        acc.status = "available"
        acc.withdrawal_id = None
    user.balance_available += w.amount  # ВОЗВРАТ
    await write_ledger(ctx, user, "withdrawal_refund", w.amount, "withdrawal", w.id)
    await settle_debt_from_balance(ctx, user)
    await notify_user(ctx, w.user_id, "wallet.failed" if status == "failed" else "wallet.cancelled",
                      amount=money(w.amount))
    if status == "failed":
        await alert_admins(ctx, "withdrawal_failed", withdrawal_id=w.id, error=error[:200])
    await ctx.session.commit()


# ── админские действия (finance) ─────────────────────────────────────────────
async def approve_withdrawal(ctx: Ctx, withdrawal_id: int, actor_id: int) -> None:
    """Подтверждение вывода в ручном режиме: отправка через Fleet."""
    w = await get_withdrawal(ctx, withdrawal_id, for_update=True)
    require(w.status == "awaiting_approval", "err.invalid_withdrawal_state")
    require(not w.requires_manual, "err.requires_manual_payout")
    w.status = "pending"
    w.processed_by = actor_id
    await audit_log(ctx, actor_id, "withdrawal_approved", "withdrawal", w.id)
    await ctx.session.commit()
    await ctx.queue.enqueue("process_withdrawal", w.id, 0)


async def mark_paid_manually(ctx: Ctx, withdrawal_id: int, actor_id: int, proof_file_id: str | None,
                             reference: str | None = None) -> None:
    """Ручная выплата (уволенным) с прикреплением подтверждения."""
    w = await get_withdrawal(ctx, withdrawal_id)
    require(w.status in ("awaiting_approval", "verifying"), "err.invalid_withdrawal_state")
    await audit_log(ctx, actor_id, "withdrawal_paid_manually", "withdrawal", w.id,
                    new_value={"proof": proof_file_id, "reference": reference})
    await complete_withdrawal(ctx, w.id, reference or f"MANUAL-{w.id}", processed_by=actor_id,
                              proof_file_id=proof_file_id)


async def cancel_withdrawal(ctx: Ctx, withdrawal_id: int, actor_id: int, reason: str) -> None:
    w = await get_withdrawal(ctx, withdrawal_id)
    require(w.status in ("awaiting_approval", "pending", "verifying"), "err.invalid_withdrawal_state")
    if w.status == "verifying":
        # исход неизвестен — отмена только после ручной сверки по метке
        assert ctx.fleet is not None
        found = await ctx.fleet.find_driver_transaction(w.driver_profile_id, w.requested_at - timedelta(minutes=5),
                                                        ctx.now(), w.marker or "")
        if found:
            await complete_withdrawal(ctx, w.id, found.transaction_id, processed_by=actor_id)
            raise BusinessError("err.withdrawal_already_paid")
    await audit_log(ctx, actor_id, "withdrawal_cancelled", "withdrawal", w.id, new_value={"reason": reason})
    await fail_withdrawal(ctx, w.id, f"cancelled: {reason}", status="cancelled", actor_id=actor_id)


async def retry_withdrawal(ctx: Ctx, withdrawal_id: int, actor_id: int) -> None:
    w = await get_withdrawal(ctx, withdrawal_id)
    require(w.status in ("pending", "verifying"), "err.invalid_withdrawal_state")
    await audit_log(ctx, actor_id, "withdrawal_retry", "withdrawal", w.id)
    await ctx.session.commit()
    if w.status == "verifying":
        await ctx.queue.enqueue("verify_withdrawal", w.id, w.attempts)
    else:
        await ctx.queue.enqueue("process_withdrawal", w.id, w.attempts)
