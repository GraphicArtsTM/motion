# Фронтир — правила для Claude Code

Источник истины по игре: [`docs/GDD.md`](docs/GDD.md). Читай его перед любой задачей.

## Где мы сейчас
Сделаны этапы **0–6**, **7а**, **7б-1** (флот), **7б-2** (авиация), доработки перед 7в, **7в-1** и **7в-2** — всё в `main` (PR #2–#8).
**7в-1** (технологии) и **7в-2** (генералы) смержены (PR #7, #8). **7г** и **8а** смержены (PR #9), разведка, **8б** и **8в** — PR #10. **8г** — PR #11. **9а** и **9б** — PR #12, **9в** и **9г** — PR #13.
**10а** (обучение) готов и ждёт проверки в Studio; **10б** (звук и музыка) — тоже; дальше 10в (телефон, аналитика, баланс)
(см. «Статус» в начале GDD §15). Обновляй «Статус» в GDD и этот раздел в конце каждого этапа.

## Порядок работы (договорённости с геймдизайнером)
- Каждый этап (или его часть) — **ветка от свежего `main` и отдельный PR в `main`**.
- **Кто мержит:** PR, где меняются **только документы или тесты**, Claude мержит сам после зелёного CI. PR с фичами
  (любой код игры, инструменты, Config) мержит **геймдизайнер** после проверки в Studio.
- **Замеры производительности:** только честные — `lune run tools/bench_ab ...`: `main` и ветка в одном запуске
  на одной машине, по 5 прогонов вперемешку, берём минимум. В отчётах только такие цифры.
- Большой этап делим на части (а/б/в…), после каждой — отчёт и «дальше».
- Сначала правила этапа в GDD (отдельный коммит), потом код. Решения геймдизайнера — сразу в GDD.
- Новые механики сразу добавлять в панель разработчика (F4) и в чек-лист README «Проверка этапа в Studio».
- Отчёты и общение — по-русски, коротко; числа — из замеров (тесты, `tools/bench`, превью), не на глаз.
- **Экономим лимиты** (решение геймдизайнера после 7в-2):
  - на PR не подписываться и проверки по расписанию не ставить — если CI упадёт, геймдизайнер напишет сам;
  - арену и долгие замеры (`bot_arena`, `bench_ab`) — только по просьбе или когда меняется баланс;
  - CI идёт на `pull_request` и на `push` только в `main` (без двойных прогонов);
  - отчёт короткий: что сделано, как проверить (до 5 пунктов), проблемы и вопросы к геймдизайнеру.

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
- **Монетизация** (решение геймдизайнера перед этапом 9, GDD §11.1): мягкий pay-to-win с потолком `Shop.MaxEdge`,
  у каждого платного буста — бесплатный путь (жетоны), один буст каждого вида за матч, в «Дуэли» — без бустов;
  никаких платных случайных наград и давящих таймеров.
- Изменения записывать в `docs/CHANGELOG.md`.
- **Превью партии** каждого этапа — в репозиторий: `lune run tools/match_preview <сек> <сид> docs/previews/stage-N.png`,
  ссылку на картинку — в отчёт.
- **Темп матча** крутится одним числом `Config.Match.Speed` (всё игровое время); новые механики со временем
  (армии, найм, перезарядки) обязаны идти через `simDt`/`simTime`, а не через реальное время.

## Отчёт по этапу (GDD §16) — всегда в конце
Коротко (с 7г): что сделано · как проверить в Studio (до 5 пунктов) · проблемы и вопросы к геймдизайнеру; ссылка на
`docs/previews/stage-N.png`. Подробный чек-лист — в README «Проверка этапа в Studio».

## Команды (из папки `frontir/`)
```bash
rokit install           # поставить инструменты из rokit.toml
lune run tests          # все тесты; `lune run tests Config` — только файлы с "Config" в имени
stylua --check src tests tools
selene src tests tools
rojo serve              # синхронизация со Studio
lune run tools/realmap all     # пересоздать реальные карты maps/*.luau (данные кешируются в build/geo/)
lune run tools/maps_preview    # лист всех карт → build/maps.png
lune run tools/bench World 60 180  # нагрузка: время тика и трафик на 60 ботах
lune run tools/genmap Pangea   # пересоздать тестовую maps/Pangea.luau (+ превью build/Pangea.bmp)
lune run tools/palette_preview # пересоздать docs/palette.png после правки цветов
lune run tools/match_preview 120 12345 build/match.png Europe 12 Teams  # партия ботов → картинка (секунды, сид, файл, карта, держав, режим)
lune run tools/bot_arena Europe 20  # «игрок» (Обычный бот) против трёх Новичков / Обычных / Генералов, 20 сидов, пороги
lune run tools/bench_ab World 60 180 5  # честный замер: main и ветка в одном запуске, 5 прогонов, минимум
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
- `maps` → `ServerStorage.Maps` (сервер копирует выбранную карту в `ReplicatedStorage.Maps` — клиенты получают только её)
- `src/server` → `ServerScriptService.Server`
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client`

## Карта и рендер
- Чистые модули карты в `src/shared`: `MapGen` (генератор), `MapFormat` (бинарный формат + base64 в ModuleScript),
  `MapPaint` (цвета клеток), `CameraMath`. Клиентская обвязка — `src/client/Render`, `src/client/Input`.
- EditableImage: максимум 1024×1024, на экране обновляется один EditableImage за кадр, бюджет памяти клиента
  (CreateEditableImage → nil), в опубликованной игре нужен флаг Allow Mesh / Image APIs.
- Pure-модули, которые нужны клиенту, кладём в `src/shared` (клиентская папка не видит shared по относительному пути).
- **Реальные карты (этап 4а):** `tools/realmap` + `tools/lib/Geo` (проекция, заливка многоугольников, реки, высоты,
  местность, фильтр имён `Geo.isNameAllowed` — без реальных стран). Параметры — `Config.RealMaps`,
  `Config.RealMapTerrain`. Имена провинций лежат в модуле карты (`provinceNames`), `Provinces.build` берёт их оттуда.
  Тест `RealMaps.spec` проверяет все карты: размер ≤ 1024, провинций 60–250, имена, места для старта.

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

## Война и мир, бой на фронте (этап 3в)
- `Wars` — чистое состояние войн: по умолчанию мир, `declare` → мобилизация → активная война, журнал взятой
  в войне земли (`record` из `Expansion.Hooks`), потери, предложения мира, запрет новой войны после мира, усталость.
  `MatchSim` решает правила: фронт против страны — только в активной войне, окружение не берёт куски стран без войны.
- `Expansion.selectCells`: идёт вся граница (вероятность клетки по скорости), focus — главное направление удара,
  щели и дыры берутся сразу. Фронт переходит реку (`frontier` с map), цена клетки ×RiverCrossCost.
- `BattleLayout` — где стоят юниты в бою (общий для клиента и превью); `Render/FrontLayer` — анимация боя из пулов,
  пределы в `Config.Render.Battle`; `UI/WarPanel` — баннер войны и окна войны и мира.
- Карты в игре — только реальная география (этап 4); «Пангея» — для тестов и превью.

## Экономика и здания (этап 4б)
- `Economy` — доход, нефть, содержание, максимум людей; `Buildings` — правила стройки и что у кого есть
  (владелец здания = владелец его клетки); `Pockets` — котлы (заливка по меткам `Grid.stamp`, пересчёт только
  при изменении территории — `Grid.version`). `MatchSim.refreshOwned` раз в тик собирает здания по державам.
- Нефтяные поля — в `Provinces.build` (детерминированно, по сети не идут). Здания — в info и сообщением `buildings`,
  деньги и нефть игрока — в FORCES.
- Клиент: `UI/BuildPanel` (B, меню, режим стройки забирает нажатие на карту), `Render/BuildingLayer`
  (значки из `BuildingSprites`, общие с превью).
- Нагрузку проверять `lune run tools/bench Europe 12 300` и `tools/bench World 60 180`: тик в среднем ≤ 10 мс.

## Цикл матча и HUD (этап 4в)
- Фазы `Waiting → Lobby → Pick → Play → Over` в `MatchSim`; победа (`checkVictory`): доля суши, последняя держава,
  `Match.TimeLimitSec`. Итог (`m.result`: места, график долей) — в info. Сервер после `Over` создаёт новый матч
  на той же карте; клиент сбрасывает состояние по новому `matchId` (`ClientState.applyInfo` → colorsChanged).
- Флаг `m.victory = false` выключает проверку победы — для тестов на крошечных картах.
- Клиент: `UI/ResultsPanel` (итоги), `UI/Minimap` + `MinimapPaint` (своё EditableImage, перерисовка по таймеру
  и только при изменениях). Превью рисует мини-карту и график так же.

## Боты v2 (этап 5)
- `BotBrain` — решения бота по `BotView` (то, что видит игрок) и профилю: уровень (`Config.BotLevels`: Новичок,
  Обычный, Генерал) и личность (`Config.BotPersonalities`, множители). `MatchSim` хранит профили в `m.botProfiles`,
  уровень и личность — в `Nation.botLevel/personality` (уходят клиенту в info).
- Бюджет: `Bots.MaxThinksPerTick` раздумий за тик. Генералу +10% дохода — в `stepEconomy` (единственное послабление).
- `MatchSim.setBot(m, id, level, personality?)` — сделать державу ботом (арена, тесты). Автостарт —
  на крупном массиве суши (`StartPositions.landmasses`, `Start.MinLandmassShare`).
- Проверка силы уровней — `lune run tools/bot_arena Europe 20` (пороги `Config.Bots.Arena*`); тесты — `Bots.spec`.
- Для Studio: `Config.Dev.BotLevel` и `Config.Dev.Nations`.

## Договоры (этап 6а)
- `Diplomacy` — чистое состояние: пакты, союзы, разрыв (`startBreak` → `update`), «Предатель», вассалы, предложения
  и требования, история; `version` растёт при изменениях. `MatchSim` решает правила: `declareWar` (предательство,
  союзникам — событие), `offer`/`resolveOffer` (ответы игроков, ботов и по таймеру), уступка провинции, капитуляция
  в `makePeace(..., from)`, дань вассала в `stepEconomy`, снабжение `Fronts.supplied(..., friends)`, победа союза.
- Боты: `BotBrain.answerOffer` и дипломатия в `decide` (веса `alliance/betray/demand/loyalty` в личностях).
- Сеть: таблица `diplo` (`MatchStats.diplo`, `ClientState.applyDiplo`), сроки — «осталось секунд игрового времени».
  info и diplo — не чаще `Net.InfoMinSec` / `Net.DiploMinSec`. Клиент: `UI/DiplomacyPanel` (T, требование
  забирает нажатие на карту).

## Совет и торговля (этап 6б)
- Торговые соглашения и эмбарго — в `Diplomacy` (`trade`, `embargo`); переводы — `MatchSim.transfer` (налог, лимит
  за минуту `m.sent`); `Council` — созыв, голосование, действующие резолюции; эффекты — `MatchSim.applyResolution`,
  доход в `stepEconomy`, перемирие в `stepAttacks` и `declare`. Пинги — событие `ping` (только фразы из Strings).
- Сеть: всё в `diplo` (версия договоров + версия Совета). Клиент: `UI/CouncilPanel`, `UI/Pings` (G, метки на canvas),
  торговля в `UI/DiplomacyPanel`.

## Туман войны, стабильность и восстания (этап 7а)
- `Stability` — чистый модуль: хозяин провинции (город или больше половины клеток — счётчики `Grid.provinceCells`),
  целевая и текущая стабильность, итоги по державам (`summary`: средняя, клетки с половинным доходом), восстания и
  «Повстанцы». Что нужно о матче — через `Stability.Context` (`MatchSim.stabilityContext`). `MatchSim`: пересчёт
  раз в `Stability.UpdateSec` (`stepStability`), восстание — `MatchSim.revolt` (клетки ничьи, город повстанцев
  с гарнизоном `RebelGarrison` в `neutralCityTaker`), ничья земля повстанцев дороже (`Expansion.Hooks.costMul`),
  доход — в `stepEconomy`. Боты: `spots.unstable` / `unstableCity` и мир раньше (`BotBrain`).
- **С правки после 8а карта открыта:** туман на карте только в «Мгле» (`m.rules.fog`, `MatchStats.fogOn`,
  `cs.rules.fog`; тесты тумана — `Modes.withFog`). Скрыта чужая военная мощь (§6.11а): `MatchSim.knownSet` (друзья,
  разведка `m.intel`, радары `m.radarIntel`, вспышка), `MatchStats.forViewer(..., known)` / `wars(m, known)` — «?»
  (−1) и грубая сила (`MatchStats.hidden`, клиент рисует юнитов по модулю). Разведка — `MatchSim.spy` (намерение
  `intel`), боты — `botIntel`.
- `Fog` — чистый модуль: обзор клиента (фаска 5/7 в прямоугольнике вокруг источников, два прохода), последний
  увиденный владелец (`known`), «видно всё» (`all`, так начинается матч и так у зрителя); грубый обзор сервера
  блоками (`visionBlocks`, `lineVisible` по выборке линии фронта `Attack.line`).
- Сеть: STATS у каждого игрока свой — `MatchStats.forViewer` (державы кодируются один раз: `Protocol.encodeStatsHead`),
  таблица `stability` раз в `Net.StabilityEverySec` (`MatchStats.stability`, `ClientState.applyStability`).
  Клиент: `ClientState.refreshFog` (раз в `Fog.RefreshSec`), дельта возвращает только клетки в обзоре;
  `TerritoryLayer` рисует `knownOwners` (туман — `TerritoryPaint.Extra`, вся карта — `MapRenderer.blit`),
  `UI/StabilityPanel` (N), строка стабильности в `MatchHud`.
- Замер: `lune run tools/bench World 60 180` в конце печатает время тумана у клиента и STATS для всех.

## Флот (этап 7б-1)
- `Naval` — море из карты (одинаково на сервере и клиенте; в `MatchSim.new` кешируется на карту): номер моря клетки,
  причалы провинций (`docks`), путь корабля — A* по блокам 8×8 (узлы — связные куски моря в блоке), потом A* по клеткам
  внутри коридора узлов (худшее на «Европе» ~15 мс; без коридора было до 280 мс). `coastReach` — берег в радиусе
  снабжения от причала (кеш).
- `Fleet` — корабли (точка в клетках, состояния docked/planning/moving/patrol), очередь путей (`Naval.PathsPerTick`
  за тик), движение, бой кораблей, блокада. Правила — в `MatchSim` (секция «Флот»): `navalIntent` (ship/land/patrol),
  `land` (плацдарм и фронт), `stepFleet` (найм, высадки, обстрел берега, блокада), снабжение по морю в `stepAttacks`
  (`seaSupplySets`, `Attack.seaSupplied`) и `pocketSeaSupplied` в котлах. Боты: `navyView` (цели — лениво, функциями)
  и `navyDecision` в `BotBrain` (личность `navy`).
- Сеть: SHIPS (`Protocol.encodeShips`, `MatchStats.ships` — по тому же обзору, что фронты, `MatchStats.vision`).
  Клиент: `Render/ShipLayer` (плавное движение, туман), `UI/NavalPanel` (меню порта, высадка, патруль),
  `ShipSprites` общие с превью.

## Авиация (этап 7б-2)
- `Air` — самолёты (точка в клетках, состояния based/flying/raiding/returning; летают по прямой), налёты по таймеру
  (событие `raid` с клеткой цели), перехват истребителями (круг вокруг точки прикрытия), батареи ПВО, ремонт
  выведенных из строя зданий (`disabled`: клетка → до когда), `aaReduction` (доля ПВО в войсках). Правила — в `MatchSim`
  (секция «Авиация»): `airIntent` (plane/raid/cover), `bomb` (фронты врага, его гарнизон у нашей линии, его здания,
  кроме города и батареи ПВО), `stepAir`; выведенные из строя здания не считаются в `Buildings.owned`, `ports`,
  укреплениях и радарах. Боты: `airView` (цель налёта — лениво, по линии фронта) и `airDecision` (личность `air`).
- Сеть: AIR (`Protocol.encodeAir`, `MatchStats.air` — тот же обзор, что фронты и корабли). Клиент: `Render/AirLayer`
  (самолёты с тенью, метки выведенных из строя зданий), `UI/AirPanel` (меню аэродрома, налёт, прикрытие),
  `PlaneSprites` общие с превью.

## Технологии и генералы (этапы 7в-1, 7в-2)
- `Tech` — уровни веток и исследования (`m.tech`); эффекты проверяет `MatchSim` через `Tech.has`, здания —
  `MatchSim.techAllows` (`Config.Tech.Unlocks`). Боты — `BotBrain.techChoice` / `techSavings` (копилка).
- `Commanders` — генерал игрока (в коде Commander, не путать с уровнем бота General): выбор, перезарядки, эффекты
  (`surgeUntil`, `revealUntil`, зоны `strikes` / `forts`), пассивки множителями. Правила — секция «Генералы» в
  `MatchSim`: `useAbility`, `abilityDefenseMul` (в бою), `surgeMul`, `revealing`, `landAt` (общий плацдарм), боты —
  `botAbility`. Цены: `MatchSim.unitCost`, `shipCost`, стройка. Туман: `Fog.Sources.visionMul / ports`,
  `Fog.visionBlocks(..., visionMul)`.
- Сеть: таблицы `tech` и `commander` раз в секунду (`MatchStats`, `ClientState.applyTech / applyCommander`).
  Клиент: `UI/TechPanel` (Y), `UI/CommanderPanel` (лобби, Q / E).
- Найм: линии `MatchSim.recruitLines` (1 + заводы + уровни городов / `CityLevelsPerLine`, до `MaxRecruitLines`).

## События и ракеты (этап 7г)
- `WorldEvents` — расписание, выбор по весам, шторм, урожай, аукцион (`m.world`, поток `m.worldRng`). Правила —
  секция «Случайные события и ракеты» в `MatchSim`: `worldEvent`, `bid` / `botsBid`, `launch`, `missileImpact`
  (сеть ПВО — `m.missileRng`), `stepWorld`, боты — `botMissile`. Шторм — `Fleet.move(..., blocked)`.
- Сеть: таблица `world` раз в секунду (`MatchStats.world`, `ClientState.applyWorld`). Клиент: `UI/WorldPanel`,
  `Render/MarkerLayer`, кнопка R в `UI/CommanderPanel`.

## Режимы (этап 8а)
- `Modes` — правила режима (`Rules`: доля суши, лимит, скорость, туман, шахта, команды, охота), варианты голосования
  (`options`, режим недели `weekly`), подсчёт (`tally`), команды по долготе (`assignTeams`). `MatchSim`: `m.rules`
  вместо `Config.Match.*` (победа, лимит, скорость), `openVote` / `setMode` (в конце лобби), намерения `modeVote`,
  `difficulty`, `solo`; команды — `MatchSim.teammates` (война, разрыв, договоры, налог), `checkTeamVictory`,
  охота — `huntWinner`. Пауза и ×2 — в `MatchService` (Heartbeat не шагает / шагает ×2).
- Сеть: `mode` в info (`ClientState.ModeInfo`), у держав `team`, `hunt`, `huntLeft`. Клиент: `UI/ModePanel`,
  время и таймеры — `ClientState.matchTime` / `simRate` (не `Config.Match.Speed`).

## Карты и дуэль (этап 8б)
- Голосование за карту — `m.mapOptions` / `m.mapVotes` (открывается в `finishMatch`), `MatchSim.mapWinner`; сервер
  после итогов зовёт `loadMap` (из `Main.server`) и начинает матч на новой карте. Дуэль — `rules.duel`
  (`targetNations` = игроки, 2×2 — `teamCount = 2`).
- **Клиент живёт сессиями:** `Main.client` → `runSession(mapId, resync)`. Любая подписка в клиенте — только
  `Session.connect(signal, fn)` (не `:Connect`), EditableImage и ScreenGui — `Session.track`; `teardown` снимает всё
  при смене карты (`MatchClient.onMapChange`), новая сессия шлёт `sync`.

## «Потоп» и регионы (этап 8в)
- `Flood` — высоты до воды (кеш на карту), `threshold`, `sinking`, `paint`; сервер — `MatchSim.floodStep`
  (`m.flood`, `Grid.sink`, `Buildings.remove`), клиент — `syncFlood` в `Main.client` (цвета карты, мини-карта).
  Новые карты — `Config.RealMaps.Scandinavia / Caribbean / Oceania`, в `MapVote.Pool`.

## Частные серверы (этап 8г)
- `ServerSettings` — настройки владельца (`parse`, `defaults`, `applyRules`, `maxNations`); `m.settings` в MatchSim
  (`setMode`, `finishPick`, `offer`, `finishMatch`). Сервер: `isPrivate`, `ownerId`, намерение `settings`,
  `startNewMatch(mapId)` (итоги и смена настроек в лобби). Клиент: `UI/ServerPanel` (O), `cs.server`.
- Studio: `Config.Dev.PrivateServer = true`.

## Профиль и магазин (этап 9а)
- `Profile` (данные, миграция, уровни, награда, генералы по уровням, `grantProduct` без повторов) и `Shop`
  (каталог, `productById`, `perks`) — чистые. MatchSim: `perksOf` / `setPerks`, `canBoost` / `useBoost`,
  `setUnlocked`, `rules.boosts`. Сервер: `Services/ProfileStore` (блокировка сессии), `Services/ShopService`
  (ProcessReceipt, пассы), в `MatchService` — `applyProfile`, `useBoost` (жетон / запас), `giveRewards`, `profile`.
  Клиент: `UI/ShopPanel` (M), `cs.profile`. Товары — id в `Config.Shop` (0 — не создан).

## Платные части, пропуск, ящики (этап 9б)
- Бусты `Guards`, `Airstrike` (цель — `cell`, `MatchSim.strikeAt`), `Squadron`, `AirWing` — в `MatchSim.useBoost`.
  Профиль: `seasonReward` / `addSeasonXp` / `grantSeason`, `openCrate` (гарантия `pity`), `claimDaily`,
  первая победа дня в `applyMatch(..., now)`; `Shop.weeklyOffer` / `weekLeft`. Сервер: `daily`, `crate`, `openCrate`.
- Таймеры в магазине — только настоящие сроки; шансы ящиков — в окне до покупки (правило Roblox).

## Косметика и флаг (этап 9в)
- `Cosmetics` — каталог, `owns` / `buy` / `equip` / `setFlag`, `public`, `patternHit`; данные — в `Profile`
  (`cosmetics`, `equipped`, `flag`). Отрисовка — `TerritoryPaint.Extra.pattern / flashColor`, `NationLabels`,
  `UI/FlagView`; окно — `UI/WardrobePanel` (K). Сервер: `cosmeticOf` в info, намерения `buyCosmetic`, `equip`, `flag`.

## Задания, лидеры, рейтинг (этап 9г)
- `Quests` — задания дня (`forDay`, `sync`, `onMatch`) и Эло (`eloExpected`, `eloDelta`); данные — в `Profile`
  (`quests`, `questsBonus`, `elo`). Сервер: `giveRewards` (задания, победы недели, Эло дуэли), `Services/Leaders`
  (OrderedDataStore), сообщения `quests`, `leaders`. Клиент: `UI/QuestsPanel` (J).
- Тест `Strings.spec` ищет в `src` ключи `Strings.get("…")` и проверяет, что они есть.

## Обучение (этап 10а)
- Режим `Tutorial` (`rules.tutorial`, `rules.events = false`), шаги — `MatchSim.tutorialDone` / `stepTutorial`
  (`m.tutorialStep`, `m.tutorialStart`), награда — `Profile.finishTutorial` на сервере по событию `tutorialDone`.
  Клиент: `UI/TutorialPanel`, `cs.tutorialStep`.

## Звук и музыка (этап 10б)
- Файлы звуков генерирует `tools/sfx_gen` (`tools/lib/Synth`, `tools/lib/SoundBank`) в `assets/audio`; в игру —
  загрузкой в Roblox (id в `Config.Sounds` / `Config.Music`) или `Sound` в `SoundService/FrontirAudio`.
- `AudioCues` (чистый): события → звуки, выбор музыки, `allow` (частота). Клиент: `Audio` (play / music /
  setVolumes), звуки подключены в `Main.client` (onEvents, onDelta, onStats, клики кнопок HUD), `UI/SoundPanel`
  («♪», громкости в профиле: `Profile.setVolumes`, намерение `volume`).

## Панель разработчика (F4)
- Только в Studio: `MatchService` создаёт `Remotes.Dev` при `RunService:IsStudio()`; действия — чистый `DevTools`
  (grant, forceOffer, warNow, peaceNow, councilNow, endMatch, setStability, revoltNow, navy, botLanding, airForce,
  botRaid, researchAll, finishResearch, resetCooldowns, nextCommander, botAbility, eventNow, silo, botMissile; «Режим» — в `MatchService`), ускорение ×5 — шагов
  симуляции за кадр в `MatchService`, «Туман выкл» — `devNoFog` в `MatchService` и `cs.fogOff` на клиенте.
  Клиент: `UI/DevPanel`. Новые механики — сразу добавлять в панель и в чек-лист README.
- С этапа 7 каждый этап — отдельный PR в `main` (кто мержит — см. «Порядок работы»).

## Производительность и случайность (правки перед 7в)
- Линии фронтов — `Expansion.FrontCache` (`m.frontCache`): живут между тиками, `Expansion.syncCache` применяет журнал
  смен владельца `Grid.ownerLog` (пары клетка, прежний владелец; `Grid.setCity` двигает `cityEpoch` — кеш строится
  заново), `Expansion.line` отдаёт линию, `pruneCache` убирает ненужные. Тест `FrontCache.spec` сверяет кеш со свежим
  `Expansion.frontier`. Шум границы — один раз на клетку (`borderNoise`). Горячие модули — `--!native`.
- Случайные числа по системам: `m.rng` — только расстановка; `m.councilRng`, `m.stabilityRng`; бой — `battleRng`
  (поток на пару атакующий → цель); боты — `botRngsOf` (think, main, navy, air, diplo, tech, ability, missile; в `BotBrain.decide` —
  параметр `streams`). Новой механике — свой поток, не общий.
- Замер: `tools/bench_ab` (git worktree `main` в `build/`), в отчётах — только его минимум.
- Арена (`tools/bot_arena`) — инструмент для отчёта, **не проверка CI** (решение геймдизайнера): полоса против
  Генералов 2.0 < среднее место ≤ 3.5, против Новичков первый ≥ 80% партий.

## Require
Внутри `src/shared` модули подключают друг друга строкой: `require("./Types")` — так работает и в Roblox (`./` = `script.Parent`), и в Lune.
Сервер и клиент берут общие модули через `ReplicatedStorage.Shared`.
