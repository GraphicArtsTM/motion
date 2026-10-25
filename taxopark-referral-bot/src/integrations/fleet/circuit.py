"""Circuit breaker: N ошибок подряд → пауза (9.6 п.4)."""

from __future__ import annotations

import time

from src.integrations.fleet.errors import CircuitOpenError


class CircuitBreaker:
    def __init__(self, failures: int, pause_seconds: float, clock: object = time.monotonic) -> None:
        self.failures_threshold = failures
        self.pause = pause_seconds
        self._clock = clock
        self.consecutive_failures = 0
        self.opened_at: float | None = None

    def _now(self) -> float:
        return self._clock()  # type: ignore[operator,no-any-return]

    @property
    def is_open(self) -> bool:
        if self.opened_at is None:
            return False
        if self._now() - self.opened_at >= self.pause:
            # half-open: пропускаем один пробный запрос
            self.opened_at = None
            self.consecutive_failures = self.failures_threshold - 1
            return False
        return True

    def before_call(self) -> None:
        if self.is_open:
            raise CircuitOpenError("Fleet API circuit breaker is open")

    def record_success(self) -> None:
        self.consecutive_failures = 0
        self.opened_at = None

    def record_failure(self) -> None:
        self.consecutive_failures += 1
        if self.consecutive_failures >= self.failures_threshold:
            self.opened_at = self._now()
