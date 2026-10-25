"""Async engine / sessionmaker."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

from src.config import get_config

_engine: AsyncEngine | None = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def make_engine(url: str | None = None, **kw: object) -> AsyncEngine:
    return create_async_engine(url or get_config().database_url, pool_pre_ping=True, **kw)  # type: ignore[arg-type]


def make_sessionmaker(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, expire_on_commit=False, autoflush=True)


def get_sessionmaker() -> async_sessionmaker[AsyncSession]:
    global _engine, _sessionmaker
    if _sessionmaker is None:
        _engine = make_engine()
        _sessionmaker = make_sessionmaker(_engine)
    return _sessionmaker


def set_sessionmaker(sm: async_sessionmaker[AsyncSession]) -> None:
    """Подмена фабрики сессий (тесты)."""
    global _sessionmaker
    _sessionmaker = sm
