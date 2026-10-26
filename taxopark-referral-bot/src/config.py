"""Конфигурация из переменных окружения (Раздел 13.3).

Здесь только инфраструктурные параметры. Все бизнес-значения (суммы, пороги,
коэффициенты) хранятся в БД — таблица `settings` и справочники (R3).
"""

from __future__ import annotations

from functools import lru_cache
from typing import Annotated

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class AppConfig(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    bot_token: str = ""
    bot_username: str = "taxopark_referral_bot"
    webhook_url: str = ""
    webhook_secret: str = ""
    # polling — бот сам опрашивает Telegram (локальный запуск, Windows); webhook — сервер с доменом и HTTPS
    bot_mode: str = "polling"
    admin_telegram_ids: Annotated[list[int], NoDecode] = Field(default_factory=list)
    admin_notify_chat_id: int | None = None

    database_url: str = "postgresql+asyncpg://referral:referral@postgres:5432/referral"
    redis_url: str = "redis://redis:6379/0"
    # redis — очередь ARQ и FSM в Redis (Docker); db — всё в PostgreSQL (запуск без Docker, start.bat)
    queue_backend: str = "redis"

    fleet_api_base_url: str = "https://fleet-api.taxi.yandex.net"
    fleet_client_id: str = ""
    fleet_api_key: str = ""
    fleet_park_id: str = ""

    admin_secret_key: str = "change-me"
    admin_base_url: str = ""

    sentry_dsn: str = ""
    log_level: str = "INFO"
    environment: str = "production"
    tz_display: str = "Asia/Tashkent"
    s3_backup_bucket: str = ""
    backup_dir: str = "/backups"

    @field_validator("admin_telegram_ids", mode="before")
    @classmethod
    def _split_ids(cls, v: object) -> object:
        if isinstance(v, str):
            return [int(x) for x in v.replace(";", ",").split(",") if x.strip()]
        if isinstance(v, int):
            return [v]
        return v

    @field_validator("admin_notify_chat_id", mode="before")
    @classmethod
    def _empty_chat(cls, v: object) -> object:
        return None if v in ("", None) else v

    @property
    def sync_database_url(self) -> str:
        return self.database_url.replace("+asyncpg", "+psycopg2")


@lru_cache
def get_config() -> AppConfig:
    return AppConfig()
