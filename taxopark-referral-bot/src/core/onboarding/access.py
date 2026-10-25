"""Решения access-gate и terms-gate (3.7, 2.13). Используются middleware бота."""

from __future__ import annotations

ALWAYS = frozenset({"support", "language"})
BY_STATUS: dict[str, frozenset[str]] = {
    "onboarding": frozenset({"registration", "terms"}),
    "pending_approval": frozenset({"pending", "terms"}),
    "rejected": frozenset({"rejected"}),
    "blocked": frozenset({"blocked"}),
}
# без приёма актуальной версии условий недоступны (2.13)
TERMS_REQUIRED = frozenset({"wallet", "withdraw", "link", "promo", "dispute"})
HOME = {"onboarding": "registration", "pending_approval": "pending", "rejected": "rejected",
        "blocked": "blocked", "approved": "menu"}


def screen_allowed(access_status: str, terms_accepted: bool, screen: str) -> tuple[bool, str | None]:
    """(разрешено, куда перенаправить). Заблокированному недоступна даже поддержка."""
    if access_status == "blocked":
        return (screen == "blocked", None if screen == "blocked" else "blocked")
    if screen in ALWAYS:
        return True, None
    if access_status != "approved":
        allowed = BY_STATUS.get(access_status, frozenset())
        return (True, None) if screen in allowed else (False, HOME.get(access_status, "registration"))
    if screen in TERMS_REQUIRED and not terms_accepted:
        return False, "terms"
    return True, None
