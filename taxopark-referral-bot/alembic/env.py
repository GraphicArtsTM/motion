from __future__ import annotations

import os

from sqlalchemy import create_engine, pool

from alembic import context
from src.config import get_config


def _url() -> str:
    url = context.config.get_main_option("sqlalchemy.url") or os.environ.get("ALEMBIC_DATABASE_URL")
    return url or get_config().sync_database_url


def run_migrations_offline() -> None:
    context.configure(url=_url(), literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = context.config.attributes.get("connection")
    if connectable is not None:
        context.configure(connection=connectable)
        with context.begin_transaction():
            context.run_migrations()
        return
    engine = create_engine(_url(), poolclass=pool.NullPool)
    with engine.connect() as connection:
        context.configure(connection=connection)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
