--!strict
--[[
	Метрики ботов (внешний обзор, §9: «не только число побед»). Только замер — правила и боты не меняются.

	lune run tools/bot_metrics [партий=20] [карта=Europe] [держав=12] [база сидов=11000]
	Полные партии ботов; всё — по уровням ботов (Новичок / Обычный / Генерал):
	1. Цель войны: перевес силы над целью при объявлении, доля войн на самого слабого соседа, доля «выгодных» войн
	   (к концу войны объявивший прибавил землю, цель потеряла).
	2. Войска: доля силы на фронтах, пока идёт война; доля времени «война есть, фронта нет».
	3. Отступление: войны, где враг стал вдвое сильнее (`LosingMul`), — сколько кончились миром, а сколько гибелью.
	4. Экономика: доля зданий, потерянных врагу (захват или разрушение), от наибольшего числа зданий.
	5. Против лидера: доля новых войн бота против лидера по суше (к победе, с вассалами) и «справедливая» доля.
	6. Десант: кораблей с войсками на партию, доля высадок, взявших землю, потоплено с грузом.
	7. Ракеты и бомбы: пусков на партию по видам, доля сбитых, клеток за попадание, доля пусков по лидеру.
	Итог — build/bot_metrics.json.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local Forces = require("../src/shared/Forces")
local Grid = require("../src/shared/Grid")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")
local Wars = require("../src/shared/Wars")

local games = tonumber(process.args[1]) or 20
local mapName = process.args[2] or "Europe"
local nations = tonumber(process.args[3]) or 12
local seedBase = tonumber(process.args[4]) or 11000
local map = MapFormat.fromModule((require :: any)("../maps/" .. mapName) :: MapFormat.MapModule)
local dt = 1 / Config.Sim.TickRate
local SAMPLE_SEC = 10
local LosingMul = 2 -- «проигрывает»: враг сильнее во столько раз
local LEVELS = { "Novice", "Normal", "General" }

type Acc = { sum: number, n: number }
type Level = { [string]: Acc }
local stats: { [string]: Level } = {}
local function add(level: string, key: string, v: number?)
	if v == nil or v ~= v or v == math.huge then
		return
	end
	local l = stats[level]
	if l == nil then
		l = {}
		stats[level] = l
	end
	local a = l[key]
	if a == nil then
		a = { sum = 0, n = 0 }
		l[key] = a
	end
	a.sum += v
	a.n += 1
end
local function mean(level: string, key: string): number?
	local l = stats[level]
	local a = if l ~= nil then l[key] else nil
	return if a ~= nil and a.n > 0 then a.sum / a.n else nil
end
local function total(level: string, key: string): number
	local l = stats[level]
	local a = if l ~= nil then l[key] else nil
	return if a ~= nil then a.sum else 0
end

-- Медианы (перевес при объявлении: среднее раздувают крошечные цели).
local samples: { [string]: { [string]: { number } } } = {}
local function sample(level: string, key: string, v: number)
	local l = samples[level]
	if l == nil then
		l = {}
		samples[level] = l
	end
	local list = l[key]
	if list == nil then
		list = {}
		l[key] = list
	end
	table.insert(list, v)
end
local function median(level: string, key: string): number?
	local l = samples[level]
	local list = if l ~= nil then l[key] else nil
	if list == nil or #list == 0 then
		return nil
	end
	table.sort(list)
	return list[(#list + 1) // 2]
end

local decisions: { [string]: { [string]: number } } = {} -- уровень → решение → сколько раз

local function levelOf(m: MatchSim.Match, id: number): string?
	local n = m.nations[id]
	return if n ~= nil and n.isBot then n.botLevel else nil
end

local t0 = os.clock()
for k = 1, games do
	local seed = seedBase + k * 41
	local m = MatchSim.new(map, seed)
	m.targetNations = nations
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, dt)
	end
	for _, n in m.nations do
		local lv = levelOf(m, n.id)
		if lv ~= nil then
			add(lv, "nationGames", 1)
		end
	end
	-- Состояние партии для метрик.
	type WarTrack = { a: number, b: number, aCells: number, bCells: number, losing: { [number]: boolean } }
	local wars: { [number]: WarTrack } = {}
	local buildingOwner: { [number]: number } = {}
	local everBuildings: { [number]: { [number]: boolean } } = {} -- держава → клетки зданий, что у неё были
	local lostBuildings: { [number]: { [number]: boolean } } = {} -- держава → клетки зданий, потерянных врагу
	local nextSample = 0
	local function pairKey(a: number, b: number): number
		return math.min(a, b) * 65536 + math.max(a, b)
	end
	local function leader(): number
		local best, bestLand = 0, -1
		for _, n in m.nations do
			if n.alive then
				local land = MatchSim.victoryLandOf(m, n.id)
				if land > bestLand then
					best, bestLand = n.id, land
				end
			end
		end
		return best
	end
	-- Война кончилась: итог для объявившего.
	local function closeWar(key: number, w: WarTrack)
		local lv = levelOf(m, w.a)
		if lv ~= nil then
			local gain = Grid.cellsOf(m.grid, w.a) - w.aCells
			local targetLoss = w.bCells - Grid.cellsOf(m.grid, w.b)
			add(lv, "warWon", if gain > 0 and targetLoss > 0 then 1 else 0)
		end
		for id in w.losing do
			local lvl = levelOf(m, id)
			local n = m.nations[id]
			if lvl ~= nil and n ~= nil then
				add(lvl, "losingPeace", if n.alive then 1 else 0)
			end
		end
		wars[key] = nil
	end
	-- Решения ботов, пока у них «война без фронта» (что вытесняет атаку и почему сервер отказывает).
	local idleNow: { [number]: string? } = {} -- держава → причина «войны без фронта» (nil — фронт есть)
	m.onBotIntent = function(id: number, intent: Types.Intent?, ok: boolean, reason: string?)
		local lv = levelOf(m, id)
		local why = idleNow[id]
		if lv == nil or why == nil then
			return
		end
		local key = why
			.. ": "
			.. (
				if intent == nil then "ничего" else intent.kind .. (if ok then "" else " ✗" .. tostring(reason))
			)
		decisions[lv] = decisions[lv] or {}
		decisions[lv][key] = (decisions[lv][key] or 0) + 1
	end
	local limit = m.rules.timeLimitSec + 5
	while m.phase == "Play" and m.time < limit do
		MatchSim.step(m, dt)
		for _, ev in MatchSim.takeEvents(m) do
			local e = ev :: any -- поля у видов событий разные
			local lv = levelOf(m, e.nation or 0)
			if e.kind == "warDeclared" and lv ~= nil then
				local a, b = e.nation :: number, e.target :: number
				local mine = MatchSim.totalPower(m, a)
				local theirs = math.max(1, MatchSim.totalPower(m, b))
				sample(lv, "declareRatio", mine / theirs)
				add(lv, "declaredStronger", if mine < theirs then 1 else 0)
				-- Самый слабый сосед по суше?
				local weakest, weakestPower = 0, math.huge
				for owner in Grid.adjacentOwners(m.grid, a) do
					if owner ~= 0 and m.nations[owner] ~= nil and m.nations[owner].alive then
						local p = MatchSim.totalPower(m, owner)
						if p < weakestPower then
							weakest, weakestPower = owner, p
						end
					end
				end
				if weakest ~= 0 then
					add(lv, "weakestTarget", if weakest == b then 1 else 0)
				end
				local lead = leader()
				local alive = 0
				for _, n in m.nations do
					alive += if n.alive then 1 else 0
				end
				if lead ~= a and alive > 2 then
					add(lv, "onLeader", if b == lead then 1 else 0)
					add(lv, "onLeaderFair", 1 / (alive - 1))
				end
				wars[pairKey(a, b)] = {
					a = a,
					b = b,
					aCells = Grid.cellsOf(m.grid, a),
					bCells = Grid.cellsOf(m.grid, b),
					losing = {},
				}
			elseif e.kind == "boatLaunched" and lv ~= nil then
				add(lv, "boats", 1)
			elseif e.kind == "landed" and lv ~= nil then
				add(lv, "landed", 1) -- и десантные корабли, и транспорты из порта
				add(lv, "landedTook", if (e.cells or 0) > 0 then 1 else 0)
			elseif e.kind == "shipSunk" and lv ~= nil and (e.lost or 0) > 0 then
				add(lv, "sunkCargo", 1)
			elseif e.kind == "missileLaunched" and lv ~= nil then
				add(lv, "launch_" .. tostring(e.warhead or "missile"), 1)
				add(lv, "launchOnLeader", if e.target == leader() then 1 else 0)
				local cap = if m.nations[e.target] ~= nil then m.nations[e.target].capital else nil
				if cap ~= nil then
					local w = m.grid.width
					local r = MatchSim.warheadRadius(m, e.warhead or "missile")
					local dx, dy = (cap :: number) % w - e.cell % w, (cap :: number) // w - e.cell // w
					add(lv, "launchAtCapital", if dx * dx + dy * dy <= r * r then 1 else 0)
				end
			elseif e.kind == "missileShot" and lv ~= nil then
				add(lv, "shot", 1)
			elseif (e.kind == "nukeHit" or e.kind == "missileHit") and lv ~= nil then
				add(lv, "hitCells", e.cells or 0)
			end
		end
		if m.time >= nextSample then
			nextSample = m.time + SAMPLE_SEC
			-- Войны: кончились ли, кто проигрывает.
			local live: { [number]: Wars.War } = {}
			for _, w in m.wars.list do
				live[pairKey(w.a, w.b)] = w
			end
			for key, w in wars do
				if live[key] == nil then
					closeWar(key, w)
				end
			end
			for key, w in live do
				local track = wars[key]
				if track ~= nil and w.state == "active" then
					local pa, pb = MatchSim.totalPower(m, w.a), MatchSim.totalPower(m, w.b)
					if pb > pa * LosingMul then
						track.losing[w.a] = true
					elseif pa > pb * LosingMul then
						track.losing[w.b] = true
					end
				end
			end
			-- Войска в войне.
			for _, n in m.nations do
				local lv = levelOf(m, n.id)
				if lv ~= nil and n.alive then
					local atWar = false
					for _, w in m.wars.list do
						if w.state == "active" and (w.a == n.id or w.b == n.id) then
							atWar = true
							break
						end
					end
					if atWar then
						local front = Forces.total(MatchSim.frontForces(m, n.id))
						local home = Forces.total(n.home)
						local fronts = 0
						for _, a in m.attacks do
							if a.attacker == n.id and a.target ~= 0 then
								fronts += 1
							end
						end
						if front + home > 0 then
							add(lv, "frontShare", front / (front + home))
						end
						add(lv, "idleWar", if fronts == 0 then 1 else 0)
						idleNow[n.id] = nil
						if fronts == 0 then
							-- Почему фронта нет (первая подходящая причина): враг не сосед по суше; войск на фронт
							-- меньше MinFrontStrength; все слоты атак заняты; недавно отступил; иначе — «другое»
							-- (решение ещё не дошло до фронта: стройка, найм, мир, дипломатия, ошибка уровня).
							local adjacent = Grid.adjacentOwners(m.grid, n.id)
							local enemies, near = 0, 0
							local retreating = true
							local memory = m.botMemory[n.id]
							local declared = false
							for _, w in m.wars.list do
								if w.state == "active" and (w.a == n.id or w.b == n.id) then
									local enemy = if w.a == n.id then w.b else w.a
									enemies += 1
									declared = declared or w.a == n.id
									if adjacent[enemy] ~= nil then
										near += 1
										local untilT = if memory ~= nil then memory.retreatUntil[enemy] else nil
										if untilT == nil or m.simTime >= untilT then
											retreating = false
										end
									end
								end
							end
							local profile = m.botProfiles[n.id]
							local frontPercent = if profile ~= nil
								then math.clamp(profile.level.frontPercent * profile.personality.front, 0.1, 0.9)
								else 0.5
							local attacks = 0
							for _, a in m.attacks do
								if a.attacker == n.id then
									attacks += 1
								end
							end
							local reason = if near == 0
								then "idleNoBorder"
								elseif home * frontPercent < Config.Forces.MinFrontStrength then "idleWeak"
								elseif attacks >= Config.Bots.MaxAttacks then "idleSlots"
								elseif retreating then "idleRetreat"
								else "idleOther"
							for _, key in { "idleNoBorder", "idleWeak", "idleSlots", "idleRetreat", "idleOther" } do
								add(lv, key, if key == reason then 1 else 0)
							end
							add(lv, "idleDefender", if declared then 0 else 1)
							idleNow[n.id] = reason
						end
					end
				end
			end
			-- Здания: захвачены или разрушены.
			local now: { [number]: number } = {}
			for cell in m.buildings.byCell do
				now[cell] = Grid.getOwner(m.grid, cell)
			end
			-- Потеря: у здания сменился хозяин (захват) или оно исчезло вместе с землёй (удар, захват). Снос своего
			-- здания (земля осталась своей) — не потеря.
			for cell, owner in buildingOwner do
				local cur = now[cell]
				if
					owner ~= 0
					and ((cur ~= nil and cur ~= owner) or (cur == nil and Grid.getOwner(m.grid, cell) ~= owner))
				then
					lostBuildings[owner] = lostBuildings[owner] or {}
					lostBuildings[owner][cell] = true
				end
			end
			buildingOwner = now
			for cell, owner in now do
				everBuildings[owner] = everBuildings[owner] or {}
				everBuildings[owner][cell] = true
			end
		end
	end
	for key, w in wars do
		closeWar(key, w)
	end
	for _, n in m.nations do
		local lv = levelOf(m, n.id)
		local ever = everBuildings[n.id]
		if lv ~= nil and ever ~= nil then
			local had, lost = 0, 0
			for cell in ever do
				had += 1
				if lostBuildings[n.id] ~= nil and lostBuildings[n.id][cell] then
					lost += 1
				end
			end
			add(lv, "buildingsLost", lost / had)
		end
	end
	print(string.format("партия %2d (сид %d): %.1f мин", k, seed, m.time / 60))
end

local function pct(v: number?): string
	return if v ~= nil then string.format("%.0f%%", v * 100) else "—"
end
local function num(v: number?, f: string): string
	return if v ~= nil then string.format(f, v) else "—"
end
local summary: { [string]: any } = { games = games, map = mapName, nations = nations, seedBase = seedBase, levels = {} }
print(
	string.format(
		"\nИТОГ: %d партий «%s», %d держав, %.0f с",
		games,
		mapName,
		nations,
		os.clock() - t0
	)
)
for _, lv in LEVELS do
	local ng = math.max(1, total(lv, "nationGames"))
	local per = function(key: string): number
		return total(lv, key) / ng
	end
	local launches = total(lv, "launch_missile") + total(lv, "launch_atom") + total(lv, "launch_hydrogen")
	local row = {
		nationGames = total(lv, "nationGames"),
		declareRatio = median(lv, "declareRatio"),
		declaredStronger = mean(lv, "declaredStronger"),
		weakestTarget = mean(lv, "weakestTarget"),
		warWon = mean(lv, "warWon"),
		frontShare = mean(lv, "frontShare"),
		idleWar = mean(lv, "idleWar"),
		idleNoBorder = mean(lv, "idleNoBorder"),
		idleWeak = mean(lv, "idleWeak"),
		idleSlots = mean(lv, "idleSlots"),
		idleRetreat = mean(lv, "idleRetreat"),
		idleOther = mean(lv, "idleOther"),
		idleDefender = mean(lv, "idleDefender"),
		losingPeace = mean(lv, "losingPeace"),
		losingWars = total(lv, "losingPeace"),
		buildingsLost = mean(lv, "buildingsLost"),
		onLeader = mean(lv, "onLeader"),
		onLeaderFair = mean(lv, "onLeaderFair"),
		boatsPerGame = per("boats"),
		landingsPerGame = per("landed"),
		landedTook = mean(lv, "landedTook"),
		sunkCargoPerGame = per("sunkCargo"),
		missilesPerGame = per("launch_missile"),
		atomPerGame = per("launch_atom"),
		hydrogenPerGame = per("launch_hydrogen"),
		shotShare = if launches > 0 then total(lv, "shot") / launches else nil,
		cellsPerHit = mean(lv, "hitCells"),
		launchOnLeader = mean(lv, "launchOnLeader"),
		launchAtCapital = mean(lv, "launchAtCapital"),
	}
	summary.levels[lv] = row
	print(string.format("\n%s (%d держав-партий):", lv, row.nationGames))
	print(
		string.format(
			"  1. цель: перевес при объявлении (медиана) ×%s, на более сильного %s, самый слабый сосед %s, война выгодна %s",
			num(row.declareRatio, "%.2f"),
			pct(row.declaredStronger),
			pct(row.weakestTarget),
			pct(row.warWon)
		)
	)
	print(
		string.format(
			"  2. войска в войне: на фронтах %s, «война есть, фронта нет» %s времени",
			pct(row.frontShare),
			pct(row.idleWar)
		)
	)
	print(
		string.format(
			"     без фронта — почему: враг не сосед %s, мало войск %s, слоты атак заняты %s, отступил %s, другое %s; войну объявил не он %s",
			pct(row.idleNoBorder),
			pct(row.idleWeak),
			pct(row.idleSlots),
			pct(row.idleRetreat),
			pct(row.idleOther),
			pct(row.idleDefender)
		)
	)
	local list: { { key: string, count: number } } = {}
	local all = 0
	local byKind: { [string]: number } = decisions[lv] or {}
	for key, count in byKind do
		table.insert(list, { key = key, count = count })
		all += count
	end
	table.sort(list, function(x, y)
		return x.count > y.count
	end)
	local top: { string } = {}
	for i = 1, math.min(14, #list) do
		table.insert(top, string.format("%s %.0f%%", list[i].key, list[i].count / math.max(1, all) * 100))
	end
	print("     решения в это время: " .. table.concat(top, ", "))
	print(
		string.format(
			"  3. проигранные войны (враг ×%d сильнее): %d, кончились миром %s",
			LosingMul,
			row.losingWars,
			pct(row.losingPeace)
		)
	)
	print(
		string.format(
			"  4. экономика: потеряно врагу %s зданий из тех, что были",
			pct(row.buildingsLost)
		)
	)
	print(
		string.format(
			"  5. новые войны против лидера %s (справедливо %s)",
			pct(row.onLeader),
			pct(row.onLeaderFair)
		)
	)
	print(
		string.format(
			"  6. десант: десантных кораблей на державу-партию %s, всех высадок %s, высадок с землёй %s, потоплено с грузом %s",
			num(row.boatsPerGame, "%.2f"),
			num(row.landingsPerGame, "%.2f"),
			pct(row.landedTook),
			num(row.sunkCargoPerGame, "%.2f")
		)
	)
	print(
		string.format(
			"  7. удары на державу-партию: ракет %s, атомных %s, водородных %s; сбито %s; клеток за попадание %s; по лидеру %s; накрывают столицу %s",
			num(row.missilesPerGame, "%.2f"),
			num(row.atomPerGame, "%.2f"),
			num(row.hydrogenPerGame, "%.2f"),
			pct(row.shotShare),
			num(row.cellsPerHit, "%.0f"),
			pct(row.launchOnLeader),
			pct(row.launchAtCapital)
		)
	)
end
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile("build/bot_metrics.json", serde.encode("json", summary, true))
