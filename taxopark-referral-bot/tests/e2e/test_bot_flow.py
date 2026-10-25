"""E2E: бот целиком (aiogram + middleware + ядро + БД) на фейковом Telegram API."""

from __future__ import annotations

import pytest
from aiogram import Bot
from aiogram.fsm.storage.memory import MemoryStorage
from sqlalchemy import select

from src.bot.dispatcher import deliver_batch
from src.bot.i18n import get_translator
from src.bot.main import build_dispatcher
from src.core.context import RecordingQueue
from src.db.models import ApprovalRequest, NotificationOutbox, Referral, User
from src.runtime import set_clock, set_fleet, set_queue
from tests.e2e.telegram import FakeSession, TgUserSim
from tests.factories import add_orders, counted_referral, create_user, with_profile

tr = get_translator()


@pytest.fixture(scope="module")
def dispatcher():
    return build_dispatcher(MemoryStorage())  # роутеры — синглтоны модулей, собираем один раз


@pytest.fixture
def bot_env(sessionmaker, fleet, dispatcher, clock):
    set_clock(clock)
    queue = RecordingQueue()
    set_queue(queue)
    set_fleet(fleet)
    session = FakeSession()
    bot = Bot("42:TEST", session=session)
    dp = dispatcher
    yield bot, dp, session, queue
    set_fleet(None)
    set_clock(None)


async def _user(sessionmaker, tg_id) -> User:
    async with sessionmaker() as s:
        return (await s.execute(select(User).where(User.telegram_id == tg_id))).scalar_one()


async def test_registration_moderation_wallet_flow(bot_env, sessionmaker, ctx):
    bot, dp, tg, queue = bot_env
    referrer = await create_user(ctx, name="Рефереров Рустам")
    await ctx.session.commit()

    friend = TgUserSim(dp, bot, 555001)
    await friend.send(f"/start r_{referrer.referral_code}_wa")
    assert tr.t("ru", "lang.choose") in tg.texts()[-1]
    await friend.click("lang:ru")
    assert "согласие" in tg.texts()[-1]
    await friend.click("consent:yes")
    assert "Принимаю" in tg.texts()[-1] or "УСЛОВИЯ" in tg.texts()[-1]
    await friend.click("terms:accept")
    assert tr.t("ru", "reg.request_phone") in tg.texts()
    await friend.send("+998901234567")  # ручной ввод запрещён
    assert tg.texts()[-1] == tr.t("ru", "reg.phone_manual_forbidden")
    await friend.contact("998901234567")
    await friend.send("Каримов Азиз Бахтиёрович")
    await friend.send("ab 123-4567")
    await friend.photo("front-id")
    await friend.photo("back-id")
    assert "ЗАЯВКА НА РАССМОТРЕНИИ" in "\n".join(tg.texts()[-3:])

    u = await _user(sessionmaker, 555001)
    assert u.access_status == "pending_approval" and u.driver_license == "AB1234567"
    async with sessionmaker() as s:
        ref = (await s.execute(select(Referral).where(Referral.referred_user_id == u.id))).scalar_one()
        assert ref.source_tag == "wa" and ref.status == "pending_approval"
        req = (await s.execute(select(ApprovalRequest))).scalar_one()

    # экран ожидания закрывает кошелёк (TC-12)
    tg.clear()
    await friend.send(tr.t("ru", "btn.menu-wallet"))
    assert "ЗАЯВКА НА РАССМОТРЕНИИ" in "\n".join(tg.texts())

    # модератор принимает с рефералкой из Telegram
    moder = await create_user(ctx, role="moderator")
    await ctx.session.commit()
    admin_sim = TgUserSim(dp, bot, moder.telegram_id)
    await admin_sim.click(f"ap:with:{req.id}")
    u = await _user(sessionmaker, 555001)
    assert u.access_status == "approved"

    # уведомления доставляются диспетчером outbox
    tg.clear()
    sent = await deliver_batch(bot)
    assert sent >= 2
    texts = "\n".join(tg.texts())
    assert "Вы подключены" in texts
    assert "успешно добавился" in texts

    # главное меню и кошелёк
    tg.clear()
    await friend.send("/menu")
    await friend.send(tr.t("ru", "btn.menu-wallet"))
    assert "МОЙ КОШЕЛЁК" in tg.texts()[-1]


