"""Изменение настроек и правил из админки (8.2.7)."""

from __future__ import annotations

from datetime import date
from typing import Any

from src.core.admin.audit import audit_log
from src.core.admin.roles import require_role
from src.core.billing.periods import ensure_current_period
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.scoring.coefficients import first_day_of_next_month
from src.core.scoring.snapshot import take_snapshot
from src.db.models import BonusRule, Setting, User

SUPERADMIN_KEYS = {"fleet_provider", "milestones_activation_mode"}
# ключи, меняющие расчёт периода, вступают в силу со следующего месяца (снимок периода)
NEXT_PERIOD_KEYS = {"qualification_threshold_points_x100", "default_tariff_coefficient_x100"}
TOGGLES_WITH_SIMULATION = {"referred_bonus_enabled", "milestones_enabled"}


def _coerce(value_type: str, value: Any) -> Any:
    try:
        if value_type == "int":
            if isinstance(value, bool):
                raise ValueError
            return int(value)
        if value_type == "bool":
            if isinstance(value, str):
                return value.lower() in ("1", "true", "yes", "on")
            return bool(value)
        if value_type == "list":
            if not isinstance(value, list):
                raise ValueError
            return value
        if value_type == "str":
            return "" if value is None else str(value)
    except (TypeError, ValueError) as e:
        raise BusinessError("err.invalid_setting_value") from e
    return value


async def update_setting(ctx: Ctx, actor: User, key: str, value: Any, *, simulated: bool = False) -> Any:
    require_role(actor.role, "superadmin" if key in SUPERADMIN_KEYS else "admin")
    row = await ctx.session.get(Setting, key)
    if row is None:
        raise BusinessError("err.unknown_setting", key=key)
    value = _coerce(row.value_type, value)
    if key in TOGGLES_WITH_SIMULATION and value and not simulated:
        raise BusinessError("err.simulation_required")
    if key == "milestones_enabled" and value:
        raise BusinessError("err.use_milestones_toggle")
    if key == "withdrawal_mode" and value not in ("auto", "manual"):
        raise BusinessError("err.invalid_setting_value")
    effective: date | None = first_day_of_next_month(ctx) if key in NEXT_PERIOD_KEYS else None
    await ctx.settings.set(ctx.session, key, value, actor.id, effective_from=effective)
    if key == "referred_bonus_enabled":
        # тумблер включает и строку справочника с получателем «referred»
        from sqlalchemy import update
        await ctx.session.execute(update(BonusRule).where(BonusRule.recipient == "referred").values(is_active=bool(value)))
    return value


async def apply_rules_to_current_period(ctx: Ctx, actor: User, reason: str) -> None:
    """«Применить к текущему месяцу» — только superadmin, с причиной, обновляет снимок (8.2.7)."""
    require_role(actor.role, "superadmin")
    if not reason.strip():
        raise BusinessError("err.reason_required")
    period = await ensure_current_period(ctx)
    await take_snapshot(ctx, period, replace=True)
    await audit_log(ctx, actor.id, "rules_applied_to_current_period", "period", period.id,
                    new_value={"reason": reason, "threshold": period.threshold_points_x100})


async def load_fleet_categories(ctx: Ctx, actor: User) -> list[dict[str, Any]]:
    """«Загрузить категории транзакций из Fleet» (TC-98)."""
    require_role(actor.role, "admin")
    assert ctx.fleet is not None
    cats = [{"id": c.id, "name": c.name, "is_enabled": c.is_enabled}
            for c in await ctx.fleet.list_transaction_categories()]
    await ctx.settings.set(ctx.session, "fleet_transaction_categories", cats, actor.id)
    return cats
