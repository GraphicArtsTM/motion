"""Проверки мастера настройки: токен Telegram, поиск ID, доступы ключа Яндекс Fleet API.

Проверка Fleet ничего не меняет в парке: методы чтения вызываются с limit=1, а методы с параметром —
с несуществующим ID. Ответ 400/404 на такой запрос означает «доступ к методу есть, объект не найден»,
401 — неверный ключ или Client ID, 403 — у ключа нет доступа к этому методу.
"""

from __future__ import annotations

import uuid
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx

from src.integrations.fleet.api import ENDPOINTS

TELEGRAM_API = "https://api.telegram.org"
DUMMY_ID = "00000000000000000000000000000000"
TIMEOUT = httpx.Timeout(20.0, connect=8.0)


# ── Telegram ─────────────────────────────────────────────────────────────────
async def telegram_check(token: str, transport: httpx.AsyncBaseTransport | None = None) -> dict[str, Any]:
    token = token.strip()
    if ":" not in token:
        return {"ok": False, "error": "Токен выглядит неверно: он должен быть вида 123456789:AA…"}
    async with httpx.AsyncClient(timeout=TIMEOUT, transport=transport) as c:
        try:
            r = await c.get(f"{TELEGRAM_API}/bot{token}/getMe")
        except httpx.HTTPError as e:
            return {"ok": False, "error": f"Нет связи с Telegram: {type(e).__name__}"}
    data = r.json() if r.content else {}
    if not data.get("ok"):
        return {"ok": False, "error": "Telegram не принял токен. Скопируйте его из @BotFather ещё раз."}
    me = data["result"]
    return {"ok": True, "username": me.get("username"), "name": me.get("first_name"), "id": me.get("id")}


async def telegram_chats(token: str, transport: httpx.AsyncBaseTransport | None = None) -> dict[str, Any]:
    """Кто недавно писал боту: личные чаты (кандидаты в админы) и группы (кандидат в админ-чат)."""
    async with httpx.AsyncClient(timeout=TIMEOUT, transport=transport) as c:
        r = await c.get(f"{TELEGRAM_API}/bot{token.strip()}/getUpdates", params={"limit": 100})
    data = r.json() if r.content else {}
    if not data.get("ok"):
        desc = str(data.get("description", ""))
        if "webhook" in desc.lower():
            return {"ok": False, "error": "У бота включён webhook (бот уже работает на сервере). "
                                          "Остановите его или введите ID вручную."}
        return {"ok": False, "error": desc or "Telegram вернул ошибку"}
    people: dict[int, dict[str, Any]] = {}
    groups: dict[int, dict[str, Any]] = {}
    for upd in data.get("result", []):
        for key in ("message", "edited_message", "channel_post", "my_chat_member", "callback_query"):
            obj = upd.get(key)
            if not obj:
                continue
            chat = obj.get("chat") or (obj.get("message") or {}).get("chat")
            sender = obj.get("from")
            if chat and chat.get("type") in ("group", "supergroup"):
                groups[chat["id"]] = {"id": chat["id"], "title": chat.get("title", "")}
            if sender and not sender.get("is_bot"):
                name = " ".join(x for x in (sender.get("first_name"), sender.get("last_name")) if x)
                prev = people.get(sender["id"], {})
                people[sender["id"]] = {"id": sender["id"], "name": name or prev.get("name", ""),
                                        "username": sender.get("username") or prev.get("username")}
    return {"ok": True, "people": list(people.values()), "groups": list(groups.values())}


# ── Яндекс Fleet ─────────────────────────────────────────────────────────────
@dataclass
class MethodCheck:
    op: str
    title: str
    access: str          # read | write
    required: bool
    why: str
    status: str = "skip"  # ok | no_access | bad_key | error | skip
    http: int | None = None
    note: str = ""

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


