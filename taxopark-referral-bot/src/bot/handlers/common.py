"""Общие функции показа экранов и маршрутизации по статусу доступа."""

from __future__ import annotations

from typing import Any

from aiogram.types import CallbackQuery, InlineKeyboardMarkup, Message, ReplyKeyboardMarkup, ReplyKeyboardRemove, TelegramObject

from src.bot.keyboards.menu import inline, language_kb, limited_menu, main_menu
from src.bot.render import current_terms_obj, terms_text
from src.core.onboarding.registration import pending_screen_params
from src.core.onboarding.terms import has_accepted_current_terms
from src.core.progress.display import friends_count
from src.db.models import User

Markup = InlineKeyboardMarkup | ReplyKeyboardMarkup | ReplyKeyboardRemove | None


async def send(event: TelegramObject, text: str, markup: Markup = None) -> Message | None:
    if isinstance(event, CallbackQuery):
        await event.answer()
        if event.message is not None:
            return await event.message.answer(text, reply_markup=markup)  # type: ignore[union-attr]
        return None
    if isinstance(event, Message):
        return await event.answer(text, reply_markup=markup)
    return None


async def show_menu(event: TelegramObject, data: dict[str, Any], text: str | None = None) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    await send(event, text or t("menu.title"), main_menu(ctx, t, await friends_count(ctx, user.id)))


async def show_terms(event: TelegramObject, data: dict[str, Any], *, force_accept: bool = False) -> None:
    ctx, user, t, lang = data["ctx"], data["user"], data["t"], data["lang"]
    terms = await current_terms_obj(ctx)
    if terms is None:
        await send(event, t("err.no_terms"))
        return
    accepted = await has_accepted_current_terms(ctx, user.id)
    text = await terms_text(ctx, lang, t, terms)
    markup = inline([[(t("btn.accept_terms"), "terms:accept")]]) if (force_accept or not accepted) else None
    if not accepted:
        text = t("terms.accept_prompt") + "\n\n" + text
    await send(event, text, markup)


async def show_screen(event: TelegramObject, data: dict[str, Any], screen: str) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    if screen == "registration":
        await send(event, t("lang.choose"), language_kb())
    elif screen == "pending":
        params = await pending_screen_params(ctx, user)
        await send(event, t("onboarding.pending", **params), inline(
            [[(t("btn.refresh_status"), "pending:refresh")], [(t("btn.menu-support"), "support:start")]]))
        await send(event, "👇", limited_menu(t))
    elif screen == "rejected":
        await send(event, t("onboarding.rejected_screen"), limited_menu(t))
    elif screen == "blocked":
        await send(event, t("account.blocked"), ReplyKeyboardRemove())
    elif screen == "terms":
        await show_terms(event, data, force_accept=True)
    else:
        await show_menu(event, data)


async def route_by_access_status(event: TelegramObject, data: dict[str, Any]) -> None:
    user: User = data["user"]
    status = user.access_status
    if status == "approved":
        if not await has_accepted_current_terms(data["ctx"], user.id):
            await send(event, data["t"]("terms.updated"))
            await show_terms(event, data, force_accept=True)
            return
        await show_menu(event, data)
        return
    await show_screen(event, data, {"onboarding": "registration", "pending_approval": "pending",
                                    "rejected": "rejected", "blocked": "blocked"}.get(status, "registration"))
