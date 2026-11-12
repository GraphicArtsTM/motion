--!strict
--[[
	Config — единственное место для чисел баланса и технических констант.
	Источник значений: docs/GDD.md. Меняешь баланс — меняй здесь и отмечай в docs/BALANCE.md.

	Модуль чистый: без Roblox API, работает и в Studio, и в Lune-тестах.
	Все таблицы заморожены (table.freeze), чтобы код случайно не правил баланс на лету.
]]

local Types = require("./Types")

local function deepFreeze<T>(t: T): T
	local tbl = t :: any
	for _, v in tbl do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	table.freeze(tbl)
	return t
end

local Config = {}

-- Версия формата конфигурации; увеличивай при несовместимых изменениях структуры.
Config.Version = 1

-- §12 Сеть и производительность
Config.Sim = {
	TickRate = 10, -- тиков в секунду на сервере
	ServerTickBudgetMs = 25, -- бюджет тика при 60 игроках на «Мире»
	ClientTargetFps = 60,
	MaxIntentsPerSecond = 20, -- лимит намерений от одного игрока
}

-- §2 Матч
-- §15з «Часы судного дня» (идея из OpenFront, против затяжных матчей): с доли StartShare лимита времени каждые
-- WaveSec поднимается обязательная доля суши (Shares); держава (в «Командах» — команда) ниже — распадается через GraceSec.
Config.Doomsday = {
	StartShare = 0.56, -- 14-я минута из 25
	WaveSec = 90,
	Shares = { 0.02, 0.04, 0.06, 0.08, 0.10, 0.13, 0.16 },
	GraceSec = 30,
}

Config.Match = {
	MinPlayers = 2,
	MaxPlayers = 60,
	DurationMinSec = 15 * 60,
	DurationMaxSec = 30 * 60,
	BlitzDurationSec = 8 * 60,
	StartPickSec = 20, -- §6.2 фаза выбора точки старта
	LobbySec = 20, -- лобби перед выбором старта (этап 4в)
	-- §15ф Ф1: без голосований — режим и карта по очереди сервера (видно в карточке матча и в ожидании игроков).
	LobbyVotes = false, -- true — как раньше: голосование за режим и карту в лобби
	ModeRotation = { "Ffa", "Ffa", "Teams" }, -- режим матча — по кругу (от сида матча)
	ResultsSec = 20, -- экран результатов, потом — лобби нового матча
	TimeLimitSec = 25 * 60, -- лимит времени матча: дальше побеждает больше всех суши
	HistoryEverySec = 10, -- точка графика доли суши на экране результатов
	VictoryLandShareFfa = 0.60,
	VictoryLandShareTeams = 0.70,
	MaxAlliesFfa = 2,
	DefaultMap = "Europe", -- карта сервера, пока нет голосования (этап 8); «Пангея» — только тесты
	-- Общий множитель скорости матча: всё, что идёт в игровом времени — рост людей, фронт атак,
	-- решения ботов (дальше — армии, найм, перезарядки) — идёт в Speed раз быстрее.
	-- 1 — обычный матч, 2 — «Блиц» (GDD §5). Таймер выбора старта и часы матча — реальное время.
	Speed = 1.0,
	-- Сколько держав в матче (игроки + боты). Свободные места заполняют боты (GDD §9).
	-- Этап 2: 6 = 2 игрока + 4 бота.
	TargetNations = 6,
}

-- §5.1 Режимы (этап 8а). Правила режима — Modes.rules; база — Config.Match (каждый сам за себя).
Config.Modes = {
	-- Режим недели по номеру недели UTC (с понедельника) по кругу; «Потоп» — этап 8б.
	Weekly = { "Blitz", "Mist", "Superweapon", "CapitalHunt", "Flood" },
	WeekStartUnix = 345600, -- понедельник 1970-01-05 00:00 UTC — неделя 0
	-- Команды: держав в матче ≤ upTo — столько команд.
	TeamsBy = { { upTo = 12, teams = 2 }, { upTo = 24, teams = 3 }, { upTo = 1e9, teams = 4 } },
	TeamTaxShare = 0, -- налог на переводы своей команде (обычный — Trade.TaxShare)
	BlitzSpeed = 2, -- «Блиц»: множитель скорости поверх Match.Speed
	MistVisionMul = 0.6, -- «Мгла»: обзор ×
	CapitalHunt = { Need = 3, HoldSec = 60 }, -- «Охота на столицы»: столиц врагов, секунд удержания (часы матча)
	SoloFastSpeed = 2, -- «Против ботов»: ×2 — шагов симуляции за кадр
	-- «Дуэль» (§5.2, этап 8б): ровно столько игроков в лобби (1×1 и 2×2), ботов нет.
	Duel = { Players = { 2, 4 }, VictoryShare = 0.45, TimeLimitSec = 12 * 60, Speed = 1.5 },
}

-- §5.3 «Потоп» (этап 8в): каждые EverySec вода поднимается на ступень (StepCells «высоты» на ширине 512).
Config.Flood = {
	EverySec = 120, -- часы матча
	MaxSteps = 5, -- было 6 (сводная правка)
	StepCells = 4, -- клеток равнины от воды за ступень (холмы тонут втрое медленнее)
	-- Цена клетки по местности (×10, индексы — Types.Terrain); гор нет — горы не тонут.
	Cost = { [1] = 10, [2] = 15, [3] = 30, [5] = 10, [6] = 12, [7] = 10 },
}

-- §5.4 Частные серверы (этап 8г): списки значений настроек владельца (первое — по умолчанию, кроме отмеченных).
Config.PrivateServer = {
	Speeds = { 1, 0.5, 1.5, 2 }, -- поверх скорости режима
	StartMoney = { 4000, 2000, 8000, 16000 },
	MinNations = 2,
	BotLevels = { "Mix", "Novice", "Normal", "General" }, -- Mix — по Bots.LevelMix
}

-- §11.2 Профиль и уровни (этап 9а).
Config.Profile = {
	Version = 1,
	StoreName = "FrontirProfile_v1", -- DataStore профилей
	AutosaveSec = 60,
	LockStaleSec = 1800, -- блокировка сессии старше — сервер упал, забираем
	LockRetrySec = 3, -- чужая живая блокировка — повторить через
	LockRetries = 10, -- §15л ч.3: переход хаб → матч — хаб снимает блокировку при выходе игрока
	PurchaseLog = 50, -- сколько последних id покупок помнить (продукт не начислится дважды)
	XpBase = 300, -- опыта до 2-го уровня
	XpGrowth = 1.15, -- каждый следующий уровень — во столько раз дороже
	MaxLevel = 100,
	XpPlay = 60, -- за участие в матче
	XpPlace = { 220, 140, 90 }, -- за 1-е, 2-е, 3-е место
	XpPerCity = 4, -- за каждый город державы к концу матча
	XpWin = 120, -- бонус за победу (и совместную)
	MedalShare = 1 / 3, -- медалей — доля опыта
	PremiumXpMul = 1.1, -- Roblox Premium
	TokenEveryLevels = 2, -- жетон штаба за каждые столько уровней
	-- Генералы по уровню (§11.2); «Все генералы» — сразу.
	CommanderLevels = { Marshal = 1, Engineer = 3, Admiral = 6, Scout = 10 },
}

-- §11.1 Магазин (этап 9а). id — на сайте Roblox (0 — товар ещё не создан: кнопка «скоро»), price — Robux для подписи.
Config.Shop = {
	MaxEdge = 0.15, -- потолок платного преимущества в матче (тест сверяет каждый эффект)
	Passes = {
		HQ = { id = 0, price = 399, recruitLines = 1, incomeMul = 1.05 },
		Intel = { id = 0, price = 249, intelCostMul = 0.5, intelDurationSec = 120 },
		Vip = { id = 0, price = 299, xpMul = 1.5 },
		AllCommanders = { id = 0, price = 199 },
	},
	Boosts = {
		Mobilize = { id = 0, price = 49, garrisonShare = 0.15 },
		Loan = { id = 0, price = 39, money = 2000 },
		Research = { id = 0, price = 29 },
		Reserve = { id = 0, price = 25 },
		-- Платные части (этап 9б, §11.3).
		Guards = { id = 0, price = 59, powerShare = 0.12, minStrength = 400, xp = 3 }, -- танки 2★ (Forces.StarXp)
		Airstrike = { id = 0, price = 45, frontLoss = 0.15 }, -- по клетке; радиус — Commanders.StrikeRadius
		Squadron = { id = 0, price = 49 }, -- эсминец и транспорт у своего порта
		AirWing = { id = 0, price = 49 }, -- истребитель и бомбардировщик у своего аэродрома
	},
	Packs = {
		Recruit = { id = 0, price = 99, tokens = 3, medals = 1500, maxLevel = 10, once = true },
		Medals = { id = 0, price = 79, medals = 2000, tokens = 0 },
		Tokens = { id = 0, price = 99, tokens = 3, medals = 0 },
		-- Этап 9б (§11.3): ящики, пропуск сезона, предложение недели.
		Crate1 = { id = 0, price = 49, crates = 1, tokens = 0, medals = 0 },
		Crate5 = { id = 0, price = 199, crates = 5, tokens = 0, medals = 0 },
		SeasonPass = { id = 0, price = 499, season = true, tokens = 0, medals = 0 },
		Weekly = { id = 0, price = 149, weekly = true, tokens = 0, medals = 0 },
	},
	-- Предложение недели (§11.3): по номеру недели UTC по кругу; дешевле, чем по отдельности.
	WeeklyOffers = {
		{ stock = { Guards = 1, Airstrike = 1 }, crates = 1, tokens = 0 },
		{ stock = { Squadron = 1, AirWing = 1 }, crates = 1, tokens = 0 },
		{ stock = { Guards = 1, AirWing = 1 }, crates = 0, tokens = 2 },
		{ stock = { Airstrike = 1, Mobilize = 1 }, crates = 2, tokens = 0 },
	} :: { { stock: { [string]: number }, crates: number, tokens: number } },
}

-- §15л ч.6 Арсенал: особое оружие навсегда за медали (и от уровня), в бой — одно, раз за матч, без «Дуэли».
-- Сила — в потолке Shop.MaxEdge (тест Arsenal.spec). Порядок — как в окне.
Config.Arsenal = {
	Order = { "Reinforce", "Convoy", "HqReserve", "Barrage", "Jammer" },
	Items = {
		Reinforce = { price = 1500, level = 3, target = false, powerShare = 0.10, minStrength = 300, xp = 1 },
		Convoy = { price = 2500, level = 6, target = false, money = 2500, oil = 150 },
		HqReserve = { price = 4000, level = 10, target = false },
		Barrage = { price = 6000, level = 15, target = true, frontLoss = 0.12 }, -- радиус — Commanders.StrikeRadius
		Jammer = { price = 9000, level = 20, target = true, radius = 12, sec = 20 }, -- ПВО и ЗРК врага не работают
	} :: { [string]: { [string]: any } },
}

-- §11.4 Косметика и флаг (этап 9в): только вид, за медали, уровень или пропуск. Порядок — как в гардеробе.
Config.Cosmetics = {
	PatternMix = 0.28, -- узор: доля цвета границы державы на внутренних клетках
	Patterns = {
		{ id = "Stripes", price = 800 },
		{ id = "Checker", price = 800 },
		{ id = "Dots", price = 600 },
		{ id = "Grid", price = 1000 },
		{ id = "Waves", price = 1500 },
	},
	Captures = { -- цвет вспышки захвата (имена — палитра)
		{ id = "Gold", price = 500 },
		{ id = "Sky", price = 500 },
		{ id = "Red", price = 700 },
		{ id = "Lime", price = 700 },
		{ id = "Violet", price = 900 },
	},
	Titles = { -- price — за медали; level — за уровень; seasonTier — премиум-пропуск
		{ id = "Strategist", price = 300 },
		{ id = "Diplomat", price = 300 },
		{ id = "Seawolf", price = 400 },
		{ id = "Veteran", level = 10 },
		{ id = "Conqueror", level = 20 },
		{ id = "Legend", seasonTier = 30 },
	} :: { { id: string, price: number?, level: number?, seasonTier: number? } },
	Flag = {
		Colors = { "Red", "Gold", "White", "Sky", "Forest", "Ink", "Violet", "Orange", "Teal", "Rose", "Sea", "Lime" },
		Layouts = { "Plain", "HStripe", "VStripe", "Cross", "Diagonal", "Border" },
		Emblems = { "None", "Circle", "Diamond", "Square", "Ring", "Cross" },
		FreeParts = 2, -- первые столько раскладок и эмблем — бесплатно
		PartPrice = 400, -- остальные — за медали
	},
	VipNameColor = "Gold",
}

-- §15л Звания по уровню профиля (только вид); §15ф — ступени «Путь командира» (Ranks).
-- §15ф Путь командира: 11 ступеней «какой частью командуете», первый уровень каждой (уровень профиля 1…MaxLevel).
Config.Ranks = { Tiers = { 1, 4, 8, 13, 19, 26, 34, 44, 56, 70, 86 } }

-- §11.5 Ежедневные задания (этап 9г): PerDay из пула, награда за каждое и жетон за все за день.
Config.Quests = {
	PerDay = 3,
	AllDoneTokens = 1,
	Pool = {
		{ kind = "play", target = 2, medals = 120, xp = 150 },
		{ kind = "play", target = 4, medals = 220, xp = 300 },
		{ kind = "win", target = 1, medals = 300, xp = 350 },
		{ kind = "top3", target = 2, medals = 200, xp = 250 },
		{ kind = "cities", target = 8, medals = 180, xp = 200 }, -- городов к концу матча
		{ kind = "land", target = 15, medals = 220, xp = 250 }, -- % суши к концу матча
	},
}

-- §11.5 Таблицы лидеров (OrderedDataStore) и рейтинг дуэлей.
Config.Leaders = {
	RefreshSec = 60,
	Top = 10,
	WeeklyStore = "FrontirWeeklyWins_", -- + номер недели UTC
	DuelStore = "FrontirDuelElo",
}
Config.Elo = { Start = 1000, K = 32 }

