"""Условия программы с версионированием и приёмом (2.13, N3)."""

from __future__ import annotations

from typing import Any

from sqlalchemy import exists, func, select

from src.core.admin.audit import audit_log
from src.core.context import Ctx
from src.core.errors import BusinessError
from src.core.notifications.service import notify_all
from src.db.models import ProgramTerms, User, UserTermsAcceptance


async def current_terms(ctx: Ctx) -> ProgramTerms | None:
    return (await ctx.session.execute(
        select(ProgramTerms).where(ProgramTerms.published_at.is_not(None))
        .order_by(ProgramTerms.version.desc()).limit(1)
    )).scalar_one_or_none()


async def has_accepted_current_terms(ctx: Ctx, user_id: int) -> bool:
    terms = await current_terms(ctx)
    if terms is None:
        return True
    return bool(await ctx.session.scalar(select(exists().where(
        UserTermsAcceptance.user_id == user_id, UserTermsAcceptance.terms_id == terms.id))))


async def accept_current_terms(ctx: Ctx, user_id: int) -> ProgramTerms:
    terms = await current_terms(ctx)
    if terms is None:
        raise BusinessError("err.no_terms")
    if not await ctx.session.scalar(select(exists().where(
            UserTermsAcceptance.user_id == user_id, UserTermsAcceptance.terms_id == terms.id))):
        ctx.session.add(UserTermsAcceptance(user_id=user_id, terms_id=terms.id, accepted_at=ctx.now()))
        await ctx.session.flush()
    return terms


async def accepted_version(ctx: Ctx, user_id: int) -> tuple[int, Any] | None:
    row = (await ctx.session.execute(
        select(ProgramTerms.version, UserTermsAcceptance.accepted_at)
        .join(UserTermsAcceptance, UserTermsAcceptance.terms_id == ProgramTerms.id)
        .where(UserTermsAcceptance.user_id == user_id)
        .order_by(ProgramTerms.version.desc()).limit(1))).first()
    return (row[0], row[1]) if row else None


async def create_terms_draft(ctx: Ctx, *, actor_id: int, text_ru: str, text_uz_latn: str,
                             text_uz_cyrl: str) -> ProgramTerms:
    if not (text_ru.strip() and text_uz_latn.strip() and text_uz_cyrl.strip()):
        raise BusinessError("err.terms_all_languages_required")
    version = int(await ctx.session.scalar(select(func.coalesce(func.max(ProgramTerms.version), 0))) or 0) + 1
    terms = ProgramTerms(version=version, text_ru=text_ru, text_uz_latn=text_uz_latn, text_uz_cyrl=text_uz_cyrl)
    ctx.session.add(terms)
    await ctx.session.flush()
    await audit_log(ctx, actor_id, "terms_draft_created", "program_terms", terms.id, new_value={"version": version})
    return terms


async def publish_terms(ctx: Ctx, terms_id: int, actor_id: int) -> ProgramTerms:
    """Публикация новой версии: все водители при следующем входе увидят экран приёма."""
    terms = await ctx.session.get(ProgramTerms, terms_id)
    if terms is None:
        raise BusinessError("err.not_found", entity="terms", id=str(terms_id))
    if terms.published_at is not None:
        raise BusinessError("err.terms_already_published")
    terms.published_at = ctx.now()
    terms.published_by = actor_id
    await audit_log(ctx, actor_id, "terms_published", "program_terms", terms.id, new_value={"version": terms.version})
    await notify_all(ctx, "terms.updated", only_approved=False)
    await ctx.session.flush()
    return terms


async def terms_stats(ctx: Ctx) -> dict[str, Any]:
    terms = await current_terms(ctx)
    total = int(await ctx.session.scalar(select(func.count()).select_from(User).where(User.role == "driver")) or 0)
    accepted = 0
    if terms:
        accepted = int(await ctx.session.scalar(select(func.count()).select_from(UserTermsAcceptance)
                                                .where(UserTermsAcceptance.terms_id == terms.id)) or 0)
    return {"version": terms.version if terms else None, "total_users": total, "accepted": accepted,
            "not_accepted": max(total - accepted, 0)}


async def users_not_accepted(ctx: Ctx, limit: int | None = None) -> list[User]:
    terms = await current_terms(ctx)
    if terms is None:
        return []
    q = (select(User).where(User.role == "driver", User.access_status.in_(["approved", "pending_approval"]),
                            ~exists().where(UserTermsAcceptance.user_id == User.id,
                                            UserTermsAcceptance.terms_id == terms.id))
         .order_by(User.id))
    if limit:
        q = q.limit(limit)
    return list((await ctx.session.execute(q)).scalars().all())
