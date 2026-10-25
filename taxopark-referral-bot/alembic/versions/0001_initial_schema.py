"""Схема БД из Раздела 10 ТЗ v6.0 (исправление E1: порядок по зависимостям).

Revision ID: 0001
Revises:
Create Date: 2026-10-25
"""

from __future__ import annotations

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


SCHEMA_SQL = r"""
-- ═══════════ 1. БАЗОВЫЕ ═══════════
CREATE TABLE users (
    id                        BIGSERIAL PRIMARY KEY,
    telegram_id               BIGINT UNIQUE NOT NULL,
    username                  VARCHAR(64),
    full_name                 VARCHAR(200),
    phone                     VARCHAR(20) UNIQUE,
    phone_verified_at         TIMESTAMPTZ,
    driver_license            VARCHAR(32) UNIQUE,
    license_photo_front       VARCHAR(256),
    license_photo_back        VARCHAR(256),
    language                  VARCHAR(10) NOT NULL DEFAULT 'uz_latn',
    role                      VARCHAR(20) NOT NULL DEFAULT 'driver',
    access_status             VARCHAR(20) NOT NULL DEFAULT 'onboarding',
    consent_at                TIMESTAMPTZ,
    referral_code             VARCHAR(12) UNIQUE NOT NULL,
    qualified_referrals_count INT    NOT NULL DEFAULT 0,
    balance_available         BIGINT NOT NULL DEFAULT 0 CHECK (balance_available >= 0),
    balance_hold              BIGINT NOT NULL DEFAULT 0 CHECK (balance_hold >= 0),
    debt                      BIGINT NOT NULL DEFAULT 0 CHECK (debt >= 0),
    payout_blocked            BOOLEAN NOT NULL DEFAULT FALSE,
    notification_settings     JSONB  NOT NULL DEFAULT '{}',
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_phone   ON users(phone);
CREATE INDEX idx_users_license ON users(driver_license);
CREATE INDEX idx_users_access  ON users(access_status);

CREATE TABLE periods (
    id                       BIGSERIAL PRIMARY KEY,
    code                     VARCHAR(7) UNIQUE NOT NULL,
    starts_at                TIMESTAMPTZ NOT NULL,
    ends_at                  TIMESTAMPTZ NOT NULL,
    threshold_points_x100    BIGINT NOT NULL,
    default_coefficient_x100 INT NOT NULL,
    status                   VARCHAR(20) NOT NULL DEFAULT 'open',
    closed_at                TIMESTAMPTZ,
    recalculated_at          TIMESTAMPTZ
);

-- ═══════════ 2. СПРАВОЧНИКИ ПРАВИЛ ═══════════
CREATE TABLE tariff_coefficients (
    code             VARCHAR(64) PRIMARY KEY,
    name             VARCHAR(128) NOT NULL,
    coefficient_x100 INT NOT NULL CHECK (coefficient_x100 > 0),
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    needs_setup      BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order       INT NOT NULL DEFAULT 100,
    updated_by       BIGINT REFERENCES users(id),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE period_tariff_coefficients (
    period_id        BIGINT NOT NULL REFERENCES periods(id),
    tariff_class     VARCHAR(64) NOT NULL,
    coefficient_x100 INT NOT NULL,
    PRIMARY KEY (period_id, tariff_class)
);

CREATE TABLE bonus_rules (
    id          SERIAL PRIMARY KEY,
    recipient   VARCHAR(10) NOT NULL DEFAULT 'referrer'
                CHECK (recipient IN ('referrer','referred')),
    min_percent INT NOT NULL,
    bonus_uzs   BIGINT NOT NULL CHECK (bonus_uzs > 0),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    updated_by  BIGINT REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (recipient, min_percent)
);

CREATE TABLE milestones (
    id             SERIAL PRIMARY KEY,
    code           VARCHAR(32) UNIQUE NOT NULL,
    name           VARCHAR(128) NOT NULL,
    required_count INT NOT NULL,
    reward_uzs     BIGINT NOT NULL CHECK (reward_uzs > 0),
    is_active      BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order     INT NOT NULL,
    updated_by     BIGINT REFERENCES users(id),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ═══════════ 3. УСЛОВИЯ ПРОГРАММЫ (N3) ═══════════
CREATE TABLE program_terms (
    id           SERIAL PRIMARY KEY,
    version      INT UNIQUE NOT NULL,
    text_ru      TEXT NOT NULL,
    text_uz_latn TEXT NOT NULL,
    text_uz_cyrl TEXT NOT NULL,
    published_at TIMESTAMPTZ,
    published_by BIGINT REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE user_terms_acceptance (
    user_id     BIGINT NOT NULL REFERENCES users(id),
    terms_id    INT    NOT NULL REFERENCES program_terms(id),
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, terms_id)
);

-- ═══════════ 4. ПАРК ═══════════
CREATE TABLE park_driver_profiles (
    driver_profile_id  VARCHAR(64) PRIMARY KEY,
    park_id            VARCHAR(64) NOT NULL,
    first_name         VARCHAR(128),
    last_name          VARCHAR(128),
    middle_name        VARCHAR(128),
    phone_normalized   VARCHAR(20),
    license_normalized VARCHAR(32),
    work_status        VARCHAR(20),
    work_rule_id       VARCHAR(64),
    hire_date          DATE,
    fire_date          DATE,
    car_id             VARCHAR(64),
    car_category       VARCHAR(64),
    blocked_balance    BIGINT,
    created_date       TIMESTAMPTZ,
    is_stale           BOOLEAN NOT NULL DEFAULT FALSE,
    raw                JSONB,
    synced_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_park_phone   ON park_driver_profiles(phone_normalized);
CREATE INDEX idx_park_license ON park_driver_profiles(license_normalized);
CREATE INDEX idx_park_park    ON park_driver_profiles(park_id);

CREATE TABLE drivers (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT UNIQUE NOT NULL REFERENCES users(id),
    driver_profile_id VARCHAR(64) UNIQUE NOT NULL
                      REFERENCES park_driver_profiles(driver_profile_id),
    work_status       VARCHAR(20),
    linked_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    linked_by         BIGINT REFERENCES users(id),
    last_sync_at      TIMESTAMPTZ
);

CREATE TABLE driver_online_time (
    driver_profile_id VARCHAR(64) NOT NULL,
    stat_date         DATE NOT NULL,
    online_seconds    INT NOT NULL DEFAULT 0,
    synced_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (driver_profile_id, stat_date)
);

-- ═══════════ 5. РЕФЕРАЛЫ И ЗАЯВКИ ═══════════
CREATE TABLE referrals (
    id                 BIGSERIAL PRIMARY KEY,
    referrer_user_id   BIGINT NOT NULL REFERENCES users(id),
    referred_user_id   BIGINT UNIQUE NOT NULL REFERENCES users(id),
    referral_code      VARCHAR(12) NOT NULL,
    source             VARCHAR(20) NOT NULL DEFAULT 'link',
    source_tag         VARCHAR(16) NOT NULL DEFAULT 'tg',
    status             VARCHAR(20) NOT NULL DEFAULT 'clicked',
    is_counted         BOOLEAN NOT NULL DEFAULT FALSE,
    clicked_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    registered_at      TIMESTAMPTZ,
    approved_at        TIMESTAMPTZ,
    hired_at           TIMESTAMPTZ,
    first_ride_at      TIMESTAMPTZ,
    first_qualified_at TIMESTAMPTZ,
    expires_at         TIMESTAMPTZ,
    rejected_reason    VARCHAR(64),
    risk_score         INT NOT NULL DEFAULT 0,
    is_fraud           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT no_self_referral CHECK (referrer_user_id <> referred_user_id)
);
CREATE INDEX idx_referrals_referrer ON referrals(referrer_user_id, status);
CREATE INDEX idx_referrals_counted  ON referrals(referrer_user_id) WHERE is_counted;
CREATE INDEX idx_referrals_tag      ON referrals(source_tag);

CREATE TABLE approval_requests (
    id               BIGSERIAL PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(id),
    referral_id      BIGINT REFERENCES referrals(id),
    found_profile_id VARCHAR(64),
    autocheck_result VARCHAR(32) NOT NULL,
    status           VARCHAR(32) NOT NULL DEFAULT 'pending',
    reason           TEXT,
    decided_by       BIGINT REFERENCES users(id),
    decided_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_approval_pending ON approval_requests(status) WHERE status = 'pending';

-- ═══════════ 6. ЗАКАЗЫ ═══════════
CREATE TABLE orders (
    id                BIGSERIAL PRIMARY KEY,
    external_order_id VARCHAR(64) UNIQUE NOT NULL,
    driver_profile_id VARCHAR(64) NOT NULL,
    tariff_class      VARCHAR(64),
    tariff_source     VARCHAR(16),
    status            VARCHAR(32) NOT NULL,
    price             BIGINT NOT NULL DEFAULT 0,
    distance_m        INT NOT NULL DEFAULT 0,
    duration_sec      INT NOT NULL DEFAULT 0,
    booked_at         TIMESTAMPTZ,
    ended_at          TIMESTAMPTZ,
    payment_method    VARCHAR(32),
    address_from      TEXT,
    address_to        TEXT,
    raw               JSONB,
    synced_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_orders_driver_ended ON orders(driver_profile_id, ended_at);
CREATE INDEX idx_orders_tariff       ON orders(tariff_class);

CREATE TABLE order_daily_stats (
    driver_profile_id VARCHAR(64) NOT NULL,
    stat_date         DATE NOT NULL,
    tariff_class      VARCHAR(64) NOT NULL,
    orders_count      INT NOT NULL DEFAULT 0,
    eligible_count    INT NOT NULL DEFAULT 0,
    points_x100       BIGINT NOT NULL DEFAULT 0,
    gmv               BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (driver_profile_id, stat_date, tariff_class)
);

-- ═══════════ 7. КВАЛИФИКАЦИИ И ДЕНЬГИ ═══════════
CREATE TABLE qualifications (
    id                    BIGSERIAL PRIMARY KEY,
    referral_id           BIGINT NOT NULL REFERENCES referrals(id),
    period_id             BIGINT NOT NULL REFERENCES periods(id),
    eligible_orders_count INT NOT NULL DEFAULT 0,
    points_x100           BIGINT NOT NULL DEFAULT 0,
    threshold_points_x100 BIGINT NOT NULL,
    achieved_percent      INT NOT NULL DEFAULT 0,
    is_qualified          BOOLEAN NOT NULL DEFAULT FALSE,
    breakdown             JSONB,
    computed_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (referral_id, period_id)
);
CREATE INDEX idx_qual_qualified ON qualifications(period_id) WHERE is_qualified;

CREATE TABLE withdrawals (
    id                      BIGSERIAL PRIMARY KEY,
    user_id                 BIGINT NOT NULL REFERENCES users(id),
    driver_profile_id       VARCHAR(64) NOT NULL,
    amount                  BIGINT NOT NULL CHECK (amount > 0),
    status                  VARCHAR(20) NOT NULL DEFAULT 'pending',
    requires_manual         BOOLEAN NOT NULL DEFAULT FALSE,
    idempotency_token       UUID UNIQUE NOT NULL,
    marker                  VARCHAR(32) UNIQUE,
    external_transaction_id VARCHAR(64),
    attempts                INT NOT NULL DEFAULT 0,
    last_error              TEXT,
    requested_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at            TIMESTAMPTZ,
    failed_at               TIMESTAMPTZ,
    processed_by            BIGINT REFERENCES users(id),
    proof_file_id           VARCHAR(256)
);
CREATE UNIQUE INDEX idx_one_active_withdrawal ON withdrawals(user_id)
    WHERE status IN ('pending','awaiting_approval','processing','verifying');

CREATE TABLE accruals (
    id              BIGSERIAL PRIMARY KEY,
    idempotency_key VARCHAR(64) UNIQUE NOT NULL,
    user_id         BIGINT NOT NULL REFERENCES users(id),
    type            VARCHAR(20) NOT NULL
                    CHECK (type IN ('referral','referred_welcome','milestone',
                                    'adjustment','manual')),
    referral_id     BIGINT REFERENCES referrals(id),
    milestone_id    INT    REFERENCES milestones(id),
    bonus_rule_id   INT    REFERENCES bonus_rules(id),
    period_id       BIGINT REFERENCES periods(id),
    withdrawal_id   BIGINT,
    amount          BIGINT NOT NULL CHECK (amount > 0),
    status          VARCHAR(20) NOT NULL DEFAULT 'available',
    hold_until      TIMESTAMPTZ,
    released_at     TIMESTAMPTZ,
    comment         TEXT,
    created_by      BIGINT REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_accruals_user_status ON accruals(user_id, status);
CREATE INDEX idx_accruals_period      ON accruals(period_id, type);

CREATE TABLE user_milestones (
    user_id                 BIGINT NOT NULL REFERENCES users(id),
    milestone_id            INT    NOT NULL REFERENCES milestones(id) ON DELETE RESTRICT,
    achieved_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    accrual_id              BIGINT,
    granted_without_payment BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (user_id, milestone_id)
);

CREATE TABLE corrections (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users(id),
    amount       BIGINT NOT NULL,
    reason       TEXT NOT NULL,
    applied      BOOLEAN NOT NULL DEFAULT TRUE,
    debt_created BIGINT NOT NULL DEFAULT 0,
    created_by   BIGINT REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE wallet_ledger (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id),
    type          VARCHAR(32) NOT NULL,
    amount        BIGINT NOT NULL,
    balance_after BIGINT NOT NULL,
    debt_after    BIGINT NOT NULL DEFAULT 0,
    ref_type      VARCHAR(32),
    ref_id        BIGINT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ledger_user ON wallet_ledger(user_id, created_at DESC);

-- ═══════════ 8. СЛУЖЕБНЫЕ ═══════════
CREATE TABLE settings (
    key VARCHAR(64) PRIMARY KEY, value JSONB NOT NULL,
    value_type VARCHAR(16) NOT NULL, description TEXT,
    updated_by BIGINT REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE settings_history (
    id BIGSERIAL PRIMARY KEY, entity VARCHAR(32) NOT NULL, key VARCHAR(64) NOT NULL,
    old_value JSONB, new_value JSONB, effective_from DATE,
    changed_by BIGINT REFERENCES users(id),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE fraud_flags (
    id BIGSERIAL PRIMARY KEY,
    referral_id BIGINT REFERENCES referrals(id), user_id BIGINT REFERENCES users(id),
    rule_code VARCHAR(32) NOT NULL, severity VARCHAR(16) NOT NULL,
    score INT NOT NULL DEFAULT 0, details JSONB,
    resolved BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_by BIGINT REFERENCES users(id), resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE broadcasts (
    id BIGSERIAL PRIMARY KEY, title VARCHAR(256), text TEXT,
    media JSONB, buttons JSONB, segment JSONB,
    scheduled_at TIMESTAMPTZ, started_at TIMESTAMPTZ, finished_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    total INT DEFAULT 0, sent INT DEFAULT 0, failed INT DEFAULT 0, blocked INT DEFAULT 0,
    created_by BIGINT REFERENCES users(id)
);
CREATE TABLE broadcast_recipients (
    broadcast_id BIGINT NOT NULL REFERENCES broadcasts(id),
    user_id BIGINT NOT NULL REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'queued', error TEXT, sent_at TIMESTAMPTZ,
    PRIMARY KEY (broadcast_id, user_id)
);
CREATE TABLE support_tickets (
    id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
    subject VARCHAR(256), kind VARCHAR(20) NOT NULL DEFAULT 'general',
    context JSONB,
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    assigned_to BIGINT REFERENCES users(id), sla_due_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(), closed_at TIMESTAMPTZ
);
CREATE TABLE support_messages (
    id BIGSERIAL PRIMARY KEY, ticket_id BIGINT NOT NULL REFERENCES support_tickets(id),
    author_type VARCHAR(10) NOT NULL, author_id BIGINT,
    text TEXT, media JSONB, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE notification_log (
    id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id),
    kind VARCHAR(32) NOT NULL, subject_id BIGINT,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notiflog ON notification_log(user_id, kind, subject_id, sent_at DESC);
CREATE TABLE blacklist (
    id BIGSERIAL PRIMARY KEY, entry_type VARCHAR(20) NOT NULL,
    value VARCHAR(128) NOT NULL, reason TEXT,
    created_by BIGINT REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (entry_type, value)
);
CREATE TABLE audit_log (
    id BIGSERIAL PRIMARY KEY, actor_user_id BIGINT REFERENCES users(id),
    action VARCHAR(64) NOT NULL, entity_type VARCHAR(32), entity_id BIGINT,
    old_value JSONB, new_value JSONB, ip INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE api_sync_log (
    id BIGSERIAL PRIMARY KEY, provider VARCHAR(32), method VARCHAR(128),
    status_code INT, duration_ms INT, records_count INT, error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE job_locks (
    job_name VARCHAR(64) PRIMARY KEY,
    locked_at TIMESTAMPTZ NOT NULL, locked_until TIMESTAMPTZ NOT NULL
);

-- ═══════════ 9. КРУГОВЫЕ СВЯЗИ (E1) ═══════════
ALTER TABLE accruals
    ADD CONSTRAINT fk_accruals_withdrawal FOREIGN KEY (withdrawal_id) REFERENCES withdrawals(id);
ALTER TABLE user_milestones
    ADD CONSTRAINT fk_user_milestones_accrual FOREIGN KEY (accrual_id) REFERENCES accruals(id);
"""

