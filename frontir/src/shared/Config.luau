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
	Infantry = { cost = 1000, oil = 0, speed = 2.4, attack = 1.0, defense = 1.2, captureRate = 26, requires = nil },
	Tanks = { cost = 2500, oil = 20, speed = 3.6, attack = 1.6, defense = 1.0, captureRate = 18, requires = "Factory" },
	Artillery = {
		cost = 3000,
		oil = 10,
		speed = 1.8,
		attack = 1.4,
		defense = 0.6,
		captureRate = 12,
		range = 4,
		requires = "Factory",
	},
	AntiAir = { cost = 2000, oil = 5, speed = 2.0, attack = 0.6, defense = 1.0, captureRate = 10, requires = "Factory" },
	Transport = { cost = 1500, oil = 10, speed = 4.0, attack = 0, defense = 0.5, captureRate = 0, requires = "Port" },
	Destroyer = { cost = 3500, oil = 25, speed = 4.5, attack = 1.4, defense = 1.2, captureRate = 0, requires = "Port" },
	Fighter = {
		cost = 4000,
		oil = 30,
		speed = 7.0,
		attack = 1.2,
		defense = 1.0,
		captureRate = 0,
		requires = "Airfield",
	},
	Bomber = { cost = 5000, oil = 40, speed = 5.0, attack = 2.0, defense = 0.6, captureRate = 0, requires = "Airfield" },
}
Config.Units = units

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
}

Config.MapGen = {
	Pangea = pangea,
}

-- Упаковка карт в ModuleScript (maps/*.luau)
Config.MapFile = {
	ChunkChars = 8000, -- длина одной строки base64 в модуле карты
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
