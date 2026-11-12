--!strict
local T = require("./lib/TestKit")
local Air = require("../src/shared/Air")
local Config = require("../src/shared/Config")
local StrikeForecast = require("../src/shared/StrikeForecast")
local ThreatMap = require("../src/shared/ThreatMap")

local W = 768
local function at(x: number, y: number): number
	return y * W + x
end

local function count(zones: { ThreatMap.Zone }, kind: string): number
	local n = 0
	for _, z in zones do
		if z.kind == kind then
			n += 1
		end
	end
	return n
end

T.describe("Карта угроз (§15х ч.4б)", function()
	T.it(
		"зоны: своя и чужая ПВО (ближняя и дальняя), аэродромы и шахты врага; нейтралов не показывать",
		function()
			local r = ThreatMap.compute({
				width = W,
				me = 1,
				friends = { [3] = true },
				enemies = { [2] = true },
				buildings = {
					{ cell = at(100, 100), kind = "AirDefense", level = 3, owner = 1 },
					{ cell = at(200, 100), kind = "AirDefense", level = 1, owner = 3 }, -- друг по доверию — как своя
					{ cell = at(400, 100), kind = "AirDefense", level = 2, owner = 2 },
					{ cell = at(420, 100), kind = "Airfield", level = 1, owner = 2 },
					{ cell = at(440, 100), kind = "MissileSilo", level = 1, owner = 2 },
					{ cell = at(460, 100), kind = "Airfield", level = 1, owner = 2, off = true }, -- выведен из строя
					{ cell = at(600, 100), kind = "AirDefense", level = 3, owner = 4 }, -- не враг и не друг
				},
				cities = {},
			})
			T.expect(count(r.zones, "myAA")).toBe(2)
			T.expect(count(r.zones, "myAALong")).toBe(1)
			T.expect(count(r.zones, "enemyAA")).toBe(1)
			T.expect(count(r.zones, "enemyAALong")).toBe(0)
			T.expect(count(r.zones, "enemyAir")).toBe(1)
			T.expect(count(r.zones, "enemySilo")).toBe(1)
			T.expect(r.enemySilos).toBe(1)
			T.expect(r.enemyAirfields).toBe(1)
			for _, z in r.zones do
				if z.kind == "myAALong" then
					T.expect(z.radius).toBe(StrikeForecast.radius(3, W, true))
				elseif z.kind == "enemyAir" then
					T.expect(z.radius).toBe(Config.Air.Range * Air.scale(W))
				end
			end
		end
	)

	T.it(
		"дыры: свои города и здания вне кругов своей ПВО против ракет (дальний круг ур. 3 — тоже защита)",
		function()
			local near = Config.Buildings.AirDefense.radius
			local far = StrikeForecast.radius(3, W, true)
			T.expect(far > near + 10).toBe(true)
			local aa = at(100, 100)
			local inNear = at(100 + near - 2, 100)
			local inFar = at(100 + math.floor(far) - 2, 100)
			local outside = at(100 + math.floor(far) + 5, 100)
			local function holes(level: number): { number }
				return ThreatMap.compute({
					width = W,
					me = 1,
					friends = {},
					enemies = {},
					buildings = {
						{ cell = aa, kind = "AirDefense", level = level, owner = 1 },
						{ cell = inFar, kind = "Factory", level = 1, owner = 1 },
					},
					cities = {
						{ cell = inNear, owner = 1 },
						{ cell = outside, owner = 1 },
						{ cell = at(5, 5), owner = 2 },
					},
				}).holes
			end
			-- ПВО ур. 1: накрыты только сама ПВО и город рядом.
			local h1 = holes(1)
			T.expect(#h1).toBe(2)
			T.expect(table.find(h1, inFar) ~= nil and table.find(h1, outside) ~= nil).toBe(true)
			-- ПВО ур. 3: завод в дальнем круге уже не дыра; город за кругом — дыра; чужой город не считается.
			local h3 = holes(3)
			T.expect(#h3).toBe(1)
			T.expect(h3[1]).toBe(outside)
		end
	)
end)
