"""Telegram-админка (Шаг 15): заявки, очередь выводов, поддержка, поиск, экстренная рассылка."""

from __future__ import annotations

import re
from typing import Any

from aiogram import F, Router
from aiogram.filters import BaseFilter, Command, CommandObject
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message
from sqlalchemy import func, select

from src.bot.handlers.common import send
from src.bot.i18n import fmt_money
from src.bot.keyboards.menu import inline
from src.bot.render import dispute_details
from src.bot.states.forms import AdminForm
from src.core.admin.broadcasts import create_broadcast, resolve_segment, start_broadcast
from src.core.admin.roles import has_role, is_staff
from src.core.admin.users import log_photo_view, search_users
from src.core.billing.withdrawal import approve_withdrawal, cancel_withdrawal, mark_paid_manually
from src.core.onboarding.approval import admin_decide, pending_requests
from src.core.onboarding.registration import notify_admins_new_request
from src.core.progress.display import friends_count
from src.core.support.tickets import close_ticket, reply_to_ticket
from src.db.models import ApprovalRequest, SupportTicket, User, Withdrawal

router = Router(name="admin")
TICKET_RE = re.compile(r"№\s?(\d+)")


class Staff(BaseFilter):
    def __init__(self, role: str = "operator", write: bool = True) -> None:
        self.role, self.write = role, write

    async def __call__(self, event: Any, user: User | None = None) -> bool:
        return user is not None and is_staff(user.role) and has_role(user.role, self.role, write=self.write)


@router.message(Command("admin"), Staff("operator", write=False), flags={"screen": "admin"})
async def admin_menu(message: Message, **data: Any) -> None:
    ctx, t = data["ctx"], data["t"]
    s = ctx.session
    counts = {
        "approvals": await s.scalar(select(func.count()).select_from(ApprovalRequest).where(ApprovalRequest.status == "pending")),
        "awaiting": await s.scalar(select(func.count()).select_from(Withdrawal).where(Withdrawal.status == "awaiting_approval")),
        "verifying": await s.scalar(select(func.count()).select_from(Withdrawal).where(Withdrawal.status == "verifying")),
        "tickets": await s.scalar(select(func.count()).select_from(SupportTicket).where(SupportTicket.status == "open")),
    }
    await message.answer(t("admin.menu", **{k: int(v or 0) for k, v in counts.items()}),
                         reply_markup=inline([[(t("admin.btn-approvals"), "adm:approvals"),
                                               (t("admin.btn-withdrawals"), "adm:withdrawals")]]))


@router.message(Command("admin"), flags={"screen": "admin"})
async def not_staff(message: Message, **data: Any) -> None:
    await message.answer(data["t"]("admin.not_staff"))


# ── заявки на подключение ────────────────────────────────────────────────────
@router.callback_query(F.data == "adm:approvals", Staff("moderator"), flags={"screen": "admin"})
async def list_approvals(cb: CallbackQuery, **data: Any) -> None:
    ctx = data["ctx"]
    reqs = await pending_requests(ctx)
    if not reqs:
        await cb.answer(data["t"]("admin.no_pending"), show_alert=True)
        return
    for req in reqs[:ctx.settings.int("friends_page_size")]:
        await notify_admins_new_request(ctx, req)  # карточки уйдут через outbox
    await cb.answer()


async def _decide(cb: CallbackQuery, data: dict[str, Any], request_id: int, decision: str, reason: str = "") -> None:
    ctx, admin, t = data["ctx"], data["user"], data["t"]
    await admin_decide(ctx, request_id, admin, decision, reason)
    note = t("admin.decision_done", request_id=request_id, decision=t(f"admin.decision-{decision}"),
             admin=admin.full_name or admin.username or str(admin.telegram_id))
    await cb.answer()
    if cb.message is not None:
        try:
            await cb.message.edit_text((cb.message.html_text or "") + "\n\n" + note)  # type: ignore[union-attr]
        except Exception:  # noqa: BLE001 — исходное сообщение могло быть удалено
            await cb.message.answer(note)  # type: ignore[union-attr]


@router.callback_query(F.data.regexp(r"^ap:(with|without):\d+$"), Staff("moderator"), flags={"screen": "admin"})
async def approve(cb: CallbackQuery, **data: Any) -> None:
    _, kind, rid = (cb.data or "").split(":")
    await _decide(cb, data, int(rid), "approve_with_referral" if kind == "with" else "approve_without_referral")


@router.callback_query(F.data.regexp(r"^ap:reject:\d+$"), Staff("moderator"), flags={"screen": "admin"})
async def reject_reasons(cb: CallbackQuery, **data: Any) -> None:
    ctx, t = data["ctx"], data["t"]
    rid = int((cb.data or "").rsplit(":", 1)[1])
    rows = [[(t(f"reject_reason.{code}"), f"ap:rr:{rid}:{code}")] for code in ctx.settings.list("rejection_reasons")]
    rows.append([(t("admin.btn-custom_reason"), f"ap:rc:{rid}")])
    await send(cb, t("admin.reject_reason_prompt", request_id=rid), inline(rows))