async def test_withdraw_via_bot(bot_env, sessionmaker, ctx):
    bot, dp, tg, queue = bot_env
    from src.core.billing.accruals import create_accrual_if_not_exists
    u = await create_user(ctx, language="ru")
    await with_profile(ctx, u)
    await create_accrual_if_not_exists(ctx, user_id=u.id, idempotency_key="b1", type="manual", amount=420000,
                                       status="available")
    await ctx.session.commit()
    sim = TgUserSim(dp, bot, u.telegram_id)
    await sim.send(tr.t("ru", "btn.menu-wallet"))
    assert "420 000" in tg.texts()[-1]
    await sim.click("wal:ask")
    assert "Вывести 420 000 сум" in tg.texts()[-1]
    await sim.click("wal:go:420000")
    assert tg.texts()[-1] == tr.t("ru", "wallet.processing")
    assert queue.calls and queue.calls[0][0] == "process_withdrawal"
    await sim.click("wal:go:420000")  # двойное нажатие
    assert "обрабатывается" in tg.texts()[-1] or "Предыдущий вывод" in "\n".join(tg.texts()[-2:])


async def test_terms_gate_blocks_wallet(bot_env, sessionmaker, ctx):
    bot, dp, tg, _ = bot_env
    u = await create_user(ctx, accept_terms=False, language="ru")
    await ctx.session.commit()
    sim = TgUserSim(dp, bot, u.telegram_id)
    await sim.send(tr.t("ru", "btn.menu-wallet"))
    assert "УСЛОВИЯ ПРОГРАММЫ" in "\n".join(tg.texts())
    tg.clear()
    await sim.send(tr.t("ru", "btn.menu-support"))
    assert tg.texts()[-1] == tr.t("ru", "support.prompt")  # поддержка доступна (TC-04)


async def test_progress_and_friends_screens(bot_env, sessionmaker, ctx):
    bot, dp, tg, _ = bot_env
    referrer, friend, ref, pid = await counted_referral(ctx, friend_name="Каримов Азиз")
    await add_orders(ctx, pid, 87, "cargo")
    await ctx.session.commit()
    fsim = TgUserSim(dp, bot, friend.telegram_id)
    await fsim.send(tr.t("ru", "btn.menu-progress"))
    text = tg.texts()[-1]
    assert "87 из 100 заказов" in text and "Рустам" in text and "30 000" in text
    rsim = TgUserSim(dp, bot, referrer.telegram_id)
    await rsim.send(tr.t("ru", "btn.menu-friends", count=1))
    assert "87 из 100 заказов" in tg.texts()[-1]
    await rsim.click(f"remind:{ref.id}")
    async with sessionmaker() as s:
        keys = (await s.execute(select(NotificationOutbox.template_key))).scalars().all()
    assert "reminder.from_friend" in keys


async def test_milestones_menu_toggle(bot_env, sessionmaker, ctx):
    bot, dp, tg, _ = bot_env
    u = await create_user(ctx, language="ru")
    await ctx.session.commit()
    sim = TgUserSim(dp, bot, u.telegram_id)
    await sim.send("/menu")
    kb = tg.requests[-1].reply_markup
    assert tr.t("ru", "btn.menu-milestones") not in str(kb)  # TC-65
    await ctx.settings.set(ctx.session, "milestones_enabled", True, None)
    await ctx.session.commit()
    await sim.send("/menu")
    assert tr.t("ru", "btn.menu-milestones") in str(tg.requests[-1].reply_markup)  # TC-68