-- §5.5 Обучение (этап 10а): игрок и боты «Новичок, Мирный», 6 шагов, награда один раз.
Config.Tutorial = {
	Nations = 3,
	ExpandMul = 3, -- шаг «Расширение»: земли во столько раз больше стартовой
	RewardTokens = 2,
	RewardMedals = 500,
	Steps = { "start", "expand", "hire", "city", "build", "alliance" },
	Map = "Scandinavia", -- обучение всегда на этой карте (сводная правка)
}

-- §11.3 Боевой пропуск сезона (этап 9б): опыт за матчи → ступени; бесплатная и премиум-дорожки (Season.reward).
Config.Season = {
	Id = 1,
	-- Конец сезона (unix UTC); 0 — без срока (решение геймдизайнера: сезон 1 без даты окончания).
	EndsUnix = 0,
	Tiers = 30,
	XpPerTier = 400,
}

-- §11.3 Ящики снабжения: веса наград (шансы видны в окне до покупки) и гарантия джекпота.
Config.Crates = {
	Pity = 10, -- не позже этого ящика подряд без джекпота — джекпот
	-- Где платные случайные награды запрещены (PolicyService): ящик за Robux → эта фиксированная награда.
	Restricted = { medals = 300, tokens = 1 },
	Table = {
		{ key = "medalsS", weight = 40, medals = 300, tokens = 0 },
		{ key = "medalsM", weight = 15, medals = 800, tokens = 0 },
		{ key = "token", weight = 20, medals = 0, tokens = 1 },
		{ key = "unit", weight = 20, medals = 0, tokens = 0 }, -- платная часть в запас (любая)
		{ key = "jackpot", weight = 5, medals = 2000, tokens = 5 },
	},
}

-- §11.3 Ежедневная награда за вход (7 дней подряд) и первая победа дня.
Config.Daily = {
	Rewards = {
		{ medals = 150, tokens = 0, crates = 0 },
		{ medals = 200, tokens = 0, crates = 0 },
		{ medals = 0, tokens = 1, crates = 0 },
		{ medals = 300, tokens = 0, crates = 0 },
		{ medals = 0, tokens = 1, crates = 0 },
		{ medals = 400, tokens = 0, crates = 0 },
		{ medals = 0, tokens = 0, crates = 1 },
	},
	FirstWinMul = 2, -- опыт за первую победу дня
}

-- §5.2 Голосование за карту (этап 8б): на экране итогов — текущая и Options − 1 случайных из пула.
Config.MapVote = {
	Options = 3,
	Pool = { "World", "Europe", "Mediterranean", "Asia", "Americas", "Africa", "Scandinavia", "Caribbean", "Oceania" },
}

-- §6.11а Разведка и скрытая мощь (правка после 8а): чужая военная мощь скрыта, разведка открывает её на время.
Config.Intel = {
	HidePower = true, -- false — мощь всех видна всем (как до правки)
	Cost = 2000, -- разведка: денег (≈ цена здания; не дёшево и не дорого)
	DurationSec = 90, -- мощь цели видна столько секунд игрового времени
	RadarEverySec = 1, -- пересчёт держав в радиусе радаров (радар — постоянная разведка)
	RadarStep = 2, -- шаг выборки клеток круга радара
	BotChance = 0.04, -- шанс за раздумье, что бот (Обычный и Генерал) разведает сильнейшего соседа
	BotMoneyMul = 3, -- …если денег не меньше стольких цен разведки
}

-- §6.2 Старт
Config.Start = {
	MinDistance = 48, -- минимальная дистанция между точками старта, клеток
	Radius = 4, -- радиус круга клеток вокруг столицы на старте
	MinCircleShare = 0.7, -- круг старта должен быть хотя бы на 70% сушей (не мыс и не островок)
	AutoPickTries = 300, -- кандидатов при автоматическом выборе старта
	MinLandmassShare = 0.08, -- автостарт — на массиве суши не меньше этой доли всей суши (не на острове)
	-- §15ф Ф1: подсказка при выборе старта — чужие столицы ближе стольких клеток (на ширину UnitsReferenceMapWidth)…
	NeighbourCells = 80,
	CalmNeighbours = 1, -- …не больше стольких — «спокойное начало», больше — «тесно»
}

-- §6.3 Люди: логистический рост, максимум зависит от территории.
Config.People = {
	Start = 600,
	BaseMax = 1500, -- максимум людей без территории
	PerCell = 6, -- +к максимуму за каждую клетку
	GrowthRate = 0.12, -- r логистической кривой, 1/с: прирост r·P·(1 − P/Max)
	MinGrowthPerSec = 2, -- чтобы держава с 0 людей могла восстановиться
	OverflowDecayPerSec = 0.1, -- если людей больше максимума (потеряли землю) — доля излишка, тающая в секунду
}

-- §6.4 Расширение границ
Config.Expansion = {
	NeutralCellCost = 1.0, -- людей за клетку нейтральной равнины (× стоимость местности)
	DefenderLossFactor = 0.5, -- защитник теряет плотность × это за каждую потерянную клетку
	FrontAdvancePerSec = 1.0, -- скорость продвижения фронта, клеток в секунду
	MaxCellsPerTick = 600, -- предел захвата одной атакой за тик (бюджет сервера)
	MaxAttacks = 4, -- одновременных атак у державы (разные цели)
	MinTroops = 5, -- меньше — атака не начинается / заканчивается
	MinPercent = 0.05, -- ползунок «Атака N%»
	MaxPercent = 1.0,
	DefaultPercent = 0.3,
	PercentStep = 0.05,
	-- Форма фронта: идёт вся граница (каждая клетка — с вероятностью по скорости), сторона клика быстрее.
	-- Плавный шум делает границу живой («языки» размером ~BorderNoiseScale клеток).
	BorderNoise = 0.6, -- разброс скорости по шуму: ×(1 ± 0.6)
	BorderNoiseScale = 14, -- размер «языков», клеток
	TouchWeight = 0.6, -- клетка с двумя нашими соседями идёт в 1.6 раза быстрее, с тремя — сразу (щель)
	NotchTouch = 3, -- клетка с таким числом наших соседей — «щель», берётся сразу
	FocusMinWeight = 0.35, -- сторона границы, отвёрнутая от точки клика, идёт хотя бы с такой долей скорости
	FocusSharpness = 2, -- насколько узко ускорение у точки клика (больше — уже)
	EnclaveMaxCells = 300, -- окружённый кусок земли до такого размера переходит к окружившему
	EnclaveRecheckTicks = 10, -- «открытый» кусок перепроверяется не чаще, чем раз в столько тиков
}

-- §9 Боты (этап 2 — простые; уровни и личности — этап 5)
Config.Bots = {
	-- Арена (tools/bot_arena, 20 партий): «игрок» — Обычный бот — против трёх ботов одного уровня.
	ArenaNoviceFirstShare = 0.8, -- против Новичков «игрок» первый хотя бы в такой доле партий
	-- Против Генералов среднее место «игрока» (из 4): хуже ArenaGeneralBestPlace (сложно, этап 5) и не хуже
	-- ArenaGeneralWorstPlace (не безнадёжно).
	ArenaGeneralBestPlace = 2.0,
	ArenaGeneralWorstPlace = 3.5,
	-- Состав матча (§9.1): уровни ботов по весам; личности — поровну случайно.
	LevelMix = { Novice = 3, Normal = 5, General = 2 },
	MaxThinksPerTick = 12, -- бюджет: столько ботов думают за тик, остальные — в следующем
	NeutralPercent = 0.35,
	MaxAttacks = 2, -- одновременно атак и фронтов (подкрепление существующего не считается)
	MaxRigs = 3, -- нефтяных вышек боту хватит
	PeaceWhenWeaker = 0.6, -- просит мира, если его сила меньше этой доли силы врага (× личность)
	ConcedeWhenWeaker = 0.35, -- …а если меньше этой доли — сразу готов отдать захваченное
	PeaceRetrySec = 20, -- повторно просит мира не чаще
	AcceptWhiteWhenWeaker = 1.0, -- соглашается на белый мир, если слабее врага (сила < его × это)
	AcceptKeepWhenWeaker = 0.7, -- отдаёт захваченное врагом, только если сильно слабее
	-- §15п: лидер для ботов — наибольшая суша к победе (своя + вассалы, §15о) от этой доли (раньше — только своя суша;
	-- 0.25 пробовали: Новички давили игрока, арена против Новичков 75% < 80%)
	StopLeaderShare = 0.35,
	LeaderSplitMax = 3, -- §15п: гарнизон лидера, воюющего с другими, бот делит на (его войн + 1), не больше чем на это
	FrontFirst = false, -- §15с: в войне без фронта открывать фронт раньше найма (Обычный, Генерал). Выключено: матч 13 мин и сильнее снежный ком
	MinInfantryShare = 0.35, -- Генерал держит хотя бы столько пехоты в войсках (лучшая оборона)
	RetreatSec = 20, -- после отмены фронта бот столько не открывает его снова (войска отдыхают дома)
	ReinforceBelowRatio = 3.0, -- Генерал подкрепляет фронт, пока перевес ниже прорыва
	SecondWarAboveRatio = 2.0, -- вторая война — только если все фронты идут с таким перевесом
	-- Денег столько — бот за одно раздумье заполняет очередь найма до числа линий (правка перед 7в-2).
	RichHireMoney = 20000,
	NoviceTanksChance = 0.2, -- Новичок нанимает танки так редко (остальное — пехота)
}

-- Уровни ботов (§9.1): насколько бот умён. Обычный — поведение ботов до этапа 5.
local botLevels: { [string]: Types.BotLevelParams } = {
	Novice = {
		thinkMinSec = 2.5,
		thinkMaxSec = 4,
		mistake = 0.3,
		smartTarget = false,
		randomTarget = true,
		counterMix = false,
		advantage = 0.7, -- лезет и на почти равного
		frontPercent = 0.4,
		cancelBelowRatio = 0,
		cancelAfterSec = 0,
		cancelUnsupplied = false,
		useFocus = false,
		buildChance = 0.12,
		buildReserve = 3000,
		hireChance = 0.3,
		hireWhenFill = 0.6,
		warHireFillMul = 1, -- §15с: пока идёт война, hireWhenFill × это (1 — как в мире)
		maxQueue = 1,
		attackWhenFill = 0.6,
		peaceAfterSec = 90,
		incomeBonus = 0,
		secondWar = false,
	},
	Normal = {
		thinkMinSec = 1,
		thinkMaxSec = 2,
		mistake = 0.1,
		smartTarget = false,
		randomTarget = false,
		counterMix = false,
		advantage = 1.0,
		frontPercent = 0.6,
		cancelBelowRatio = 0.5,
		cancelAfterSec = 20,
		cancelUnsupplied = false,
		useFocus = false,
		buildChance = 0.3,
		buildReserve = 1500,
		hireChance = 0.5,
		hireWhenFill = 0.45,
		warHireFillMul = 1, -- §15с: 0.5 пробовали — без заметного эффекта, арена «Генералы» 3.55 > 3.5
		maxQueue = 2,
		attackWhenFill = 0.45,
		peaceAfterSec = 30,
		incomeBonus = 0,
		secondWar = false,
	},
	General = {
		thinkMinSec = 0.7,
		thinkMaxSec = 1.2,
		mistake = 0,
		smartTarget = true,
		randomTarget = false,
		counterMix = true,
		advantage = 1.3,
		frontPercent = 0.7,
		cancelBelowRatio = 0.9,
		cancelAfterSec = 10,
		cancelUnsupplied = true,
		useFocus = true,
		buildChance = 0.5,
		buildReserve = 800,
		hireChance = 0.8,
		hireWhenFill = 0.35,
		warHireFillMul = 1, -- §15с: 0.5 у всех — лидер 15-й мин 33% (было 60%), но арена «Генералы» 3.8 > 3.5
		maxQueue = 4,
		attackWhenFill = 0.35,
		peaceAfterSec = 20,
		incomeBonus = 0.10, -- единственное послабление (GDD §9)
		secondWar = true,
	},
}
Config.BotLevels = botLevels

-- Личности ботов (§9.1): множители к уровню и вкусы.
local botPersonalities: { [string]: Types.BotPersonalityParams } = {
	Peaceful = {
		declare = 1.5,
		hire = 0.8,
		build = 1.5,
		front = 0.9,
		peace = 1.4,
		maxWars = 1,
		maxFactories = 3,
		distracted = 1.2,
		leader = 1.5,
		forts = true,
		alliance = 1.5, -- охота к союзам и пактам
		betray = 0, -- готовность предать союзника (0 — никогда)
		demand = 0, -- готовность требовать провинции (0 — никогда)
		loyalty = 1.2, -- вступает в войны союзника
		trade = 1.0, -- охота к торговым соглашениям (§8.2)
		navy = 0.2, -- охота к флоту и высадкам (§6.12)
		air = 0.2, -- охота к авиации (§6.13)
	},
	Aggressor = {
		declare = 0.8,
		hire = 1.4,
		build = 0.7,
		front = 1.15,
		peace = 0.6,
		maxWars = 2,
		maxFactories = 1,
		distracted = 1.2,
		leader = 1.3,
		forts = false,
		alliance = 0.6, -- охота к союзам и пактам
		betray = 0.3, -- готовность предать союзника (0 — никогда)
		demand = 1.0, -- готовность требовать провинции (0 — никогда)
		loyalty = 1.0, -- вступает в войны союзника
		trade = 0.2, -- охота к торговым соглашениям (§8.2)
		navy = 0.4, -- охота к флоту и высадкам (§6.12)
		air = 1.0, -- охота к авиации (§6.13)
	},
	Trader = {
		declare = 1.3,
		hire = 0.8,
		build = 1.6,
		front = 0.9,
		peace = 1.3,
		maxWars = 1,
		maxFactories = 5,
		distracted = 1.2,
		leader = 1.5,
		forts = true,
		alliance = 1.8, -- охота к союзам и пактам (сводная правка: было 1.3)
		betray = 0, -- готовность предать союзника (0 — никогда)
		demand = 0.3, -- готовность требовать провинции (0 — никогда)
		loyalty = 1.0, -- вступает в войны союзника
		trade = 2.0, -- охота к торговым соглашениям (§8.2)
		navy = 0.3, -- охота к флоту и высадкам (§6.12)
		air = 0.2, -- охота к авиации (§6.13)
		-- Сводная правка: Торговец тратит накопленное — при угрозе нанимает чаще, на наёмников ставит больше.
		threatHire = 2.5,
		bidShare = 2.0,
	},
	Cunning = {
		declare = 1.0,
		hire = 1.0,
		build = 1.0,
		front = 1.0,
		peace = 1.0,
		maxWars = 1,
		maxFactories = 2,
		distracted = 2.0,
		leader = 2.0,
		forts = true,
		alliance = 1.4, -- охота к союзам и пактам
		betray = 1.0, -- готовность предать союзника (0 — никогда)
		demand = 1.0, -- готовность требовать провинции (0 — никогда)
		loyalty = 0.6, -- вступает в войны союзника
		trade = 0.6, -- охота к торговым соглашениям (§8.2)
		navy = 0.4, -- охота к флоту и высадкам (§6.12)
		air = 0.6, -- охота к авиации (§6.13)
	},
	-- Флотоводец: до флота (этап 7) — как Обычный.
	Admiral = {
		declare = 1.0,
		hire = 1.0,
		build = 1.0,
		front = 1.0,
		peace = 1.0,
		maxWars = 1,
		maxFactories = 2,
		distracted = 1.2,
		leader = 1.5,
		forts = true,
		alliance = 1.0, -- охота к союзам и пактам
		betray = 0.1, -- готовность предать союзника (0 — никогда)
		demand = 0.3, -- готовность требовать провинции (0 — никогда)
		loyalty = 1.0, -- вступает в войны союзника
		trade = 0.6, -- охота к торговым соглашениям (§8.2)
		navy = 1.0, -- охота к флоту и высадкам (§6.12)
		air = 0.3, -- охота к авиации (§6.13)
	},
}
Config.BotPersonalities = botPersonalities

