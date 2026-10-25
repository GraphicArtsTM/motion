"""Admin API веб-панели (Раздел 8). Тонкий слой над core/: проверка роли → вызов ядра → JSON."""

from __future__ import annotations

import csv
import io
from datetime import date, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy import select

from src.admin.auth import current_admin, get_ctx, login, require
from src.core.admin import broadcasts as bc
from src.core.admin import users as users_admin
from src.core.admin.audit import audit_log
from src.core.admin.dashboard import dashboard
from src.core.admin.reports import REPORTS
from src.core.admin.settings_admin import apply_rules_to_current_period, load_fleet_categories, update_setting
from src.core.billing import bonus_rules, milestones
from src.core.billing.periods import close_period, get_period
from src.core.billing.recalculation import recalculate_closed_period
from src.core.billing.withdrawal import (
    approve_withdrawal,
    cancel_withdrawal,
    mark_paid_manually,
    retry_withdrawal,
)
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.fraud.engine import resolve_flag, whitelist_user
from src.core.onboarding import terms as terms_core
from src.core.onboarding.approval import admin_decide, pending_requests
from src.core.onboarding.registration import approval_card_params
from src.core.referral.attribution import admin_link_referral, admin_unlink_referral, set_is_counted
from src.core.referral.matching import admin_link_profile, admin_unlink_profile
from src.core.scoring.coefficients import delete_tariff, tariff_table, upsert_tariff
from src.core.scoring.snapshot import period_coefficients
from src.core.simulation.simulator import compare, current_draft
from src.core.support.tickets import close_ticket, reply_to_ticket
from src.db.models import (
    Accrual,
    AuditLog,
    Broadcast,
    FraudFlag,
    Period,
    Referral,
    Setting,
    SupportMessage,
    SupportTicket,
    User,
    Withdrawal,
)

router = APIRouter(prefix="/admin/api")


def jsonable(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: jsonable(v) for k, v in obj.items()}
    if isinstance(obj, list | tuple | set):
        return [jsonable(v) for v in obj]
    if isinstance(obj, datetime | date):
        return obj.isoformat()
    if hasattr(obj, "__table__"):
        return {c.name: jsonable(getattr(obj, c.name)) for c in obj.__table__.columns
                if c.name not in ("password_hash", "totp_secret")}
    if hasattr(obj, "as_dict"):
        return jsonable(obj.as_dict())
    if hasattr(obj, "__dataclass_fields__"):
        return {k: jsonable(getattr(obj, k)) for k in obj.__dataclass_fields__}
    return obj


def business_error_handler(_: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, BusinessError)
    return JSONResponse({"error": exc.key, "params": jsonable(exc.params)}, status_code=400)


# ── схемы запросов ───────────────────────────────────────────────────────────
class LoginIn(BaseModel):
    login: str
    password: str
    totp: str | None = None


class DecisionIn(BaseModel):
    decision: str
    reason: str = ""


class TariffIn(BaseModel):
    name: str | None = None
    coefficient_x100: int | None = Field(default=None, gt=0)
    is_active: bool | None = None
    sort_order: int | None = None


class BonusRuleIn(BaseModel):
    recipient: str
    min_percent: int
    bonus_uzs: int
    is_active: bool = True


class MilestoneIn(BaseModel):
    name: str
    required_count: int
    reward_uzs: int
    is_active: bool = False
    sort_order: int = 100


class ToggleIn(BaseModel):
    mode: str = "from_now"
    confirm: bool = False


class WelcomeIn(BaseModel):
    enabled: bool
    max_periods: int | None = None
    confirm: bool = False


class ReasonIn(BaseModel):
    reason: str = ""


class SimulateIn(BaseModel):
    period: str
    draft: dict[str, Any] = {}


class SettingIn(BaseModel):
    value: Any


class RecalcIn(BaseModel):
    reason: str
    preview: bool = True


class TermsIn(BaseModel):
    text_ru: str
    text_uz_latn: str
    text_uz_cyrl: str


