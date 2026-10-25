"""Фабрики тестовых данных."""

from __future__ import annotations

import itertools
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import func, select, text

from src.core.billing.periods import ensure_current_period, open_period
from src.core.clock import display_tz
from src.core.context import Ctx
from src.core.referral.codes import unique_referral_code
from src.db.models import (
    Accrual,
    Driver,
    Order,
    ParkDriverProfile,
    ProgramTerms,
    Referral,
    User,
    UserTermsAcceptance,
    WalletLedger,
    Withdrawal,
)

_seq = itertools.count(1)


def tashkent(*args: int) -> datetime:
    return datetime(*args, tzinfo=display_tz())


async def create_user(ctx: Ctx, *, access_status: str = "approved", role: str = "driver", name: str | None = None,
                      phone: str | None = None, license_: str | None = None, accept_terms: bool = True,
                      language: str = "ru", **kw: Any) -> User:
    n = next(_seq)
    user = User(telegram_id=100000 + n, username=f"user{n}", full_name=name or f"Фамилия{n} Имя{n}",
                phone=phone if phone is not None else f"+99890{n:07d}",
                driver_license=license_ if license_ is not None else f"AA{n:07d}",
                language=language, role=role, access_status=access_status,
                referral_code=await unique_referral_code(ctx), **kw)
    ctx.session.add(user)
    await ctx.session.flush()
    if accept_terms:
        terms = (await ctx.session.execute(select(ProgramTerms).order_by(ProgramTerms.version.desc()))).scalars().first()
        if terms:
            ctx.session.add(UserTermsAcceptance(user_id=user.id, terms_id=terms.id))
    await ctx.session.flush()
    return user


async def add_profile(ctx: Ctx, *, profile_id: str | None = None, phone: str | None = None, license_: str | None = None,
                      created_date: datetime | None = None, work_status: str = "working", fire_date: Any = None,
                      car_id: str | None = None, car_category: str | None = None) -> ParkDriverProfile:
    n = next(_seq)
    p = ParkDriverProfile(driver_profile_id=profile_id or f"prof-{n}", park_id="park-1", phone_normalized=phone,
                          license_normalized=license_, created_date=created_date or ctx.now(),
                          work_status=work_status, fire_date=fire_date, car_id=car_id, car_category=car_category,
                          first_name="Имя", last_name="Фамилия")
    ctx.session.add(p)
    await ctx.session.flush()
    return p


async def link(ctx: Ctx, user: User, profile: ParkDriverProfile) -> Driver:
    d = Driver(user_id=user.id, driver_profile_id=profile.driver_profile_id, work_status=profile.work_status)
    ctx.session.add(d)
    await ctx.session.flush()
    return d


async def counted_referral(ctx: Ctx, referrer: User | None = None, *, status: str = "hired",
                           friend_name: str | None = None) -> tuple[User, User, Referral, str]:
    """Засчитанный реферал с привязанным профилем Fleet."""
    referrer = referrer or await create_user(ctx, name="Рефереров Рустам")
    friend = await create_user(ctx, name=friend_name)
    profile = await add_profile(ctx, phone=friend.phone, license_=friend.driver_license)
    await link(ctx, friend, profile)
    ref = Referral(referrer_user_id=referrer.id, referred_user_id=friend.id, referral_code=referrer.referral_code,
                   status=status, is_counted=True, clicked_at=ctx.now() - timedelta(days=40),
                   registered_at=ctx.now() - timedelta(days=39), approved_at=ctx.now() - timedelta(days=38),
                   hired_at=ctx.now() - timedelta(days=38))
    ctx.session.add(ref)
    await ctx.session.flush()
    return referrer, friend, ref, profile.driver_profile_id