-- Звуки (GDD §14): id ассетов. Пусто — заглушка, звук пока не играет (ассеты — этап 10).
-- §13 Звук (этап 10б). id — «rbxassetid://…» загруженного звука (пусто — молчит, если нет Sound с этим именем в
-- SoundService/FrontirAudio). volume — громкость звука до общей громкости игрока. Файлы для загрузки —
-- assets/audio/sfx/<Имя>.wav (их делает lune run tools/sfx_gen). Как заменить — README «Звуки и музыка».
Config.Sounds = {
	Click = { id = "", volume = 0.35 }, -- нажатие кнопки
	Error = { id = "", volume = 0.4 }, -- отказ сервера
	Capture = { id = "", volume = 0.25 }, -- ваша граница растёт (не чаще Audio.Gaps.Capture)
	Province = { id = "", volume = 0.45 }, -- взят город
	Battle = { id = "", volume = 0.35 }, -- ваш фронт в бою (не чаще Audio.Gaps.Battle)
	Explosion = { id = "", volume = 0.6 }, -- удар ракеты, налёт по вам
	Plane = { id = "", volume = 0.35 }, -- ваш налёт, готовый самолёт
	Parachute = { id = "", volume = 0.5 }, -- десанты генералов
	Siren = { id = "", volume = 0.35 }, -- война или ракета против вас
	Offer = { id = "", volume = 0.5 }, -- вам предложили союз, пакт, торговлю, мир
	Betrayal = { id = "", volume = 0.45 }, -- вас предали
	Victory = { id = "", volume = 0.6 },
	Defeat = { id = "", volume = 0.55 },
	Notify = { id = "", volume = 0.45 }, -- событие, «Изучено», готовый корабль
	Coin = { id = "", volume = 0.35 }, -- покупка, награда
	Hire = { id = "", volume = 0.35 }, -- найм
	Build = { id = "", volume = 0.45 }, -- стройка
}

-- §13 Музыка (этап 10б): петли (Looped). Файлы — assets/audio/music/<Имя>.wav.
Config.Music = {
	Lobby = { id = "", volume = 0.35 }, -- лобби, выбор старта, итоги
	Calm = { id = "", volume = 0.3 }, -- игра
	Finale = { id = "", volume = 0.35 }, -- лидер близко к победе
}

Config.Audio = {
	Folder = "FrontirAudio", -- папка в SoundService: Sound с именем звука важнее id из Config
	DefaultSfx = 0.8, -- громкости игрока по умолчанию (0..1, шаг VolumeStep)
	DefaultMusic = 0.5,
	VolumeStep = 0.1,
	FadeSec = 1.5, -- смена мелодии
	FinaleMargin = 0.10, -- «Финал»: лидеру до доли для победы осталось меньше
	FinaleTimeSec = 60, -- …или до конца лимита времени меньше (секунды матча)
	Gaps = { Capture = 0.4, Battle = 3, Click = 0.05, Offer = 1, Explosion = 0.3 }, -- не чаще (секунды)
}

-- Для разработки
Config.Dev = {
	-- Язык интерфейса: "" — по языку Roblox у игрока, "ru" или "en" — принудительно
	-- (например, проверить кириллицу, когда Roblox в Studio на английском).
	ForceLang = "",
	-- Карта матча: "" — Config.Match.DefaultMap; имя из Config.RealMaps (или "Pangea" — тестовая) — эта.
	Map = "",
	-- Все боты одного уровня (§9.1): "" — по Bots.LevelMix; "Novice", "Normal" или "General".
	BotLevel = "",
	-- Режим без голосования (§5.1): "" — голосование в лобби; "Ffa", "Teams", "Blitz", "Mist", "Superweapon",
	-- "CapitalHunt" — этот.
	Mode = "",
	-- «Карта» в F4 (этап 8б) идёт по кругу Config.MapVote.Pool.
	-- Этап 8г: true — в Studio сервер считается частным, владелец — первый вошедший (§5.4).
	PrivateServer = false,
	-- Сколько держав в матче (игроки + боты): 0 — как у карты (RealMaps.<карта>.Nations).
	Nations = 0,
	-- Панель разработчика (F4, только в Studio): сколько давать и во сколько ускорять.
	GrantForces = 2000, -- силы каждого типа войск
	GrantPeople = 5000,
	GrantMoney = 50000,
	GrantOil = 2000,
	GrantTokens = 3, -- «+3 жетона» (этап 9а)
	GrantXp = 2000, -- «+опыт» (этап 9а)
	GrantMedals = 5000, -- «+медали» (этап 9в)
	FastSpeed = 5, -- «Время ×5»
	EndLeadSec = 5, -- «К концу матча»: до лимита времени остаётся столько секунд
	StabilityLow = 10, -- «Стабильность 10»: свои провинции сразу на это значение
	StabilityHigh = 100, -- «Стабильность 100»
	-- §15л ч.3: роль сервера в Studio для проверки вида — "" (как раньше: меню поверх матча), "hub" или "match".
	-- Телепорт в Studio не работает: «В БОЙ» в роли хаба покажет «Не удалось подключиться».
	Role = "",
}

-- §15л ч.4 Свой арт интерфейса (docs/ART_LIST.md, раздел «Интерфейс»): "" — рисуем кодом; "rbxassetid://…" —
-- картинка (загрузить в Creator Hub → Development Items → Decals / Images, скопировать id).
Config.Art = {
	Logo = "", -- картинка логотипа вместо встроенного (Shared.LogoArt, «WORLD CONQUER», §15л ч.5)
	LogoW = 360,
	LogoH = 72,
	LogoScale = 2, -- встроенный логотип 149×21: во столько раз крупнее в главном меню
	LobbyLogoScale = 3, -- …и на экране лобби
	MenuBackground = "", -- фон главного меню (поверх затемнённой карты)
	BackgroundAlpha = 0.35, -- прозрачность фона меню
}

-- §15л ч.5 Хаб: за меню — живая война ботов (игроки — зрители), камера сама облетает фронты.
Config.Hub = {
	DemoNations = 12, -- держав в показательном матче
	DemoSpeed = 2, -- время показательного матча идёт быстрее (войны начинаются раньше)
	DemoMaps = { "Europe", "World", "Asia", "Americas", "Africa", "Mediterranean" }, -- по кругу
	TourSec = 9, -- камера переходит к новой цели раз в столько секунд
	TourZoom = 2.4, -- зум облёта: во столько раз ближе, чем «вся карта»
	TourEase = 0.6, -- плавность перехода (доля пути в секунду)
	ShadeAlpha = 0.6, -- прозрачность затемнения за меню в хабе (в матче — Render.Menu.ShadeAlpha)
}

-- §15л ч.3 Хаб и матч — разные места одной игры (одна сборка, роль — по game.PlaceId, модуль Places).
Config.Places = {
	Hub = 4316252648, -- стартовое место: главное меню без матча
	Match = 135440328929805, -- сервер матча
	ListName = "FrontirMatches_v1", -- MemoryStore: серверы матча пишут о себе
	CodesName = "FrontirCodes_v1", -- MemoryStore: коды резервных серверов матча (только сервер)
	PublishSec = 10, -- сервер матча пишет о себе раз в
	ExpireSec = 45, -- запись живёт (сервер упал — пропадёт из списка)
	CodeExpireSec = 86400, -- код резервного сервера живёт
	ListRefreshSec = 8, -- хаб читает список раз в
	ListMax = 5, -- строк «Матчи» в меню хаба
	ReadMax = 50, -- сколько записей хаб читает
	BatchSec = 2, -- «В БОЙ» без свободных матчей: ждём столько, чтобы отправить нажавших вместе на один новый сервер
	RetrySec = 10, -- кнопка снова доступна, если переход не случился
	-- §15л ч.4 Свой матч по коду.
	CodeLength = 6,
	CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", -- без 0/O и 1/I — код легко продиктовать
	PrivateCodesName = "FrontirPrivate_v1", -- MemoryStore: код → сервер и владелец
	PrivateCodeSec = 86400, -- код живёт
	VerifyTries = 5, -- сервер матча проверяет код (запись появляется чуть позже игрока)
	VerifyWaitSec = 2,
}

-- §12 Сеть
Config.Net = {
	InfoMinSec = 0.5, -- info (державы, города, фаза) — не чаще: выбывания подряд уходят одним сообщением
	DiploMinSec = 0.5, -- договоры (diplo) рассылаются не чаще (изменения за это время — одним сообщением)
	SnapshotPartBytes = 32000, -- полный снимок сетки уходит частями не больше этого
	StatsHz = 5, -- частота рассылки статистики держав
	StabilityEverySec = 1, -- стабильность своих провинций и повстанцы (§6.10) — раз в столько секунд
	MaxStepsPerFrame = 3, -- сколько тиков сервер догоняет за кадр после подвисания
	-- Ориентир трафика сервер → клиент. В документации Roblox явного лимита нет (там только ~500 запросов/с
	-- клиент → сервер и 1000 байт на ненадёжное событие); 50 КБ/с — распространённая рекомендация сообщества.
	BudgetBytesPerSec = 50000,
}

