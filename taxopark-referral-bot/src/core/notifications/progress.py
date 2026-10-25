"""Уведомления о прогрессе друзей (7.3): первый заказ, пороги 50/80/90%, дедлайн, неактивность (N5),
«Напомнить другу». Дедупликация — A18."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import func, select

from src.core.billing.periods import current_period
from src.core.clock import ceil_div, days_left_in_period, display_tz, local_date
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.notifications.service import (
    button,
    cooldown_passed,
    last_sent_at,
    log_notification,
    notify_user,
    sent_since,
    should_notify,
)
from src.core.referral.queries import referrals_with_profiles
from src.core.scoring.points import achieved_percent, points_for_profiles
from src.db.models import Order, Referral, User


def _remind_button(referral_id: int) -> list[list[dict[str, object]]]:
    return [[button("btn.remind_friend", f"remind:{referral_id}")]]


async def _names(ctx: Ctx, user_ids: list[int]) -> dict[int, str]:
    if not user_ids:
        return {}
    rows = (await ctx.session.execute(select(User.id, User.full_name).where(User.id.in_(user_ids)))).all()
    return {uid: name or "" for uid, name in rows}


async def _progress_muted(ctx: Ctx, user_ids: list[int]) -> set[int]:
    """Пользователи, выключившие уведомления о прогрессе друзей в «⚙️ Настройках»."""
    if not user_ids:
        return set()
    rows = (await ctx.session.execute(select(User.id, User.notification_settings).where(User.id.in_(user_ids)))).all()
    return {uid for uid, prefs in rows if (prefs or {}).get("progress") is False}


async def check_first_rides(ctx: Ctx) -> int:
    """«{name} выполнил первый заказ 🚕» — один раз на реферала."""
    refs = [(r, pid) for r, pid in await referrals_with_profiles(ctx) if pid and r.first_ride_at is None]
    if not refs:
        return 0
    statuses = ctx.settings.list("eligible_order_statuses")
    firsts = dict((await ctx.session.execute(
        select(Order.driver_profile_id, func.min(Order.ended_at))
        .where(Order.driver_profile_id.in_([pid for _, pid in refs]), Order.status.in_(statuses))
        .group_by(Order.driver_profile_id))).all())
    names = await _names(ctx, [r.referred_user_id for r, _ in refs])
    sent = 0
    for ref, pid in refs:
        first = firsts.get(pid)
        if first is None:
            continue
        ref.first_ride_at = first
        await notify_user(ctx, ref.referrer_user_id, "referral.first_ride", name=names.get(ref.referred_user_id, ""))
        sent += 1
    await ctx.session.commit()
    return sent


async def _current_progress(ctx: Ctx) -> list[tuple[Referral, int, int]]:
    """(реферал, баллы ×100, процент) для засчитанных рефералов в текущем периоде."""
    period = await current_period(ctx)
    refs = [(r, pid) for r, pid in await referrals_with_profiles(ctx, statuses=("hired", "active", "qualified")) if pid]
    pts = await points_for_profiles(ctx, period, [pid for _, pid in refs])
    out = []
    for ref, pid in refs:
        p = pts[pid].points_x100
        out.append((ref, p, achieved_percent(p, period.threshold_points_x100)))
    return out


async def _deadline_condition(ctx: Ctx, percent: int) -> bool:
    period = await current_period(ctx)
    s = ctx.settings
    days_left = days_left_in_period(ctx.now(), period.code)
    return 100 - percent < s.int("notify_deadline_percent_left") and percent < 100 \
        and days_left < s.int("notify_deadline_days")


async def progress_notifications(ctx: Ctx) -> int:
    """Ежедневно 10:00: друг достиг 50/80/90% плана. Порог — один раз за период,
    не чаще раза в сутки по другу, дедлайн-уведомление вытесняет пороговое (TC-92/93)."""
    period = await current_period(ctx)
    thresholds = sorted(int(x) for x in ctx.settings.list("notify_progress_percents"))
    sent = 0
    progress = await _current_progress(ctx)
    names = await _names(ctx, [r.referred_user_id for r, _, _ in progress])
    muted = await _progress_muted(ctx, [r.referrer_user_id for r, _, _ in progress])
    for ref, _pts, percent in progress:
        if ref.referrer_user_id in muted:
            continue
        reached = [t for t in thresholds if percent >= t and percent < 100]
        if not reached:
            continue
        level = reached[-1]
        if await sent_since(ctx, ref.referrer_user_id, f"progress_{level}", ref.id, period.starts_at):
            continue
        if await _deadline_condition(ctx, percent):
            continue  # сегодня уйдёт дедлайн-напоминание — оно приоритетнее
        if not await should_notify(ctx, ref.referrer_user_id, "progress", ref.id):
            continue
        await notify_user(ctx, ref.referrer_user_id, "friends.progress_threshold", kind="progress", subject_id=ref.id,
                          buttons=_remind_button(ref.id), name=names.get(ref.referred_user_id, ""), percent=level)
        await log_notification(ctx, ref.referrer_user_id, f"progress_{level}", ref.id)
        sent += 1
    await ctx.session.commit()
    return sent


async def deadline_reminders(ctx: Ctx) -> int:
    """Ежедневно 11:00: < 10% до плана и < 5 дней до конца месяца — рефереру и другу."""
    period = await current_period(ctx)
    days_left = days_left_in_period(ctx.now(), period.code)
    sent = 0
    progress = await _current_progress(ctx)
    names = await _names(ctx, [r.referred_user_id for r, _, _ in progress])
    for ref, pts, percent in progress:
        if not await _deadline_condition(ctx, percent):
            continue
        left = ceil_div(max(period.threshold_points_x100 - pts, 0), 100)
        if await should_notify(ctx, ref.referrer_user_id, "deadline", ref.id):
            await notify_user(ctx, ref.referrer_user_id, "friends.deadline", kind="deadline", subject_id=ref.id,
                              buttons=_remind_button(ref.id), name=names.get(ref.referred_user_id, ""),
                              left=left, days=days_left)
            sent += 1
        if await should_notify(ctx, ref.referred_user_id, "deadline", ref.id):
            await notify_user(ctx, ref.referred_user_id, "progress.deadline_self", kind="deadline", subject_id=ref.id,
                              left=left, days=days_left)
            sent += 1
    await ctx.session.commit()
    return sent


async def inactive_friend_alert(ctx: Ctx) -> int:
    """N5: друг не выполнял заказы N дней. Одно уведомление на период неактивности."""
    days = ctx.settings.int("notify_inactive_days")
    border = ctx.now() - timedelta(days=days)
    refs = [(r, pid) for r, pid in await referrals_with_profiles(ctx, statuses=("hired", "active", "qualified")) if pid]
    if not refs:
        return 0
    last = dict((await ctx.session.execute(
        select(Order.driver_profile_id, func.max(Order.ended_at))
        .where(Order.driver_profile_id.in_([pid for _, pid in refs]))
        .group_by(Order.driver_profile_id))).all())
    names = await _names(ctx, [r.referred_user_id for r, _ in refs])
    sent = 0
    for ref, pid in refs:
        last_order = last.get(pid)
        since = last_order or ref.hired_at or ref.approved_at
        if since is None or since > border:
            continue
        prev = await last_sent_at(ctx, ref.referrer_user_id, "inactive", ref.id)
        if prev is not None and prev >= since:
            continue  # уже уведомляли в этом эпизоде неактивности
        idle_days = (local_date(ctx.now()) - since.astimezone(display_tz()).date()).days
        await notify_user(ctx, ref.referrer_user_id, "referral.friend_inactive", kind="inactive", subject_id=ref.id,
                          buttons=_remind_button(ref.id), name=names.get(ref.referred_user_id, ""), days=idle_days)
        sent += 1
    await ctx.session.commit()
    return sent


async def remind_friend(ctx: Ctx, referrer: User, referral_id: int) -> None:
    """Кнопка «🔔 Напомнить другу»: сообщение другу не чаще раза в N часов."""
    ref = await ctx.session.get(Referral, referral_id)
    if ref is None or ref.referrer_user_id != referrer.id:
        raise BusinessError("err.not_found", entity="referral", id=str(referral_id))
    hours = ctx.settings.int("reminder_cooldown_hours")
    if not await cooldown_passed(ctx, referrer.id, "reminder", ref.id, hours):
        raise BusinessError("err.reminder_cooldown", hours=hours)
    period = await current_period(ctx)
    await notify_user(ctx, ref.referred_user_id, "reminder.from_friend", name=referrer.full_name or "",
                      days=days_left_in_period(ctx.now(), period.code))
    await log_notification(ctx, referrer.id, "reminder", ref.id)
    await ctx.session.commit()
