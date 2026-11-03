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

-- Сухопутные войска (§6.6), по порядку: индекс — номер типа в пуле войск и в сетевом протоколе.
Types.LandUnits = table.freeze({ "Infantry", "Tanks", "Artillery", "AntiAir" }) :: { string }

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
	range: number?,
	requires: BuildingKind?,
	people: number, -- людей на найм (этап 3: найм стоит людей; деньги и нефть — этап 4)
	recruitSec: number, -- время найма, игровые секунды
	strength: number, -- сила юнита, добавляемая в пул войск
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
	-- Провинции (этап 3): рост от затравок по «стоимости пути», мелкие сливаются с соседями.
	ProvinceTargetCells: number, -- средний размер провинции, клеток суши
	ProvinceMinCells: number, -- провинции меньше сливаются с соседом (кроме островов)
	ProvinceSeedSpacing: number, -- минимальное расстояние между затравками, в долях √ProvinceTargetCells
	ProvinceNoise: number, -- насколько шум искривляет границы провинций (0 — ровные ячейки)
	ProvinceNoiseScale: number,
	ProvinceHillCost: number, -- «стоимость» прохода через холмы, горы и реку: границы ложатся по хребтам и рекам
	ProvinceMountainCost: number,
	ProvinceRiverCost: number,
}

-- Державы и матч (этап 2) -----------------------------------------------------------------

-- Id державы: 1..N; 0 — нейтральная земля.
export type NationId = number

export type Nation = {
	id: NationId,
	name: string, -- имя для русского интерфейса
	nameEn: string, -- имя для английского (у игроков совпадает)
	isBot: boolean,
	userId: number?, -- игрок Roblox; nil — бот
	colorIndex: number, -- 1..24 (NationColors); 0 — ещё не назначен (идёт выбор старта)
	capital: number?, -- клетка столицы; nil — старт ещё не выбран
	people: number, -- люди дома (без отправленных в атаки)
	alive: boolean,
	home: Forces, -- гарнизон: войска дома (защищают державу)
	queue: { Recruit }, -- очередь найма
}

-- Отряд одного типа в пуле: суммарная сила и средний опыт (§6.7: ветераны).
export type Squad = { strength: number, xp: number }

-- Войска по типам — индексы как в Types.LandUnits.
export type Forces = { Squad }

export type Recruit = { kind: number, left: number }

-- Атака вдоль границы (§6.4) или фронт (§6.6): attacker тратит troops (людей) на ничью землю,
-- а forces (войска) воюют с державой target (0 — ничья земля).
export type Attack = {
	attacker: NationId,
	target: NationId,
	troops: number,
	focus: number?, -- клетка, к которой тянется атака
	forces: Forces, -- войска на этом фронте
	supplied: boolean, -- есть снабжение (§6.7)
	ratio: number, -- последний перевес: атака / оборона (math.huge — обороны нет)
	fighting: boolean, -- идёт бой (у защитника есть войска на этом фронте)
}

-- Сухопутные войска (флот и авиация — этап 7).
export type LandUnit = "Infantry" | "Tanks" | "Artillery" | "AntiAir"

-- Намерения игрока — всё, что клиент может попросить у сервера (GDD §0 п. 4).
export type PickIntent = { kind: "pick", cell: number }
export type AttackIntent = { kind: "attack", target: NationId, percent: number, focus: number? }
export type CancelIntent = { kind: "cancel", target: NationId }
export type HireIntent = { kind: "hire", unit: LandUnit }
-- Война и мир (§6.7а).
export type PeaceTerms = "white" | "keep" | "capitulate"
export type DeclareIntent = { kind: "declare", target: NationId }
export type PeaceIntent = { kind: "peace", target: NationId, terms: PeaceTerms }
export type PeaceReplyIntent = { kind: "peaceReply", target: NationId, accept: boolean }
export type Intent =
	PickIntent
	| AttackIntent
	| CancelIntent
	| HireIntent
	| DeclareIntent
	| PeaceIntent
	| PeaceReplyIntent

export type Phase = "Waiting" | "Pick" | "Play"

return Types
