"""TC-01…TC-23: условия, регистрация, автопроверка, модерация, атрибуция."""

from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import func, select

from src.core.errors import BusinessError
from src.core.onboarding.access import screen_allowed
from src.core.onboarding.approval import admin_decide, expire_referrals
from src.core.onboarding.registration import finish_registration
from src.core.onboarding.terms import (
    accept_current_terms,
    create_terms_draft,
    current_terms,
    has_accepted_current_terms,
    publish_terms,
)
from src.core.onboarding.validation import normalize_license, normalize_phone, validate_license
from src.core.referral.attribution import enter_code_manually, handle_start
from src.core.referral.codes import get_or_create_user
from src.db.models import ApprovalRequest, AuditLog, Driver, FraudFlag, Referral, User, UserTermsAcceptance
from tests.factories import add_profile, create_user, outbox_keys

PHOTOS = ("file-front", "file-back")


async def new_user(ctx, tg: int, *, consent=True, terms=True) -> User:
    user, _ = await get_or_create_user(ctx, tg)
    if consent:
        user.consent_at = ctx.now()
    if terms:
        await accept_current_terms(ctx, user.id)
    await ctx.session.flush()
    return user


async def invited(ctx, referrer: User, tg: int, payload_suffix="") -> tuple[User, Referral]:
    user = await new_user(ctx, tg)
    res = await handle_start(ctx, user, f"r_{referrer.referral_code}{payload_suffix}")
    assert res.outcome == "created"
    return user, res.referral


# ── условия программы ─────────────────────────────────────────────────────────
async def test_registration_requires_terms_tc01_tc02(ctx):
    user = await new_user(ctx, 1, terms=False)
    with pytest.raises(BusinessError) as e:
        await finish_registration(ctx, user, "+998901112233", "Каримов Азиз", "AB1234567", PHOTOS)
    assert e.value.key == "err.terms_not_accepted"
    terms = await accept_current_terms(ctx, user.id)
    row = (await ctx.session.execute(select(UserTermsAcceptance).where(UserTermsAcceptance.user_id == user.id))).scalar_one()
    assert row.terms_id == terms.id and row.accepted_at is not None and terms.version == 1


async def test_new_version_requires_acceptance_tc03_tc04(ctx):
    user = await create_user(ctx)
    admin = await create_user(ctx, role="admin")
    assert await has_accepted_current_terms(ctx, user.id)
    draft = await create_terms_draft(ctx, actor_id=admin.id, text_ru="v2", text_uz_latn="v2", text_uz_cyrl="v2")
    await publish_terms(ctx, draft.id, admin.id)
    assert not await has_accepted_current_terms(ctx, user.id)
    assert screen_allowed("approved", False, "wallet") == (False, "terms")
    assert screen_allowed("approved", False, "withdraw") == (False, "terms")
    assert screen_allowed("approved", False, "link") == (False, "terms")
    assert screen_allowed("approved", False, "support") == (True, None)
    assert "terms.updated" in await outbox_keys(ctx, user.id)


async def test_terms_in_three_languages_tc05(ctx):
    t = await current_terms(ctx)
    texts = {lang: t.text_for(lang) for lang in ("ru", "uz_latn", "uz_cyrl")}
    assert len(set(texts.values())) == 3 and all("{coefficients_table}" in v for v in texts.values())


# ── регистрация ──────────────────────────────────────────────────────────────
async def test_full_registration_pending_tc06_tc13(ctx):
    user = await new_user(ctx, 10)
    res = await finish_registration(ctx, user, "998 90 111 22 33", "Каримов Азиз Бахтиёрович", "ab 123-4567", PHOTOS)
    assert res.outcome == "pending" and user.access_status == "pending_approval"
    assert user.phone == "+998901112233" and user.driver_license == "AB1234567" and len(user.referral_code) == 6
    assert "admin.approval_card" in await outbox_keys(ctx)
    assert screen_allowed("pending_approval", True, "wallet") == (False, "pending")  # TC-12
    from src.core.onboarding.registration import pending_screen_params
    assert (await pending_screen_params(ctx, user))["park_contacts"] == ctx.settings.str("park_contacts")  # TC-13


def test_license_validation_tc07_tc08():
    regex = r"^[A-Z]{2}\d{7}$"
    assert normalize_license("ab 123-4567") == "AB1234567"
    assert validate_license("ab 123-4567", regex).ok
    assert not validate_license("12", regex).ok
    flagged = validate_license("UZ12345678", regex)
    assert flagged.ok and flagged.needs_admin_flag
    assert normalize_phone("+998 (90) 123-45-67") == "+998901234567"
    assert normalize_phone("901234567") == "+998901234567"
    assert normalize_phone("+7 900 123 45 67") is None