class ValueIn(BaseModel):
    value: Any
    reason: str = ""


class AdjustmentIn(BaseModel):
    amount: int
    reason: str


class TextIn(BaseModel):
    text: str


class LinkProfileIn(BaseModel):
    driver_profile_id: str


class LinkReferralIn(BaseModel):
    referrer_code: str
    counted: bool = True


class PaidIn(BaseModel):
    proof_file_id: str
    reference: str | None = None


class BroadcastIn(BaseModel):
    title: str
    text: str
    segment: dict[str, Any] = {}
    media: dict[str, Any] | None = None
    buttons: list[Any] | None = None
    scheduled_at: datetime | None = None


class ResolveIn(BaseModel):
    confirm_fraud: bool = False


class WhitelistIn(BaseModel):
    user_id: int
    reason: str


class BulkCountedIn(BaseModel):
    referral_ids: list[int]
    value: bool


# ── авторизация ──────────────────────────────────────────────────────────────
@router.post("/auth/login")
async def auth_login(body: LoginIn, request: Request, ctx: Ctx = Depends(get_ctx)) -> dict[str, str]:
    token = await login(ctx.session, body.login, body.password, body.totp)
    await audit_log(ctx, None, "admin_login", "admin", None, new_value={"login": body.login},
                    ip=request.client.host if request.client else None)
    return {"token": token}


@router.get("/me")
async def me(user: User = Depends(current_admin)) -> dict[str, Any]:
    return {"id": user.id, "role": user.role, "full_name": user.full_name}


