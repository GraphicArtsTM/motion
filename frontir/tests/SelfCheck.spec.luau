--!strict
local T = require("./lib/TestKit")
local Commanders = require("../src/shared/Commanders")
local Config = require("../src/shared/Config")
local DevTools = require("../src/shared/DevTools")
local MapFormat = require("../src/shared/MapFormat")
local MatchSim = require("../src/shared/MatchSim")
local Types = require("../src/shared/Types")
local WorldEvents = require("../src/shared/WorldEvents")

local DT = 1 / Config.Sim.TickRate

-- Партия на «Европе»: игрок 1 и боты, 30 с игры (стабильность провинций уже посчитана).
local function europe(): MatchSim.Match
	local map = MapFormat.fromModule((require :: any)("../maps/Europe") :: MapFormat.MapModule)
	local m = MatchSim.new(map, 777)
	MatchSim.addPlayer(m, 1, "Игрок")
	m.targetNations = 8
	MatchSim.startPick(m)
	while m.phase ~= "Play" do
		MatchSim.step(m, DT)
	end
	m.victory = false
	for _ = 1, 30 * Config.Sim.TickRate do
		MatchSim.step(m, DT)
	end
	return m
end

T.describe("Самопроверка (сводная правка, часть 1)", function()
	T.it(
		"каждая способность каждого генерала срабатывает с подобранной целью",
		function()
			local m = europe()
			for _, c in Types.CommanderIds do
				for slot = 1, 2 do
					local ok, reason = DevTools.selfAbility(m, 1, c, slot)
					if not ok then
						print("FAIL", c, slot, Commanders.ability(c :: any, slot), reason)
					end
					T.expect(ok).toBe(true)
					MatchSim.step(m, DT)
				end
			end
			T.expect((DevTools.selfAbility(m, 1, "Pirate", 1))).toBe(false)
		end
	)

	T.it("каждое случайное событие запускается по имени", function()
		local m = europe()
		for _, kind in WorldEvents.Kinds do
			local ok, reason = DevTools.worldEventKind(m, kind)
			if not ok then
				print("FAIL", kind, reason)
			end
			T.expect(ok).toBe(true)
		end
		T.expect((DevTools.worldEventKind(m, "Meteor"))).toBe(false)
	end)
end)
