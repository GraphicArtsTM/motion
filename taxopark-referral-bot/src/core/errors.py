"""Бизнес-ошибки с ключом локализации."""

from __future__ import annotations

from typing import Any


class BusinessError(Exception):
    """Ошибка бизнес-правила. `key` — ключ локализации для показа пользователю."""

    def __init__(self, key: str, **params: Any) -> None:
        super().__init__(key)
        self.key = key
        self.params = params


class PermissionDenied(BusinessError):
    def __init__(self, required_role: str) -> None:
        super().__init__("err.permission_denied", role=required_role)


class NotFound(BusinessError):
    def __init__(self, entity: str, ident: object) -> None:
        super().__init__("err.not_found", entity=entity, id=str(ident))


def require(condition: object, key: str, **params: Any) -> None:
    if not condition:
        raise BusinessError(key, **params)
