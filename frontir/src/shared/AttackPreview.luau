--!strict
--[[
	AttackPreview — прогноз до атаки (§15н ч.2): какой будет перевес, если ударить по соседу сейчас долей войск
	с ползунка. Чистый модуль: данные — то, что знает клиент (Source), формула боя — общая с сервером
	(FrontForecast.preview → Fronts.battle без потерь).

	- Наши войска на фронт: доля гарнизона по типам, с опытом; уже идущий фронт против него — плюсом («подкрепление»).
	- Оборона: гарнизон врага по силе и составу из статистики (опыт неизвестен — 0), поровну между видимыми фронтами
	  против него; его встречный фронт против нас.
	- Местность, берег реки и укрепления — по его клеткам на нашей границе возле курсора (Forecast.PreviewRadius).
	- Снабжение — средняя дальность от этих клеток до нашего или дружеского города (как Fronts.supplied).
	Не знает: «укреплённую линию», способности генерала, котлы, технологии снабжения и брони.
]]

local Config = require("./Config")
local Forces = require("./Forces")
local FrontForecast = require("./FrontForecast")
local MapData = require("./MapData")
local Protocol = require("./Net/Protocol")
local Types = require("./Types")

type MapData = MapData.MapData

export type Source = {
	width: number,
	height: number,
	map: MapData,
	ownerAt: (cell: number) -> number,
	me: number,
	myKinds: { Protocol.KindForces }, -- свои войска по типам (Types.LandUnits): дома и опыт
	nations: { Protocol.NationStats }, -- статистика держав: сила и состав гарнизона
	attacks: { Protocol.AttackStats }, -- видимые фронты
	cities: { number }, -- клетки городов (хозяин — по ownerAt)
	friends: { [number]: boolean }, -- чьи города снабжают нас (мы, союзники, вассалы, сюзерен)
	buildings: { [number]: Types.Building }, -- клетка → здание
}

export type Result = {
	ratio: number, -- перевес после удара (с нашим уже идущим фронтом)
	state: FrontForecast.State,
	why: number, -- номер причины в FrontForecast.Whys (0 — нет)
	need: number, -- силы до полной скорости
	existing: number?, -- перевес нашего фронта против него сейчас (nil — фронта нет)
	known: boolean, -- его силы известны (иначе — грубая оценка, §6.11а)
	samples: number, -- клеток его границы у курсора
}

local AttackPreview = {}

local RIVER = Types.Terrain.River

-- Войска по силе и составу (опыт неизвестен).
local function forcesOf(total: number, mix: { number }): Types.Forces
	local f = Forces.new()
	for kind, share in mix do
		if share > 0 then
			Forces.add(f, kind, total * share, 0)
		end
	end
	return f
end

-- Его клетки на нашей границе возле cell: { клетка, на берегу реки (через реку от нас) }.
local function borderNear(src: Source, enemy: number, cell: number): { { cell: number, river: boolean } }
	local w, h = src.width, src.height
	local r = math.max(2, math.round(Config.Forecast.PreviewRadius * w / Config.UnitsReferenceMapWidth))
	local cx, cy = cell % w, cell // w
	local out: { { cell: number, river: boolean } } = {}
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for dy = -r, r do
		for dx = -r, r do
			local x, y = cx + dx, cy + dy
			if x >= 0 and y >= 0 and x < w and y < h and dx * dx + dy * dy <= r * r then
				local j = y * w + x
				if src.ownerAt(j) == enemy then
					local touches, river = false, false
					for _, d in dirs do
						local nx, ny = x + d[1], y + d[2]
						if nx >= 0 and ny >= 0 and nx < w and ny < h then
							local n = ny * w + nx
							if src.ownerAt(n) == src.me then
								touches = true
							elseif MapData.getTerrain(src.map, n) == RIVER then
								-- Через реку (до RiverMaxWidth клеток воды) — наша клетка: берег реки.
								for step = 2, Config.Combat.RiverMaxWidth + 1 do
									local fx, fy = x + d[1] * step, y + d[2] * step
									if fx < 0 or fy < 0 or fx >= w or fy >= h then
										break
									end
									local far = fy * w + fx
									if MapData.getTerrain(src.map, far) ~= RIVER then
										if src.ownerAt(far) == src.me then
											touches, river = true, true
										end
										break
									end
								end
							end
						end
					end
					if touches then
						table.insert(out, { cell = j, river = river })
					end
				end
			end
		end
	end
	return out
