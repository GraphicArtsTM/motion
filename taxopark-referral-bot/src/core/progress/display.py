"""Отображение прогресса (A16), экран «Мой прогресс» (N2), «Мои друзья», рейтинг, воронка ссылки."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import case, func, select

from src.core.billing.bonus_rules import referrer_bonus_amount, welcome_bonus_amount
from src.core.billing.periods import current_period
from src.core.clock import ceil_div, days_left_in_period
from src.core.context import Ctx
from src.core.scoring.points import TariffPoints, points_for_profiles
from src.db.models import Accrual, Driver, ParkDriverProfile, Period, Referral, User


def display_progress(breakdown: list[TariffPoints], threshold_x100: int, dominant_share: int) -> dict[str, Any]:
    """A16. Доминирующий тариф (≥ share% заказов) → режим «заказы», иначе «баллы»."""
    total_orders = sum(b.orders for b in breakdown)
    dominant = next((b for b in breakdown
                     if total_orders and b.orders * 100 // total_orders >= dominant_share), None)
    if dominant:
        target = ceil_div(threshold_x100, dominant.coefficient_x100)
        return {"mode": "orders", "done": total_orders, "target": target, "tariff": dominant.tariff_class,
                "left": max(target - total_orders, 0)}
    done = sum(b.points_x100 for b in breakdown) // 100
    target = threshold_x100 // 100
    return {"mode": "points", "done": done, "target": target, "breakdown": breakdown,
            "left": max(target - done, 0)}


def progress_bar(done: int, target: int, width: int) -> str:
    filled = min(width, done * width // target) if target else 0
    return "▓" * filled + "░" * (width - filled)


@dataclass
class MyProgress:
    period_code: str
    has_profile: bool
    display: dict[str, Any] | None
    points_x100: int
    threshold_x100: int
    days_left: int
    breakdown: list[TariffPoints] = field(default_factory=list)
    friend_note: dict[str, Any] | None = None
    welcome_bonus: int | None = None


async def my_progress(ctx: Ctx, user: User) -> MyProgress:
    period = await current_period(ctx)
    pid = await ctx.session.scalar(select(Driver.driver_profile_id).where(Driver.user_id == user.id))
    days_left = days_left_in_period(ctx.now(), period.code)
    friend_note = None
    welcome = None
    ref = (await ctx.session.execute(select(Referral).where(
        Referral.referred_user_id == user.id, Referral.is_counted.is_(True), Referral.is_fraud.is_(False))
    )).scalar_one_or_none()
    if ref is not None:  # TC-88: блок только для засчитанного реферала
        referrer = await ctx.session.get(User, ref.referrer_user_id)
        friend_note = {"name": first_name(referrer.full_name if referrer else None),
                       "bonus": await referrer_bonus_amount(ctx)}
        if ctx.settings.bool("referred_bonus_enabled"):
            from src.core.billing.accruals import count_accruals
            max_p = ctx.settings.int("referred_bonus_max_periods")
            paid = await count_accruals(ctx, user_id=user.id, type="referred_welcome")
            if max_p == 0 or paid < max_p:
                welcome = await welcome_bonus_amount(ctx)
    if not pid:
        return MyProgress(period.code, False, None, 0, period.threshold_points_x100, days_left,
                          friend_note=friend_note, welcome_bonus=welcome)
    res = (await points_for_profiles(ctx, period, [pid]))[pid]
    disp = display_progress(res.breakdown, period.threshold_points_x100,
                            ctx.settings.int("dominant_tariff_share_percent"))
    return MyProgress(period.code, True, disp, res.points_x100, period.threshold_points_x100, days_left,
                      res.breakdown, friend_note, welcome)


# ── Мои друзья ───────────────────────────────────────────────────────────────
FRIEND_FILTERS = ("all", "working", "qualified", "pending", "not_counted", "fired")


@dataclass
class FriendRow:
    referral_id: int
    user_id: int
    name: str
    status: str
    is_counted: bool
    rejected_reason: str | None
    fired: bool
    display: dict[str, Any] | None = None
    points_x100: int = 0


async def friends_list(ctx: Ctx, referrer: User, flt: str = "all", page: int = 0) -> tuple[list[FriendRow], int]:
    period = await current_period(ctx)
    page_size = ctx.settings.int("friends_page_size")
    q = (select(Referral, User.full_name, Driver.driver_profile_id, ParkDriverProfile.work_status)
         .join(User, User.id == Referral.referred_user_id)
         .outerjoin(Driver, Driver.user_id == Referral.referred_user_id)
         .outerjoin(ParkDriverProfile, ParkDriverProfile.driver_profile_id == Driver.driver_profile_id)
         .where(Referral.referrer_user_id == referrer.id))
    fired = ParkDriverProfile.work_status == "fired"
    if flt == "working":
        q = q.where(Referral.is_counted.is_(True), Referral.status.in_(["hired", "active", "qualified"]),
                    func.coalesce(ParkDriverProfile.work_status, "") != "fired")
    elif flt == "qualified":
        q = q.where(Referral.is_counted.is_(True), Referral.status == "qualified")
    elif flt == "pending":
        q = q.where(Referral.status.in_(["clicked", "registered", "pending_approval"]))
    elif flt == "not_counted":
        q = q.where(Referral.is_counted.is_(False), Referral.status.in_(["rejected", "expired", "fraud"]))
    elif flt == "fired":
        q = q.where(fired)
    total = int(await ctx.session.scalar(select(func.count()).select_from(q.subquery())) or 0)
    rows = (await ctx.session.execute(
        q.order_by(case((Referral.is_counted.is_(True), 0), else_=1), Referral.created_at.desc())
        .offset(page * page_size).limit(page_size))).all()
    pids = [pid for _, _, pid, _ in rows if pid]
    points = await points_for_profiles(ctx, period, pids)
    share = ctx.settings.int("dominant_tariff_share_percent")
    out = []
    for ref, name, pid, work_status in rows:
        row = FriendRow(ref.id, ref.referred_user_id, name or "", ref.status, ref.is_counted, ref.rejected_reason,
                        work_status == "fired")
        if pid and ref.is_counted and pid in points:
            row.points_x100 = points[pid].points_x100
            row.display = display_progress(points[pid].breakdown, period.threshold_points_x100, share)
        out.append(row)
    return out, total


async def friends_count(ctx: Ctx, referrer_id: int) -> int:
    return int(await ctx.session.scalar(select(func.count()).where(Referral.referrer_user_id == referrer_id)) or 0)


async def link_stats(ctx: Ctx, referrer_id: int) -> dict[str, int]:
    """Счётчики: переходов / зарегистрировались / подтверждены / выполнили план."""
    rows = (await ctx.session.execute(select(Referral).where(Referral.referrer_user_id == referrer_id))).scalars().all()
    return {
        "clicked": len(rows),
        "registered": sum(1 for r in rows if r.registered_at is not None),
        "approved": sum(1 for r in rows if r.is_counted),
        "qualified": sum(1 for r in rows if r.first_qualified_at is not None and r.is_counted),
    }


async def leaderboard(ctx: Ctx, period: Period | None = None) -> list[dict[str, Any]]:
    """Топ рефереров месяца по сумме начислений referral; при равенстве — по числу друзей."""
    period = period or await current_period(ctx)
    rows = (await ctx.session.execute(
        select(Referral.referrer_user_id, User.full_name,
               func.count(func.distinct(Referral.id)).filter(Referral.is_counted.is_(True)).label("friends"),
               func.coalesce(func.sum(Accrual.amount).filter(Accrual.period_id == period.id), 0).label("earned"))
        .join(User, User.id == Referral.referrer_user_id)
        .outerjoin(Accrual, (Accrual.referral_id == Referral.id) & (Accrual.type == "referral")
                   & (Accrual.status != "cancelled"))
        .group_by(Referral.referrer_user_id, User.full_name)
        .order_by(func.coalesce(func.sum(Accrual.amount).filter(Accrual.period_id == period.id), 0).desc(),
                  func.count(func.distinct(Referral.id)).filter(Referral.is_counted.is_(True)).desc())
    )).all()
    out = []
    for pos, (uid, name, friends, earned) in enumerate(rows, start=1):
        out.append({"position": pos, "user_id": uid, "name": mask_name(name), "friends": int(friends),
                    "earned": int(earned)})
    return out  # полный список: первые `size` — рейтинг, остальное нужно для позиции пользователя


def first_name(full_name: str | None) -> str:
    """ФИО «Фамилия Имя Отчество» → «Имя»."""
    if not full_name:
        return ""
    parts = full_name.split()
    return parts[1] if len(parts) > 1 else parts[0]


def mask_name(name: str | None) -> str:
    """«Каримов Азиз» → «Азиз К.»"""
    if not name:
        return "—"
    parts = name.split()
    if len(parts) == 1:
        return parts[0][:1] + "***"
    return f"{parts[1]} {parts[0][:1]}."
