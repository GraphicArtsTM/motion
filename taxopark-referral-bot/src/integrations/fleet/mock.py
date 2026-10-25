"""MockFleetProvider — in-memory реализация для тестов и локальной разработки.

Поведение выплат управляется очередью сценариев `tx_script`:
"ok" | "timeout" | "500" | "429" | "400" | "connect".
"""

from __future__ import annotations

import itertools
from collections import deque
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any

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
from src.integrations.fleet.errors import NonRetryableFleetError, RetryableFleetError, UnknownOutcomeError


@dataclass
class MockTx:
    id: str
    driver_profile_id: str
    amount: int
    description: str
    idempotency_token: str
    event_at: datetime | None
    status: str = "success"


class MockFleetProvider(FleetProvider):
    name = "mock"

    def __init__(self, park_id: str = "park-1") -> None:
        self.park_id = park_id
        self.drivers: dict[str, FleetDriverProfile] = {}
        self.drivers_without_license_in_list: set[str] = set()
        self.orders: dict[str, FleetOrder] = {}
        self.cars: dict[str, FleetCar] = {}
        self.categories = [TransactionCategory(id="cat-bonus", name="Бонус реферальной программы"),
                           TransactionCategory(id="cat-other", name="Прочее")]
        self.work_rules = [WorkRule(id="wr-1", name="Свой автомобиль")]
        self.online_seconds: dict[tuple[str, date], int] = {}
        self.transactions: list[MockTx] = []
        self.tx_script: deque[str] = deque()
        self.lose_tx_on_timeout = False  # таймаут до записи транзакции
        self.status_lookup_supported = True
        self.unavailable = False
        self.calls: list[tuple[str, Any]] = []
        self.get_driver_calls: list[str] = []
        self._ids = itertools.count(1)

    def _check(self, op: str, payload: Any = None) -> None:
        self.calls.append((op, payload))
        if self.unavailable:
            raise RetryableFleetError("Fleet API unavailable", 503)

    # ── данные ──────────────────────────────────────────────────────────────
    def add_driver(self, profile: FleetDriverProfile, *, license_in_list: bool = True) -> None:
        self.drivers[profile.id] = profile
        if not license_in_list:
            self.drivers_without_license_in_list.add(profile.id)

    def add_order(self, order: FleetOrder) -> None:
        self.orders[order.id] = order

    # ── FleetProvider ──────────────────────────────────────────────────────
    async def list_drivers(self, limit: int, offset: int) -> list[FleetDriverProfile]:
        self._check("list_drivers", (limit, offset))
        items = sorted(self.drivers.values(), key=lambda p: p.id)[offset:offset + limit]
        out = []
        for p in items:
            if p.id in self.drivers_without_license_in_list:
                p = FleetDriverProfile(**{**p.__dict__, "driver_license": None})
            out.append(p)
        return out

    async def get_driver(self, driver_profile_id: str) -> FleetDriverProfile | None:
        self._check("get_driver", driver_profile_id)
        self.get_driver_calls.append(driver_profile_id)
        return self.drivers.get(driver_profile_id)

    async def list_orders(self, from_dt: datetime, to_dt: datetime, limit: int, offset: int) -> list[FleetOrder]:
        self._check("list_orders", (from_dt, to_dt, limit, offset))
        items = [o for o in self.orders.values()
                 if o.ended_at is None or from_dt <= o.ended_at <= to_dt]
        items.sort(key=lambda o: o.id)
        return items[offset:offset + limit]

    async def list_cars(self, limit: int, offset: int) -> list[FleetCar]:
        self._check("list_cars")
        return sorted(self.cars.values(), key=lambda c: c.id)[offset:offset + limit]

    async def get_car(self, car_id: str) -> FleetCar | None:
        self._check("get_car", car_id)
        return self.cars.get(car_id)

    async def list_transaction_categories(self) -> list[TransactionCategory]:
        self._check("list_transaction_categories")
        return list(self.categories)

    async def create_driver_transaction(self, driver_profile_id: str, amount: int, category_id: str,
                                        description: str, idempotency_token: str) -> TransactionResult:
        self._check("create_driver_transaction", (driver_profile_id, amount, description))
        step = self.tx_script.popleft() if self.tx_script else "ok"
        if step == "400":
            raise NonRetryableFleetError("bad request", 400)
        if step in ("500", "429"):
            raise RetryableFleetError(f"Fleet API {step}", int(step))
        if step == "connect":
            raise RetryableFleetError("connect error")
        # идемпотентность по токену, как у реального API
        for tx in self.transactions:
            if tx.idempotency_token == idempotency_token:
                if step == "timeout":
                    raise UnknownOutcomeError("timeout")
                return TransactionResult(transaction_id=tx.id)
        if step == "timeout" and self.lose_tx_on_timeout:
            raise UnknownOutcomeError("timeout before processing")
        tx = MockTx(id=f"TX-{next(self._ids)}", driver_profile_id=driver_profile_id, amount=amount,
                    description=description, idempotency_token=idempotency_token, event_at=None)
        self.transactions.append(tx)
        if step == "timeout":
            raise UnknownOutcomeError("timeout after processing")
        return TransactionResult(transaction_id=tx.id)

    async def get_transaction_status(self, transaction_id: str) -> TransactionStatus:
        self._check("get_transaction_status", transaction_id)
        if not self.status_lookup_supported:
            raise NonRetryableFleetError("not supported", 404)
        for tx in self.transactions:
            if tx.id == transaction_id:
                return TransactionStatus(is_success=tx.status == "success", is_failed=tx.status == "failed")
        raise NonRetryableFleetError("not found", 404)

    async def list_driver_transactions(self, driver_profile_id: str, from_dt: datetime,
                                       to_dt: datetime) -> list[DriverTransaction]:
        self._check("list_driver_transactions", driver_profile_id)
        return [DriverTransaction(transaction_id=t.id, amount=t.amount, description=t.description)
                for t in self.transactions if t.driver_profile_id == driver_profile_id]

    async def get_driver_online_time(self, driver_profile_id: str, day: date) -> int:
        self._check("get_driver_online_time", (driver_profile_id, day))
        return self.online_seconds.get((driver_profile_id, day), 0)

    async def list_work_rules(self) -> list[WorkRule]:
        self._check("list_work_rules")
        return list(self.work_rules)

    async def get_driver_blocked_balance(self, driver_profile_id: str) -> int | None:
        self._check("get_driver_blocked_balance", driver_profile_id)
        return 0
