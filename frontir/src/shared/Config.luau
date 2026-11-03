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
Config.Match = {
	MinPlayers = 2,
	MaxPlayers = 60,
	DurationMinSec = 15 * 60,
	DurationMaxSec = 30 * 60,
	BlitzDurationSec = 8 * 60,
	StartPickSec = 20, -- §6.2 фаза выбора точки старта
	VictoryLandShareFfa = 0.60,
	VictoryLandShareTeams = 0.70,
	MaxAlliesFfa = 2,
	DefaultMap = "Pangea",
	-- Общий множитель скорости матча: всё, что идёт в игровом времени — рост людей, фронт атак,
	-- решения ботов (дальше — армии, найм, перезарядки) — идёт в Speed раз быстрее.
	-- 1 — обычный матч, 2 — «Блиц» (GDD §5). Таймер выбора старта и часы матча — реальное время.
	Speed = 1.0,
	-- Сколько держав в матче (игроки + боты). Свободные места заполняют боты (GDD §9).
	-- Этап 2: 6 = 2 игрока + 4 бота.
	TargetNations = 6,
}

-- §6.2 Старт
Config.Start = {
	MinDistance = 48, -- минимальная дистанция между точками старта, клеток
	Radius = 4, -- радиус круга клеток вокруг столицы на старте
	MinCircleShare = 0.7, -- круг старта должен быть хотя бы на 70% сушей (не мыс и не островок)
	AutoPickTries = 300, -- кандидатов при автоматическом выборе старта
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
	ThinkMinSec = 1,
	ThinkMaxSec = 2,
	AttackWhenFill = 0.45, -- атакует, когда людей больше этой доли от максимума
	NeutralPercent = 0.35,
	NationAdvantage = 1.0, -- нападает на соседа, если отправит войск не меньше его гарнизона
	MaxAttacks = 2,
	HireWhenFill = 0.45, -- нанимает юнит, когда людей больше этой доли от максимума
	HireChance = 0.5, -- вероятность выбрать найм, если можно
	MaxQueue = 2, -- бот держит в очереди найма не больше
	FrontPercent = 0.6, -- какую долю войск бот шлёт на фронт
	MaxWars = 1, -- сам объявляет войну, только если воюет меньше чем с таким числом стран
	MinWarSec = 60, -- раньше этого мира не просит
	PeaceWhenWeaker = 0.6, -- просит мира, если его сила меньше этой доли силы врага
	PeaceRetrySec = 60, -- повторно просит мира не чаще
	AcceptWhiteWhenWeaker = 1.0, -- соглашается на белый мир, если слабее врага (сила < его × это)
	AcceptKeepWhenWeaker = 0.7, -- отдаёт захваченное врагом, только если сильно слабее
}

-- Для разработки
Config.Dev = {
	-- Язык интерфейса: "" — по языку Roblox у игрока, "ru" или "en" — принудительно
	-- (например, проверить кириллицу, когда Roblox в Studio на английском).
	ForceLang = "",
}

-- §12 Сеть
Config.Net = {
	SnapshotPartBytes = 32000, -- полный снимок сетки уходит частями не больше этого
	StatsHz = 5, -- частота рассылки статистики держав
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
	CaptureFlashStrength = 0.6, -- насколько свежезахваченная клетка вспыхивает к белому
	NationLabelSize = 14, -- размер подписи державы на карте, px
	CaptureFlashSteps = 4, -- вспышка гаснет ступенями (пиксельный стиль и меньше перерисовок)
	TapSlopPx = 10, -- сдвиг пальца/мыши, после которого это уже не нажатие, а перетаскивание
	TapMaxSec = 0.4, -- дольше — не нажатие
	ToastSec = 3, -- сколько висит всплывающее сообщение
	FrontSpritesPerFront = 24, -- юнитов на линии одного фронта (рисуются вдоль границы)
	FrontSpritesTotal = 160, -- всего юнитов на фронтах на экране
	UnitSpriteScales = { { zoom = 4, scale = 2 }, { zoom = 8, scale = 3 } }, -- с какого зума спрайты юнитов крупнее
	FrontScanSec = 0.5, -- как часто клиент пересчитывает линию фронта
	BattleEffectsPerSec = 10, -- вспышек и взрывов в секунду на фронте с боем
	BattleEffectsMax = 60, -- вспышек и взрывов на экране одновременно
	NarrowScreenPx = 1000, -- уже — раскладка HUD для телефона (карточки найма справа)
	-- Блики воды — отдельные пиксели поверх карты, текстуру не перерисовываем.
	SparkleMax = 48,
	SparklesPerSec = 24,
	SparkleLifeSec = 0.9,
	SparkleMinDepth = 2, -- блики только там, где до суши не меньше N клеток
	DebugRefreshSec = 0.25, -- частота обновления окна F3
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
		requires = "Factory",
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
		requires = "Factory",
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
		requires = "Factory",
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
		recruitSec = 4,
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
		recruitSec = 6,
		strength = 300,
	},
	Fighter = {
		cost = 4000,
		oil = 30,
		speed = 7.0,
		attack = 1.2,
		defense = 1.0,
		requires = "Airfield",
		people = 150,
		recruitSec = 6,
		strength = 150,
	},
	Bomber = {
		cost = 5000,
		oil = 40,
		speed = 5.0,
		attack = 2.0,
		defense = 0.6,
		requires = "Airfield",
		people = 200,
		recruitSec = 8,
		strength = 200,
	},
}
Config.Units = units