METHODS: list[MethodCheck] = [
    MethodCheck("list_drivers", "Получение списка профилей исполнителей", "read", True,
                "автопроверка друга по базе парка, привязка профиля"),
    MethodCheck("get_driver", "Получение профиля исполнителя", "read", True,
                "добор номера ВУ, если его нет в списке профилей"),
    MethodCheck("list_orders", "Получение списка заказов", "read", True, "баллы друзей за заказы"),
    MethodCheck("list_transaction_categories", "Получение списка категорий транзакций", "read", True,
                "выбор категории, под которой проходят выплаты"),
    MethodCheck("create_driver_transaction", "Создание транзакции на балансе исполнителя", "write", True,
                "автоматический вывод денег на баланс Яндекс Про (без него — только ручные выплаты)"),
    MethodCheck("get_transaction_status", "Получение информации о статусе транзакции", "read", True,
                "сверка выплаты при обрыве связи — защита от двойной выплаты"),
    MethodCheck("list_driver_transactions", "Получение списка транзакций по исполнителю", "read", True,
                "резервная сверка выплаты по метке REFBOT-W…"),
    MethodCheck("list_cars", "Получение списка автомобилей", "read", False,
                "тариф по категории авто, если его нет в заказе"),
    MethodCheck("get_car", "Получение автомобиля", "read", False, "то же, по одному авто"),
    MethodCheck("get_driver_online_time", "Получение времени исполнителя на линии", "read", False,
                "антифрод: баллы без времени на линии"),
    MethodCheck("list_work_rules", "Получение списка условий работы", "read", False,
                "сегментация рассылок (аренда / свой авто)"),
    MethodCheck("get_driver_blocked_balance", "Получение заблокированного баланса водителя", "read", False,
                "карточка водителя в админке"),
]


@dataclass
class FleetReport:
    ok: bool = False
    key_valid: bool | None = None
    checks: list[dict[str, Any]] = field(default_factory=list)
    categories: list[dict[str, Any]] = field(default_factory=list)
    facts: dict[str, Any] = field(default_factory=dict)
    error: str = ""


def classify(status: int | None, probe: bool) -> tuple[str, str]:
    if status is None:
        return "error", "нет ответа"
    if status // 100 == 2:  # 2xx
        return "ok", "доступ есть"
    if status == 401:
        return "bad_key", "неверный ключ API или Client ID"
    if status == 403:
        return "no_access", "у ключа нет доступа к этому методу"
    if probe and status in (400, 404, 409, 422):
        return "ok", "доступ есть (пробный запрос с несуществующим ID)"
    if status == 429:
        return "error", "слишком много запросов, повторите через минуту"
    return "error", f"ответ {status}"


