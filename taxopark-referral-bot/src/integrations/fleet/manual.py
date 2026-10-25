"""ManualFleetProvider — режим без интеграции: данные парка вводит администратор
(ручная привязка профилей, импорт), выплаты делает финансист вручную."""

from __future__ import annotations

from datetime import date, datetime

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


class ManualFleetProvider(FleetProvider):
    name = "manual"

    def __init__(self, park_id: str = "") -> None:
        self.park_id = park_id

    async def list_drivers(self, limit: int, offset: int) -> list[FleetDriverProfile]:
        return []

    async def get_driver(self, driver_profile_id: str) -> FleetDriverProfile | None:
        return None

    async def list_orders(self, from_dt: datetime, to_dt: datetime, limit: int, offset: int) -> list[FleetOrder]:
        return []

    async def list_cars(self, limit: int, offset: int) -> list[FleetCar]:
        return []

    async def get_car(self, car_id: str) -> FleetCar | None:
        return None

    async def list_transaction_categories(self) -> list[TransactionCategory]:
        return []

    async def create_driver_transaction(self, driver_profile_id: str, amount: int, category_id: str,
                                        description: str, idempotency_token: str) -> TransactionResult:
        raise NonRetryableFleetError("manual provider: payouts are made by finance manually")

    async def get_transaction_status(self, transaction_id: str) -> TransactionStatus:
        raise NonRetryableFleetError("manual provider")

    async def list_driver_transactions(self, driver_profile_id: str, from_dt: datetime,
                                       to_dt: datetime) -> list[DriverTransaction]:
        return []

    async def get_driver_online_time(self, driver_profile_id: str, day: date) -> int:
        return 0

    async def list_work_rules(self) -> list[WorkRule]:
        return []

    async def get_driver_blocked_balance(self, driver_profile_id: str) -> int | None:
        return None