-- §3 Рендер карты и камера
Config.Render = {
	ChunkSize = 256, -- сторона чанка EditableImage в клетках (лимит Roblox — 1024)
	-- Зум — пикселей экрана на клетку. Самый мелкий зум — «вся карта на экране» (дробный, с отступом FitMargin).
	-- От IntegerZoomFrom и выше колесо и щипок останавливаются только на целых значениях: все клетки
	-- одного размера, пиксели ровные (GDD: ×2–×12 без размытия).
	ZoomFloor = 0.5, -- абсолютный минимум зума для очень маленьких экранов
	IntegerZoomFrom = 2,
	ZoomMax = 12,
	FitMargin = 0.96, -- доля экрана, которую занимает карта в режиме «вся карта»
	WheelZoomFactor = 1.25, -- шаг колеса мыши (×), затем округление до целого от IntegerZoomFrom
	ZoomLerpPerSec = 14, -- скорость плавного зума (чем больше, тем резче)
	PanMarginPx = 48, -- насколько карту можно утащить за край экрана
	KeyPanSpeedPx = 900, -- скорость прокрутки WASD/стрелками, пикселей экрана в секунду
	CaptureFlashSec = 0.7,
	MinTouchTargetPx = 44,
	-- Вода: глубина по расстоянию до суши (в клетках).
	WaterShallowDistance = 1,
	WaterMidDistance = 4,
	DitherShare = 0.22, -- доля клеток с альтернативным оттенком местности
	SnowRadius = 3, -- снег на горе, если все клетки в этом радиусе — горы
	ProvinceBorderShade = 0.84, -- граница провинций: местность чуть темнее (тонкая, едва заметная линия)
	OwnerTint = 0.55, -- доля цвета державы поверх местности (местность просвечивает)
	-- §15х ч.8: граница державы в 2 клетки — внешняя тёмная (Nations.BorderShade), внутренняя — яркая полоса
	-- (цвет державы на столько поверх местности). BorderWidth = 1 — прежняя линия в 1 клетку.
	BorderWidth = 2,
	BorderInnerTint = 0.85,
	BuildingDotZoom = 3, -- §15х ч.8: дальше (меньше px на клетку) значок здания — точка цвета державы
	BuildingDotPx = 4,
	-- §15х ч.8: подсветки на карте (Render/MapHighlightLayer): граница с врагом, контур державы под курсором, котлы.
	MapHighlight = {
		RefreshSec = 0.5, -- пересчёт контуров в кадре
		MaxScan = 40000, -- клеток просмотра за пересчёт (шаг выборки растёт с размером кадра)
		WarDots = 220, -- меток на границе с врагом
		HoverDots = 360, -- точек контура державы под курсором
		PocketDots = 160, -- точек пунктира одного котла
		PocketMaxCells = 6000, -- клеток котла в заливке (больше — контур по найденному)
		DotMinPx = 3,
		DotScale = 0.9, -- точка — столько клеток (но не меньше DotMinPx)
		PulseHz = 1.4, -- пульс и бегущая волна
		HoverLighten = 0.7, -- контур под курсором — к белому на столько (не путать с красной границей войны)
	},
	CaptureFlashStrength = 0.6, -- насколько свежезахваченная клетка вспыхивает к белому
	NationLabelSize = 14, -- размер подписи державы на карте, px
	CaptureFlashSteps = 4, -- вспышка гаснет ступенями (пиксельный стиль и меньше перерисовок)
	TapSlopPx = 10, -- сдвиг пальца/мыши, после которого это уже не нажатие, а перетаскивание
	TapMaxSec = 0.4, -- дольше — не нажатие
	LongPressSec = 0.5, -- долгое касание без сдвига — кольцо действий (§15е)
	ActionRing = { Radius = 78, ButtonW = 128 },
	-- §15х ч.5 панель «УДАРЫ»: плитка (ширина, высота, высота картинки), доля ширины экрана — не больше.
	Strikes = { TileW = 96, TileH = 112, ArtH = 58, MaxScreenShare = 0.42 },
	-- §15х ч.4б «Карта угроз»: ширина плашки, пересчёт зон (с), радиус точки «дыры» (клеток).
	Threat = { WidthPx = 440, RefreshSec = 0.5, HoleRadius = 2 }, -- кольцо действий (§15е): радиус круга и ширина кнопки, px
	PeopleZone = { 0.35, 0.65 },
	-- §15з док снизу по центру: кнопка, отступы, масштаб значка 8×8, над карточками найма (56 px).
	-- §15з док; §15л ч.2 — вертикально слева под «≡» (LeftPx, TopPx), BottomPx — место под командную полосу.
	Dock = {
		ButtonPx = 40, -- §15ф: строка кнопок «значок · название · клавиша» сверху слева
		PadPx = 4,
		GapPx = 4,
		IconScale = 3,
		LeftPx = 64, -- правее кнопки «≡»
		TopPx = 8,
		BottomPx = 120,
		RefreshSec = 0.2,
	},
	-- §15л ч.2 командная полоса матча: высота, ширина клеток, кнопки доли атаки; полоса ужимается до MinScale
	-- и на узком экране переносится в два ряда.
	-- §15ф Ф2: панель «АТАКИ» справа (свои и на вас) и фишки своих атак над нижней полосой.
	AttackList = {
		WidthPx = 300,
		RowPx = 44,
		MaxRows = 6, -- строк в панели; остальное — «ещё N»
		MaxChips = 5, -- фишек над полосой
		ChipPx = 36,
		RefreshSec = 0.2,
	},
	CommandBar = {
		HeightPx = 76,
		SlotPx = 46,
		BottomPx = 10,
		MinScale = 0.6,
		Percents = { 0.1, 0.25, 0.35, 0.5, 0.75 },
		RefreshSec = 0.15,
	},
	Banner = { MaxPx = 110, MinPx = 36, CardPx = 78, SideCardPx = 58 }, -- §15л ч.8: картинки-шапки окон и карточек
	-- §15и экран лобби: затемнение карты, ширина карточки, место под док; «Как играть» — шаги со значками PixelIcons.
	Lobby = {
		ShadeAlpha = 0.35,
		TopPx = 60,
		WidthPx = 620, -- §15ф Ф1: карточка «Ожидание игроков»
		HeightPx = 560,
		SeatPx = 22, -- квадратик места (люди — голубые, остальные займут боты)
		SeatsMax = 24, -- больше квадратиков не рисуем (на «Мире» держав до 60)
		DockSpacePx = 24, -- §15л ч.2: док теперь слева, снизу в лобби свободно
		HelpWidthPx = 620,
		HelpSteps = {
			{ key = "start", icon = "land" },
			{ key = "expand", icon = "people" },
			{ key = "war", icon = "army" },
			{ key = "build", icon = "build" },
			{ key = "goal", icon = "money" },
			{ key = "doom", icon = "stability" },
		},
	}, -- §15е: зона лучшего роста людей (доля максимума) на столбике в полосе ресурсов
	-- §15л главное меню и меню игры: затемнение карты под меню, размеры карточек и плиток, слои окон.
	Menu = {
		ShadeAlpha = 0.45, -- прозрачность затемнения карты (0 — чёрное)
		TopBarPx = 64, -- верхняя полоса (звание, уровень, медали)
		SideCardPx = 300, -- карточки «Задания дня» и «Магазин»
		CenterCardPx = 520, -- карточка «Сейчас на сервере» (§15ф Ф1: шире)
		TilePx = 104, -- плитки снизу
		MinWidthPx = 1180, -- уже — меню ужимается масштабом
		MinHeightPx = 700,
		ColumnHeightPx = 860, -- §15ф: штабная колонка во весь рост — ниже экрана ужимается
		RankIconScale = 3, -- значок ступени 16×16 в профиле меню
		RanksColumns = 5, -- окно «Звания»: столбцов
		GameMenuWidthPx = 380, -- меню игры (≡)
		RefreshSec = 0.25, -- как часто меню перечитывает профиль и сервер
	},
	ToastSec = 3, -- сколько висит всплывающее сообщение
	MinimapSide = 200, -- мини-карта вписана в квадрат стольких пикселей (HUD v1)
	MinimapEverySec = 2, -- как часто перерисовывать мини-карту
	ResultsPlaces = 8, -- строк мест на экране результатов
	ResultsChartLines = 5, -- линий на графике доли суши (лучшие места + своя держава)
	ResultsChartPoints = 60, -- точек на линию графика (больше — прореживаем)
	FeedLines = 4, -- строк в ленте событий (GDD §10)
	FeedSec = 8, -- строка ленты исчезает через столько секунд
	AttackedFlashSec = 2.5, -- баннер войны мигает, когда на вас напали
	-- С какого зума спрайты юнитов крупнее (§15г: спрайт 12×10 — крупные и видные с общего плана).
	UnitSpriteScales = { { zoom = 2.5, scale = 2 }, { zoom = 6, scale = 3 }, { zoom = 10, scale = 4 } },
	BuildingIconScales = { { zoom = 5, scale = 2 }, { zoom = 10, scale = 3 } }, -- значки зданий 12×12 (§15д ч.4)
	-- Названия городов (§15д ч.4): крупные (с этого уровня) — всегда, остальные — с зума CityLabelZoom.
	CityScales = { { zoom = 2.5, scale = 2 }, { zoom = 7, scale = 3 } }, -- пиксель-арт города (§15д ч.4)
	ResourceLerpPerSec = 8, -- полоса ресурсов (§15д ч.5): скорость «бегущих» чисел
	ResourceFlashMin = 200, -- вспышка плашки — изменение не меньше (и не меньше 5% значения)
	CityLabelZoom = 2.5,
	CityLabelBigLevel = 3,
	CityLabelSize = 11, -- + 2 за каждый уровень города
	CityLabelMax = 80,
	-- Тени облаков над картой (§15г): размеры в клетках для ширины карты 512, ветер — клеток в секунду.
	Clouds = {
		Count = 7,
		PhoneCount = 3,
		MinSize = 40,
		MaxSize = 90,
		Transparency = 0.86,
		Wind = { 2.2, 0.6 },
	},
	FrontScanSec = 0.5, -- как часто клиент пересчитывает линию фронта
	-- Бой на линии фронта (GDD §6.7б). Всё из пулов; пределы — чтобы телефон держал 60 FPS.
	Battle = {
		NoMansLand = 4, -- клеток ничейной полосы между войсками сторон (2–4)
		ArtilleryBack = 6, -- артиллерия стоит в стольких клетках позади границы
		StrengthPerUnit = 150, -- один юнит на экране ≈ столько силы
		MaxUnitsPerFront = 20, -- юнитов одной стороны на фронте (§15г: было 28 — крупные спрайты не сливаются)
		MaxUnitsOnScreen = 180, -- всего юнитов на экране
		UnitMoveCellsPerSec = 3, -- скорость, с которой юнит идёт к своему месту
		ReinforceFromCells = 5, -- подкрепление выходит из тыла с такого расстояния
		InfantryAdvance = 0.8, -- клеток: пехота сходится к полосе и отходит
		TankAdvance = 1.3, -- клеток: танки выезжают вперёд
		ArtilleryFireMinSec = 2, -- залп артиллерии раз в 2–4 с
		ArtilleryFireMaxSec = 4,
		ShellFlightSec = 1.1, -- полёт снаряда
		ShellArc = 0.35, -- высота дуги в долях дальности
		RifleFlashesPerSec = 8, -- вспышек выстрелов в секунду на фронте с боем
		CraterSec = 20, -- воронка и дым держатся столько
		MaxCraters = 60,
		SmokeEverySec = 0.9, -- воронка дымит раз в столько секунд
		SmokeLifeSec = 2.6,
		MaxParticles = 220, -- искры, дым, вспышки, разрывы — все вместе
		DeathSparks = 7, -- пикселей в разлёте при гибели юнита
		ChurnMul = 1.0, -- сколько юнитов гибнет на экране за долю потерь (визуально)
	},
	NarrowScreenPx = 1160, -- уже — раскладка HUD для телефона (карточки найма в две строки слева от мини-карты)
	-- Телефон (касание без клавиатуры, этап 10в): меньше эффектов, чтобы держать 60 FPS (RenderBudget).
	Phone = {
		MaxUnitsOnScreen = 90,
		MaxParticles = 100,
		MaxStrikeParts = 110, -- §15х ч.7: частиц ударов
		WarDots = 80, -- §15х ч.8
		HoverDots = 140,
		PocketDots = 60,
		MaxCraters = 30,
		SparkleMax = 16,
		-- Зрелищная война (§15б) на телефоне — меньше.
		BorderSparks = 24,
		MaxArrows = 10,
		MaxCaptureFlashes = 40,
		MaxBadges = 4, -- §15м: плашек перевеса
		MaxRings = 4, -- §15м: колец захвата городов
		FireworkSparks = 10,
	},
	-- §15м живой фронт и зрелищный матч: плашки перевеса, «ПРОРЫВ!», захват городов, выбывание, корона, тряска.
	BattleFx = {
		BadgeScanSec = 0.5, -- пересчёт мест плашек над фронтами
		BadgeEasePerSec = 5, -- число на плашке догоняет перевес (доля разницы в секунду)
		BadgeMoveEasePerSec = 4, -- плашка плавно едет за фронтом
		MaxBadges = 8,
		BadgeMaxShown = 8, -- больше — «×8+»
		BreakthroughSec = 1.6, -- всплывающее «ПРОРЫВ!»
		CityRingSec = 1.1, -- ударное кольцо при захвате города
		CityRingCells = 9, -- радиус кольца в клетках
		CityTextSec = 1.9, -- «+ Город» / «− Город»
		MaxRings = 10,
		ElimSec = 2.6, -- баннер «X выбывает»
		FireworkSec = 1.8, -- салют над местом последнего города
		FireworkSparks = 28,
		FireworkCells = 7, -- разлёт салюта, клеток
		CrownPx = 3, -- пиксель короны сверхдержавы (корона 7×5 пикселей)
		CrownFromGiant = 0.5, -- корона — когда бонус «Сверхдержава» от половины
	},
	-- §15х ч.7: зрелищные удары и разрушения (план — StrikeFx, рисует Render/StrikeFxLayer). Время — в секундах,
	-- размеры — в клетках карты.
	StrikeFx = {
		MaxParts = 260, -- частиц ударов на экране (на телефоне — Phone.MaxStrikeParts)
		JetCount = 3, -- звено штурмовиков авиаудара
		JetSec = 1.1, -- проход звена над целью
		JetSize = 4.6, -- размер самолёта (клеток; на экране не меньше JetMinPx)
		JetSpacing = 1.25, -- расстояние между дорожками звена (в размерах самолёта; не шире 0.8 радиуса)
		CarpetPerLane = 6, -- разрывов на дорожку ковра (дорожек — по самолётам)
		BurstSec = 0.55, -- разрыв бомбы: вспышка и огненный шар
		BurstSize = 3.4,
		JetMinPx = 22, -- самолёт звена на экране не меньше (px)
		BurstMinPx = 8, -- разрыв, вспышка, пожар — не меньше (px)
		DustSec = 1.6, -- пыль после разрыва
		ScarSec = 12, -- воронки и копоть на земле
		ScarNukeSec = { atom = 25, hydrogen = 40 }, -- выжженная земля
		ScarsPerRadius = 1.4, -- воронок на клетку радиуса (не больше MaxScars)
		MaxScars = 18,
		FireSec = 8, -- пожар и дым над задетым зданием
		MaxFires = 12,
		SmokeEverySec = 0.45, -- клуб дыма от пожара
		DebrisPerRadius = 1.2, -- обломков на клетку радиуса (не больше MaxDebris)
		MaxDebris = 22,
		DebrisSec = 1.2,
		DebrisReach = 1.6, -- обломки летят на столько радиусов
		EmbersPerRadius = 0.5, -- тлеющие угли на выжженной земле
		MaxEmbers = 24,
		WaveSec = { 0.9, 2.0 }, -- ядерные волны: быстрая белая и медленная огненная
		WaveReach = { 2.4, 1.6 }, -- радиус волн в радиусах удара
		InterceptRingSec = 0.7,
		InterceptRingSize = 9,
		ShakePx = { airstrike = 3, raid = 3, missile = 5, atom = 10, hydrogen = 14 },
	},
	Shake = {
		NukePx = 10, -- ядерный взрыв в кадре
		CapitalPx = 7, -- потеря своей столицы
		Sec = 0.55,
		Hz = 22, -- частота дрожи
		PhoneMul = 0.5,
	},
	-- Зрелищная война (§15б): баннер войны, вспышка общей границы, виньетка, стрелки наступления, вспышки захвата.
	WarFx = {
		BannerSec = 2.6, -- крупный баннер (война касается вас или союзника)
		BannerSmallSec = 1.8, -- малый (чужая война)
		BannerFadeSec = 0.35, -- появление и исчезновение
		BorderFlashSec = 3.0, -- искры на общей границе
		BorderSparks = 60, -- искр не больше (по всей границе, равномерно)
		BorderStride = 2, -- шаг поиска границы, клеток
		VignetteSec = 2.2, -- красные края экрана, когда война против вас
		ArrowScanSec = 0.5, -- пересчёт стрелок наступления
		ArrowStride = 2,
		MaxArrowsPerFront = 3,
		ArrowMinCells = 10, -- кусок линии фронта на одну стрелку (клеток выборки)
		MaxArrows = 24, -- стрелок на экране
		ArrowChevrons = 3, -- шевронов в стрелке
		ArrowLengthCells = 10, -- длина стрелки в клетках…
		ArrowMinPx = 36, -- …но не короче (px)
		ArrowCycleSec = 1.2, -- шевроны пробегают стрелку за столько секунд (победа — вдвое быстрее)
		-- §15у ч.2: стрелка отряда через союзника — пунктир от своей границы до места выхода и метка «>»
		PassageDotCells = 3, -- точка пунктира через столько клеток…
		PassageMaxDots = 28, -- …но не больше стольких точек
		PassageDotScale = 1.4, -- размер точки (клеток)…
		PassageDotMinPx = 7, -- …но не меньше (px)
		PassageHeadPx = 28, -- метка «>» (px)
		PassageKeepSec = 2, -- стрелка держится после расчётного прибытия, если событие прибытия не пришло
		CaptureFlashSec = 0.6,
		MaxCaptureFlashes = 120, -- вспышек захвата одновременно
		CaptureFlashPerDelta = 30, -- из одной дельты — не больше
		FloatSec = 1.6, -- «+$» над портом, куда доплыло торговое судно (§15е)
		MaxFloats = 12,
		-- §15ж: полёт ракеты и взрывы.
		RocketArc = 0.35, -- высота дуги в долях расстояния
		SmokeEverySec = 0.05, -- дымный след
		SmokeSec = 1.2,
		MaxSmoke = 80,
		BlastSec = 1.3, -- огненный шар и ударная волна
		ShockwaveMul = 2.2, -- ударная волна — во столько радиусов удара
		MushroomSec = 3.5, -- «гриб» над ядерным взрывом
		FlashSec = 0.7, -- вспышка экрана при ядерном взрыве
		EmojiSec = 3, -- эмодзи над столицей
		EmojiSize = 34,
		InterceptSec = 0.7, -- §15з: полёт перехватчика от ЗРК / батареи к ракете
	},
	-- Блики воды — отдельные пиксели поверх карты, текстуру не перерисовываем.
	SparkleMax = 48,
	SparklesPerSec = 24,
	SparkleLifeSec = 0.9,
	SparkleMinDepth = 2, -- блики только там, где до суши не меньше N клеток
	DebugRefreshSec = 0.25, -- частота обновления окна F3
	-- Туман (§6.11): вне обзора клетка смешивается с цветом палитры FogColor на эту долю.
	FogColor = "Ink",
	FogDarken = 0.25, -- было 0.5 (7а); после 7г туман только намекает на обзор
	-- Повстанцы (§6.10): ничья земля их провинции — штриховка цветом RebelColor (каждая RebelHatch-я диагональ).
	RebelColor = "Red",
	RebelHatch = 4,
	RebelHatchMix = 0.6,
	-- Режим карты «Стабильность» (N): свои провинции цветом от красного (0) через золотой (50) к зелёному (100).
	StabilityColors = { "Red", "Gold", "Lime" },
	StabilityTint = 0.75, -- доля этого цвета поверх местности (вместо цвета державы)
	StabilityLabelZoom = 4, -- числа стабильности на провинциях — с этого зума
	-- Шрифт интерфейса (сводная правка, часть 3 — решает геймдизайнер): "RobotoMono" — как сейчас; "Arcade" —
	-- пиксельный шрифт Roblox (вариант А); вариант Б — свой bitmap 5×7, превью docs/previews/font-pixel.png.
	UiFont = "RobotoMono", -- запасной шрифт (Enum), если UiFontFamily пустое
	UiFontFamily = "rbxasset://fonts/families/Montserrat.json", -- §15ф Ф1: читаемый шрифт с кириллицей
	ProvinceNameZoom = 6, -- названия провинций на карте — с этого зума (сводная правка)
	ProvinceNameMax = 80, -- не больше стольких названий на экране
	PlaneShadow = 3, -- тень летящего самолёта ниже и правее на столько пикселей спрайта (§6.13)
	-- Видимость авиации (§6.13): самолёт не мельче этого на экране при любом зуме, вспышки бомб, падение сбитого.
	Air = {
		MinPlanePx = 16, -- ширина спрайта самолёта на экране не меньше
		FlashLifeSec = 0.45, -- одна вспышка: растёт и гаснет
		FlashPx = 10, -- размер вспышки при зуме ×1 (растёт с зумом)
		FallSec = 1.4, -- сбитый самолёт падает столько секунд…
		FallCells = 3, -- …на столько клеток вниз, крутясь
		ExplosionSec = 0.6, -- взрыв в конце падения
		MaxEffects = 80, -- одновременно на экране (телефон)
	},
}