@router.callback_query(F.data.regexp(r"^ap:rr:\d+:\w+$"), Staff("moderator"), flags={"screen": "admin"})
async def reject_with_code(cb: CallbackQuery, **data: Any) -> None:
    _, _, rid, code = (cb.data or "").split(":")
    await _decide(cb, data, int(rid), "reject", f"code:{code}")


@router.callback_query(F.data.regexp(r"^ap:rc:\d+$"), Staff("moderator"), flags={"screen": "admin"})
async def reject_custom(cb: CallbackQuery, state: FSMContext, **data: Any) -> None:
    await state.set_state(AdminForm.reject_reason)
    await state.update_data(request_id=int((cb.data or "").rsplit(":", 1)[1]))
    await send(cb, data["t"]("admin.reject_custom_prompt"))


@router.message(AdminForm.reject_reason, F.text, Staff("moderator"), flags={"screen": "admin"})
async def reject_custom_text(message: Message, state: FSMContext, **data: Any) -> None:
    form = await state.get_data()
    await state.clear()
    ctx, admin, t = data["ctx"], data["user"], data["t"]
    await admin_decide(ctx, form["request_id"], admin, "reject", message.text or "")
    await message.answer(t("admin.decision_done", request_id=form["request_id"], decision=t("admin.decision-reject"),
                           admin=admin.full_name or str(admin.telegram_id)))


@router.callback_query(F.data.regexp(r"^ap:photo:[fb]:\d+$"), Staff("moderator", write=False), flags={"screen": "admin"})
async def license_photo(cb: CallbackQuery, **data: Any) -> None:
    ctx, admin = data["ctx"], data["user"]
    _, _, side, rid = (cb.data or "").split(":")
    req = await ctx.session.get(ApprovalRequest, int(rid))
    if req is None:
        await cb.answer()
        return
    front, back = await log_photo_view(ctx, admin, req.user_id)  # каждое открытие — в audit log
    file_id = front if side == "f" else back
    await cb.answer()
    if file_id and cb.message is not None:
        await cb.message.answer_photo(file_id, caption=f"#{rid}")  # type: ignore[union-attr]


# ── выводы ───────────────────────────────────────────────────────────────────
@router.callback_query(F.data == "adm:withdrawals", Staff("finance", write=False), flags={"screen": "admin"})
async def list_withdrawals(cb: CallbackQuery, **data: Any) -> None:
    ctx, t = data["ctx"], data["t"]
    rows = (await ctx.session.execute(
        select(Withdrawal, User.full_name).join(User, User.id == Withdrawal.user_id)
        .where(Withdrawal.status.in_(["awaiting_approval", "verifying", "failed"]))
        .order_by(Withdrawal.id.desc()).limit(30))).all()
    if not rows:
        await cb.answer(t("admin.no_withdrawals"), show_alert=True)
        return
    lines = [t("admin.withdrawals_title")] + [
        t("admin.withdrawal_row", id=w.id, amount=fmt_money(w.amount), status=t(f"withdrawal.status-{w.status}"),
          name=name or "—") for w, name in rows]
    kb = [[(f"✅ #{w.id}", f"wd:approve:{w.id}") if not w.requires_manual else (f"🧾 #{w.id}", f"wd:paid:{w.id}"),
           (f"↩️ #{w.id}", f"wd:cancel:{w.id}")] for w, _ in rows if w.status == "awaiting_approval"]
    await send(cb, "\n".join(lines), inline(kb))


@router.callback_query(F.data.regexp(r"^wd:approve:\d+$"), Staff("finance"), flags={"screen": "admin"})
async def wd_approve(cb: CallbackQuery, **data: Any) -> None:
    wid = int((cb.data or "").rsplit(":", 1)[1])
    await approve_withdrawal(data["ctx"], wid, data["user"].id)
    await send(cb, data["t"]("admin.withdrawal_done", withdrawal_id=wid, status=data["t"]("withdrawal.status-pending")))


@router.callback_query(F.data.regexp(r"^wd:cancel:\d+$"), Staff("finance"), flags={"screen": "admin"})
async def wd_cancel(cb: CallbackQuery, **data: Any) -> None:
    wid = int((cb.data or "").rsplit(":", 1)[1])
    admin = data["user"]
    await cancel_withdrawal(data["ctx"], wid, admin.id, f"telegram admin {admin.id}")
    await send(cb, data["t"]("admin.withdrawal_done", withdrawal_id=wid, status=data["t"]("withdrawal.status-cancelled")))


