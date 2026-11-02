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
})

-- Все id местности по порядку — для перебора (record-таблицу выше перебирать неудобно в strict).
Types.TerrainIds = table.freeze({ 0, 1, 2, 3, 4, 5, 6 }) :: { TerrainId }

export type TerrainStats = {
	captureCost: number, -- множитель стоимости захвата клетки
	defense: number, -- множитель защиты
	armySpeed: number, -- множитель скорости армий
	passable: boolean, -- может ли граница идти по клетке
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

return Types
