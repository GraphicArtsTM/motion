"""Уведомления через outbox (D-05).

Ядро не зависит от Telegram: уведомления пишутся в `notification_outbox` в той же
транзакции, что и бизнес-изменение, а диспетчер бота доставляет их, учитывая
лимиты и блокировки. Параметры типизируются обёртками — их форматирует рендерер
на языке получателя.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import and_, exists, func, select

from src.core.clock import display_tz, local_date
from src.core.context import Ctx
from src.db.models import NotificationLog, NotificationOutbox, User

Button = dict[str, Any]
Buttons = list[list[Button]]


# ── типизированные параметры ─────────────────────────────────────────────────
def money(value: int) -> dict[str, int]:
    return {"__money__": int(value)}


def dt(value: datetime | None) -> dict[str, str | None]:
    return {"__dt__": value.isoformat() if value else None}


def d(value: datetime | None) -> dict[str, str | None]:
    return {"__date__": value.isoformat() if value else None}


def month(code: str) -> dict[str, str]:
    return {"__month__": code}


def tkey(key: str, **params: Any) -> dict[str, Any]:
    return {"__t__": key, "params": params}


def button(text_key: str, callback: str | None = None, url: str | None = None, **params: Any) -> Button:
    b: Button = {"text_key": text_key, "params": params}
    if callback:
        b["callback"] = callback
    if url:
        b["url"] = url
    return b


# ── отправка ─────────────────────────────────────────────────────────────────
async def notify_user(
    ctx: Ctx,
    user_id: int,
    key: str,
    *,
    buttons: Buttons | None = None,
    media: dict[str, Any] | None = None,
    kind: str | None = None,
    subject_id: int | None = None,
    **params: Any,
) -> NotificationOutbox:
    item = NotificationOutbox(user_id=user_id, audience="user", template_key=key, params=params,
                              buttons=buttons, media=media, not_before=ctx.now())
    ctx.session.add(item)
    if kind:
        await log_notification(ctx, user_id, kind, subject_id)
    return item


async def alert_admins(ctx: Ctx, kind: str, *, buttons: Buttons | None = None, **params: Any) -> None:
    """Алерт в админ-чат. Шаблон `admin.alert.<kind>`."""
    ctx.session.add(NotificationOutbox(audience="admins", template_key=f"admin.alert.{kind}",
                                       params=params, buttons=buttons, not_before=ctx.now()))


async def notify_admins(ctx: Ctx, key: str, *, buttons: Buttons | None = None,
                        media: dict[str, Any] | None = None, **params: Any) -> None:
    ctx.session.add(NotificationOutbox(audience="admins", template_key=key, params=params,
                                       buttons=buttons, media=media, not_before=ctx.now()))


async def notify_all(ctx: Ctx, key: str, *, only_approved: bool = False, **params: Any) -> int:
    """Массовое уведомление всем пользователям (новые условия, изменение коэффициентов)."""
    q = select(User.id).where(User.bot_blocked.is_(False), User.role == "driver")
    if only_approved:
        q = q.where(User.access_status == "approved")
    ids = (await ctx.session.execute(q)).scalars().all()
    for uid in ids:
        ctx.session.add(NotificationOutbox(user_id=uid, audience="user", template_key=key,
                                           params=params, not_before=ctx.now()))
    return len(ids)


# ── журнал и дедупликация (A18) ──────────────────────────────────────────────
async def log_notification(ctx: Ctx, user_id: int, kind: str, subject_id: int | None) -> None:
    ctx.session.add(NotificationLog(user_id=user_id, kind=kind, subject_id=subject_id, sent_at=ctx.now()))
    await ctx.session.flush()


def _local_day_start(ctx: Ctx) -> datetime:
    tz = display_tz()
    today = local_date(ctx.now())
    return datetime(today.year, today.month, today.day, tzinfo=tz)


async def sent_since(ctx: Ctx, user_id: int, kind: str, subject_id: int | None, since: datetime | None) -> bool:
    cond = [NotificationLog.user_id == user_id, NotificationLog.kind == kind]
    if since is not None:
        cond.append(NotificationLog.sent_at >= since)
    cond.append(NotificationLog.subject_id == subject_id if subject_id is not None
                else NotificationLog.subject_id.is_(None))
    return bool(await ctx.session.scalar(select(exists().where(and_(*cond)))))


async def sent_today(ctx: Ctx, user_id: int, kind: str, subject_id: int | None) -> bool:
    return await sent_since(ctx, user_id, kind, subject_id, _local_day_start(ctx))


async def sent_ever(ctx: Ctx, user_id: int, kind: str, subject_id: int | None) -> bool:
    return await sent_since(ctx, user_id, kind, subject_id, None)


async def last_sent_at(ctx: Ctx, user_id: int, kind: str, subject_id: int | None) -> datetime | None:
    return await ctx.session.scalar(
        select(func.max(NotificationLog.sent_at)).where(
            NotificationLog.user_id == user_id, NotificationLog.kind == kind,
            NotificationLog.subject_id == subject_id)
    )


async def should_notify(ctx: Ctx, user_id: int, kind: str, subject_id: int | None) -> bool:
    """A18. Не более одного уведомления о прогрессе по одному другу в сутки.
    Дедлайн-уведомление имеет приоритет над пороговым."""
    if kind == "progress" and await sent_today(ctx, user_id, "deadline", subject_id):
        return False
    return not await sent_today(ctx, user_id, kind, subject_id)


async def cooldown_passed(ctx: Ctx, user_id: int, kind: str, subject_id: int | None, hours: int) -> bool:
    return not await sent_since(ctx, user_id, kind, subject_id, ctx.now() - timedelta(hours=hours))
