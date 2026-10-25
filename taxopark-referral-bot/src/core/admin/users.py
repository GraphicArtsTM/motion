"""Действия с водителями из админки (8.3 «Водители»). Всё от moderator и выше — в audit_log."""

from __future__ import annotations

from typing import Any

from sqlalchemy import func, or_, select

from src.core.admin.audit import audit_log
from src.core.admin.roles import ROLES, require_role
from src.core.billing.debt import create_correction, write_off_debt
from src.core.billing.wallet import wallet_totals
from src.core.context import Ctx
from src.core.errors import BusinessError, NotFound
from src.core.notifications.service import notify_user
from src.core.onboarding.terms import accepted_version
from src.core.onboarding.validation import normalize_license, normalize_phone
from src.db.models import (
    Accrual,
    Correction,
    Driver,
    DriverOnlineTime,
    ParkDriverProfile,
    Qualification,
    Referral,
    SupportTicket,
    User,
    UserNote,
    Withdrawal,
)

ACCESS_STATUSES = ("onboarding", "pending_approval", "approved", "rejected", "blocked")


async def search_users(ctx: Ctx, query: str, limit: int = 20) -> list[User]:
    q = query.strip()
    conds = [User.full_name.ilike(f"%{q}%"), User.referral_code == q.upper(), User.username == q.lstrip("@")]
    phone = normalize_phone(q)
    if phone:
        conds.append(User.phone == phone)
    lic = normalize_license(q)
    if lic:
        conds.append(User.driver_license == lic)
    if q.isdigit():
        conds.append(User.telegram_id == int(q))
        conds.append(User.id == int(q))
    conds.append(User.id.in_(select(Driver.user_id).where(Driver.driver_profile_id == q)))
    return list((await ctx.session.execute(select(User).where(or_(*conds)).order_by(User.id).limit(limit))).scalars())


async def get_user(ctx: Ctx, user_id: int, *, for_update: bool = False) -> User:
    user = await ctx.session.get(User, user_id, with_for_update=for_update)
    if user is None:
        raise NotFound("user", user_id)
    return user


