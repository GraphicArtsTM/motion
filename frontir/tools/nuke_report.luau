--!strict
--[[
	Замер боеголовок (после внешнего обзора: «водородная бомба — почти втрое больше площади, проверить на картах»).
	Только замер — правила игры не меняет.

	lune run tools/nuke_report [карты=Europe,World,Scandinavia] [минуты=4,5,7,8,9,11,12,13] [база сидов=9100] [целей на державу=4]
	На каждой карте — партия ботов (держав — как в игре на этой карте, RealMaps.*.Nations), снимки на этих минутах (победа выключена). Потом «удары» без изменения матча: по столице и
	случайным клеткам каждой живой державы, каждой боеголовкой (ракета, атомная, водородная), как MatchSim.nukeImpact /
	missileImpact, если запустивший воюет только с жертвой. Считаем, что теряет жертва:
	- клетки (и долю всей её суши), здания (кроме городов), уровни городов;
	- гарнизон (Nukes.*.garrisonLossMul / maxGarrisonLoss) и войска фронтов, линия которых касается круга;
	- всё то же на $1000 цены (ракета — без цены: только шахта и перезарядка).
	Итог — build/nuke_report.json.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")

local mapList = string.split(process.args[1] or "Europe,World,Scandinavia", ",")
local minutes: { number } = {}
for _, part in string.split(process.args[2] or "4,5,7,8,9,11,12,13", ",") do
	table.insert(minutes, tonumber(part) :: number)
end
local seedBase = tonumber(process.args[3]) or 9100
local perNation = tonumber(process.args[4]) or 4
local dt = 1 / Config.Sim.TickRate
local WARHEADS: { Types.Warhead } = { "missile", "atom", "hydrogen" }

type Acc = { [string]: number }
local function bump(a: Acc, key: string, v: number)
	a[key] = (a[key] or 0) + v
end

-- Что потеряет жертва от удара warhead по cell (матч не меняется).
local function impact(m: MatchSim.Match, victim: number, cell: number, warhead: Types.Warhead): Acc
	local g = m.grid
	local w = g.width
	local nuke = MatchSim.nukeConfig(warhead)
	local r = MatchSim.warheadRadius(m, warhead)
	local cx, cy = cell % w, cell // w
	local out: Acc = { cells = 0, buildings = 0, cityLevels = 0, garrison = 0, front = 0, share = 0 }
	local owned = math.max(1, Grid.cellsOf(g, victim))
	for dy = -r, r do
		for dx = -r, r do
			local x, y = cx + dx, cy + dy
			if x >= 0 and y >= 0 and x < w and y < g.height and dx * dx + dy * dy <= r * r then
				local i = y * w + x
				if Grid.isCapturable(g, i) and Grid.getOwner(g, i) == victim then
					out.cells += 1
				end
			end
		end
	end
	out.share = out.cells / owned
	for bcell, b in m.buildings.byCell do
		local dx, dy = bcell % w - cx, bcell // w - cy
		if dx * dx + dy * dy <= r * r and Grid.getOwner(g, bcell) == victim then
			if b.kind == "City" then
				-- Бомба — до ур. 1; ракета — −1 уровень (strikeDamage).
				out.cityLevels += if nuke ~= nil then math.max(0, b.level - 1) else (if b.level > 1 then 1 else 0)
			else
				out.buildings += if nuke ~= nil then 1 else (if b.level > 1 then 0 else 1)
			end
		end
	end
	local nation = m.nations[victim]
	if nuke ~= nil and nation ~= nil then
		local loss = math.min(nuke.maxGarrisonLoss, out.cells / owned * nuke.garrisonLossMul)
		out.garrison = Forces.total(nation.home) * loss
	end
	local frontLoss = if nuke ~= nil then nuke.frontLoss else Config.Missile.FrontLoss
	for _, a in m.attacks do
		if a.target == victim or a.attacker == victim then
			local line = a.line
			if line ~= nil then
				for _, c in line do
					local dx, dy = c % w - cx, c // w - cy
					if dx * dx + dy * dy <= r * r then
						out.front += Forces.total(a.forces) * frontLoss
						break
					end
				end
			end
		end
	end
	return out
end

local KEYS = { "cells", "share", "buildings", "cityLevels", "garrison", "front" }
local report: { [string]: any } = { minutes = minutes, seedBase = seedBase, maps = {} }
local t0 = os.clock()
for mi, mapName in mapList do
	local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
	local m = MatchSim.new(map, seedBase + mi)
	local mapCfg = (Config.RealMaps :: any)[mapName]
	m.targetNations = if mapCfg ~= nil and mapCfg.Nations ~= nil then mapCfg.Nations else 12 -- как в игре на этой карте
	m.victory = false -- матч не кончается до нужной минуты
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, dt)
	end
	local rng = Rng.new(seedBase * 7 + mi)
	local sums: { [string]: Acc } = {}
	local counts: { [string]: number } = {}
	local cityHits: { [string]: number } = {}
	local radius: { [string]: number } = {}
	for _, wh: Types.Warhead in WARHEADS do
		sums[wh], counts[wh], cityHits[wh] = {}, 0, 0
		radius[wh] = MatchSim.warheadRadius(m, wh)
	end
	local victims, fronts = 0, 0
	for _, minute in minutes do
		while m.time < minute * 60 do
			MatchSim.step(m, dt)
		end
		for _, a in m.attacks do
			if a.target ~= 0 then
				fronts += 1
			end
		end
		for _, n in m.nations do
			if n.alive and Grid.cellsOf(m.grid, n.id) > 0 then
				victims += 1
				local targets: { number } = {}
				if n.capital ~= nil then
					table.insert(targets, n.capital :: number)
				end
				-- Случайные клетки державы: перебор клеток сетки — по равномерной выборке индексов.
				local tries = 0
				while #targets < perNation and tries < 20000 do
					tries += 1
					local i = math.floor(Rng.nextFloat(rng) * m.grid.size)
					if Grid.getOwner(m.grid, i) == n.id then
						table.insert(targets, i)
					end
				end
				for _, cell in targets do
					for _, wh: Types.Warhead in WARHEADS do
						local hit = impact(m, n.id, cell, wh)
						bump(sums[wh], "radius", MatchSim.warheadRadius(m, wh))
						for _, k in KEYS do
							bump(sums[wh], k, hit[k] or 0)
						end
						counts[wh] += 1
						if hit.cityLevels > 0 or hit.buildings > 0 then
							cityHits[wh] += 1
						end
					end
				end
			end
		end
	end
	local rows: { [string]: any } = {}
	print(
		string.format(
			"\n«%s» %d×%d, минуты %s, держав в снимках %d, фронтов в снимках %d, ударов на боеголовку %d",
			mapName,
			m.grid.width,
			m.grid.height,
			table.concat(minutes :: { any }, ","),
			victims,
			fronts,
			counts.atom
		)
	)
	for _, wh: Types.Warhead in WARHEADS do
		local nuke = MatchSim.nukeConfig(wh)
		local n = math.max(1, counts[wh])
		local row: { [string]: number } =
			{ radius = (sums[wh].radius or 0) / n, cost = if nuke ~= nil then nuke.cost else 0 }
		for _, k in KEYS do
			row[k] = (sums[wh][k] or 0) / n
		end
		row.hitsSomething = cityHits[wh] / n
		local per = if nuke ~= nil then 1000 / nuke.cost else nil
		row.cellsPer1k = if per ~= nil then row.cells * per else 0
		row.troopsPer1k = if per ~= nil then (row.garrison + row.front) * per else 0
		rows[wh] = row
		print(
			string.format(
				"  %-8s r=%4.1f  клеток %6.0f (%4.1f%% суши жертвы)  зданий %4.1f  ур. городов %4.1f  гарнизон −%6.0f  фронты −%6.0f%s",
				wh,
				row.radius,
				row.cells,
				row.share * 100,
				row.buildings,
				row.cityLevels,
				row.garrison,
				row.front,
				if per ~= nil
					then string.format(
						"  · на $1000: %4.0f клеток, %5.0f войск",
						row.cellsPer1k,
						row.troopsPer1k
					)
					else ""
			)
		)
	end
	local a, h = rows.atom, rows.hydrogen
	print(
		string.format(
			"  водородная / атомная: цена ×%.2f, клеток ×%.2f, войск ×%.2f, клеток на $ ×%.2f, войск на $ ×%.2f",
			h.cost / a.cost,
			h.cells / math.max(1e-9, a.cells),
			(h.garrison + h.front) / math.max(1e-9, a.garrison + a.front),
			h.cellsPer1k / math.max(1e-9, a.cellsPer1k),
			h.troopsPer1k / math.max(1e-9, a.troopsPer1k)
		)
	)
	report.maps[mapName] = rows
end
print(string.format("\nИТОГ: %d карт, %.0f с", #mapList, os.clock() - t0))
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile("build/nuke_report.json", serde.encode("json", report, true))