end

-- Прогноз удара по enemy у клетки cell долей percent гарнизона. nil — у курсора нет нашей общей границы с ним.
function AttackPreview.compute(src: Source, enemy: number, cell: number, percent: number): Result?
	local stats: Protocol.NationStats? = nil
	for _, n in src.nations do
		if n.id == enemy then
			stats = n
		end
	end
	if stats == nil then
		return nil
	end
	local border = borderNear(src, enemy, cell)
	if #border == 0 then
		return nil
	end
	-- Местность, берег, укрепления (как Fronts.terrainDefense: средние по клеткам линии).
	local w = src.width
	local fortOf: { [number]: number } = {} -- провинция → лучшее его укрепление
	for bcell, b in src.buildings do
		if b.kind == "Fort" and src.ownerAt(bcell) == enemy then
			local p = MapData.getProvince(src.map, bcell)
			local mul = Config.Buildings.Fort.defenseByLevel[b.level] or Config.Buildings.Fort.defenseMultiplier
			fortOf[p] = math.max(fortOf[p] or 1, mul)
		end
	end
	local plain, withRiver, full = 0, 0, 0
	for _, s in border do
		local d = Config.Terrain[MapData.getTerrain(src.map, s.cell)].defense
		local r = d * (if s.river then Config.Combat.RiverBankDefense else 1)
		plain += d
		withRiver += r
		full += r * (fortOf[MapData.getProvince(src.map, s.cell)] or 1)
	end
	plain /= #border
	withRiver /= #border
	full /= #border
	-- Снабжение: средняя дальность от клеток линии до ближайшего нашего или дружеского города.
	local mine: { number } = {}
	for _, c in src.cities do
		local owner = src.ownerAt(c)
		if owner ~= 0 and (owner == src.me or src.friends[owner]) then
			table.insert(mine, c)
		end
	end
	local supplied = false
	if #mine > 0 then
		local sum = 0
		for _, s in border do
			local best = math.huge
			for _, c in mine do
				best = math.min(best, (s.cell % w - c % w) ^ 2 + (s.cell // w - c // w) ^ 2)
			end
			sum += math.sqrt(best)
		end
		supplied = sum / #border <= Config.Combat.SupplyRange * w / Config.UnitsReferenceMapWidth
	end
	-- Его гарнизон — поровну между фронтами против него (наш — один из них); встречный фронт — против нас.
	local others, existing = 0, nil :: number?
	local counter: Types.Forces? = nil
	local attack = Forces.new()
	for kind, k in src.myKinds do
		if k.home > 0 then
			Forces.add(attack, kind, k.home * percent, k.xp)
		end
	end
	for _, a in src.attacks do
		if a.target == enemy and a.attacker ~= src.me then
			others += 1
		elseif a.attacker == src.me and a.target == enemy then
			existing = a.ratio
			Forces.merge(attack, forcesOf(math.max(0, a.power), a.mix))
		elseif a.attacker == enemy and a.target == src.me then
			counter = forcesOf(math.max(0, a.power), a.mix)
		end
	end
	local p = FrontForecast.preview({
		attack = attack,
		defenders = forcesOf(math.max(0, stats.power), stats.mix),
		share = 1 / (1 + others),
		counter = counter,
		supplied = supplied,
		plain = plain,
		river = withRiver / math.max(plain, 1e-6),
		forts = full / math.max(withRiver, 1e-6),
	})
	return {
		ratio = p.ratio,
		state = p.state,
		why = p.why,
		need = p.need,
		existing = existing,
		known = stats.troops >= 0,
		samples = #border,
	}
end

return table.freeze(AttackPreview)
