--!strict
--[[
	StrikeForecast — прогноз удара до пуска (§15х «Понятные удары и защита»): дойдёт ли удар до клетки или его собьют
	и чем. Чистый модуль, правило — как у сервера (MatchSim.defenders / intercept / interceptCharges): защищают
	батареи ПВО (радиус Buildings.AirDefense.radius), а против ракет и бомб ПВО ур. 3 — дальняя (longRadius на ширину
	UnitsReferenceMapWidth, §15х ч.6) хозяина клетки и его друзей по полному доверию, только с готовыми зарядами; ближайшая —
	первой. Ракета и налёт сбиваются одним зарядом, бомба — Nukes.Atom / Hydrogen.charges зарядами (не хватает — заряды не
	тратятся, бомба дойдёт). Налёт: бомбу сбивает заряд батареи ПВО (как ракету), а сам бомбардировщик в пути
	обстреливают батареи и перехватывают истребители врага (их число у цели — предупреждение, не «собьют»).
	Данные — что знает клиент: здания (cs.buildings), заряды (cs.world.batteries), самолёты (cs.air.planes).
]]

local Config = require("./Config")

export type Kind = "raid" | "missile" | "atom" | "hydrogen"

export type Defense = { cell: number, kind: string, ready: number, max: number, level: number? }

export type Fighter = { x: number, y: number } -- истребитель врага (где он сейчас)

export type Input = {
	width: number,
	cell: number, -- куда бьём
	kind: Kind,
	victim: number, -- хозяин клетки (0 — ничья)
	ownerAt: (cell: number) -> number,
	friends: { [number]: boolean }, -- друзья цели по полному доверию (их ПВО тоже прикрывает)
	defenses: { Defense }, -- все батареи ПВО на карте с зарядами и уровнем
	fighters: { Fighter }?, -- истребители врага (только для налёта)
}

-- long — накрывает дальним кругом (ПВО ур. 3 против ракет и боеголовок).
export type Cover = { cell: number, kind: string, ready: number, max: number, dist: number, long: boolean }

export type Result = {
	covers: { Cover }, -- защита в радиусе (с зарядом и без), ближайшая — первой
	ready: number, -- готовых зарядов в радиусе
	need: number, -- сколько зарядов нужно, чтобы сбить
	stopped: boolean, -- удар собьют
	fighters: number, -- истребителей врага у цели (налёт): самолёт могут сбить в пути
}

local StrikeForecast = {}

-- Сколько зарядов сбивает удар этого вида.
function StrikeForecast.need(kind: Kind): number
	if kind == "atom" then
		return Config.Nukes.Atom.charges
	elseif kind == "hydrogen" then
		return Config.Nukes.Hydrogen.charges
	end
	return 1
end

-- Радиус защиты батареи ПВО уровня level на карте шириной width (как у сервера): против ракет и боеголовок
-- (vsMissile) ПВО ур. 3 бьёт дальним кругом (§15х ч.6), против налётов — всегда ближним.
function StrikeForecast.radius(level: number, width: number, vsMissile: boolean): number
	local cfg = Config.Buildings.AirDefense
	if vsMissile and level >= cfg.longRangeLevel then
		return math.max(cfg.radius, cfg.longRadius * width / Config.UnitsReferenceMapWidth) -- не меньше ближнего
	end
	return cfg.radius
end

function StrikeForecast.compute(input: Input): Result
	local w = input.width
	local cx, cy = input.cell % w, input.cell // w
	local vsMissile = input.kind ~= "raid"
	local covers: { Cover } = {}
	local ready = 0
	if input.victim ~= 0 then
		for _, d in input.defenses do
			if d.kind == "AirDefense" then
				local owner = input.ownerAt(d.cell)
				if owner == input.victim or input.friends[owner] then
					local level = d.level or 1
					local r = StrikeForecast.radius(level, w, vsMissile)
					local dx, dy = d.cell % w - cx, d.cell // w - cy
					local dist = dx * dx + dy * dy
					if dist <= r * r then
						local kindName: string = d.kind
						local near = Config.Buildings.AirDefense.radius
						local cover: Cover = {
							cell = d.cell,
							kind = kindName,
							ready = d.ready,
							max = d.max,
							dist = dist,
							long = dist > near * near,
						}
						table.insert(covers, cover)
						ready += d.ready
					end
				end
			end
		end
	end
	table.sort(covers, function(a: Cover, b: Cover): boolean
		return if a.dist ~= b.dist then a.dist < b.dist else a.cell < b.cell
	end)
	local need = StrikeForecast.need(input.kind)
	local fighters = 0
	if input.kind == "raid" then
		local reach = Config.Air.InterceptRadius * w / Config.UnitsReferenceMapWidth
		local list: { Fighter } = input.fighters or {}
		for _, f in list do
			if (f.x - cx) ^ 2 + (f.y - cy) ^ 2 <= reach * reach then
				fighters += 1
			end
		end
	end
	return {
		covers = covers,
		ready = ready,
		need = need,
		stopped = ready >= need,
		fighters = fighters,
	}
end

return table.freeze(StrikeForecast)
