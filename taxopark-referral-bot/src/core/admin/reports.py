"""Отчёты (8.3): реестр выводов, воронка, каналы, рефереры, тарифы, часы, удержание, audit log.
Каждый отчёт — (заголовки, строки); экспорт в XLSX/CSV делает слой админки."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import func, literal_column, select

from src.core.admin.dashboard import FUNNEL, channels_report, funnel_from_rows
from src.core.clock import to_local
from src.core.context import Ctx
from src.db.models import AuditLog, DriverOnlineTime, OrderDailyStat, Qualification, Referral, User, Withdrawal

MONTH_FMT = literal_column("'YYYY-MM'")
Report = tuple[list[str], list[list[Any]]]


def _dt(v: datetime | None) -> str:
    return to_local(v).strftime("%d.%m.%Y %H:%M") if v else ""


async def withdrawals_registry(ctx: Ctx, date_from: datetime | None = None, date_to: datetime | None = None) -> Report:
    q = select(Withdrawal, User).join(User, User.id == Withdrawal.user_id).order_by(Withdrawal.id)
    if date_from:
        q = q.where(Withdrawal.requested_at >= date_from)
    if date_to:
        q = q.where(Withdrawal.requested_at < date_to)
    rows = (await ctx.session.execute(q)).all()
    head = ["ID", "Водитель", "Телефон", "Профиль Fleet", "Сумма, сум", "Статус", "Ручная", "Метка",
            "Транзакция", "Запрошено", "Завершено"]
    return head, [[w.id, u.full_name, u.phone, w.driver_profile_id, w.amount, w.status, w.requires_manual, w.marker,
                   w.external_transaction_id, _dt(w.requested_at), _dt(w.completed_at)] for w, u in rows]


async def funnel_report(ctx: Ctx) -> Report:
    f = funnel_from_rows(list((await ctx.session.execute(select(Referral))).scalars().all()))
    return ["Этап", "Количество"], [[k, f[k]] for k in FUNNEL]


async def channels_effectiveness(ctx: Ctx) -> Report:
    rows = await channels_report(ctx)
    head = ["Канал", *FUNNEL, "Конверсия клик→план, %"]
    return head, [[r["source_tag"], *[r[k] for k in FUNNEL], r["conversion"]["clicked->qualified"]] for r in rows]


async def referrers_activity(ctx: Ctx) -> Report:
    rows = (await ctx.session.execute(
        select(User.id, User.full_name, func.count(Referral.id),
               func.count(Referral.id).filter(Referral.is_counted.is_(True)),
               User.qualified_referrals_count)
        .join(Referral, Referral.referrer_user_id == User.id).group_by(User.id).order_by(func.count(Referral.id).desc())
    )).all()
    return ["ID", "Реферер", "Приглашено", "Засчитано", "Выполняли план"], [list(r) for r in rows]


async def points_by_tariff(ctx: Ctx) -> Report:
    month = func.to_char(OrderDailyStat.stat_date, MONTH_FMT)
    rows = (await ctx.session.execute(
        select(month, OrderDailyStat.tariff_class,
               func.sum(OrderDailyStat.orders_count), func.sum(OrderDailyStat.eligible_count),
               func.sum(OrderDailyStat.points_x100))
        .group_by(month, OrderDailyStat.tariff_class)
        .order_by(month, OrderDailyStat.tariff_class))).all()
    return ["Месяц", "Тариф", "Заказов", "Зачётных", "Баллы ×100"], [list(r) for r in rows]


async def online_hours(ctx: Ctx) -> Report:
    month = func.to_char(DriverOnlineTime.stat_date, MONTH_FMT)
    rows = (await ctx.session.execute(
        select(DriverOnlineTime.driver_profile_id, month, func.sum(DriverOnlineTime.online_seconds) / 3600)
        .group_by(DriverOnlineTime.driver_profile_id, month))).all()
    return ["Профиль", "Месяц", "Часы"], [list(r) for r in rows]


async def retention(ctx: Ctx) -> Report:
    """Удержание засчитанных рефералов: активен через 1/3/6 месяцев после подтверждения."""
    refs = (await ctx.session.execute(select(Referral).where(Referral.is_counted.is_(True),
                                                             Referral.approved_at.is_not(None)))).scalars().all()
    quals = (await ctx.session.execute(select(Qualification.referral_id, Qualification.period_id,
                                              Qualification.points_x100))).all()
    from src.db.models import Period
    periods = {p.id: p for p in (await ctx.session.execute(select(Period))).scalars()}
    active: dict[int, list[datetime]] = {}
    for rid, pid, pts in quals:
        if pts > 0 and pid in periods:
            active.setdefault(rid, []).append(periods[pid].starts_at)
    out = []
    for months in (1, 3, 6):
        base = [r for r in refs if r.approved_at and (ctx.now() - r.approved_at).days >= months * 30]
        kept = [r for r in base if any((s - r.approved_at).days >= (months - 1) * 30 for s in active.get(r.id, []))]
        out.append([months, len(base), len(kept), len(kept) * 100 // len(base) if base else None])
    return ["Месяцев", "База", "Активны", "%"], out


async def audit_report(ctx: Ctx, limit: int = 5000) -> Report:
    rows = (await ctx.session.execute(select(AuditLog).order_by(AuditLog.id.desc()).limit(limit))).scalars().all()
    return ["ID", "Кто", "Действие", "Сущность", "ID сущности", "Было", "Стало", "Когда"], [
        [a.id, a.actor_user_id, a.action, a.entity_type, a.entity_id, a.old_value, a.new_value, _dt(a.created_at)]
        for a in rows]


REPORTS = {
    "withdrawals": withdrawals_registry,
    "funnel": funnel_report,
    "channels": channels_effectiveness,
    "referrers": referrers_activity,
    "tariffs": points_by_tariff,
    "online_hours": online_hours,
    "retention": retention,
    "audit": audit_report,
}
