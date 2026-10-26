"""Очередь задач и состояние диалогов бота в PostgreSQL — режим без Redis (запуск без Docker).

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-26
"""

from __future__ import annotations

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
CREATE TABLE task_queue (
    id          BIGSERIAL PRIMARY KEY,
    func        VARCHAR(64)  NOT NULL,
    args        JSONB        NOT NULL DEFAULT '[]',
    job_key     VARCHAR(200) NOT NULL,
    run_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    status      VARCHAR(16)  NOT NULL DEFAULT 'queued',
    attempts    INT          NOT NULL DEFAULT 0,
    last_error  TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uq_task_queue_active ON task_queue(job_key) WHERE status IN ('queued', 'running');
CREATE INDEX idx_task_queue_due ON task_queue(run_at) WHERE status = 'queued';

CREATE TABLE fsm_storage (
    key        VARCHAR(256) PRIMARY KEY,
    state      VARCHAR(256),
    data       JSONB        NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
""")


def downgrade() -> None:
    op.execute("DROP TABLE fsm_storage; DROP TABLE task_queue;")