async def fleet_check(base_url: str, client_id: str, api_key: str, park_id: str,
                      transport: httpx.AsyncBaseTransport | None = None) -> dict[str, Any]:
    report = FleetReport()
    if not (client_id and api_key and park_id):
        report.error = "Заполните Client ID, API-ключ и ID парка"
        return asdict(report)
    headers = {"X-Client-ID": client_id.strip(), "X-API-Key": api_key.strip(), "X-Park-ID": park_id.strip(),
               "Accept-Language": "ru"}
    park = {"id": park_id.strip()}
    now = datetime.now(UTC)
    driver_id, car_id = DUMMY_ID, DUMMY_ID
    async with httpx.AsyncClient(base_url=base_url, headers=headers, timeout=TIMEOUT, transport=transport) as c:

        async def call(op: str, **kw: Any) -> tuple[int | None, Any]:
            method, path = ENDPOINTS[op]
            try:
                r = await c.request(method, path, **kw)
            except httpx.HTTPError:
                return None, None
            try:
                return r.status_code, r.json()
            except ValueError:
                return r.status_code, None

        results: dict[str, tuple[int | None, Any]] = {}

        results["list_drivers"] = await call("list_drivers", json={"query": {"park": park}, "limit": 1, "offset": 0})
        body = results["list_drivers"][1]
        profiles = (body.get("driver_profiles") or []) if isinstance(body, dict) else []
        if profiles:
            dp = profiles[0].get("driver_profile") or {}
            driver_id = dp.get("id") or DUMMY_ID
            car_id = (profiles[0].get("car") or {}).get("id") or DUMMY_ID
            report.facts["Номер ВУ в списке профилей"] = bool((dp.get("driver_license") or {}).get("number"))
            report.facts["Водителей в парке (по API)"] = body.get("total") if isinstance(body, dict) else None

        requests: dict[str, dict[str, Any]] = {
            "get_driver": {"params": {"contractor_profile_id": driver_id}},
            "list_orders": {"json": {"query": {"park": {**park, "order": {"ended_at": {
                "from": (now - timedelta(days=2)).isoformat(), "to": now.isoformat()}}}}, "limit": 20}},
            "list_transaction_categories": {"json": {"query": {"park": park}}},
            # заведомо невалидная транзакция: сумма 0 несуществующему водителю — денег не двигает
            "create_driver_transaction": {"json": {"park_id": park["id"], "contractor_profile_id": DUMMY_ID,
                                                   "amount": "0", "category_id": "", "description": "REFBOT-SETUP-CHECK"},
                                          "headers": {"X-Idempotency-Token": str(uuid.uuid4())}},
            "get_transaction_status": {"params": {"transaction_id": DUMMY_ID}},
            "list_driver_transactions": {"json": {"query": {"park": {**park, "driver_profile": {"id": driver_id},
                                                                     "transaction": {"event_at": {
                                                                         "from": (now - timedelta(days=1)).isoformat(),
                                                                         "to": now.isoformat()}}}}, "limit": 1}},
            "list_cars": {"json": {"query": {"park": park}, "limit": 1, "offset": 0}},
            "get_car": {"params": {"vehicle_id": car_id}},
            "get_driver_online_time": {"params": {"contractor_profile_id": driver_id,
                                                  "period_from": (now - timedelta(days=1)).isoformat(),
                                                  "period_to": now.isoformat()}},
            "list_work_rules": {"params": {"park_id": park["id"]}},
            "get_driver_blocked_balance": {"params": {"contractor_id": driver_id}},
        }
        for op, kw in requests.items():
            results[op] = await call(op, **kw)

    probes = {"get_driver", "create_driver_transaction", "get_transaction_status", "list_driver_transactions",
              "get_car", "get_driver_online_time", "get_driver_blocked_balance"}
    for m in METHODS:
        status, _ = results.get(m.op, (None, None))
        st, note = classify(status, m.op in probes)
        check = MethodCheck(**{**asdict(m), "status": st, "http": status, "note": note})
        report.checks.append(check.as_dict())

    statuses = {c["op"]: c["status"] for c in report.checks}
    report.key_valid = not any(s == "bad_key" for s in statuses.values())
    orders = (results["list_orders"][1] or {}).get("orders") if isinstance(results["list_orders"][1], dict) else None
    if orders is not None:
        report.facts["Заказов за 2 дня (до 20)"] = len(orders)
        if orders:
            report.facts["Тариф (category) в заказах"] = any(o.get("category") for o in orders)
            report.facts["Поле price в заказах"] = any("price" in o for o in orders)
    cats = results["list_transaction_categories"][1]
    if isinstance(cats, dict):
        report.categories = [{"id": str(x.get("id")), "name": x.get("name", "")} for x in cats.get("categories", [])
                             if x.get("is_enabled", True)]
    required_ok = all(c["status"] == "ok" for c in report.checks if c["required"]
                      and c["op"] != "create_driver_transaction")
    report.ok = bool(report.key_valid and required_ok)
    if not report.key_valid:
        report.error = "Ключ не принят: проверьте Client ID и API-ключ (и что ключ выдан для этого парка)."
    elif not required_ok:
        report.error = "У ключа не хватает обязательных доступов — отметьте их в кабинете парка (см. таблицу)."
    return asdict(report)
