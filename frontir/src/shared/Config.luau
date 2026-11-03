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
	NationCellCostBase = 3, -- людей за клетку державы при нулевой плотности (× местность)
	DensityCostFactor = 2.0, -- + плотность защитника (людей на клетку) × это
	DefenderLossFactor = 0.5, -- защитник теряет плотность × это за каждую потерянную клетку
	FrontAdvancePerSec = 1.0, -- скорость продвижения фронта, клеток в секунду
	MaxCellsPerTick = 600, -- предел захвата одной атакой за тик (бюджет сервера)
	MaxAttacks = 4, -- одновременных атак у державы (разные цели)
	MinTroops = 5, -- меньше — атака не начинается / заканчивается
	MinPercent = 0.05, -- ползунок «Атака N%»
	MaxPercent = 1.0,
	DefaultPercent = 0.3,
	PercentStep = 0.05,
	-- Форма фронта: клетки берутся по близости к точке нажатия (или к столице) — фронт идёт кругом
	-- к цели. Плавный шум делает границу живой («языки» размером ~BorderNoiseScale клеток).
	BorderNoise = 14, -- амплитуда шума в клетках расстояния
	BorderNoiseScale = 14, -- размер «языков», клеток
	TouchWeight = 0.6, -- бонус за каждого нашего соседа (заливает щели в одну клетку)
	TickJitter = 0.3, -- шум тика: только чтобы ничьи решались по-разному
	NotchTouch = 3, -- клетка с таким числом наших соседей — «щель», берётся в первую очередь
	NotchBonus = 1e6, -- приоритет щелей (больше любого расстояния на карте)
	EnclaveMaxCells = 300, -- окружённый кусок земли до такого размера переходит к окружившему
	EnclaveRecheckTicks = 10, -- «открытый» кусок перепроверяется не чаще, чем раз в столько тиков
}

-- §9 Боты (этап 2 — простые; уровни и личности — этап 5)
Config.Bots = {
	ThinkMinSec = 1,
	ThinkMaxSec = 2,
	AttackWhenFill = 0.45, -- атакует, когда людей больше этой доли от максимума
	NeutralPercent = 0.35,
	NationPercent = 0.5,
	NationAdvantage = 1.5, -- нападает на соседа, если людей в 1.5 раза больше, чем у него
	MaxAttacks = 2,
	HireWhenFill = 0.45, -- нанимает армию, когда людей больше этой доли от максимума
	HireChance = 0.5, -- вероятность выбрать найм, если можно
	MaxArmies = 4,
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
	-- people / recruitSec / strength — этап 3: найм стоит людей (деньги и нефть — этап 4, cost и oil).
	Infantry = {
		cost = 1000,
		oil = 0,
		speed = 2.4,
		attack = 1.0,
		defense = 1.2,
		captureRate = 26,
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
		captureRate = 18,
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
		captureRate = 12,
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
		captureRate = 10,
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
		captureRate = 0,
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
		captureRate = 0,
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
		captureRate = 0,
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
		captureRate = 0,
		requires = "Airfield",
		people = 200,
		recruitSec = 8,
		strength = 200,
	},
}
Config.Units = units

-- §6.6 Армии (этап 3а)
Config.Armies = {
	MaxPerNation = 20, -- армий у державы, включая нанимаемые
	PathMaxNodes = 120000, -- предел поиска пути (клеток), дальше — «нет пути»
	MaxOrderArmies = 40, -- армий в одном приказе
	CityCaptureSlowdown = 0.5, -- провинцию с чужим городом армия захватывает в 2 раза медленнее
	IdleRecheckSec = 0.5, -- как часто стоящая армия проверяет, не надо ли снова захватывать
	-- Приказ «авто»: выбор соседней непокорённой провинции (GDD §6.6).
	AutoCityWeight = 3, -- провинция с городом
	AutoNeutralWeight = 1, -- ничья провинция
	AutoWeakWeight = 1.5, -- провинция более слабой державы
	AutoDistancePenalty = 0.02, -- за клетку расстояния
}

-- §6.7 Бой
Config.Combat = {
	DamageSpread = 0.40, -- случайный разброс ±40%
	MaxVeteranStars = 3,
	VeteranStarBonus = 0.30, -- +30% к силе и скорости захвата за звезду
	SupplyRange = 12, -- клеток от своей/союзной земли
	OutOfSupplyLossPerSec = 0.02,
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
