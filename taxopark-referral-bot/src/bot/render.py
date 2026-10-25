"""Сборка текстов экранов из данных ядра и строк локализации."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from sqlalchemy import select

from src.bot.i18n import fmt_coef, fmt_money, fmt_points, get_translator
from src.core.billing.bonus_rules import referrer_bonus_amount, welcome_bonus_amount
from src.core.billing.milestones import active_milestones_ordered_asc
from src.core.clock import days_left_in_period
from src.core.context import Ctx
from src.core.progress.display import FriendRow, MyProgress, progress_bar
from src.core.scoring.coefficients import tariff_table
from src.db.models import ProgramTerms

T = Callable[..., str]


def translator_for(lang: str) -> T:
    tr = get_translator()

    def t(key: str, **params: Any) -> str:
        return tr.t(lang, key, **params)
    return t


def tariff_name(lang: str, code: str | None, fallback: str | None = None) -> str:
    tr = get_translator()
    key = f"tariff.{code or 'unknown'}"
    return tr.t(lang, key) if tr.has(lang, key) else (fallback or code or "—")


def tariff_icon(ctx: Ctx, code: str | None) -> str:
    icons: dict[str, str] = ctx.settings.json("tariff_icons") or {}
    return icons.get(code or "", icons.get("default", ""))


def bar(ctx: Ctx, done: int, target: int) -> str:
    return progress_bar(done, target, ctx.settings.int("progress_bar_width"))


async def coefficients_table(ctx: Ctx, lang: str, t: T, threshold_x100: int | None = None) -> str:
    rows = await tariff_table(ctx, threshold_x100)
    return "\n".join(
        "• " + t("rules.coefficient_row", icon=tariff_icon(ctx, r["code"]),
                 tariff_name=tariff_name(lang, r["code"], r["name"]), coef=fmt_coef(r["coefficient_x100"]),
                 orders_needed=r["orders_to_plan"])
        for r in rows)


async def terms_text(ctx: Ctx, lang: str, t: T, terms: ProgramTerms) -> str:
    s = ctx.settings
    values = {
        "threshold": fmt_points(s.int("qualification_threshold_points_x100")),
        "bonus": fmt_money(await referrer_bonus_amount(ctx)),
        "click_days": s.int("attribution_window_click_days"),
        "notice_days": s.int("coefficient_change_notice_days"),
        "coefficients_table": await coefficients_table(ctx, lang, t),
    }

    class _Safe(dict[str, Any]):
        def __missing__(self, key: str) -> str:
            return "{" + key + "}"

    body = terms.text_for(lang).format_map(_Safe(values))
    blocks = [t("terms.title", version=terms.version), body]
    if s.bool("referred_bonus_enabled"):
        blocks.append(t("terms.welcome_block", bonus={"__money__": await welcome_bonus_amount(ctx)}))
    if s.bool("milestones_enabled"):
        rows = [t("terms.milestone_row", required=m.required_count, reward={"__money__": m.reward_uzs})
                for m in await active_milestones_ordered_asc(ctx)]
        if rows:
            blocks.append(t("terms.milestones_block") + "\n" + "\n".join(rows))
    return "\n\n".join(blocks)


def breakdown_lines(lang: str, t: T, breakdown: list[Any]) -> str:
    return "\n".join("  " + t("progress.breakdown_row", tariff_name=tariff_name(lang, b.tariff_class),
                              orders=b.orders, coef=fmt_coef(b.coefficient_x100), points=fmt_points(b.points_x100))
                     for b in breakdown)


def progress_screen(ctx: Ctx, lang: str, t: T, mp: MyProgress) -> str:
    parts = [t("progress.title", month={"__month__": mp.period_code})]
    if not mp.has_profile or mp.display is None:
        parts.append(t("progress.no_profile"))
    else:
        d = mp.display
        if d["mode"] == "orders":
            parts.append(t("progress.orders", icon=tariff_icon(ctx, d["tariff"]),
                           tariff_name=tariff_name(lang, d["tariff"]), bar=bar(ctx, d["done"], d["target"]),
                           done=d["done"], target=d["target"], left=d["left"], days=mp.days_left))
        else:
            parts.append(t("progress.points", bar=bar(ctx, d["done"], d["target"]), done=d["done"],
                           target=d["target"], left=d["left"], days=mp.days_left))
        lines = [t("progress.points_total", done=fmt_points(mp.points_x100), target=fmt_points(mp.threshold_x100))]
        if mp.breakdown:
            lines.append(breakdown_lines(lang, t, mp.breakdown))
        parts.append("\n".join(lines))
        if mp.points_x100 >= mp.threshold_x100:
            parts.append(t("progress.done"))
    if mp.friend_note:
        parts.append(t("progress.friend_note", name=mp.friend_note["name"],
                       bonus={"__money__": mp.friend_note["bonus"]}))
    if mp.welcome_bonus:
        parts.append(t("progress.welcome_note", bonus={"__money__": mp.welcome_bonus}))
    return "\n\n".join(parts)


def friend_status_key(row: FriendRow) -> str:
    if row.fired:
        return "friends.status-fired"
    if row.status == "fraud":
        return "friends.status-fraud"
    if row.status == "expired":
        return "friends.status-expired"
    if not row.is_counted and row.status == "rejected":
        return ("friends.status-not_counted_existing"
                if row.rejected_reason in ("EXISTING_DRIVER", "REHIRE") else "friends.status-not_counted")
    if row.status in ("clicked", "pending_approval"):
        return "friends.status-pending"
    if row.status == "registered":
        return "friends.status-registered"
    return "friends.status-no_orders"


def friend_row(ctx: Ctx, lang: str, t: T, n: int, row: FriendRow, days_left: int) -> str:
    from src.core.progress.display import mask_name
    name = mask_name(row.name)
    d = row.display
    if d and row.points_x100 > 0 and not row.fired:
        if d["mode"] == "orders":
            return t("friends.progress_orders", n=n, name=name, tariff_icon=tariff_icon(ctx, d["tariff"]),
                     tariff_name=tariff_name(lang, d["tariff"]), bar=bar(ctx, d["done"], d["target"]),
                     done=d["done"], target=d["target"], left=d["left"], days=days_left)
        parts = " + ".join(f"{b.orders} {tariff_name(lang, b.tariff_class).lower()}" for b in d["breakdown"])
        return t("friends.progress_points", n=n, name=name, mixed=t("tariff.mixed"),
                 bar=bar(ctx, d["done"], d["target"]), done=d["done"], target=d["target"], breakdown=parts)
    return t("friends.row_status", n=n, name=name, status=t(friend_status_key(row)))


def days_left(ctx: Ctx, period_code: str) -> int:
    return days_left_in_period(ctx.now(), period_code)


def dispute_details(lang: str, t: T, context: dict[str, Any]) -> str:
    out = []
    for p in context.get("periods", []):
        out.append(t("admin.dispute_period", code=p["code"], threshold=fmt_points(p["threshold_points_x100"]),
                     status=p["status"]))
        coefs = ", ".join(f"{k} {fmt_coef(v)}" for k, v in sorted(p["coefficients"].items()))
        out.append(t("admin.dispute_coefs", coefs=coefs))
        for f in p["friends"]:
            mark = "✅" if f["points_x100"] >= p["threshold_points_x100"] else "·"
            bd = ", ".join(f"{b['tariff_class']} {b['orders']}×{fmt_coef(int(b['coefficient_x100']))}"
                           for b in f["breakdown"])
            out.append(t("admin.dispute_friend", mark=mark, name=f["name"] or "—", points=fmt_points(f["points_x100"]),
                         orders=f["orders"], breakdown=f"({bd})" if bd else ""))
        total = sum(a["amount"] for a in p["accruals"])
        out.append(t("admin.dispute_accruals", total={"__money__": total}))
        out.append("")
    return "\n".join(out).strip()


async def current_terms_obj(ctx: Ctx) -> ProgramTerms | None:
    return (await ctx.session.execute(select(ProgramTerms).where(ProgramTerms.published_at.is_not(None))
                                      .order_by(ProgramTerms.version.desc()).limit(1))).scalar_one_or_none()