async def test_duplicate_phone_tc09(ctx):
    await create_user(ctx, phone="+998901112233")
    user = await new_user(ctx, 11)
    res = await finish_registration(ctx, user, "+998901112233", "Каримов Азиз", "AB7654321", PHOTOS)
    assert res.outcome == "duplicate"
    assert "admin.alert.duplicate_registration" in await outbox_keys(ctx)


async def test_duplicate_license_tc10(ctx):
    await create_user(ctx, license_="AB1234567")
    user = await new_user(ctx, 12)
    res = await finish_registration(ctx, user, "+998901112299", "Каримов Азиз", "AB1234567", PHOTOS)
    assert res.outcome == "duplicate"
    flags = (await ctx.session.execute(select(FraudFlag.rule_code))).scalars().all()
    assert flags == ["DUPLICATE_LICENSE"]


async def test_click_window_checked_at_registration_tc11(ctx, clock):
    referrer = await create_user(ctx)
    user, ref = await invited(ctx, referrer, 13)
    clock.advance(days=31)
    res = await finish_registration(ctx, user, "+998901112244", "Каримов Азиз", "AB1234561", PHOTOS)
    assert res.outcome == "pending" and ref.status == "expired" and not ref.is_counted
    assert res.request.referral_id is None
    assert "referral.expired" in await outbox_keys(ctx, referrer.id)


async def test_profile_before_click_tc14(ctx, clock):
    referrer = await create_user(ctx)
    await add_profile(ctx, phone="+998901112255", created_date=clock.now() - timedelta(days=100))
    user, ref = await invited(ctx, referrer, 14)
    res = await finish_registration(ctx, user, "+998901112255", "Каримов Азиз", "AB1234562", PHOTOS)
    assert res.outcome == "already_in_park" and user.access_status == "approved"
    assert not ref.is_counted and ref.rejected_reason == "EXISTING_DRIVER"
    assert "onboarding.already_in_park" in await outbox_keys(ctx, user.id)
    assert "referral.not_counted_existing" in await outbox_keys(ctx, referrer.id)
    assert await ctx.session.scalar(select(func.count()).select_from(ApprovalRequest)) == 0


async def test_profile_after_click_goes_to_moderation_tc15(ctx, clock):
    referrer = await create_user(ctx)
    user, ref = await invited(ctx, referrer, 15)
    clock.advance(days=2)
    await add_profile(ctx, phone="+998901112266", created_date=clock.now() - timedelta(days=1))
    res = await finish_registration(ctx, user, "+998901112266", "Каримов Азиз", "AB1234563", PHOTOS)
    assert res.outcome == "pending" and res.request.autocheck_result == "FOUND_AFTER_CLICK"
    assert ref.status == "pending_approval"
    assert "referral.pending" in await outbox_keys(ctx, referrer.id)


async def test_rehire(ctx, clock):
    referrer = await create_user(ctx)
    await add_profile(ctx, phone="+998901112267", created_date=clock.now() + timedelta(seconds=1),
                      work_status="fired", fire_date=(clock.now() - timedelta(days=10)).date())
    user, ref = await invited(ctx, referrer, 16)
    res = await finish_registration(ctx, user, "+998901112267", "Каримов Азиз", "AB1234564", PHOTOS)
    assert res.outcome == "rehire" and user.access_status == "approved"
    assert ref.rejected_reason == "REHIRE" and not ref.is_counted
    assert "admin.alert.rehire_detected" in await outbox_keys(ctx)


async def test_source_tag_tc16(ctx):
    referrer = await create_user(ctx)
    _, ref = await invited(ctx, referrer, 17, "_wa")
    assert ref.source_tag == "wa"
    user = await new_user(ctx, 18)
    res = await handle_start(ctx, user, f"r_{referrer.referral_code.lower()}_xyz")
    assert res.referral.source_tag == "other"


async def test_self_referral_and_first_click_wins(ctx):
    referrer = await create_user(ctx, access_status="onboarding")
    with pytest.raises(BusinessError):
        await handle_start(ctx, referrer, f"r_{referrer.referral_code}")
    other = await create_user(ctx)
    user, ref = await invited(ctx, referrer, 19)
    second = await handle_start(ctx, user, f"r_{other.referral_code}")
    assert second.outcome == "exists" and ref.referrer_user_id == referrer.id
    assert (await handle_start(ctx, user, "r_NOPE00")).outcome == "not_found"


