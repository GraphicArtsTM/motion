"""Мастер настройки: проверки Telegram и Fleet, запись .env, применение настроек в БД."""

from __future__ import annotations

import json

import httpx
import pyotp
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from src.db.models import AdminCredential, Setting, User
from src.setup_wizard import app as wizard
from src.setup_wizard.checks import classify, fleet_check, telegram_chats, telegram_check
from src.setup_wizard.envfile import read_env, write_env


def tg_transport(ok=True):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/getMe"):
            return httpx.Response(200, json={"ok": ok, "result": {"id": 1, "username": "park_ref_bot", "first_name": "Парк"}}
                                  if ok else {"ok": False, "description": "Unauthorized"})
        return httpx.Response(200, json={"ok": True, "result": [
            {"update_id": 1, "message": {"chat": {"id": 555, "type": "private"},
                                         "from": {"id": 555, "first_name": "Азиз", "username": "aziz", "is_bot": False}}},
            {"update_id": 2, "my_chat_member": {"chat": {"id": -100777, "type": "supergroup", "title": "Админы парка"},
                                                "from": {"id": 555, "first_name": "Азиз", "is_bot": False}}}]})
    return httpx.MockTransport(handler)


async def test_telegram_checks():
    assert (await telegram_check("123:abc", tg_transport()))["username"] == "park_ref_bot"
    assert not (await telegram_check("123:abc", tg_transport(ok=False)))["ok"]
    assert not (await telegram_check("garbage"))["ok"]
    chats = await telegram_chats("123:abc", tg_transport())
    assert chats["people"] == [{"id": 555, "name": "Азиз", "username": "aziz"}]
    assert chats["groups"] == [{"id": -100777, "title": "Админы парка"}]


def fleet_transport(denied: set[str] = frozenset(), bad_key: bool = False):
    from src.integrations.fleet.api import ENDPOINTS
    by_path = {path: op for op, (_, path) in ENDPOINTS.items()}

    def handler(request: httpx.Request) -> httpx.Response:
        op = by_path[request.url.path]
        if bad_key:
            return httpx.Response(401, json={"message": "unauthorized"})
        if op in denied:
            return httpx.Response(403, json={"message": "forbidden"})
        if op == "list_drivers":
            return httpx.Response(200, json={"total": 812, "driver_profiles": [
                {"driver_profile": {"id": "d1", "driver_license": {"number": "AB1234567"}}, "car": {"id": "c1"}}]})
        if op == "list_orders":
            return httpx.Response(200, json={"orders": [{"id": "o1", "category": "cargo", "price": "45000"}]})
        if op == "list_transaction_categories":
            return httpx.Response(200, json={"categories": [{"id": "cat1", "name": "Бонус", "is_enabled": True},
                                                            {"id": "cat2", "name": "Старое", "is_enabled": False}]})
        if op in ("create_driver_transaction", "get_transaction_status", "get_driver_blocked_balance"):
            return httpx.Response(400 if op == "create_driver_transaction" else 404, json={"message": "not found"})
        return httpx.Response(200, json={})
    return httpx.MockTransport(handler)


async def test_fleet_check_all_ok():
    r = await fleet_check("https://f.test", "taxi/park/x", "key", "park", fleet_transport())
    assert r["ok"] and r["key_valid"]
    assert all(c["status"] == "ok" for c in r["checks"])
    assert r["categories"] == [{"id": "cat1", "name": "Бонус"}]
    assert r["facts"]["Тариф (category) в заказах"] is True and r["facts"]["Номер ВУ в списке профилей"] is True


async def test_fleet_check_missing_access_and_bad_key():
    r = await fleet_check("https://f.test", "c", "k", "p", fleet_transport(denied={"list_orders", "create_driver_transaction"}))
    statuses = {c["op"]: c["status"] for c in r["checks"]}
    assert statuses["list_orders"] == "no_access" and statuses["create_driver_transaction"] == "no_access"
    assert not r["ok"] and "доступ" in r["error"]
    r = await fleet_check("https://f.test", "c", "k", "p", fleet_transport(denied={"create_driver_transaction"}))
    assert r["ok"]  # без выплат бот работает — включится ручной вывод
    r = await fleet_check("https://f.test", "c", "k", "p", fleet_transport(bad_key=True))
    assert not r["ok"] and r["key_valid"] is False
    assert (await fleet_check("https://f.test", "", "", ""))["error"]
    assert classify(404, True)[0] == "ok" and classify(404, False)[0] == "error" and classify(None, True)[0] == "error"


def test_env_roundtrip(tmp_path):
    p = tmp_path / ".env"
    write_env(p, {"BOT_TOKEN": "1:a", "PARK": "a b # c", "EXTRA": "x"})
    assert read_env(p) == {"BOT_TOKEN": "1:a", "PARK": "a b # c", "EXTRA": "x", **{
        k: "" for k in read_env(p) if k not in ("BOT_TOKEN", "PARK", "EXTRA")}}


