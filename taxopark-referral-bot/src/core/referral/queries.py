"""Общие выборки по рефералам."""

from __future__ import annotations

from collections.abc import Sequence

from sqlalchemy import select

from src.core.context import Ctx
from src.db.models import Driver, Referral


async def referrals_with_profiles(
    ctx: Ctx, *, statuses: Sequence[str] | None = None, referrer_id: int | None = None,
    counted_only: bool = True,
) -> list[tuple[Referral, str | None]]:
    q = (select(Referral, Driver.driver_profile_id)
         .outerjoin(Driver, Driver.user_id == Referral.referred_user_id)
         .order_by(Referral.id))
    if counted_only:
        q = q.where(Referral.is_counted.is_(True), Referral.is_fraud.is_(False))
    if statuses:
        q = q.where(Referral.status.in_(list(statuses)))
    if referrer_id is not None:
        q = q.where(Referral.referrer_user_id == referrer_id)
    return [(r, pid) for r, pid in (await ctx.session.execute(q)).all()]


async def get_referral_for(ctx: Ctx, referred_user_id: int, *, for_update: bool = False) -> Referral | None:
    q = select(Referral).where(Referral.referred_user_id == referred_user_id)
    if for_update:
        q = q.with_for_update()
    return (await ctx.session.execute(q)).scalar_one_or_none()


async def driver_profile_id_of(ctx: Ctx, user_id: int) -> str | None:
    return await ctx.session.scalar(select(Driver.driver_profile_id).where(Driver.user_id == user_id))
