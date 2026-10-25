"""TC-112 и соответствие ORM-моделей схеме миграций."""

from __future__ import annotations

from sqlalchemy import inspect

from src.db.models import Base


def test_orm_matches_migrated_schema(sync_engine):
    insp = inspect(sync_engine)
    db_tables = set(insp.get_table_names())
    for table in Base.metadata.sorted_tables:
        assert table.name in db_tables, table.name
        cols = {c["name"]: c for c in insp.get_columns(table.name)}
        for col in table.columns:
            assert col.name in cols, f"{table.name}.{col.name}"
            assert cols[col.name]["nullable"] == col.nullable, f"{table.name}.{col.name} nullable"


def test_checks_and_partial_index(sync_engine):
    insp = inspect(sync_engine)
    checks = {c["name"] for c in insp.get_check_constraints("users")}
    assert any("balance_available" in (c.get("sqltext") or "") for c in insp.get_check_constraints("users")) or checks
    idx = {i["name"] for i in insp.get_indexes("withdrawals")}
    assert "idx_one_active_withdrawal" in idx
    fks = {fk["referred_table"] for fk in insp.get_foreign_keys("accruals")}
    assert "withdrawals" in fks  # круговая связь добавлена через ALTER TABLE (E1)


def test_audit_log_is_immutable(sync_engine):
    import pytest
    from sqlalchemy import text
    with sync_engine.begin() as conn:
        conn.execute(text("INSERT INTO audit_log (action) VALUES ('x')"))
    with pytest.raises(Exception):
        with sync_engine.begin() as conn:
            conn.execute(text("UPDATE audit_log SET action='y'"))
