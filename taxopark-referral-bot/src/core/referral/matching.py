"""Привязка профиля Fleet к пользователю (3.6) и фоновый поиск (match_pending_referrals)."""

from __future__ import annotations

from sqlalchemy import or_, select

from src.core.admin.audit import audit_log
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.notifications.service import alert_admins
from src.db.models import Driver, ParkDriverProfile, Referral, User


async def find_profiles(ctx: Ctx, phone: str | None, license_: str | None) -> list[ParkDriverProfile]:
    """Все профили по телефону или ВУ; свежие (по created_date) — первыми."""
    conds = []
    if phone:
        conds.append(ParkDriverProfile.phone_normalized == phone)
    if license_:
        conds.append(ParkDriverProfile.license_normalized == license_)
    if not conds:
        return []
    q = select(ParkDriverProfile).where(or_(*conds))
    park_id = _park_id(ctx)
    if park_id:  # N8: все запросы фильтруются по park_id
        q = q.where(ParkDriverProfile.park_id == park_id)
    rows = (await ctx.session.execute(
        q.order_by(ParkDriverProfile.created_date.desc().nulls_last()))).scalars().all()
    return list(rows)


def _park_id(ctx: Ctx) -> str:
    from src.config import get_config
    return ctx.fleet.park_id if ctx.fleet is not None and ctx.fleet.park_id else get_config().fleet_park_id


async def find_profile(ctx: Ctx, phone: str | None, license_: str | None) -> ParkDriverProfile | None:
    """park_profiles.find_by_phone(phone) or park_profiles.find_by_license(lic)."""
    profiles = await find_profiles(ctx, phone, None)
    if not profiles:
        profiles = await find_profiles(ctx, None, license_)
    return profiles[0] if profiles else None


async def link_driver_profile(ctx: Ctx, user: User, profile: ParkDriverProfile, actor_id: int | None = None) -> Driver:
    existing = (await ctx.session.execute(select(Driver).where(Driver.user_id == user.id))).scalar_one_or_none()
    if existing is not None:
        return existing
    taken = (await ctx.session.execute(
        select(Driver).where(Driver.driver_profile_id == profile.driver_profile_id))).scalar_one_or_none()
    if taken is not None:
        raise BusinessError("err.profile_already_linked")
    d = Driver(user_id=user.id, driver_profile_id=profile.driver_profile_id, work_status=profile.work_status,
               linked_at=ctx.now(), linked_by=actor_id, last_sync_at=profile.synced_at)
    ctx.session.add(d)
    await ctx.session.flush()
    return d


async def try_link_driver_profile(ctx: Ctx, user: User, actor_id: int | None = None) -> bool:
    profile = await find_profile(ctx, user.phone, user.driver_license)
    if profile is None:
        return False
    try:
        await link_driver_profile(ctx, user, profile, actor_id)
    except BusinessError:
        await alert_admins(ctx, "profile_conflict", user_id=user.id, profile_id=profile.driver_profile_id)
        return False
    return True


async def admin_link_profile(ctx: Ctx, user_id: int, driver_profile_id: str, actor_id: int) -> Driver:
    user = await ctx.session.get(User, user_id)
    profile = await ctx.session.get(ParkDriverProfile, driver_profile_id)
    if user is None or profile is None:
        raise BusinessError("err.not_found", entity="profile", id=driver_profile_id)
    d = await link_driver_profile(ctx, user, profile, actor_id)
    await _mark_hired(ctx, user.id)
    await audit_log(ctx, actor_id, "driver_profile_linked", "user", user_id, new_value={"profile": driver_profile_id})
    return d


async def admin_unlink_profile(ctx: Ctx, user_id: int, actor_id: int) -> None:
    d = (await ctx.session.execute(select(Driver).where(Driver.user_id == user_id))).scalar_one_or_none()
    if d is None:
        return
    await audit_log(ctx, actor_id, "driver_profile_unlinked", "user", user_id, old_value={"profile": d.driver_profile_id})
    await ctx.session.delete(d)


async def _mark_hired(ctx: Ctx, user_id: int) -> None:
    ref = (await ctx.session.execute(select(Referral).where(Referral.referred_user_id == user_id))).scalar_one_or_none()
    if ref is not None and ref.is_counted and ref.status == "registered":
        ref.status = "hired"
        ref.hired_at = ctx.now()


async def match_pending_users(ctx: Ctx) -> int:
    """Подтверждённые пользователи без привязанного профиля — ищем профиль (ежечасно и после синка)."""
    users = (await ctx.session.execute(
        select(User).where(User.access_status == "approved", User.role == "driver",
                           ~select(Driver.id).where(Driver.user_id == User.id).exists())
    )).scalars().all()
    linked = 0
    for u in users:
        if await try_link_driver_profile(ctx, u):
            await _mark_hired(ctx, u.id)
            linked += 1
    await ctx.session.commit()
    return linked
