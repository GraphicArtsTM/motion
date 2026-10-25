"""Награды за достижения (2.9). Выключены по умолчанию, но полностью реализованы (R14)."""

from __future__ import annotations

from typing import Any

from sqlalchemy import exists, select

from src.core.admin.audit import audit_log
from src.core.admin.roles import require_role
from src.core.billing.qualification import count_distinct_qualified_referrals_lifetime, users_with_counted_referrals
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.db.models import Milestone, SettingsHistory, User, UserMilestone


async def active_milestones_ordered_asc(ctx: Ctx) -> list[Milestone]:
    return list((await ctx.session.execute(
        select(Milestone).where(Milestone.is_active.is_(True))
        .order_by(Milestone.required_count, Milestone.sort_order)
    )).scalars().all())


async def all_milestones(ctx: Ctx) -> list[Milestone]:
    return list((await ctx.session.execute(
        select(Milestone).order_by(Milestone.required_count, Milestone.sort_order))).scalars().all())


async def user_has_milestone(ctx: Ctx, user_id: int, milestone_id: int) -> bool:
    return bool(await ctx.session.scalar(select(exists().where(
        UserMilestone.user_id == user_id, UserMilestone.milestone_id == milestone_id))))


async def record_user_milestone(ctx: Ctx, user_id: int, milestone_id: int, *, accrual_id: int | None,
                                granted_without_payment: bool) -> None:
    ctx.session.add(UserMilestone(user_id=user_id, milestone_id=milestone_id, accrual_id=accrual_id,
                                  granted_without_payment=granted_without_payment, achieved_at=ctx.now()))
    await ctx.session.flush()


async def user_milestones(ctx: Ctx, user_id: int) -> dict[int, UserMilestone]:
    rows = (await ctx.session.execute(select(UserMilestone).where(UserMilestone.user_id == user_id))).scalars()
    return {m.milestone_id: m for m in rows}


async def enable_milestones(ctx: Ctx, *, actor: User, mode: str) -> dict[str, Any]:
    """Включение тумблера (2.9.1).

    from_now   — пройденные ступени помечаются выданными без выплаты.
    retroactive — только superadmin: пройденные ступени выплачиваются сразу."""
    from src.core.billing.accruals import create_accrual_if_not_exists
    from src.core.billing.wallet import sha256
    from src.core.notifications.service import money, notify_user

    if mode not in ("from_now", "retroactive"):
        raise BusinessError("err.invalid_mode")
    require_role(actor.role, "superadmin" if mode == "retroactive" else "admin")
    if ctx.settings.bool("milestones_enabled"):
        raise BusinessError("err.already_enabled")

    granted, paid, paid_amount = 0, 0, 0
    milestones = await active_milestones_ordered_asc(ctx)
    for referrer_id in await users_with_counted_referrals(ctx):
        n = await count_distinct_qualified_referrals_lifetime(ctx, referrer_id)
        user = await ctx.session.get(User, referrer_id)
        assert user is not None
        user.qualified_referrals_count = n
        for m in milestones:
            if n < m.required_count or await user_has_milestone(ctx, referrer_id, m.id):
                continue
            if mode == "from_now":
                await record_user_milestone(ctx, referrer_id, m.id, accrual_id=None, granted_without_payment=True)
                granted += 1
            else:
                acc = await create_accrual_if_not_exists(
                    ctx, user_id=referrer_id, idempotency_key=sha256(f"ms:{referrer_id}:{m.code}"),
                    type="milestone", milestone_id=m.id, amount=m.reward_uzs, status="available",
                    comment="retroactive", created_by=actor.id)
                await record_user_milestone(ctx, referrer_id, m.id, accrual_id=acc.id if acc else None,
                                            granted_without_payment=False)
                if acc:
                    paid += 1
                    paid_amount += m.reward_uzs
                    await notify_user(ctx, referrer_id, "milestone.achieved", name=m.name,
                                      reward=money(m.reward_uzs))

    await ctx.settings.set(ctx.session, "milestones_activation_mode", mode, actor.id)
    await ctx.settings.set(ctx.session, "milestones_activated_at", ctx.now().isoformat(), actor.id)
    await ctx.settings.set(ctx.session, "milestones_enabled", True, actor.id)
    result = {"mode": mode, "granted_without_payment": granted, "paid": paid, "paid_amount": paid_amount}
    await audit_log(ctx, actor.id, "milestones_enabled", "setting", None, new_value=result)
    return result


async def disable_milestones(ctx: Ctx, *, actor: User) -> None:
    require_role(actor.role, "admin")
    await ctx.settings.set(ctx.session, "milestones_enabled", False, actor.id)


async def upsert_milestone(ctx: Ctx, *, actor_id: int, code: str, name: str, required_count: int,
                           reward_uzs: int, is_active: bool, sort_order: int) -> Milestone:
    if required_count <= 0 or reward_uzs <= 0:
        raise BusinessError("err.invalid_milestone")
    m = (await ctx.session.execute(select(Milestone).where(Milestone.code == code))).scalar_one_or_none()
    old = None
    if m is None:
        m = Milestone(code=code, name=name, required_count=required_count, reward_uzs=reward_uzs,
                      is_active=is_active, sort_order=sort_order, updated_by=actor_id)
        ctx.session.add(m)
    else:
        old = {"name": m.name, "required_count": m.required_count, "reward_uzs": m.reward_uzs,
               "is_active": m.is_active}
        m.name, m.required_count, m.reward_uzs = name, required_count, reward_uzs
        m.is_active, m.sort_order, m.updated_by = is_active, sort_order, actor_id
    new = {"name": name, "required_count": required_count, "reward_uzs": reward_uzs, "is_active": is_active}
    ctx.session.add(SettingsHistory(entity="milestone", key=code, old_value=old, new_value=new, changed_by=actor_id))
    await audit_log(ctx, actor_id, "milestone_changed", "milestone", None, old_value=old, new_value={**new, "code": code})
    await ctx.session.flush()
    return m


async def delete_milestone(ctx: Ctx, milestone_id: int, actor_id: int) -> None:
    """Ступень с выданными наградами удалить нельзя — только деактивировать (TC-70)."""
    if await ctx.session.scalar(select(exists().where(UserMilestone.milestone_id == milestone_id))):
        raise BusinessError("err.milestone_in_use")
    m = await ctx.session.get(Milestone, milestone_id)
    if m is not None:
        await ctx.session.delete(m)
        await audit_log(ctx, actor_id, "milestone_deleted", "milestone", milestone_id)
