"""Режим без Docker: очередь задач и FSM в PostgreSQL, планировщик, мастер с LOCAL_MODE."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from aiogram.fsm.state import State, StatesGroup
from aiogram.fsm.storage.base import StorageKey
from sqlalchemy import select

from src.bot.fsm_storage import DbStorage
from src.core.clock import display_tz
from src.db.models import TaskQueueItem, Withdrawal
from src.runtime import set_clock, set_fleet, set_queue
from src.workers import dbqueue
from src.workers.dbqueue import DbQueue, recover_running, run_due_tasks
from src.workers.schedule import due
from tests.factories import create_user, with_profile


class Form(StatesGroup):
    phone = State()


async def test_db_queue_dedup_and_delay(sessionmaker):
    q = DbQueue()
    await q.enqueue("process_withdrawal", 7, 0)
    await q.enqueue("process_withdrawal", 7, 0)            # та же задача — без дубля
    await q.enqueue("process_withdrawal", 7, 1, delay_seconds=3600)
    async with sessionmaker() as s:
        rows = (await s.execute(select(TaskQueueItem).order_by(TaskQueueItem.id))).scalars().all()
    assert [r.job_key for r in rows] == ["process_withdrawal:7:0", "process_withdrawal:7:1"]
    assert rows[1].run_at > datetime.now(UTC) + timedelta(minutes=50)


async def test_withdrawal_runs_through_db_queue(sessionmaker, fleet, clock, ctx):
    """Полный путь вывода в режиме без Redis: заявка → task_queue → исполнитель → Fleet."""
    from src.core.billing.accruals import create_accrual_if_not_exists
    from src.core.billing.withdrawal import request_withdrawal
    set_fleet(fleet)
    set_clock(clock)
    queue = DbQueue()
    set_queue(queue)
    try:
        u = await create_user(ctx)
        await with_profile(ctx, u)
        await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key="lq", type="manual", amount=30000,
                                           status="available")
        await ctx.session.commit()
        ctx.queue = queue
        w = await request_withdrawal(ctx, u.id)
        assert await run_due_tasks() == 1
        async with sessionmaker() as s:
            assert (await s.get(Withdrawal, w.id)).status == "completed"
            item = (await s.execute(select(TaskQueueItem))).scalar_one()
            assert item.status == "done" and item.attempts == 1
        assert len(fleet.transactions) == 1
    finally:
        set_fleet(None)
        set_clock(None)


async def test_failed_task_and_recovery(sessionmaker, monkeypatch):
    async def boom(_ctx, *args):
        raise RuntimeError("нет сети")
    monkeypatch.setattr(dbqueue, "task_functions", lambda: {"boom": boom})
    await DbQueue().enqueue("boom", 1)
    assert await run_due_tasks() == 1
    async with sessionmaker() as s:
        item = (await s.execute(select(TaskQueueItem))).scalar_one()
        assert item.status == "failed" and "нет сети" in item.last_error
        item.status = "running"   # имитация аварийной остановки во время задачи
        await s.commit()
    assert await recover_running() == 1


async def test_fsm_db_storage(sessionmaker):
    storage = DbStorage()
    key = StorageKey(bot_id=1, chat_id=555, user_id=555)
    assert await storage.get_state(key) is None and await storage.get_data(key) == {}
    await storage.set_state(key, Form.phone)
    await storage.update_data(key, {"phone": "+998901112233"})
    fresh = DbStorage()   # «перезапуск бота»: состояние сохраняется в базе
    assert await fresh.get_state(key) == "Form:phone"
    assert await fresh.get_data(key) == {"phone": "+998901112233"}
    await fresh.set_state(key, None)
    assert await fresh.get_state(key) is None


def test_schedule_due_matches_section_11():
    tz = display_tz()
    assert "close_period" in due(datetime(2026, 9, 1, 2, 0, tzinfo=tz))
    assert "open_period" in due(datetime(2026, 9, 1, 1, 0, tzinfo=tz))
    assert "close_period" not in due(datetime(2026, 9, 2, 2, 0, tzinfo=tz))
    at_1030 = due(datetime(2026, 9, 5, 10, 30, tzinfo=tz))
    assert {"sync_orders", "reconcile_withdrawals", "health_check"} <= set(at_1030)
    assert "progress_notifications" in due(datetime(2026, 9, 5, 10, 0, tzinfo=tz))
    assert "sync_park_driver_profiles" in due(datetime(2026, 9, 5, 18, 15, tzinfo=tz))
    assert "sync_park_driver_profiles" not in due(datetime(2026, 9, 5, 17, 15, tzinfo=tz))
    assert "retry_failed_withdrawals" in due(datetime(2026, 9, 5, 10, 37, tzinfo=tz))


async def test_health_in_db_mode(ctx, monkeypatch):
    from src.config import get_config
    from src.health import collect_health
    monkeypatch.setattr(get_config(), "queue_backend", "db")
    h = await collect_health(ctx)
    assert h["db"] and h["queue"] and "redis" not in h


async def test_wizard_local_mode_env(tmp_path, monkeypatch):
    from httpx import ASGITransport, AsyncClient

    from src.setup_wizard import app as wizard
    from src.setup_wizard.envfile import read_env
    monkeypatch.setattr(wizard, "ENV_PATH", tmp_path / ".env")
    monkeypatch.setattr(wizard, "CONFIG_DIR", tmp_path / "config")
    monkeypatch.setattr(wizard, "LOCAL_MODE", True)
    (tmp_path / ".env").write_text("POSTGRES_PASSWORD=keep-me\n", encoding="utf-8")  # база уже создана
    async with AsyncClient(transport=ASGITransport(app=wizard.app), base_url="http://w") as c:
        assert (await c.get("/api/current")).json()["local"] is True
        r = (await c.post("/api/save", json={"bot_token": "1:a", "admin_ids": [5], "mode": "webhook",
                                             "domain": "x.uz", "fleet_provider": "manual"})).json()
    assert r["ok"] and r["mode"] == "polling"   # без Docker — только этот компьютер
    env = read_env(tmp_path / ".env")
    assert env["DATABASE_URL"] == "postgresql+asyncpg://referral:keep-me@127.0.0.1:54329/referral"
    assert env["QUEUE_BACKEND"] == "db" and env["REDIS_URL"] == "" and env["BACKUP_DIR"] == "backups"
