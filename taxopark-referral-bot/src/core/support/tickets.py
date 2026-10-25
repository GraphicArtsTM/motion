"""Поддержка: тикеты, ответы, оспаривание начисления с детализацией (N6)."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

from sqlalchemy import select

from src.core.admin.audit import audit_log
from src.core.clock import month_code
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.notifications.service import button, notify_admins, notify_user
from src.core.referral.queries import referrals_with_profiles
from src.core.scoring.points import points_for_profiles
from src.core.scoring.snapshot import period_coefficients
from src.db.models import Accrual, BonusRule, Period, SupportMessage, SupportTicket, User


async def create_ticket(ctx: Ctx, user: User, text: str | None, *, kind: str = "general",
                        context: dict[str, Any] | None = None, media: dict[str, Any] | None = None) -> SupportTicket:
    t = SupportTicket(user_id=user.id, subject=(text or "")[:120] or kind, kind=kind, context=context,
                      status="open", sla_due_at=ctx.now() + timedelta(hours=ctx.settings.int("support_sla_hours")),
                      created_at=ctx.now())
    ctx.session.add(t)
    await ctx.session.flush()
    ctx.session.add(SupportMessage(ticket_id=t.id, author_type="user", author_id=user.id, text=text, media=media,
                                   created_at=ctx.now()))
    await notify_admins(ctx, "admin.support_ticket" if kind == "general" else "admin.support_dispute",
                        ticket_id=t.id, user_id=user.id, name=user.full_name or str(user.telegram_id),
                        text=text or "", media=media, buttons=_ticket_buttons(t))
    await ctx.session.commit()
    return t


def _ticket_buttons(t: SupportTicket) -> list[list[dict[str, Any]]]:
    rows = [[button("admin.btn.dispute_details", f"tk:details:{t.id}")]] if t.kind == "dispute" else []
    return [*rows, [button("admin.btn.close_ticket", f"tk:close:{t.id}")]]


async def add_user_message(ctx: Ctx, ticket_id: int, user: User, text: str | None,
                           media: dict[str, Any] | None = None) -> None:
    t = await ctx.session.get(SupportTicket, ticket_id)
    if t is None or t.user_id != user.id:
        raise BusinessError("err.not_found", entity="ticket", id=str(ticket_id))
    t.status = "open"
    ctx.session.add(SupportMessage(ticket_id=t.id, author_type="user", author_id=user.id, text=text, media=media,
                                   created_at=ctx.now()))
    await notify_admins(ctx, "admin.support_message", ticket_id=t.id, name=user.full_name or "", text=text or "",
                        media=media)
    await ctx.session.commit()


async def reply_to_ticket(ctx: Ctx, ticket_id: int, admin: User, text: str) -> None:
    t = await ctx.session.get(SupportTicket, ticket_id)
    if t is None:
        raise BusinessError("err.not_found", entity="ticket", id=str(ticket_id))
    ctx.session.add(SupportMessage(ticket_id=t.id, author_type="admin", author_id=admin.id, text=text,
                                   created_at=ctx.now()))
    t.status = "answered"
    t.assigned_to = t.assigned_to or admin.id
    await notify_user(ctx, t.user_id, "support.reply", ticket_id=t.id, text=text)
    await ctx.session.commit()


async def close_ticket(ctx: Ctx, ticket_id: int, admin: User) -> None:
    t = await ctx.session.get(SupportTicket, ticket_id)
    if t is None:
        raise BusinessError("err.not_found", entity="ticket", id=str(ticket_id))
    t.status, t.closed_at = "closed", ctx.now()
    await audit_log(ctx, admin.id, "ticket_closed", "support_ticket", t.id)
    await notify_user(ctx, t.user_id, "support.closed", ticket_id=t.id)
    await ctx.session.commit()


async def open_ticket_of(ctx: Ctx, user_id: int) -> SupportTicket | None:
    return (await ctx.session.execute(
        select(SupportTicket).where(SupportTicket.user_id == user_id, SupportTicket.status != "closed")
        .order_by(SupportTicket.id.desc()).limit(1))).scalar_one_or_none()


# ── N6: оспаривание расчёта ──────────────────────────────────────────────────
async def build_dispute_context(ctx: Ctx, user: User) -> dict[str, Any]:
    """Детализация: друзья, баллы, разбивка по тарифам, коэффициенты периода, ступень бонуса."""
    periods = (await ctx.session.execute(
        select(Period).where(Period.code <= month_code(ctx.now())).order_by(Period.starts_at.desc()).limit(2)
    )).scalars().all()
    refs = await referrals_with_profiles(ctx, referrer_id=user.id, counted_only=False)
    out: dict[str, Any] = {"user_id": user.id, "periods": []}
    for p in periods:
        coefs = await period_coefficients(ctx, p.id)
        pts = await points_for_profiles(ctx, p, [pid for _, pid in refs if pid])
        friends = []
        for ref, pid in refs:
            friend = await ctx.session.get(User, ref.referred_user_id)
            res = pts.get(pid) if pid else None
            friends.append({
                "referral_id": ref.id, "name": friend.full_name if friend else "", "status": ref.status,
                "is_counted": ref.is_counted, "points_x100": res.points_x100 if res else 0,
                "orders": res.eligible_orders_count if res else 0,
                "breakdown": res.breakdown_json() if res else [],
            })
        accs = (await ctx.session.execute(select(Accrual, BonusRule).outerjoin(
            BonusRule, BonusRule.id == Accrual.bonus_rule_id).where(
            Accrual.user_id == user.id, Accrual.period_id == p.id, Accrual.parent_accrual_id.is_(None)))).all()
        out["periods"].append({
            "code": p.code, "status": p.status, "threshold_points_x100": p.threshold_points_x100,
            "default_coefficient_x100": p.default_coefficient_x100, "coefficients": coefs, "friends": friends,
            "accruals": [{"id": a.id, "type": a.type, "amount": a.amount, "status": a.status,
                          "referral_id": a.referral_id,
                          "bonus_rule": {"min_percent": r.min_percent, "bonus_uzs": r.bonus_uzs} if r else None}
                         for a, r in accs],
        })
    return out


async def create_dispute(ctx: Ctx, user: User, text: str | None = None) -> SupportTicket:
    context = await build_dispute_context(ctx, user)
    return await create_ticket(ctx, user, text or "dispute", kind="dispute", context=context)
