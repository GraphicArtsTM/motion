"""Локализация на Fluent (R9: тексты только в файлах локализации).

Ключи в коде пишутся через точку ("wallet.title"), в .ftl — через дефис ("wallet-title").
Типизированные параметры outbox ({"__money__": …}, {"__dt__": …}, {"__t__": …}) форматируются
здесь, на языке получателя.
"""

from __future__ import annotations

import html
import pathlib
from datetime import datetime
from functools import lru_cache
from typing import Any

from fluent.runtime import FluentBundle, FluentResource

from src.core.clock import to_local

LANGS = ("uz_latn", "uz_cyrl", "ru")
DEFAULT_LANG = "uz_latn"
LOCALES_DIR = pathlib.Path(__file__).resolve().parent.parent / "locales"
FLUENT_LOCALE = {"uz_latn": "uz", "uz_cyrl": "uz", "ru": "ru"}
# параметры, которые уже являются HTML (контакты парка, текст условий, собранные таблицы)
RAW_PARAMS = {"park_contacts", "terms_text", "table", "breakdown", "rows", "body", "blocks", "channels",
              "progress", "filters"}


def fluent_id(key: str) -> str:
    return key.replace(".", "-")


def fmt_money(value: int) -> str:
    sign = "-" if value < 0 else ""
    digits = f"{abs(int(value)):,}".replace(",", " ")
    return sign + digits


def fmt_points(points_x100: int) -> str:
    """26100 → '261'; 15050 → '150,5' (без float, R2)."""
    whole, frac = divmod(abs(points_x100), 100)
    sign = "-" if points_x100 < 0 else ""
    if not frac:
        return f"{sign}{whole}"
    return f"{sign}{whole},{frac:02d}".rstrip("0")


def fmt_coef(coef_x100: int) -> str:
    """300 → '3.0'; 70 → '0.7'; 150 → '1.5'."""
    whole, frac = divmod(coef_x100, 100)
    frac_s = f"{frac:02d}".rstrip("0") or "0"
    return f"{whole}.{frac_s}"


class Translator:
    def __init__(self, locales_dir: pathlib.Path = LOCALES_DIR) -> None:
        self.bundles: dict[str, FluentBundle] = {}
        self.messages: dict[str, set[str]] = {}
        for lang in LANGS:
            bundle = FluentBundle([FLUENT_LOCALE[lang]], use_isolating=False)
            ids: set[str] = set()
            for path in sorted((locales_dir / lang).glob("*.ftl")):
                resource = FluentResource(path.read_text(encoding="utf-8"))
                bundle.add_resource(resource)
                ids.update(entry.id.name for entry in resource.body
                           if hasattr(entry, "id") and hasattr(entry.id, "name"))
            self.bundles[lang] = bundle
            self.messages[lang] = ids

    def has(self, lang: str, key: str) -> bool:
        return self.bundles[self._lang(lang)].has_message(fluent_id(key))

    def keys(self, lang: str) -> set[str]:
        return set(self.messages[lang])

    def _lang(self, lang: str | None) -> str:
        return lang if lang in self.bundles else DEFAULT_LANG

    def t(self, lang: str | None, key: str, **params: Any) -> str:
        lang = self._lang(lang)
        bundle = self.bundles[lang]
        mid = fluent_id(key)
        if not bundle.has_message(mid):
            if lang != "ru" and self.bundles["ru"].has_message(mid):
                bundle = self.bundles["ru"]
            else:
                return key
        msg = bundle.get_message(mid)
        if msg.value is None:
            return key
        text, _errors = bundle.format_pattern(msg.value, self.resolve_params(lang, params))
        return text

    def all_variants(self, key: str, **params: Any) -> set[str]:
        """Текст ключа на всех языках — для фильтров кнопок главного меню."""
        return {self.t(lang, key, **params) for lang in LANGS}

    # ── типизированные параметры ───────────────────────────────────────────
    def resolve_params(self, lang: str, params: dict[str, Any]) -> dict[str, Any]:
        out: dict[str, Any] = {}
        for k, v in params.items():
            out[k] = self.resolve_value(lang, k, v)
        return out

    def resolve_value(self, lang: str, key: str, v: Any) -> Any:
        if isinstance(v, dict):
            if "__money__" in v:
                return fmt_money(v["__money__"])
            if "__dt__" in v:
                return to_local(datetime.fromisoformat(v["__dt__"])).strftime("%d.%m.%Y %H:%M") if v["__dt__"] else "—"
            if "__date__" in v:
                return to_local(datetime.fromisoformat(v["__date__"])).strftime("%d.%m.%Y") if v["__date__"] else "—"
            if "__month__" in v:
                return self.month_name(lang, v["__month__"])
            if "__t__" in v:
                return self.t(lang, v["__t__"], **(v.get("params") or {}))
            return html.escape(str(v))
        if isinstance(v, bool):
            return self.t(lang, "common.yes" if v else "common.no")
        if isinstance(v, int):
            return str(v)
        if v is None:
            return "—"
        s = str(v)
        return s if key in RAW_PARAMS else html.escape(s)

    def month_name(self, lang: str, code: str) -> str:
        year, month = code.split("-")
        return f"{self.t(lang, f'month.{int(month)}')} {year}"


@lru_cache
def get_translator() -> Translator:
    return Translator()
