"""CsvFleetProvider — импорт выгрузок кабинета парка (drivers.csv, orders.csv, cars.csv).

Используется, если API временно недоступно или ещё не подключено. Выплаты через
CSV невозможны — вывод средств при этом провайдере переводится в ручной режим.
"""

from __future__ import annotations

import csv
import sys
from datetime import date, datetime
from pathlib import Path

from src.integrations.fleet.api import parse_date, parse_dt, parse_int, parse_money, pick_category
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
from src.integrations.fleet.errors import NonRetryableFleetError


class CsvFleetProvider(FleetProvider):
    name = "csv"

    def __init__(self, directory: str | Path, park_id: str) -> None:
        self.dir = Path(directory)
        self.park_id = park_id

    def _rows(self, name: str) -> list[dict[str, str]]:
        path = self.dir / name
        if not path.exists():
            return []
        with path.open(encoding="utf-8-sig", newline="") as f:
            return list(csv.DictReader(f))

    async def list_drivers(self, limit: int, offset: int) -> list[FleetDriverProfile]:
        rows = self._rows("drivers.csv")[offset:offset + limit]
        return [FleetDriverProfile(
            id=r["id"], park_id=r.get("park_id") or self.park_id, phone=r.get("phone"),
            driver_license=r.get("driver_license"), first_name=r.get("first_name"),
            last_name=r.get("last_name"), middle_name=r.get("middle_name"),
            work_status=r.get("work_status"), work_rule_id=r.get("work_rule_id"),
            hire_date=parse_date(r.get("hire_date")), fire_date=parse_date(r.get("fire_date")),
            car_id=r.get("car_id"), car_category=pick_category(r.get("car_category")),
            created_date=parse_dt(r.get("created_date")), raw=dict(r)) for r in rows]

    async def get_driver(self, driver_profile_id: str) -> FleetDriverProfile | None:
        for p in await self.list_drivers(sys.maxsize, 0):
            if p.id == driver_profile_id:
                return p
        return None

    async def list_orders(self, from_dt: datetime, to_dt: datetime, limit: int, offset: int) -> list[FleetOrder]:
        out = []
        for r in self._rows("orders.csv"):
            ended = parse_dt(r.get("ended_at"))
            if ended and not (from_dt <= ended <= to_dt):
                continue
            out.append(FleetOrder(
                id=r["id"], driver_profile_id=r["driver_profile_id"], status=r.get("status", ""),
                price=parse_money(r.get("price")), distance_m=parse_int(r.get("distance_m")),
                duration_sec=parse_int(r.get("duration_sec")), booked_at=parse_dt(r.get("booked_at")),
                ended_at=ended, tariff_class=r.get("tariff_class") or None, car_id=r.get("car_id") or None,
                payment_method=r.get("payment_method"), address_from=r.get("address_from"),
                address_to=r.get("address_to"), raw=dict(r)))
        return out[offset:offset + limit]

    async def list_cars(self, limit: int, offset: int) -> list[FleetCar]:
        rows = self._rows("cars.csv")[offset:offset + limit]
        return [FleetCar(id=r["id"], category=pick_category(r.get("category")), raw=dict(r)) for r in rows]

    async def get_car(self, car_id: str) -> FleetCar | None:
        for c in await self.list_cars(sys.maxsize, 0):
            if c.id == car_id:
                return c
        return None

    async def list_transaction_categories(self) -> list[TransactionCategory]:
        return []

    async def create_driver_transaction(self, driver_profile_id: str, amount: int, category_id: str,
                                        description: str, idempotency_token: str) -> TransactionResult:
        raise NonRetryableFleetError("payouts are not supported by CSV provider")

    async def get_transaction_status(self, transaction_id: str) -> TransactionStatus:
        raise NonRetryableFleetError("not supported by CSV provider")

    async def list_driver_transactions(self, driver_profile_id: str, from_dt: datetime,
                                       to_dt: datetime) -> list[DriverTransaction]:
        return []

    async def get_driver_online_time(self, driver_profile_id: str, day: date) -> int:
        for r in self._rows("online_time.csv"):
            if r.get("driver_profile_id") == driver_profile_id and parse_date(r.get("date")) == day:
                return parse_int(r.get("online_seconds"))
        return 0

    async def list_work_rules(self) -> list[WorkRule]:
        return []

    async def get_driver_blocked_balance(self, driver_profile_id: str) -> int | None:
        return None
