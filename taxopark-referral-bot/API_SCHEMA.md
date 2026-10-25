# API_SCHEMA — Яндекс Fleet API

> ⚠️ **Статус: НЕ ПОДТВЕРЖДЕНО.** Шаг 0 («Разведка API», блокирующий) требует ключей реального парка, которых у
> разработки не было. Ниже — то, что заложено в код по публичной документации
> `https://fleet.taxi.yandex.ru/docs/api/`. Перед запуском:
>
> ```bash
> FLEET_CLIENT_ID=… FLEET_API_KEY=… FLEET_PARK_ID=… python -m scripts.api_recon            # чтение
> FLEET_TEST_DRIVER_ID=… FLEET_TEST_CATEGORY_ID=… python -m scripts.api_recon --tx-test     # + транзакция 1 сум
> ```
>
> Скрипт сохранит обезличенные ответы в `docs/api_recon/*.json` и напечатает сводку «ЕСТЬ / НЕТ». Заполните
> таблицу ниже, а при расхождениях поправьте `ENDPOINTS` и `_map_*` в `src/integrations/fleet/api.py`
> (это единственное место, где зашиты пути и имена полей). После фиксации поле `price` не меняется без
> пересчёта истории (E9).

## Сводка Шага 0

| # | Что проверить | Заложено в коде | Факт |
|---|---|---|---|
| 1 | Номер ВУ в **списке профилей** | `driver_profile.driver_license.normalized_number` или `.number` | ☐ есть / ☐ нет |
| 2 | Номер ВУ в **профиле исполнителя** (не deprecated) | `person.driver_license.number` | ☐ есть / ☐ нет |
| 3 | **Тариф заказа** | `category` (например `econom`, `cargo`) | ☐ есть / ☐ нет |
| 3 | Какое поле считать **`price`** (E9) | `price` — стоимость заказа для пассажира, строка `"23400.0000"` | ☐ подтверждено |
| 3 | Дистанция / длительность | `mileage` (м) / `ended_at − transporting_at` (с) | ☐ подтверждено |
| 3 | **Грузовые заказы** в том же `park_id` и методе | ожидается да | ☐ да / ☐ нет |
| 4 | Категории транзакций | `categories[].id`, `.name` | ☐ подтверждено |
| 5 | Создание транзакции поддерживает **`X-Idempotency-Token`** | да, повтор возвращает ту же транзакцию | ☐ да / ☐ нет |
| 5 | Знак суммы | положительная — зачисление водителю | ☐ подтверждено |
| 6 | **Статус транзакции** — по какому идентификатору | `transaction_id` из ответа создания | ☐ подтверждено |
| 7 | `description` в списке транзакций по исполнителю | да (сверка по метке `REFBOT-W{id}`) | ☐ есть / ☐ нет |

> **Если метод заказов не отдаёт тариф и категория авто не отражает грузовой тариф** — балльная система не
> отличит грузовой заказ от легкового. Это нужно эскалировать заказчику до запуска (9.4).

## Методы

Все запросы: заголовки `X-Client-ID`, `X-API-Key`, `X-Park-ID`, `Accept-Language: ru`; мутирующие —
`X-Idempotency-Token`. Таймауты: connect 5 с, read 30 с. Circuit breaker: 5 ошибок подряд → пауза 5 минут.
Чтение повторяется (tenacity, 3 попытки); создание транзакции — никогда без сверки.

| Операция `FleetProvider` | Метод Fleet | HTTP | Путь |
|---|---|---|---|
| `list_drivers` | Получение списка профилей исполнителей | POST | `/v1/parks/driver-profiles/list` |
| `get_driver` | Получение профиля исполнителя | GET | `/v2/parks/contractors/driver-profile?contractor_profile_id=` |
| `list_orders` | Получение списка заказов | POST | `/v1/parks/orders/list` (курсор) |
| `list_cars` / `get_car` | Список автомобилей / автомобиль | POST / GET | `/v1/parks/cars/list`, `/v2/parks/vehicles/car` |
| `list_transaction_categories` | Список категорий транзакций | POST | `/v2/parks/transactions/categories/list` |
| `create_driver_transaction` | Создание транзакции на балансе исполнителя (**не** `[Устаревший]`, R13) | POST | `/v3/parks/driver-profiles/transactions` |
| `get_transaction_status` | Статус транзакции | GET | `/v3/parks/driver-profiles/transactions/status` |
| `list_driver_transactions` | Список транзакций по исполнителю | POST | `/v2/parks/driver-profiles/transactions/list` |
| `get_driver_online_time` | Время исполнителя на линии | GET | `/v2/parks/contractors/supply-hours` |
| `list_work_rules` | Условия работы | GET | `/v1/parks/driver-work-rules` |
| `get_driver_blocked_balance` | Заблокированный баланс | GET | `/v2/parks/contractors/blocked-balance` |

## Классы ошибок (9.6 п.3)

| Класс | Когда | Поведение вывода (A11) |
|---|---|---|
| `NonRetryableFleetError` | 400, 401, 403, 404, 409, 422 | сразу `failed`, деньги возвращаются |
| `RetryableFleetError` | 429, 5xx с ответом; ошибка соединения до отправки; разомкнут circuit breaker | `pending` + ретраи 1м/5м/15м/1ч/6ч |
| `UnknownOutcomeError` | таймаут чтения, обрыв после отправки, ответ без id | `verifying` → сверка, повтор только если транзакции нет |

## Пример ожидаемых ответов (для тестов маппинга)

```json
// /v1/parks/orders/list → orders[]
{"id": "a1b2", "status": "complete", "category": "cargo", "price": "45000.0000", "mileage": "12300",
 "driver_profile": {"id": "d1"}, "booked_at": "2026-08-10T10:00:00+0000",
 "transporting_at": "2026-08-10T10:05:00+0000", "ended_at": "2026-08-10T10:40:00+0000",
 "address_from": {"address": "Ташкент, ул. А"}, "route_points": [{"address": "Ташкент, ул. Б"}]}
```
