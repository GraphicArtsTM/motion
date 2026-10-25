"""Сиды справочников, настроек и условий программы v1.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-25
"""

from __future__ import annotations

from alembic import op

from src.db.seeding import apply_seeds

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    apply_seeds(op.get_bind())


def downgrade() -> None:
    for table in ("program_terms", "settings", "milestones", "bonus_rules", "tariff_coefficients"):
        op.execute(f"DELETE FROM {table}")
