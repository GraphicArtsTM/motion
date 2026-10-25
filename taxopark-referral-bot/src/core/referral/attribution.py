"""A1 — обработка /start и создание связки. First click wins (2.11)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta

import structlog

from src.core.admin.audit import audit_log
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.referral.codes import find_user_by_referral_code
from src.core.referral.queries import get_referral_for
from src.db.models import Referral, User

log = structlog.get_logger()


@dataclass
class StartResult:
    referral: Referral | None
    outcome: str  # created | not_found | self | exists | disabled | no_payload | locked


def parse_payload(payload: str | None, allowed_tags: list[str]) -> tuple[str, str] | None:
    """'r_ABC123_wa' → ('ABC123', 'wa'). Неизвестный канал → 'other'."""
    if not payload or not payload.startswith("r_"):
        return None
    parts = payload[2:].split("_", 1)
    code = parts[0].upper()
    tag = parts[1].lower() if len(parts) > 1 else "tg"  # N4
    if tag not in allowed_tags:
        tag = "other"
    return code, tag


async def attach_referral(ctx: Ctx, user: User, code: str, source_tag: str, source: str = "link") -> StartResult:
    referrer = await find_user_by_referral_code(ctx, code)
    if referrer is None:
        log.info("referral_code_not_found", code=code)
        return StartResult(None, "not_found")
    if referrer.id == user.id:
        raise BusinessError("err.self_referral")
    if await get_referral_for(ctx, user.id) is not None:
        log.info("referral_already_attributed", user_id=user.id)
        return StartResult(None, "exists")
    if user.access_status not in ("onboarding",):
        # регистрация уже завершена — задним числом ссылку не приклеиваем
        return StartResult(None, "locked")
    if not ctx.settings.bool("program_enabled"):
        log.info("program_disabled")
        return StartResult(None, "disabled")
    now = ctx.now()
    ref = Referral(referrer_user_id=referrer.id, referred_user_id=user.id, referral_code=code, source=source,
                   source_tag=source_tag, status="clicked", is_counted=False, clicked_at=now,
                   expires_at=now + timedelta(days=ctx.settings.int("attribution_window_click_days")))
    ctx.session.add(ref)
    await ctx.session.flush()
    return StartResult(ref, "created")


async def handle_start(ctx: Ctx, user: User, payload: str | None) -> StartResult:
    parsed = parse_payload(payload, ctx.settings.list("source_tags"))
    if parsed is None:
        return StartResult(None, "no_payload")
    code, tag = parsed
    return await attach_referral(ctx, user, code, tag)


async def enter_code_manually(ctx: Ctx, user: User, code: str) -> StartResult:
    if not ctx.settings.bool("allow_manual_code_entry"):
        raise BusinessError("err.manual_code_disabled")
    result = await attach_referral(ctx, user, code.strip().upper(), "other", source="manual")
    if result.outcome == "not_found":
        raise BusinessError("err.code_not_found")
    return result


async def admin_link_referral(ctx: Ctx, *, referred_user_id: int, referrer_code: str, actor_id: int,
                              counted: bool) -> Referral:
    """Ручная привязка админом, пишется в audit log (2.11)."""
    referrer = await find_user_by_referral_code(ctx, referrer_code)
    if referrer is None:
        raise BusinessError("err.code_not_found")
    if referrer.id == referred_user_id:
        raise BusinessError("err.self_referral")
    if await get_referral_for(ctx, referred_user_id) is not None:
        raise BusinessError("err.referral_exists")
    now = ctx.now()
    ref = Referral(referrer_user_id=referrer.id, referred_user_id=referred_user_id, referral_code=referrer.referral_code,
                   source="admin", source_tag="other", status="registered", is_counted=counted, clicked_at=now,
                   registered_at=now, approved_at=now if counted else None)
    ctx.session.add(ref)
    await ctx.session.flush()
    from src.core.referral.matching import try_link_driver_profile
    user = await ctx.session.get(User, referred_user_id)
    assert user is not None
    if await try_link_driver_profile(ctx, user, actor_id=actor_id):
        ref.status = "hired"
        ref.hired_at = now
    await audit_log(ctx, actor_id, "referral_linked_manually", "referral", ref.id,
                    new_value={"referrer": referrer.id, "referred": referred_user_id, "counted": counted})
    return ref


async def admin_unlink_referral(ctx: Ctx, referral_id: int, actor_id: int) -> None:
    ref = await ctx.session.get(Referral, referral_id)
    if ref is None:
        raise BusinessError("err.not_found", entity="referral", id=str(referral_id))
    old = {"referrer": ref.referrer_user_id, "referred": ref.referred_user_id, "status": ref.status}
    ref.is_counted = False
    ref.status = "rejected"
    ref.rejected_reason = "ADMIN_UNLINK"
    await audit_log(ctx, actor_id, "referral_unlinked", "referral", ref.id, old_value=old)


async def set_is_counted(ctx: Ctx, referral_id: int, counted: bool, actor_id: int) -> None:
    ref = await ctx.session.get(Referral, referral_id)
    if ref is None:
        raise BusinessError("err.not_found", entity="referral", id=str(referral_id))
    old = ref.is_counted
    ref.is_counted = counted
    if counted and ref.status in ("rejected", "registered", "pending_approval", "expired"):
        from sqlalchemy import select

        from src.db.models import Driver
        has_driver = await ctx.session.scalar(select(Driver.id).where(Driver.user_id == ref.referred_user_id))
        ref.status = "hired" if has_driver else "registered"
        ref.rejected_reason = None
    await audit_log(ctx, actor_id, "referral_is_counted_changed", "referral", ref.id,
                    old_value={"is_counted": old}, new_value={"is_counted": counted})
