"""Экраны главного меню (Раздел 7.2)."""

from __future__ import annotations

import io
import re
from typing import Any

import qrcode
from aiogram import F, Router
from aiogram.filters import BaseFilter, Command
from aiogram.fsm.context import FSMContext
from aiogram.types import (
    BufferedInputFile,
    CallbackQuery,
    InlineQuery,
    InlineQueryResultArticle,
    InputTextMessageContent,
    Message,
)

from src.bot.handlers.common import send, show_menu, show_terms
from src.bot.i18n import LANGS, fmt_money, get_translator
from src.bot.keyboards.menu import inline, language_kb
from src.bot.render import days_left, friend_row, progress_screen
from src.config import get_config
from src.core.billing.milestones import active_milestones_ordered_asc, user_milestones
from src.core.billing.periods import current_period
from src.core.notifications.progress import remind_friend
from src.core.progress.display import FRIEND_FILTERS, friends_list, leaderboard, link_stats, my_progress
from src.core.referral.codes import get_user_by_telegram
from src.db.models import User
from src.runtime import open_ctx

router = Router(name="menu")
QR_BOX_SIZE = 12
COUNT_SUFFIX = re.compile(r"\s*\(\d+\)$")


class MenuButton(BaseFilter):
    """Совпадение текста с кнопкой меню на любом языке (кнопка «друзья» содержит счётчик)."""

    def __init__(self, key: str) -> None:
        tr = get_translator()
        self.variants = {COUNT_SUFFIX.sub("", tr.t(lang, key, count=0)) for lang in LANGS}

    async def __call__(self, message: Message) -> bool:
        return bool(message.text) and COUNT_SUFFIX.sub("", message.text or "") in self.variants


def ref_link(code: str, tag: str | None = None) -> str:
    payload = f"r_{code}" + (f"_{tag}" if tag and tag != "tg" else "")
    return f"https://t.me/{get_config().bot_username}?start={payload}"


# ── 📈 Мой прогресс ──────────────────────────────────────────────────────────
@router.message(MenuButton("btn.menu-progress"), flags={"screen": "progress"})
@router.message(Command("progress"), flags={"screen": "progress"})
async def progress(message: Message, **data: Any) -> None:
    ctx, user, t, lang = data["ctx"], data["user"], data["t"], data["lang"]
    mp = await my_progress(ctx, user)
    await message.answer(progress_screen(ctx, lang, t, mp))


