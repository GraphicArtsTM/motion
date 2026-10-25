"""SQLAdmin: просмотр таблиц в браузере (только чтение — все изменения идут через admin API и ядро)."""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from sqladmin import Admin, ModelView
from sqladmin.authentication import AuthenticationBackend
from starlette.requests import Request

from src.admin.auth import TOKEN_TTL_SECONDS, login, serializer
from src.db import models as m
from src.db.session import get_sessionmaker


class ReadOnlyView(ModelView):
    can_create = False
    can_edit = False
    can_delete = False
    can_export = True
    page_size = 100


def view(model: Any, cols: list[str], *, search: list[str] | None = None, icon: str = "fa-solid fa-table") -> type:
    attrs = {"column_list": [getattr(model, c) for c in cols], "icon": icon,
             "column_searchable_list": [getattr(model, c) for c in (search or [])],
             "column_default_sort": [(getattr(model, cols[0]), True)]}
    return type(f"{model.__name__}Admin", (ReadOnlyView,), attrs, model=model)


VIEWS = [
    view(m.User, ["id", "telegram_id", "full_name", "phone", "access_status", "role", "referral_code",
                  "balance_available", "balance_hold", "debt", "payout_blocked"],
         search=["full_name", "phone", "referral_code", "driver_license"], icon="fa-solid fa-user"),
    view(m.ApprovalRequest, ["id", "user_id", "referral_id", "autocheck_result", "status", "created_at", "decided_at"]),
    view(m.Referral, ["id", "referrer_user_id", "referred_user_id", "status", "is_counted", "source_tag",
                      "risk_score", "is_fraud", "clicked_at"]),
    view(m.Accrual, ["id", "user_id", "type", "amount", "status", "period_id", "referral_id", "created_at"]),
    view(m.Withdrawal, ["id", "user_id", "amount", "status", "requires_manual", "marker", "external_transaction_id",
                        "requested_at", "completed_at"], icon="fa-solid fa-money-bill"),
    view(m.Period, ["id", "code", "status", "threshold_points_x100", "closed_at", "recalculated_at"]),
    view(m.Qualification, ["id", "referral_id", "period_id", "points_x100", "achieved_percent", "is_qualified"]),
    view(m.Order, ["id", "external_order_id", "driver_profile_id", "tariff_class", "tariff_source", "status", "price",
                   "ended_at"], search=["external_order_id", "driver_profile_id"]),
    view(m.ParkDriverProfile, ["driver_profile_id", "first_name", "last_name", "phone_normalized",
                               "license_normalized", "work_status", "car_category", "is_stale"],
         search=["driver_profile_id", "phone_normalized", "license_normalized"]),
    view(m.TariffCoefficient, ["code", "name", "coefficient_x100", "is_active", "needs_setup"]),
    view(m.BonusRule, ["id", "recipient", "min_percent", "bonus_uzs", "is_active"]),
    view(m.Milestone, ["id", "code", "required_count", "reward_uzs", "is_active"]),
    view(m.FraudFlag, ["id", "referral_id", "rule_code", "severity", "score", "resolved", "created_at"]),
    view(m.SupportTicket, ["id", "user_id", "kind", "status", "subject", "created_at"]),
    view(m.Broadcast, ["id", "title", "status", "total", "sent", "failed", "blocked", "scheduled_at"]),
    view(m.SettingsHistory, ["id", "entity", "key", "effective_from", "changed_by", "changed_at"]),
    view(m.AuditLog, ["id", "actor_user_id", "action", "entity_type", "entity_id", "created_at"]),
    view(m.ApiSyncLog, ["id", "provider", "method", "status_code", "duration_ms", "records_count", "error",
                        "created_at"]),
    view(m.NotificationOutbox, ["id", "user_id", "audience", "template_key", "status", "attempts", "created_at"]),
]


class PanelAuth(AuthenticationBackend):
    async def login(self, request: Request) -> bool:
        form = await request.form()
        try:
            async with get_sessionmaker()() as s:
                token = await login(s, str(form.get("username")), str(form.get("password")),
                                    str(form.get("totp") or "") or None)
        except Exception:  # noqa: BLE001
            return False
        request.session.update({"token": token})
        return True

    async def logout(self, request: Request) -> bool:
        request.session.clear()
        return True

    async def authenticate(self, request: Request) -> bool:
        token = request.session.get("token")
        if not token:
            return False
        try:
            serializer().loads(token, max_age=TOKEN_TTL_SECONDS)
        except Exception:  # noqa: BLE001
            return False
        return True


def mount_sqladmin(app: FastAPI, engine: Any, secret: str) -> Admin:
    admin = Admin(app, engine, base_url="/admin", title="Реферальная программа",
                  authentication_backend=PanelAuth(secret_key=secret))
    for v in VIEWS:
        admin.add_view(v)
    return admin
