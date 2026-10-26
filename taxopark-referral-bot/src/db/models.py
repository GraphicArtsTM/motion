"""ORM-модели. Зеркало схемы из миграции 0001 (Раздел 10 + дополнения DECISIONS.md)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import INET, JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


TS = DateTime(timezone=True)


def _now() -> Any:
    return mapped_column(TS, nullable=False, server_default=func.now())


# ═══════════ 1. БАЗОВЫЕ ═══════════
class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    telegram_id: Mapped[int] = mapped_column(BigInteger, unique=True, nullable=False)
    username: Mapped[str | None] = mapped_column(String(64))
    full_name: Mapped[str | None] = mapped_column(String(200))
    phone: Mapped[str | None] = mapped_column(String(20), unique=True)
    phone_verified_at: Mapped[datetime | None] = mapped_column(TS)
    driver_license: Mapped[str | None] = mapped_column(String(32), unique=True)
    license_photo_front: Mapped[str | None] = mapped_column(String(256))
    license_photo_back: Mapped[str | None] = mapped_column(String(256))
    language: Mapped[str] = mapped_column(String(10), nullable=False, server_default="uz_latn")
    role: Mapped[str] = mapped_column(String(20), nullable=False, server_default="driver")
    access_status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="onboarding")
    consent_at: Mapped[datetime | None] = mapped_column(TS)
    referral_code: Mapped[str] = mapped_column(String(12), unique=True, nullable=False)
    qualified_referrals_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    balance_available: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    balance_hold: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    debt: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    payout_blocked: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    notification_settings: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default="{}")
    bot_blocked: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = mapped_column(TS, nullable=False, server_default=func.now(),
                                                 onupdate=func.now())


class Period(Base):
    __tablename__ = "periods"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    code: Mapped[str] = mapped_column(String(7), unique=True, nullable=False)
    starts_at: Mapped[datetime] = mapped_column(TS, nullable=False)
    ends_at: Mapped[datetime] = mapped_column(TS, nullable=False)
    threshold_points_x100: Mapped[int] = mapped_column(BigInteger, nullable=False)
    default_coefficient_x100: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="open")
    closed_at: Mapped[datetime | None] = mapped_column(TS)
    recalculated_at: Mapped[datetime | None] = mapped_column(TS)


# ═══════════ 2. СПРАВОЧНИКИ ПРАВИЛ ═══════════
class TariffCoefficient(Base):
    __tablename__ = "tariff_coefficients"

    code: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    coefficient_x100: Mapped[int] = mapped_column(Integer, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    needs_setup: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="100")
    updated_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    updated_at: Mapped[datetime] = _now()


class PeriodTariffCoefficient(Base):
    __tablename__ = "period_tariff_coefficients"

    period_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("periods.id"), primary_key=True)
    tariff_class: Mapped[str] = mapped_column(String(64), primary_key=True)
    coefficient_x100: Mapped[int] = mapped_column(Integer, nullable=False)


class BonusRule(Base):
    __tablename__ = "bonus_rules"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    recipient: Mapped[str] = mapped_column(String(10), nullable=False, server_default="referrer")
    min_percent: Mapped[int] = mapped_column(Integer, nullable=False)
    bonus_uzs: Mapped[int] = mapped_column(BigInteger, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    updated_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    updated_at: Mapped[datetime] = _now()


class Milestone(Base):
    __tablename__ = "milestones"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(32), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    required_count: Mapped[int] = mapped_column(Integer, nullable=False)
    reward_uzs: Mapped[int] = mapped_column(BigInteger, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False)
    updated_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    updated_at: Mapped[datetime] = _now()


# ═══════════ 3. УСЛОВИЯ ПРОГРАММЫ ═══════════
class ProgramTerms(Base):
    __tablename__ = "program_terms"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    version: Mapped[int] = mapped_column(Integer, unique=True, nullable=False)
    text_ru: Mapped[str] = mapped_column(Text, nullable=False)
    text_uz_latn: Mapped[str] = mapped_column(Text, nullable=False)
    text_uz_cyrl: Mapped[str] = mapped_column(Text, nullable=False)
    published_at: Mapped[datetime | None] = mapped_column(TS)
    published_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    created_at: Mapped[datetime] = _now()

    def text_for(self, language: str) -> str:
        return {"ru": self.text_ru, "uz_cyrl": self.text_uz_cyrl}.get(language, self.text_uz_latn)


class UserTermsAcceptance(Base):
    __tablename__ = "user_terms_acceptance"

    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), primary_key=True)
    terms_id: Mapped[int] = mapped_column(Integer, ForeignKey("program_terms.id"), primary_key=True)
    accepted_at: Mapped[datetime] = _now()


# ═══════════ 4. ПАРК ═══════════
class ParkDriverProfile(Base):
    __tablename__ = "park_driver_profiles"

    driver_profile_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    park_id: Mapped[str] = mapped_column(String(64), nullable=False)
    first_name: Mapped[str | None] = mapped_column(String(128))
    last_name: Mapped[str | None] = mapped_column(String(128))
    middle_name: Mapped[str | None] = mapped_column(String(128))
    phone_normalized: Mapped[str | None] = mapped_column(String(20))
    license_normalized: Mapped[str | None] = mapped_column(String(32))
    work_status: Mapped[str | None] = mapped_column(String(20))
    work_rule_id: Mapped[str | None] = mapped_column(String(64))
    hire_date: Mapped[date | None] = mapped_column(Date)
    fire_date: Mapped[date | None] = mapped_column(Date)
    car_id: Mapped[str | None] = mapped_column(String(64))
    car_category: Mapped[str | None] = mapped_column(String(64))
    blocked_balance: Mapped[int | None] = mapped_column(BigInteger)
    created_date: Mapped[datetime | None] = mapped_column(TS)
    is_stale: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    raw: Mapped[dict | None] = mapped_column(JSONB)
    synced_at: Mapped[datetime] = _now()


class Driver(Base):
    __tablename__ = "drivers"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), unique=True, nullable=False)
    driver_profile_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("park_driver_profiles.driver_profile_id"), unique=True, nullable=False
    )
    work_status: Mapped[str | None] = mapped_column(String(20))
    linked_at: Mapped[datetime] = _now()
    linked_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    last_sync_at: Mapped[datetime | None] = mapped_column(TS)


class DriverOnlineTime(Base):
    __tablename__ = "driver_online_time"

    driver_profile_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    stat_date: Mapped[date] = mapped_column(Date, primary_key=True)
    online_seconds: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    synced_at: Mapped[datetime] = _now()


# ═══════════ 5. РЕФЕРАЛЫ И ЗАЯВКИ ═══════════
class Referral(Base):
    __tablename__ = "referrals"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    referrer_user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    referred_user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), unique=True,
                                                  nullable=False)
    referral_code: Mapped[str] = mapped_column(String(12), nullable=False)
    source: Mapped[str] = mapped_column(String(20), nullable=False, server_default="link")
    source_tag: Mapped[str] = mapped_column(String(16), nullable=False, server_default="tg")
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="clicked")
    is_counted: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    clicked_at: Mapped[datetime] = _now()
    registered_at: Mapped[datetime | None] = mapped_column(TS)
    approved_at: Mapped[datetime | None] = mapped_column(TS)
    hired_at: Mapped[datetime | None] = mapped_column(TS)
    first_ride_at: Mapped[datetime | None] = mapped_column(TS)
    first_qualified_at: Mapped[datetime | None] = mapped_column(TS)
    expires_at: Mapped[datetime | None] = mapped_column(TS)
    rejected_reason: Mapped[str | None] = mapped_column(String(64))
    risk_score: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    is_fraud: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    created_at: Mapped[datetime] = _now()


class ApprovalRequest(Base):
    __tablename__ = "approval_requests"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    referral_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("referrals.id"))
    found_profile_id: Mapped[str | None] = mapped_column(String(64))
    autocheck_result: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False, server_default="pending")
    reason: Mapped[str | None] = mapped_column(Text)
    decided_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    decided_at: Mapped[datetime | None] = mapped_column(TS)
    created_at: Mapped[datetime] = _now()


# ═══════════ 6. ЗАКАЗЫ ═══════════
class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    external_order_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    driver_profile_id: Mapped[str] = mapped_column(String(64), nullable=False)
    tariff_class: Mapped[str | None] = mapped_column(String(64))
    tariff_source: Mapped[str | None] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    price: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    distance_m: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    duration_sec: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    booked_at: Mapped[datetime | None] = mapped_column(TS)
    ended_at: Mapped[datetime | None] = mapped_column(TS)
    payment_method: Mapped[str | None] = mapped_column(String(32))
    address_from: Mapped[str | None] = mapped_column(Text)
    address_to: Mapped[str | None] = mapped_column(Text)
    raw: Mapped[dict | None] = mapped_column(JSONB)
    synced_at: Mapped[datetime] = _now()


class OrderDailyStat(Base):
    __tablename__ = "order_daily_stats"

    driver_profile_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    stat_date: Mapped[date] = mapped_column(Date, primary_key=True)
    tariff_class: Mapped[str] = mapped_column(String(64), primary_key=True)
    orders_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    eligible_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    points_x100: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    gmv: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")


# ═══════════ 7. КВАЛИФИКАЦИИ И ДЕНЬГИ ═══════════
class Qualification(Base):
    __tablename__ = "qualifications"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    referral_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("referrals.id"), nullable=False)
    period_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("periods.id"), nullable=False)
    eligible_orders_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    points_x100: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    threshold_points_x100: Mapped[int] = mapped_column(BigInteger, nullable=False)
    achieved_percent: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    is_qualified: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    breakdown: Mapped[Any | None] = mapped_column(JSONB)
    computed_at: Mapped[datetime] = _now()


class Withdrawal(Base):
    __tablename__ = "withdrawals"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    driver_profile_id: Mapped[str] = mapped_column(String(64), nullable=False)
    amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="pending")
    requires_manual: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    idempotency_token: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), unique=True, nullable=False)
    marker: Mapped[str | None] = mapped_column(String(32), unique=True)
    external_transaction_id: Mapped[str | None] = mapped_column(String(64))
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    last_error: Mapped[str | None] = mapped_column(Text)
    requested_at: Mapped[datetime] = _now()
    completed_at: Mapped[datetime | None] = mapped_column(TS)
    failed_at: Mapped[datetime | None] = mapped_column(TS)
    processed_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    proof_file_id: Mapped[str | None] = mapped_column(String(256))


class Accrual(Base):
    __tablename__ = "accruals"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    idempotency_key: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    type: Mapped[str] = mapped_column(String(20), nullable=False)
    referral_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("referrals.id"))
    milestone_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("milestones.id"))
    bonus_rule_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("bonus_rules.id"))
    period_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("periods.id"))
    withdrawal_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("withdrawals.id"))
    amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="available")
    hold_until: Mapped[datetime | None] = mapped_column(TS)
    released_at: Mapped[datetime | None] = mapped_column(TS)
    comment: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    parent_accrual_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("accruals.id"))
    created_at: Mapped[datetime] = _now()


class UserMilestone(Base):
    __tablename__ = "user_milestones"

    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), primary_key=True)
    milestone_id: Mapped[int] = mapped_column(Integer, ForeignKey("milestones.id", ondelete="RESTRICT"),
                                              primary_key=True)
    achieved_at: Mapped[datetime] = _now()
    accrual_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("accruals.id"))
    granted_without_payment: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")


class Correction(Base):
    __tablename__ = "corrections"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    applied: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    debt_created: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    created_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    created_at: Mapped[datetime] = _now()


class WalletLedger(Base):
    __tablename__ = "wallet_ledger"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    type: Mapped[str] = mapped_column(String(32), nullable=False)
    amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    balance_after: Mapped[int] = mapped_column(BigInteger, nullable=False)
    debt_after: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    ref_type: Mapped[str | None] = mapped_column(String(32))
    ref_id: Mapped[int | None] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = _now()


# ═══════════ 8. СЛУЖЕБНЫЕ ═══════════
class Setting(Base):
    __tablename__ = "settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[Any] = mapped_column(JSONB, nullable=False)
    value_type: Mapped[str] = mapped_column(String(16), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    updated_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    updated_at: Mapped[datetime] = _now()


class SettingsHistory(Base):
    __tablename__ = "settings_history"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    entity: Mapped[str] = mapped_column(String(32), nullable=False)
    key: Mapped[str] = mapped_column(String(64), nullable=False)
    old_value: Mapped[Any | None] = mapped_column(JSONB)
    new_value: Mapped[Any | None] = mapped_column(JSONB)
    effective_from: Mapped[date | None] = mapped_column(Date)
    changed_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    changed_at: Mapped[datetime] = _now()


class FraudFlag(Base):
    __tablename__ = "fraud_flags"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    referral_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("referrals.id"))
    user_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    rule_code: Mapped[str] = mapped_column(String(32), nullable=False)
    severity: Mapped[str] = mapped_column(String(16), nullable=False)
    score: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    details: Mapped[Any | None] = mapped_column(JSONB)
    resolved: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    resolved_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    resolved_at: Mapped[datetime | None] = mapped_column(TS)
    period_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("periods.id"))
    created_at: Mapped[datetime] = _now()


class Broadcast(Base):
    __tablename__ = "broadcasts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    title: Mapped[str | None] = mapped_column(String(256))
    text: Mapped[str | None] = mapped_column(Text)
    media: Mapped[Any | None] = mapped_column(JSONB)
    buttons: Mapped[Any | None] = mapped_column(JSONB)
    segment: Mapped[Any | None] = mapped_column(JSONB)
    scheduled_at: Mapped[datetime | None] = mapped_column(TS)
    started_at: Mapped[datetime | None] = mapped_column(TS)
    finished_at: Mapped[datetime | None] = mapped_column(TS)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="draft")
    total: Mapped[int | None] = mapped_column(Integer, server_default="0")
    sent: Mapped[int | None] = mapped_column(Integer, server_default="0")
    failed: Mapped[int | None] = mapped_column(Integer, server_default="0")
    blocked: Mapped[int | None] = mapped_column(Integer, server_default="0")
    created_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))


class BroadcastRecipient(Base):
    __tablename__ = "broadcast_recipients"

    broadcast_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("broadcasts.id"), primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), primary_key=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="queued")
    error: Mapped[str | None] = mapped_column(Text)
    sent_at: Mapped[datetime | None] = mapped_column(TS)
    outbox_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("notification_outbox.id"))


class SupportTicket(Base):
    __tablename__ = "support_tickets"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    subject: Mapped[str | None] = mapped_column(String(256))
    kind: Mapped[str] = mapped_column(String(20), nullable=False, server_default="general")
    context: Mapped[Any | None] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="open")
    assigned_to: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    sla_due_at: Mapped[datetime | None] = mapped_column(TS)
    created_at: Mapped[datetime] = _now()
    closed_at: Mapped[datetime | None] = mapped_column(TS)
    admin_message_id: Mapped[int | None] = mapped_column(BigInteger)
    admin_thread_id: Mapped[int | None] = mapped_column(BigInteger)


class SupportMessage(Base):
    __tablename__ = "support_messages"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    ticket_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("support_tickets.id"), nullable=False)
    author_type: Mapped[str] = mapped_column(String(10), nullable=False)
    author_id: Mapped[int | None] = mapped_column(BigInteger)
    text: Mapped[str | None] = mapped_column(Text)
    media: Mapped[Any | None] = mapped_column(JSONB)
    created_at: Mapped[datetime] = _now()


class NotificationLog(Base):
    __tablename__ = "notification_log"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    subject_id: Mapped[int | None] = mapped_column(BigInteger)
    sent_at: Mapped[datetime] = _now()


class Blacklist(Base):
    __tablename__ = "blacklist"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    entry_type: Mapped[str] = mapped_column(String(20), nullable=False)
    value: Mapped[str] = mapped_column(String(128), nullable=False)
    reason: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    created_at: Mapped[datetime] = _now()


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    actor_user_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    action: Mapped[str] = mapped_column(String(64), nullable=False)
    entity_type: Mapped[str | None] = mapped_column(String(32))
    entity_id: Mapped[int | None] = mapped_column(BigInteger)
    old_value: Mapped[Any | None] = mapped_column(JSONB)
    new_value: Mapped[Any | None] = mapped_column(JSONB)
    ip: Mapped[str | None] = mapped_column(INET)
    created_at: Mapped[datetime] = _now()


class ApiSyncLog(Base):
    __tablename__ = "api_sync_log"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    provider: Mapped[str | None] = mapped_column(String(32))
    method: Mapped[str | None] = mapped_column(String(128))
    status_code: Mapped[int | None] = mapped_column(Integer)
    duration_ms: Mapped[int | None] = mapped_column(Integer)
    records_count: Mapped[int | None] = mapped_column(Integer)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _now()


class JobLock(Base):
    __tablename__ = "job_locks"

    job_name: Mapped[str] = mapped_column(String(64), primary_key=True)
    locked_at: Mapped[datetime] = mapped_column(TS, nullable=False)
    locked_until: Mapped[datetime] = mapped_column(TS, nullable=False)


# ═══════════ Дополнения (DECISIONS.md) ═══════════
class NotificationOutbox(Base):
    __tablename__ = "notification_outbox"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    chat_id: Mapped[int | None] = mapped_column(BigInteger)
    audience: Mapped[str] = mapped_column(String(16), nullable=False, server_default="user")
    template_key: Mapped[str] = mapped_column(String(64), nullable=False)
    params: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default="{}")
    buttons: Mapped[Any | None] = mapped_column(JSONB)
    media: Mapped[Any | None] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column(String(16), nullable=False, server_default="queued")
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    error: Mapped[str | None] = mapped_column(Text)
    not_before: Mapped[datetime] = _now()
    created_at: Mapped[datetime] = _now()
    sent_at: Mapped[datetime | None] = mapped_column(TS)


class SyncCursor(Base):
    __tablename__ = "sync_cursors"

    name: Mapped[str] = mapped_column(String(64), primary_key=True)
    cursor_at: Mapped[datetime] = mapped_column(TS, nullable=False)
    updated_at: Mapped[datetime] = _now()


class AdminCredential(Base):
    __tablename__ = "admin_credentials"

    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), primary_key=True)
    login: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(256), nullable=False)
    totp_secret: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = _now()


class UserNote(Base):
    __tablename__ = "user_notes"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), nullable=False)
    author_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    text: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = _now()


class FraudWhitelist(Base):
    __tablename__ = "fraud_whitelist"

    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"), primary_key=True)
    reason: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("users.id"))
    created_at: Mapped[datetime] = _now()


class TaskQueueItem(Base):
    """Очередь задач в PostgreSQL (режим без Redis)."""

    __tablename__ = "task_queue"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    func: Mapped[str] = mapped_column(String(64), nullable=False)
    args: Mapped[Any] = mapped_column(JSONB, nullable=False, server_default="[]")
    job_key: Mapped[str] = mapped_column(String(200), nullable=False)
    run_at: Mapped[datetime] = _now()
    status: Mapped[str] = mapped_column(String(16), nullable=False, server_default="queued")
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    last_error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _now()
    finished_at: Mapped[datetime | None] = mapped_column(TS)


class FsmState(Base):
    """Состояние диалогов бота (FSM aiogram) в PostgreSQL (режим без Redis)."""

    __tablename__ = "fsm_storage"

    key: Mapped[str] = mapped_column(String(256), primary_key=True)
    state: Mapped[str | None] = mapped_column(String(256))
    data: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default="{}")
    updated_at: Mapped[datetime] = _now()