# Дополнения к схеме Раздела 10 — обоснование в DECISIONS.md (D-05 … D-11).
EXTENSIONS_SQL = r"""
CREATE TABLE notification_outbox (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT REFERENCES users(id),
    chat_id      BIGINT,
    audience     VARCHAR(16) NOT NULL DEFAULT 'user',
    template_key VARCHAR(64) NOT NULL,
    params       JSONB NOT NULL DEFAULT '{}',
    buttons      JSONB,
    media        JSONB,
    status       VARCHAR(16) NOT NULL DEFAULT 'queued',
    attempts     INT NOT NULL DEFAULT 0,
    error        TEXT,
    not_before   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at      TIMESTAMPTZ
);
CREATE INDEX idx_outbox_queued ON notification_outbox(not_before) WHERE status = 'queued';

CREATE TABLE sync_cursors (
    name       VARCHAR(64) PRIMARY KEY,
    cursor_at  TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE admin_credentials (
    user_id       BIGINT PRIMARY KEY REFERENCES users(id),
    login         VARCHAR(64) UNIQUE NOT NULL,
    password_hash VARCHAR(256) NOT NULL,
    totp_secret   VARCHAR(64),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_notes (
    id         BIGSERIAL PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users(id),
    author_id  BIGINT REFERENCES users(id),
    text       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE fraud_whitelist (
    user_id    BIGINT PRIMARY KEY REFERENCES users(id),
    reason     TEXT,
    created_by BIGINT REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users            ADD COLUMN bot_blocked BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE accruals         ADD COLUMN parent_accrual_id BIGINT REFERENCES accruals(id);
ALTER TABLE fraud_flags      ADD COLUMN period_id BIGINT REFERENCES periods(id);
ALTER TABLE support_tickets  ADD COLUMN admin_message_id BIGINT;
ALTER TABLE support_tickets  ADD COLUMN admin_thread_id BIGINT;
ALTER TABLE broadcast_recipients ADD COLUMN outbox_id BIGINT REFERENCES notification_outbox(id);
CREATE INDEX idx_fraud_open ON fraud_flags(referral_id) WHERE NOT resolved;
CREATE INDEX idx_withdrawals_status ON withdrawals(status);

-- Неизменяемый audit log (14.2 п.10)
CREATE OR REPLACE FUNCTION audit_log_immutable() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_audit_log_immutable
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();
"""


def upgrade() -> None:
    op.execute(SCHEMA_SQL)
    op.execute(EXTENSIONS_SQL)


def downgrade() -> None:
    op.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
