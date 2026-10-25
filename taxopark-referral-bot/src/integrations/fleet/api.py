"""ApiFleetProvider — реальный Яндекс Fleet API.

Пути и имена полей собраны в одном месте (ENDPOINTS и функции `_map_*`). Они
должны быть подтверждены на Шаге 0 скриптом `scripts/api_recon.py`, а результат
зафиксирован в API_SCHEMA.md. Денежные строки API ("23400.0000") переводятся в
целые сумы через Decimal — float не используется (R1).
"""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable
from datetime import UTC, date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import Any
from zoneinfo import ZoneInfo

import httpx
from tenacity import AsyncRetrying, retry_if_exception_type, stop_after_attempt, wait_exponential

from src.config import get_config
from src.db import seeds
from src.integrations.fleet.base import (
    DriverTransaction,
    FleetCar,
    FleetDriverProfile,
    FleetOrder,
    FleetProvider,
    TransactionCategory,
    TransactionResult,
    TransactionStatus,
    WorkRule,
)
from src.integrations.fleet.circuit import CircuitBreaker
from src.integrations.fleet.errors import (
    FleetError,
    NonRetryableFleetError,
    RetryableFleetError,
    UnknownOutcomeError,
)

LogSink = Callable[[dict[str, Any]], Awaitable[None]]

ENDPOINTS = {
    "list_drivers": ("POST", "/v1/parks/driver-profiles/list"),
    "get_driver": ("GET", "/v2/parks/contractors/driver-profile"),
    "list_orders": ("POST", "/v1/parks/orders/list"),
    "list_cars": ("POST", "/v1/parks/cars/list"),
    "get_car": ("GET", "/v2/parks/vehicles/car"),
    "list_transaction_categories": ("POST", "/v2/parks/transactions/categories/list"),
    # НЕ «[Устаревший] Создание транзакции» (/v2/parks/driver-profiles/transactions) — R13
    "create_driver_transaction": ("POST", "/v3/parks/driver-profiles/transactions"),
    "get_transaction_status": ("GET", "/v3/parks/driver-profiles/transactions/status"),
    "list_driver_transactions": ("POST", "/v2/parks/driver-profiles/transactions/list"),
    "get_driver_online_time": ("GET", "/v2/parks/contractors/supply-hours"),
    "list_work_rules": ("GET", "/v1/parks/driver-work-rules"),
    "get_driver_blocked_balance": ("GET", "/v2/parks/contractors/blocked-balance"),
}

NON_RETRYABLE = {400, 401, 403, 404, 409, 422}
SUCCESS_TX_STATUSES = {"success", "completed", "done", "applied"}
FAILED_TX_STATUSES = {"failed", "rejected", "cancelled", "canceled", "error"}


