--!strict
local T = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")
local MapPaint = require("../src/shared/MapPaint")
local MatchSim = require("../src/shared/MatchSim")
local NationColors = require("../src/shared/NationColors")
local Protocol = require("../src/shared/Net/Protocol")
local Rng = require("../src/shared/Rng")
local TerritoryPaint = require("../src/shared/TerritoryPaint")

local DT = 1 / Config.Sim.TickRate

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

	T.it("статистика туда и обратно", function()
		local s: Protocol.Stats = {
			tickMs = 1.5,
			changed = 321,
			nations = { { id = 3, people = 1234.5, maxPeople = 5000, cells = 777, troops = 12.25 } },
			attacks = { { attacker = 3, target = 0, troops = 99.5 } },
		}
		local back = Protocol.decodeStats(Protocol.encodeStats(s))
		T.expect(back.changed).toBe(321)
		T.expect(back.nations[1].cells).toBe(777)
		T.expect(back.nations[1].people).toBeNear(1234.5, 0.01)
		T.expect(back.attacks[1].target).toBe(0)
		T.expect(back.tickMs).toBeNear(1.5, 1e-6)
	end)
end)

T.describe("Protocol: армии", function()
	local function view(id: number, kind: string, state: string, x: number): Protocol.ArmyView
		return {
			id = id,
			owner = 3,
			kind = kind,
			x = x,
			y = 55.5,
			strength = 287.4,
			maxStrength = 300,
			state = state,
			stars = 2,
			progress = 0.63,
			auto = true,
		}
	end

	T.it("армии туда и обратно, позиция с точностью 1/32 клетки", function()
		local tick, back = Protocol.decodeArmies(
			Protocol.encodeArmies(42, { view(7, "Tanks", "capture", 101.37), view(9, "Artillery", "recruit", 2) })
		)
		T.expect(tick).toBe(42)
		T.expect(#back).toBe(2)
		T.expect(back[1].kind).toBe("Tanks")
		T.expect(back[1].state).toBe("capture")
		T.expect(back[1].x).toBeNear(101.37, 1 / 64)
		T.expect(back[1].progress).toBeNear(0.63, 1 / 255)
		T.expect(back[1].auto).toBe(true)
		T.expect(back[1].strength).toBe(287)
		T.expect(back[2].kind).toBe("Artillery")
		T.expect(back[2].state).toBe("recruit")
	end)

	T.it(
		"клиент двигает армию плавно между тиками и забывает исчезнувшие",
		function()
			local cs = ClientState.new(10, 10)
			ClientState.applyBuffer(cs, Protocol.encodeArmies(1, { view(1, "Infantry", "move", 2) }), 10)
			ClientState.applyBuffer(cs, Protocol.encodeArmies(2, { view(1, "Infantry", "move", 3) }), 10.1)
			local a = cs.armies[1]
			T.expect((ClientState.armyPosition(a, 10.1))).toBeNear(2, 1e-6)
			T.expect((ClientState.armyPosition(a, 10.15))).toBeNear(2.5, 1e-6)
			T.expect((ClientState.armyPosition(a, 11))).toBeNear(3, 1e-6)
			ClientState.applyBuffer(cs, Protocol.encodeArmies(3, {}), 10.2)
			T.expect(cs.armies[1]).toBe(nil)
		end
	)
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
