"""A13 — синхронизация заказов (каждые 30 минут) + автозапуск A17 для закрытых периодов."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert

from src.core.context import Ctx
from src.core.scoring.coefficients import register_tariff_if_unknown, resolve_tariff
from src.db import seeds
from src.db.models import Order, ParkDriverProfile, Period, SyncCursor
from src.integrations.fleet.base import FleetOrder

CURSOR = "orders"


async def get_sync_cursor(ctx: Ctx, name: str) -> datetime | None:
    row = await ctx.session.get(SyncCursor, name)
    return row.cursor_at if row else None


async def set_sync_cursor(ctx: Ctx, name: str, at: datetime) -> None:
    stmt = insert(SyncCursor).values(name=name, cursor_at=at, updated_at=ctx.now())
    await ctx.session.execute(stmt.on_conflict_do_update(index_elements=["name"],
                                                         set_={"cursor_at": at, "updated_at": ctx.now()}))


async def upsert_orders(ctx: Ctx, batch: list[FleetOrder]) -> None:
    for o in batch:
        values: dict[str, Any] = dict(
            external_order_id=o.id, driver_profile_id=o.driver_profile_id, tariff_class=o.tariff_class,
            tariff_source=o.tariff_source, status=o.status, price=o.price, distance_m=o.distance_m,
            duration_sec=o.duration_sec, booked_at=o.booked_at, ended_at=o.ended_at,
            payment_method=o.payment_method, address_from=o.address_from, address_to=o.address_to,
            raw=o.raw or None, synced_at=ctx.now(),
        )
        stmt = insert(Order).values(**values)
        await ctx.session.execute(stmt.on_conflict_do_update(
            index_elements=["external_order_id"],
            set_={k: stmt.excluded[k] for k in values if k != "external_order_id"}))


async def _car_categories(ctx: Ctx, batch: list[FleetOrder]) -> dict[str, str | None]:
    ids = list({o.driver_profile_id for o in batch})
    rows = (await ctx.session.execute(
        select(ParkDriverProfile.driver_profile_id, ParkDriverProfile.car_category)
        .where(ParkDriverProfile.driver_profile_id.in_(ids)))).all()
    return {pid: cat for pid, cat in rows}


def _fingerprint(o: Any) -> tuple[Any, ...]:
    return (o.driver_profile_id, o.status, o.price, o.distance_m, o.duration_sec, o.ended_at, o.tariff_class)


async def _known_orders(ctx: Ctx, ids: list[str]) -> dict[str, tuple[Any, ...]]:
    if not ids:
        return {}
    rows = (await ctx.session.execute(select(Order).where(Order.external_order_id.in_(ids)))).scalars().all()
    return {r.external_order_id: _fingerprint(r) for r in rows}


async def sync_orders(ctx: Ctx, *, recalc_closed: bool = True) -> dict[str, Any]:
    from src.core.billing.periods import ensure_current_period, period_of
    from src.core.billing.recalculation import recalculate_closed_period
    from src.core.notifications.progress import check_first_rides
    from src.core.sync.stats import rebuild_daily_stats

    assert ctx.fleet is not None
    await ensure_current_period(ctx)  # E4
    now = ctx.now()
    window = timedelta(hours=ctx.settings.int("late_orders_window_hours"))
    cursor = await get_sync_cursor(ctx, CURSOR)
    # перекрытие окном опозданий: заказ может «закрыться» в Fleet позже своего ended_at
    since = min(cursor, now - window) if cursor else now - window
    limit = seeds.FLEET_BATCH_SIZE
    page, total, touched_periods = 0, 0, set()
    seen: set[str] = set()
    while True:
        batch = await ctx.fleet.list_orders(from_dt=since, to_dt=now, limit=limit, offset=page * limit)
        if not batch:
            break
        batch = [o for o in batch if o.id not in seen]
        cats = await _car_categories(ctx, batch)
        known = await _known_orders(ctx, [o.id for o in batch])
        for o in batch:
            seen.add(o.id)
            o.tariff_class, o.tariff_source = await resolve_tariff(ctx, o.tariff_class, o.driver_profile_id,
                                                                   cats.get(o.driver_profile_id))
            await register_tariff_if_unknown(ctx, o.tariff_class)
            if _fingerprint(o) == known.get(o.id):
                continue  # без изменений — пересчёт не нужен
            p = await period_of(ctx, o.ended_at)
            if p and p.status == "closed":
                touched_periods.add(p.id)
        await upsert_orders(ctx, batch)
        total += len(batch)
        page += 1
        if len(batch) < limit or not batch:
            break

    await rebuild_daily_stats(ctx, since)
    await set_sync_cursor(ctx, CURSOR, now)
    await ctx.session.commit()
    await check_first_rides(ctx)

    recalculated = []
    if recalc_closed:
        for pid in touched_periods:  # E3
            period = await ctx.session.get(Period, pid)
            if period and period.closed_at and now - period.closed_at <= window:
                await recalculate_closed_period(ctx, period, reason="late_orders")
                recalculated.append(period.code)
    return {"orders": total, "recalculated": recalculated}