# ── 🔗 Моя ссылка ────────────────────────────────────────────────────────────
@router.message(MenuButton("btn.menu-link"), flags={"screen": "link"})
async def my_link(message: Message, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    tags = [tag for tag in ctx.settings.list("source_tags") if tag != "other"]
    channels = "\n".join(t("link.channel_row", channel=t(f"channel.{tag}"), link=ref_link(user.referral_code, tag))
                         for tag in tags)
    stats = await link_stats(ctx, user.id)
    await message.answer(t("link.title", code=user.referral_code, link=ref_link(user.referral_code), channels=channels,
                           **stats),
                         reply_markup=inline([[(t("btn.share"), f"inline:{user.referral_code}")],
                                              [(t("btn.qr"), "link:qr")]]),
                         disable_web_page_preview=True)


def qr_png(url: str) -> bytes:
    img = qrcode.make(url, box_size=QR_BOX_SIZE, border=2)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@router.callback_query(F.data.startswith("link:qr"), flags={"screen": "link"})
async def link_qr(cb: CallbackQuery, **data: Any) -> None:
    user, t = data["user"], data["t"]
    tag = cb.data.split(":")[2] if cb.data and cb.data.count(":") == 2 else "qr"
    await cb.answer()
    if cb.message is not None:
        await cb.message.answer_photo(BufferedInputFile(qr_png(ref_link(user.referral_code, tag)), "qr.png"),  # type: ignore[union-attr]
                                      caption=t("link.qr_caption"))


@router.inline_query()
async def inline_share(query: InlineQuery, **data: Any) -> None:
    """«Поделиться» (switch_inline_query): готовое приглашение со ссылкой."""
    from src.db.session import get_sessionmaker
    async with get_sessionmaker()() as session:
        ctx = await open_ctx(session)
        user = await get_user_by_telegram(ctx, query.from_user.id)
        if user is None or user.access_status != "approved":
            await query.answer([], cache_time=5, is_personal=True)
            return
        tr = get_translator()
        link = ref_link(user.referral_code)
        text = tr.t(user.language, "link.share_text", link=link)
        await query.answer([InlineQueryResultArticle(
            id=user.referral_code, title=tr.t(user.language, "link.share_title"), description=link,
            input_message_content=InputTextMessageContent(message_text=text))], cache_time=60, is_personal=True)


# ── 👥 Мои друзья ────────────────────────────────────────────────────────────
async def render_friends(ctx: Any, user: User, t: Any, lang: str, flt: str, page: int) -> tuple[str, Any]:
    rows, total = await friends_list(ctx, user, flt, page)
    period = await current_period(ctx)
    left = days_left(ctx, period.code)
    page_size = ctx.settings.int("friends_page_size")
    body = [t("friends.title", total=total)]
    if not rows:
        body.append(t("friends.empty"))
    for i, row in enumerate(rows, start=page * page_size + 1):
        body.append(friend_row(ctx, lang, t, i, row, left))
    kb: list[list[tuple[str, str]]] = []
    for row in rows:
        if row.display and row.is_counted and not row.fired and row.points_x100 < period.threshold_points_x100:
            kb.append([(t("btn.remind_named", name=(row.name or "").split(" ")[-1]), f"remind:{row.referral_id}")])
    filters = [(("• " if f == flt else "") + t(f"friends.filter-{f}"), f"fr:{f}:0") for f in FRIEND_FILTERS]
    kb += [filters[:3], filters[3:]]
    nav = []
    if page > 0:
        nav.append((t("btn.prev"), f"fr:{flt}:{page - 1}"))
    if (page + 1) * page_size < total:
        nav.append((t("btn.next"), f"fr:{flt}:{page + 1}"))
    kb.append(nav)
    return "\n\n".join(body), inline(kb)


@router.message(MenuButton("btn.menu-friends"), flags={"screen": "friends"})
async def friends(message: Message, **data: Any) -> None:
    text, kb = await render_friends(data["ctx"], data["user"], data["t"], data["lang"], "all", 0)
    await message.answer(text, reply_markup=kb)


@router.callback_query(F.data.startswith("fr:"), flags={"screen": "friends"})
async def friends_page(cb: CallbackQuery, **data: Any) -> None:
    _, flt, page = (cb.data or "fr:all:0").split(":")
    if flt not in FRIEND_FILTERS:
        flt = "all"
    text, kb = await render_friends(data["ctx"], data["user"], data["t"], data["lang"], flt, int(page))
    await cb.answer()
    if cb.message is not None:
        await cb.message.edit_text(text, reply_markup=kb)  # type: ignore[union-attr]


@router.callback_query(F.data.startswith("remind:"), flags={"screen": "friends"})
async def remind(cb: CallbackQuery, **data: Any) -> None:
    await remind_friend(data["ctx"], data["user"], int((cb.data or "").split(":")[1]))
    await cb.answer(data["t"]("friends.reminded"), show_alert=False)


# ── 🏆 Мои достижения ────────────────────────────────────────────────────────
@router.message(MenuButton("btn.menu-milestones"), flags={"screen": "milestones"})
async def milestones(message: Message, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    if not ctx.settings.bool("milestones_enabled"):
        await show_menu(message, data)
        return
    got = await user_milestones(ctx, user.id)
    n = user.qualified_referrals_count
    lines = [t("milestones.title", count=n), ""]
    width = ctx.settings.int("milestone_bar_width")
    from src.core.progress.display import progress_bar
    next_shown = False
    for m in await active_milestones_ordered_asc(ctx):
        um = got.get(m.id)
        if um is not None:
            lines.append(t("milestone.granted_row", required=m.required_count) if um.granted_without_payment else
                         t("milestone.done_row", required=m.required_count, reward={"__money__": m.reward_uzs},
                           date={"__date__": um.achieved_at.isoformat()}))
        elif not next_shown:
            next_shown = True
            lines += ["", t("milestone.progress", name=m.name, reward={"__money__": m.reward_uzs},
                            bar=progress_bar(n, m.required_count, width), current=n, required=m.required_count,
                            left=max(m.required_count - n, 0))]
    await message.answer("\n".join(lines))


# ── 📄 Условия ───────────────────────────────────────────────────────────────
@router.message(MenuButton("btn.menu-terms"), flags={"screen": "terms"})
@router.message(Command("terms"), flags={"screen": "terms"})
async def terms(message: Message, **data: Any) -> None:
    await show_terms(message, data)


# ── 📊 Рейтинг ───────────────────────────────────────────────────────────────
@router.message(MenuButton("btn.menu-rating"), flags={"screen": "rating"})
async def rating(message: Message, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    period = await current_period(ctx)
    board = await leaderboard(ctx, period)
    size = ctx.settings.int("leaderboard_size")
    lines = [t("rating.title", month={"__month__": period.code}), ""]
    top = [r for r in board[:size] if r["earned"] or r["friends"]]
    if not top:
        lines.append(t("rating.empty"))
    for r in top:
        lines.append(t("rating.row", position=r["position"], name=r["name"], earned=fmt_money(r["earned"]),
                       friends=r["friends"]))
    mine = next((r for r in board if r["user_id"] == user.id), None)
    lines += ["", t("rating.you", position=mine["position"]) if mine else t("rating.you_none")]
    await message.answer("\n".join(lines))


# ── 🎁 Промо-материалы ───────────────────────────────────────────────────────
@router.message(MenuButton("btn.menu-promo"), flags={"screen": "promo"})
async def promo(message: Message, **data: Any) -> None:
    user, t = data["user"], data["t"]
    await message.answer(t("promo.title"))
    for i, tag in enumerate(("tg", "wa", "ig"), start=1):
        await message.answer(t(f"promo.text-{i}", link=ref_link(user.referral_code, tag)),
                             disable_web_page_preview=True)
    await message.answer_photo(BufferedInputFile(qr_png(ref_link(user.referral_code, "qr")), "promo.png"),
                               caption=t("promo.ad", link=ref_link(user.referral_code, "qr")))


# ── ⚙️ Настройки ─────────────────────────────────────────────────────────────
def _settings_text(t: Any, lang: str, user: User) -> str:
    progress_on = (user.notification_settings or {}).get("progress", True)
    return t("settings.title", language=get_translator().t(lang, f"lang.{lang}"), progress=bool(progress_on))


@router.message(MenuButton("btn.menu-settings"), flags={"screen": "language"})
async def settings_screen(message: Message, **data: Any) -> None:
    t, lang, user = data["t"], data["lang"], data["user"]
    await message.answer(_settings_text(t, lang, user), reply_markup=inline(
        [[(t("btn.change_language"), "settings:lang")], [(t("btn.toggle_progress"), "settings:progress")]]))


@router.callback_query(F.data == "settings:lang", flags={"screen": "language"})
async def settings_lang(cb: CallbackQuery, **data: Any) -> None:
    await send(cb, data["t"]("lang.choose"), language_kb())


@router.callback_query(F.data == "settings:progress", flags={"screen": "language"})
async def settings_progress(cb: CallbackQuery, **data: Any) -> None:
    ctx, user, t, lang = data["ctx"], data["user"], data["t"], data["lang"]
    prefs = dict(user.notification_settings or {})
    prefs["progress"] = not prefs.get("progress", True)
    user.notification_settings = prefs
    await ctx.session.commit()
    await cb.answer(t("settings.saved"))
    if cb.message is not None:
        await cb.message.edit_text(_settings_text(t, lang, user), reply_markup=cb.message.reply_markup)  # type: ignore[union-attr]


@router.message(Command("menu"), flags={"screen": "menu"})
async def menu_cmd(message: Message, state: FSMContext, **data: Any) -> None:
    await state.clear()
    await show_menu(message, data)