async def test_manual_code_entry(ctx):
    referrer = await create_user(ctx)
    user = await new_user(ctx, 20)
    res = await enter_code_manually(ctx, user, f" {referrer.referral_code.lower()} ")
    assert res.referral.source == "manual"
    await ctx.settings.set(ctx.session, "allow_manual_code_entry", False, None)
    with pytest.raises(BusinessError):
        await enter_code_manually(ctx, await new_user(ctx, 21), referrer.referral_code)


async def test_program_disabled_no_attribution(ctx):
    await ctx.settings.set(ctx.session, "program_enabled", False, None)
    referrer = await create_user(ctx)
    user = await new_user(ctx, 22)
    assert (await handle_start(ctx, user, f"r_{referrer.referral_code}")).outcome == "disabled"


# ── модерация ────────────────────────────────────────────────────────────────
async def _pending(ctx, referrer, tg, phone, profile=False):
    user, ref = await invited(ctx, referrer, tg)
    if profile:
        await add_profile(ctx, phone=phone, created_date=ctx.now() + timedelta(seconds=5))
    res = await finish_registration(ctx, user, phone, "Каримов Азиз", f"AB{tg:07d}", PHOTOS)
    return user, ref, res.request


async def test_approve_with_referral_tc17_tc20_tc23(ctx):
    referrer = await create_user(ctx)
    moder = await create_user(ctx, role="moderator")
    user, ref, req = await _pending(ctx, referrer, 30, "+998901113030", profile=True)
    await admin_decide(ctx, req.id, moder, "approve_with_referral")
    assert user.access_status == "approved" and ref.is_counted and ref.status == "hired"
    assert await ctx.session.scalar(select(Driver.driver_profile_id).where(Driver.user_id == user.id))
    assert "onboarding.approved" in await outbox_keys(ctx, user.id)
    assert "referral.counted" in await outbox_keys(ctx, referrer.id)
    log = (await ctx.session.execute(select(AuditLog).where(AuditLog.action == "approval_decision"))).scalar_one()
    assert log.new_value == "approve_with_referral" and log.actor_user_id == moder.id


async def test_approve_without_referral_tc18(ctx):
    referrer = await create_user(ctx)
    moder = await create_user(ctx, role="moderator")
    user, ref, req = await _pending(ctx, referrer, 31, "+998901113031", profile=True)
    await admin_decide(ctx, req.id, moder, "approve_without_referral")
    assert user.access_status == "approved" and not ref.is_counted
    assert "referral.not_counted" in await outbox_keys(ctx, referrer.id)


async def test_reject_tc19(ctx):
    referrer = await create_user(ctx)
    moder = await create_user(ctx, role="moderator")
    user, ref, req = await _pending(ctx, referrer, 32, "+998901113032")
    with pytest.raises(BusinessError):
        await admin_decide(ctx, req.id, moder, "reject", "")
    await admin_decide(ctx, req.id, moder, "reject", "Документы не прошли проверку")
    assert user.access_status == "rejected" and not ref.is_counted
    assert screen_allowed("rejected", True, "wallet")[0] is False
    assert "onboarding.rejected" in await outbox_keys(ctx, user.id)
    assert "referral.not_counted" in await outbox_keys(ctx, referrer.id)


async def test_profile_not_found_then_background_match_tc21(ctx):
    from src.core.referral.matching import match_pending_users
    referrer = await create_user(ctx)
    moder = await create_user(ctx, role="moderator")
    user, ref, req = await _pending(ctx, referrer, 33, "+998901113033")
    await admin_decide(ctx, req.id, moder, "approve_with_referral")
    assert ref.status == "registered"
    assert "admin.alert.profile_not_found_after_approval" in await outbox_keys(ctx)
    await add_profile(ctx, phone="+998901113033")
    assert await match_pending_users(ctx) == 1
    ref = await ctx.session.get(Referral, ref.id, populate_existing=True)
    assert ref.status == "hired"


async def test_operator_cannot_decide(ctx):
    referrer = await create_user(ctx)
    op = await create_user(ctx, role="operator")
    _, _, req = await _pending(ctx, referrer, 34, "+998901113034")
    with pytest.raises(BusinessError):
        await admin_decide(ctx, req.id, op, "approve_with_referral")


async def test_approval_window_expired_tc22(ctx, clock):
    referrer = await create_user(ctx)
    moder = await create_user(ctx, role="moderator")
    user, ref, req = await _pending(ctx, referrer, 35, "+998901113035")
    clock.advance(days=46)
    assert (await expire_referrals(ctx))["approval"] == 1
    ref = await ctx.session.get(Referral, ref.id, populate_existing=True)
    assert ref.status == "expired"
    await admin_decide(ctx, req.id, moder, "approve_with_referral")
    assert not (await ctx.session.get(Referral, ref.id, populate_existing=True)).is_counted
