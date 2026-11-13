--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local StrikeMenu = require("../src/shared/StrikeMenu")
local Strings = require("../src/shared/Strings")

local function facts(over: { [string]: any }): StrikeMenu.Facts
	local f: any = {
		atWar = true,
		armyLevel = 0,
		fleetLevel = 0,
		silo = false,
		missileLeft = 0,
		airfields = 0,
		inRange = true,
		bombers = 0,
		bombersReady = 0,
		ability = nil,
		abilityLeft = 0,
	}
	for k, v in over do
		f[k] = v
	end
	return f
end

T.describe("Удары под рукой (§15х ч.4)", function()
	T.it("ракета: технология → шахта → перезарядка → война", function()
		T.expect(StrikeMenu.missile(facts({}))).toBe("needTech")
		local lvl = Config.Tech.Unlocks.MissileSilo.level
		T.expect(StrikeMenu.missile(facts({ armyLevel = lvl }))).toBe("needSilo")
		T.expect(StrikeMenu.missile(facts({ silo = true, missileLeft = 5 }))).toBe("cooldown")
		T.expect(StrikeMenu.missile(facts({ silo = true, atWar = false }))).toBe("notAtWar")
		T.expect(StrikeMenu.missile(facts({ silo = true }))).toBe("ok")
	end)

	T.it(
		"налёт: технология → аэродром → бомбардировщик → свободный → война → радиус",
		function()
			T.expect(StrikeMenu.raid(facts({}))).toBe("needAirfieldTech")
			T.expect(StrikeMenu.raid(facts({ fleetLevel = Config.Tech.Unlocks.Airfield.level }))).toBe("needAirfield")
			T.expect(StrikeMenu.raid(facts({ airfields = 1 }))).toBe("needBomber")
			T.expect(StrikeMenu.raid(facts({ airfields = 1, bombers = 2 }))).toBe("bombersBusy")
			local ready = { airfields = 1, bombers = 2, bombersReady = 1 }
			T.expect(StrikeMenu.raid(facts(ready))).toBe("ok")
			local far = table.clone(ready) :: { [string]: any }
			far.inRange = false
			T.expect(StrikeMenu.raid(facts(far))).toBe("outOfRange")
			far.atWar = false
			T.expect(StrikeMenu.raid(facts(far))).toBe("notAtWar")
		end
	)

	T.it("удар генерала: есть ли, перезарядка, война", function()
		T.expect(StrikeMenu.ability(facts({}))).toBe("noAbility")
		T.expect(StrikeMenu.ability(facts({ ability = "Airstrike", abilityLeft = 3 }))).toBe("cooldown")
		T.expect(StrikeMenu.ability(facts({ ability = "Airstrike", atWar = false }))).toBe("notAtWar")
		T.expect(StrikeMenu.ability(facts({ ability = "Airstrike" }))).toBe("ok")
		T.expect(StrikeMenu.EnemyAbilities.Airstrike).toBe(true)
		T.expect(StrikeMenu.EnemyAbilities.Surge == nil).toBe(true)
	end)

	T.it(
		"у каждой причины есть подсказка «что сделать» и короткая надпись (RU/EN)",
		function()
			local cases: { [string]: { StrikeMenu.Why } } = {
				missile = { "needTech", "needSilo", "cooldown", "notAtWar" },
				raid = { "needAirfieldTech", "needAirfield", "needBomber", "bombersBusy", "notAtWar", "outOfRange" },
				ability = { "noAbility", "cooldown", "notAtWar" },
			}
			for kind, whys in cases do
				for _, why in whys do
					local key = StrikeMenu.howKey(kind :: any, why :: any)
					T.expect(Strings.Table[key] ~= nil).toBe(true)
					T.expect(Strings.Table["strikeShort." .. why] ~= nil).toBe(true)
				end
			end
		end
	)
end)

-- §15ш Ш2: узкие плитки — только для того, чего не хватает надолго.
T.describe("Узкие плитки «УДАРОВ» (§15ш Ш2)", function()
	T.it(
		"нет технологии, здания или самолёта — узко; перезарядка и «нет войны» — обычная плитка",
		function()
			for _, why in { "needTech", "needSilo", "needAirfieldTech", "needAirfield", "needBomber" } do
				T.expect(StrikeMenu.missing(why)).toBe(true)
			end
			for _, why in { "ok", "cooldown", "notAtWar", "bombersBusy", "outOfRange" } do
				T.expect(StrikeMenu.missing(why)).toBe(false)
			end
		end
	)
end)
