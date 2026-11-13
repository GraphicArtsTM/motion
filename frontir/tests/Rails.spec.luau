--!strict
-- Железные дороги (§15ч Ч1): путь, мост, сеть и главная сеть со столицей.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Rails = require("../src/shared/Rails")

-- Поле W×H: всё «своё», кроме реки (столбец riverX), воды (blocked) и чужой земли (foreign).
local W, H = 128, 40
local function field(riverX: number?, blocked: { [number]: boolean }?, foreign: { [number]: boolean }?): Rails.Context
	local function river(cell: number): boolean
		return riverX ~= nil and cell % W == riverX
	end
	return {
		width = W,
		height = H,
		now = 0,
		river = river,
		passable = function(cell: number): number?
			if blocked ~= nil and blocked[cell] then
				return nil
			end
			if foreign ~= nil and foreign[cell] then
				return nil
			end
			if river(cell) then
				return Config.Rail.BridgeCost
			end
			return 1
		end,
	}
end
local function at(x: number, y: number): number
	return y * W + x
end

T.describe("Железные дороги (§15ч Ч1)", function()
	T.it(
		"путь по своей земле; река — мост; чужая земля и вода — нельзя",
		function()
			local ctx = field(nil)
			local path = Rails.path(ctx, at(10, 10), at(18, 10))
			T.expect(path ~= nil).toBe(true)
			T.expect((path :: { number })[1]).toBe(at(10, 10))
			T.expect((path :: { number })[#(path :: { number })]).toBe(at(18, 10))
			-- Мост через реку шириной 1.
			local _, bridges = Rails.path(field(14), at(10, 10), at(18, 10))
			T.expect(bridges).toBe(1)
			-- Стена чужой земли поперёк поля — пути нет.
			local wall: { [number]: boolean } = {}
			for y = 0, H - 1 do
				wall[at(14, y)] = true
			end
			T.expect((Rails.path(field(nil, nil, wall), at(10, 10), at(18, 10)))).toBe(nil)
		end
	)

	T.it("широкая река (больше BridgeMaxCells) — без моста", function()
		local ctx = field(nil)
		local function river(cell: number): boolean
			local x = cell % W
			return x >= 12 and x < 12 + Config.Rail.BridgeMaxCells + 1
		end
		ctx.river = river
		ctx.passable = function(cell: number): number?
			return if river(cell) then Config.Rail.BridgeCost else 1
		end
		T.expect((Rails.path(ctx, at(8, 10), at(20, 10)))).toBe(nil)
	end)

	T.it(
		"сеть: три станции в ряд — две дороги, все в главной сети со столицей; путь сжимается и разжимается",
		function()
			local ctx = field(nil)
			local stations: { Rails.Station } = {
				{ cell = at(10, 10), kind = "City" },
				{ cell = at(17, 10), kind = "Factory" },
				{ cell = at(24, 10), kind = "Port" },
			}
			local net = Rails.build(stations, at(10, 10), ctx, nil)
			T.expect(#net.links).toBe(2)
			T.expect(net.connected[at(24, 10)]).toBe(true)
			T.expect(net.cells[at(10, 10)]).toBe(nil) -- станция — не рельсы
			T.expect(net.cells[at(13, 10)] ~= nil).toBe(true)
			local link = net.links[1]
			local start, dirs = Rails.encode(link.path, W)
			local back = Rails.decode(start, dirs, W)
			T.expect(#back).toBe(#link.path)
			for k, cell in link.path do
				T.expect(back[k]).toBe(cell)
			end
		end
	)

	T.it(
		"станция без дороги к столице — не в главной сети; перерезанная дорога — сеть перестраивается",
		function()
			local wall: { [number]: boolean } = {}
			for y = 0, H - 1 do
				wall[at(20, y)] = true
			end
			local stations: { Rails.Station } = {
				{ cell = at(10, 10), kind = "City" },
				{ cell = at(17, 10), kind = "Factory" },
				{ cell = at(24, 10), kind = "Factory" },
			}
			local net = Rails.build(stations, at(10, 10), field(nil, nil, wall), nil)
			T.expect(net.connected[at(17, 10)]).toBe(true)
			T.expect(net.connected[at(24, 10)]).toBe(nil)
			-- Дорога была, потом её клетку взял враг: не цела.
			local open = Rails.build(stations, at(10, 10), field(nil), nil)
			T.expect(Rails.allIntact(field(nil), open)).toBe(true)
			local cut: { [number]: boolean } = {}
			for cell in open.cells do
				cut[cell] = true
				break
			end
			T.expect(Rails.allIntact(field(nil, nil, cut), open)).toBe(false)
		end
	)

	T.it(
		"дальние станции (дальше LinkRange) не соединяются; повторный расчёт переиспользует пути",
		function()
			local range = Rails.range(W)
			local far = math.floor(range) + 3
			local stations: { Rails.Station } = {
				{ cell = at(5, 10), kind = "City" },
				{ cell = at(5 + far, 10), kind = "Factory" },
			}
			local net = Rails.build(stations, at(5, 10), field(nil), nil)
			T.expect(#net.links).toBe(0)
			local near: { Rails.Station } = {
				{ cell = at(10, 10), kind = "City" },
				{ cell = at(16, 10), kind = "Factory" },
			}
			local first = Rails.build(near, at(10, 10), field(nil), nil)
			local again = Rails.build(near, at(10, 10), field(nil), first)
			T.expect(again.links[1]).toBe(first.links[1]) -- тот же объект: путь не искали заново
		end
	)
end)
