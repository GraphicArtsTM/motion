--!strict
-- Понятность логистики (§15ч Ч5б): «призрак» будущей дороги (Rails.ghost) и сводка режима «Логистика».
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Logistics = require("../src/shared/Logistics")
local Rails = require("../src/shared/Rails")

local W, H = 128, 40
local function at(x: number, y: number): number
	return y * W + x
end
-- Всё своё, кроме стены чужой земли (столбец wallX), если задан.
local function field(wallX: number?): Rails.Context
	return {
		width = W,
		height = H,
		now = 0,
		river = function(_cell: number): boolean
			return false
		end,
		passable = function(cell: number): number?
			return if wallX ~= nil and cell % W == wallX then nil else 1
		end,
	}
end

T.describe("Понятность логистики (§15ч Ч5б)", function()
	T.it(
		"призрак дороги: путь к ближайшей станции в дальности; дальше дальности — «far»; стена — «noPath»",
		function()
			local range = Rails.range(W)
			local near, far = at(10, 10), at(10 + math.floor(range) - 2, 10)
			local spot = at(10, 14)
			local path, why, dist = Rails.ghost(field(nil), spot, { far, near })
			T.expect(why).toBe("ok")
			local p = path :: { number }
			T.expect(p[1]).toBe(spot)
			T.expect(p[#p]).toBe(near) -- ближайшая
			T.expect(dist).toBe(4)
			-- Как на сервере: тот же путь, что Rails.path.
			T.expect(#p).toBe(#(Rails.path(field(nil), spot, near) :: { number }))
			local farSpot = at(10 + math.floor(range * 3), 30)
			local none, why2 = Rails.ghost(field(nil), farSpot, { near })
			T.expect(none).toBe(nil)
			T.expect(why2).toBe("far")
			local blocked, why3 = Rails.ghost(field(12), at(14, 10), { near })
			T.expect(blocked).toBe(nil)
			T.expect(why3).toBe("noPath")
		end
	)

	T.it(
		"сводка: в сети / без дороги (по порядку клеток), счётчики как есть",
		function()
			local s = Logistics.summary({
				stations = {
					{ cell = 50, kind = "City" },
					{ cell = 30, kind = "Factory" },
					{ cell = 10, kind = "Port" },
					{ cell = 40, kind = "OilRig" },
				},
				connected = { [50] = true, [40] = true },
				waterways = 1,
				junctions = 2,
				broken = 3,
				trains = 4,
			})
			T.expect(s.total).toBe(4)
			T.expect(s.connected).toBe(2)
			T.expect(#s.offline).toBe(2)
			T.expect(s.offline[1]).toBe(10)
			T.expect(s.offline[2]).toBe(30)
			T.expect(s.waterways + s.junctions + s.broken + s.trains).toBe(10)
			T.expect(Config.Render.Rail.StationOn ~= Config.Render.Rail.StationOff).toBe(true)
		end
	)
end)
