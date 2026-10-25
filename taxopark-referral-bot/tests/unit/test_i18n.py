"""TC-05/TC-109: все три языка, непереведённых ключей нет; ключи из кода существуют."""

from __future__ import annotations

import pathlib
import re

import pytest

from src.bot.i18n import LANGS, Translator, fmt_coef, fmt_money, fmt_points
from src.core.admin.dashboard import FUNNEL  # noqa: F401
from src.db import seeds

SRC = pathlib.Path(__file__).resolve().parents[2] / "src"
KEY_RE = re.compile(r"""["']((?:err|wallet|referral|onboarding|friends|welcome|milestone|milestones|period|progress|"""
                    r"""reminder|support|account|terms|admin|broadcast|rules|reg|start|consent|btn|menu|link|rating|"""
                    r"""promo|settings|lang|common|tariff|channel|month|accrual|withdrawal|reject_reason)\."""
                    r"""[a-z_][a-z0-9_.\-]*)["']""")


@pytest.fixture(scope="module")
def tr() -> Translator:
    return Translator()


def test_same_keys_in_all_languages(tr):
    ru = tr.keys("ru")
    for lang in LANGS:
        assert tr.keys(lang) == ru, f"{lang}: {sorted(tr.keys(lang) ^ ru)}"


def _code_keys() -> set[str]:
    keys = set()
    for path in SRC.rglob("*.py"):
        for m in KEY_RE.finditer(path.read_text(encoding="utf-8")):
            key = m.group(1)
            if key.endswith(".") or key.endswith("-"):
                continue
            keys.add(key)
    return keys


def test_every_code_key_is_translated(tr):
    ignore = {"admin.alert", "btn.menu", "friends.status", "friends.filter", "admin.support", "milestones.id", "promo.png"}
    missing = []
    for key in sorted(_code_keys()):
        if key in ignore:
            continue
        for lang in LANGS:
            if not tr.has(lang, key):
                missing.append(f"{lang}:{key}")
    assert not missing, missing


def test_dynamic_key_families(tr):
    families = [f"tariff.{code}" for code, *_ in seeds.TARIFFS] + ["tariff.unknown", "tariff.mixed"]
    families += [f"channel.{tag}" for tag in ("tg", "wa", "ig", "qr", "other")]
    families += [f"month.{i}" for i in range(1, 13)]
    families += [f"reject_reason.{r}" for r in ("not_connected", "documents_invalid", "duplicate", "other")]
    families += [f"friends.filter-{f}" for f in ("all", "working", "qualified", "pending", "not_counted", "fired")]
    families += [f"accrual.type-{t}" for t in ("referral", "referred_welcome", "milestone", "adjustment", "manual")]
    families += [f"withdrawal.status-{s}" for s in ("pending", "awaiting_approval", "processing", "verifying",
                                                    "completed", "failed", "cancelled")]
    families += [f"admin.decision-{d}" for d in ("approve_with_referral", "approve_without_referral", "reject")]
    families += [f"lang.{lang}" for lang in LANGS]
    families += [f"promo.text-{i}" for i in (1, 2, 3)]
    import ast
    for path in SRC.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "alert_admins" and len(node.args) > 1:
                arg = node.args[1]
                if isinstance(arg, ast.Constant):
                    families.append(f"admin.alert.{arg.value}")
    for key in families:
        for lang in LANGS:
            assert tr.has(lang, key), f"{lang}:{key}"


def test_typed_params_and_escaping(tr):
    assert tr.t("ru", "wallet.available", amount={"__money__": 420000}) == "Доступно к выводу: <b>420 000 сум</b>"
    assert tr.t("uz_latn", "progress.title", month={"__month__": "2026-08"}) == "📈 MENING NATIJAM — Avgust 2026"
    assert "&lt;script&gt;" in tr.t("ru", "referral.pending", name="<script>")
    assert tr.t("ru", "no.such.key") == "no.such.key"
    assert fmt_money(-1500) == "-1 500" and fmt_points(26100) == "261" and fmt_points(15050) == "150,5"
    assert fmt_coef(300) == "3.0" and fmt_coef(70) == "0.7" and fmt_coef(150) == "1.5"
