# Фронтир — правила для Claude Code

Источник истины по игре: [`docs/GDD.md`](docs/GDD.md). Читай его перед любой задачей.

## Как работаем
- **Строго по этапам** из GDD §15, по одному. В конце этапа: commit + отчёт по GDD §16, потом ждать «дальше».
- **Логика отдельно от Roblox.** `src/shared/` — чистый Luau без Roblox API (можно `buffer`, `math`, `table`, `bit32`). Всё в нём покрывается Lune-тестами в `tests/`.
- **`--!strict` в каждом файле**, типы у всех публичных функций.
- **Сервер решает всё.** Клиент шлёт намерения (intents) и рисует. Каждое намерение сервер валидирует.
- **Все числа баланса — только в `src/shared/Config.luau`.** Никаких магических чисел. Изменения баланса — в `docs/BALANCE.md`.
- **Все строки UI — через ключи** в `src/shared/Strings.luau` (RU/EN), не хардкодом.
- **Плейсхолдеры вместо арта**: рисуем программно. Нужные спрайты и размеры — в `docs/ART_LIST.md`. Цвета — только из `docs/palette.md` (32 цвета палитры + 24 цвета держав из `NationColors`).
- **Не выдумывать API Roblox.** Сверяться с create.roblox.com/docs. Упёрлись в лимит — сказать и предложить замену.
- **Оригинальность** (уточнено геймдизайнером): механики жанра можно брать у других игр, если они делают игру интереснее. Не копируем только чужой код, арт, звуки, названия, логотипы и узнаваемый интерфейс один в один — это авторское право и правила Roblox.
- **Никаких реальных стран, флагов, лидеров**, любой текст игроков — через фильтр Roblox.
- Изменения записывать в `docs/CHANGELOG.md`.
- **Превью партии** каждого этапа — в репозиторий: `lune run tools/match_preview <сек> <сид> docs/previews/stage-N.png`,
  ссылку на картинку — в отчёт.
- **Темп матча** крутится одним числом `Config.Match.Speed` (всё игровое время); новые механики со временем
  (армии, найм, перезарядки) обязаны идти через `simDt`/`simTime`, а не через реальное время.

## Отчёт по этапу (GDD §16) — всегда в конце
Что сделано · Как проверить в Studio · Тесты · Известные проблемы · Что дальше · ссылка на `docs/previews/stage-N.png` ·
чек-лист для геймдизайнера (заполняет он): карта/кириллица (для кириллицы при английском Roblox —
`Config.Dev.ForceLang = "ru"`); границы в двух окнах одинаковые — да/нет; атака и отмена; ошибки в Output; телефон.

## Команды (из папки `frontir/`)
```bash
rokit install           # поставить инструменты из rokit.toml
lune run tests          # все тесты; `lune run tests Config` — только файлы с "Config" в имени
stylua --check src tests tools
selene src tests tools
rojo serve              # синхронизация со Studio
lune run tools/genmap Pangea   # пересоздать maps/Pangea.luau (+ превью build/Pangea.bmp)
lune run tools/palette_preview # пересоздать docs/palette.png после правки цветов
lune run tools/match_preview 120  # партия ботов на 120 с → build/match.png (форма границ, цвета, темп)
rojo sourcemap default.project.json -o sourcemap.json   # для luau-lsp
lune setup              # типы Lune (алиас @lune в .luaurc)
luau-lsp analyze --platform=roblox --definitions:@roblox=types/globalTypes.d.luau --sourcemap=sourcemap.json --base-luaurc=.luaurc src tests tools
```
CI (`.github/workflows/ci.yml`) гоняет StyLua, Selene, luau-lsp analyze (strict) и тесты; любая ошибка роняет сборку.

## Типы в strict
- Singleton-юнионы (`"ru" | "en"`) расширяются до `string` на неаннотированных `local` и переменных цикла — аннотируй: `local lang: Strings.Lang = ...`.
- Наборы с известными ключами (юниты, здания) — record-типы (`Types.UnitTable`), а не словари с юнион-ключами.
- Для перебора перечислений держим отдельные списки (`Types.TerrainIds`).

## Раскладка в Roblox (default.project.json)
- `src/shared` → `ReplicatedStorage.Shared`
- `maps` → `ReplicatedStorage.Maps`
- `src/server` → `ServerScriptService.Server`
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client`

## Карта и рендер
- Чистые модули карты в `src/shared`: `MapGen` (генератор), `MapFormat` (бинарный формат + base64 в ModuleScript),
  `MapPaint` (цвета клеток), `CameraMath`. Клиентская обвязка — `src/client/Render`, `src/client/Input`.
- EditableImage: максимум 1024×1024, на экране обновляется один EditableImage за кадр, бюджет памяти клиента
  (CreateEditableImage → nil), в опубликованной игре нужен флаг Allow Mesh / Image APIs.
- Pure-модули, которые нужны клиенту, кладём в `src/shared` (клиентская папка не видит shared по относительному пути).

## Матч (этап 2)
- Симуляция целиком в `src/shared/MatchSim.luau` (+ `Grid`, `Economy`, `Expansion`, `StartPositions`, `BotBrain`,
  `NameGen`, `Intents`, `RateLimiter`) — без Roblox API, тестируется в Lune. Сервер (`src/server/Match/MatchService`)
  только кормит её игроками, намерениями и временем и рассылает результат.
- Сеть: один RemoteEvent `Remotes.Match` (сервер → клиент, порядок сохраняется): buffer-сообщения `Net/Protocol`
  (снимок частями, дельты, статистика) и таблицы (`info`, `events`, `rejected`). Клиент → сервер: `Remotes.Intent`
  (kind, payload), сервер проверяет лимитом, `Intents.parse` и `MatchSim.applyIntent`.
- Клиент собирает состояние в `ClientState` (тест сверяет его с сеткой сервера побайтно).
- StyLua 2.6 падает на `//` внутри длинного конструктора таблицы — выноси вычисление в локальную переменную.

## Провинции, города и фронты (этапы 3а–3б)
- Провинции генерирует `MapGen.generateProvinces` (хранятся в слое province карты); всё остальное о них —
  `Provinces.build(map)` одинаково на сервере и клиенте (центры, соседи, имена, нейтральные города).
- Город — клетка с флагом `Grid.city`: ползущая граница людей (`Expansion`) города не берёт, берут только войска.
- **Модель «Фронты» (решение геймдизайнера, 3б):** отрядов на карте нет. Войска — пул державы по типам
  (`Types.Forces`, `Forces`): найм в очередь, гарнизон `nation.home`. Атака на державу — фронт: доля войск
  уходит в `attack.forces`; бой, перевес, потери, опыт и снабжение — `Fronts`; клетки двигает `Expansion.advanceFront`.
  Выбывание — когда пал последний город (`MatchSim`).
- Сеть: фронты и сила держав — в STATS (`Net/MatchStats`), свои войска — FORCES каждому игроку; сетка — дельтами.
  Трафик проверяет тест «60 держав» против `Config.Net.BudgetBytesPerSec`.
- Клиент: `Render/FrontLayer` сам находит линии фронтов в своей копии сетки и ставит юнитов (`UnitSprites` —
  общие спрайты с превью), `UI/ForcesPanel` — найм Z/X/C/V и панель войск.

## Require
Внутри `src/shared` модули подключают друг друга строкой: `require("./Types")` — так работает и в Roblox (`./` = `script.Parent`), и в Lune.
Сервер и клиент берут общие модули через `ReplicatedStorage.Shared`.