@router.callback_query(F.data.regexp(r"^wd:paid:\d+$"), Staff("finance"), flags={"screen": "admin"})
async def wd_paid(cb: CallbackQuery, state: FSMContext, **data: Any) -> None:
    wid = int((cb.data or "").rsplit(":", 1)[1])
    await state.set_state(AdminForm.paid_proof)
    await state.update_data(withdrawal_id=wid)
    await send(cb, data["t"]("admin.paid_proof_prompt", withdrawal_id=wid))


@router.message(AdminForm.paid_proof, F.photo | F.document, Staff("finance"), flags={"screen": "admin"})
async def wd_paid_proof(message: Message, state: FSMContext, **data: Any) -> None:
    form = await state.get_data()
    await state.clear()
    proof = message.photo[-1].file_id if message.photo else message.document.file_id  # type: ignore[union-attr]
    await mark_paid_manually(data["ctx"], form["withdrawal_id"], data["user"].id, proof, message.caption)
    await message.answer(data["t"]("admin.withdrawal_done", withdrawal_id=form["withdrawal_id"],
                                   status=data["t"]("withdrawal.status-completed")))


# ── поддержка ────────────────────────────────────────────────────────────────
@router.callback_query(F.data.regexp(r"^tk:close:\d+$"), Staff("operator"), flags={"screen": "admin"})
async def ticket_close(cb: CallbackQuery, **data: Any) -> None:
    tid = int((cb.data or "").rsplit(":", 1)[1])
    await close_ticket(data["ctx"], tid, data["user"])
    await send(cb, data["t"]("admin.ticket_closed", ticket_id=tid))


@router.callback_query(F.data.regexp(r"^tk:details:\d+$"), Staff("operator", write=False), flags={"screen": "admin"})
async def ticket_details(cb: CallbackQuery, **data: Any) -> None:
    ticket = await data["ctx"].session.get(SupportTicket, int((cb.data or "").rsplit(":", 1)[1]))
    if ticket is None or not ticket.context:
        await cb.answer()
        return
    await send(cb, dispute_details(data["lang"], data["t"], ticket.context))


@router.message(F.reply_to_message, Staff("operator"), flags={"screen": "admin"})
async def ticket_reply(message: Message, **data: Any) -> None:
    """Ответ оператора: reply на сообщение с обращением в админ-чате."""
    ctx = data["ctx"]
    replied = message.reply_to_message
    assert replied is not None
    ticket = (await ctx.session.execute(select(SupportTicket).where(
        SupportTicket.admin_message_id == replied.message_id))).scalar_one_or_none()
    if ticket is None:
        m = TICKET_RE.search(replied.text or replied.caption or "")
        ticket = await ctx.session.get(SupportTicket, int(m.group(1))) if m else None
    if ticket is None or not (message.text or message.caption):
        return
    await reply_to_ticket(ctx, ticket.id, data["user"], message.text or message.caption or "")
    await message.answer(data["t"]("admin.reply_sent"))


# ── поиск и рассылка ─────────────────────────────────────────────────────────
@router.message(Command("find"), Staff("operator", write=False), flags={"screen": "admin"})
async def find(message: Message, command: CommandObject, **data: Any) -> None:
    ctx, t = data["ctx"], data["t"]
    if not command.args:
        await message.answer(t("admin.find_usage"))
        return
    users = await search_users(ctx, command.args)
    if not users:
        await message.answer(t("admin.find_empty"))
        return
    lines = [t("admin.user_row", id=u.id, name=u.full_name or "—", phone=u.phone or "—", status=u.access_status,
               code=u.referral_code, available=fmt_money(u.balance_available), debt=fmt_money(u.debt),
               friends=await friends_count(ctx, u.id)) for u in users]
    await message.answer("\n\n".join(lines))


@router.message(Command("broadcast"), Staff("admin"), flags={"screen": "admin"})
async def broadcast(message: Message, command: CommandObject, state: FSMContext, **data: Any) -> None:
    ctx, t = data["ctx"], data["t"]
    if not command.args:
        await message.answer(t("admin.broadcast_usage"))
        return
    segment = {"access_status": "approved", "role": "driver"}
    count = len(await resolve_segment(ctx, segment))
    b = await create_broadcast(ctx, data["user"], title="emergency", text_=command.args, segment=segment)
    await ctx.session.commit()
    await message.answer(t("admin.broadcast_confirm", count=count, text=command.args),
                         reply_markup=inline([[(t("admin.btn-broadcast_send"), f"bc:send:{b.id}"),
                                               (t("btn.cancel"), "wal:cancel")]]))


@router.callback_query(F.data.regexp(r"^bc:send:\d+$"), Staff("admin"), flags={"screen": "admin"})
async def broadcast_send(cb: CallbackQuery, **data: Any) -> None:
    bid = int((cb.data or "").rsplit(":", 1)[1])
    count = await start_broadcast(data["ctx"], bid, data["user"].id)
    if cb.message is not None:
        await cb.message.edit_reply_markup(reply_markup=None)  # type: ignore[union-attr]
    await send(cb, data["t"]("admin.broadcast_started", id=bid, count=count))
