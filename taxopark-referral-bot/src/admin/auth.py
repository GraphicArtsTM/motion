"""Аутентификация веб-панели: логин + пароль (scrypt) + TOTP для ролей admin и выше (14.2 п.6)."""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
from collections.abc import AsyncIterator
from typing import Any

import pyotp
from fastapi import Depends, Header, HTTPException, Request
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.config import get_config
from src.core.admin.roles import has_role, is_staff, role_level
from src.core.context import Ctx
from src.db.models import AdminCredential, User
from src.db.session import get_sessionmaker
from src.runtime import open_ctx

TOKEN_TTL_SECONDS = 12 * 3600
SCRYPT_N, SCRYPT_R, SCRYPT_P = 2**14, 8, 1


def hash_password(password: str, salt: bytes | None = None) -> str:
    salt = salt or os.urandom(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(digest).decode()


def verify_password(password: str, stored: str) -> bool:
    try:
        _, salt_b64, digest_b64 = stored.split("$")
    except ValueError:
        return False
    expected = hash_password(password, base64.b64decode(salt_b64)).split("$")[2]
    return hmac.compare_digest(expected, digest_b64)


def requires_2fa(role: str) -> bool:
    return role_level(role) >= role_level("admin")


def serializer() -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(get_config().admin_secret_key, salt="admin-session")


def issue_token(user: User) -> str:
    return serializer().dumps({"uid": user.id, "role": user.role})


async def login(session: AsyncSession, login_: str, password: str, totp: str | None) -> str:
    row = (await session.execute(select(AdminCredential, User).join(User, User.id == AdminCredential.user_id)
                                 .where(AdminCredential.login == login_))).first()
    if row is None or not verify_password(password, row[0].password_hash):
        raise HTTPException(401, "invalid credentials")
    cred, user = row
    if not is_staff(user.role):
        raise HTTPException(403, "not staff")
    if requires_2fa(user.role):
        if not cred.totp_secret:
            raise HTTPException(403, "2FA is not configured for this account")
        if not totp or not pyotp.TOTP(cred.totp_secret).verify(totp, valid_window=1):
            raise HTTPException(401, "invalid 2FA code")
    return issue_token(user)


async def get_ctx() -> AsyncIterator[Ctx]:
    async with get_sessionmaker()() as session:
        ctx = await open_ctx(session)
        try:
            yield ctx
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def current_admin(ctx: Ctx = Depends(get_ctx), authorization: str = Header(default="")) -> User:
    token = authorization.removeprefix("Bearer ").strip()
    try:
        data: dict[str, Any] = serializer().loads(token, max_age=TOKEN_TTL_SECONDS)
    except (BadSignature, SignatureExpired) as e:
        raise HTTPException(401, "invalid or expired token") from e
    user = await ctx.session.get(User, data["uid"])
    if user is None or not is_staff(user.role) or user.access_status == "blocked":
        raise HTTPException(403, "forbidden")
    return user


def require(role: str, write: bool = True) -> Any:
    async def dep(request: Request, user: User = Depends(current_admin)) -> User:
        if request.method == "GET":
            ok = has_role(user.role, role, write=False)
        else:
            ok = has_role(user.role, role, write=write)
        if not ok:
            raise HTTPException(403, f"role '{role}' required")
        return user
    return dep
