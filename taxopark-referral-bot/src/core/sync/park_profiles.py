"""A12 — синхронизация базы водителей парка (каждые 6 часов)."""

from __future__ import annotations

from typing import Any

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert

from src.core.context import Ctx
from src.core.notifications.service import notify_user, sent_ever
from src.core.onboarding.validation import normalize_license, normalize_phone
from src.db import seeds
from src.db.models import Driver, ParkDriverProfile, Referral, User
from src.integrations.fleet.base import FleetDriverProfile


async def _is_new_or_unmatched(ctx: Ctx, profile_id: str) -> bool:
    row = await ctx.session.get(ParkDriverProfile, profile_id)
    return row is None or not row.license_normalized


async def upsert_park_profile(ctx: Ctx, p: FleetDriverProfile, license_normalized: str | None) -> None:
    values: dict[str, Any] = dict(
        driver_profile_id=p.id, park_id=p.park_id, phone_normalized=normalize_phone(p.phone),
        license_normalized=license_normalized, first_name=p.first_name, last_name=p.last_name,
        middle_name=p.middle_name, work_status=p.work_status, hire_date=p.hire_date, fire_date=p.fire_date,
        car_id=p.car_id, car_category=p.car_category, created_date=p.created_date, raw=p.raw, is_stale=False,
        synced_at=ctx.now(),
    )
    stmt = insert(ParkDriverProfile).values(**values)
    update_cols = {k: stmt.excluded[k] for k in values if k != "driver_profile_id"}
    if license_normalized is None:
        update_cols.pop("license_normalized")  # не затираем ранее добранный номер ВУ
    await ctx.session.execute(stmt.on_conflict_do_update(index_elements=["driver_profile_id"], set_=update_cols))


async def sync_park_driver_profiles(ctx: Ctx) -> dict[str, int]:
    assert ctx.fleet is not None
    limit = seeds.FLEET_BATCH_SIZE
    page, seen, fetched_individually = 0, set(), 0
    while True:
        batch = await ctx.fleet.list_drivers(limit=limit, offset=page * limit)
        if not batch:
            break
        for p in batch:
            if p.id in seen:  # защита от бесконечного цикла при сломанной пагинации
                continue
            lic = normalize_license(p.driver_license)
            if not lic and ctx.settings.bool("fetch_license_individually") and await _is_new_or_unmatched(ctx, p.id):
                full = await ctx.fleet.get_driver(p.id)
                lic = normalize_license(full.driver_license) if full else None
                fetched_individually += 1
            await upsert_park_profile(ctx, p, lic)
            seen.add(p.id)
        page += 1
        if len(batch) < limit:
            break
    await mark_missing_profiles_as_stale(ctx, seen)
    await sync_drivers_work_status(ctx)
    await ctx.session.commit()

    from src.core.referral.matching import match_pending_users
    linked = await match_pending_users(ctx)
    fired = await detect_fired_referrals(ctx)
    await ctx.session.commit()
    return {"profiles": len(seen), "fetched_individually": fetched_individually, "linked": linked, "fired": fired}


async def mark_missing_profiles_as_stale(ctx: Ctx, seen: set[str]) -> None:
    if not seen:
        return
    park_id = ctx.fleet.park_id if ctx.fleet else None
    q = update(ParkDriverProfile).where(ParkDriverProfile.driver_profile_id.not_in(seen))
    if park_id:
        q = q.where(ParkDriverProfile.park_id == park_id)
    await ctx.session.execute(q.values(is_stale=True))


async def sync_drivers_work_status(ctx: Ctx) -> None:
    rows = (await ctx.session.execute(
        select(Driver, ParkDriverProfile.work_status)
        .join(ParkDriverProfile, ParkDriverProfile.driver_profile_id == Driver.driver_profile_id))).all()
    for driver, status in rows:
        driver.work_status = status
        driver.last_sync_at = ctx.now()


async def detect_fired_referrals(ctx: Ctx) -> int:
    """Уведомление «друг уволился» (один раз на реферала)."""
    rows = (await ctx.session.execute(
        select(Referral, User.full_name)
        .join(Driver, Driver.user_id == Referral.referred_user_id)
        .join(ParkDriverProfile, ParkDriverProfile.driver_profile_id == Driver.driver_profile_id)
        .join(User, User.id == Referral.referred_user_id)
        .where(Referral.is_counted.is_(True), ParkDriverProfile.work_status == "fired"))).all()
    sent = 0
    for ref, name in rows:
        if await sent_ever(ctx, ref.referrer_user_id, "friend_fired", ref.id):
            continue
        await notify_user(ctx, ref.referrer_user_id, "referral.friend_fired", kind="friend_fired", subject_id=ref.id,
                          name=name or "")
        sent += 1
    return sent
