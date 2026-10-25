"""RBAC (8.1)."""

from __future__ import annotations

from src.core.errors import PermissionDenied

ROLE_ORDER = ["driver", "operator", "moderator", "finance", "admin", "superadmin"]
ROLES = [*ROLE_ORDER, "readonly"]
STAFF_ROLES = {"operator", "moderator", "finance", "admin", "superadmin", "readonly"}


def role_level(role: str) -> int:
    if role == "readonly":
        return ROLE_ORDER.index("operator")
    return ROLE_ORDER.index(role) if role in ROLE_ORDER else 0


def has_role(role: str, required: str, *, write: bool = False) -> bool:
    if role == "readonly":
        return not write and role_level(role) >= role_level(required)
    return role_level(role) >= role_level(required)


def require_role(role: str, required: str, *, write: bool = True) -> None:
    if not has_role(role, required, write=write):
        raise PermissionDenied(required)


def is_staff(role: str) -> bool:
    return role in STAFF_ROLES


def is_audited(role: str) -> bool:
    """Все действия от moderator и выше пишутся в audit_log."""
    return role_level(role) >= role_level("moderator") and role != "readonly"