-- §6.1 Местность. Порядок id фиксирован форматом карты, не переставлять.
local terrain: { [Types.TerrainId]: Types.TerrainStats } = {
	[Types.Terrain.Water] = { captureCost = 0, defense = 0, armySpeed = 0, borderPassable = false },
	[Types.Terrain.Plains] = { captureCost = 1.0, defense = 1.0, armySpeed = 1.0, borderPassable = true },
	[Types.Terrain.Forest] = { captureCost = 1.3, defense = 1.2, armySpeed = 0.8, borderPassable = true },
	[Types.Terrain.Hills] = { captureCost = 1.5, defense = 1.3, armySpeed = 0.7, borderPassable = true },
	[Types.Terrain.Mountains] = { captureCost = 2.5, defense = 1.8, armySpeed = 0.45, borderPassable = true },
	[Types.Terrain.Desert] = { captureCost = 1.2, defense = 0.9, armySpeed = 0.85, borderPassable = true },
	[Types.Terrain.Tundra] = { captureCost = 1.4, defense = 1.0, armySpeed = 0.75, borderPassable = true },
	[Types.Terrain.River] = { captureCost = 0, defense = 1.0, armySpeed = 0.5, borderPassable = false },
}
Config.Terrain = terrain

-- §7 Юниты. Скорость в клетках/с для эталонной ширины карты UnitsReferenceMapWidth.
Config.UnitsReferenceMapWidth = 512
local units: Types.UnitTable = {
	-- people / recruitSec / strength — найм стоит людей (деньги и нефть — этап 4, cost и oil).
	-- speed — темп фронта относительно пехоты (§7); attack/defense — сила в бою на фронте (§6.7).
	Infantry = {
		cost = 1000,
		oil = 0,
		speed = 2.4,
		attack = 1.0,
		defense = 1.2,
		requires = nil,
		people = 300,
		recruitSec = 3,
		strength = 300,
	},
	Tanks = {
		cost = 2500,
		oil = 20,
		speed = 3.6,
		attack = 1.6,
		defense = 1.0,
		requires = "Barracks", -- §15д: Казармы ур. requiresLevel (было — Завод)
		requiresLevel = 2,
		people = 450,
		recruitSec = 5,
		strength = 300,
	},
	Artillery = {
		cost = 3000,
		oil = 10,
		speed = 1.8,
		attack = 1.4,
		defense = 0.6,
		range = 4,
		requires = "Barracks",
		requiresLevel = 2,
		people = 400,
		recruitSec = 6,
		strength = 250,
	},
	AntiAir = {
		cost = 2000,
		oil = 5,
		speed = 2.0,
		attack = 0.6,
		defense = 1.0,
		requires = "Barracks",
		requiresLevel = 3,
		people = 300,
		recruitSec = 4,
		strength = 200,
	},
	Transport = {
		cost = 1500,
		oil = 10,
		speed = 4.0,
		attack = 0,
		defense = 0.5,
		requires = "Port",
		people = 100,
		recruitSec = 8,
		strength = 100,
	},
	Destroyer = {
		cost = 3500,
		oil = 25,
		speed = 4.5,
		attack = 1.4,
		defense = 1.2,
		requires = "Port",
		people = 300,
		recruitSec = 12,
		strength = 300,
	},
	Fighter = {
		cost = 4000,
		oil = 20, -- правка после PR #16: было 30 (ботам не хватало нефти на авиацию)
		speed = 7.0,
		attack = 1.2,
		defense = 1.0,
		requires = "Airfield",
		people = 150,
		recruitSec = 12,
		strength = 150,
	},
	Bomber = {
		cost = 5000,
		oil = 25, -- правка после PR #16: было 40
		speed = 5.0,
		attack = 2.0,
		defense = 0.6,
		requires = "Airfield",
		people = 200,
		recruitSec = 15,
		strength = 200,
	},
}
Config.Units = units

-- §6.6 Войска и фронты
Config.Forces = {
	MaxQueue = 10, -- юнитов в очереди найма (было 5; с линиями найма — до MaxRecruitLines одновременно)
	-- Линии найма (правка перед 7в-2): юниты в начале очереди готовятся параллельно — одна линия, по одной
	-- на каждый свой завод и на каждые CityLevelsPerLine уровней своих городов, не больше MaxRecruitLines.
	-- Иначе большая держава не может потратить доход на войска.
	CityLevelsPerLine = 12,
	MaxRecruitLines = 8,
	MinFrontStrength = 50, -- меньше войск — фронт против державы не открыть
}

-- §6.7 Бой на фронте
Config.Combat = {
	DamageSpread = 0.40, -- случайный разброс урона ±40%
	LossRate = 0.02, -- урона в секунду на единицу силы противника
	FrontSpeedMul = 0.25, -- фронт против державы идёт медленнее, чем экспансия на ничью землю (0.5 → 0.3 сводная правка, → 0.25 §15б: «Первый удар» и события ускорили войны)
	-- «Первый удар» (§15б): объявивший войну первые OpeningSec после мобилизации наступает быстрее.
	OpeningSec = 20,
	OpeningSpeedMul = 1.4,
	FullSpeedRatio = 2.0, -- при таком перевесе фронт идёт с полной скоростью; при 1 — стоит
	BreakthroughRatio = 3.0, -- прорыв: перевес от этого числа (золотые стрелки, «ПРОРЫВ!»)
	-- §15м: скорость фронта — плавная кривая перевеса { перевес, скорость }, между точками — по прямой,
	-- после последней — как последняя (насыщение). Было: ×1→×2 по прямой до 1, от ×3 — ступенька ×1.5.
	SpeedCurve = {
		{ 1.0, 0 },
		{ 1.5, 0.45 },
		{ 2.0, 1.0 },
		{ 3.0, 1.6 },
		{ 5.0, 2.3 },
		{ 8.0, 2.8 },
	} :: { { number } },
	-- §15м «Сверхдержава»: доля державы во всей захватываемой суше; бонус плавно растёт от FromShare до FullShare.
	Giant = {
		FromShare = 0.10,
		FullShare = 0.35,
		AttackerSpeedMax = 1.4, -- её фронт идёт быстрее
		AttackerLossMin = 0.75, -- её войска на атаке теряют меньше (× потерь)
		DefenderSpeedMax = 1.25, -- фронты против неё идут быстрее
	},
	DefenderHomeBonus = 1.25, -- защитник на своей земле сильнее
	CityCaptureRatio = 1.5, -- город державы фронт берёт только при таком перевесе
	NeutralCityGarrison = 300, -- силы теряют войска, беря ничейный город
	CounterBonus = 1.3, -- контр-тип (камень-ножницы-бумага)
	ArtilleryLossMul = 0.5, -- артиллерия бьёт издалека и теряет меньше
	MaxVeteranStars = 3,
	VeteranStarBonus = 0.30, -- +30% к силе и скорости фронта за звезду
	StarXp = { 1, 3, 6 }, -- опыт для звёзд: нанесённый урон в «своих силах»
	SupplyRange = 60, -- клеток от своих городов на карте шириной 512 (масштабируется)
	SupplySamples = 24, -- сколько клеток фронта проверять на снабжение
	OutOfSupplyLossPerSec = 0.02, -- без снабжения войска фронта теряют 2% силы в секунду
	UnsuppliedPowerMul = 0.7, -- …и бьют на 30% слабее
	RiverCrossCost = 3.0, -- фронт за рекой идёт втрое медленнее (граница людей реку не переходит)
	RiverBankDefense = 1.5, -- защитник на берегу реки: +50% к обороне
	RiverMaxWidth = 3, -- реку шире стольких клеток фронт не переходит
}

-- §6.7а Война и мир
Config.War = {
	MobilizationSec = 5, -- от объявления до начала боёв (§15з: было 15 — война начинается почти сразу)
	PeaceCooldownSec = 60, -- после мира пара не может снова объявить войну
	PeaceReplySec = 20, -- сколько ждать ответа на предложение мира
	BotReplyDelaySec = 2, -- бот отвечает на предложение мира через столько секунд
	WearinessAfterSec = 300, -- через 5 минут войны — усталость
	WearinessPenalty = 0.25, -- −25% к приросту людей…
	WearinessPenaltyPerMin = 0.05, -- …и ещё −5% за каждую следующую минуту
	WearinessMaxPenalty = 0.5, -- но не больше −50%
}

