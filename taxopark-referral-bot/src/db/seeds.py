"""Сиды справочников и настроек (Приложение 18.1, Раздел 10).

ЕДИНСТВЕННОЕ место в коде, где допустимы числовые бизнес-значения (R3).
Всё остальное читает эти значения из БД через SettingsService / справочники.
Используется миграцией `0002_seeds` и тестами.
"""

from __future__ import annotations

from typing import Any

# ─────────────────────────── Справочник тарифов (2.1) ───────────────────────────
# (code, name, coefficient_x100, sort_order)
TARIFFS: list[tuple[str, str, int, int]] = [
    ("econom", "Эконом", 100, 1),
    ("comfort", "Комфорт", 100, 2),
    ("comfort_plus", "Комфорт+", 150, 3),
    ("business", "Бизнес", 180, 4),
    ("delivery", "Доставка / курьер", 70, 5),
    ("cargo", "Грузовой", 300, 6),
]

# ─────────────────────────── Справочник бонусов (2.7) ───────────────────────────
# (recipient, min_percent, bonus_uzs, is_active)
BONUS_RULES: list[tuple[str, int, int, bool]] = [
    ("referrer", 100, 30000, True),
    ("referred", 100, 20000, False),  # welcome-бонус, выключен (N1)
]

# ─────────────────────────── Достижения (2.9) — заготовки ───────────────────────
# (code, name, required_count, reward_uzs, is_active, sort_order)
MILESTONES: list[tuple[str, str, int, int, bool, int]] = [
    ("friends_10", "10 друзей выполнили план", 10, 30000, False, 1),
    ("friends_20", "20 друзей выполнили план", 20, 60000, False, 2),
    ("friends_30", "30 друзей выполнили план", 30, 100000, False, 3),
    ("friends_40", "40 друзей выполнили план", 40, 150000, False, 4),
    ("friends_50", "50 друзей выполнили план", 50, 200000, False, 5),
]

# ─────────────────────────── Антифрод (Раздел 12) ───────────────────────────────
FRAUD_RULES: dict[str, dict[str, Any]] = {
    "SELF_REF": {"severity": "critical", "score": 100},
    "REHIRE": {"severity": "critical", "score": 100},
    "EXISTING_DRIVER": {"severity": "critical", "score": 100},
    "DUPLICATE_LICENSE": {"severity": "critical", "score": 100},
    "IMPOSSIBLE_HOURS": {"severity": "high", "score": 45},
    "SAME_CAR": {"severity": "high", "score": 40},
    "BURST_QUALIFY": {"severity": "high", "score": 35},
    "SHORT_RIDES": {"severity": "high", "score": 35},
    "SAME_ROUTE": {"severity": "high", "score": 35},
    "TARIFF_ANOMALY": {"severity": "high", "score": 35},
    "VELOCITY": {"severity": "medium", "score": 20},
    "LOW_GMV": {"severity": "medium", "score": 20},
    "PHONE_CLUSTER": {"severity": "medium", "score": 20},
    "NIGHT_PATTERN": {"severity": "low", "score": 10},
    "LICENSE_FORMAT": {"severity": "low", "score": 0},
}

PARK_CONTACTS_DEFAULT = (
    "<b>Таксопарк</b>\nТелефон: +998 __ ___ __ __\nАдрес: ...\nМенеджер: @...\n"
    "Часы работы: 09:00–18:00"
)

