"""TC-24…TC-27, TC-98: Fleet API, зеркало базы водителей, классы ошибок, circuit breaker."""

from __future__ import annotations

from datetime import UTC, datetime

import httpx
import pytest
from sqlalchemy import func, select

from src.core.referral.matching import find_profile
from src.core.sync.park_profiles import sync_park_driver_profiles
from src.db.models import ApiSyncLog, ParkDriverProfile
from src.integrations.fleet.api import ApiFleetProvider
from src.integrations.fleet.base import FleetDriverProfile
from src.integrations.fleet.circuit import CircuitBreaker
from src.integrations.fleet.errors import (
    CircuitOpenError,
    NonRetryableFleetError,
    RetryableFleetError,
    UnknownOutcomeError,
)


def _p(i, **kw):
    return FleetDriverProfile(id=f"d{i}", park_id="park-1", phone=kw.get("phone", f"+99890{i:07d}"),
                              driver_license=kw.get("lic", f"BB{i:07d}"), first_name="A", last_name="B",
                              work_status=kw.get("work_status", "working"),
                              created_date=datetime(2026, 1, 1, tzinfo=UTC))


async def test_sync_profiles_idempotent_tc24_tc25(ctx, fleet):
    for i in range(1, 8):
        fleet.add_driver(_p(i))
    await sync_park_driver_profiles(ctx)
    await sync_park_driver_profiles(ctx)
    assert await ctx.session.scalar(select(func.count()).select_from(ParkDriverProfile)) == 7
    found = await find_profile(ctx, "+998900000003", None)
    assert found is not None and found.driver_profile_id == "d3"


async def test_license_fetched_individually_only_for_new_tc26(ctx, fleet):
    fleet.add_driver(_p(1, lic="ab 765-4321"), license_in_list=False)
    fleet.add_driver(_p(2))
    await sync_park_driver_profiles(ctx)
    assert fleet.get_driver_calls == ["d1"]
    found = await find_profile(ctx, None, "AB7654321")
    assert found is not None and found.driver_profile_id == "d1"
    await sync_park_driver_profiles(ctx)
    assert fleet.get_driver_calls == ["d1"]  # повторно не добирается


async def test_fired_friend_notification(ctx, fleet):
    from tests.factories import counted_referral, outbox_keys
    referrer, friend, ref, pid = await counted_referral(ctx)
    fleet.add_driver(FleetDriverProfile(id=pid, park_id="park-1", phone=friend.phone, work_status="fired"))
    await sync_park_driver_profiles(ctx)
    await sync_park_driver_profiles(ctx)
    assert (await outbox_keys(ctx, referrer.id)).count("referral.friend_fired") == 1


async def _log_sink_factory(ctx):
    async def sink(rec):
        ctx.session.add(ApiSyncLog(**rec))
        await ctx.session.flush()
    return sink


def _api(handler, ctx_sink=None, **kw):
    return ApiFleetProvider("https://fleet.test", "cid", "key", "park-1", transport=httpx.MockTransport(handler),
                            log_sink=ctx_sink, read_retries=1, **kw)


async def test_api_unavailable_logged_tc27(ctx):
    def handler(request):
        raise httpx.ConnectError("down")
    api = _api(handler, await _log_sink_factory(ctx))
    ctx.fleet = api
    with pytest.raises(RetryableFleetError):
        await sync_park_driver_profiles(ctx)
    row = (await ctx.session.execute(select(ApiSyncLog))).scalars().first()
    assert row is not None and row.method == "list_drivers" and "connect" in row.error
    assert "key" not in (row.error or "")  # ключи не логируются


async def test_error_classes():
    def make(status=None, exc=None):
        def handler(request):
            if exc:
                raise exc
            return httpx.Response(status, json={})
        return _api(handler)
    with pytest.raises(NonRetryableFleetError):
        await make(400).create_driver_transaction("d", 1, "c", "x", "tok")
    with pytest.raises(RetryableFleetError):
        await make(500).create_driver_transaction("d", 1, "c", "x", "tok")
    with pytest.raises(RetryableFleetError):
        await make(429).create_driver_transaction("d", 1, "c", "x", "tok")
    with pytest.raises(UnknownOutcomeError):
        await make(exc=httpx.ReadTimeout("t")).create_driver_transaction("d", 1, "c", "x", "tok")


async def test_create_transaction_headers_and_endpoint():
    seen = {}

    def handler(request):
        seen["path"] = request.url.path
        seen["headers"] = dict(request.headers)
        return httpx.Response(200, json={"id": "TX-1"})
    res = await _api(handler).create_driver_transaction("d1", 30000, "cat", "Bonus REFBOT-W1", "tok-1")
    assert res.transaction_id == "TX-1"
    assert seen["path"] == "/v3/parks/driver-profiles/transactions"  # не [Устаревший] v2 (R13)
    assert seen["headers"]["x-idempotency-token"] == "tok-1" and seen["headers"]["x-park-id"] == "park-1"


async def test_circuit_breaker_opens():
    t = [0.0]
    breaker = CircuitBreaker(5, 300, clock=lambda: t[0])
    calls = []

    def handler(request):
        calls.append(1)
        return httpx.Response(503)
    api = _api(handler, breaker=breaker)
    for _ in range(5):
        with pytest.raises(RetryableFleetError):
            await api.list_transaction_categories()
    with pytest.raises(CircuitOpenError):
        await api.list_transaction_categories()
    assert len(calls) == 5
    t[0] = 301
    with pytest.raises(RetryableFleetError):
        await api.list_transaction_categories()
    assert len(calls) == 6


async def test_pagination_stops_on_repeating_pages(ctx):
    pages = []

    def handler(request):
        pages.append(1)
        body = {"driver_profiles": [{"driver_profile": {"id": f"x{i}", "phones": [f"+99891{i:07d}"],
                                                        "driver_license": {"number": f"CC{i:07d}"}}}
                                    for i in range(500)]}
        return httpx.Response(200, json=body)
    ctx.fleet = _api(handler)
    res = await sync_park_driver_profiles(ctx)
    assert res["profiles"] == 500 and len(pages) <= 3


async def test_load_transaction_categories_tc98(ctx, fleet):
    from src.core.admin.settings_admin import load_fleet_categories
    admin = __import__("tests.factories", fromlist=["create_user"])
    user = await admin.create_user(ctx, role="admin")
    cats = await load_fleet_categories(ctx, user)
    assert {c["id"] for c in cats} == {"cat-bonus", "cat-other"}
    assert ctx.settings.list("fleet_transaction_categories") == cats
