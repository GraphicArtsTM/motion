"""Контроль бюджета программы (2.10, N7)."""

from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import func, select

from src.core.clock import month_code
from src.core.context import Ctx
from src.db.models import Accrual, Period


@dataclass
class BudgetTracker:
    budget: int
    spent: int = 0
    alerted: bool = field(default=False)

    def is_over(self, amount: int) -> bool:
        return self.budget > 0 and self.spent + amount > self.budget


async def period_spent(ctx: Ctx, period_id: int) -> int:
    return int(await ctx.session.scalar(
        select(func.coalesce(func.sum(Accrual.amount), 0)).where(
            Accrual.period_id == period_id,
            (Accrual.status != "cancelled") | (Accrual.comment == "debt_repayment"))
    ) or 0)


async def budget_usage(ctx: Ctx) -> dict[str, int | str | None]:
    """Индикатор освоения бюджета: начислено за последний закрытый период + прогноз текущего."""
    code = month_code(ctx.now())
    budget = ctx.settings.int("monthly_program_budget")
    period = (await ctx.session.execute(select(Period).where(Period.code == code))).scalar_one_or_none()
    spent = await period_spent(ctx, period.id) if period else 0
    percent = spent * 100 // budget if budget else None
    return {"period": code, "budget": budget, "spent": spent, "percent": percent}