# ─────────────────────────── Настройки (Приложение 18.1) ────────────────────────
# (key, value, value_type, description)
SETTINGS: list[tuple[str, Any, str, str]] = [
    ("program_enabled", True, "bool", "Программа включена"),
    ("qualification_threshold_points_x100", 30000, "int", "Порог плана, баллы ×100"),
    ("default_tariff_coefficient_x100", 100, "int", "Коэффициент неизвестного тарифа ×100"),
    ("dominant_tariff_share_percent", 90, "int", "Доля тарифа для режима «заказы» (A16)"),
    ("coefficient_change_notice_days", 14, "int", "Уведомление об изменении коэффициентов, дней"),
    ("referred_bonus_enabled", False, "bool", "Welcome-бонус другу (N1)"),
    ("referred_bonus_max_periods", 1, "int", "За сколько первых планов платить welcome (0 — всегда)"),
    ("milestones_enabled", False, "bool", "Награды за достижения"),
    ("milestones_activation_mode", "from_now", "str", "from_now | retroactive"),
    ("milestones_activated_at", None, "datetime", "Момент включения наград"),
    ("eligible_order_statuses", ["complete"], "list", "Зачётные статусы заказа"),
    ("min_order_price", 5000, "int", "Минимальная стоимость заказа, сум"),
    ("min_order_distance_m", 1000, "int", "Минимальная дистанция, м"),
    ("min_order_duration_sec", 180, "int", "Минимальная длительность, сек"),
    ("attribution_window_click_days", 30, "int", "Окно клик → регистрация, дней"),
    ("attribution_window_approval_days", 45, "int", "Окно регистрация → подтверждение, дней"),
    ("rehire_block_days", 90, "int", "Блокировка повторного найма, дней"),
    ("allow_manual_code_entry", True, "bool", "Ручной ввод кода"),
    ("treat_post_click_profile_as_new", True, "bool", "Профиль после клика — новый"),
    ("require_license_photo", True, "bool", "Требовать фото ВУ"),
    ("driver_license_regex", r"^[A-Z]{2}\d{7}$", "str", "Формат номера ВУ"),
    ("fetch_license_individually", True, "bool", "Добирать номер ВУ по одному профилю"),
    ("park_contacts", PARK_CONTACTS_DEFAULT, "str", "Контакты таксопарка (HTML)"),
    ("accrual_hold_days", 0, "int", "Холд начислений, дней"),
    ("monthly_program_budget", 0, "int", "Месячный бюджет программы, сум (0 — без лимита)"),
    ("max_payout_per_referrer_per_month", 0, "int", "Лимит на реферера в месяц, сум (0 — без лимита)"),
    ("withdrawal_enabled", True, "bool", "Вывод включён"),
    ("withdrawal_mode", "auto", "str", "auto | manual"),
    ("min_withdrawal_amount", 0, "int", "Минимальная сумма вывода"),
    ("max_withdrawal_amount", 0, "int", "Максимальная сумма вывода (0 — без лимита)"),
    ("withdrawal_cooldown_hours", 0, "int", "Кулдаун между выводами, ч"),
    ("max_withdrawals_per_day", 0, "int", "Выводов в сутки (0 — без лимита)"),
    ("withdrawal_verify_delay_seconds", 60, "int", "Задержка перед сверкой, сек"),
    ("withdrawal_retry_delays_seconds", [60, 300, 900, 3600, 21600], "list", "Задержки ретраев вывода (A11)"),
    ("withdrawal_verifying_alert_minutes", 10, "int", "Алерт по выводу в verifying, мин"),
    ("payout_description", "Бонус реферальной программы", "str", "Описание транзакции выплаты в Fleet"),
    ("fleet_provider", "api", "str", "api | csv | manual | mock"),
    ("fleet_transaction_category_id", "", "str", "Категория бонусной транзакции Fleet"),
    ("fleet_transaction_categories", [], "list", "Кеш категорий транзакций из Fleet"),
    ("park_profiles_sync_interval_hours", 6, "int", "Интервал синка профилей, ч"),
    ("orders_sync_interval_minutes", 30, "int", "Интервал синка заказов, мин"),
    ("late_orders_window_hours", 72, "int", "Окно доначисления, ч (A17)"),
    ("online_time_sync_days", 35, "int", "Глубина синка времени на линии, дней"),
    ("fraud_autoapprove_below", 30, "int", "Риск ниже — авто-одобрение"),
    ("fraud_autoreject_above", 70, "int", "Риск выше — аннулирование"),
    ("impossible_hours_points_per_hour", 15, "int", "Порог баллов в час (IMPOSSIBLE_HOURS)"),
    ("fraud_rules", FRAUD_RULES, "json", "Severity и score правил антифрода"),
    ("fraud_burst_days", 3, "int", "BURST_QUALIFY: план быстрее, дней"),
    ("fraud_short_rides_share_percent", 60, "int", "SHORT_RIDES: доля коротких заказов, %"),
    ("fraud_same_route_share_percent", 50, "int", "SAME_ROUTE: доля повторяющихся маршрутов, %"),
    ("fraud_tariff_anomaly_jump_percent", 50, "int", "TARIFF_ANOMALY: рост доли тарифа, п.п."),
    ("fraud_velocity_per_day", 10, "int", "VELOCITY: рефералов за сутки"),
    ("fraud_low_gmv_percent", 40, "int", "LOW_GMV: средний чек ниже среднего на, %"),
    ("fraud_phone_cluster_size", 3, "int", "PHONE_CLUSTER: подряд идущих телефонов"),
    ("fraud_night_share_percent", 80, "int", "NIGHT_PATTERN: доля ночных заказов, %"),
    ("fraud_night_hours", [0, 1, 2, 3, 4, 5], "list", "NIGHT_PATTERN: ночные часы (Asia/Tashkent)"),
    ("fraud_min_orders_for_patterns", 20, "int", "Минимум заказов для статистических правил"),
    ("notify_progress_percents", [50, 80, 90], "list", "Пороги уведомлений о прогрессе, %"),
    ("notify_deadline_days", 5, "int", "Дедлайн: дней до конца месяца"),
    ("notify_deadline_percent_left", 10, "int", "Дедлайн: осталось до плана, %"),
    ("notify_inactive_days", 7, "int", "Друг не выходит на линию, дней (N5)"),
    ("approval_reminder_hours", 24, "int", "Напоминание о заявках в очереди, ч"),
    ("reminder_cooldown_hours", 24, "int", "Кнопка «Напомнить другу» — не чаще, ч"),
    ("broadcast_rate_per_second", 25, "int", "Скорость рассылки, msg/сек"),
    ("support_sla_hours", 4, "int", "SLA поддержки, ч"),
    ("source_tags", ["tg", "wa", "ig", "qr", "other"], "list", "Метки каналов (N4)"),
    ("tariff_aliases", {"express": "delivery", "courier": "delivery"}, "json",
     "Сопоставление категорий Fleet с кодами тарифов"),
    ("tariff_icons", {"econom": "🚗", "comfort": "🚙", "comfort_plus": "🚙", "business": "🚘",
                      "delivery": "📦", "cargo": "🚛", "default": "🚕"}, "json", "Иконки тарифов"),
    ("rejection_reasons", ["not_connected", "documents_invalid", "duplicate", "other"], "list",
     "Справочник причин отказа"),
    ("progress_bar_width", 10, "int", "Ширина прогресс-бара"),
    ("milestone_bar_width", 20, "int", "Ширина прогресс-бара достижений"),
    ("friends_page_size", 5, "int", "Друзей на странице"),
    ("leaderboard_size", 20, "int", "Размер рейтинга"),
    ("dashboard_top_referrers", 10, "int", "Топ рефереров в дашборде"),
    ("pending_profile_match_hours", 1, "int", "Интервал поиска профиля после подтверждения, ч"),
]

