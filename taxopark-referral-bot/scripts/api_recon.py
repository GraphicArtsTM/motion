"""Шаг 0 — разведка Fleet API на реальном парке (БЛОКИРУЮЩИЙ).

Вызывает 7 критичных методов и сохраняет обезличенные ответы в docs/api_recon/*.json, а сводку
«есть / нет» — в консоль. По результатам заполняется API_SCHEMA.md.

    FLEET_CLIENT_ID=... FLEET_API_KEY=... FLEET_PARK_ID=... python -m scripts.api_recon [--tx-test]

--tx-test создаёт тестовую транзакцию на 1 сум (нужен FLEET_TEST_DRIVER_ID и согласие парка).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import httpx

from src.config import get_config
from src.integrations.fleet.api import ENDPOINTS

OUT = Path("docs/api_recon")
PII = re.compile(r"(\+?\d{9,15})|([A-Z]{2}\d{7})")


def scrub(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: scrub(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [scrub(v) for v in obj[:3]]
    if isinstance(obj, str):
        return PII.sub("***", obj)
    return obj


async def call(client: httpx.AsyncClient, op: str, **kw: Any) -> dict[str, Any]:
    method, path = ENDPOINTS[op]
    r = await client.request(method, path, **kw)
    data: dict[str, Any] = {"status": r.status_code}
    try:
        data["body"] = r.json()
    except ValueError:
        data["body"] = r.text[:2000]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{op}.json").write_text(json.dumps(scrub(data), ensure_ascii=False, indent=2), encoding="utf-8")
    return data


def has_path(obj: Any, *keys: str) -> bool:
    for k in keys:
        if not isinstance(obj, dict) or k not in obj:
            return False
        obj = obj[k]
    return obj not in (None, "", [])


async def main(tx_test: bool) -> None:
    cfg = get_config()
    park = cfg.fleet_park_id
    headers = {"X-Client-ID": cfg.fleet_client_id, "X-API-Key": cfg.fleet_api_key, "X-Park-ID": park,
               "Accept-Language": "ru"}
    now = datetime.now(UTC)
    async with httpx.AsyncClient(base_url=cfg.fleet_api_base_url, headers=headers, timeout=30) as c:
        drivers = await call(c, "list_drivers", json={"query": {"park": {"id": park}}, "limit": 5, "offset": 0})
        profiles = drivers["body"].get("driver_profiles", []) if isinstance(drivers["body"], dict) else []
        first = profiles[0] if profiles else {}
        pid = (first.get("driver_profile") or {}).get("id")
        report = {"1. Номер ВУ в списке профилей": has_path(first, "driver_profile", "driver_license", "number"),
                  "1. created_date в профиле": has_path(first, "driver_profile", "created_date")}
        if pid:
            one = await call(c, "get_driver", params={"contractor_profile_id": pid})
            report["2. Номер ВУ в профиле исполнителя"] = "driver_license" in json.dumps(one["body"])
        orders = await call(c, "list_orders", json={"query": {"park": {"id": park, "order": {"ended_at": {
            "from": (now - timedelta(days=3)).isoformat(), "to": now.isoformat()}}}}, "limit": 50})
        olist = orders["body"].get("orders", []) if isinstance(orders["body"], dict) else []
        report["3. Тариф/категория в заказе"] = any(o.get("category") for o in olist)
        report["3. Поле price в заказе"] = any("price" in o for o in olist)
        report["3. Грузовые заказы в общей выгрузке"] = any(o.get("category") == "cargo" for o in olist)
        cats = await call(c, "list_transaction_categories", json={"query": {"park": {"id": park}}})
        report["4. Категории транзакций"] = bool((cats["body"] or {}).get("categories"))
        if pid:
            txs = await call(c, "list_driver_transactions", json={"query": {"park": {
                "id": park, "driver_profile": {"id": pid},
                "transaction": {"event_at": {"from": (now - timedelta(days=30)).isoformat(), "to": now.isoformat()}}}},
                "limit": 20})
            tlist = (txs["body"] or {}).get("transactions", []) if isinstance(txs["body"], dict) else []
            report["7. description в списке транзакций"] = any("description" in t for t in tlist)
        if tx_test and os.environ.get("FLEET_TEST_DRIVER_ID"):
            token = str(uuid.uuid4())
            body = {"park_id": park, "contractor_profile_id": os.environ["FLEET_TEST_DRIVER_ID"], "amount": "1",
                    "category_id": os.environ.get("FLEET_TEST_CATEGORY_ID", ""), "description": "REFBOT-RECON"}
            first_tx = await call(c, "create_driver_transaction", json=body, headers={"X-Idempotency-Token": token})
            second_tx = await call(c, "create_driver_transaction", json=body, headers={"X-Idempotency-Token": token})
            report["5. Создание транзакции"] = first_tx["status"] == 200
            report["5. X-Idempotency-Token (повтор не дублирует)"] = first_tx["body"] == second_tx["body"]
            tx_id = (first_tx["body"] or {}).get("id") if isinstance(first_tx["body"], dict) else None
            if tx_id:
                st = await call(c, "get_transaction_status", params={"transaction_id": tx_id})
                report["6. Статус транзакции по id"] = st["status"] == 200
    for k, v in report.items():
        print(f"{'ЕСТЬ' if v else 'НЕТ '}  {k}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--tx-test", action="store_true")
    asyncio.run(main(p.parse_args().tx_test))
