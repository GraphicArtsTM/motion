"""A2 — завершение регистрации и автопроверка по базе водителей парка (3.3)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import exists, select

from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.notifications.service import alert_admins, button, d, dt, notify_admins, notify_user, tkey
from src.core.onboarding.validation import (
    format_phone,
    mask_phone,
    normalize_license,
    normalize_phone,
    validate_full_name,
    validate_license,
)
from src.core.referral.matching import find_profile, find_profiles, link_driver_profile
from src.core.referral.queries import get_referral_for
from src.db.models import ApprovalRequest, FraudFlag, ParkDriverProfile, Referral, User

AUTOCHECK_NOT_FOUND = "NOT_FOUND"
AUTOCHECK_FOUND_AFTER_CLICK = "FOUND_AFTER_CLICK"


@dataclass
class RegistrationResult:
    outcome: str  # duplicate | already_in_park | rehire | pending
    request: ApprovalRequest | None = None


async def user_exists_with(ctx: Ctx, *, phone: str | None = None, driver_license: str | None = None,
                           exclude: int) -> bool:
    cond = User.phone == phone if phone else User.driver_license == driver_license
    return bool(await ctx.session.scalar(select(exists().where(cond, User.id != exclude))))


async def flag_fraud(ctx: Ctx, *, rule: str, referral: Referral | None = None, user_id: int | None = None,
                     details: dict[str, object] | None = None, resolved: bool = False) -> FraudFlag:
    cfg = (ctx.settings.json("fraud_rules") or {}).get(rule, {})
    flag = FraudFlag(referral_id=referral.id if referral else None, user_id=user_id, rule_code=rule,
                     severity=cfg.get("severity", "medium"), score=int(cfg.get("score", 0)), details=details,
                     resolved=resolved, resolved_at=ctx.now() if resolved else None, created_at=ctx.now())
    ctx.session.add(flag)
    if referral is not None and not resolved:
        referral.risk_score = min(100, referral.risk_score + flag.score)
    await ctx.session.flush()
    return flag


async def notify_referrer(ctx: Ctx, ref: Referral, key: str, **params: object) -> None:
    friend = await ctx.session.get(User, ref.referred_user_id)
    await notify_user(ctx, ref.referrer_user_id, key, name=(friend.full_name if friend else "") or "", **params)


async def save_contact(ctx: Ctx, user: User, raw_phone: str) -> str:
    phone = normalize_phone(raw_phone)
    if phone is None:
        raise BusinessError("err.invalid_phone")
    if await user_exists_with(ctx, phone=phone, exclude=user.id):
        await alert_admins(ctx, "duplicate_registration", user_id=user.id, field="phone")
        raise BusinessError("err.duplicate_identity")
    return phone


async def finish_registration(ctx: Ctx, user: User, phone: str, full_name: str, driver_license: str,
                              license_photos: tuple[str | None, str | None]) -> RegistrationResult:
    s = ctx.settings
    phone_n = normalize_phone(phone)
    if phone_n is None:
        raise BusinessError("err.invalid_phone")
    lic_check = validate_license(driver_license, s.str("driver_license_regex"))
    if not lic_check.ok or lic_check.value is None:
        raise BusinessError("err.invalid_license")
    lic = lic_check.value
    name = validate_full_name(full_name)
    if name is None:
        raise BusinessError("err.invalid_name")
    if s.bool("require_license_photo") and not (license_photos[0] and license_photos[1]):
        raise BusinessError("err.license_photo_required")

    ref = await get_referral_for(ctx, user.id, for_update=True)
    dup_phone = await user_exists_with(ctx, phone=phone_n, exclude=user.id)
    dup_lic = await user_exists_with(ctx, driver_license=lic, exclude=user.id)
    if dup_phone or dup_lic:
        if dup_lic:
            await flag_fraud(ctx, rule="DUPLICATE_LICENSE", referral=ref, user_id=user.id,
                             details={"license": lic})
        await alert_admins(ctx, "duplicate_registration", user_id=user.id,
                           field="license" if dup_lic else "phone")
        await ctx.session.commit()
        return RegistrationResult("duplicate")

    # SELF_REF: данные реферала совпадают с данными пригласившего
    if ref is not None:
        referrer = await ctx.session.get(User, ref.referrer_user_id)
        if referrer and (referrer.phone == phone_n or referrer.driver_license == lic
                         or referrer.telegram_id == user.telegram_id):
            await flag_fraud(ctx, rule="SELF_REF", referral=ref, user_id=user.id)

    user.phone, user.phone_verified_at = phone_n, ctx.now()
    user.full_name, user.driver_license = name, lic
    user.license_photo_front, user.license_photo_back = license_photos
    now = ctx.now()

    # ── E5: окно клика проверяется здесь, а не только в cron ──
    if ref and ref.status == "clicked" and now > ref.clicked_at + timedelta(days=s.int("attribution_window_click_days")):
        ref.status, ref.is_counted = "expired", False
        await notify_referrer(ctx, ref, "referral.expired", days=s.int("attribution_window_click_days"))
        ref = None  # дальше как будто ссылки не было
    elif ref and ref.status != "clicked":
        ref = None

    if lic_check.needs_admin_flag:
        await flag_fraud(ctx, rule="LICENSE_FORMAT", referral=ref, user_id=user.id, details={"license": lic},
                         resolved=True)

    profile = await find_profile(ctx, phone_n, lic)
    click_at = ref.clicked_at if ref else now
    treat_new = s.bool("treat_post_click_profile_as_new")

    # REHIRE (3.3): работал в парке в последние rehire_block_days — рефералка не засчитывается,
    # доступ открывается, админу уведомление (D-04)
    rehire_border = (now - timedelta(days=s.int("rehire_block_days"))).date()
    fired_recently = next((p for p in await find_profiles(ctx, phone_n, lic)
                           if p.fire_date and p.fire_date > rehire_border), None)

    # СЛУЧАЙ 1: уже был в парке до клика
    existing = profile is not None and profile.created_date is not None and (
        profile.created_date < click_at or not treat_new)
    if profile is not None and (existing or fired_recently is not None):
        await link_driver_profile(ctx, user, profile)
        user.access_status = "approved"
        outcome = "already_in_park"
        if ref:
            ref.status, ref.is_counted = "rejected", False
            ref.registered_at = now
            if fired_recently is not None and not existing:
                ref.rejected_reason = "REHIRE"
                await flag_fraud(ctx, rule="REHIRE", referral=ref, user_id=user.id,
                                 details={"fire_date": fired_recently.fire_date.isoformat()
                                          if fired_recently.fire_date else None})
                await alert_admins(ctx, "rehire_detected", user_id=user.id, referral_id=ref.id)
                outcome = "rehire"
            else:
                ref.rejected_reason = "EXISTING_DRIVER"
            await notify_referrer(ctx, ref, "referral.not_counted_existing")
        await notify_user(ctx, user.id, "onboarding.already_in_park")
        await ctx.session.commit()
        return RegistrationResult(outcome)

    # СЛУЧАЙ 2: модерация
    if fired_recently is not None and ref:
        await flag_fraud(ctx, rule="REHIRE", referral=ref, user_id=user.id)

    user.access_status = "pending_approval"
    if ref:
        ref.status, ref.registered_at = "pending_approval", now
        ref.expires_at = now + timedelta(days=s.int("attribution_window_approval_days"))
        await notify_referrer(ctx, ref, "referral.pending")
    req = ApprovalRequest(user_id=user.id, referral_id=ref.id if ref else None,
                          found_profile_id=profile.driver_profile_id if profile else None,
                          autocheck_result=AUTOCHECK_FOUND_AFTER_CLICK if profile else AUTOCHECK_NOT_FOUND,
                          status="pending", created_at=now)
    ctx.session.add(req)
    await ctx.session.flush()
    await notify_admins_new_request(ctx, req)
    await ctx.session.commit()
    return RegistrationResult("pending", req)


async def approval_card_params(ctx: Ctx, req: ApprovalRequest) -> dict[str, object]:
    user = await ctx.session.get(User, req.user_id)
    assert user is not None
    ref = await ctx.session.get(Referral, req.referral_id) if req.referral_id else None
    referrer = await ctx.session.get(User, ref.referrer_user_id) if ref else None
    flags = (await ctx.session.execute(
        select(FraudFlag.rule_code).where(FraudFlag.user_id == user.id, FraudFlag.resolved.is_(False))
    )).scalars().all()
    lic_flag = (await ctx.session.execute(
        select(FraudFlag.rule_code).where(FraudFlag.user_id == user.id, FraudFlag.rule_code == "LICENSE_FORMAT")
    )).scalars().all()
    profile = await ctx.session.get(ParkDriverProfile, req.found_profile_id) if req.found_profile_id else None
    return {
        "request_id": req.id,
        "name": user.full_name or "",
        "phone": format_phone(user.phone),
        "license": user.driver_license or "",
        "referrer": (f"{referrer.full_name or ''} ({mask_phone(referrer.phone)}), {referrer.referral_code}"
                     if referrer else tkey("admin.no_referrer")),
        "channel": tkey(f"channel.{ref.source_tag}") if ref else "—",
        "clicked_at": dt(ref.clicked_at) if ref else "—",
        "created_at": dt(req.created_at),
        "autocheck": tkey("admin.autocheck.found" if profile else "admin.autocheck.not_found",
                          profile=profile.driver_profile_id if profile else ""),
        "flags": ", ".join([*flags, *lic_flag]) or tkey("admin.flags_none"),
    }


async def notify_admins_new_request(ctx: Ctx, req: ApprovalRequest) -> None:
    user = await ctx.session.get(User, req.user_id)
    assert user is not None
    params = await approval_card_params(ctx, req)
    buttons = [
        [button("admin.btn.approve_with_referral", f"ap:with:{req.id}")] if req.referral_id else [],
        [button("admin.btn.approve_without_referral", f"ap:without:{req.id}")],
        [button("admin.btn.reject", f"ap:reject:{req.id}")],
        [button("admin.btn.photo_front", f"ap:photo:f:{req.id}"), button("admin.btn.photo_back", f"ap:photo:b:{req.id}")],
    ]
    await notify_admins(ctx, "admin.approval_card", buttons=[row for row in buttons if row], **params)


async def pending_screen_params(ctx: Ctx, user: User) -> dict[str, object]:
    req = (await ctx.session.execute(
        select(ApprovalRequest).where(ApprovalRequest.user_id == user.id)
        .order_by(ApprovalRequest.id.desc()).limit(1))).scalar_one_or_none()
    return {"park_contacts": ctx.settings.str("park_contacts"), "date": d(req.created_at if req else ctx.now())}


def normalize_inputs(phone: str, license_: str) -> tuple[str | None, str | None]:
    return normalize_phone(phone), normalize_license(license_)