# ── парсинг ──────────────────────────────────────────────────────────────────
def parse_money(value: Any) -> int:
    """'23400.5000' → 23401 (целые сумы, банковское округление не используется)."""
    if value is None or value == "":
        return 0
    try:
        return int(Decimal(str(value)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    except (InvalidOperation, ValueError):
        return 0


def parse_int(value: Any) -> int:
    return parse_money(value)


def parse_dt(value: Any) -> datetime | None:
    if not value:
        return None
    s = str(value).strip().replace("Z", "+00:00")
    if len(s) >= 5 and (s[-5] in "+-") and s[-3] != ":":
        s = s[:-2] + ":" + s[-2:]  # +0000 → +00:00
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=UTC)


def parse_date(value: Any) -> date | None:
    if not value:
        return None
    dt = parse_dt(value)
    if dt:
        return dt.date()
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def pick_category(categories: Any) -> str | None:
    """Основная категория авто: грузовая приоритетна, иначе первая (D-14)."""
    if isinstance(categories, str):
        return categories
    if not categories:
        return None
    cats = [str(c) for c in categories]
    return "cargo" if "cargo" in cats else cats[0]


def _map_driver(item: dict[str, Any], park_id: str) -> FleetDriverProfile:
    dp = item.get("driver_profile", item)
    car = item.get("car") or {}
    lic = dp.get("driver_license") or {}
    phones = dp.get("phones") or []
    return FleetDriverProfile(
        id=str(dp.get("id")),
        park_id=str(dp.get("park_id") or park_id),
        phone=phones[0] if phones else dp.get("phone"),
        driver_license=lic.get("normalized_number") or lic.get("number") if isinstance(lic, dict) else lic,
        first_name=dp.get("first_name"),
        last_name=dp.get("last_name"),
        middle_name=dp.get("middle_name"),
        work_status=dp.get("work_status"),
        work_rule_id=dp.get("work_rule_id"),
        hire_date=parse_date(dp.get("hire_date")),
        fire_date=parse_date(dp.get("fire_date")),
        car_id=car.get("id") or dp.get("car_id"),
        car_category=pick_category(car.get("category") or car.get("categories")),
        created_date=parse_dt(dp.get("created_date")),
        raw=item,
    )


def _map_driver_v2(data: dict[str, Any], driver_profile_id: str, park_id: str) -> FleetDriverProfile:
    person = data.get("person") or {}
    name = person.get("full_name") or {}
    lic = person.get("driver_license") or {}
    contact = person.get("contact_info") or {}
    profile = data.get("profile") or {}
    return FleetDriverProfile(
        id=driver_profile_id,
        park_id=park_id,
        phone=contact.get("phone"),
        driver_license=lic.get("number"),
        first_name=name.get("first_name"),
        last_name=name.get("last_name"),
        middle_name=name.get("middle_name"),
        work_status=profile.get("work_status"),
        hire_date=parse_date(profile.get("hire_date")),
        fire_date=parse_date(profile.get("fire_date")),
        car_id=data.get("car_id"),
        raw=data,
    )


def _address(value: Any) -> str | None:
    if isinstance(value, dict):
        return value.get("address") or value.get("fullname")
    return value


def _map_order(item: dict[str, Any]) -> FleetOrder:
    ended = parse_dt(item.get("ended_at"))
    started = parse_dt(item.get("transporting_at") or item.get("driving_at") or item.get("booked_at"))
    duration = int((ended - started).total_seconds()) if ended and started and ended > started else 0
    if item.get("duration") is not None:
        duration = parse_int(item.get("duration"))
    route = item.get("route_points") or []
    return FleetOrder(
        id=str(item.get("id")),
        driver_profile_id=str((item.get("driver_profile") or {}).get("id") or item.get("driver_profile_id")),
        status=str(item.get("status")),
        # E9: стоимость заказа — поле `price` (подтверждается в API_SCHEMA.md)
        price=parse_money(item.get("price")),
        distance_m=parse_int(item.get("mileage") if item.get("mileage") is not None else item.get("distance")),
        duration_sec=duration,
        booked_at=parse_dt(item.get("booked_at")),
        ended_at=ended,
        tariff_class=item.get("category") or item.get("tariff_class"),
        car_id=(item.get("car") or {}).get("id"),
        payment_method=item.get("payment_method"),
        address_from=_address(item.get("address_from")),
        address_to=_address(route[-1]) if route else _address(item.get("address_to")),
        raw=item,
    )


def _map_car(item: dict[str, Any]) -> FleetCar:
    cats = item.get("category") or (item.get("park_profile") or {}).get("categories") or []
    cats_list = [cats] if isinstance(cats, str) else list(cats)
    return FleetCar(id=str(item.get("id") or item.get("vehicle_id")), category=pick_category(cats_list),
                    categories=cats_list, raw=item)


# ── провайдер ────────────────────────────────────────────────────────────────
class ApiFleetProvider(FleetProvider):
    name = "api"

    def __init__(
        self,
        base_url: str,
        client_id: str,
        api_key: str,
        park_id: str,
        *,
        log_sink: LogSink | None = None,
        transport: httpx.AsyncBaseTransport | None = None,
        breaker: CircuitBreaker | None = None,
        read_retries: int = 3,
    ) -> None:
        self.park_id = park_id
        self._headers = {
            "X-Client-ID": client_id,
            "X-API-Key": api_key,
            "X-Park-ID": park_id,
            "Accept-Language": "ru",
        }
        self._client = httpx.AsyncClient(
            base_url=base_url,
            timeout=httpx.Timeout(seeds.FLEET_READ_TIMEOUT, connect=seeds.FLEET_CONNECT_TIMEOUT),
            transport=transport,
        )
        self.breaker = breaker or CircuitBreaker(seeds.FLEET_BREAKER_FAILURES, seeds.FLEET_BREAKER_PAUSE_SECONDS)
        self._log_sink = log_sink
        self._read_retries = read_retries
        self._order_cursors: dict[tuple[str, str, int], str | None] = {}

    async def aclose(self) -> None:
        await self._client.aclose()

    # ── транспорт ───────────────────────────────────────────────────────────
    async def _log(self, method: str, status: int | None, started: float, records: int | None,
                   error: str | None) -> None:
        if self._log_sink is None:
            return
        try:
            await self._log_sink({
                "provider": self.name, "method": method, "status_code": status,
                "duration_ms": int((time.monotonic() - started) * 1000),
                "records_count": records, "error": (error or "")[:1000] or None,
            })
        except Exception:  # noqa: BLE001 — журнал не должен ломать вызов
            pass

    async def _send(self, op: str, *, json: Any = None, params: dict[str, Any] | None = None,
                    headers: dict[str, str] | None = None) -> dict[str, Any]:
        method, path = ENDPOINTS[op]
        self.breaker.before_call()
        started = time.monotonic()
        try:
            resp = await self._client.request(method, path, json=json, params=params,
                                              headers={**self._headers, **(headers or {})})
        except (httpx.ConnectError, httpx.ConnectTimeout) as e:
            # запрос не ушёл на сервер — операция точно не выполнена
            self.breaker.record_failure()
            await self._log(op, None, started, None, f"connect: {type(e).__name__}")
            raise RetryableFleetError(f"connect error: {type(e).__name__}") from e
        except (httpx.TimeoutException, httpx.TransportError) as e:
            self.breaker.record_failure()
            await self._log(op, None, started, None, f"transport: {type(e).__name__}")
            raise UnknownOutcomeError(f"unknown outcome: {type(e).__name__}") from e

        status = resp.status_code
        if status >= 500 or status == 429:
            self.breaker.record_failure()
            await self._log(op, status, started, None, resp.text[:300])
            raise RetryableFleetError(f"Fleet API {status}", status)
        if status >= 400:
            self.breaker.record_success()
            await self._log(op, status, started, None, resp.text[:300])
            raise NonRetryableFleetError(f"Fleet API {status}: {resp.text[:200]}", status)
        self.breaker.record_success()
        try:
            data = resp.json() if resp.content else {}
        except ValueError as e:
            await self._log(op, status, started, None, "invalid json")
            raise RetryableFleetError("invalid JSON from Fleet API", status) from e
        records = None
        for key in ("driver_profiles", "orders", "cars", "transactions", "categories", "rules"):
            if isinstance(data, dict) and isinstance(data.get(key), list):
                records = len(data[key])
        await self._log(op, status, started, records, None)
        return data if isinstance(data, dict) else {"items": data}

    async def _read(self, op: str, **kw: Any) -> dict[str, Any]:
        """Чтение — безопасно повторять, включая неизвестный исход."""
        async for attempt in AsyncRetrying(
            stop=stop_after_attempt(self._read_retries),
            wait=wait_exponential(multiplier=0.5, max=8),
            retry=retry_if_exception_type((RetryableFleetError, UnknownOutcomeError)),
            reraise=True,
        ):
            with attempt:
                return await self._send(op, **kw)
        raise FleetError("unreachable")  # pragma: no cover

    def _park_query(self, extra: dict[str, Any] | None = None) -> dict[str, Any]:
        park: dict[str, Any] = {"id": self.park_id}
        if extra:
            park.update(extra)
        return {"park": park}

    # ── методы ──────────────────────────────────────────────────────────────
    async def list_drivers(self, limit: int, offset: int) -> list[FleetDriverProfile]:
        data = await self._read("list_drivers", json={"query": self._park_query(), "limit": limit,
                                                      "offset": offset})
        return [_map_driver(i, self.park_id) for i in data.get("driver_profiles", [])]

    async def get_driver(self, driver_profile_id: str) -> FleetDriverProfile | None:
        try:
            data = await self._read("get_driver", params={"contractor_profile_id": driver_profile_id})
        except NonRetryableFleetError as e:
            if e.status_code == 404:
                return None
            raise
        return _map_driver_v2(data, driver_profile_id, self.park_id)

    async def list_orders(self, from_dt: datetime, to_dt: datetime, limit: int, offset: int) -> list[FleetOrder]:
        key = (from_dt.isoformat(), to_dt.isoformat(), offset)
        if offset and key not in self._order_cursors:
            # курсорная пагинация API: догоняем последовательно (D-15)
            current = 0
            while current < offset:
                await self.list_orders(from_dt, to_dt, limit, current)
                current += limit
                if self._order_cursors.get((key[0], key[1], current)) is None:
                    return []
        cursor = self._order_cursors.get(key) if offset else None
        body: dict[str, Any] = {
            "query": self._park_query({"order": {"ended_at": {"from": from_dt.isoformat(),
                                                              "to": to_dt.isoformat()}}}),
            "limit": limit,
        }
        if cursor:
            body["cursor"] = cursor
        data = await self._read("list_orders", json=body)
        orders = [_map_order(i) for i in data.get("orders", [])]
        self._order_cursors[(key[0], key[1], offset + limit)] = data.get("cursor") or None
        return orders

    async def list_cars(self, limit: int, offset: int) -> list[FleetCar]:
        data = await self._read("list_cars", json={"query": self._park_query(), "limit": limit, "offset": offset})
        return [_map_car(i) for i in data.get("cars", [])]

    async def get_car(self, car_id: str) -> FleetCar | None:
        try:
            data = await self._read("get_car", params={"vehicle_id": car_id})
        except NonRetryableFleetError as e:
            if e.status_code == 404:
                return None
            raise
        data.setdefault("id", car_id)
        return _map_car(data)

    async def list_transaction_categories(self) -> list[TransactionCategory]:
        data = await self._read("list_transaction_categories", json={"query": self._park_query()})
        return [TransactionCategory(id=str(c.get("id")), name=str(c.get("name")),
                                    is_enabled=bool(c.get("is_enabled", True)))
                for c in data.get("categories", [])]

    async def create_driver_transaction(self, driver_profile_id: str, amount: int, category_id: str,
                                        description: str, idempotency_token: str) -> TransactionResult:
        body = {
            "park_id": self.park_id,
            "contractor_profile_id": driver_profile_id,
            "amount": str(amount),  # положительная сумма — зачисление водителю
            "category_id": category_id,
            "description": description,
        }
        # без ретраев: мутирующая операция, повтор только после сверки (A11)
        data = await self._send("create_driver_transaction", json=body,
                                headers={"X-Idempotency-Token": idempotency_token})
        tx_id = data.get("id") or data.get("transaction_id") or (data.get("transaction") or {}).get("id")
        if not tx_id:
            raise UnknownOutcomeError("transaction id missing in response")
        return TransactionResult(transaction_id=str(tx_id), raw=data)

    async def get_transaction_status(self, transaction_id: str) -> TransactionStatus:
        data = await self._read("get_transaction_status", params={"transaction_id": transaction_id})
        status = str(data.get("status", "")).lower()
        return TransactionStatus(is_success=status in SUCCESS_TX_STATUSES,
                                 is_failed=status in FAILED_TX_STATUSES, raw=data)

    async def list_driver_transactions(self, driver_profile_id: str, from_dt: datetime,
                                       to_dt: datetime) -> list[DriverTransaction]:
        result: list[DriverTransaction] = []
        cursor: str | None = None
        for _ in range(seeds.FLEET_BATCH_SIZE):  # защита от бесконечного цикла
            body: dict[str, Any] = {
                "query": self._park_query({
                    "driver_profile": {"id": driver_profile_id},
                    "transaction": {"event_at": {"from": from_dt.isoformat(), "to": to_dt.isoformat()}},
                }),
                "limit": seeds.FLEET_BATCH_SIZE,
            }
            if cursor:
                body["cursor"] = cursor
            data = await self._read("list_driver_transactions", json=body)
            for t in data.get("transactions", []):
                result.append(DriverTransaction(
                    transaction_id=str(t.get("id")), amount=parse_money(t.get("amount")),
                    description=str(t.get("description") or ""), event_at=parse_dt(t.get("event_at")),
                    category_id=t.get("category_id")))
            cursor = data.get("cursor")
            if not cursor or not data.get("transactions"):
                break
        return result

    async def get_driver_online_time(self, driver_profile_id: str, day: date) -> int:
        start = datetime(day.year, day.month, day.day, tzinfo=ZoneInfo(get_config().tz_display))
        data = await self._read("get_driver_online_time", params={
            "contractor_profile_id": driver_profile_id,
            "period_from": start.isoformat(),
            "period_to": (start + timedelta(days=1)).isoformat(),
        })
        return parse_int(data.get("supply_duration_seconds"))

    async def list_work_rules(self) -> list[WorkRule]:
        data = await self._read("list_work_rules", params={"park_id": self.park_id})
        return [WorkRule(id=str(r.get("id")), name=str(r.get("name"))) for r in data.get("rules", [])]

    async def get_driver_blocked_balance(self, driver_profile_id: str) -> int | None:
        data = await self._read("get_driver_blocked_balance", params={"contractor_id": driver_profile_id})
        value = data.get("blocked_balance", data.get("balance"))
        return parse_money(value) if value is not None else None
