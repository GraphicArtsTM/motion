"""Квалификации рефералов по периодам."""

from __future__ import annotations

from typing import Any

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert

from src.core.context import Ctx
from src.db.models import Qualification, Referral


async def upsert_qualification(ctx: Ctx, *, referral_id: int, period_id: int, eligible_orders_count: int,
                               points_x100: int, threshold_points_x100: int, achieved_percent: int,
                               is_qualified: bool, breakdown: Any) -> None:
    values = dict(referral_id=referral_id, period_id=period_id, eligible_orders_count=eligible_orders_count,
                  points_x100=points_x100, threshold_points_x100=threshold_points_x100,
                  achieved_percent=achieved_percent, is_qualified=is_qualified, breakdown=breakdown,
                  computed_at=ctx.now())
    stmt = insert(Qualification).values(**values)
    stmt = stmt.on_conflict_do_update(index_elements=["referral_id", "period_id"],
                                      set_={k: stmt.excluded[k] for k in values if k not in ("referral_id", "period_id")})
    await ctx.session.execute(stmt)


async def get_qualification(ctx: Ctx, referral_id: int, period_id: int) -> Qualification | None:
    return (await ctx.session.execute(
        select(Qualification).where(Qualification.referral_id == referral_id, Qualification.period_id == period_id)
        .execution_options(populate_existing=True)
    )).scalar_one_or_none()


async def qualifications_for_referrer(ctx: Ctx, period_id: int, referrer_id: int,
                                      only_qualified: bool = True) -> list[Qualification]:
    q = (select(Qualification).join(Referral, Referral.id == Qualification.referral_id)
         .where(Qualification.period_id == period_id, Referral.referrer_user_id == referrer_id,
                Referral.is_counted.is_(True), Referral.is_fraud.is_(False))
         .order_by(Qualification.referral_id)
         .execution_options(populate_existing=True))
    if only_qualified:
        q = q.where(Qualification.is_qualified.is_(True))
    return list((await ctx.session.execute(q)).scalars().all())


async def count_distinct_qualified_referrals_lifetime(ctx: Ctx, referrer_id: int) -> int:
    return int(await ctx.session.scalar(
        select(func.count(func.distinct(Referral.id)))
        .select_from(Referral).join(Qualification, Qualification.referral_id == Referral.id)
        .where(Referral.referrer_user_id == referrer_id, Referral.is_counted.is_(True),
               Referral.is_fraud.is_(False), Qualification.is_qualified.is_(True))
    ) or 0)


async def users_with_counted_referrals(ctx: Ctx) -> list[int]:
    return list((await ctx.session.execute(
        select(Referral.referrer_user_id).where(Referral.is_counted.is_(True))
        .group_by(Referral.referrer_user_id).order_by(Referral.referrer_user_id)
    )).scalars().all())
