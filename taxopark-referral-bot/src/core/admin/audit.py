"""Запись в неизменяемый audit_log."""

from __future__ import annotations

from typing import Any

from src.core.context import Ctx
from src.db.models import AuditLog


async def audit_log(
    ctx: Ctx,
    actor_id: int | None,
    action: str,
    entity_type: str | None = None,
    entity_id: int | None = None,
    *,
    old_value: Any = None,
    new_value: Any = None,
    ip: str | None = None,
) -> None:
    ctx.session.add(AuditLog(actor_user_id=actor_id, action=action, entity_type=entity_type,
                             entity_id=entity_id, old_value=old_value, new_value=new_value, ip=ip))