-- §8.1 Договоры (этап 6а)
Config.Diplomacy = {
	OfferSec = 20, -- сколько ждать ответа на предложение пакта, союза или требование
	PactMinutes = { 3, 5 }, -- сроки пакта о ненападении
	BreakWarningSec = 15, -- «Разорвать»: договор кончается через столько секунд
	TraitorSec = 300, -- метка «Предатель»
	CapitulateBelow = 1 / 3, -- капитулировать можно, если войск меньше этой доли от врага
	VassalTribute = 0.20, -- доля дохода вассала сюзерену
	VassalVictoryShare = 0.5, -- §15о: суша вассала идёт в победу сюзерена с таким весом (замер: вассалы разгоняли матч)
	VassalRebelSec = 300, -- через столько вассал может объявить независимость
	HistorySize = 12, -- записей в истории договоров
	OfferRetrySec = 30, -- повторно предложить то же той же державе можно не раньше
	-- Боты (§8.1): чего и когда
	DemandYieldBelow = 0.4, -- бот отдаёт провинцию, если его войск меньше этой доли от требующего
	DemandAdvantage = 2.5, -- бот требует провинцию, если сильнее соседа во столько раз
	AllyStrongerShare = 0.8, -- бот берёт в союз того, кто не слабее этой доли его самого
	PactAgainstStronger = 1.2, -- бот предлагает пакт соседу, который сильнее во столько раз, пока воюет с другим
	BetrayAdvantage = 2.0, -- Хитрец предаёт союзника-соседа, если сильнее его во столько раз
	BetrayLossShare = 1 / 3, -- партнёр «ослаб»: воюет с другим и потерял больше этой доли войск…
	BetrayWeakenedAdvantage = 1.0, -- …тогда Хитрецу хватает войск не меньше обороны партнёра…
	BetrayWeakenedChance = 0.5, -- …с такой вероятностью за раздумье (× betray личности)
	OpportunistBetray = 0.5, -- ловят «удобный момент» только личности с betray не меньше (Хитрец)
	RebelAbove = 0.8, -- вассал объявляет независимость, если у него войск не меньше этой доли от сюзерена
	OfferChance = 0.15, -- вероятность за раздумье заняться дипломатией (× личность)
}

-- §15у Два уровня союза: полное доверие и удар через союзника.
Config.Alliance = {
	TrustAfterSec = 60, -- полное доверие можно предложить, когда союз длится столько игровых секунд
	PassageCellsPerSec = 6, -- войска идут через землю союзника (клеток в секунду на ширину UnitsReferenceMapWidth)
	PassageMinSec = 4, -- не быстрее…
	PassageMaxSec = 30, -- …и не дольше
	PassageBeachhead = 3, -- плацдарм на земле врага при выходе (радиус, клеток)
	MaxPassages = 2, -- отрядов в пути у державы одновременно
	SearchCells = 96, -- место выхода ищется не дальше стольких клеток от точки удара (на ширину UnitsReferenceMapWidth)
	EntrySearchMul = 3, -- подсказка клиента: свою клетку у союзника ищет не дальше SearchCells × столько от выхода
	BotTrustLoyalty = 1.0, -- бот предлагает и принимает полное доверие, если loyalty личности не меньше…
	BotTrustChance = 0.4, -- …с такой вероятностью за раздумье о дипломатии
}

-- §8.2 Торговля, Совет держав, пинги (этап 6б)
-- §15е Торговые суда (идея жанра из OpenFront): свой порт сам отправляет судно в порт другой державы у того же моря.
Config.TradeShips = {
	EverySec = 25, -- каждый свой порт — раз в столько игровых секунд
	MaxPerNation = 3, -- судов в пути у державы
	BaseMoney = 200, -- доставка: деньги обоим…
	PerCellMoney = 2, -- …+ за клетку расстояния между причалами (на ширину UnitsReferenceMapWidth)
	AgreementMul = 1.5, -- с торговым соглашением
	PiracyShare = 0.5, -- эсминец врага топит судно и забирает эту долю груза
	Hp = 60,
	-- Судно не нанимается: цена и люди не нужны; скорость и защита — как у кораблей (Units.*).
	Stats = {
		cost = 0,
		oil = 0,
		speed = 4.5,
		attack = 0,
		defense = 0.4,
		requires = "Port",
		people = 0,
		recruitSec = 0,
		strength = 0,
	},
}

Config.Trade = {
	TaxShare = 0.10, -- налог на перевод (сгорает)
	-- Лимит отправки за скользящую минуту (против прокачки через вторые аккаунты).
	LimitPerMinute = { money = 20000, oil = 400, people = 3000 },
	QuickAmounts = { money = 1000, oil = 50, people = 300 }, -- кнопки быстрых переводов в окне дипломатии
	AgreementIncome = 0.05, -- торговое соглашение: +5% дохода обоим
	MaxAgreements = 3,
	-- Боты
	BotGiftReserve = 6000, -- бот переводит союзнику в войне, если денег больше этого
	BotGiftShare = 0.25, -- …такую долю излишка
}

Config.Council = {
	EverySec = 360, -- Совет собирается каждые 6 минут (первый — через 6 минут)
	VoteSec = 30,
	Options = 3, -- резолюций на голосовании
	-- Пул резолюций; «Запрет супероружия» добавится с ракетной шахтой (этап 7).
	Pool = { "sanctions", "truce", "aid", "freeTrade", "superweaponBan" }, -- запрет — с ракетной шахтой (этап 7г)
	SanctionsIncomeMul = 0.75, -- санкции против лидера: −25% дохода…
	SanctionsSec = 120, -- …на 2 минуты
	TruceSec = 60, -- всеобщее перемирие
	AidMoney = 5000, -- помощь слабым: каждому из трёх последних
	AidCount = 3,
	FreeTradeSec = 180, -- переводы без налога
	SuperweaponBanSec = 180,
}

Config.Pings = {
	Phrases = { "help", "attack", "alliance", "thanks", "traitor" },
	ShowSec = 6, -- метка на карте
	CooldownSec = 2, -- не чаще (на державу)
}

-- Контр-типы: кто против кого силён (GDD §6.7). Индексы — Types.LandUnits.
Config.Counters = {
	Infantry = { "Artillery", "AntiAir" },
	Tanks = { "Infantry" },
	Artillery = { "Tanks" },
	AntiAir = {},
}

-- §6.9 Здания (цены в деньгах)
Config.Buildings = {
	-- Город: улучшение своего города до ур. 2 стоит cost, до ур. 3 — upgradeCosts[1].
	City = { cost = 2000, upgradeCosts = { 4000, 7000, 11000 } }, -- §15д ч.4: ур. до 5
	-- §15д: maxLevel — до какого уровня здание улучшается (нет — только ур. 1).
	OilRig = { cost = 1500, maxLevel = 2, oilByLevel = { 1, 1.8 } }, -- нефть × (Oil.PerRigPerSec)
	Port = { cost = 2500 },
	-- §15д: деньги в секунду за уровень (было — найм); §15х ч.6: ур. bonusLevel — ещё +incomeBonus ко всему доходу
	-- (бывший «Рынок»).
	Factory = { cost = 3000, maxLevel = 3, income = 15, bonusLevel = 3, incomeBonus = 0.05 },
	Barracks = { cost = 2000, maxLevel = 3, recruitSpeedBonus = 0.15 }, -- §15д: линия найма за уровень; ур. 3 — найм быстрее
	Housing = { cost = 2000, maxLevel = 3, people = 500 }, -- §15д: + к максимуму людей за уровень
	Airfield = { cost = 3500 }, -- §15х ч.6: видит силу врага в круге Fog.RadarVision (бывший «Радар»)
	Fort = { cost = 1500, maxLevel = 2, defenseMultiplier = 1.5, defenseByLevel = { 1.5, 1.8 } },
	-- §15х ч.6: ПВО ур. 1–2 — ближняя (radius клеток): налёты, ракеты, боеголовки; ур. longRangeLevel — ещё и дальняя
	-- против ракет и боеголовок (longRadius на ширину 512, бывший ЗРК). upgradeMul — цена уровня L = cost × это.
	AirDefense = {
		cost = 2000,
		radius = 14,
		maxLevel = 3,
		longRangeLevel = 3,
		longRadius = 40,
		upgradeMul = { 1.0, 1.0, 2.5 },
	},
	MissileSilo = { cost = 10000, oil = 200, strikeRadius = 6, cooldownSec = 240, warningSec = 10 }, -- радиус ракеты — постоянный (§15р)
}

-- Подсказки «что делать дальше» (§15д ч.5, Shared.Hints).
-- §15т: лента событий по важности (EventFeed): сколько секунд держится строка каждого уровня.
Config.Feed = {
	CriticalSec = 12, -- по вам: война, удар, высадка, предательство
	ImportantSec = 8, -- касается вас или союзников, большие события мира
	BackgroundSec = 4, -- чужие дела и своя рутина
}

Config.Hints = {
	EarlySec = 240, -- «расширяйтесь» — только в начале матча
	ExpandFill = 0.5, -- …когда людей не меньше этой доли максимума и атак нет
	FewTroops = 1500, -- «нанимайте» — войск дома меньше
	WarAfterSec = 360, -- «можно воевать» — не раньше
	WarTroops = 6000, -- …и войск не меньше
	ShowEverySec = 1, -- пересчёт подсказки
	BombedSec = 60, -- «вас бомбят» — столько секунд после налёта
}

-- Удары и защита (§15д ч.3): без случайности.
Config.Defense = {
	ChargesPerLevel = 1, -- батарея ПВО ур. N — N зарядов; каждый перехватывает один удар (налёт или ракету)
	NetworkBonus = 1, -- «Сеть ПВО» (Флот-4): + столько зарядов каждой батарее
	RechargeSec = 30, -- потраченный заряд восстанавливается за столько секунд
	ProtectSec = 30, -- после удара по городу или зданию столько секунд следующий удар уровень не снимает
	HitDisableSec = 60, -- здание ур. 1 после удара выключено на столько (не разрушается)
}

-- Стройка на любой своей клетке (§15г).
Config.Build = {
	MinGap = 3, -- не ближе стольких клеток (по большей оси) к другому зданию и городу
	GhostEveryMs = 50, -- «призрак» под курсором пересчитывается не чаще
	PopSec = 0.45, -- новое здание «вырастает» за столько секунд
	DustPuffs = 10, -- пыль при постройке
	CostFloatSec = 1.4, -- «−$цена» всплывает и гаснет
	-- Экономика 2.0 (§15д): без ограничения числа зданий — баланс ценой.
	CostStep = 0.25, -- каждое следующее здание того же типа (уровни считаются) дороже на столько
	UpgradeMul = { 1.0, 1.0, 1.5 }, -- цена уровня L = cost × UpgradeMul[L] (ур. 1 — постройка)
	UpkeepShare = 0.0005, -- содержание здания: cost × это в секунду за уровень
	DistrictRadius = 6, -- район города: здание не дальше стольких клеток от своего города…
	DistrictPerCityLevel = 0.10, -- …работает сильнее на столько за уровень города
	DemolishRefund = 0.5, -- снос: доля цены назад
	DemolishFrontCells = 8, -- снос нельзя, если земля врага в войне ближе стольких клеток
	DemolishAfterHitSec = 30, -- …и если по зданию ударили меньше стольких секунд назад
}

-- Что можно строить сейчас (этап 4б; радар — 7а, порт — 7б-1, аэродром и батарея ПВО — 7б-2); шахта — этап 7г.
Config.Buildable = {
	"City",
	"Barracks",
	"Factory",
	"Housing",
	"OilRig",
	"Fort",
	"Port",
	"Airfield",
	"AirDefense",
	"MissileSilo",
}

-- §6.9 Ракетный удар (этап 7г). Радиус, перезарядка и предупреждение — Buildings.MissileSilo.
-- §15ж Ядерные боеголовки шахты (идея жанра из OpenFront). Радиус — в клетках на ширину UnitsReferenceMapWidth.
Config.Nukes = {
	Atom = {
		cost = 12000,
		oil = 300,
		radius = 14, -- прежний радиус (ref 512) — основа пределов §15р
		area = 0.055, -- §15р: круг ≈ эта доля средней живой державы (калибровка: «Европа» — как было)
		warningSec = 15,
		charges = 2, -- столько зарядов ПВО нужно, чтобы сбить
		falloutSec = 60, -- заражённая зона: её ничья земля не берётся
		garrisonLossMul = 2, -- гарнизон теряет долю потерянной в круге земли × это…
		maxGarrisonLoss = 0.5, -- …но не больше
		frontLoss = 0.8, -- фронты, линия которых касается круга
	},
	Hydrogen = {
		cost = 35000,
		oil = 800,
		radius = 24,
		area = 0.17,
		warningSec = 20,
		charges = 3,
		falloutSec = 90,
		garrisonLossMul = 2.5,
		maxGarrisonLoss = 0.7,
		frontLoss = 0.95,
		techLevel = 4, -- нужна Войска-4 «Тяжёлая броня»
	},
	BotChance = 0.35, -- бот с шахтой и деньгами на бомбу — доля пусков бомбой
	-- §15р: радиус по средней державе — не меньше / не больше этой доли прежнего радиуса (больше прежнего — никогда)
	RadiusMinScale = 0.4,
	RadiusMaxScale = 1.0,
}
Config.Emoji = {
	List = { "👍", "😂", "😡", "😢", "🤝", "⚔", "🔥", "💀" }, -- §15ж: эмодзи над столицей (без своего текста)
	ShowSec = 3,
	MinGapSec = 3, -- не чаще (у одного игрока)
}

Config.Missile = {
	FrontLoss = 0.5, -- фронты, линия которых касается круга, теряют эту долю войск
	-- §15д: шанса перехвата нет — ракету и налёт ловят заряды батарей ПВО (Config.Defense).
	BotChance = 0.3, -- бот с готовой шахтой во время войны — шанс пуска за раздумье
	BotSiloMoneyMul = 1.0, -- бот строит шахту, когда денег не меньше цены × это (сводная правка: было 1.5)
}

-- §6.16 Случайные события (этап 7г).
Config.Events = {
	FirstSec = 150, -- первое событие — через столько секунд игры (§15б: было 180)
	MinGapSec = 150, -- дальше — через случайный промежуток MinGapSec..MaxGapSec (§15б: было 180..240)
	MaxGapSec = 200,
	BannerSec = 6, -- баннер сверху у клиента
	Weights = { OilRush = 2, Storm = 2, Harvest = 2, Mercenaries = 2, Revolt = 1, Defectors = 2 },
	StormRadius = 40, -- клеток на ширине 512
	StormSec = 40,
	HarvestMul = 1.2,
	HarvestSec = 60,
	AuctionSec = 20,
	MercMinBid = 4000, -- было 2000 (решение геймдизайнера: наёмники уходили слишком дёшево)
	MercStep = 500,
	MercStrength = 1500, -- войска наёмников (2/3 пехота, 1/3 танки)
	MercStars = 2, -- опыт наёмников — звёзды
	BotBidShare = 0.3, -- бот ставит до такой доли своих денег (Новичок — вдвое меньше)
	DefectorStrength = 1200, -- пехота перебежчиков
}

