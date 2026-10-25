"""Рассылки (8.3): сегментация, планирование, тест-отправка, статистика.
Доставка — через outbox, скорость ограничивает диспетчер (broadcast_rate_per_second)."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import func, select, text

from src.core.admin.audit import audit_log
from src.core.admin.roles import require_role
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.db.models import Broadcast, BroadcastRecipient, Driver, NotificationOutbox, ParkDriverProfile, Referral, User


async def create_broadcast(ctx: Ctx, actor: User, *, title: str, text_: str, segment: dict[str, Any] | None = None,
                           media: dict[str, Any] | None = None, buttons: list[Any] | None = None,
                           scheduled_at: datetime | None = None) -> Broadcast:
    require_role(actor.role, "admin")
    if segment and segment.get("sql"):
        require_role(actor.role, "superadmin")
    b = Broadcast(title=title, text=text_, segment=segment or {}, media=media, buttons=buttons,
                  scheduled_at=scheduled_at, status="scheduled" if scheduled_at else "draft", created_by=actor.id)
    ctx.session.add(b)
    await ctx.session.flush()
    await audit_log(ctx, actor.id, "broadcast_created", "broadcast", b.id, new_value={"segment": segment})
    return b


async def resolve_segment(ctx: Ctx, segment: dict[str, Any]) -> list[int]:
    q = select(User.id).where(User.bot_blocked.is_(False))
    if segment.get("role"):
        q = q.where(User.role.in_(_as_list(segment["role"])))
    if segment.get("language"):
        q = q.where(User.language.in_(_as_list(segment["language"])))
    if segment.get("access_status"):
        q = q.where(User.access_status.in_(_as_list(segment["access_status"])))
    if segment.get("channel"):
        q = q.where(User.id.in_(select(Referral.referred_user_id).where(
            Referral.source_tag.in_(_as_list(segment["channel"])))))
    if segment.get("tariff") or segment.get("work_rule_id"):
        sub = select(Driver.user_id).join(ParkDriverProfile,
                                          ParkDriverProfile.driver_profile_id == Driver.driver_profile_id)
        if segment.get("tariff"):
            sub = sub.where(ParkDriverProfile.car_category.in_(_as_list(segment["tariff"])))
        if segment.get("work_rule_id"):
            sub = sub.where(ParkDriverProfile.work_rule_id.in_(_as_list(segment["work_rule_id"])))
        q = q.where(User.id.in_(sub))
    if segment.get("min_referrals") is not None:
        cnt = select(Referral.referrer_user_id).group_by(Referral.referrer_user_id).having(
            func.count(Referral.id) >= int(segment["min_referrals"]))
        q = q.where(User.id.in_(cnt))
    if segment.get("active_since_days") is not None:
        from datetime import timedelta
        from src.db.models import Order
        border = ctx.now() - timedelta(days=int(segment["active_since_days"]))
        q = q.where(User.id.in_(select(Driver.user_id).join(Order, Order.driver_profile_id == Driver.driver_profile_id)
                                .where(Order.ended_at >= border)))
    ids = set((await ctx.session.execute(q)).scalars().all())
    if segment.get("sql"):
        # только superadmin; запрос только на чтение и должен вернуть столбец user_id
        sql = str(segment["sql"]).strip().rstrip(";")
        if not sql.lower().startswith("select") or ";" in sql:
            raise BusinessError("err.invalid_sql_segment")
        sql_ids = set((await ctx.session.execute(text(f"SELECT user_id FROM ({sql}) s"))).scalars().all())
        ids &= sql_ids
    return sorted(ids)


def _as_list(v: Any) -> list[Any]:
    return v if isinstance(v, list) else [v]


async def start_broadcast(ctx: Ctx, broadcast_id: int, actor_id: int | None = None) -> int:
    b = await ctx.session.get(Broadcast, broadcast_id, with_for_update=True)
    if b is None:
        raise BusinessError("err.not_found", entity="broadcast", id=str(broadcast_id))
    if b.status not in ("draft", "scheduled"):
        raise BusinessError("err.broadcast_already_started")
    ids = await resolve_segment(ctx, b.segment or {})
    b.status, b.started_at, b.total = "sending", ctx.now(), len(ids)
    for uid in ids:
        item = NotificationOutbox(user_id=uid, audience="user", template_key="broadcast.raw",
                                  params={"text": b.text or "", "broadcast_id": b.id},
                                  buttons=b.buttons, media=b.media, not_before=ctx.now())
        ctx.session.add(item)
        await ctx.session.flush()
        ctx.session.add(BroadcastRecipient(broadcast_id=b.id, user_id=uid, outbox_id=item.id))
    await audit_log(ctx, actor_id, "broadcast_started", "broadcast", b.id, new_value={"total": len(ids)})
    await ctx.session.commit()
    return len(ids)


async def test_send(ctx: Ctx, actor: User, broadcast_id: int) -> None:
    b = await ctx.session.get(Broadcast, broadcast_id)
    if b is None:
        raise BusinessError("err.not_found", entity="broadcast", id=str(broadcast_id))
    ctx.session.add(NotificationOutbox(user_id=actor.id, audience="user", template_key="broadcast.raw",
                                       params={"text": b.text or ""}, buttons=b.buttons, media=b.media,
                                       not_before=ctx.now()))
    await ctx.session.commit()


async def run_scheduled_broadcasts(ctx: Ctx) -> int:
    rows = (await ctx.session.execute(select(Broadcast.id).where(
        Broadcast.status == "scheduled", Broadcast.scheduled_at <= ctx.now()))).scalars().all()
    for bid in rows:
        await start_broadcast(ctx, bid)
    return len(rows)


async def refresh_stats(ctx: Ctx, broadcast_id: int) -> dict[str, int]:
    """Синхронизация статистики рассылки со статусами outbox."""
    rows = dict((await ctx.session.execute(
        select(NotificationOutbox.status, func.count())
        .join(BroadcastRecipient, BroadcastRecipient.outbox_id == NotificationOutbox.id)
        .where(BroadcastRecipient.broadcast_id == broadcast_id).group_by(NotificationOutbox.status))).all())
    b = await ctx.session.get(Broadcast, broadcast_id)
    assert b is not None
    b.sent, b.failed, b.blocked = rows.get("sent", 0), rows.get("failed", 0), rows.get("blocked", 0)
    if b.status == "sending" and not rows.get("queued"):
        b.status, b.finished_at = "finished", ctx.now()
    await ctx.session.commit()
    return {"total": b.total or 0, "sent": b.sent or 0, "failed": b.failed or 0, "blocked": b.blocked or 0,
            "queued": rows.get("queued", 0)}
