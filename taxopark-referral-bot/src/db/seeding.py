"""Применение сидов (используется миграцией 0002 и тестами)."""

from __future__ import annotations

import json

from sqlalchemy import text
from sqlalchemy.engine import Connection

from src.db import seeds


def apply_seeds(conn: Connection) -> None:
    """Идемпотентно наполняет справочники и настройки значениями по умолчанию."""
    for code, name, coef, sort in seeds.TARIFFS:
        conn.execute(
            text(
                "INSERT INTO tariff_coefficients (code, name, coefficient_x100, sort_order) "
                "VALUES (:c, :n, :k, :s) ON CONFLICT (code) DO NOTHING"
            ),
            {"c": code, "n": name, "k": coef, "s": sort},
        )
    for recipient, pct, amount, active in seeds.BONUS_RULES:
        conn.execute(
            text(
                "INSERT INTO bonus_rules (recipient, min_percent, bonus_uzs, is_active) "
                "VALUES (:r, :p, :a, :i) ON CONFLICT (recipient, min_percent) DO NOTHING"
            ),
            {"r": recipient, "p": pct, "a": amount, "i": active},
        )
    for code, name, required, reward, active, sort in seeds.MILESTONES:
        conn.execute(
            text(
                "INSERT INTO milestones (code, name, required_count, reward_uzs, is_active, sort_order) "
                "VALUES (:c, :n, :q, :r, :i, :s) ON CONFLICT (code) DO NOTHING"
            ),
            {"c": code, "n": name, "q": required, "r": reward, "i": active, "s": sort},
        )
    for key, value, vtype, descr in seeds.SETTINGS:
        conn.execute(
            text(
                "INSERT INTO settings (key, value, value_type, description) "
                "VALUES (:k, CAST(:v AS JSONB), :t, :d) ON CONFLICT (key) DO NOTHING"
            ),
            {"k": key, "v": json.dumps(value, ensure_ascii=False), "t": vtype, "d": descr},
        )
    for t in seeds.TERMS:
        conn.execute(
            text(
                "INSERT INTO program_terms (version, text_ru, text_uz_latn, text_uz_cyrl, published_at) "
                "VALUES (:v, :ru, :ul, :uc, now()) ON CONFLICT (version) DO NOTHING"
            ),
            {"v": t["version"], "ru": t["text_ru"], "ul": t["text_uz_latn"], "uc": t["text_uz_cyrl"]},
        )
