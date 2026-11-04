--!strict
local serde = require("@lune/serde")

local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Buildings = require("../src/shared/Buildings")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapPaint = require("../src/shared/MapPaint")
local MatchSim = require("../src/shared/MatchSim")
local NationColors = require("../src/shared/NationColors")
local MatchStats = require("../src/shared/Net/MatchStats")
local Protocol = require("../src/shared/Net/Protocol")
local Rng = require("../src/shared/Rng")
local TerritoryPaint = require("../src/shared/TerritoryPaint")

local DT = 1 / Config.Sim.TickRate
local OVERHEAD = 16 -- оценка служебных байт Roblox на одно сообщение RemoteEvent (с запасом)

local function randomOwners(count: number, seed: number): buffer
	local rng = Rng.new(seed)
	local owners = buffer.create(count * 2)
	local i = 0
	while i < count do
		local run = Rng.range(rng, 1, 3)
		local owner = Rng.range(rng, 0, 40)
		for k = i, math.min(count, i + run) - 1 do
			buffer.writeu16(owners, k * 2, owner)
		end
		i += run
	end
	return owners
end

-- Что сервер разослал бы всем в этом тике: снимок частями или дельту.
local function deltaOf(m: MatchSim.Match): buffer
	return Protocol.encodeDelta(m.tick, Grid.takeChanges(m.grid), m.grid.owner)
end

