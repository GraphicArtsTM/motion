"""/start, выбор языка, согласие, приём условий и шаги регистрации (3.2)."""

from __future__ import annotations

from typing import Any

from aiogram import F, Router
from aiogram.filters import CommandObject, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, KeyboardButton, Message, ReplyKeyboardMarkup

from src.bot.handlers.common import route_by_access_status, send, show_menu, show_screen
from src.bot.keyboards.menu import inline, remove
from src.bot.render import translator_for
from src.bot.states.forms import Registration
from src.core.errors import BusinessError
from src.core.onboarding.registration import finish_registration, save_contact
from src.core.onboarding.terms import accept_current_terms
from src.core.onboarding.validation import validate_full_name, validate_license
from src.core.referral.attribution import enter_code_manually, handle_start
from src.core.referral.queries import get_referral_for

router = Router(name="onboarding")


@router.message(CommandStart(), flags={"screen": "language"})
async def cmd_start(message: Message, command: CommandObject, state: FSMContext, **data: Any) -> None:
    ctx, user = data["ctx"], data["user"]
    await state.clear()
    try:
        res = await handle_start(ctx, user, command.args)  # A1
        if res.outcome == "created":
            await ctx.session.commit()
    except BusinessError as e:
        await message.answer(data["t"](e.key))
    await route_by_access_status(message, data)


@router.callback_query(F.data.startswith("lang:"), flags={"screen": "language"})
async def choose_language(cb: CallbackQuery, **data: Any) -> None:
    ctx, user = data["ctx"], data["user"]
    lang = cb.data.split(":", 1)[1]  # type: ignore[union-attr]
    user.language = lang
    await ctx.session.commit()
    t = translator_for(lang)
    data.update(lang=lang, t=t)
    if user.access_status != "onboarding":
        await send(cb, t("settings.saved"))
        await route_by_access_status(cb, data)
        return
    rows = [[(t("btn.consent_agree"), "consent:yes")], [(t("btn.consent_decline"), "consent:no")]]
    await send(cb, t("start.welcome") + "\n\n" + t("start.consent"), inline(rows))


@router.callback_query(F.data == "consent:no", flags={"screen": "registration"})
async def consent_no(cb: CallbackQuery, **data: Any) -> None:
    await send(cb, data["t"]("consent.declined"))


@router.callback_query(F.data == "consent:yes", flags={"screen": "registration"})
async def consent_yes(cb: CallbackQuery, **data: Any) -> None:
    ctx, user = data["ctx"], data["user"]
    user.consent_at = ctx.now()
    await ctx.session.commit()
    from src.bot.handlers.common import show_terms
    await show_terms(cb, data, force_accept=True)


