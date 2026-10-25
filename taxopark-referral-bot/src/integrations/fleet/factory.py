"""Выбор реализации FleetProvider по настройке `fleet_provider`."""

from __future__ import annotations

import os

from src.config import get_config
from src.integrations.fleet.api import ApiFleetProvider, LogSink
from src.integrations.fleet.base import FleetProvider
from src.integrations.fleet.csv import CsvFleetProvider
from src.integrations.fleet.manual import ManualFleetProvider
from src.integrations.fleet.mock import MockFleetProvider

_api_singleton: ApiFleetProvider | None = None


def build_provider(kind: str, log_sink: LogSink | None = None) -> FleetProvider:
    cfg = get_config()
    global _api_singleton
    if kind == "api":
        # один экземпляр на процесс — circuit breaker должен помнить ошибки между задачами
        if _api_singleton is None:
            _api_singleton = ApiFleetProvider(cfg.fleet_api_base_url, cfg.fleet_client_id, cfg.fleet_api_key,
                                              cfg.fleet_park_id, log_sink=log_sink)
        return _api_singleton
    if kind == "csv":
        return CsvFleetProvider(os.environ.get("FLEET_CSV_DIR", "/data/fleet_csv"), cfg.fleet_park_id)
    if kind == "mock":
        return MockFleetProvider(cfg.fleet_park_id or "park-mock")
    return ManualFleetProvider(cfg.fleet_park_id)