async def add_orders(ctx: Ctx, profile_id: str, count: int, tariff: str | None = "econom", *,
                     ended_at: datetime | None = None, status: str = "complete", price: int | None = None,
                     distance_m: int | None = None, duration_sec: int | None = None, days: float = 10,
                     address_from: str | None = None, address_to: str | None = None) -> None:
    """`count` заказов, равномерно распределённых на `days` дней до `ended_at` (по умолчанию — час назад)."""
    base = ended_at or ctx.now() - timedelta(hours=1)
    s = ctx.settings
    spread_hours = days * 24 / max(count, 1)
    for i in range(count):
        n = next(_seq)
        ctx.session.add(Order(
            external_order_id=f"ord-{n}", driver_profile_id=profile_id, tariff_class=tariff,
            tariff_source="order" if tariff else "default", status=status,
            price=price if price is not None else s.int("min_order_price") * 2,
            distance_m=distance_m if distance_m is not None else s.int("min_order_distance_m") * 5,
            duration_sec=duration_sec if duration_sec is not None else s.int("min_order_duration_sec") * 5,
            ended_at=base - timedelta(hours=spread_hours * i), booked_at=base - timedelta(hours=spread_hours * i, minutes=20),
            address_from=address_from or f"A{n}", address_to=address_to or f"B{n}"))
    await ctx.session.flush()


async def period_for(ctx: Ctx, code: str):  # type: ignore[no-untyped-def]
    return await open_period(ctx, code)


async def current(ctx: Ctx):  # type: ignore[no-untyped-def]
    return await ensure_current_period(ctx)


async def ledger_sum(ctx: Ctx, user_id: int) -> int:
    return int(await ctx.session.scalar(select(func.coalesce(func.sum(WalletLedger.amount), 0))
                                        .where(WalletLedger.user_id == user_id)) or 0)


async def accrual_sum(ctx: Ctx, user_id: int, status: str) -> int:
    return int(await ctx.session.scalar(select(func.coalesce(func.sum(Accrual.amount), 0))
                                        .where(Accrual.user_id == user_id, Accrual.status == status)) or 0)


async def assert_wallet_invariants(ctx: Ctx, user_id: int) -> None:
    """Инварианты Раздела 10 / TC-86."""
    ctx.session.expire_all()
    user = await ctx.session.get(User, user_id)
    assert user is not None
    assert user.balance_available >= 0 and user.debt >= 0
    assert await ledger_sum(ctx, user_id) == user.balance_available, "SUM(ledger) != balance_available"
    assert await accrual_sum(ctx, user_id, "available") == user.balance_available
    assert await accrual_sum(ctx, user_id, "hold") == user.balance_hold
    completed = int(await ctx.session.scalar(select(func.coalesce(func.sum(Withdrawal.amount), 0)).where(
        Withdrawal.user_id == user_id, Withdrawal.status == "completed")) or 0)
    assert completed == await accrual_sum(ctx, user_id, "withdrawn"), "completed withdrawals != withdrawn accruals"
    active = (await ctx.session.execute(select(Withdrawal).where(
        Withdrawal.user_id == user_id,
        Withdrawal.status.in_(["pending", "awaiting_approval", "processing", "verifying"])))).scalars().all()
    assert len(active) <= 1
    reserved = await accrual_sum(ctx, user_id, "reserved")
    assert reserved == sum(w.amount for w in active)
    last = (await ctx.session.execute(select(WalletLedger).where(WalletLedger.user_id == user_id)
                                      .order_by(WalletLedger.id.desc()).limit(1))).scalar_one_or_none()
    if last is not None:
        assert last.balance_after == user.balance_available and last.debt_after == user.debt


async def run_queue(ctx: Ctx, max_steps: int = 50) -> list[str]:
    """Исполняет поставленные задачи вывода (эмуляция воркера ARQ)."""
    from src.core.billing.withdrawal import process_withdrawal, verify_withdrawal
    results = []
    for _ in range(max_steps):
        calls = ctx.queue.pop_all()  # type: ignore[attr-defined]
        if not calls:
            break
        for name, args, _delay in calls:
            if name == "process_withdrawal":
                results.append(await process_withdrawal(ctx, *args))
            elif name == "verify_withdrawal":
                results.append(await verify_withdrawal(ctx, *args))
    return results


async def outbox_keys(ctx: Ctx, user_id: int | None = None) -> list[str]:
    await ctx.session.flush()
    q = "SELECT template_key FROM notification_outbox"
    params: dict[str, Any] = {}
    if user_id is not None:
        q += " WHERE user_id = :u"
        params["u"] = user_id
    return [r[0] for r in (await ctx.session.execute(text(q + " ORDER BY id"), params)).all()]


async def with_profile(ctx: Ctx, user: User, work_status: str = "working") -> str:
    p = await add_profile(ctx, phone=user.phone, license_=user.driver_license, work_status=work_status)
    await link(ctx, user, p)
    return p.driver_profile_id