@pytest.fixture
def workspace(tmp_path, monkeypatch):
    monkeypatch.setattr(wizard, "ENV_PATH", tmp_path / ".env")
    monkeypatch.setattr(wizard, "CONFIG_DIR", tmp_path / "config")
    monkeypatch.setattr(wizard, "NGINX_TEMPLATE", tmp_path / "nginx.conf.template")
    monkeypatch.setattr(wizard, "NGINX_OUT", tmp_path / "nginx.generated.conf")
    (tmp_path / "nginx.conf.template").write_text("server_name __DOMAIN__;", encoding="utf-8")
    return tmp_path


async def test_save_writes_env_and_settings(workspace):
    secret = pyotp.random_base32()
    body = {"bot_token": "1:abc", "bot_username": "@park_ref_bot", "admin_ids": [555, 666], "admin_chat_id": -100777,
            "fleet_client_id": "taxi/park/x", "fleet_api_key": "KEY", "fleet_park_id": "park1",
            "fleet_category_id": "cat1", "fleet_categories": [{"id": "cat1", "name": "Бонус"}], "can_payout": False,
            "park_contacts": "<b>Парк</b>", "panel_login": "boss", "panel_password": "secret-pass",
            "totp_secret": secret, "totp_code": pyotp.TOTP(secret).now()}
    async with AsyncClient(transport=ASGITransport(app=wizard.app), base_url="http://w") as c:
        bad = (await c.post("/api/save", json={**body, "admin_ids": [], "totp_code": "000000"})).json()
        assert not bad["ok"] and len(bad["errors"]) == 2
        r = (await c.post("/api/save", json=body)).json()
        assert r["ok"] and r["mode"] == "polling" and r["bot_link"] == "https://t.me/park_ref_bot"
        env = read_env(workspace / ".env")
        assert env["BOT_MODE"] == "polling" and env["COMPOSE_PROFILES"] == "polling"
        assert env["ADMIN_TELEGRAM_IDS"] == "555,666" and env["FLEET_API_KEY"] == "KEY"
        pg = env["POSTGRES_PASSWORD"]
        assert pg in env["DATABASE_URL"] and len(env["ADMIN_SECRET_KEY"]) > 30
        init = json.loads((workspace / "config" / "initial_settings.json").read_text(encoding="utf-8"))
        assert init["settings"]["withdrawal_mode"] == "manual"  # нет доступа к созданию транзакций
        assert init["settings"]["fleet_provider"] == "api" and init["admin"]["telegram_id"] == 555
        assert init["admin"]["password_hash"].startswith("scrypt$")
        # повторная настройка: пустые секреты не затираются, пароль БД не меняется, домен → webhook
        r = (await c.post("/api/save", json={**body, "bot_token": "", "fleet_api_key": "", "panel_password": "",
                                             "mode": "webhook", "domain": "https://bot.park.uz/"})).json()
        env = read_env(workspace / ".env")
        assert env["BOT_TOKEN"] == "1:abc" and env["FLEET_API_KEY"] == "KEY" and env["POSTGRES_PASSWORD"] == pg
        assert env["WEBHOOK_URL"] == "https://bot.park.uz/webhook/telegram" and env["COMPOSE_PROFILES"] == "webhook"
        assert (workspace / "nginx.generated.conf").read_text(encoding="utf-8") == "server_name bot.park.uz;"
        current = (await c.get("/api/current")).json()
        assert current["bot_token_masked"] == "•••" and current["admin_ids"] == [555, 666]
        page = await c.get("/")
        assert "Настройка реферального бота" in page.text
        totp = (await c.post("/api/totp/new?login=boss")).json()
        assert totp["qr"].startswith("data:image/png;base64,")


async def test_bootstrap_applies_settings(sessionmaker, tmp_path, monkeypatch):
    from src import bootstrap
    from src.admin.auth import hash_password
    monkeypatch.setattr(bootstrap, "CONFIG_DIR", tmp_path)
    (tmp_path / "initial_settings.json").write_text(json.dumps({
        "settings": {"park_contacts": "<b>Наш парк</b>", "withdrawal_mode": "manual", "unknown_key": 1},
        "admin": {"telegram_id": 777, "login": "boss", "password_hash": hash_password("x" * 8),
                  "totp_secret": "ABC", "role": "superadmin"}}), encoding="utf-8")
    await bootstrap.main()
    assert not (tmp_path / "initial_settings.json").exists()
    applied = json.loads((tmp_path / "initial_settings.applied.json").read_text(encoding="utf-8"))
    assert "password_hash" not in applied["admin"] and "totp_secret" not in applied["admin"]
    async with sessionmaker() as s:
        assert (await s.get(Setting, "park_contacts")).value == "<b>Наш парк</b>"
        assert (await s.get(Setting, "withdrawal_mode")).value == "manual"
        user = (await s.execute(select(User).where(User.telegram_id == 777))).scalar_one()
        assert user.role == "superadmin" and user.access_status == "approved"
        assert (await s.execute(select(AdminCredential))).scalar_one().login == "boss"
    await bootstrap.main()  # повторный запуск — ничего не делает