# ─────────────────────────── Условия программы v1 (17.3) ────────────────────────
# Плейсхолдеры подставляются из актуальных справочников при показе, поэтому
# в тексте нет зашитых сумм — изменение правил не делает условия устаревшими.
TERMS_V1_RU = """<b>Приведи друга — зарабатывай каждый месяц!</b>

1. Отправь другу свою персональную ссылку из бота.
2. Друг регистрируется: телефон и водительское удостоверение.
3. Друг подключает свой Яндекс Про к нашему таксопарку — контакты придут ему в боте.
4. Мы подтверждаем подключение, и друг появляется в твоём списке.
5. Каждый месяц, когда друг выполняет <b>план в {threshold} баллов</b>, ты получаешь <b>{bonus} сум</b>.
6. Бонус приходит <b>каждый месяц без ограничений</b>. Не выполнил план в этом месяце — в следующем всё продолжится.

<b>📊 СКОЛЬКО ЗАКАЗОВ НУЖНО ДЛЯ ПЛАНА</b>
Разные заказы дают разное количество баллов:
{coefficients_table}
Если друг ездит в разных тарифах, баллы складываются.

<b>💸 ВЫВОД ДЕНЕГ</b>
Деньги копятся в боте. Нажми «Вывести» в любой момент — сумма автоматически придёт на твой баланс в Яндекс Про.

<b>Важно:</b> если друг уже работал в нашем парке, рефералка не засчитывается. Приглашение действует {click_days} дней. Об изменении таблицы баллов мы предупреждаем минимум за {notice_days} дней. При накрутке заказов бонус аннулируется, а аккаунт блокируется."""

TERMS_V1_UZ_LATN = """<b>Do'stingizni taklif qiling — har oy daromad qiling!</b>

1. Do'stingizga botdagi shaxsiy havolangizni yuboring.
2. Do'stingiz ro'yxatdan o'tadi: telefon raqami va haydovchilik guvohnomasi.
3. Do'stingiz o'z Yandex Pro ilovasini taksoparkimizga ulaydi — kontaktlar unga botda yuboriladi.
4. Biz ulanishni tasdiqlaymiz va do'stingiz ro'yxatingizda paydo bo'ladi.
5. Har oy do'stingiz <b>{threshold} ballik rejani</b> bajarganda, siz <b>{bonus} so'm</b> olasiz.
6. Bonus <b>har oy cheklovsiz</b> beriladi. Bu oy reja bajarilmasa — keyingi oy hammasi davom etadi.

<b>📊 REJA UCHUN NECHTA BUYURTMA KERAK</b>
Turli buyurtmalar turlicha ball beradi:
{coefficients_table}
Agar do'stingiz turli tariflarda ishlasa, ballar qo'shiladi.

<b>💸 PULNI YECHISH</b>
Pul botda yig'iladi. Istalgan vaqtda «Yechish» tugmasini bosing — summa avtomatik ravishda Yandex Pro balansingizga tushadi.

<b>Muhim:</b> agar do'stingiz avval parkimizda ishlagan bo'lsa, taklif hisobga olinmaydi. Taklif {click_days} kun amal qiladi. Ballar jadvali o'zgarishi haqida kamida {notice_days} kun oldin ogohlantiramiz. Buyurtmalar sun'iy ko'paytirilsa, bonus bekor qilinadi va akkaunt bloklanadi."""

