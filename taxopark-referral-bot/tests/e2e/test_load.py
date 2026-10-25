"""TC-110: 200 одновременных пользователей → p95 ответа бота ≤ 1,5 с.

Запуск: RUN_LOAD=1 pytest tests/e2e/test_load.py -s
Telegram API подменён (FakeSession), поэтому измеряется время обработки апдейта ботом: middleware,
access gate, ядро, запросы к PostgreSQL.
"""

from __future__ import annotations

import asyncio
import os
import random
import statistics
import time

import pytest
from aiogram import Bot
from aiogram.fsm.storage.memory import MemoryStorage

from src.bot.i18n import get_translator
from src.bot.main import build_dispatcher
from src.core.context import RecordingQueue
from src.runtime import set_clock, set_fleet, set_queue
from tests.e2e.telegram import FakeSession, TgUserSim
from tests.factories import add_orders, counted_referral, create_user

pytestmark = pytest.mark.skipif(not os.environ.get("RUN_LOAD"), reason="нагрузочный тест: RUN_LOAD=1")
USERS = 200
P95_LIMIT = 1.5
ACTIONS = 3
THINK_MIN, THINK_MAX = 1.0, 3.0  # сек между действиями пользователя


async def test_200_concurrent_users_p95(sessionmaker, ctx, fleet, clock):
    set_queue(RecordingQueue())
    set_fleet(fleet)
    set_clock(clock)
    tr = get_translator()
    referrer = await create_user(ctx, name="Нагрузочный Реферер")
    for _ in range(USERS // 4):
        _, _, _, pid = await counted_referral(ctx, referrer)
        await add_orders(ctx, pid, 30, "econom")
    drivers = [await create_user(ctx, language="ru") for _ in range(USERS)]
    await ctx.session.commit()
    from src.core.settings import service as settings_service
    settings_service.configure_cache(15)  # как в продакшене: кеш настроек
    # как в продакшене: пул соединений (pool_size + overflow), а не соединение на апдейт
    from src.db.session import make_engine, make_sessionmaker, set_sessionmaker
    engine = make_engine(pool_size=20, max_overflow=10)
    set_sessionmaker(make_sessionmaker(engine))
    bot = Bot("42:TEST", session=FakeSession())
    dp = build_dispatcher(MemoryStorage())
    screens = ["btn.menu-wallet", "btn.menu-progress", "btn.menu-terms", "btn.menu-rating"]
    latencies: list[float] = []
    burst: list[float] = []
    rnd = random.Random(42)

    async def session_of(i: int) -> None:
        """Пользователь в сессии: несколько экранов подряд с «временем на чтение»."""
        sim = TgUserSim(dp, bot, drivers[i].telegram_id)
        await asyncio.sleep(rnd.uniform(0, THINK_MAX))
        for step in range(ACTIONS):
            start = time.perf_counter()
            await sim.send(tr.t("ru", screens[(i + step) % len(screens)]))
            latencies.append(time.perf_counter() - start)
            await asyncio.sleep(rnd.uniform(THINK_MIN, THINK_MAX))

    async def burst_one(i: int) -> None:
        sim = TgUserSim(dp, bot, drivers[i].telegram_id)
        start = time.perf_counter()
        await sim.send(tr.t("ru", screens[i % len(screens)]))
        burst.append(time.perf_counter() - start)

    started = time.perf_counter()
    await asyncio.gather(*(session_of(i) for i in range(USERS)))
    total = time.perf_counter() - started
    await asyncio.gather(*(burst_one(i) for i in range(USERS)))  # стресс: все 200 апдейтов в одну миллисекунду
    rsim = TgUserSim(dp, bot, referrer.telegram_id)
    start = time.perf_counter()
    await rsim.send(tr.t("ru", "btn.menu-friends", count=0))
    friends_latency = time.perf_counter() - start
    p95 = statistics.quantiles(latencies, n=100)[94]
    burst_p95 = statistics.quantiles(burst, n=100)[94]
    print(f"\nusers={USERS} updates={len(latencies)} total={total:.2f}s p50={statistics.median(latencies):.3f}s "
          f"p95={p95:.3f}s max={max(latencies):.3f}s friends_screen={friends_latency:.3f}s "
          f"| burst200: p95={burst_p95:.3f}s max={max(burst):.3f}s (один процесс)")
    settings_service.configure_cache(0)
    await engine.dispose()
    set_sessionmaker(sessionmaker)
    assert p95 <= P95_LIMIT
    set_fleet(None)
    set_clock(None)
