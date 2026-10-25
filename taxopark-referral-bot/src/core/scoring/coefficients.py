"""Справочник тарифов: определение тарифа заказа (9.4), неизвестные тарифы (2.4), редактирование (8.2.1)."""

from __future__ import annotations

from datetime import date
from typing import Any

from sqlalchemy import exists, func, select

from src.core.admin.audit import audit_log
from src.core.clock import ceil_div, local_date, next_code, parse_code
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.notifications.service import alert_admins
from src.db.models import (
    Broadcast,
    ParkDriverProfile,
    Period,
    PeriodTariffCoefficient,
    SettingsHistory,
    TariffCoefficient,
)

UNKNOWN = "unknown"


def normalize_tariff_code(ctx: Ctx, raw: str | None) -> str | None:
    if not raw:
        return None
    code = str(raw).strip().lower()
    aliases: dict[str, str] = ctx.settings.json("tariff_aliases") or {}
    return aliases.get(code, code)


async def resolve_tariff(ctx: Ctx, order_tariff: str | None, driver_profile_id: str,
                         car_category: str | None = None) -> tuple[str | None, str]:
    """Три уровня: тариф заказа → категория авто водителя → default."""
    code = normalize_tariff_code(ctx, order_tariff)
    if code:
        return code, "order"
    if car_category is None:
        car_category = await ctx.session.scalar(
            select(ParkDriverProfile.car_category).where(ParkDriverProfile.driver_profile_id == driver_profile_id))
    code = normalize_tariff_code(ctx, car_category)
    if code:
        return code, "car"
    return None, "default"


async def register_tariff_if_unknown(ctx: Ctx, code: str | None) -> bool:
    """Неизвестный тариф: добавляется неактивным с needs_setup, админу уведомление."""
    if not code or code == UNKNOWN:
        return False
    if await ctx.session.get(TariffCoefficient, code) is not None:
        return False
    ctx.session.add(TariffCoefficient(code=code, name=code,
                                      coefficient_x100=ctx.settings.int("default_tariff_coefficient_x100"),
                                      is_active=False, needs_setup=True, sort_order=1000))
    await ctx.session.flush()
    await alert_admins(ctx, "unknown_tariff", code=code)
    return True


async def tariff_table(ctx: Ctx, threshold_x100: int | None = None, *, only_active: bool = True) -> list[dict[str, Any]]:
    """Таблица «Заказов до плана» = ⌈порог ÷ коэффициент⌉ (8.2.1, TC-95)."""
    threshold = threshold_x100 or ctx.settings.int("qualification_threshold_points_x100")
    q = select(TariffCoefficient).order_by(TariffCoefficient.sort_order, TariffCoefficient.code)
    if only_active:
        q = q.where(TariffCoefficient.is_active.is_(True))
    rows = (await ctx.session.execute(q)).scalars().all()
    return [{
        "code": t.code, "name": t.name, "coefficient_x100": t.coefficient_x100,
        "orders_to_plan": ceil_div(threshold, t.coefficient_x100) if t.coefficient_x100 else None,
        "is_active": t.is_active, "needs_setup": t.needs_setup,
    } for t in rows]


def first_day_of_next_month(ctx: Ctx) -> date:
    y, m = parse_code(next_code(f"{local_date(ctx.now()):%Y-%m}"))
    return date(y, m, 1)


async def upsert_tariff(ctx: Ctx, *, code: str, actor_id: int, name: str | None = None,
                        coefficient_x100: int | None = None, is_active: bool | None = None,
                        sort_order: int | None = None) -> TariffCoefficient:
    """Изменение справочника. Действует со следующего месяца — текущий период считается по снимку."""
    if coefficient_x100 is not None and coefficient_x100 <= 0:
        raise BusinessError("err.invalid_coefficient")
    t = await ctx.session.get(TariffCoefficient, code, with_for_update=True)
    old = None
    if t is None:
        t = TariffCoefficient(code=code, name=name or code,
                              coefficient_x100=coefficient_x100 or ctx.settings.int("default_tariff_coefficient_x100"),
                              is_active=True if is_active is None else is_active, sort_order=sort_order or 100)
        ctx.session.add(t)
    else:
        old = {"name": t.name, "coefficient_x100": t.coefficient_x100, "is_active": t.is_active}
        if name is not None:
            t.name = name
        if coefficient_x100 is not None:
            t.coefficient_x100 = coefficient_x100
        if is_active is not None:
            t.is_active = is_active
        if sort_order is not None:
            t.sort_order = sort_order
    t.needs_setup = False
    t.updated_by = actor_id
    new = {"name": t.name, "coefficient_x100": t.coefficient_x100, "is_active": t.is_active}
    effective = first_day_of_next_month(ctx)
    ctx.session.add(SettingsHistory(entity="tariff", key=code, old_value=old, new_value=new,
                                    effective_from=effective, changed_by=actor_id))
    await audit_log(ctx, actor_id, "tariff_changed", "tariff", None, old_value=old, new_value={**new, "code": code})
    if old and old.get("coefficient_x100") != new["coefficient_x100"]:
        await _coefficient_change_draft(ctx, code, old["coefficient_x100"], new["coefficient_x100"], effective, actor_id)
    await ctx.session.flush()
    return t


async def _coefficient_change_draft(ctx: Ctx, code: str, old: int, new: int, effective: date, actor_id: int) -> None:
    """8.2.7: при изменении коэффициентов формируется черновик рассылки."""
    ctx.session.add(Broadcast(
        title=f"Изменение коэффициента {code}",
        text=None, status="draft", created_by=actor_id,
        segment={"template": "rules.coefficients_changed", "code": code, "old": old, "new": new,
                 "effective_from": effective.isoformat()},
    ))


async def delete_tariff(ctx: Ctx, code: str, actor_id: int) -> None:
    """Удаление запрещено, если тариф есть в снимках закрытых периодов — только деактивация."""
    used = await ctx.session.scalar(select(exists().where(
        PeriodTariffCoefficient.tariff_class == code,
        PeriodTariffCoefficient.period_id.in_(select(Period.id).where(Period.status == "closed")))))
    if used:
        raise BusinessError("err.tariff_in_use")
    t = await ctx.session.get(TariffCoefficient, code)
    if t is not None:
        await ctx.session.delete(t)
        await audit_log(ctx, actor_id, "tariff_deleted", "tariff", None, old_value={"code": code})


async def unknown_tariff_orders_count(ctx: Ctx) -> int:
    from src.db.models import Order
    return int(await ctx.session.scalar(
        select(func.count()).select_from(Order).where(Order.tariff_source == "default")) or 0)