-- §6.8 Экономика (этап 4б)
Config.Economy = {
	StartMoney = 4000,
	TaxPerCellPerSec = 0.012, -- денег в секунду с клетки суши
	CityIncomePerLevel = 10, -- денег в секунду за уровень каждого своего города (столица — город ур. 1)
	CityMaxPeoplePerLevel = 400, -- +к максимуму людей за уровень города
	MaxCityLevel = 5, -- §15д ч.4: Посёлок, Город, Промышленный, Крупный, Мегаполис (было 3)
	UpkeepPerStrengthPerSec = 0.01, -- содержание войск: денег в секунду за единицу силы
	UnpaidAttritionPerSec = 0.02, -- денег нет, доход ниже содержания — войска тают на 2% в секунду
}

-- Нефтяные поля и вышки (§6.8)
Config.Oil = {
	ProvinceShare = 0.15, -- доля провинций с нефтяным полем
	PerRigPerSec = 1.0, -- нефти в секунду с вышки
	-- Вес местности центра провинции при выборе полей (индексы — Types.Terrain).
	TerrainWeight = { [1] = 1.5, [2] = 0.7, [3] = 1.0, [4] = 0.3, [5] = 3.0, [6] = 2.0 },
}

-- Укреплённая линия (§6.9): фронт стоит долго — защитнику бонус
-- §15н Прогноз фронта на плашке перевеса: только показ, бой не меняется (FrontForecast).
Config.Forecast = {
	TrendSec = 5, -- тренд: перевес сейчас против перевеса столько реальных секунд назад
	TrendDeadband = 0.05, -- изменилось меньше этой доли — без стрелки
	ReasonMinMul = 1.1, -- множитель обороны меньше этого — не причина («мало войск»)
	LastsShowSec = 120, -- «войск на ~N с» — только если меньше
	RetreatBelowSec = 30, -- «Лучше отступить»: стоит или ползёт, перевес не растёт, войск меньше чем на столько
	MinRatio = 0.05, -- нижняя граница перевеса в делителях (сила атаки ~0)
	PreviewRadius = 24, -- §15н ч.2: прогноз до атаки — его клетки на нашей границе в этом радиусе от курсора (ref 512)
	PreviewRefreshSec = 1, -- …подсказка с прогнозом пересчитывается не реже (силы меняются)
	HistoryStepSec = 0.5, -- клиент: шаг истории перевеса для тренда
	StatusTextPx = 12, -- строка состояния на плашке
	DetailTextPx = 11, -- строка чисел и совета (на телефоне строки чисел нет)
}

Config.Fortify = {
	AfterSec = 60, -- столько секунд фронт не брал ни клетки
	LineBonus = 1.15, -- оборона ×
}

-- Котёл (§6.7): земля, отрезанная от столицы
Config.Pocket = {
	SurrenderSec = 30, -- котёл без города через столько секунд переходит соседу, с которым идёт война
	NationsPerTick = 1, -- проверка связности: столько держав за тик (по кругу)
	CheckEverySec = 2, -- одну державу пересчитывать не чаще (и только если её земля менялась)
	MaxShown = 8, -- §15х ч.8: котлов в таблице world одному игроку (самые крупные)
}

-- §4 Генератор выдуманных карт (описание полей — Types.MapGenParams).
local pangea: Types.MapGenParams = {
	Name = "Pangea",
	Seed = 20261102,
	Width = 512,
	Height = 320,
	LandShare = 0.42,
	EdgeWater = 8,
	NoiseScale = 95,
	Octaves = 6,
	Lacunarity = 2.0,
	Gain = 0.5,
	FalloffStrength = 0.7,
	FalloffPower = 2.0,
	MinIslandCells = 120,
	FillHoleCells = 24,
	RidgeScale = 60,
	RidgeWeight = 0.8,
	MountainShare = 0.07,
	HillShare = 0.14,
	MoistureScale = 90,
	TundraLatitude = 0.62,
	LatitudeJitter = 0.45,
	DesertMoistureMax = 0.40,
	DesertLatitudeMax = 0.45,
	ForestMoistureMin = 0.56,
	LakeCount = 6,
	LakeMinCells = 14,
	LakeMaxCells = 70,
	LakeCoastGap = 4,
	RiverCount = 9,
	RiverMinLength = 14,
	RiverMaxLength = 260,
	RiverMeander = 0.3,
	ProvinceTargetCells = 550,
	ProvinceMinCells = 160,
	ProvinceSeedSpacing = 0.85,
	ProvinceNoise = 0.6,
	ProvinceNoiseScale = 12,
	ProvinceHillCost = 1.5,
	ProvinceMountainCost = 3,
	ProvinceRiverCost = 6,
}

Config.MapGen = {
	Pangea = pangea,
}

-- §4 Карты с реальной географией (этап 4а, tools/realmap). Данные: Natural Earth 1:50m (суша, озёра, реки,
-- географические подписи) и ETOPO1 (рельеф, NOAA). Реальных стран и границ нет — только береговые линии,
-- горы, реки и имена гор, равнин, пустынь. Окна подобраны так, чтобы клетка была почти квадратной.
Config.RealMaps = {
	World = {
		Name = "World",
		Nations = 24, -- держав в матче (игроки + боты)
		Seed = 4001,
		Lon0 = -180,
		Lon1 = 180,
		Lat0 = -56,
		Lat1 = 80,
		Width = 1024,
		Height = 512,
		Provinces = 170,
		RiverMaxRank = 3,
		MaxPlayers = 60,
	},
	Europe = {
		Name = "Europe",
		Nations = 12, -- держав в матче (игроки + боты)
		Seed = 4002,
		Lon0 = -24,
		Lon1 = 60,
		Lat0 = 34,
		Lat1 = 72,
		Width = 768,
		Height = 576,
		Provinces = 150,
		RiverMaxRank = 5,
		MaxPlayers = 40,
	},
	Mediterranean = {
		Name = "Mediterranean",
		Nations = 10, -- держав в матче (игроки + боты)
		Seed = 4003,
		Lon0 = -9,
		Lon1 = 37,
		Lat0 = 27.5,
		Lat1 = 48.7,
		Width = 768,
		Height = 448,
		Provinces = 110,
		RiverMaxRank = 6,
		MaxPlayers = 30,
	},
	Asia = {
		Name = "Asia",
		Nations = 18, -- держав в матче (игроки + боты)
		Seed = 4004,
		Lon0 = 25,
		Lon1 = 180,
		Lat0 = -11,
		Lat1 = 68,
		Width = 1024,
		Height = 640,
		Provinces = 170,
		RiverMaxRank = 4,
		MaxPlayers = 50,
	},
	Americas = {
		Name = "Americas",
		Nations = 14, -- держав в матче (игроки + боты)
		Seed = 4005,
		Lon0 = -168,
		Lon1 = -34,
		Lat0 = -56,
		Lat1 = 72,
		Width = 640,
		Height = 1024,
		Provinces = 160,
		RiverMaxRank = 4,
		MaxPlayers = 40,
	},
	Africa = {
		Name = "Africa",
		Nations = 12, -- держав в матче (игроки + боты)
		Seed = 4006,
		Lon0 = -20,
		Lon1 = 56,
		Lat0 = -36,
		Lat1 = 38,
		Width = 640,
		Height = 704,
		Provinces = 170,
		RiverMaxRank = 4,
		MaxPlayers = 30,
	},
	-- Этап 8в (§5.3): новые регионы.
	Scandinavia = {
		Name = "Scandinavia",
		Nations = 8, -- держав в матче (игроки + боты); малая карта — удобна для дуэли
		Seed = 4007,
		Lon0 = 3,
		Lon1 = 33,
		Lat0 = 54,
		Lat1 = 71.5,
		Width = 512,
		Height = 640,
		Provinces = 90,
		RiverMaxRank = 6,
		MaxPlayers = 20,
	},
	Caribbean = {
		Name = "Caribbean",
		Nations = 10, -- держав в матче (игроки + боты); острова и перешеек — много флота
		Seed = 4008,
		Lon0 = -103,
		Lon1 = -60,
		Lat0 = 7,
		Lat1 = 31.5,
		Width = 832,
		Height = 512,
		Provinces = 100,
		RiverMaxRank = 6,
		MaxPlayers = 25,
	},
	Oceania = {
		Name = "Oceania",
		Nations = 10, -- держав в матче (игроки + боты)
		Seed = 4009,
		Lon0 = 110,
		Lon1 = 180,
		Lat0 = -48,
		Lat1 = -9,
		Width = 960,
		Height = 608,
		Provinces = 130,
		RiverMaxRank = 5,
		MaxPlayers = 25,
	},
}
-- Порядок карт (ротация, лобби — этап 4в).
Config.RealMapOrder =
	{ "Europe", "Mediterranean", "Africa", "Asia", "Americas", "World", "Scandinavia", "Caribbean", "Oceania" }

-- Местность реальных карт по рельефу (метры, перепад — в окне 3×3 клетки) и широте.
Config.RealMapTerrain = {
	MountainMeters = 2200, -- выше — горы
	MountainBaseMeters = 1200, -- …или выше этого при перепаде MountainRelief
	MountainRelief = 900,
	HillMeters = 800, -- выше — холмы
	HillRelief = 350, -- …или такой перепад
	-- Перепад меряется в окне 3×3 клетки, поэтому на крупных клетках он больше: пороги перепада
	-- умножаются на √(размер клетки / ReliefRefCellKm).
	ReliefRefCellKm = 7,
	TundraLatitude = 65, -- севернее (и южнее −65) — тундра…
	TundraJitter = 3, -- …граница тундры неровная: ±3° по шуму
	-- Доля леса по широте (между точками — плавно): тропики, сухой пояс, умеренный пояс, тайга, тундра.
	ForestByLatitude = {
		{ lat = 0, share = 0.62 },
		{ lat = 12, share = 0.6 },
		{ lat = 20, share = 0.12 },
		{ lat = 32, share = 0.15 },
		{ lat = 42, share = 0.3 },
		{ lat = 50, share = 0.4 },
		{ lat = 58, share = 0.6 },
		{ lat = 66, share = 0.55 },
		{ lat = 72, share = 0.1 },
	},
	ForestNoiseScale = 16, -- размер лесных массивов, клеток (шум из нескольких октав)
	ForestNoiseSpread = 0.22, -- разброс этого шума вокруг 0.5 (чтобы доля леса совпадала с заданной)
	MinIslandCells = 8, -- острова меньше — в воду (каждый остров — своя провинция)
	FillLakeCells = 3, -- лужи меньше (не моря) — в сушу
	LabelSearchCells = 40, -- имя провинции — от подписи не дальше стольких клеток
	ProvinceMinShare = 0.3, -- провинции меньше этой доли среднего сливаются с соседом
	ProvinceSeedSpacing = 0.85,
	ProvinceNoise = 0.6,
	ProvinceNoiseScale = 12,
	ProvinceHillCost = 1.5,
	ProvinceMountainCost = 3,
	ProvinceRiverCost = 6,
}

