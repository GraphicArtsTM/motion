"""Статические проверки жёстких правил: R1 (без float в деньгах), R3 (нет хардкодов), R13."""

from __future__ import annotations

import io
import pathlib
import tokenize

SRC = pathlib.Path(__file__).resolve().parents[2] / "src"
# файл сидов — единственное место для бизнес-чисел (R3); схема БД — размеры колонок
ALLOWED = {SRC / "db" / "seeds.py", SRC / "db" / "models.py"}
FORBIDDEN_NUMBERS = {"300", "30000", "30_000", "3.0", "10", "50"}


def _python_files() -> list[pathlib.Path]:
    return [p for p in SRC.rglob("*.py") if p not in ALLOWED]


def test_no_hardcoded_business_numbers_r3():
    hits = []
    for path in _python_files():
        tokens = tokenize.generate_tokens(io.StringIO(path.read_text(encoding="utf-8")).readline)
        for tok in tokens:
            if tok.type == tokenize.NUMBER and tok.string in FORBIDDEN_NUMBERS:
                hits.append(f"{path.relative_to(SRC)}:{tok.start[0]} → {tok.string}")
    assert not hits, "Хардкод бизнес-чисел (R3):\n" + "\n".join(hits)


def test_no_float_in_money_code_r1():
    hits = []
    for sub in ("core/billing", "core/scoring"):
        for path in (SRC / sub).rglob("*.py"):
            for tok in tokenize.generate_tokens(io.StringIO(path.read_text(encoding="utf-8")).readline):
                if tok.type == tokenize.NAME and tok.string == "float":
                    hits.append(f"{path.relative_to(SRC)}:{tok.start[0]}")
                if tok.type == tokenize.NUMBER and "." in tok.string and path.parent.name in ("billing", "scoring"):
                    hits.append(f"{path.relative_to(SRC)}:{tok.start[0]} → {tok.string}")
    allowed = {"core/billing/withdrawal.py"}  # float('inf') — секунды антифлуда, не деньги
    assert not [h for h in hits if h.split(":")[0] not in allowed], hits


def test_deprecated_transaction_method_not_used_r13():
    text = (SRC / "integrations" / "fleet" / "api.py").read_text(encoding="utf-8")
    assert '"/v2/parks/driver-profiles/transactions"' not in text.replace(
        '(/v2/parks/driver-profiles/transactions)', "")


def test_business_logic_only_in_core_r6():
    """Бот и админка не трогают деньги напрямую: никаких изменений balance_* вне core/."""
    hits = []
    for sub in ("bot", "admin", "workers"):
        for path in (SRC / sub).rglob("*.py"):
            text = path.read_text(encoding="utf-8")
            for needle in ("balance_available +=", "balance_available -=", ".debt +=", ".debt -="):
                if needle in text:
                    hits.append(f"{path.relative_to(SRC)}: {needle}")
    assert not hits, hits
