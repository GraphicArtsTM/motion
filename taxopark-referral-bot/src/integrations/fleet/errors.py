"""Три класса ошибок Fleet API (9.6 п.3)."""

from __future__ import annotations


class FleetError(Exception):
    def __init__(self, message: str, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


class NonRetryableFleetError(FleetError):
    """400, 401, 403, 404 — повтор бессмыслен."""


class RetryableFleetError(FleetError):
    """429, 5xx с полученным ответом — операция точно не выполнена, повтор разрешён."""


class CircuitOpenError(RetryableFleetError):
    """Circuit breaker разомкнут — запрос не отправлялся."""


class UnknownOutcomeError(FleetError):
    """Таймаут, обрыв связи — исход неизвестен, повтор запрещён до сверки."""
