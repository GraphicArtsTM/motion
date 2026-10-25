"""💰 Мой кошелёк, вывод средств (6.2–6.4), история, оспаривание (N6), поддержка."""

from __future__ import annotations

from typing import Any

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message
from sqlalchemy import func, select

from src.bot.handlers.common import send
from src.bot.handlers.menu import MenuButton
from src.bot.i18n import fmt_money
from src.bot.keyboards.menu import inline
from src.bot.states.forms import SupportForm, WalletForm
from src.core.billing.periods import current_period
from src.core.billing.wallet import wallet_totals
from src.core.billing.withdrawal import request_withdrawal, withdrawal_block_reason
from src.core.clock import prev_code
from src.core.context import Ctx
from src.core.support.tickets import add_user_message, create_dispute, create_ticket, open_ticket_of
from src.db.models import Accrual, Period, User, Withdrawal

router = Router(name="wallet")


async def wallet_text(ctx: Ctx, user: User, t: Any) -> tuple[str, Any]:
    totals = await wallet_totals(ctx, user.id)
    lines = [t("wallet.title"), "", t("wallet.available", amount={"__money__": totals["available"]}),
             "─────────────────────────────────",
             t("wallet.totals", earned={"__money__": totals["total_earned"]},
               withdrawn={"__money__": totals["total_withdrawn"]})]
    # последний закрытый месяц
    period = await current_period(ctx)
    last = (await ctx.session.execute(select(Period).where(Period.code == prev_code(period.code)))).scalar_one_or_none()
    if last is not None:
        rows = (await ctx.session.execute(
            select(Accrual.type, func.count(), func.coalesce(func.sum(Accrual.amount), 0))
            .where(Accrual.user_id == user.id, Accrual.period_id == last.id, Accrual.parent_accrual_id.is_(None))
            .group_by(Accrual.type))).all()
        by_type = {tp: (int(c), int(s)) for tp, c, s in rows}
        if "referral" in by_type:
            c, s = by_type["referral"]
            lines += ["", t("wallet.month_block", month={"__month__": last.code}, count=c, unit=fmt_money(s // c),
                            total=fmt_money(s))]
        if ctx.settings.bool("milestones_enabled") and "milestone" in by_type:
            lines.append(t("wallet.milestone_line", amount={"__money__": by_type["milestone"][1]}))
        if ctx.settings.bool("referred_bonus_enabled") and "referred_welcome" in by_type:
            lines.append(t("wallet.welcome_line", amount={"__money__": by_type["referred_welcome"][1]}))
    if totals["hold"]:
        lines.append(t("wallet.hold", amount={"__money__": totals["hold"]}))
    if totals["reserved"]:
        lines.append(t("wallet.reserved", amount={"__money__": totals["reserved"]}))
    if totals["debt"]:
        lines += ["", t("wallet.debt", amount={"__money__": totals["debt"]})]
    kb: list[list[tuple[str, str]]] = []
    if totals["available"] > 0 and await withdrawal_block_reason(ctx, user) is None:
        kb.append([(t("wallet.withdraw_button", amount={"__money__": totals["available"]}), "wal:ask")])
        kb.append([(t("btn.other_amount"), "wal:other"), (t("btn.history"), "wal:history")])
    else:
        kb.append([(t("btn.history"), "wal:history")])
    kb.append([(t("wallet.dispute_button"), "wal:dispute")])
    return "\n".join(lines), inline(kb)


@router.message(MenuButton("btn.menu-wallet"), flags={"screen": "wallet"})
async def wallet(message: Message, **data: Any) -> None:
    text, kb = await wallet_text(data["ctx"], data["user"], data["t"])
    await message.answer(text, reply_markup=kb)


async def _confirm(event: Any, data: dict[str, Any], amount: int) -> None:
    t = data["t"]
    await send(event, t("wallet.confirm", amount={"__money__": amount}),
               inline([[(t("btn.confirm_withdraw"), f"wal:go:{amount}"), (t("btn.cancel"), "wal:cancel")]]))


@router.callback_query(F.data == "wal:ask", flags={"screen": "withdraw"})
async def ask_withdraw(cb: CallbackQuery, **data: Any) -> None:
    ctx, user = data["ctx"], data["user"]
    await ctx.session.refresh(user)
    await _confirm(cb, data, user.balance_available)


@router.callback_query(F.data == "wal:other", flags={"screen": "withdraw"})
async def other_amount(cb: CallbackQuery, state: FSMContext, **data: Any) -> None:
    await state.set_state(WalletForm.amount)
    await send(cb, data["t"]("wallet.enter_amount", amount={"__money__": data["user"].balance_available}))


@router.message(WalletForm.amount, F.text, flags={"screen": "withdraw"})
async def got_amount(message: Message, state: FSMContext, **data: Any) -> None:
    digits = (message.text or "").replace(" ", "").replace(" ", "")
    if not digits.isdigit() or int(digits) <= 0:
        await message.answer(data["t"]("wallet.invalid_amount"))
        return
    await state.clear()
    await _confirm(message, data, int(digits))


@router.callback_query(F.data == "wal:cancel", flags={"screen": "wallet"})
async def cancel(cb: CallbackQuery, **data: Any) -> None:
    await cb.answer()
    if cb.message is not None:
        await cb.message.delete()  # type: ignore[union-attr]


@router.callback_query(F.data.startswith("wal:go:"), flags={"screen": "withdraw"})
async def do_withdraw(cb: CallbackQuery, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    amount = int((cb.data or "").rsplit(":", 1)[1])
    if cb.message is not None:
        await cb.message.edit_reply_markup(reply_markup=None)  # type: ignore[union-attr]  # кнопка блокируется
    w = await request_withdrawal(ctx, user.id, amount)  # A10
    await cb.answer()
    if w.status == "pending" and cb.message is not None:
        await cb.message.answer(t("wallet.processing"))  # type: ignore[union-attr]


@router.callback_query(F.data == "wal:history", flags={"screen": "wallet"})
async def history(cb: CallbackQuery, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    accs = (await ctx.session.execute(select(Accrual).where(
        Accrual.user_id == user.id, Accrual.parent_accrual_id.is_(None), Accrual.status != "cancelled")
        .order_by(Accrual.created_at.desc()).limit(15))).scalars().all()
    wds = (await ctx.session.execute(select(Withdrawal).where(Withdrawal.user_id == user.id)
                                     .order_by(Withdrawal.requested_at.desc()).limit(10))).scalars().all()
    items: list[tuple[Any, str]] = []
    for a in accs:
        items.append((a.created_at, t("wallet.history_accrual", date={"__date__": a.created_at.isoformat()},
                                      amount={"__money__": a.amount}, type=t(f"accrual.type-{a.type}"))))
    for w in wds:
        items.append((w.requested_at, t("wallet.history_withdrawal", date={"__date__": w.requested_at.isoformat()},
                                        amount={"__money__": w.amount}, status=t(f"withdrawal.status-{w.status}"))))
    items.sort(key=lambda x: x[0], reverse=True)
    body = "\n".join(text for _, text in items) or t("wallet.history_empty")
    await send(cb, t("wallet.history_title") + "\n\n" + body)


@router.callback_query(F.data == "wal:dispute", flags={"screen": "dispute"})
async def dispute(cb: CallbackQuery, state: FSMContext, **data: Any) -> None:
    await state.set_state(WalletForm.dispute)
    await send(cb, data["t"]("wallet.dispute_prompt"))


@router.message(WalletForm.dispute, flags={"screen": "dispute"})
async def dispute_text(message: Message, state: FSMContext, **data: Any) -> None:
    ticket = await create_dispute(data["ctx"], data["user"], message.text or message.caption)
    await state.clear()
    await message.answer(data["t"]("wallet.dispute_created", ticket_id=ticket.id))


# ── 🆘 Поддержка (доступна при любом access_status, кроме блокировки) ────────
@router.message(MenuButton("btn.menu-support"), flags={"screen": "support"})
async def support(message: Message, state: FSMContext, **data: Any) -> None:
    await state.set_state(SupportForm.message)
    await message.answer(data["t"]("support.prompt"))


@router.callback_query(F.data == "support:start", flags={"screen": "support"})
async def support_cb(cb: CallbackQuery, state: FSMContext, **data: Any) -> None:
    await state.set_state(SupportForm.message)
    await send(cb, data["t"]("support.prompt"))


@router.message(SupportForm.message, flags={"screen": "support"})
async def support_message(message: Message, state: FSMContext, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    media = {"photo": message.photo[-1].file_id} if message.photo else None
    text = message.text or message.caption
    await state.clear()
    ticket = await open_ticket_of(ctx, user.id)
    if ticket is not None:
        await add_user_message(ctx, ticket.id, user, text, media)
        await message.answer(t("support.sent", ticket_id=ticket.id))
        return
    ticket = await create_ticket(ctx, user, text, media=media)
    await message.answer(t("support.created", ticket_id=ticket.id))
