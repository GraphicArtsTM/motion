"""Снимок коэффициентов периода (2.3)."""

from __future__ import annotations

from sqlalchemy import delete, exists, select

from src.core.context import Ctx
from src.db.models import Period, PeriodTariffCoefficient, TariffCoefficient


async def has_snapshot(ctx: Ctx, period_id: int) -> bool:
    return bool(await ctx.session.scalar(select(exists().where(PeriodTariffCoefficient.period_id == period_id))))


async def take_snapshot(ctx: Ctx, period: Period, *, replace: bool = False) -> None:
    """Замораживает активные коэффициенты и порог на период."""
    if replace:
        await ctx.session.execute(delete(PeriodTariffCoefficient).where(PeriodTariffCoefficient.period_id == period.id))
    tariffs = (await ctx.session.execute(
        select(TariffCoefficient).where(TariffCoefficient.is_active.is_(True))
    )).scalars().all()
    for t in tariffs:
        ctx.session.add(PeriodTariffCoefficient(period_id=period.id, tariff_class=t.code,
                                                coefficient_x100=t.coefficient_x100))
    period.threshold_points_x100 = ctx.settings.int("qualification_threshold_points_x100")
    period.default_coefficient_x100 = ctx.settings.int("default_tariff_coefficient_x100")
    await ctx.session.flush()


async def period_coefficients(ctx: Ctx, period_id: int) -> dict[str, int]:
    rows = (await ctx.session.execute(
        select(PeriodTariffCoefficient.tariff_class, PeriodTariffCoefficient.coefficient_x100)
        .where(PeriodTariffCoefficient.period_id == period_id)
    )).all()
    return {code: coef for code, coef in rows}
