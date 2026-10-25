"""A3 — решение администратора по заявке на подключение (3.5)."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from src.core.admin.audit import audit_log
from src.core.admin.roles import require_role
from src.core.billing.bonus_rules import referrer_bonus_amount
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.notifications.service import alert_admins, money, notify_user, tkey
from src.core.onboarding.registration import notify_referrer
from src.core.referral.matching import try_link_driver_profile
from src.core.referral.queries import get_referral_for
from src.db.models import ApprovalRequest, Referral, User

DECISIONS = ("approve_with_referral", "approve_without_referral", "reject")


async def get_approval_request(ctx: Ctx, request_id: int) -> ApprovalRequest:
    req = (await ctx.session.execute(
        select(ApprovalRequest).where(ApprovalRequest.id == request_id).with_for_update())).scalar_one_or_none()
    if req is None:
        raise BusinessError("err.not_found", entity="approval_request", id=str(request_id))
    return req


async def admin_decide(ctx: Ctx, request_id: int, admin: User, decision: str, reason: str = "") -> ApprovalRequest:
    require_role(admin.role, "moderator")
    if decision not in DECISIONS:
        raise BusinessError("err.invalid_decision")
    req = await get_approval_request(ctx, request_id)
    if req.status != "pending":
        raise BusinessError("err.request_already_decided")
    if decision == "reject" and not reason.strip():
        raise BusinessError("err.reject_reason_required")
    user = await ctx.session.get(User, req.user_id, with_for_update=True)
    assert user is not None
    ref = await get_referral_for(ctx, user.id, for_update=True)
    if ref is not None and (req.referral_id is None or ref.status == "expired"):
        ref = None  # ссылки нет или окно атрибуции истекло (TC-22)
    now = ctx.now()
    linked = False

    if decision == "approve_with_referral":
        user.access_status = "approved"
        linked = await try_link_driver_profile(ctx, user, actor_id=admin.id)
        if ref:
            ref.is_counted = True
            ref.approved_at = now
            ref.status = "hired" if linked else "registered"
            ref.hired_at = now if linked else None
            ref.rejected_reason = None
            await notify_referrer(ctx, ref, "referral.counted", bonus=money(await referrer_bonus_amount(ctx)))
        await notify_user(ctx, user.id, "onboarding.approved")

    elif decision == "approve_without_referral":
        user.access_status = "approved"
        linked = await try_link_driver_profile(ctx, user, actor_id=admin.id)
        if ref:
            ref.is_counted = False
            ref.status = "rejected"
            ref.rejected_reason = "ADMIN_NO_REFERRAL"
            await notify_referrer(ctx, ref, "referral.not_counted")
        await notify_user(ctx, user.id, "onboarding.approved")

    else:  # reject
        user.access_status = "rejected"
        if ref:
            ref.is_counted = False
            ref.status = "rejected"
            ref.rejected_reason = (reason or "ADMIN_REJECT")[:64]
            await notify_referrer(ctx, ref, "referral.not_counted")
        await notify_user(ctx, user.id, "onboarding.rejected", reason=_reason_param(reason))

    if decision != "reject" and not linked:
        # 3.6: профиль не найден — предупреждение админу, фоновая задача продолжит поиск
        await alert_admins(ctx, "profile_not_found_after_approval", user_id=user.id, request_id=req.id)

    req.status = decision
    req.decided_by = admin.id
    req.decided_at = now
    req.reason = reason or None
    await audit_log(ctx, admin.id, "approval_decision", "approval_request", request_id, new_value=decision)
    await ctx.session.commit()
    return req


def _reason_param(reason: str) -> object:
    """Код из справочника причин → локализованный текст, иначе — свободный текст админа."""
    if reason.startswith("code:"):
        return tkey(f"reject_reason.{reason[5:]}")
    return reason


async def pending_requests(ctx: Ctx) -> list[ApprovalRequest]:
    return list((await ctx.session.execute(
        select(ApprovalRequest).where(ApprovalRequest.status == "pending").order_by(ApprovalRequest.created_at)
    )).scalars().all())


async def expire_referrals(ctx: Ctx) -> dict[str, int]:
    """Ежедневно 04:30: окна клика (30 дн.) и подтверждения (45 дн.)."""
    now = ctx.now()
    s = ctx.settings
    click_border = now - timedelta(days=s.int("attribution_window_click_days"))
    approval_border = now - timedelta(days=s.int("attribution_window_approval_days"))
    clicked = (await ctx.session.execute(
        select(Referral).where(Referral.status == "clicked", Referral.clicked_at < click_border))).scalars().all()
    for ref in clicked:
        ref.status, ref.is_counted = "expired", False
        await notify_referrer(ctx, ref, "referral.expired", days=s.int("attribution_window_click_days"))
    pending = (await ctx.session.execute(
        select(Referral).where(Referral.status == "pending_approval", Referral.registered_at < approval_border)
    )).scalars().all()
    for ref in pending:
        ref.status, ref.is_counted = "expired", False
        await notify_referrer(ctx, ref, "referral.expired", days=s.int("attribution_window_approval_days"))
    await ctx.session.commit()
    return {"click": len(clicked), "approval": len(pending)}


async def pending_approval_reminder(ctx: Ctx) -> int:
    hours = ctx.settings.int("approval_reminder_hours")
    border = ctx.now() - timedelta(hours=hours)
    count = len([r for r in await pending_requests(ctx) if r.created_at < border])
    if count:
        await alert_admins(ctx, "pending_approvals", count=count, hours=hours)
        await ctx.session.commit()
    return count
