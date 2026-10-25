"""Подсчёт баллов (A5). Все вычисления целочисленные в сотых долях (R2)."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import asdict, dataclass

from sqlalchemy import and_, func, literal, select

from src.core.context import Ctx
from src.db.models import Order, Period, PeriodTariffCoefficient

UNKNOWN = "unknown"


@dataclass
class TariffPoints:
    tariff_class: str
    orders: int
    coefficient_x100: int
    points_x100: int

    def as_dict(self) -> dict[str, int | str]:
        return asdict(self)


@dataclass
class PointsResult:
    eligible_orders_count: int
    points_x100: int
    breakdown: list[TariffPoints]

    def breakdown_json(self) -> list[dict[str, int | str]]:
        return [b.as_dict() for b in self.breakdown]


def eligibility_filters(ctx: Ctx, period: Period) -> list:  # type: ignore[type-arg]
    s = ctx.settings
    return [
        Order.status.in_(s.list("eligible_order_statuses")),
        Order.ended_at >= period.starts_at,
        Order.ended_at < period.ends_at,
        Order.price >= s.int("min_order_price"),
        Order.distance_m >= s.int("min_order_distance_m"),
        Order.duration_sec >= s.int("min_order_duration_sec"),
    ]


async def points_for_profiles(ctx: Ctx, period: Period, profile_ids: list[str],
                              coefficients: dict[str, int] | None = None,
                              default_coefficient_x100: int | None = None) -> dict[str, PointsResult]:
    """Баллы сразу для набора профилей одним запросом.

    Без `coefficients` используется снимок периода (LEFT JOIN period_tariff_coefficients,
    как в A5). С `coefficients` — черновые правила симулятора."""
    if not profile_ids:
        return {}
    tariff = func.coalesce(Order.tariff_class, literal(UNKNOWN))
    default = default_coefficient_x100 if default_coefficient_x100 is not None else period.default_coefficient_x100
    coef_col = func.coalesce(PeriodTariffCoefficient.coefficient_x100, literal(default))
    q = (
        select(Order.driver_profile_id, tariff.label("tariff"), func.count().label("cnt"),
               func.max(coef_col).label("coef"))
        .select_from(Order)
        .outerjoin(PeriodTariffCoefficient, and_(PeriodTariffCoefficient.period_id == period.id,
                                                 PeriodTariffCoefficient.tariff_class == tariff))
        .where(Order.driver_profile_id.in_(profile_ids), *eligibility_filters(ctx, period))
        .group_by(Order.driver_profile_id, tariff)
    )
    grouped: dict[str, list[TariffPoints]] = defaultdict(list)
    for pid, tclass, cnt, coef in (await ctx.session.execute(q)).all():
        if coefficients is not None:
            coef = coefficients.get(tclass, default)
        grouped[pid].append(TariffPoints(tariff_class=tclass, orders=int(cnt), coefficient_x100=int(coef),
                                         points_x100=int(cnt) * int(coef)))
    result: dict[str, PointsResult] = {}
    for pid in profile_ids:
        items = sorted(grouped.get(pid, []), key=lambda b: (-b.points_x100, b.tariff_class))
        result[pid] = PointsResult(eligible_orders_count=sum(b.orders for b in items),
                                   points_x100=sum(b.points_x100 for b in items), breakdown=items)
    return result


async def count_points(ctx: Ctx, driver_profile_id: str | None, period: Period,
                       coefficients: dict[str, int] | None = None) -> tuple[int, int, list[dict[str, int | str]]]:
    """(eligible_orders_count, points_x100, breakdown) — интерфейс из A6/A17."""
    if not driver_profile_id:
        return 0, 0, []
    res = (await points_for_profiles(ctx, period, [driver_profile_id], coefficients))[driver_profile_id]
    return res.eligible_orders_count, res.points_x100, res.breakdown_json()


async def points_breakdown_by_tariff(ctx: Ctx, driver_profile_id: str, period: Period) -> list[TariffPoints]:
    res = await points_for_profiles(ctx, period, [driver_profile_id])
    return res[driver_profile_id].breakdown


def achieved_percent(points_x100: int, threshold_x100: int) -> int:
    return points_x100 * 100 // threshold_x100 if threshold_x100 else 0