async def user_card(ctx: Ctx, user_id: int) -> dict[str, Any]:
    user = await get_user(ctx, user_id)
    driver = (await ctx.session.execute(select(Driver).where(Driver.user_id == user_id))).scalar_one_or_none()
    profile = await ctx.session.get(ParkDriverProfile, driver.driver_profile_id) if driver else None
    online = 0
    if driver:
        online = int(await ctx.session.scalar(select(func.coalesce(func.sum(DriverOnlineTime.online_seconds), 0))
                                              .where(DriverOnlineTime.driver_profile_id == driver.driver_profile_id)) or 0)
    refs = (await ctx.session.execute(select(Referral, User.full_name).join(User, User.id == Referral.referred_user_id)
                                      .where(Referral.referrer_user_id == user_id).order_by(Referral.id))).all()
    invited_by = (await ctx.session.execute(select(Referral).where(Referral.referred_user_id == user_id))).scalar_one_or_none()
    quals = (await ctx.session.execute(select(Qualification).join(Referral, Referral.id == Qualification.referral_id)
                                       .where(Referral.referred_user_id == user_id)
                                       .order_by(Qualification.period_id))).scalars().all()
    accruals = (await ctx.session.execute(select(Accrual).where(Accrual.user_id == user_id)
                                          .order_by(Accrual.id.desc()))).scalars().all()
    withdrawals = (await ctx.session.execute(select(Withdrawal).where(Withdrawal.user_id == user_id)
                                             .order_by(Withdrawal.id.desc()))).scalars().all()
    tickets = (await ctx.session.execute(select(SupportTicket).where(SupportTicket.user_id == user_id)
                                         .order_by(SupportTicket.id.desc()))).scalars().all()
    notes = (await ctx.session.execute(select(UserNote).where(UserNote.user_id == user_id)
                                       .order_by(UserNote.id.desc()))).scalars().all()
    corrections = (await ctx.session.execute(select(Correction).where(Correction.user_id == user_id)
                                             .order_by(Correction.id.desc()))).scalars().all()
    terms = await accepted_version(ctx, user_id)
    return {
        "user": {"id": user.id, "telegram_id": user.telegram_id, "username": user.username,
                 "full_name": user.full_name, "phone": user.phone, "driver_license": user.driver_license,
                 "language": user.language, "role": user.role, "access_status": user.access_status,
                 "referral_code": user.referral_code, "payout_blocked": user.payout_blocked,
                 "qualified_referrals_count": user.qualified_referrals_count, "created_at": user.created_at,
                 "has_license_photos": bool(user.license_photo_front)},
        "wallet": await wallet_totals(ctx, user_id),
        "terms": {"version": terms[0], "accepted_at": terms[1]} if terms else None,
        "profile": None if profile is None else {
            "driver_profile_id": profile.driver_profile_id, "work_status": profile.work_status,
            "work_rule_id": profile.work_rule_id, "car_id": profile.car_id, "car_category": profile.car_category,
            "hire_date": profile.hire_date, "fire_date": profile.fire_date,
            "blocked_balance": profile.blocked_balance, "online_hours": online // 3600},
        "invited_by": None if invited_by is None else {"referral_id": invited_by.id,
                                                        "referrer_user_id": invited_by.referrer_user_id,
                                                        "status": invited_by.status,
                                                        "is_counted": invited_by.is_counted},
        "referrals": [{"id": r.id, "name": name, "status": r.status, "is_counted": r.is_counted,
                       "source_tag": r.source_tag, "is_fraud": r.is_fraud, "risk_score": r.risk_score}
                      for r, name in refs],
        "points_by_month": [{"period_id": q.period_id, "points_x100": q.points_x100,
                             "is_qualified": q.is_qualified, "breakdown": q.breakdown} for q in quals],
        "accruals": [{"id": a.id, "type": a.type, "amount": a.amount, "status": a.status, "period_id": a.period_id,
                      "referral_id": a.referral_id, "comment": a.comment, "created_at": a.created_at} for a in accruals],
        "corrections": [{"id": c.id, "amount": c.amount, "reason": c.reason, "debt_created": c.debt_created,
                         "created_at": c.created_at} for c in corrections],
        "withdrawals": [{"id": w.id, "amount": w.amount, "status": w.status, "marker": w.marker,
                         "external_transaction_id": w.external_transaction_id, "requested_at": w.requested_at,
                         "requires_manual": w.requires_manual} for w in withdrawals],
        "tickets": [{"id": t.id, "kind": t.kind, "status": t.status, "subject": t.subject} for t in tickets],
        "notes": [{"id": n.id, "text": n.text, "author_id": n.author_id, "created_at": n.created_at} for n in notes],
    }


async def set_access_status(ctx: Ctx, actor: User, user_id: int, status: str, reason: str = "") -> None:
    require_role(actor.role, "moderator")
    if status not in ACCESS_STATUSES:
        raise BusinessError("err.invalid_access_status")
    user = await get_user(ctx, user_id, for_update=True)
    old = user.access_status
    user.access_status = status
    await audit_log(ctx, actor.id, "access_status_changed", "user", user_id,
                    old_value={"access_status": old}, new_value={"access_status": status, "reason": reason})
    if status == "blocked":
        await notify_user(ctx, user_id, "account.blocked")
    elif old == "blocked" and status == "approved":
        await notify_user(ctx, user_id, "account.unblocked")


async def set_payout_blocked(ctx: Ctx, actor: User, user_id: int, blocked: bool, reason: str = "") -> None:
    require_role(actor.role, "finance")
    user = await get_user(ctx, user_id, for_update=True)
    user.payout_blocked = blocked
    await audit_log(ctx, actor.id, "payout_blocked_changed", "user", user_id,
                    new_value={"payout_blocked": blocked, "reason": reason})


async def set_role(ctx: Ctx, actor: User, user_id: int, role: str) -> None:
    require_role(actor.role, "superadmin")
    if role not in ROLES:
        raise BusinessError("err.invalid_role")
    user = await get_user(ctx, user_id, for_update=True)
    old = user.role
    user.role = role
    await audit_log(ctx, actor.id, "role_changed", "user", user_id, old_value={"role": old}, new_value={"role": role})


async def manual_adjustment(ctx: Ctx, actor: User, user_id: int, amount: int, reason: str) -> Correction:
    """Ручное начисление (amount > 0) или корректировка (amount < 0) — роль admin."""
    require_role(actor.role, "admin")
    if not reason.strip():
        raise BusinessError("err.reason_required")
    corr = await create_correction(ctx, user_id=user_id, amount=amount, reason=reason, created_by=actor.id,
                                   notify=True)
    await audit_log(ctx, actor.id, "manual_adjustment", "user", user_id, new_value={"amount": amount, "reason": reason})
    if amount > 0:
        from src.core.notifications.service import money
        await notify_user(ctx, user_id, "wallet.manual_credit", amount=money(amount))
    return corr


async def forgive_debt(ctx: Ctx, actor: User, user_id: int, amount: int, reason: str) -> Correction:
    require_role(actor.role, "admin")
    corr = await write_off_debt(ctx, user_id=user_id, amount=amount, reason=reason, actor_id=actor.id)
    await audit_log(ctx, actor.id, "debt_written_off", "user", user_id, new_value={"amount": corr.amount})
    return corr


async def add_note(ctx: Ctx, actor: User, user_id: int, text: str) -> UserNote:
    require_role(actor.role, "operator")
    note = UserNote(user_id=user_id, author_id=actor.id, text=text, created_at=ctx.now())
    ctx.session.add(note)
    await ctx.session.flush()
    return note


async def send_personal_message(ctx: Ctx, actor: User, user_id: int, text: str) -> None:
    require_role(actor.role, "operator")
    await notify_user(ctx, user_id, "admin.personal_message", text=text)
    await audit_log(ctx, actor.id, "personal_message", "user", user_id)


async def log_photo_view(ctx: Ctx, actor: User, user_id: int) -> tuple[str | None, str | None]:
    """Фото ВУ — только moderator и выше, каждое открытие в audit log (14.2 п.4)."""
    require_role(actor.role, "moderator", write=False)
    user = await get_user(ctx, user_id)
    await audit_log(ctx, actor.id, "license_photo_viewed", "user", user_id)
    return user.license_photo_front, user.license_photo_back


async def delete_personal_data(ctx: Ctx, actor: User, user_id: int) -> None:
    """Удаление ПД по запросу с сохранением обезличенных финансовых записей (14.2 п.11)."""
    require_role(actor.role, "admin")
    user = await get_user(ctx, user_id, for_update=True)
    user.full_name = None
    user.username = None
    user.phone = None
    user.driver_license = None
    user.license_photo_front = None
    user.license_photo_back = None
    user.access_status = "blocked"
    user.consent_at = None
    await audit_log(ctx, actor.id, "personal_data_deleted", "user", user_id)


async def cancel_accrual_by_admin(ctx: Ctx, actor: User, accrual_id: int, reason: str) -> int:
    """Аннулирование начисления (8.3 «Начисления»). Уже выведенное — только через корректировку."""
    from src.core.billing.accruals import cancel_accrual
    require_role(actor.role, "admin")
    if not reason.strip():
        raise BusinessError("err.reason_required")
    acc = await ctx.session.get(Accrual, accrual_id)
    if acc is None:
        raise NotFound("accrual", accrual_id)
    if acc.status not in ("available", "hold"):
        raise BusinessError("err.invalid_accrual_state")
    amount = await cancel_accrual(ctx, acc, f"admin: {reason}")
    await audit_log(ctx, actor.id, "accrual_cancelled", "accrual", accrual_id,
                    new_value={"amount": amount, "reason": reason})
    return amount
