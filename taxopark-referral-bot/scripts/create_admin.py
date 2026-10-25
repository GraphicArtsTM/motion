"""Создание учётной записи веб-панели.

python -m scripts.create_admin --telegram-id 123 --login boss --password '...' --role superadmin
Печатает otpauth-ссылку для Google Authenticator (2FA обязательна для admin/superadmin).
"""

from __future__ import annotations

import argparse
import asyncio

import pyotp
from sqlalchemy import select

from src.admin.auth import hash_password, requires_2fa
from src.core.referral.codes import get_or_create_user
from src.db.models import AdminCredential
from src.db.session import get_sessionmaker
from src.runtime import open_ctx


async def main(args: argparse.Namespace) -> None:
    async with get_sessionmaker()() as s:
        ctx = await open_ctx(s)
        user, _ = await get_or_create_user(ctx, args.telegram_id)
        user.role = args.role
        if user.access_status == "onboarding":
            user.access_status = "approved"
        cred = (await s.execute(select(AdminCredential).where(AdminCredential.user_id == user.id))).scalar_one_or_none()
        secret = pyotp.random_base32() if requires_2fa(args.role) else None
        if cred is None:
            s.add(AdminCredential(user_id=user.id, login=args.login, password_hash=hash_password(args.password),
                                  totp_secret=secret))
        else:
            cred.login, cred.password_hash, cred.totp_secret = args.login, hash_password(args.password), secret
        await s.commit()
    print(f"OK: user #{user.id} role={args.role}")
    if secret:
        print("2FA:", pyotp.TOTP(secret).provisioning_uri(name=args.login, issuer_name="Taxopark Referral"))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--telegram-id", type=int, required=True)
    p.add_argument("--login", required=True)
    p.add_argument("--password", required=True)
    p.add_argument("--role", default="admin")
    asyncio.run(main(p.parse_args()))