-- §6.6 Войска и фронты
Config.Forces = {
	MaxQueue = 5, -- юнитов в очереди найма
	MinFrontStrength = 50, -- меньше войск — фронт против державы не открыть
}

-- §6.7 Бой на фронте
Config.Combat = {
	DamageSpread = 0.40, -- случайный разброс урона ±40%
	LossRate = 0.02, -- урона в секунду на единицу силы противника
	FrontSpeedMul = 0.5, -- фронт против державы идёт медленнее, чем экспансия на ничью землю
	FullSpeedRatio = 2.0, -- при таком перевесе фронт идёт с полной скоростью; при 1 — стоит
	BreakthroughRatio = 3.0, -- прорыв: перевес от этого числа
	BreakthroughMul = 1.5, -- …и фронт идёт во столько раз быстрее
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
	MobilizationSec = 15, -- от объявления до начала боёв
	PeaceCooldownSec = 60, -- после мира пара не может снова объявить войну
	PeaceReplySec = 20, -- сколько ждать ответа на предложение мира
	BotReplyDelaySec = 2, -- бот отвечает на предложение мира через столько секунд
	WearinessAfterSec = 300, -- через 5 минут войны — усталость
	WearinessPenalty = 0.25, -- −25% к приросту людей…
	WearinessPenaltyPerMin = 0.05, -- …и ещё −5% за каждую следующую минуту
	WearinessMaxPenalty = 0.5, -- но не больше −50%
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
	City = { cost = 2000, upgradeCosts = { 4000 } },
	OilRig = { cost = 1500 },
	Port = { cost = 2500 },
	Factory = { cost = 3000, recruitSpeedBonus = 0.10 },
	Airfield = { cost = 3500, airstrikeCooldownReductionSec = 2 },
	Fort = { cost = 1500, defenseMultiplier = 1.5 },
	AirDefense = { cost = 2000, radius = 10 },
	Radar = { cost = 1500, visionRadius = 25 },
	Market = { cost = 2000, incomeBonus = 0.05 },
	MissileSilo = { cost = 10000, oil = 200, strikeRadius = 6, cooldownSec = 240, warningSec = 10 },
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

-- Упаковка карт в ModuleScript (maps/*.luau)
Config.MapFile = {
	ChunkChars = 8000, -- длина одной строки base64 в модуле карты
}

-- §6.5 Провинции и города (этап 3)
Config.Cities = {
	ProvinceShare = 0.3, -- доля провинций с нейтральным городом на старте
	MinDistance = 28, -- минимальное расстояние между городами, клеток
}

-- Цвета держав (отдельный набор, не входит в 32 цвета палитры — см. NationColors.luau)
Config.Nations = {
	BorderShade = 0.55, -- граница державы = её цвет × это число
	-- Сколько ближайших по старту держав гарантированно получают цвет, отличный от твоего.
	-- 3 — доказуемо выполнимо для любой расстановки при 24 цветах (см. NationColors.assign).
	DistinctNearest = 3,
}

-- §6.11 Туман войны
Config.Fog = {
	TerritoryVision = 6,
	ArmyVision = 8,
	RadarVision = 25,
}

return deepFreeze(Config)
