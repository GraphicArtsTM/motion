"""Доставка уведомлений из notification_outbox в Telegram (Шаг 14).

* скорость ограничена `broadcast_rate_per_second`;
* пользователь заблокировал бота → статус `blocked`, users.bot_blocked = TRUE;
* RetryAfter → пауза и повтор; прочие ошибки → до MAX_ATTEMPTS попыток.
"""

from __future__ import annotations

import asyncio
from datetime import timedelta

import structlog
from aiogram import Bot
from aiogram.exceptions import TelegramBadRequest, TelegramForbiddenError, TelegramRetryAfter
from sqlalchemy import select

from src.bot.i18n import get_translator
from src.bot.keyboards.menu import from_spec
from src.config import get_config
from src.core.clock import Clock
from src.core.settings.service import SettingsService
from src.db.models import NotificationOutbox, SupportTicket, User
from src.db.session import get_sessionmaker

log = structlog.get_logger()
MAX_ATTEMPTS = 5
BATCH = 100
ADMIN_LANG = "ru"


def admin_chats() -> list[int]:
    cfg = get_config()
    return [cfg.admin_notify_chat_id] if cfg.admin_notify_chat_id else list(cfg.admin_telegram_ids)


async def _send_one(bot: Bot, chat_id: int, lang: str, item: NotificationOutbox) -> int | None:
    text = get_translator().t(lang, item.template_key, **(item.params or {}))
    markup = from_spec(lang, item.buttons)
    media = item.media or (item.params or {}).get("media")
    if media and media.get("photo"):
        msg = await bot.send_photo(chat_id, media["photo"], caption=text[:1024], reply_markup=markup)
    else:
        msg = await bot.send_message(chat_id, text, reply_markup=markup, disable_web_page_preview=True)
    return msg.message_id


async def deliver_batch(bot: Bot, clock: Clock | None = None) -> int:
    if clock is None:
        from src.runtime import _clock as clock
    async with get_sessionmaker()() as session:
        settings = await SettingsService.load(session)
        rate = max(1, settings.int("broadcast_rate_per_second"))
        items = (await session.execute(
            select(NotificationOutbox).where(NotificationOutbox.status == "queued",
                                             NotificationOutbox.not_before <= clock.now())
            .order_by(NotificationOutbox.id).limit(BATCH).with_for_update(skip_locked=True))).scalars().all()
        for item in items:
            try:
                if item.audience == "admins":
                    message_id = None
                    for chat in admin_chats():
                        message_id = await _send_one(bot, chat, ADMIN_LANG, item)
                    ticket_id = (item.params or {}).get("ticket_id")
                    if ticket_id and message_id and item.template_key.startswith("admin.support"):
                        ticket = await session.get(SupportTicket, int(ticket_id))
                        if ticket is not None and ticket.admin_message_id is None:
                            ticket.admin_message_id = message_id
                else:
                    user = await session.get(User, item.user_id)
                    if user is None:
                        item.status = "failed"
                        continue
                    await _send_one(bot, user.telegram_id, user.language, item)
                item.status, item.sent_at = "sent", clock.now()
            except TelegramForbiddenError:
                item.status = "blocked"
                if item.user_id:
                    user = await session.get(User, item.user_id)
                    if user is not None:
                        user.bot_blocked = True
            except TelegramRetryAfter as e:
                item.not_before = clock.now() + timedelta(seconds=e.retry_after)
                await session.commit()
                await asyncio.sleep(min(e.retry_after, 30))
                break
            except TelegramBadRequest as e:
                item.attempts += 1
                item.error = str(e)[:500]
                item.status = "failed" if item.attempts >= MAX_ATTEMPTS else "queued"
            except Exception as e:  # noqa: BLE001 — сеть и прочее: повторим позже
                item.attempts += 1
                item.error = str(e)[:500]
                item.not_before = clock.now() + timedelta(seconds=item.attempts * 30)
                if item.attempts >= MAX_ATTEMPTS:
                    item.status = "failed"
                log.warning("outbox_send_failed", outbox_id=item.id, error=type(e).__name__)
            await asyncio.sleep(1 / rate)
        await session.commit()
        return len(items)


async def run_dispatcher(bot: Bot, stop: asyncio.Event | None = None) -> None:
    stop = stop or asyncio.Event()
    while not stop.is_set():
        try:
            sent = await deliver_batch(bot)
        except Exception:  # noqa: BLE001
            log.exception("outbox_dispatcher_failed")
            sent = 0
        if not sent:
            try:
                await asyncio.wait_for(stop.wait(), timeout=1.0)
            except TimeoutError:
                pass
