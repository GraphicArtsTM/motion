"""Справочник бонусов со ступенями и получателями (2.7)."""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from sqlalchemy import exists, select

from src.core.admin.audit import audit_log
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.db.models import Accrual, BonusRule, SettingsHistory

RECIPIENTS = ("referrer", "referred")


async def best_bonus_rule(ctx: Ctx, achieved_percent: int, recipient: str) -> BonusRule | None:
    """Строка с максимальным min_percent, не превышающим достигнутый процент."""
    return (await ctx.session.execute(
        select(BonusRule).where(BonusRule.is_active.is_(True), BonusRule.recipient == recipient,
                                BonusRule.min_percent <= achieved_percent)
        .order_by(BonusRule.min_percent.desc()).limit(1)
    )).scalar_one_or_none()


def best_rule(rules: Iterable[dict[str, Any]], achieved_percent: int, recipient: str) -> dict[str, Any] | None:
    """То же для черновых правил симулятора."""
    candidates = [r for r in rules if r.get("is_active", True) and r["recipient"] == recipient
                  and r["min_percent"] <= achieved_percent]
    return max(candidates, key=lambda r: r["min_percent"]) if candidates else None


async def list_rules(ctx: Ctx) -> list[BonusRule]:
    return list((await ctx.session.execute(
        select(BonusRule).order_by(BonusRule.recipient, BonusRule.min_percent))).scalars().all())


async def rules_as_dicts(ctx: Ctx) -> list[dict[str, Any]]:
    return [{"id": r.id, "recipient": r.recipient, "min_percent": r.min_percent, "bonus_uzs": r.bonus_uzs,
             "is_active": r.is_active} for r in await list_rules(ctx)]


async def referrer_bonus_amount(ctx: Ctx) -> int:
    """Сумма за 100% плана для текстов («получит {bonus} сум»)."""
    rule = await best_bonus_rule(ctx, 100, "referrer")
    return rule.bonus_uzs if rule else 0


async def welcome_bonus_amount(ctx: Ctx) -> int:
    rule = await best_bonus_rule(ctx, 100, "referred")
    return rule.bonus_uzs if rule else 0


async def upsert_rule(ctx: Ctx, *, actor_id: int, recipient: str, min_percent: int, bonus_uzs: int,
                      is_active: bool = True, rule_id: int | None = None) -> BonusRule:
    if recipient not in RECIPIENTS:
        raise BusinessError("err.invalid_recipient")
    if bonus_uzs <= 0 or min_percent <= 0:
        raise BusinessError("err.invalid_bonus_rule")
    rule = await ctx.session.get(BonusRule, rule_id) if rule_id else (await ctx.session.execute(
        select(BonusRule).where(BonusRule.recipient == recipient, BonusRule.min_percent == min_percent)
    )).scalar_one_or_none()
    old = None
    if rule is None:
        rule = BonusRule(recipient=recipient, min_percent=min_percent, bonus_uzs=bonus_uzs, is_active=is_active,
                         updated_by=actor_id)
        ctx.session.add(rule)
    else:
        old = {"recipient": rule.recipient, "min_percent": rule.min_percent, "bonus_uzs": rule.bonus_uzs,
               "is_active": rule.is_active}
        rule.recipient, rule.min_percent, rule.bonus_uzs, rule.is_active = recipient, min_percent, bonus_uzs, is_active
        rule.updated_by = actor_id
    new = {"recipient": recipient, "min_percent": min_percent, "bonus_uzs": bonus_uzs, "is_active": is_active}
    ctx.session.add(SettingsHistory(entity="bonus_rule", key=f"{recipient}:{min_percent}", old_value=old,
                                    new_value=new, changed_by=actor_id))
    await audit_log(ctx, actor_id, "bonus_rule_changed", "bonus_rule", rule_id, old_value=old, new_value=new)
    await ctx.session.flush()
    return rule


async def delete_rule(ctx: Ctx, rule_id: int, actor_id: int) -> None:
    rule = await ctx.session.get(BonusRule, rule_id)
    if rule is None:
        return
    if await ctx.session.scalar(select(exists().where(Accrual.bonus_rule_id == rule_id))):
        raise BusinessError("err.bonus_rule_in_use")
    await ctx.session.delete(rule)
    await audit_log(ctx, actor_id, "bonus_rule_deleted", "bonus_rule", rule_id)