TERMS_V1_UZ_CYRL = """<b>Дўстингизни таклиф қилинг — ҳар ой даромад қилинг!</b>

1. Дўстингизга ботдаги шахсий ҳаволангизни юборинг.
2. Дўстингиз рўйхатдан ўтади: телефон рақами ва ҳайдовчилик гувоҳномаси.
3. Дўстингиз ўз Яндекс Про иловасини таксопаркимизга улайди — контактлар унга ботда юборилади.
4. Биз уланишни тасдиқлаймиз ва дўстингиз рўйхатингизда пайдо бўлади.
5. Ҳар ой дўстингиз <b>{threshold} баллик режани</b> бажарганда, сиз <b>{bonus} сўм</b> оласиз.
6. Бонус <b>ҳар ой чекловсиз</b> берилади. Бу ой режа бажарилмаса — кейинги ой ҳаммаси давом этади.

<b>📊 РЕЖА УЧУН НЕЧТА БУЮРТМА КЕРАК</b>
Турли буюртмалар турлича балл беради:
{coefficients_table}
Агар дўстингиз турли тарифларда ишласа, баллар қўшилади.

<b>💸 ПУЛНИ ЕЧИШ</b>
Пул ботда йиғилади. Исталган вақтда «Ечиш» тугмасини босинг — сумма автоматик равишда Яндекс Про балансингизга тушади.

<b>Муҳим:</b> агар дўстингиз аввал паркимизда ишлаган бўлса, таклиф ҳисобга олинмайди. Таклиф {click_days} кун амал қилади. Баллар жадвали ўзгариши ҳақида камида {notice_days} кун олдин огоҳлантирамиз. Буюртмалар сунъий кўпайтирилса, бонус бекор қилинади ва аккаунт блокланади."""

TERMS: list[dict[str, Any]] = [
    {"version": 1, "text_ru": TERMS_V1_RU, "text_uz_latn": TERMS_V1_UZ_LATN, "text_uz_cyrl": TERMS_V1_UZ_CYRL},
]

# ─────────────────────────── Инфраструктурные константы ─────────────────────────
ANTIFLOOD_SECONDS = 30  # антифлуд кнопки вывода, «не отключается» (6.5)

# Расписание фоновых задач (Раздел 11), время — Asia/Tashkent.
# minute может быть числом, списком или {"every": N}.
JOB_SCHEDULE: dict[str, dict[str, Any]] = {
    "ensure_current_period": {"minute": 5},
    "open_period": {"day": 1, "hour": 1, "minute": 0},
    "close_period": {"day": 1, "hour": 2, "minute": 0},
    "sync_orders": {"minute": {"every": 30}},
    "sync_park_driver_profiles": {"hour": {"every": 6}, "minute": 15},
    "sync_driver_online_time": {"hour": 6, "minute": 0},
    "match_pending_referrals": {"minute": 20},
    "reconcile_withdrawals": {"minute": {"every": 10}},
    "retry_failed_withdrawals": {"minute": {"every": 30}, "offset": 7},
    "expire_referrals": {"hour": 4, "minute": 30},
    "rebuild_daily_stats": {"hour": 3, "minute": 0},
    "release_holds": {"hour": 4, "minute": 0},
    "fraud_check": {"day": 1, "hour": 3, "minute": 0},
    "progress_notifications": {"hour": 10, "minute": 0},
    "deadline_reminders": {"hour": 11, "minute": 0},
    "inactive_friend_alert": {"hour": 12, "minute": 0},
    "pending_approval_reminder": {"hour": 9, "minute": 0},
    "unknown_tariff_alert": {"hour": 9, "minute": 30},
    "terms_acceptance_reminder": {"hour": 13, "minute": 0},
    "monthly_digest": {"day": 1, "hour": 12, "minute": 0},
    "leaderboard_update": {"hour": 8, "minute": 0},
    "db_backup": {"hour": 5, "minute": 0},
    "health_check": {"minute": {"every": 5}},
    "run_scheduled_broadcasts": {"minute": {"every": 1}},
}

BACKUP_RETENTION_DAYS = 30
JOB_LOCK_TTL_MINUTES = 30
SETTINGS_CACHE_TTL_SECONDS = 15
FLEET_BATCH_SIZE = 500
FLEET_CONNECT_TIMEOUT = 5.0
FLEET_READ_TIMEOUT = 30.0
FLEET_BREAKER_FAILURES = 5
FLEET_BREAKER_PAUSE_SECONDS = 5 * 60
