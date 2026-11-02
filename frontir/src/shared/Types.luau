--!strict
--[[
	Types — общие типы и перечисления, которые используют сервер, клиент, тесты и инструменты.
	Модуль чистый: без Roblox API.
]]

local Types = {}

-- §6.1 Местность. Числа — это байт местности в формате карты (docs/GDD.md §4), не менять порядок.
export type TerrainId = number

Types.Terrain = table.freeze({
	Water = 0,
	Plains = 1,
	Forest = 2,
	Hills = 3,
	Mountains = 4,
	Desert = 5,
	Tundra = 6,
	River = 7, -- §4: граница не проходит, армии идут с замедлением
})

-- Все id местности по порядку — для перебора (record-таблицу выше перебирать неудобно в strict).
Types.TerrainIds = table.freeze({ 0, 1, 2, 3, 4, 5, 6, 7 }) :: { TerrainId }

export type TerrainStats = {
	captureCost: number, -- множитель стоимости захвата клетки
	defense: number, -- множитель защиты
	armySpeed: number, -- множитель скорости армий
	borderPassable: boolean, -- может ли граница державы идти по клетке
	-- армии проходят клетку, если armySpeed > 0; флот ходит только по воде
}

-- §7 Юниты
export type UnitKind = "Infantry" | "Tanks" | "Artillery" | "AntiAir" | "Transport" | "Destroyer" | "Fighter" | "Bomber"

export type BuildingKind =
	"City"
	| "OilRig"
	| "Port"
	| "Factory"
	| "Airfield"
	| "Fort"
	| "AirDefense"
	| "Radar"
	| "Market"
	| "MissileSilo"

export type UnitStats = {
	cost: number,
	oil: number,
	speed: number, -- клеток/с на эталонной карте
	attack: number,
	defense: number,
	captureRate: number, -- клеток/с при захвате провинции
	range: number?,
	requires: BuildingKind?,
}

-- Таблица параметров всех юнитов (запись, чтобы обращение Config.Units.Infantry проверялось типами).
export type UnitTable = {
	Infantry: UnitStats,
	Tanks: UnitStats,
	Artillery: UnitStats,
	AntiAir: UnitStats,
	Transport: UnitStats,
	Destroyer: UnitStats,
	Fighter: UnitStats,
	Bomber: UnitStats,
}

-- §4 Параметры генератора выдуманных карт. Доли (Share) — от всей суши или всей карты, как подписано.
export type MapGenParams = {
	Name: string,
	Seed: number,
	Width: number,
	Height: number,
	LandShare: number, -- доля суши от всей карты
	EdgeWater: number, -- ширина гарантированной воды по краям, клеток
	NoiseScale: number, -- размер крупных форм рельефа, клеток
	Octaves: number,
	Lacunarity: number,
	Gain: number,
	FalloffStrength: number, -- насколько сильно суша «тонет» к краям
	FalloffPower: number,
	MinIslandCells: number, -- острова меньше — в воду
	FillHoleCells: number, -- внутренние лужи меньше — в сушу
	RidgeScale: number,
	RidgeWeight: number, -- вклад хребтов против общей высоты в выбор гор (0..1)
	MountainShare: number, -- доля суши под горами
	HillShare: number, -- доля суши под холмами
	MoistureScale: number,
	TundraLatitude: number, -- 0 — экватор (середина карты), 1 — полюс (край)
	LatitudeJitter: number, -- размах шумовой поправки широты
	DesertMoistureMax: number,
	DesertLatitudeMax: number,
	ForestMoistureMin: number,
	LakeCount: number,
	LakeMinCells: number,
	LakeMaxCells: number,
	LakeCoastGap: number, -- минимум клеток от озера до моря
	RiverCount: number,
	RiverMinLength: number,
	RiverMaxLength: number,
	RiverMeander: number, -- вероятность шага «вбок» вместо шага к воде
}

return Types
