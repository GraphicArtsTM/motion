"""Тестовая инфраструктура: реальный PostgreSQL, миграции Alembic, сиды, замороженные часы."""

from __future__ import annotations

import os
from collections.abc import AsyncIterator
from datetime import datetime

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://postgres@127.0.0.1:5433/referral_test")
os.environ.setdefault("FLEET_PARK_ID", "park-1")
os.environ.setdefault("TZ_DISPLAY", "Asia/Tashkent")
os.environ.setdefault("ENVIRONMENT", "test")

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from alembic import command
from src.config import get_config
from src.core.clock import FrozenClock, display_tz
from src.core.context import Ctx, RecordingQueue, make_ctx
from src.core.settings import service as settings_service
from src.db.seeding import apply_seeds
from src.db.session import set_sessionmaker
from src.integrations.fleet.mock import MockFleetProvider

ROOT = os.path.dirname(os.path.dirname(__file__))


def _sync_url() -> str:
    return get_config().sync_database_url


@pytest.fixture(scope="session")
def migrated_db() -> str:
    """TC-112: alembic upgrade head на пустой БД проходит без ошибок внешних ключей."""
    engine = create_engine(_sync_url())
    with engine.begin() as conn:
        conn.execute(text("DROP SCHEMA public CASCADE; CREATE SCHEMA public;"))
    engine.dispose()
    cfg = Config(os.path.join(ROOT, "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(ROOT, "alembic"))
    cfg.set_main_option("sqlalchemy.url", _sync_url())
    command.upgrade(cfg, "head")
    return _sync_url()


@pytest.fixture(scope="session")
def table_names(migrated_db: str) -> list[str]:
    engine = create_engine(migrated_db)
    with engine.connect() as conn:
        rows = conn.execute(text(
            "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> 'alembic_version'"))
        names = [r[0] for r in rows]
    engine.dispose()
    return names


@pytest.fixture(scope="session")
def sync_engine(migrated_db: str):  # type: ignore[no-untyped-def]
    engine = create_engine(migrated_db)
    yield engine
    engine.dispose()


@pytest.fixture
def clean_db(sync_engine, table_names: list[str]) -> None:  # type: ignore[no-untyped-def]
    with sync_engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {', '.join(table_names)} RESTART IDENTITY CASCADE"))
        apply_seeds(conn)
    settings_service.configure_cache(0)


@pytest.fixture(scope="session")
async def async_engine(migrated_db: str):  # type: ignore[no-untyped-def]
    engine = create_async_engine(get_config().database_url, poolclass=NullPool)
    yield engine
    await engine.dispose()


@pytest.fixture
def sessionmaker(async_engine, clean_db) -> async_sessionmaker[AsyncSession]:  # type: ignore[no-untyped-def]
    sm = async_sessionmaker(async_engine, expire_on_commit=False)
    set_sessionmaker(sm)
    return sm


@pytest.fixture
async def session(sessionmaker: async_sessionmaker[AsyncSession]) -> AsyncIterator[AsyncSession]:
    async with sessionmaker() as s:
        yield s


@pytest.fixture
def clock() -> FrozenClock:
    return FrozenClock(datetime(2026, 8, 15, 12, 0, tzinfo=display_tz()))


@pytest.fixture
def fleet() -> MockFleetProvider:
    return MockFleetProvider(park_id="park-1")


@pytest.fixture
def queue() -> RecordingQueue:
    return RecordingQueue()


@pytest.fixture
async def ctx(session: AsyncSession, clock: FrozenClock, fleet: MockFleetProvider, queue: RecordingQueue) -> Ctx:
    return await make_ctx(session, clock=clock, fleet=fleet, queue=queue)