-- Упаковка карт в ModuleScript (maps/*.luau)
Config.MapFile = {
	ChunkChars = 8000, -- длина одной строки base64 в модуле карты
}

-- §6.5 Провинции и города (этап 3)
Config.Cities = {
	ProvinceShare = 0.3, -- доля провинций с нейтральным городом на старте
	MinDistance = 28, -- минимальное расстояние между городами, клеток
	-- Реальные города на реальных картах (§15д ч.4, tools/realcities): 2–3 крупнейших в каждой стране.
	RealPerCountry = 3,
	RealMinPop = 400000, -- второй и третий город страны — не меньше такого населения
	RealMinDistance = 7, -- реальные города не ближе стольких клеток друг к другу
	-- «Основать город» (§15д ч.4): свой город на своей земле, каждый следующий дороже.
	FoundCost = 6000,
	FoundStep = 0.5, -- +50% за каждый уже основанный державой город
	FoundMinDistance = 12, -- не ближе стольких клеток к другому городу
}

-- Цвета держав (отдельный набор, не входит в 32 цвета палитры — см. NationColors.luau)
Config.Nations = {
	BorderShade = 0.55, -- граница державы = её цвет × это число
	-- Сколько ближайших по старту держав гарантированно получают цвет, отличный от твоего.
	-- 3 — доказуемо выполнимо для любой расстановки при 24 цветах (см. NationColors.assign).
	DistinctNearest = 3,
}

-- §6.11 Туман войны (этап 7а)
Config.Fog = {
	Enabled = true, -- false — карта видна целиком (частные серверы, «Мгла» — этап 8)
	-- false — границы и города всех держав видны везде, туман прячет войска, корабли, самолёты и здания
	-- (решение геймдизайнера после 7г); true — правило 7а: вне обзора последний увиденный владелец.
	HideTerritory = false,
	TerritoryVision = 6, -- клеток вокруг земли своей и друзей
	ArmyVision = 8, -- …вокруг линий фронтов (граница с державой, с которой идёт бой)
	RadarVision = 25, -- …вокруг аэродрома (§15х ч.6: аэродром — и радар)
	RefreshSec = 1, -- клиент пересчитывает обзор не чаще (на «Мире» в Lune — 4–7 мс)
	-- Сервер: фронты чужих войн шлёт, только если линия фронта в обзоре — грубо, блоками этой стороны.
	BlockSize = 8,
	LineSamples = 12, -- сколько клеток линии фронта сервер помнит для этой проверки
}

-- §6.12 Флот (этап 7б-1).
Config.Naval = {
	MinSeaCells = 300, -- связная вода меньше — озеро: кораблей и портов там нет
	PathWeight = 1.6, -- вес эвристики A* (больше — быстрее поиск, путь чуть длиннее)
	PathMaxNodes = 60000, -- точный поиск раскрывает не больше стольких клеток (иначе «пути нет»)
	NavBlock = 8, -- сторона блока грубой навигации, клеток
	PathsPerTick = 1, -- сервер ищет не больше стольких путей за тик (поиск — до ~40 мс на «Европе»)
	-- Расстояния ниже (кроме BeachheadRadius и ShipVision) — в клетках на ширине карты 512, на больших картах больше.
	SpeedMul = 1.0, -- множитель скорости кораблей (скорость — Units.*.speed)
	MaxShips = 10, -- кораблей у державы (с очередью)
	ShipQueue = 3, -- кораблей в очереди найма
	TransportHp = 100,
	DestroyerHp = 300,
	TransportCapacity = 1000, -- силы войск на борту
	TransportPeople = 1500, -- людей на борту
	BeachheadRadius = 4, -- круг плацдарма, клеток
	DestroyerRange = 8, -- эсминец бьёт корабли и берег в этом радиусе
	ShipDamage = 20, -- урон в секунду: атака × ShipDamage / защита цели (транспорт 100 прочности — ~2 с)
	ShoreDamage = 15, -- обстрел берега: атака × ShoreDamage силы в секунду вражескому фронту в радиусе
	BlockadeRange = 8, -- эсминец врага не дальше этого от причала — порт заблокирован
	SeaSupplyRange = 60, -- порт снабжает берег, до которого по воде не дальше этого
	SeaSupplyNear = 6, -- фронт снабжён по морю, если такой берег не дальше этого от его линии (клеток)
	ShipVision = 6, -- обзор своих кораблей (§6.11), клеток
	LandReach = 3, -- точка высадки: суша не дальше этого от моря
	MaxBoats = 3, -- десантных кораблей (§15д: атака на другой берег) одновременно; в MaxShips не входят
	BoatSearch = { 3, 8, 16, 32, 64 }, -- десант: радиусы поиска моря у нажатой клетки (ближайший берег острова)
	-- Десант при общей границе: нажатая клетка дальше этого от сухопутной линии с целью (ref)…
	InvadeFarCells = 40,
	InvadeCloserMul = 0.5, -- …а берег цели у неё не дальше этой доли того расстояния — плывём, а не идём
	-- Боты
	BotPortReserve = 1500, -- строит порт, если денег больше цены на столько
	BotTransports = 1, -- держит транспортов (Флотоводец — × navy личности)
	BotDestroyers = 1,
	BotLandChance = 0.3, -- вероятность за раздумье заняться высадкой (× navy)
	BotLandShare = 0.5, -- доля гарнизона на высадку
}

-- §6.13 Авиация (этап 7б-2). Расстояния (кроме BombRadius и AirVision) — в клетках на ширине карты 512.
Config.Air = {
	Range = 60, -- самолёты летают не дальше этого от своего работающего аэродрома
	SpeedMul = 1.0, -- множитель скорости (скорость — Units.Fighter/Bomber.speed)
	MaxAircraft = 8, -- самолётов у державы (с очередью)
	Queue = 3,
	FighterHp = 100,
	BomberHp = 120,
	AirDamage = 25, -- бой в воздухе: атака × AirDamage / защита цели в секунду (бомбардировщик — ~2.4 с)
	GunRange = 3, -- истребитель стреляет с такого расстояния
	InterceptRadius = 40, -- истребитель перехватывает самолёты врага в этом круге вокруг точки прикрытия
	BombRadius = 5, -- круг налёта, клеток
	BombEverySec = 4, -- налёт раз в столько секунд…
	RaidsPerSortie = 3, -- …столько налётов за вылет
	BombDamage = 60, -- × атака бомбардировщика (2.0) = 120 силы за налёт фронту врага в круге
	GarrisonShare = 0.5, -- линия фронта против врага в круге: его гарнизон теряет столько от урона налёта
	BuildingDisableSec = 60, -- здание врага в круге выведено из строя на столько секунд
	AAFullShare = 0.3, -- доля ПВО в войсках, при которой урон с воздуха меньше на AAMaxReduction
	AAMaxReduction = 0.6,
	BatteryDamage = 40, -- батарея ПВО: прочности самолёта врага в секунду в радиусе Buildings.AirDefense.radius
	AirVision = 5, -- обзор своих самолётов (§6.11), клеток
	-- Боты
	BotFighters = 1,
	BotBombers = 1,
	BotRaidChance = 0.35, -- вероятность за раздумье (× air личности) послать бомбардировщик
	BotFightersWhenBombed = 2, -- Генерал под бомбами держит столько истребителей…
	BotCoverAir = 0.5, -- …и так же поступает личность с air не меньше (Хитрец, Агрессор; сводная правка)
	BotCoverNear = 0.5, -- …и переносит прикрытие, если оно дальше этой доли радиуса перехвата от места налёта
}

-- §6.14 Технологии (этап 7в-1): три ветки по четыре уровня, одно исследование за раз.
-- §6.15 Генералы игроков (этап 7в-2). Расстояния с пометкой «ref» — в клетках на ширине карты 512.
Config.Commanders = {
	Default = "Marshal", -- не выбрал до начала игры
	BotPick = {
		Aggressor = "Marshal",
		Admiral = "Admiral",
		Cunning = "Scout",
		Trader = "Engineer",
		Peaceful = "Engineer",
	},
	-- Пассивки.
	TankDiscount = 0.15, -- Маршал: танки дешевле (деньги)
	ShipDiscount = 0.20, -- Адмирал: корабли дешевле (вместе с «Верфями» — множители перемножаются)
	PortVision = 2, -- Адмирал: обзор вокруг своих портов = TerritoryVision + столько клеток
	-- Разведчик: мощь соседей по суше видна всегда (MatchSim.knownSet; с PR #17 вместо «обзор ×1.3»).
	BuildDiscount = 0.25, -- Инженер: здания и улучшение города дешевле (деньги; PR #17: 0.20 откатили, ослаблен «Укрепрайон»)
	-- Способности: перезарядка (игровые секунды) по слотам Q, E.
	Cooldown = {
		Marshal = { 90, 120 },
		Admiral = { 120, 150 },
		Scout = { 100, 140 },
		Engineer = { 90, 120 },
	},
	StrikeRadius = 5, -- Авиаудар: круг, клеток
	StrikeLoss = 0.25, -- …фронты врагов в круге теряют эту долю силы (ПВО в составе снижает)
	StrikeDefenseMul = 0.7, -- …оборона врага на линиях, касающихся круга
	StrikeSec = 15,
	SurgeMul = 1.5, -- Прорыв: скорость своих фронтов
	SurgeSec = 15,
	BlockadeRadius = 30, -- Блокада: круг (ref)
	BlockadeSec = 30, -- …порты врагов выведены из строя
	RevealSec = 20, -- Радарная вспышка: видна мощь всех держав и все фронты
	PropagandaRadius = 25, -- Пропаганда: круг (ref)
	PropagandaLoss = 30, -- …стабильность провинций врага
	FortSec = 30, -- Укрепрайон
	FortMul = 1.7, -- …оборона на линиях, касающихся провинции (PR #17: было 2.0)
	AirdropShare = 0.2, -- Воздушный десант: не больше этой доли пехоты гарнизона
	AirdropRadius = 3, -- …плацдарм, клеток
	-- Боты: шанс за раздумье применить готовую способность (Новичок ×0.3) — только во время войны.
	BotChance = 0.35,
	BotLandPercent = 0.3, -- доля гарнизона в морской десант бота
}

Config.Tech = {
	Cost = { 3000, 5000, 8000, 12000 }, -- цена уровня 1..4 (деньги, сразу)
	Sec = { 40, 60, 80, 100 }, -- время исследования, игровые секунды
	-- Закрытые уровни (ветка → с этого и выше не изучаются). До 7г были Войска-4 и Флот-4; с 7г всё открыто.
	Locked = {} :: { [string]: number },
	SupplyRangeMul = 1.5, -- Войска-2 «Снабжение»: дальность снабжения от городов
	TankArmor = 1.2, -- Войска-4 «Тяжёлая броня»: защита танков в обороне (сводная правка; было Войска-3)
	TaxBonus = 0.10, -- Экономика-1 «Налоги»: доход
	OilBonus = 0.30, -- Экономика-2 «Нефтедобыча»: нефть
	TradeMul = 1.5, -- Экономика-3 «Торговые пути»: бонус торговых соглашений
	OrderStability = 15, -- Экономика-4 «Порядок»: целевая стабильность провинций
	ShipyardDiscount = 0.20, -- Флот-1 «Верфи»: корабли дешевле в деньгах
	-- Что открывают уровни (здание → ветка и уровень).
	-- Флот-2 «Авиация», Флот-3 «Дальняя ПВО» (§15х ч.6; была «Радар»).
	Unlocks = {
		Airfield = { branch = "Fleet", level = 2 },
		MissileSilo = { branch = "Army", level = 3 }, -- Войска-3 «Ракетная шахта» (сводная правка; было Войска-4)
	},
	-- §15х ч.6: уровень здания, который открывает технология (здание → с какого уровня, ветка, уровень ветки).
	LevelUnlocks = {
		AirDefense = { from = 3, branch = "Fleet", level = 3 }, -- ПВО ур. 3 «дальняя»
	},
	-- Боты: вероятность за раздумье заняться исследованием и очередь уровней по личности (запись — следующий
	-- уровень этой ветки; сводная правка: ветки чередуются, «Авиация» и «Ракетная шахта» — раньше, чем было, когда
	-- бот проходил ветку целиком). Генерал — по своей очереди GeneralOrder.
	BotChance = 0.25,
	BotSaveShare = 1, -- в мире бот копит на следующий уровень (доля цены), найм — только сверх неё
	BotOrder = {
		-- Налоги, Учебка, Нефть, Верфи, Авиация, Снабжение, Торговые пути, Шахта, Радар, Порядок, Броня, ПВО
		Peaceful = {
			"Economy",
			"Army",
			"Economy",
			"Fleet",
			"Fleet",
			"Army",
			"Economy",
			"Army",
			"Fleet",
			"Economy",
			"Army",
			"Fleet",
		},
		-- Учебка, Снабжение, Шахта, Верфи, Авиация, Налоги, Броня, Нефть, Радар, Торговые пути, ПВО, Порядок
		Aggressor = {
			"Army",
			"Army",
			"Army",
			"Fleet",
			"Fleet",
			"Economy",
			"Army",
			"Economy",
			"Fleet",
			"Economy",
			"Fleet",
			"Economy",
		},
		-- Торговец — «экономика ↔ войска»: Налоги, Учебка, Нефть, Снабжение, Торговые пути, Шахта, Верфи, Авиация, …
		Trader = {
			"Economy",
			"Army",
			"Economy",
			"Army",
			"Economy",
			"Army",
			"Fleet",
			"Fleet",
			"Economy",
			"Army",
			"Fleet",
			"Fleet",
		},
		-- Учебка, Верфи, Авиация, Снабжение, Шахта, Налоги, Радар, Нефть, Броня, Торговые пути, Порядок, ПВО
		Cunning = {
			"Army",
			"Fleet",
			"Fleet",
			"Army",
			"Army",
			"Economy",
			"Fleet",
			"Economy",
			"Army",
			"Economy",
			"Economy",
			"Fleet",
		},
		-- Верфи, Авиация, Налоги, Радар, Учебка, Снабжение, Шахта, ПВО, Нефть, Торговые пути, Броня, Порядок
		Admiral = {
			"Fleet",
			"Fleet",
			"Economy",
			"Fleet",
			"Army",
			"Army",
			"Army",
			"Fleet",
			"Economy",
			"Economy",
			"Army",
			"Economy",
		},
	},
	GeneralOrder = {
		"Army", -- Учебка
		"Fleet", -- Верфи
		"Fleet", -- Авиация (сводная правка: раньше налогов и снабжения)
		"Economy", -- Налоги
		"Army", -- Снабжение
		"Army", -- Ракетная шахта (Войска-3)
		"Fleet", -- Радар
		"Economy", -- Нефтедобыча
		"Economy", -- Торговые пути
		"Economy", -- Порядок
		"Army", -- Тяжёлая броня (Войска-4)
		"Fleet", -- Сеть ПВО
	},
}

-- §6.10 Стабильность провинций и восстания (этап 7а). Стабильность 0..100, идёт к целевой.
Config.Stability = {
	Base = 60, -- целевая стабильность без поправок
	UpdateSec = 1, -- пересчёт раз в столько игровых секунд
	ChangePerSec = 1, -- текущая идёт к целевой на столько в секунду
	-- Удалённость от столицы: −PerDistance за каждые DistanceCells клеток (приведено к ширине DistanceRefWidth).
	DistancePenalty = 12,
	DistanceCells = 100,
	DistanceRefWidth = 512,
	DistanceMax = 36,
	War = -10, -- держава в активной войне
	WearinessMul = -30, -- × усталость от войны (0.25..0.5 → −7.5..−15)
	RecentCapture = -25, -- провинция взята у другой державы (или у повстанцев)…
	RecentCaptureSec = 180, -- …поправка тает до нуля за столько секунд
	Traitor = -20, -- метка «Предатель» (§8.1)
	Capital = 30, -- провинция столицы
	CityPerLevel = 8, -- город в провинции, за уровень
	Fort = 10, -- «Укрепление» в провинции
	Peace = 10, -- у державы нет войн
	CaptureStart = 30, -- взята у другой державы: стабильность сразу не выше этого
	SettleStart = 50, -- новая провинция с ничьей земли начинает с этого
	LowBelow = 30, -- ниже — доход провинции ×LowIncomeMul
	LowIncomeMul = 0.5,
	RevoltBelow = 15, -- ниже — провинция восстаёт через RevoltDelaySec (§15д: по таймеру, а не по шансу)
	RevoltDelaySec = 30, -- столько секунд подряд ниже RevoltBelow — восстание (отсчёт виден игроку)
	RebelGarrison = 600, -- сила гарнизона города повстанцев (обычный ничейный — Combat.NeutralCityGarrison)
	RebelSec = 180, -- столько провинция — «Повстанцы»
	RebelCellCostMul = 3, -- ничья земля повстанцев дороже для границы людей
	-- Боты: при средней стабильности ниже — просят мира раньше (× к порогу мира).
	BotPeaceBelow = 30,
	BotPeaceMul = 1.5,
	BotCalmForts = 3, -- укреплений против нестабильности бот ставит, пока у него их меньше
}

return deepFreeze(Config)
