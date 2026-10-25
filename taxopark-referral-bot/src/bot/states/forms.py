from aiogram.fsm.state import State, StatesGroup


class Registration(StatesGroup):
    code = State()
    phone = State()
    name = State()
    license = State()
    photo_front = State()
    photo_back = State()


class WalletForm(StatesGroup):
    amount = State()
    dispute = State()


class SupportForm(StatesGroup):
    message = State()


class AdminForm(StatesGroup):
    reject_reason = State()
    paid_proof = State()
    broadcast = State()
