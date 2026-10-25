"""R11: покрытие core/billing, core/referral, core/onboarding, core/scoring — не менее 85%.

Запускать после `pytest --cov=src`.
"""

from __future__ import annotations

import sys

import coverage

PACKAGES = ("src/core/billing", "src/core/referral", "src/core/onboarding", "src/core/scoring")
MIN_PERCENT = 85


def main() -> int:
    cov = coverage.Coverage()
    cov.load()
    data = cov.get_data()
    failed = False
    for pkg in PACKAGES:
        statements = missing = 0
        for path in data.measured_files():
            if f"/{pkg}/" not in path.replace("\\", "/"):
                continue
            _, stmts, _, miss, _ = cov.analysis2(path)
            statements += len(stmts)
            missing += len(miss)
        percent = 100 * (statements - missing) / statements if statements else 0
        mark = "OK " if percent >= MIN_PERCENT else "LOW"
        print(f"{mark} {pkg:<24} {percent:5.1f}%  ({statements - missing}/{statements})")
        failed |= percent < MIN_PERCENT
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
