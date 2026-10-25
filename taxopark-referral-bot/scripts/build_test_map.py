"""docs/test_cases.md: соответствие кейсов раздела 16 автотестам (по упоминаниям TC-NN в тестах)."""

from __future__ import annotations

import ast
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANUAL = {
    43: "tests/integration/test_scoring.py::test_qualification_matrix", 44: "…::test_qualification_matrix",
    45: "…::test_qualification_matrix", 46: "…::test_qualification_matrix", 47: "…::test_qualification_matrix",
    48: "…::test_qualification_matrix", 49: "…::test_qualification_matrix", 50: "…::test_qualification_matrix",
    109: "tests/unit/test_i18n.py (весь модуль)",
    110: "tests/e2e/test_load.py::test_200_concurrent_users_p95 (RUN_LOAD=1)",
    111: "scripts/backup_restore_check.sh (операционная проверка на стенде)",
    112: "tests/conftest.py::migrated_db + tests/integration/test_schema.py",
}


def main() -> None:
    found: dict[int, set[str]] = {}
    for path in sorted((ROOT / "tests").rglob("test_*.py")):
        rel = path.relative_to(ROOT)
        src = path.read_text(encoding="utf-8")
        tree = ast.parse(src)
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef) and node.name.startswith("test_"):
                body = "\n".join(src.splitlines()[node.lineno - 1:node.end_lineno])  # вместе с комментариями
                ids = {int(i) for i in re.findall(r"TC-(\d+)", body)}
                ids |= {int(i) for i in re.findall(r"tc(\d+)", node.name)}
                for i in ids:
                    found.setdefault(i, set()).add(f"{rel}::{node.name}")
    lines = ["# Кейсы приёмки (Раздел 16) → автотесты", "",
             "Сгенерировано `python scripts/build_test_map.py`.", "", "| Кейс | Тест |", "|---|---|"]
    for i in range(1, 113):
        tests = sorted(found.get(i, set()))
        cell = "<br>".join(f"`{t}`" for t in tests) if tests else f"`{MANUAL.get(i, '—')}`"
        lines.append(f"| TC-{i:02d} | {cell} |")
    out = ROOT / "docs" / "test_cases.md"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    missing = [i for i in range(1, 113) if i not in found and i not in MANUAL]
    print(f"{out}: {len(found)} кейсов найдено в тестах, без теста: {missing}")


if __name__ == "__main__":
    main()
