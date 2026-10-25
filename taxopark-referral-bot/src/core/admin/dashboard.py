"""Дашборд (8.3): воронка, каналы (N4), очередь заявок, деньги, бюджет, тарифы, здоровье API."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

from sqlalchemy import func, literal_column, select

from src.core.billing.budget import budget_usage
from src.core.billing.periods import current_period
from src.core.context import Ctx
from src.core.progress.display import leaderboard
from src.core.scoring.coefficients import unknown_tariff_orders_count
from src.db.models import (
    Accrual,
    ApiSyncLog,
    ApprovalRequest,
    Order,
    Referral,
    TariffCoefficient,
    User,
    Withdrawal,
)

FUNNEL = ("clicked", "registered", "approved", "hired", "active", "qualified")


def _conv(a: int, b: int) -> int | None:
    return b * 100 // a if a else None


def funnel_from_rows(rows: list[Referral]) -> dict[str, int]:
    return {
        "clicked": len(rows),
        "registered": sum(1 for r in rows if r.registered_at is not None),
        "approved": sum(1 for r in rows if r.is_counted),
        "hired": sum(1 for r in rows if r.is_counted and r.hired_at is not None),
        "active": sum(1 for r in rows if r.is_counted and (r.first_ride_at or r.status in ("active", "qualified"))),
        "qualified": sum(1 for r in rows if r.is_counted and r.first_qualified_at is not None),
    }


def with_conversions(f: dict[str, int]) -> dict[str, Any]:
    out: dict[str, Any] = dict(f)
    out["conversion"] = {f"{a}->{b}": _conv(f[a], f[b]) for a, b in zip(FUNNEL, FUNNEL[1:])}
    out["conversion"]["clicked->qualified"] = _conv(f["clicked"], f["qualified"])
    return out


async def channels_report(ctx: Ctx) -> list[dict[str, Any]]:
    """TC-101: конверсия по каналам привлечения."""
    rows = (await ctx.session.execute(select(Referral))).scalars().all()
    by_tag: dict[str, list[Referral]] = {}
    for r in rows:
        by_tag.setdefault(r.source_tag, []).append(r)
    return [{"source_tag": tag, **with_conversions(funnel_from_rows(items))} for tag, items in sorted(by_tag.items())]


async def dashboard(ctx: Ctx) -> dict[str, Any]:
    period = await current_period(ctx)
    refs = (await ctx.session.execute(select(Referral))).scalars().all()
    money_rows = dict((await ctx.session.execute(
        select(Accrual.status, func.coalesce(func.sum(Accrual.amount), 0)).group_by(Accrual.status))).all())
    debts = int(await ctx.session.scalar(select(func.coalesce(func.sum(User.debt), 0))) or 0)
    tariff_expr = func.coalesce(Order.tariff_class, literal_column("'unknown'"))
    tariffs = (await ctx.session.execute(
        select(tariff_expr, func.count())
        .where(Order.ended_at >= period.starts_at, Order.ended_at < period.ends_at)
        .group_by(tariff_expr))).all()
    errors = int(await ctx.session.scalar(select(func.count()).select_from(ApiSyncLog).where(
        ApiSyncLog.error.is_not(None), ApiSyncLog.created_at >= ctx.now() - timedelta(hours=1))) or 0)
    calls = int(await ctx.session.scalar(select(func.count()).select_from(ApiSyncLog).where(
        ApiSyncLog.created_at >= ctx.now() - timedelta(hours=1))) or 0)
    total_paid = int(money_rows.get("withdrawn", 0)) + int(money_rows.get("available", 0)) + \
        int(money_rows.get("reserved", 0)) + int(money_rows.get("hold", 0))
    hired = sum(1 for r in refs if r.is_counted and r.hired_at)
    top = (await leaderboard(ctx, period))[:ctx.settings.int("dashboard_top_referrers")]
    return {
        "period": period.code,
        "funnel": with_conversions(funnel_from_rows(list(refs))),
        "channels": await channels_report(ctx),
        "approvals_pending": int(await ctx.session.scalar(select(func.count()).select_from(ApprovalRequest)
                                                          .where(ApprovalRequest.status == "pending")) or 0),
        "money": {"accrued": total_paid, "available": int(money_rows.get("available", 0)),
                  "hold": int(money_rows.get("hold", 0)), "withdrawn": int(money_rows.get("withdrawn", 0)),
                  "reserved": int(money_rows.get("reserved", 0)), "debts": debts},
        "budget": await budget_usage(ctx),
        "cac": total_paid // hired if hired else None,
        "top_referrers": top,
        "tariff_distribution": {t: int(c) for t, c in tariffs},
        "unknown_tariff_orders": await unknown_tariff_orders_count(ctx),
        "tariffs_need_setup": list((await ctx.session.execute(
            select(TariffCoefficient.code).where(TariffCoefficient.needs_setup.is_(True)))).scalars()),
        "withdrawals_verifying": int(await ctx.session.scalar(select(func.count()).select_from(Withdrawal)
                                                              .where(Withdrawal.status == "verifying")) or 0),
        "fleet_api": {"calls_last_hour": calls, "errors_last_hour": errors,
                      "healthy": errors == 0 or errors * 2 < calls},
    }
