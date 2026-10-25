"""FleetProvider — контракт интеграции с Яндекс Fleet (9.6 п.1)."""

from __future__ import annotations

import abc
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any


@dataclass
class FleetDriverProfile:
    id: str
    park_id: str
    phone: str | None = None
    driver_license: str | None = None
    first_name: str | None = None
    last_name: str | None = None
    middle_name: str | None = None
    work_status: str | None = None
    work_rule_id: str | None = None
    hire_date: date | None = None
    fire_date: date | None = None
    car_id: str | None = None
    car_category: str | None = None
    created_date: datetime | None = None
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass
class FleetOrder:
    id: str
    driver_profile_id: str
    status: str
    price: int = 0
    distance_m: int = 0
    duration_sec: int = 0
    booked_at: datetime | None = None
    ended_at: datetime | None = None
    tariff_class: str | None = None
    car_id: str | None = None
    payment_method: str | None = None
    address_from: str | None = None
    address_to: str | None = None
    raw: dict[str, Any] = field(default_factory=dict)
    tariff_source: str | None = None


@dataclass
class FleetCar:
    id: str
    category: str | None = None
    categories: list[str] = field(default_factory=list)
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass
class TransactionCategory:
    id: str
    name: str
    is_enabled: bool = True


@dataclass
class TransactionResult:
    transaction_id: str
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass
class TransactionStatus:
    is_success: bool
    is_failed: bool
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass
class DriverTransaction:
    transaction_id: str
    amount: int
    description: str
    event_at: datetime | None = None
    category_id: str | None = None


@dataclass
class WorkRule:
    id: str
    name: str


class FleetProvider(abc.ABC):
    name: str = "base"
    park_id: str = ""

    @abc.abstractmethod
    async def list_drivers(self, limit: int, offset: int) -> list[FleetDriverProfile]: ...

    @abc.abstractmethod
    async def get_driver(self, driver_profile_id: str) -> FleetDriverProfile | None: ...

    @abc.abstractmethod
    async def list_orders(self, from_dt: datetime, to_dt: datetime, limit: int,
                          offset: int) -> list[FleetOrder]: ...

    @abc.abstractmethod
    async def list_cars(self, limit: int, offset: int) -> list[FleetCar]: ...

    @abc.abstractmethod
    async def get_car(self, car_id: str) -> FleetCar | None: ...

    @abc.abstractmethod
    async def list_transaction_categories(self) -> list[TransactionCategory]: ...

    @abc.abstractmethod
    async def create_driver_transaction(self, driver_profile_id: str, amount: int, category_id: str,
                                        description: str, idempotency_token: str) -> TransactionResult: ...

    @abc.abstractmethod
    async def get_transaction_status(self, transaction_id: str) -> TransactionStatus: ...

    @abc.abstractmethod
    async def list_driver_transactions(self, driver_profile_id: str, from_dt: datetime,
                                       to_dt: datetime) -> list[DriverTransaction]: ...

    async def find_driver_transaction(self, driver_profile_id: str, from_dt: datetime, to_dt: datetime,
                                      marker: str) -> DriverTransaction | None:
        """Поиск транзакции по метке REFBOT-W{id} в description (резервная сверка)."""
        for tx in await self.list_driver_transactions(driver_profile_id, from_dt, to_dt):
            if marker and marker in (tx.description or ""):
                return tx
        return None

    @abc.abstractmethod
    async def get_driver_online_time(self, driver_profile_id: str, day: date) -> int: ...

    @abc.abstractmethod
    async def list_work_rules(self) -> list[WorkRule]: ...

    @abc.abstractmethod
    async def get_driver_blocked_balance(self, driver_profile_id: str) -> int | None: ...

    async def aclose(self) -> None:
        return None
