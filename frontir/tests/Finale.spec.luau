--!strict
-- Кульминация (§15й Й3): финал «лидер близко» и «время», запас против мигания, обратный отсчёт, «Все против лидера».
local T = require("./lib/TestKit")
local TinyMap = require("./lib/TinyMap")
local AudioCues = require("../src/shared/AudioCues")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local Diplomacy = require("../src/shared/Diplomacy")
local Finale = require("../src/shared/Finale")
local Grid = require("../src/shared/Grid")
local MapData = require("../src/shared/MapData")
local MatchSim = require("../src/shared/MatchSim")
local Modes = require("../src/shared/Modes")

local cfg = Config.Finale
local W, H = 64, 24

local function facts(leader: number, left: number?, allowed: boolean?): Finale.Facts
	return { victoryShare = 0.6, leaderShare = leader, timeLeft = left, nearAllowed = allowed ~= false }
end

-- Три державы: 1 владеет x ≤ split, 2 и 3 — остальным пополам.
local function trio(split: number): MatchSim.Match
	local map = TinyMap.plains(W, H)
	for i = 0, W * H - 1 do
		if MapData.getTerrain(map, i) ~= 0 then
			MapData.setProvince(map, i, (i % W) // 10 + 1)
		end
	end
	local m = MatchSim.new(map, 5)
	m.victory = false
	for k = 1, 3 do
		MatchSim.addPlayer(m, k, "N" .. k)
	end
	m.phase = "Play"
	local rest = (62 - split) // 2
	for y = 1, H - 2 do
		for x = 1, 62 do
			Grid.setOwner(m.grid, y * W + x, if x <= split then 1 elseif x <= split + rest then 2 else 3)
		end
	end
	return m
end

T.describe("Финал: правило (§15й Й3)", function()
	T.it(
		"«лидер близко» — с доли победы минус Margin; ниже — нет; запас Hysteresis не даёт мигать",
		function()
			T.expect(Finale.state(facts(0.6 - cfg.Margin, 900), false).reason).toBe("near")
			T.expect(Finale.state(facts(0.6 - cfg.Margin - 0.01, 900), false).on).toBe(false)
			T.expect(Finale.state(facts(0.6 - cfg.Margin - 0.01, 900), true).reason).toBe("near")
			T.expect(Finale.state(facts(0.6 - cfg.Margin - cfg.Hysteresis - 0.01, 900), true).on).toBe(false)
		end
	)

	T.it(
		"«время» — последние Sec; отсчёт — CountdownSec, красный — UrgentSec; «лидер близко» главнее",
		function()
			local t = Finale.state(facts(0.2, cfg.Sec - 1), false)
			T.expect(t.reason).toBe("time")
			T.expect(t.countdown).toBe(false)
			T.expect(Finale.state(facts(0.2, cfg.CountdownSec), false).countdown).toBe(true)
			T.expect(Finale.state(facts(0.2, cfg.UrgentSec), false).urgent).toBe(true)
			T.expect(Finale.state(facts(0.55, 30), false).reason).toBe("near")
			T.expect(Finale.state(facts(0.2, nil), false).on).toBe(false)
		end
	)

	T.it(
		"«Команды», «Охота», «Обучение» — только «время»; музыка — то же правило",
		function()
			T.expect(Finale.nearAllowed(Modes.rules("Ffa"))).toBe(true)
			T.expect(Finale.nearAllowed(Modes.rules("Teams"))).toBe(false)
			T.expect(Finale.nearAllowed(Modes.rules("CapitalHunt"))).toBe(false)
			T.expect(Finale.state(facts(0.58, 900, false), false).on).toBe(false)
			T.expect(AudioCues.music({ phase = "Play", leaderShare = 0.58, victoryShare = 0.6, nearAllowed = false }))
				.toBe("Match")
			T.expect(AudioCues.music({ phase = "Play", leaderShare = 0.58, victoryShare = 0.6 })).toBe("War")
		end
	)

	T.it(
		"«Все против лидера»: фронт против блока лидера быстрее, внутри блока и против остальных — нет",
		function()
			local bloc = { [1] = true, [4] = true }
			T.expect(Finale.coalitionMul(bloc, 2, 1)).toBe(cfg.CoalitionSpeed)
			T.expect(Finale.coalitionMul(bloc, 2, 4)).toBe(cfg.CoalitionSpeed)
			T.expect(Finale.coalitionMul(bloc, 1, 2)).toBe(1)
			T.expect(Finale.coalitionMul(bloc, 4, 1)).toBe(1)
			T.expect(Finale.coalitionMul(nil, 2, 1)).toBe(1)
		end
	)
end)

T.describe("Финал в симуляции (§15й Й3)", function()
	T.it(
		"лидер близко к победе — блок лидера с союзником; откатился — блока нет",
		function()
			local m = trio(36) -- 1 — ~57% суши
			Diplomacy.sign(m.diplo, "alliance", 1, 3, 0)
			MatchSim.step(m, 1 / Config.Sim.TickRate)
			local leader = MatchSim.leaderBloc(m)
			T.expect(leader).toBe(1)
			T.expect(m.finaleNear).toBe(true)
			local bloc = m.finaleBloc :: { [number]: boolean }
			T.expect(bloc[1] and bloc[3] and not bloc[2]).toBe(true)
			local small = trio(12)
			MatchSim.step(small, 1 / Config.Sim.TickRate)
			T.expect(small.finaleNear).toBe(false)
			T.expect(small.finaleBloc).toBe(nil)
		end
	)

	T.it(
		"F4 «бот почти победил»: ничьей земли нет — берёт чужую, кроме игрока и городов",
		function()
			local m = trio(20)
			local mine = Grid.cellsOf(m.grid, 1)
			T.expect((DevTools.finaleNear(m, 2, 1))).toBe(true)
			local share = Grid.cellsOf(m.grid, 2) / m.grid.capturableCount
			T.expect(share >= 0.6 - cfg.Margin / 2 - 0.01).toBe(true)
			T.expect(Grid.cellsOf(m.grid, 1)).toBe(mine)
		end
	)

	T.it(
		"в «Командах» и с выключателем замеров — без «Все против лидера»",
		function()
			local m = trio(40)
			m.rules = Modes.rules("Teams")
			MatchSim.step(m, 1 / Config.Sim.TickRate)
			T.expect(m.finaleBloc).toBe(nil)
			local off = trio(40)
			off.finaleOff = true
			MatchSim.step(off, 1 / Config.Sim.TickRate)
			T.expect(off.finaleNear).toBe(true)
			T.expect(off.finaleBloc).toBe(nil)
		end
	)
end)
