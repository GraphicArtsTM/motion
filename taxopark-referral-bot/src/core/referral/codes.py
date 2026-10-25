"""Пользователи и реферальные коды."""

from __future__ import annotations

import secrets

from sqlalchemy import exists, select

from src.core.context import Ctx
from src.db.models import User

# без похожих символов (0/O, 1/I/L)
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 6


def generate_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


async def unique_referral_code(ctx: Ctx) -> str:
    while True:
        code = generate_code()
        if not await ctx.session.scalar(select(exists().where(User.referral_code == code))):
            return code


async def get_user_by_telegram(ctx: Ctx, telegram_id: int) -> User | None:
    return (await ctx.session.execute(select(User).where(User.telegram_id == telegram_id))).scalar_one_or_none()


async def get_or_create_user(ctx: Ctx, telegram_id: int, *, username: str | None = None,
                             language: str | None = None) -> tuple[User, bool]:
    user = await get_user_by_telegram(ctx, telegram_id)
    if user is not None:
        if username and user.username != username:
            user.username = username
        return user, False
    user = User(telegram_id=telegram_id, username=username, referral_code=await unique_referral_code(ctx),
                language=language or "uz_latn")
    ctx.session.add(user)
    await ctx.session.flush()
    return user, True


async def find_user_by_referral_code(ctx: Ctx, code: str) -> User | None:
    return (await ctx.session.execute(select(User).where(User.referral_code == code.upper()))).scalar_one_or_none()