# ── дашборд ──────────────────────────────────────────────────────────────────
@router.get("/dashboard")
async def get_dashboard(ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    return jsonable(await dashboard(ctx))


# ── заявки на подключение ────────────────────────────────────────────────────
@router.get("/approvals")
async def approvals(ctx: Ctx = Depends(get_ctx), _: User = Depends(require("moderator"))) -> Any:
    out = []
    for req in await pending_requests(ctx):
        card = await approval_card_params(ctx, req)
        card["sla_hours"] = int((ctx.now() - req.created_at).total_seconds() // 3600)
        out.append(card)
    return jsonable(out)


@router.post("/approvals/{request_id}/decide")
async def decide(request_id: int, body: DecisionIn, ctx: Ctx = Depends(get_ctx),
                 user: User = Depends(require("moderator"))) -> Any:
    req = await admin_decide(ctx, request_id, user, body.decision, body.reason)
    return jsonable(req)


@router.get("/drivers/{user_id}/license-photos")
async def license_photos(user_id: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("moderator"))) -> Any:
    front, back = await users_admin.log_photo_view(ctx, user, user_id)
    return {"front_file_id": front, "back_file_id": back}


# ── правила программы ────────────────────────────────────────────────────────
@router.get("/rules")
async def rules(ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    s = ctx.settings
    return jsonable({
        "threshold_points_x100": s.int("qualification_threshold_points_x100"),
        "tariffs": await tariff_table(ctx, only_active=False),
        "bonus_rules": await bonus_rules.rules_as_dicts(ctx),
        "milestones": await milestones.all_milestones(ctx),
        "milestones_enabled": s.bool("milestones_enabled"),
        "milestones_activation_mode": s.str("milestones_activation_mode"),
        "referred_bonus_enabled": s.bool("referred_bonus_enabled"),
        "referred_bonus_max_periods": s.int("referred_bonus_max_periods"),
        "eligible": {k: s.get(k) for k in ("eligible_order_statuses", "min_order_price", "min_order_distance_m",
                                           "min_order_duration_sec")},
        "budget": {k: s.int(k) for k in ("monthly_program_budget", "max_payout_per_referrer_per_month")},
    })


@router.put("/rules/tariffs/{code}")
async def put_tariff(code: str, body: TariffIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    await upsert_tariff(ctx, code=code, actor_id=user.id, **body.model_dump())
    return jsonable(await tariff_table(ctx, only_active=False))  # «Заказов до плана» пересчитан (TC-95)


@router.delete("/rules/tariffs/{code}")
async def del_tariff(code: str, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    await delete_tariff(ctx, code, user.id)
    return {"ok": True}


@router.post("/rules/bonus")
async def add_bonus_rule(body: BonusRuleIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    return jsonable(await bonus_rules.upsert_rule(ctx, actor_id=user.id, **body.model_dump()))


@router.put("/rules/bonus/{rule_id}")
async def put_bonus_rule(rule_id: int, body: BonusRuleIn, ctx: Ctx = Depends(get_ctx),
                         user: User = Depends(require("admin"))) -> Any:
    return jsonable(await bonus_rules.upsert_rule(ctx, actor_id=user.id, rule_id=rule_id, **body.model_dump()))


@router.delete("/rules/bonus/{rule_id}")
async def del_bonus_rule(rule_id: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    await bonus_rules.delete_rule(ctx, rule_id, user.id)
    return {"ok": True}


@router.put("/rules/milestones/{code}")
async def put_milestone(code: str, body: MilestoneIn, ctx: Ctx = Depends(get_ctx),
                        user: User = Depends(require("admin"))) -> Any:
    return jsonable(await milestones.upsert_milestone(ctx, actor_id=user.id, code=code, **body.model_dump()))


@router.delete("/rules/milestones/{milestone_id}")
async def del_milestone(milestone_id: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    await milestones.delete_milestone(ctx, milestone_id, user.id)
    return {"ok": True}


async def _last_closed_code(ctx: Ctx) -> str:
    code = await ctx.session.scalar(select(Period.code).where(Period.status == "closed")
                                    .order_by(Period.starts_at.desc()).limit(1))
    if code is None:
        raise BusinessError("err.not_found", entity="period", id="closed")
    return str(code)


@router.post("/rules/milestones/enable")
async def enable_ms(body: ToggleIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    """Перед включением — обязательный прогон симулятора с показом стоимости в обоих режимах (8.2.3)."""
    if not body.confirm:
        code = await _last_closed_code(ctx)
        return {"confirm_required": True, "simulation": {
            mode: jsonable(await compare(ctx, code, {"milestones_enabled": True, "milestones_activation_mode": mode}))
            for mode in ("from_now", "retroactive")}}
    return jsonable(await milestones.enable_milestones(ctx, actor=user, mode=body.mode))


@router.post("/rules/milestones/disable")
async def disable_ms(ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    await milestones.disable_milestones(ctx, actor=user)
    return {"ok": True}


@router.post("/rules/welcome")
async def welcome_toggle(body: WelcomeIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    if body.enabled and not body.confirm:
        code = await _last_closed_code(ctx)
        rules_draft = [{**r, "is_active": True} if r["recipient"] == "referred" else r
                       for r in await bonus_rules.rules_as_dicts(ctx)]
        draft = {"referred_bonus_enabled": True, "bonus_rules": rules_draft}
        if body.max_periods is not None:
            draft["referred_bonus_max_periods"] = body.max_periods
        return {"confirm_required": True, "simulation": jsonable(await compare(ctx, code, draft))}
    if body.max_periods is not None:
        await update_setting(ctx, user, "referred_bonus_max_periods", body.max_periods)
    await update_setting(ctx, user, "referred_bonus_enabled", body.enabled, simulated=True)
    return {"ok": True}


@router.post("/rules/simulate")
async def simulate_rules(body: SimulateIn, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("admin"))) -> Any:
    return jsonable(await compare(ctx, body.period, body.draft))  # ничего не сохраняет (TC-97)


@router.get("/rules/simulate/base/{period}")
async def simulate_base(period: str, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("admin"))) -> Any:
    return jsonable(await current_draft(ctx, period))


@router.post("/rules/apply-current")
async def apply_current(body: ReasonIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("superadmin"))) -> Any:
    await apply_rules_to_current_period(ctx, user, body.reason)
    return {"ok": True}


# ── настройки ────────────────────────────────────────────────────────────────
@router.get("/settings")
async def get_settings(ctx: Ctx = Depends(get_ctx), _: User = Depends(require("admin", write=False))) -> Any:
    rows = (await ctx.session.execute(select(Setting).order_by(Setting.key))).scalars().all()
    return jsonable(rows)


@router.put("/settings/{key}")
async def put_setting(key: str, body: SettingIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    return {"key": key, "value": jsonable(await update_setting(ctx, user, key, body.value))}


@router.post("/settings/fleet-categories/load")
async def fleet_categories(ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    return await load_fleet_categories(ctx, user)


# ── периоды ──────────────────────────────────────────────────────────────────
@router.get("/periods")
async def periods(ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    rows = (await ctx.session.execute(select(Period).order_by(Period.starts_at.desc()))).scalars().all()
    return [{**jsonable(p), "snapshot": await period_coefficients(ctx, p.id)} for p in rows]


@router.post("/periods/{code}/recalculate")
async def recalc(code: str, body: RecalcIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    period = await get_period(ctx, code)
    if period is None or period.status != "closed":
        raise HTTPException(400, "period must be closed")
    return jsonable(await recalculate_closed_period(ctx, period, body.reason, user.id, preview=body.preview))


@router.post("/periods/{code}/close")
async def close(code: str, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    """Идемпотентный перезапуск закрытия (например, после падения на шаге calculating)."""
    period = await get_period(ctx, code)
    if period is None or period.status == "closed" or period.ends_at > ctx.now():
        raise HTTPException(400, "period cannot be closed now")
    await audit_log(ctx, user.id, "period_close_rerun", "period", period.id)
    return jsonable(await close_period(ctx, period))


# ── условия программы ────────────────────────────────────────────────────────
@router.get("/terms")
async def list_terms(ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    from src.db.models import ProgramTerms
    rows = (await ctx.session.execute(select(ProgramTerms).order_by(ProgramTerms.version.desc()))).scalars().all()
    return {"versions": jsonable(rows), "stats": await terms_core.terms_stats(ctx)}


@router.post("/terms")
async def create_terms(body: TermsIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    return jsonable(await terms_core.create_terms_draft(ctx, actor_id=user.id, **body.model_dump()))


@router.post("/terms/{terms_id}/publish")
async def publish_terms(terms_id: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    return jsonable(await terms_core.publish_terms(ctx, terms_id, user.id))


@router.get("/terms/not-accepted")
async def terms_not_accepted(ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    return [{"id": u.id, "full_name": u.full_name, "phone": u.phone} for u in await terms_core.users_not_accepted(ctx)]


# ── водители ─────────────────────────────────────────────────────────────────
@router.get("/drivers")
async def drivers(q: str, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    return [{"id": u.id, "full_name": u.full_name, "phone": u.phone, "access_status": u.access_status,
             "referral_code": u.referral_code, "role": u.role} for u in await users_admin.search_users(ctx, q)]


@router.get("/drivers/{user_id}")
async def driver_card(user_id: int, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    return jsonable(await users_admin.user_card(ctx, user_id))


@router.post("/drivers/{user_id}/access-status")
async def driver_access(user_id: int, body: ValueIn, ctx: Ctx = Depends(get_ctx),
                        user: User = Depends(require("moderator"))) -> Any:
    await users_admin.set_access_status(ctx, user, user_id, str(body.value), body.reason)
    return {"ok": True}


@router.post("/drivers/{user_id}/payout-block")
async def driver_payout_block(user_id: int, body: ValueIn, ctx: Ctx = Depends(get_ctx),
                              user: User = Depends(require("finance"))) -> Any:
    await users_admin.set_payout_blocked(ctx, user, user_id, bool(body.value), body.reason)
    return {"ok": True}


@router.post("/drivers/{user_id}/adjustment")
async def driver_adjustment(user_id: int, body: AdjustmentIn, ctx: Ctx = Depends(get_ctx),
                            user: User = Depends(require("admin"))) -> Any:
    return jsonable(await users_admin.manual_adjustment(ctx, user, user_id, body.amount, body.reason))


@router.post("/drivers/{user_id}/debt-writeoff")
async def driver_debt(user_id: int, body: AdjustmentIn, ctx: Ctx = Depends(get_ctx),
                      user: User = Depends(require("admin"))) -> Any:
    return jsonable(await users_admin.forgive_debt(ctx, user, user_id, body.amount, body.reason))


@router.post("/drivers/{user_id}/note")
async def driver_note(user_id: int, body: TextIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("operator"))) -> Any:
    return jsonable(await users_admin.add_note(ctx, user, user_id, body.text))


@router.post("/drivers/{user_id}/message")
async def driver_message(user_id: int, body: TextIn, ctx: Ctx = Depends(get_ctx),
                         user: User = Depends(require("operator"))) -> Any:
    await users_admin.send_personal_message(ctx, user, user_id, body.text)
    return {"ok": True}


@router.post("/drivers/{user_id}/role")
async def driver_role(user_id: int, body: ValueIn, ctx: Ctx = Depends(get_ctx),
                      user: User = Depends(require("superadmin"))) -> Any:
    await users_admin.set_role(ctx, user, user_id, str(body.value))
    return {"ok": True}


@router.post("/drivers/{user_id}/link-profile")
async def driver_link(user_id: int, body: LinkProfileIn, ctx: Ctx = Depends(get_ctx),
                      user: User = Depends(require("moderator"))) -> Any:
    return jsonable(await admin_link_profile(ctx, user_id, body.driver_profile_id, user.id))


@router.post("/drivers/{user_id}/unlink-profile")
async def driver_unlink(user_id: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("moderator"))) -> Any:
    await admin_unlink_profile(ctx, user_id, user.id)
    return {"ok": True}


@router.post("/drivers/{user_id}/referral")
async def driver_referral(user_id: int, body: LinkReferralIn, ctx: Ctx = Depends(get_ctx),
                          user: User = Depends(require("moderator"))) -> Any:
    return jsonable(await admin_link_referral(ctx, referred_user_id=user_id, referrer_code=body.referrer_code,
                                              actor_id=user.id, counted=body.counted))


@router.delete("/drivers/{user_id}/personal-data")
async def driver_forget(user_id: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    await users_admin.delete_personal_data(ctx, user, user_id)
    return {"ok": True}


# ── рефералы ─────────────────────────────────────────────────────────────────
@router.get("/referrals")
async def referrals(status: str | None = None, tag: str | None = None, counted: bool | None = None,
                    ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    q = select(Referral).order_by(Referral.id.desc())
    if status:
        q = q.where(Referral.status == status)
    if tag:
        q = q.where(Referral.source_tag == tag)
    if counted is not None:
        q = q.where(Referral.is_counted.is_(counted))
    return jsonable((await ctx.session.execute(q.limit(1000))).scalars().all())


@router.post("/referrals/{referral_id}/counted")
async def referral_counted(referral_id: int, body: ValueIn, ctx: Ctx = Depends(get_ctx),
                           user: User = Depends(require("moderator"))) -> Any:
    await set_is_counted(ctx, referral_id, bool(body.value), user.id)
    return {"ok": True}


@router.post("/referrals/bulk-counted")
async def referral_bulk(body: BulkCountedIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("moderator"))) -> Any:
    for rid in body.referral_ids:
        await set_is_counted(ctx, rid, body.value, user.id)
    return {"ok": True, "count": len(body.referral_ids)}


@router.post("/referrals/{referral_id}/unlink")
async def referral_unlink(referral_id: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("moderator"))) -> Any:
    await admin_unlink_referral(ctx, referral_id, user.id)
    return {"ok": True}


# ── кошельки и выводы ────────────────────────────────────────────────────────
@router.get("/withdrawals")
async def withdrawals(status: str | None = None, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("finance"))) -> Any:
    q = select(Withdrawal).order_by(Withdrawal.id.desc())
    if status:
        q = q.where(Withdrawal.status == status)
    return jsonable((await ctx.session.execute(q.limit(1000))).scalars().all())


@router.post("/withdrawals/{wid}/approve")
async def wd_approve(wid: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("finance"))) -> Any:
    await approve_withdrawal(ctx, wid, user.id)
    return {"ok": True}


@router.post("/withdrawals/{wid}/paid")
async def wd_paid(wid: int, body: PaidIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("finance"))) -> Any:
    await mark_paid_manually(ctx, wid, user.id, body.proof_file_id, body.reference)
    return {"ok": True}


@router.post("/withdrawals/{wid}/cancel")
async def wd_cancel(wid: int, body: ReasonIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("finance"))) -> Any:
    await cancel_withdrawal(ctx, wid, user.id, body.reason or "admin")
    return {"ok": True}


@router.post("/withdrawals/{wid}/retry")
async def wd_retry(wid: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("finance"))) -> Any:
    await retry_withdrawal(ctx, wid, user.id)
    return {"ok": True}


# ── начисления ───────────────────────────────────────────────────────────────
@router.get("/accruals")
async def accruals(period: str | None = None, type: str | None = None, user_id: int | None = None,
                   ctx: Ctx = Depends(get_ctx), _: User = Depends(require("finance"))) -> Any:
    q = select(Accrual).order_by(Accrual.id.desc())
    if period:
        q = q.join(Period, Period.id == Accrual.period_id).where(Period.code == period)
    if type:
        q = q.where(Accrual.type == type)
    if user_id:
        q = q.where(Accrual.user_id == user_id)
    return jsonable((await ctx.session.execute(q.limit(5000))).scalars().all())


@router.post("/accruals/{accrual_id}/cancel")
async def accrual_cancel(accrual_id: int, body: ReasonIn, ctx: Ctx = Depends(get_ctx),
                         user: User = Depends(require("admin"))) -> Any:
    return {"cancelled": await users_admin.cancel_accrual_by_admin(ctx, user, accrual_id, body.reason)}


# ── рассылки ─────────────────────────────────────────────────────────────────
@router.get("/broadcasts")
async def broadcasts(ctx: Ctx = Depends(get_ctx), _: User = Depends(require("admin", write=False))) -> Any:
    return jsonable((await ctx.session.execute(select(Broadcast).order_by(Broadcast.id.desc()))).scalars().all())


@router.post("/broadcasts")
async def broadcast_create(body: BroadcastIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    b = await bc.create_broadcast(ctx, user, title=body.title, text_=body.text, segment=body.segment, media=body.media,
                                  buttons=body.buttons, scheduled_at=body.scheduled_at)
    return {**jsonable(b), "recipients": len(await bc.resolve_segment(ctx, body.segment))}


@router.post("/broadcasts/{bid}/start")
async def broadcast_start(bid: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    return {"recipients": await bc.start_broadcast(ctx, bid, user.id)}


@router.post("/broadcasts/{bid}/test")
async def broadcast_test(bid: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("admin"))) -> Any:
    await bc.test_send(ctx, user, bid)
    return {"ok": True}


@router.get("/broadcasts/{bid}/stats")
async def broadcast_stats(bid: int, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("admin", write=False))) -> Any:
    return await bc.refresh_stats(ctx, bid)


# ── поддержка ────────────────────────────────────────────────────────────────
@router.get("/tickets")
async def tickets(status: str | None = None, kind: str | None = None, ctx: Ctx = Depends(get_ctx),
                  _: User = Depends(require("operator"))) -> Any:
    q = select(SupportTicket).order_by(SupportTicket.id.desc())
    if status:
        q = q.where(SupportTicket.status == status)
    if kind:
        q = q.where(SupportTicket.kind == kind)
    return jsonable((await ctx.session.execute(q.limit(500))).scalars().all())


@router.get("/tickets/{tid}")
async def ticket(tid: int, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("operator"))) -> Any:
    t = await ctx.session.get(SupportTicket, tid)
    if t is None:
        raise HTTPException(404)
    msgs = (await ctx.session.execute(select(SupportMessage).where(SupportMessage.ticket_id == tid)
                                      .order_by(SupportMessage.id))).scalars().all()
    return {"ticket": jsonable(t), "messages": jsonable(msgs)}


@router.post("/tickets/{tid}/reply")
async def ticket_reply(tid: int, body: TextIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("operator"))) -> Any:
    await reply_to_ticket(ctx, tid, user, body.text)
    return {"ok": True}


@router.post("/tickets/{tid}/close")
async def ticket_close(tid: int, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("operator"))) -> Any:
    await close_ticket(ctx, tid, user)
    return {"ok": True}


# ── антифрод ─────────────────────────────────────────────────────────────────
@router.get("/fraud")
async def fraud_queue(resolved: bool = False, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("moderator"))) -> Any:
    rows = (await ctx.session.execute(select(FraudFlag, Referral.risk_score)
                                      .outerjoin(Referral, Referral.id == FraudFlag.referral_id)
                                      .where(FraudFlag.resolved.is_(resolved))
                                      .order_by(Referral.risk_score.desc().nulls_last(), FraudFlag.id.desc()))).all()
    return [{**jsonable(f), "risk_score": score} for f, score in rows]


@router.post("/fraud/{flag_id}/resolve")
async def fraud_resolve(flag_id: int, body: ResolveIn, ctx: Ctx = Depends(get_ctx),
                        user: User = Depends(require("moderator"))) -> Any:
    await resolve_flag(ctx, flag_id, user.id, confirm_fraud=body.confirm_fraud)
    return {"ok": True}


@router.post("/fraud/whitelist")
async def fraud_whitelist(body: WhitelistIn, ctx: Ctx = Depends(get_ctx), user: User = Depends(require("moderator"))) -> Any:
    await whitelist_user(ctx, body.user_id, user.id, body.reason)
    return {"ok": True}


# ── отчёты и audit log ───────────────────────────────────────────────────────
@router.get("/reports/{name}")
async def report(name: str, format: str = "json", ctx: Ctx = Depends(get_ctx),
                 user: User = Depends(require("operator", write=False))) -> Any:
    if name not in REPORTS:
        raise HTTPException(404)
    if name in ("withdrawals",) and user.role not in ("finance", "admin", "superadmin", "readonly"):
        raise HTTPException(403)
    if name == "audit" and user.role != "superadmin":
        raise HTTPException(403)
    head, rows = await REPORTS[name](ctx)
    rows = jsonable(rows)
    if format == "csv":
        buf = io.StringIO()
        w = csv.writer(buf, delimiter=";")
        w.writerow(head)
        w.writerows(rows)
        return StreamingResponse(iter([buf.getvalue().encode("utf-8-sig")]), media_type="text/csv",
                                 headers={"Content-Disposition": f"attachment; filename={name}.csv"})
    if format == "xlsx":
        from openpyxl import Workbook
        wb = Workbook()
        ws = wb.active
        ws.title = name[:31]
        ws.append(head)
        for r in rows:
            ws.append([str(v) if isinstance(v, dict | list) else v for v in r])
        out = io.BytesIO()
        wb.save(out)
        return StreamingResponse(iter([out.getvalue()]),
                                 media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                 headers={"Content-Disposition": f"attachment; filename={name}.xlsx"})
    return {"head": head, "rows": rows}


@router.get("/audit")
async def audit(limit: int = 200, ctx: Ctx = Depends(get_ctx), _: User = Depends(require("superadmin", write=False))) -> Any:
    return jsonable((await ctx.session.execute(select(AuditLog).order_by(AuditLog.id.desc()).limit(limit))).scalars().all())
