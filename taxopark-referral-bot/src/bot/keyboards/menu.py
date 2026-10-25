"""Клавиатуры. Главное меню строится динамически по включённым функциям (7.1)."""

from __future__ import annotations

from typing import Any

from aiogram.types import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    KeyboardButton,
    ReplyKeyboardMarkup,
    ReplyKeyboardRemove,
)

from src.bot.i18n import LANGS, get_translator
from src.bot.render import T
from src.core.context import Ctx

# ключ кнопки → экран (для access gate и фильтров)
MENU_BUTTONS = {
    "btn.menu-link": "link",
    "btn.menu-friends": "friends",
    "btn.menu-progress": "progress",
    "btn.menu-wallet": "wallet",
    "btn.menu-rating": "rating",
    "btn.menu-terms": "terms",
    "btn.menu-promo": "promo",
    "btn.menu-support": "support",
    "btn.menu-settings": "settings",
    "btn.menu-milestones": "milestones",
}


def main_menu(ctx: Ctx, t: T, friends_count: int) -> ReplyKeyboardMarkup:
    rows = [
        [KeyboardButton(text=t("btn.menu-link")), KeyboardButton(text=t("btn.menu-friends", count=friends_count))],
        [KeyboardButton(text=t("btn.menu-progress")), KeyboardButton(text=t("btn.menu-wallet"))],
        [KeyboardButton(text=t("btn.menu-rating")), KeyboardButton(text=t("btn.menu-terms"))],
        [KeyboardButton(text=t("btn.menu-promo")), KeyboardButton(text=t("btn.menu-support"))],
    ]
    if ctx.settings.bool("milestones_enabled"):  # TC-65/68: пункт появляется без перезапуска
        rows.append([KeyboardButton(text=t("btn.menu-milestones")), KeyboardButton(text=t("btn.menu-settings"))])
    else:
        rows.append([KeyboardButton(text=t("btn.menu-settings"))])
    return ReplyKeyboardMarkup(keyboard=rows, resize_keyboard=True)


def limited_menu(t: T) -> ReplyKeyboardMarkup:
    """Экран ожидания/отказа: только условия и поддержка (3.4)."""
    return ReplyKeyboardMarkup(keyboard=[[KeyboardButton(text=t("btn.menu-terms")),
                                          KeyboardButton(text=t("btn.menu-support"))]], resize_keyboard=True)


def remove() -> ReplyKeyboardRemove:
    return ReplyKeyboardRemove()


def language_kb() -> InlineKeyboardMarkup:
    tr = get_translator()
    return InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text=tr.t(lang, f"lang.{lang}"),
                                                                       callback_data=f"lang:{lang}")]
                                                 for lang in LANGS])


def inline(rows: list[list[tuple[str, str]]]) -> InlineKeyboardMarkup:
    """[(текст, callback_data | url:…)]"""
    out = []
    for row in rows:
        buttons = []
        for text, data in row:
            if data.startswith("url:"):
                buttons.append(InlineKeyboardButton(text=text, url=data[4:]))
            elif data.startswith("inline:"):
                buttons.append(InlineKeyboardButton(text=text, switch_inline_query=data[7:]))
            else:
                buttons.append(InlineKeyboardButton(text=text, callback_data=data))
        if buttons:
            out.append(buttons)
    return InlineKeyboardMarkup(inline_keyboard=out)


def from_spec(lang: str, spec: list[list[dict[str, Any]]] | None) -> InlineKeyboardMarkup | None:
    """Кнопки из outbox ({"text_key", "params", "callback"|"url"})."""
    if not spec:
        return None
    tr = get_translator()
    rows = []
    for row in spec:
        rows.append([(tr.t(lang, b["text_key"], **(b.get("params") or {})),
                      b.get("callback") or ("url:" + b["url"] if b.get("url") else "noop")) for b in row])
    return inline(rows)


def menu_texts(key: str) -> set[str]:
    """Все языковые варианты кнопки; для «Мои друзья (N)» — сопоставление по префиксу."""
    return get_translator().all_variants(key, count=0)
