"""Admin API: авторизация с 2FA, RBAC, ключевые эндпоинты (TC-95…TC-99, TC-101)."""

from __future__ import annotations

import pyotp
import pytest
from httpx import ASGITransport, AsyncClient

from src.admin.auth import hash_password
from src.db.models import AdminCredential, SettingsHistory
from src.runtime import set_clock, set_fleet
from tests.factories import add_orders, counted_referral, create_user


@pytest.fixture
async def client(sessionmaker, fleet, clock):
    from src.web import app
    set_fleet(fleet)
    set_clock(clock)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        yield c
    set_fleet(None)
    set_clock(None)


async def _staff(ctx, role, login_, totp=True):
    u = await create_user(ctx, role=role)
    secret = pyotp.random_base32() if totp else None
    ctx.session.add(AdminCredential(user_id=u.id, login=login_, password_hash=hash_password("pw"), totp_secret=secret))
    await ctx.session.commit()
    return u, secret


async def _token(client, login_, secret=None):
    body = {"login": login_, "password": "pw"}
    if secret:
        body["totp"] = pyotp.TOTP(secret).now()
    r = await client.post("/admin/api/auth/login", json=body)
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


async def test_login_requires_2fa_for_admin(client, ctx):
    _, secret = await _staff(ctx, "admin", "boss")
    r = await client.post("/admin/api/auth/login", json={"login": "boss", "password": "pw"})
    assert r.status_code == 401
    r = await client.post("/admin/api/auth/login", json={"login": "boss", "password": "bad", "totp": "1"})
    assert r.status_code == 401
    await _token(client, "boss", secret)
    await _staff(ctx, "operator", "op", totp=False)
    await _token(client, "op")


async def test_rbac(client, ctx):
    await _staff(ctx, "operator", "op", totp=False)
    h = await _token(client, "op")
    assert (await client.get("/admin/api/dashboard", headers=h)).status_code == 200
    assert (await client.put("/admin/api/settings/min_order_price", json={"value": 1}, headers=h)).status_code == 403
    assert (await client.get("/admin/api/dashboard")).status_code == 401


async def test_rules_flow(client, ctx, clock):
    from datetime import timedelta

    from src.core.billing.periods import close_period, ensure_current_period
    _, secret = await _staff(ctx, "admin", "boss")
    h = await _token(client, "boss", secret)
    r = await client.put("/admin/api/rules/tariffs/cargo", json={"coefficient_x100": 250}, headers=h)
    cargo = next(t for t in r.json() if t["code"] == "cargo")
    assert cargo["orders_to_plan"] == 120  # TC-95
    r = await client.put("/admin/api/settings/min_order_price", json={"value": 6000}, headers=h)
    assert r.json()["value"] == 6000
    r = await client.put("/admin/api/settings/referred_bonus_enabled", json={"value": True}, headers=h)
    assert r.status_code == 400 and r.json()["error"] == "err.simulation_required"
    # симулятор и включение welcome с обязательной симуляцией
    referrer, friend, ref, pid = await counted_referral(ctx)
    await add_orders(ctx, pid, 300, "econom")
    period = await ensure_current_period(ctx)
    clock.set(period.ends_at + timedelta(hours=2))
    await close_period(ctx, period)
    r = await client.post("/admin/api/rules/welcome", json={"enabled": True}, headers=h)
    assert r.json()["confirm_required"] and r.json()["simulation"]["draft"]["welcome_payout"] == 20000
    r = await client.post("/admin/api/rules/welcome", json={"enabled": True, "confirm": True}, headers=h)
    assert r.status_code == 200
    r = await client.post("/admin/api/rules/simulate", json={"period": "2026-08", "draft": {"threshold_points_x100": 40000}},
                          headers=h)
    assert r.json()["draft"]["qualified"] == 0 and r.json()["current"]["qualified"] == 1
    r = await client.post("/admin/api/periods/2026-08/recalculate", json={"reason": "check", "preview": True}, headers=h)
    assert r.status_code == 200 and r.json()["preview"]
    r = await client.get("/admin/api/reports/channels?format=xlsx", headers=h)
    assert r.status_code == 200 and r.content[:2] == b"PK"
    r = await client.post("/admin/api/settings/fleet-categories/load", headers=h)
    assert {c["id"] for c in r.json()} == {"cat-bonus", "cat-other"}  # TC-98
    hist = (await ctx.session.execute(__import__("sqlalchemy").select(SettingsHistory))).scalars().all()
    assert {h_.entity for h_ in hist} >= {"tariff", "settings"} and all(h_.changed_by for h_ in hist)  # TC-99


async def test_driver_card_and_actions(client, ctx):
    _, secret = await _staff(ctx, "admin", "boss")
    h = await _token(client, "boss", secret)
    referrer, friend, ref, pid = await counted_referral(ctx)
    await ctx.session.commit()
    r = await client.get(f"/admin/api/drivers?q={friend.phone}", headers=h)
    assert r.json()[0]["id"] == friend.id
    r = await client.get(f"/admin/api/drivers/{referrer.id}", headers=h)
    assert r.json()["referrals"][0]["id"] == ref.id
    r = await client.post(f"/admin/api/drivers/{referrer.id}/adjustment", json={"amount": 5000, "reason": "приз"},
                          headers=h)
    assert r.status_code == 200
    r = await client.get("/admin/api/dashboard", headers=h)
    assert r.json()["funnel"]["approved"] == 1


async def test_health_and_webhook_secret(client, monkeypatch):
    r = await client.get("/health")
    assert r.status_code == 200 and r.json()["db"] is True
    from src.config import get_config
    monkeypatch.setattr(get_config(), "webhook_secret", "s3cret")
    r = await client.post("/webhook/telegram", json={}, headers={"X-Telegram-Bot-Api-Secret-Token": "bad"})
    assert r.status_code == 403