@router.callback_query(F.data == "terms:accept", flags={"screen": "terms"})
async def terms_accept(cb: CallbackQuery, state: FSMContext, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    await accept_current_terms(ctx, user.id)
    await ctx.session.commit()
    await send(cb, t("terms.accepted"))
    if user.access_status != "onboarding":
        await route_by_access_status(cb, data)
        return
    rows = []
    if ctx.settings.bool("allow_manual_code_entry") and await get_referral_for(ctx, user.id) is None:
        rows.append([(t("btn.have_code"), "reg:code")])
    await state.set_state(Registration.phone)
    kb = ReplyKeyboardMarkup(keyboard=[[KeyboardButton(text=t("btn.send_phone"), request_contact=True)]],
                             resize_keyboard=True, one_time_keyboard=True)
    await send(cb, t("reg.request_phone"), kb)
    if rows:
        await send(cb, "🔑", inline(rows))


@router.callback_query(F.data == "reg:code", flags={"screen": "registration"})
async def ask_code(cb: CallbackQuery, state: FSMContext, **data: Any) -> None:
    await state.set_state(Registration.code)
    await send(cb, data["t"]("reg.enter_code"))


@router.message(Registration.code, F.text, flags={"screen": "registration"})
async def got_code(message: Message, state: FSMContext, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    await enter_code_manually(ctx, user, message.text or "")
    await ctx.session.commit()
    await state.set_state(Registration.phone)
    kb = ReplyKeyboardMarkup(keyboard=[[KeyboardButton(text=t("btn.send_phone"), request_contact=True)]],
                             resize_keyboard=True, one_time_keyboard=True)
    await message.answer(t("reg.code_applied") + "\n\n" + t("reg.request_phone"), reply_markup=kb)


@router.message(Registration.phone, F.contact, flags={"screen": "registration"})
async def got_phone(message: Message, state: FSMContext, **data: Any) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    contact = message.contact
    assert contact is not None
    if contact.user_id and message.from_user and contact.user_id != message.from_user.id:
        await message.answer(t("reg.phone_not_own"))
        return
    phone = await save_contact(ctx, user, contact.phone_number)
    await state.update_data(phone=phone)
    await state.set_state(Registration.name)
    await message.answer(t("reg.request_name"), reply_markup=remove())


@router.message(Registration.phone, flags={"screen": "registration"})
async def phone_manual(message: Message, **data: Any) -> None:
    await message.answer(data["t"]("reg.phone_manual_forbidden"))


@router.message(Registration.name, F.text, flags={"screen": "registration"})
async def got_name(message: Message, state: FSMContext, **data: Any) -> None:
    t = data["t"]
    name = validate_full_name(message.text)
    if name is None:
        await message.answer(t("err.invalid_name"))
        return
    await state.update_data(full_name=name)
    await state.set_state(Registration.license)
    await message.answer(t("reg.request_license"))


@router.message(Registration.license, F.text, flags={"screen": "registration"})
async def got_license(message: Message, state: FSMContext, **data: Any) -> None:
    ctx, t = data["ctx"], data["t"]
    check = validate_license(message.text, ctx.settings.str("driver_license_regex"))
    if not check.ok:
        await message.answer(t("err.invalid_license"))  # TC-07
        return
    await state.update_data(license=check.value)
    if ctx.settings.bool("require_license_photo"):
        await state.set_state(Registration.photo_front)
        await message.answer(t("reg.request_license_photo"))
    else:
        await _finish(message, state, data)


@router.message(Registration.photo_front, F.photo, flags={"screen": "registration"})
async def got_front(message: Message, state: FSMContext, **data: Any) -> None:
    await state.update_data(photo_front=message.photo[-1].file_id)  # type: ignore[index]
    await state.set_state(Registration.photo_back)
    await message.answer(data["t"]("reg.request_license_photo_back"))


@router.message(Registration.photo_back, F.photo, flags={"screen": "registration"})
async def got_back(message: Message, state: FSMContext, **data: Any) -> None:
    await state.update_data(photo_back=message.photo[-1].file_id)  # type: ignore[index]
    await _finish(message, state, data)


@router.message(Registration.photo_front, flags={"screen": "registration"})
@router.message(Registration.photo_back, flags={"screen": "registration"})
async def need_photo(message: Message, **data: Any) -> None:
    await message.answer(data["t"]("reg.need_photo"))


async def _finish(message: Message, state: FSMContext, data: dict[str, Any]) -> None:
    ctx, user, t = data["ctx"], data["user"], data["t"]
    form = await state.get_data()
    await message.answer(t("reg.checking"))
    res = await finish_registration(ctx, user, form["phone"], form["full_name"], form["license"],
                                    (form.get("photo_front"), form.get("photo_back")))  # A2
    await state.clear()
    if res.outcome == "duplicate":
        await message.answer(t("err.duplicate_identity"))
        return
    if res.outcome in ("already_in_park", "rehire"):
        await show_menu(message, data, t("onboarding.already_in_park"))
        return
    await show_screen(message, data, "pending")


@router.callback_query(F.data == "pending:refresh", flags={"screen": "pending"})
async def pending_refresh(cb: CallbackQuery, **data: Any) -> None:
    user = data["user"]
    if user.access_status == "pending_approval":
        await cb.answer(data["t"]("onboarding.still_pending"), show_alert=True)
        return
    await route_by_access_status(cb, data)
