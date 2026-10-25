"""Фейковый Telegram API для e2e-тестов бота: перехватывает запросы aiogram и отвечает правдоподобно."""

from __future__ import annotations

import itertools
from datetime import datetime
from typing import Any

from aiogram import Bot
from aiogram.client.session.base import BaseSession
from aiogram.methods import TelegramMethod
from aiogram.types import CallbackQuery, Chat, Contact, Message, PhotoSize, Update
from aiogram.types import User as TgUser

_ids = itertools.count(1000)


class FakeSession(BaseSession):
    def __init__(self) -> None:
        super().__init__()
        self.requests: list[TelegramMethod[Any]] = []

    async def close(self) -> None:
        return None

    async def stream_content(self, *a: Any, **k: Any):  # type: ignore[override]
        yield b""

    async def make_request(self, bot: Bot, method: TelegramMethod[Any], timeout: int | None = None) -> Any:
        self.requests.append(method)
        name = type(method).__name__
        if name in ("SendMessage", "SendPhoto", "EditMessageText", "EditMessageReplyMarkup"):
            chat_id = getattr(method, "chat_id", None) or 1
            return Message(message_id=next(_ids), date=datetime.now(), chat=Chat(id=int(chat_id), type="private"),
                           text=getattr(method, "text", None) or getattr(method, "caption", None))
        return True

    def texts(self) -> list[str]:
        out = []
        for m in self.requests:
            text = getattr(m, "text", None) or getattr(m, "caption", None)
            if text:
                out.append(text)
        return out

    def clear(self) -> None:
        self.requests.clear()


class TgUserSim:
    """Пользователь Telegram, отправляющий апдейты в Dispatcher."""

    def __init__(self, dp: Any, bot: Bot, tg_id: int, first_name: str = "Test") -> None:
        self.dp, self.bot = dp, bot
        self.user = TgUser(id=tg_id, is_bot=False, first_name=first_name, language_code="ru")
        self.chat = Chat(id=tg_id, type="private")

    def _msg(self, **kw: Any) -> Message:
        return Message(message_id=next(_ids), date=datetime.now(), chat=self.chat, from_user=self.user, **kw)

    async def send(self, text: str) -> None:
        entities = None
        if text.startswith("/"):
            from aiogram.types import MessageEntity
            entities = [MessageEntity(type="bot_command", offset=0, length=len(text.split()[0]))]
        await self.dp.feed_update(self.bot, Update(update_id=next(_ids), message=self._msg(text=text, entities=entities)))

    async def contact(self, phone: str) -> None:
        c = Contact(phone_number=phone, first_name="T", user_id=self.user.id)
        await self.dp.feed_update(self.bot, Update(update_id=next(_ids), message=self._msg(contact=c)))

    async def photo(self, file_id: str) -> None:
        p = [PhotoSize(file_id=file_id, file_unique_id=file_id, width=100, height=100)]
        await self.dp.feed_update(self.bot, Update(update_id=next(_ids), message=self._msg(photo=p)))

    async def click(self, data: str) -> None:
        cb = CallbackQuery(id=str(next(_ids)), from_user=self.user, chat_instance="x", data=data,
                           message=self._msg(text="kb"))
        await self.dp.feed_update(self.bot, Update(update_id=next(_ids), callback_query=cb))
