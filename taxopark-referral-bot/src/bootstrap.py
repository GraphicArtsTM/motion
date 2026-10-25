"""Применение настроек из мастера настройки (config/initial_settings.json) к БД.

Запускается сервисом `migrate` после `alembic upgrade head`. Файл применяется один раз и переименовывается
в initial_settings.applied.json — повторный запуск ничего не меняет.
"""

from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
from typing import Any

from sqlalchemy import select

from src.core.admin.audit import audit_log
from src.core.referral.codes import get_or_create_user
from src.db.models import AdminCredential, Setting
from src.db.session import get_sessionmaker
from src.runtime import open_ctx

CONFIG_DIR = Path(os.environ.get("BOOTSTRAP_DIR", "config"))
PENDING = "initial_settings.json"
APPLIED = "initial_settings.applied.json"


async def apply(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    applied: dict[str, Any] = {"settings": [], "admin": None}
    async with get_sessionmaker()() as session:
        ctx = await open_ctx(session)
        for key, value in (data.get("settings") or {}).items():
            row = await session.get(Setting, key)
            if row is None:
                continue
            await ctx.settings.set(session, key, value, None)
            applied["settings"].append(key)
        admin = data.get("admin")
        if admin and admin.get("telegram_id") and admin.get("login") and admin.get("password_hash"):
            user, _ = await get_or_create_user(ctx, int(admin["telegram_id"]))
            user.role = admin.get("role", "superadmin")
            if user.access_status == "onboarding":
                user.access_status = "approved"
            cred = (await session.execute(select(AdminCredential).where(
                AdminCredential.user_id == user.id))).scalar_one_or_none()
            if cred is None:
                session.add(AdminCredential(user_id=user.id, login=admin["login"],
                                            password_hash=admin["password_hash"], totp_secret=admin.get("totp_secret")))
            else:
                cred.login, cred.password_hash = admin["login"], admin["password_hash"]
                cred.totp_secret = admin.get("totp_secret")
            applied["admin"] = admin["login"]
        await audit_log(ctx, None, "setup_wizard_applied", "settings", None, new_value=applied)
        await session.commit()
    return applied


async def main() -> None:
    pending = CONFIG_DIR / PENDING
    if not pending.exists():
        print("bootstrap: нет новых настроек из мастера")
        return
    result = await apply(pending)
    # на диске не оставляем хеш пароля и секрет 2FA
    data = json.loads(pending.read_text(encoding="utf-8"))
    if data.get("admin"):
        data["admin"] = {k: v for k, v in data["admin"].items() if k not in ("password_hash", "totp_secret")}
    (CONFIG_DIR / APPLIED).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    pending.unlink()
    print(f"bootstrap: применено настроек {len(result['settings'])}, учётная запись панели: {result['admin']}")


if __name__ == "__main__":
    asyncio.run(main())
