"""A14 — время на линии (ежедневно)."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert

from src.core.clock import local_date
from src.core.context import Ctx
from src.db.models import Driver, DriverOnlineTime
from src.integrations.fleet.errors import FleetError


async def upsert_online_time(ctx: Ctx, driver_profile_id: str, day: object, secs: int) -> None:
    stmt = insert(DriverOnlineTime).values(driver_profile_id=driver_profile_id, stat_date=day,
                                           online_seconds=secs, synced_at=ctx.now())
    await ctx.session.execute(stmt.on_conflict_do_update(
        index_elements=["driver_profile_id", "stat_date"],
        set_={"online_seconds": stmt.excluded.online_seconds, "synced_at": stmt.excluded.synced_at}))


async def sync_driver_online_time(ctx: Ctx) -> int:
    assert ctx.fleet is not None
    days = ctx.settings.int("online_time_sync_days")
    today = local_date(ctx.now())
    profile_ids = (await ctx.session.execute(select(Driver.driver_profile_id))).scalars().all()
    written = 0
    for pid in profile_ids:
        for i in range(days):
            day = today - timedelta(days=i)
            try:
                secs = await ctx.fleet.get_driver_online_time(pid, day)
            except FleetError:
                continue
            await upsert_online_time(ctx, pid, day, secs)
            written += 1
        await ctx.session.commit()
    return written