T.describe("Protocol", function()
	T.it(
		"снимок большой сетки: несколько частей, собирается в любом порядке",
		function()
			local count = 200 * 200
			local owners = randomOwners(count, 1)
			local parts = Protocol.encodeSnapshot(77, owners, count)
			T.expect(#parts > 1).toBe(true)
			for _, p in parts do
				T.expect(buffer.len(p) <= Config.Net.SnapshotPartBytes + 13).toBe(true)
			end
			local a = Protocol.newAssembler()
			local result: buffer? = nil
			for k = #parts, 1, -1 do -- задом наперёд
				result = Protocol.assemble(a, Protocol.decodeSnapshotPart(parts[k]), count)
				if k > 1 then
					T.expect(result).toBe(nil)
				end
			end
			T.expect(result ~= nil and buffer.tostring(result) == buffer.tostring(owners)).toBe(true)
		end
	)

	T.it(
		"дельта туда и обратно; соседние клетки одного владельца стоят ~1 байт",
		function()
			local count = 1000
			local owners = buffer.create(count * 2)
			local cells = {}
			for i = 100, 399 do
				buffer.writeu16(owners, i * 2, 7)
				table.insert(cells, i)
			end
			buffer.writeu16(owners, 900 * 2, 3)
			table.insert(cells, 900)
			local msg = Protocol.encodeDelta(5, cells, owners)
			T.expect(buffer.len(msg) < #cells * 1.2 + 16).toBe(true)
			local d = Protocol.decodeDelta(msg, count)
			T.expect(d.tick).toBe(5)
			T.expect(d.cells).toEqual(cells)
			for k, i in d.cells do
				T.expect(d.owners[k]).toBe(buffer.readu16(owners, i * 2))
			end
		end
	)

	T.it("порченые сообщения — ошибка, а не мусор", function()
		local owners = buffer.create(20)
		local msg = Protocol.encodeDelta(1, { 2, 3, 9 }, owners)
		T.expect(function()
			Protocol.decodeDelta(msg, 5) -- клетка за пределами карты
		end).toThrow()
		local cut = buffer.create(buffer.len(msg) - 1)
		buffer.copy(cut, 0, msg, 0, buffer.len(cut))
		T.expect(function()
			Protocol.decodeDelta(cut, 10)
		end).toThrow()
		T.expect(function()
			Protocol.decodeStats(msg)
		end).toThrow()
	end)
end)

T.describe("Protocol: войска и фронты", function()
	T.it("статистика с войсками и фронтами туда и обратно", function()
		local s: Protocol.Stats = {
			tickMs = 2.5,
			changed = 77,
			nations = {
				{
					id = 4,
					people = 1234.5,
					maxPeople = 9000,
					cells = 4321,
					troops = 10,
					power = 3000,
					frontPower = 1500,
					cities = 6,
					mix = { 0.75, 0, 0.25, 0 },
					weariness = 0.35,
				},
			},
			attacks = {
				{
					attacker = 4,
					target = 2,
					troops = 0,
					power = 1500,
					mix = { 0.5, 0.25, 0.25, 0 },
					supplied = false,
					fighting = true,
					ratio = 1.75,
					focus = 123456,
				},
				{
					attacker = 4,
					target = 0,
					troops = 99,
					power = 0,
					mix = { 0, 0, 0, 0 },
					supplied = true,
					fighting = false,
					ratio = math.huge,
				},
			},
		}
		local back = Protocol.decodeStats(Protocol.encodeStats(s))
		T.expect(back.nations[1].power).toBe(3000)
		T.expect(back.nations[1].cities).toBe(6)
		local a = back.attacks[1]
		T.expect(a.supplied).toBe(false)
		T.expect(a.fighting).toBe(true)
		T.expect(a.ratio).toBeNear(1.75, 1 / 32)
		T.expect(a.mix[2]).toBeNear(0.25, 1 / 255)
		T.expect(a.focus).toBe(123456)
		T.expect(back.attacks[2].ratio).toBe(math.huge)
		T.expect(back.attacks[2].focus).toBe(nil)
		T.expect(back.nations[1].mix[3]).toBeNear(0.25, 1 / 255)
		T.expect(back.nations[1].weariness).toBeNear(0.35, 0.01)
	end)

	T.it("войны и запреты после мира туда и обратно", function()
		local msg: Protocol.WarsMessage = {
			wars = {
				{
					a = 3,
					b = 7,
					active = false,
					timeLeft = 12.3,
					age = 0,
					takenA = 0,
					takenB = 0,
					lossesA = 0,
					lossesB = 0,
					powerA = 4000,
					powerB = 2500,
					proposalFrom = 0,
					proposalTerms = "white",
					proposalLeft = 0,
				},
				{
					a = 1,
					b = 2,
					active = true,
					timeLeft = 0,
					age = 361,
					takenA = 1500,
					takenB = 20,
					lossesA = 800.5,
					lossesB = 2100,
					powerA = 6000,
					powerB = 900,
					proposalFrom = 2,
					proposalTerms = "keep",
					proposalLeft = 17.2,
				},
			},
			cooldowns = { { a = 4, b = 5, left = 42.5 } },
		}
		local back = Protocol.decodeWars(Protocol.encodeWars(msg))
		T.expect(#back.wars).toBe(2)
		T.expect(back.wars[1].active).toBe(false)
		T.expect(back.wars[1].timeLeft).toBeNear(12.3, 0.05)
		T.expect(back.wars[2].takenA).toBe(1500)
		T.expect(back.wars[2].lossesA).toBeNear(800.5, 1e-3)
		T.expect(back.wars[2].proposalFrom).toBe(2)
		T.expect(back.wars[2].proposalTerms).toBe("keep")
		T.expect(back.wars[2].proposalLeft).toBe(18)
		T.expect(back.cooldowns[1].b).toBe(5)
		T.expect(back.cooldowns[1].left).toBe(43)
	end)

	T.it("свои войска и очередь найма туда и обратно", function()
		local f: Protocol.MyForces = {
			kinds = {
				{ home = 900, xp = 1.5, front = 300 },
				{ home = 0, xp = 0, front = 600 },
				{ home = 250, xp = 0, front = 0 },
				{ home = 0, xp = 0, front = 0 },
			},
			queue = { { kind = 2, left = 3.5 }, { kind = 1, left = 3 } },
			economy = { money = 12345.5, oil = 42, income = 88.25, oilIncome = 2, upkeep = 31.5, factories = 1 },
		}
		local back = Protocol.decodeForces(Protocol.encodeForces(f))
		T.expect(back.kinds[1].xp).toBeNear(1.5, 1e-6)
		T.expect(back.kinds[2].front).toBe(600)
		T.expect(#back.queue).toBe(2)
		T.expect(back.queue[1].kind).toBe(2)
		T.expect(back.economy.money).toBeNear(12345.5, 1e-3)
		T.expect(back.economy.upkeep).toBeNear(31.5, 1e-6)
		T.expect(back.economy.factories).toBe(1)
	end)
end)

T.describe("Трафик", function()
	T.it("60 держав: трафик на клиента не больше Config.Net.BudgetBytesPerSec", function()
		local m = MatchSim.new(Fixtures.pangea, 60)
		m.targetNations = 60
		MatchSim.startPick(m)
		while m.phase ~= "Play" do
			MatchSim.step(m, DT)
		end
		T.expect(#m.nations).toBe(60)
		Grid.takeChanges(m.grid)
		local snapshot = 0
		for _, part in Protocol.encodeSnapshot(m.tick, m.grid.owner, m.grid.size) do
			snapshot += buffer.len(part) + OVERHEAD
		end
		-- info — таблица; её размер оцениваем по JSON (Roblox сериализует компактнее).
		local function infoBytes(): number
			local nations = {}
			for _, n in m.nations do
				table.insert(nations, {
					id = n.id,
					name = n.name,
					nameEn = n.nameEn,
					colorIndex = n.colorIndex,
					capital = n.capital,
					isBot = n.isBot,
					alive = n.alive,
				})
			end
			local info = {
				kind = "info",
				phase = m.phase,
				phaseLeft = 0,
				time = m.time,
				myNation = 1,
				nations = nations,
				cities = MatchSim.cities(m),
			}
			return #serde.encode("json", info) + OVERHEAD
		end
		local statsEvery = Config.Sim.TickRate // Config.Net.StatsHz
		local perTick: { number } = {}
		local diploVersion, diploAt = -1, -math.huge
		local infoAt = -math.huge
		for tick = 1, 180 * Config.Sim.TickRate do
			MatchSim.step(m, DT)
			local bytes = 0
			local changes = Grid.takeChanges(m.grid)
			if #changes > 0 then
				bytes += buffer.len(Protocol.encodeDelta(m.tick, changes, m.grid.owner)) + OVERHEAD
			end
			if tick % statsEvery == 0 then
				bytes += buffer.len(Protocol.encodeStats(MatchStats.build(m, 0, #changes))) + OVERHEAD
				bytes += buffer.len(Protocol.encodeForces(MatchStats.forcesOf(m, 1))) + OVERHEAD
				bytes += buffer.len(Protocol.encodeWars(MatchStats.wars(m))) + OVERHEAD
			end
			if m.infoDirty and m.time >= infoAt + Config.Net.InfoMinSec then
				m.infoDirty, infoAt = false, m.time
				bytes += infoBytes()
			end
			local built = Buildings.takeChanges(m.buildings)
			if #built > 0 then
				bytes += #serde.encode("json", { kind = "buildings", list = built }) + OVERHEAD
			end
			local events = MatchSim.takeEvents(m)
			if #events > 0 then
				bytes += #serde.encode("json", { kind = "events", events = events }) + OVERHEAD
			end
			-- Договоры (§8.1): как на сервере — при изменении, не чаще Net.DiploMinSec.
			local version = m.diplo.version + m.council.version * 65536
			if version ~= diploVersion and m.time >= diploAt + Config.Net.DiploMinSec then
				diploVersion, diploAt = version, m.time
				bytes += #serde.encode("json", MatchStats.diplo(m)) + OVERHEAD
			end
			table.insert(perTick, bytes)
		end
		-- Скользящее окно в 1 секунду.
		local window = Config.Sim.TickRate
		local sum, peak, total = 0, 0, 0
		for k, b in perTick do
			sum += b
			total += b
			if k > window then
				sum -= perTick[k - window]
			end
			peak = math.max(peak, sum)
		end
		local avg = total / (#perTick / Config.Sim.TickRate)
		print(
			string.format(
				"      трафик на клиента (60 держав): средний %.1f КБ/с, пик %.1f КБ/с, снимок при входе %.1f КБ",
				avg / 1000,
				peak / 1000,
				snapshot / 1000
			)
		)
		T.expect(peak <= Config.Net.BudgetBytesPerSec).toBe(true)
	end)
end)

T.describe("ClientState: клиенты видят ту же сетку, что и сервер", function()
	T.it(
		"матч 60 с через сериализацию: копия клиента совпадает с сервером побайтно, опоздавший тоже",
		function()
			local map = Fixtures.pangea
			local m = MatchSim.new(map, 21)
			MatchSim.addPlayer(m, 1, "A")
			MatchSim.addPlayer(m, 2, "B")
			MatchSim.startPick(m)
			local early = ClientState.new(map.width, map.height)
			local late = ClientState.new(map.width, map.height)
			while m.phase ~= "Play" do
				MatchSim.step(m, DT)
			end
			-- Начало игры: снимок всем (изменения расстановки уже в нём).
			Grid.takeChanges(m.grid)
			for _, part in Protocol.encodeSnapshot(m.tick, m.grid.owner, m.grid.size) do
				ClientState.applyBuffer(early, part)
			end
			T.expect(early.hasSnapshot).toBe(true)
			for tick = 1, 60 * Config.Sim.TickRate do
				MatchSim.step(m, DT)
				local delta = deltaOf(m)
				ClientState.applyBuffer(early, delta)
				if tick == 300 then
					-- Опоздавший игрок: снимок в середине игры, дальше дельты.
					for _, part in Protocol.encodeSnapshot(m.tick, m.grid.owner, m.grid.size) do
						ClientState.applyBuffer(late, part)
					end
					T.expect((select(1, ClientState.applyBuffer(late, delta)))).toBe("ignored") -- уже в снимке
				elseif tick > 300 then
					ClientState.applyBuffer(late, delta)
				end
			end
			T.expect(buffer.tostring(early.owners) == buffer.tostring(m.grid.owner)).toBe(true)
			T.expect(buffer.tostring(late.owners) == buffer.tostring(m.grid.owner)).toBe(true)
		end
	)

	T.it("info: державы, фаза, цвета", function()
		local cs = ClientState.new(10, 10)
		local changed = ClientState.applyInfo(cs, {
			kind = "info",
			phase = "Pick",
			phaseLeft = 12,
			time = 0,
			myNation = 2,
			nations = {
				{ id = 1, name = "A", nameEn = "A", colorIndex = 0, capital = nil, isBot = true, alive = true },
				{ id = 2, name = "B", nameEn = "B", colorIndex = 0, capital = 5, isBot = false, alive = true },
			},
		}, 100)
		T.expect(changed).toBe(true)
		T.expect(cs.phaseEndsAt).toBe(112)
		T.expect(cs.myNation).toBe(2)
		T.expect(ClientState.colorIndexOf(cs, 2)).toBe(0)
		T.expect(ClientState.colorIndexOf(cs, 9)).toBe(0)
	end)
end)

T.describe("TerritoryPaint", function()
	local map = Fixtures.pangea
	local terrain = MapPaint.paint(map)
	local w, h = map.width, map.height
	local owners = buffer.create(w * h * 2)
	-- Квадрат 5×5 державы 1 в середине суши.
	local cx, cy = 256, 160
	for y = cy - 2, cy + 2 do
		for x = cx - 2, cx + 2 do
			buffer.writeu16(owners, (y * w + x) * 2, 1)
		end
	end
	local function colorOf(owner: number): number
		return if owner == 1 then 5 else 0
	end
	local function rgbAt(i: number, flash: number): (number, number, number)
		return TerritoryPaint.cellColor(terrain, owners, w, h, i, colorOf, flash)
	end

	T.it("ничья земля — цвет местности", function()
		local i = 10 * w + 10
		local r, g, b = rgbAt(i, 0)
		T.expect(r).toBe(buffer.readu8(terrain, i * 4))
		T.expect(g).toBe(buffer.readu8(terrain, i * 4 + 1))
		T.expect(b).toBe(buffer.readu8(terrain, i * 4 + 2))
	end)

	T.it(
		"край территории — цвет границы, середина — смесь с местностью",
		function()
			local edge = (cy - 2) * w + cx
			local r, g, b = rgbAt(edge, 0)
			local border = NationColors.Borders[5]
			T.expect(r).toBe(border.r)
			T.expect(g).toBe(border.g)
			T.expect(b).toBe(border.b)
			local mid = cy * w + cx
			local mr = rgbAt(mid, 0)
			local t = Config.Render.OwnerTint
			local expected = buffer.readu8(terrain, mid * 4) * (1 - t) + NationColors.Colors[5].r * t
			T.expect(mr).toBeNear(expected, 0.51)
		end
	)

	T.it(
		"вспышка захвата делает клетку светлее, без вспышки — обычный цвет",
		function()
			local mid = cy * w + cx
			local r0, g0, b0 = rgbAt(mid, 0)
			local r1, g1, b1 = rgbAt(mid, 1)
			T.expect(r1 + g1 + b1 > r0 + g0 + b0).toBe(true)
			T.expect(r1 <= 255 and g1 <= 255 and b1 <= 255).toBe(true)
		end
	)

	T.it(
		"держава без цвета (ещё идёт выбор) рисуется местностью",
		function()
			local mid = cy * w + cx
			local r = TerritoryPaint.cellColor(terrain, owners, w, h, mid, function()
				return 0
			end, 0)
			T.expect(r).toBe(buffer.readu8(terrain, mid * 4))
		end
	)
end)
