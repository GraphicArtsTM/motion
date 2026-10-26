"""python -m src.local — всё в одном процессе, для запуска без Docker.

1. Миграции Alembic и применение настроек мастера (config/initial_settings.json).
2. Веб-панель и /health на 127.0.0.1:8000.
3. Бот (polling) + доставка уведомлений.
4. Очередь задач и расписание Раздела 11 — в PostgreSQL (Redis не нужен).
"""

from __future__ import annotations

import asyncio
import os
from pathlib import Path
from typing import Any

import structlog

ROOT = Path(__file__).resolve().parents[2]
log = structlog.get_logger()


def migrate() -> None:
    from alembic.config import Config

    from alembic import command
    from src.config import get_config

    cfg = Config(str(ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(ROOT / "alembic"))
    cfg.set_main_option("sqlalchemy.url", get_config().sync_database_url)
    command.upgrade(cfg, "head")


async def run_web(stop: asyncio.Event) -> None:
    import uvicorn

    from src.web import app
    port = int(os.environ.get("WEB_PORT", "8000"))
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, log_level="warning"))
    server.install_signal_handlers = lambda: None  # type: ignore[method-assign]
    serve = asyncio.create_task(server.serve())
    waiter = asyncio.create_task(stop.wait())
    await asyncio.wait({serve, waiter}, return_when=asyncio.FIRST_COMPLETED)
    if serve.done() and not stop.is_set():
        raise RuntimeError(f"веб-сервер остановился — порт {port} занят другой программой?")
    server.should_exit = True
    await serve


async def run_bot(stop: asyncio.Event) -> None:
    from src.bot.dispatcher import run_dispatcher
    from src.bot.main import build_dispatcher, make_bot
    from src.config import get_config

    if not get_config().bot_token:
        log.warning("bot_token_missing", hint="запустите setup.bat")
        await stop.wait()
        return
    bot, dp = make_bot(), build_dispatcher()
    sender = asyncio.create_task(run_dispatcher(bot, stop))
    await bot.delete_webhook(drop_pending_updates=False)
    polling = asyncio.create_task(dp.start_polling(bot, handle_signals=False))
    await stop.wait()
    await dp.stop_polling()
    await asyncio.gather(polling, sender, return_exceptions=True)
    await bot.session.close()


RESTART_DELAY_SECONDS = 15
ERROR_SNIPPET = 400


async def supervise(name: str, component: Any, stop: asyncio.Event) -> None:
    """Компонент перезапускается после сбоя (нет интернета, Telegram недоступен), процесс не падает."""
    while not stop.is_set():
        try:
            await component(stop)
            return
        except Exception as e:  # noqa: BLE001
            log.error("local_component_failed", component=name, error=repr(e)[:ERROR_SNIPPET],
                      restart_in=RESTART_DELAY_SECONDS)
            try:
                await asyncio.wait_for(stop.wait(), timeout=RESTART_DELAY_SECONDS)
            except TimeoutError:
                pass


async def main() -> None:
    from src import bootstrap
    from src.logging_setup import setup_logging
    from src.workers.dbqueue import run_scheduler, run_task_loop

    setup_logging()
    os.chdir(ROOT)
    await asyncio.to_thread(migrate)
    await bootstrap.main()
    stop = asyncio.Event()
    log.info("local_started", url=f"http://127.0.0.1:{os.environ.get('WEB_PORT', '8000')}/")
    components = {"web": run_web, "bot": run_bot, "tasks": run_task_loop, "scheduler": run_scheduler}
    await asyncio.gather(*(supervise(name, fn, stop) for name, fn in components.items()))


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
