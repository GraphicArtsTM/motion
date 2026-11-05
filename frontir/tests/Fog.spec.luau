--!strict
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local ClientState = require("../src/shared/ClientState")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Diplomacy = require("../src/shared/Diplomacy")
local Fog = require("../src/shared/Fog")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")
local MatchStats = require("../src/shared/Net/MatchStats")
local Protocol = require("../src/shared/Net/Protocol")

local cfg = Config.Fog
local W, H = 80, 40

-- Буфер владельцев W×H: держава id владеет прямоугольником [x0..x1]×[y0..y1].
local function owners(rects: { { id: number, x0: number, y0: number, x1: number, y1: number } }): buffer
	local b = buffer.create(W * H * 2)
	for _, r in rects do
		for y = r.y0, r.y1 do
			for x = r.x0, r.x1 do
				buffer.writeu16(b, (y * W + x) * 2, r.id)
			end
		end
	end
	return b
end

local function at(x: number, y: number): number
	return y * W + x
end

T.describe("Туман войны", function()
	T.it(
		"своя земля + 6 клеток; дальше — не видно, но известен последний увиденный владелец",
		function()
			local o =
				owners({ { id = 1, x0 = 0, y0 = 0, x1 = 19, y1 = 39 }, { id = 2, x0 = 40, y0 = 0, x1 = 79, y1 = 39 } })
			local fs = Fog.new(W, H)
			fs.hideTerritory = true -- правило 7а («Мгла»): чужие границы вне обзора не видны
			-- Матч начинается с «видно всё»: первый пересчёт — перерисовать всю карту.
			T.expect(fs.all).toBe(true)
			local full = Fog.compute(fs, o, { friends = { [1] = true }, fronts = {}, radars = {} })
			T.expect(full).toBe(true)
			T.expect(fs.all).toBe(false)
			T.expect(Fog.isVisible(fs, at(5, 20))).toBe(true)
			T.expect(Fog.isVisible(fs, at(19 + cfg.TerritoryVision, 20))).toBe(true)
			T.expect(Fog.isVisible(fs, at(19 + cfg.TerritoryVision + 1, 20))).toBe(false)
			-- По диагонали — «почти круг»: 6 по стороне видно, (5, 5) по диагонали (≈7.1) — нет.
			T.expect(Fog.isVisible(fs, at(19 + 5, 39))).toBe(true)
			-- Держава 2 вдали: её земли не видели — владелец неизвестен.
			T.expect(Fog.knownOwner(fs, at(50, 20))).toBe(0)
			T.expect(Fog.wasSeen(fs, at(50, 20))).toBe(false)
			T.expect(Fog.knownOwner(fs, at(5, 20))).toBe(1)
		end
	)

	T.it(
		"по умолчанию границы видны везде: чужой рост вдали виден, обзор прячет только войска и здания",
		function()
			T.expect(cfg.HideTerritory).toBe(false)
			local o =
				owners({ { id = 1, x0 = 0, y0 = 0, x1 = 19, y1 = 39 }, { id = 2, x0 = 40, y0 = 0, x1 = 79, y1 = 39 } })
			local fs = Fog.new(W, H)
			local sources = { friends = { [1] = true }, fronts = {}, radars = {} }
			Fog.compute(fs, o, sources)
			T.expect(Fog.isVisible(fs, at(50, 20))).toBe(false)
			T.expect(Fog.wasSeen(fs, at(50, 20))).toBe(false) -- здания там не показываются
			T.expect(Fog.knownOwner(fs, at(50, 20))).toBe(2)
			-- Держава 2 растёт вдали: дельта сразу видна и просит перерисовку.
			buffer.writeu16(o, at(39, 30) * 2, 2)
			T.expect(Fog.applyDelta(fs, o, { at(39, 30) })).toEqual({ at(39, 30) })
			T.expect(Fog.knownOwner(fs, at(39, 30))).toBe(2)
			-- И после пересчёта обзора владельцы настоящие.
			buffer.writeu16(o, at(70, 5) * 2, 0)
			Fog.compute(fs, o, sources)
			T.expect(Fog.knownOwner(fs, at(70, 5))).toBe(0)
			T.expect(Fog.isVisible(fs, at(70, 5))).toBe(false)
		end
	)

	T.it(
		"линия фронта видит на 8, радар — на 25, союзник делится обзором",
		function()
			-- 1 и 2 граничат по x = 19/20; 3 — далеко справа.
			local o = owners({
				{ id = 1, x0 = 0, y0 = 0, x1 = 19, y1 = 39 },
				{ id = 2, x0 = 20, y0 = 0, x1 = 49, y1 = 39 },
				{ id = 3, x0 = 60, y0 = 0, x1 = 79, y1 = 39 },
			})
			local fs = Fog.new(W, H)
			Fog.compute(fs, o, { friends = { [1] = true }, fronts = {}, radars = {} })
			T.expect(Fog.isVisible(fs, at(19 + cfg.ArmyVision, 20))).toBe(false)
			Fog.compute(fs, o, { friends = { [1] = true }, fronts = { { mine = 1, other = 2 } }, radars = {} })
			T.expect(Fog.isVisible(fs, at(19 + cfg.ArmyVision, 20))).toBe(true)
			T.expect(Fog.isVisible(fs, at(19 + cfg.ArmyVision + 1, 20))).toBe(false)
			-- Радар у границы.
			Fog.compute(fs, o, { friends = { [1] = true }, fronts = {}, radars = { at(19, 20) } })
			T.expect(Fog.isVisible(fs, at(19 + cfg.RadarVision, 20))).toBe(true)
			T.expect(Fog.isVisible(fs, at(19 + cfg.RadarVision + 1, 20))).toBe(false)
			-- Союзник 3: его земля и 6 клеток вокруг.
			Fog.compute(fs, o, { friends = { [1] = true, [3] = true }, fronts = {}, radars = {} })
			T.expect(Fog.isVisible(fs, at(70, 5))).toBe(true)
			T.expect(Fog.isVisible(fs, at(60 - cfg.TerritoryVision, 5))).toBe(true)
			T.expect(Fog.isVisible(fs, at(40, 5))).toBe(false)
		end
	)

	T.it(
		"вне обзора захват не виден; обзор вернулся — known обновился; «видно всё» и обратно",
		function()
			local o =
				owners({ { id = 1, x0 = 0, y0 = 0, x1 = 19, y1 = 39 }, { id = 2, x0 = 20, y0 = 0, x1 = 79, y1 = 39 } })
			local fs = Fog.new(W, H)
			fs.hideTerritory = true
			local sources = { friends = { [1] = true }, fronts = {}, radars = {} }
			Fog.compute(fs, o, sources)
			T.expect(Fog.knownOwner(fs, at(22, 20))).toBe(2) -- рядом — видно
			T.expect(Fog.knownOwner(fs, at(60, 20))).toBe(0)
			-- Вдали клетка сменила владельца — known прежний; рядом — сразу.
			buffer.writeu16(o, at(60, 20) * 2, 3)
			buffer.writeu16(o, at(22, 20) * 2, 3)
			local repaint = Fog.applyDelta(fs, o, { at(60, 20), at(22, 20) })
			T.expect(#repaint).toBe(1)
			T.expect(Fog.knownOwner(fs, at(60, 20))).toBe(0)
			T.expect(Fog.knownOwner(fs, at(22, 20))).toBe(3)
			-- Наша земля дошла туда — увидели.
			for x = 20, 60 do
				buffer.writeu16(o, at(x, 20) * 2, 1)
			end
			local full, changed = Fog.compute(fs, o, sources)
			T.expect(full).toBe(false)
			T.expect(Fog.knownOwner(fs, at(60, 20))).toBe(1)
			T.expect(table.find(changed, at(60, 20)) ~= nil).toBeTruthy()
			-- Земля ушла — клетка снова в тумане, но остаётся последний увиденный владелец.
			for x = 20, 60 do
				buffer.writeu16(o, at(x, 20) * 2, 2)
			end
			Fog.compute(fs, o, sources)
			T.expect(Fog.isVisible(fs, at(60, 20))).toBe(false)
			T.expect(Fog.knownOwner(fs, at(60, 20))).toBe(1)
			T.expect(Fog.wasSeen(fs, at(60, 20))).toBe(true)
			-- «Видно всё» (зритель, панель): known = настоящие владельцы; потом туман снова.
			T.expect(Fog.revealAll(fs, o)).toBe(true)
			T.expect(Fog.revealAll(fs, o)).toBe(false) -- уже «видно всё»
			T.expect(Fog.isVisible(fs, at(70, 30))).toBe(true)
			T.expect(Fog.knownOwner(fs, at(60, 20))).toBe(2)
			-- В режиме «видно всё» дельты обновляют known везде.
			buffer.writeu16(o, at(70, 30) * 2, 3)
			T.expect(#Fog.applyDelta(fs, o, { at(70, 30) })).toBe(1)
			local back = Fog.compute(fs, o, sources)
			T.expect(back).toBe(true)
			T.expect(Fog.isVisible(fs, at(70, 30))).toBe(false)
			T.expect(Fog.knownOwner(fs, at(70, 30))).toBe(3) -- последнее увиденное
		end
	)

	T.it(
		"сервер: чужие фронты вне обзора не уходят, свои и союзника — уходят; STATS из общего начала",
		function()
			-- Три державы полосами: 1 — x 1..14, 2 — 15..29, 3 — 30..43 (карта 45×12).
			local w, h = 45, 12
			local map = TinyMap.plains(w, h)
			for y = 1, h - 2 do
				for x = 1, w - 2 do
					MapData.setProvince(map, y * w + x, x // 5 + 1)
				end
			end
			local m = MatchSim.new(map, 3)
			m.victory = false
			m.rules = Modes.withFog("Ffa") -- туман на карте — только в «Мгле» (§6.11а)
			for k = 1, 3 do
				MatchSim.addPlayer(m, k, "N" .. k)
			end
			m.phase = "Play"
			for y = 1, h - 2 do
				for x = 1, w - 2 do
					Grid.setOwner(m.grid, y * w + x, math.min(3, x // 15 + 1))
				end
			end
			for _, n in m.nations do
				n.colorIndex = n.id
				n.people = 5000
				n.capital = 6 * w + (n.id - 1) * 15 + 2
				Grid.setCity(m.grid, n.capital :: number, true)
				m.cityOf[-n.id] = n.capital :: number
			end
			DevTools.grant(m, 2, "forces")
			DevTools.warNow(m, 2, 3)
			T.expect((MatchSim.applyIntent(m, 2, { kind = "attack", target = 3, percent = 50 }))).toBe(true)
			MatchSim.step(m, 1 / Config.Sim.TickRate)
			T.expect(m.attacks[1].line ~= nil and #(m.attacks[1].line :: { number }) > 0).toBeTruthy()
			local full = MatchStats.build(m, 0, 0)
			T.expect(#full.attacks).toBe(1)
			T.expect(#MatchStats.forViewer(m, full, 1).attacks).toBe(0) -- фронт 2–3 далеко от 1
			T.expect(#MatchStats.forViewer(m, full, 2).attacks).toBe(1)
			T.expect(#MatchStats.forViewer(m, full, 3).attacks).toBe(1)
			T.expect(#MatchStats.forViewer(m, full, nil).attacks).toBe(1) -- зритель
			-- Союз с 3 — фронт 2–3 виден и державе 1.
			Diplomacy.sign(m.diplo, "alliance", 1, 3, m.simTime)
			T.expect(#MatchStats.forViewer(m, full, 1).attacks).toBe(1)
			-- Общее начало STATS + свои фронты — то же, что закодировать целиком.
			local head = Protocol.encodeStatsHead(full)
			local one = Protocol.decodeStats(Protocol.encodeStats(full, head))
			local two = Protocol.decodeStats(Protocol.encodeStats(full))
			T.expect(one).toEqual(two)
			T.expect(#one.attacks).toBe(1)
		end
	)

	T.it(
		"клиент: дельта вне обзора не перерисовывается; выбывший и зритель видят всё",
		function()
			local w, h = 45, 12
			local map = TinyMap.plains(w, h)
			local m = MatchSim.new(map, 3)
			m.victory = false
			m.rules = Modes.withFog("Ffa") -- туман на карте — только в «Мгле» (§6.11а)
			for k = 1, 3 do
				MatchSim.addPlayer(m, k, "N" .. k)
			end
			m.phase = "Play"
			for y = 1, h - 2 do
				for x = 1, w - 2 do
					Grid.setOwner(m.grid, y * w + x, math.min(3, x // 15 + 1))
				end
			end
			Grid.takeChanges(m.grid)
			local cs = ClientState.new(w, h)
			local nations: { ClientState.NationInfo } = {}
			for id = 1, 3 do
				nations[id] = {
					id = id,
					name = "N" .. id,
					nameEn = "N" .. id,
					colorIndex = id,
					capital = nil,
					isBot = false,
					alive = true,
				}
			end
			local info: ClientState.Info =
				{ kind = "info", phase = "Play", phaseLeft = 0, time = 0, myNation = 1, nations = nations }
			ClientState.applyInfo(cs, info, 0)
			cs.fog.hideTerritory = true -- правило 7а («Мгла»)
			cs.rules = Modes.withFog("Ffa")
			for _, part in Protocol.encodeSnapshot(m.tick, m.grid.owner, m.grid.size) do
				ClientState.applyBuffer(cs, part)
			end
			T.expect(cs.fog.all).toBe(true) -- до первого пересчёта видно всё
			local full = ClientState.refreshFog(cs)
			T.expect(full).toBe(true)
			local near, far = 6 * w + 16, 6 * w + 40
			T.expect(ClientState.knownOwnerAt(cs, far)).toBe(3) -- старт виден всем: последнее увиденное
			-- Сервер: 3 взяла клетку рядом с нами, 2 — далеко.
			Grid.setOwner(m.grid, near, 3)
			Grid.setOwner(m.grid, far, 2)
			m.tick += 1
			local delta = Protocol.encodeDelta(m.tick, Grid.takeChanges(m.grid), m.grid.owner)
			local kind, cells = ClientState.applyBuffer(cs, delta)
			T.expect(kind).toBe("delta")
			T.expect(cells).toEqual({ near })
			T.expect(ClientState.ownerAt(cs, far)).toBe(2) -- настоящая сетка у клиента полная (§12)
			T.expect(ClientState.knownOwnerAt(cs, far)).toBe(3)
			-- Держава выбыла — зритель: видно всё, перерисовать всю карту.
			nations[1].alive = false
			ClientState.applyInfo(cs, info, 1)
			T.expect((ClientState.refreshFog(cs))).toBe(true)
			T.expect(ClientState.knownOwnerAt(cs, far)).toBe(2)
			-- Стабильность: свои провинции и повстанцы; изменения повстанцев — провинции для перерисовки.
			local changed = ClientState.applyStability(cs, {
				kind = "stability",
				average = 42,
				lowCells = 0,
				ids = { 1, 2 },
				values = { 80, 20 },
				rebels = { 5 },
				rebelLeft = { 100 },
			})
			T.expect(changed).toEqual({ 5 })
			T.expect(ClientState.stabilityOf(cs, 2)).toBe(20)
			T.expect(ClientState.stabilityOf(cs, 7)).toBe(nil)
			changed = ClientState.applyStability(cs, MatchStats.stability(m, 1))
			T.expect(changed).toEqual({ 5 }) -- повстанцев больше нет
		end
	)

	T.it(
		"сервер: грубый обзор блоками покрывает точный (+6 от границы, радар +25)",
		function()
			local width, height = 200, 100
			local border: { [number]: boolean } = { [50 * width + 100] = true }
			local blocks = Fog.visionBlocks(width, height, { border }, { 10 * width + 10 })
			T.expect(blocks[Fog.blockOf(width, 50 * width + 100 + cfg.TerritoryVision)]).toBe(true)
			T.expect(blocks[Fog.blockOf(width, 50 * width + 100 - cfg.ArmyVision)]).toBe(true)
			T.expect(blocks[Fog.blockOf(width, 10 * width + 10 + cfg.RadarVision)]).toBe(true)
			T.expect(blocks[Fog.blockOf(width, 90 * width + 190)]).toBe(nil)
			T.expect(Fog.lineVisible(width, blocks, { 90 * width + 190, 50 * width + 104 })).toBe(true)
			T.expect(Fog.lineVisible(width, blocks, { 90 * width + 190 })).toBe(false)
		end
	)
end)
