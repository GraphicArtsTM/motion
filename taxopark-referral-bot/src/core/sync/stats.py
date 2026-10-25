"""order_daily_stats — дневные агрегаты для дашборда, антифрода и уведомлений."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import text

from src.config import get_config
from src.core.clock import display_tz
from src.core.context import Ctx

REBUILD_SQL = text("""
INSERT INTO order_daily_stats (driver_profile_id, stat_date, tariff_class, orders_count,
                               eligible_count, points_x100, gmv)
SELECT o.driver_profile_id,
       (o.ended_at AT TIME ZONE :tz)::date AS stat_date,
       COALESCE(o.tariff_class, 'unknown') AS tariff_class,
       COUNT(*),
       COUNT(*) FILTER (WHERE o.status = ANY(:statuses) AND o.price >= :min_price
                          AND o.distance_m >= :min_distance AND o.duration_sec >= :min_duration),
       COALESCE(SUM(CASE WHEN o.status = ANY(:statuses) AND o.price >= :min_price
                          AND o.distance_m >= :min_distance AND o.duration_sec >= :min_duration
                         THEN COALESCE(ptc.coefficient_x100, p.default_coefficient_x100, :default_coef)
                         ELSE 0 END), 0),
       COALESCE(SUM(o.price), 0)
FROM orders o
LEFT JOIN periods p ON o.ended_at >= p.starts_at AND o.ended_at < p.ends_at
LEFT JOIN period_tariff_coefficients ptc
       ON ptc.period_id = p.id AND ptc.tariff_class = COALESCE(o.tariff_class, 'unknown')
WHERE o.ended_at >= :from_ts
GROUP BY 1, 2, 3
ON CONFLICT (driver_profile_id, stat_date, tariff_class) DO UPDATE SET
    orders_count = EXCLUDED.orders_count, eligible_count = EXCLUDED.eligible_count,
    points_x100 = EXCLUDED.points_x100, gmv = EXCLUDED.gmv
""")


async def rebuild_daily_stats(ctx: Ctx, since: datetime) -> None:
    tz = display_tz()
    local = since.astimezone(tz)
    day_start = datetime(local.year, local.month, local.day, tzinfo=tz)
    s = ctx.settings
    await ctx.session.execute(text("DELETE FROM order_daily_stats WHERE stat_date >= :d"), {"d": day_start.date()})
    await ctx.session.execute(REBUILD_SQL, {
        "tz": get_config().tz_display, "statuses": s.list("eligible_order_statuses"),
        "min_price": s.int("min_order_price"), "min_distance": s.int("min_order_distance_m"),
        "min_duration": s.int("min_order_duration_sec"), "default_coef": s.int("default_tariff_coefficient_x100"),
        "from_ts": day_start,
    })
