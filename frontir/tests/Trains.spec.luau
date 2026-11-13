--!strict
-- Поезда (§15ч Ч2): маршрут через станции, остановки с платой, движение.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Rails = require("../src/shared/Rails")
local Trains = require("../src/shared/Trains")

local W, H = 128, 40
local function at(x: number, y: number): number
	return y * W + x
end
local ctx: Rails.Context = {
	width = W,
	height = H,
	now = 0,
	river = function(_cell: number): boolean
		return false
	end,
	passable = function(_cell: number): number?
		return 1
	end,
}

-- Завод — город — порт в ряд: дороги завод–город и город–порт.
local function line(): Rails.Net
	return Rails.build({
		{ cell = at(10, 10), kind = "Factory" },
		{ cell = at(17, 10), kind = "City" },
		{ cell = at(24, 10), kind = "Port" },
	}, at(17, 10), ctx, nil)
end

T.describe("Поезда (§15ч Ч2)", function()
	T.it(
		"цели — города и порты своей сети; маршрут через город к порту — две остановки с платой",
		function()
			local net = line()
			local dests = Trains.destinations(net, at(10, 10))
			T.expect(#dests).toBe(2)
			local cells, stops = Trains.plan(net, at(10, 10), at(24, 10), function(): number
				return 2
			end)
			T.expect(cells ~= nil).toBe(true)
			local c = cells :: { number }
			T.expect(c[1]).toBe(at(10, 10))
			T.expect(c[#c]).toBe(at(24, 10))
			-- Клетки идут без разрывов (соседи по 8 направлениям) и без повтора стыка.
			for k = 2, #c do
				local dx, dy = math.abs(c[k] % W - c[k - 1] % W), math.abs(c[k] // W - c[k - 1] // W)
				T.expect(dx <= 1 and dy <= 1 and dx + dy > 0).toBe(true)
			end
			local s = stops :: { Trains.Stop }
			T.expect(#s).toBe(2)
			T.expect(s[1].cell).toBe(at(17, 10))
			T.expect(s[1].money).toBe(Config.Rail.StopMoney + 2 * Config.Rail.StopCityLevelMoney)
			T.expect(s[2].money).toBe(Config.Rail.PortStopMoney)
			T.expect(s[1].index < s[2].index).toBe(true)
		end
	)

	T.it(
		"движение: остановки оплачиваются по одной по пути, в конце — прибыл; точка на маршруте — между клетками",
		function()
			local net = line()
			local cells, stops = Trains.plan(net, at(10, 10), at(24, 10), function(): number
				return 1
			end)
			local train: Trains.Train = {
				id = 1,
				owner = 1,
				cells = cells :: { number },
				stops = stops :: { Trains.Stop },
				nextStop = 1,
				pos = 1,
				speed = 4,
				start = 0,
				checkAt = 0,
			}
			local reached, done = Trains.advance(train, 1) -- 5-я клетка: до города ещё не доехал
			T.expect(#reached).toBe(0)
			T.expect(done).toBe(false)
			reached, done = Trains.advance(train, 1) -- 9-я клетка: город позади
			T.expect(#reached).toBe(1)
			reached, done = Trains.advance(train, 10)
			T.expect(#reached).toBe(1)
			T.expect(done).toBe(true)
			local x, y = Trains.at(cells :: { number }, W, 4, 0.125, 0)
			T.expect(x > 10.5 and x < 11.5).toBe(true)
			T.expect(math.abs(y - 10.5) < 1e-9).toBe(true)
		end
	)

	T.it(
		"нет пути (станции в разных сетях) — маршрута нет; станция без сети — целей нет",
		function()
			local net = Rails.build({
				{ cell = at(10, 10), kind = "Factory" },
				{ cell = at(100, 10), kind = "City" },
			}, at(100, 10), ctx, nil)
			T.expect((Trains.route(net, at(10, 10), at(100, 10)))).toBe(nil)
			T.expect(#Trains.destinations(net, at(10, 10))).toBe(0)
		end
	)

	T.it("оплачиваемых остановок не больше MaxPaidStops", function()
		local stations: { Rails.Station } = { { cell = at(4, 10), kind = "Factory" } }
		for k = 1, Config.Rail.MaxPaidStops + 3 do
			table.insert(stations, { cell = at(4 + 6 * k, 10), kind = "City" })
		end
		local net = Rails.build(stations, at(10, 10), ctx, nil)
		local last = stations[#stations].cell
		local _, stops = Trains.plan(net, at(4, 10), last, function(): number
			return 1
		end)
		T.expect(#(stops :: { Trains.Stop })).toBe(Config.Rail.MaxPaidStops)
	end)
end)
