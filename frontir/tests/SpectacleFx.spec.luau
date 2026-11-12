--!strict
-- Зрелищность (§15х ч.9): план частиц.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local SpectacleFx = require("../src/shared/SpectacleFx")
local StrikeFx = require("../src/shared/StrikeFx")

local function count(parts: { StrikeFx.Part }, kind: StrikeFx.PartKind): number
	local n = 0
	for _, p in parts do
		if p.kind == kind then
			n += 1
		end
	end
	return n
end

T.describe("Зрелищность (§15х ч.9)", function()
	T.it("кильватер — позади корабля", function()
		for _, p in SpectacleFx.wake(10, 10, 1, 0, 1) do
			T.expect(p.x < 10).toBe(true)
			T.expect(p.dx < 0).toBe(true)
		end
		for _, p in SpectacleFx.wake(10, 10, 0, -1, 1) do
			T.expect(p.y > 10).toBe(true)
		end
	end)

	T.it(
		"морской бой: эсминец бьёт врага в радиусе (сначала транспорт), союзника и далёкого — нет",
		function()
			local width = Config.UnitsReferenceMapWidth
			local range = Config.Naval.DestroyerRange
			local ships: { SpectacleFx.ShipLike } = {
				{ id = 1, owner = 1, kind = "Destroyer", x = 0, y = 0 },
				{ id = 2, owner = 2, kind = "Destroyer", x = range * 0.5, y = 0 },
				{ id = 3, owner = 2, kind = "Transport", x = range * 0.9, y = 0 },
				{ id = 4, owner = 3, kind = "Transport", x = 1, y = 0 }, -- не враг
				{ id = 5, owner = 2, kind = "Transport", x = range * 3, y = 0 }, -- далеко
			}
			local function atWar(a: number, b: number): boolean
				return (a == 1 and b == 2) or (a == 2 and b == 1)
			end
			local duels = SpectacleFx.duels(ships, width, atWar)
			T.expect(#duels).toBe(2)
			T.expect(duels[1].from.id).toBe(1)
			T.expect(duels[1].to.id).toBe(3) -- транспорт в приоритете (вес ×0.25)
			T.expect(duels[2].from.id).toBe(2)
			T.expect(duels[2].to.id).toBe(1)
			local salvo = SpectacleFx.salvo(0, 0, 5, 0, 7)
			T.expect(count(salvo, "tracer")).toBe(1)
			T.expect(count(salvo, "splash")).toBe(2)
		end
	)

	T.it(
		"тонущий корабль: пятно, всплески, дым; взятый город: флаг цвета державы поднимается и волны",
		function()
			local sink = SpectacleFx.sinking(4, 4, 2)
			T.expect(count(sink, "slick")).toBe(1)
			T.expect(count(sink, "splash") >= 2).toBe(true)
			local cap = SpectacleFx.capture(4, 4, 3)
			T.expect(count(cap, "flag")).toBe(1)
			T.expect(count(cap, "wave")).toBe(2)
			for _, p in cap do
				if p.kind == "flag" then
					T.expect(p.color).toBe("nation")
					T.expect(p.dy).toBe(-Config.Render.Spectacle.FlagRise)
				end
			end
		end
	)

	T.it(
		"заражение и дождь — внутри круга; шевроны сходятся к точке",
		function()
			for _, p in SpectacleFx.fallout(50, 50, 8, 1, 20) do
				T.expect((p.x - 50) ^ 2 + (p.y - 50) ^ 2 <= 64).toBe(true)
			end
			local rain = SpectacleFx.storm(50, 50, 10, 1, 30, 2)
			T.expect(count(rain, "rain")).toBe(30)
			T.expect(count(rain, "cloud")).toBe(2)
			for _, p in SpectacleFx.order(20, 20) do
				if p.kind == "chev" then
					T.expect(math.abs(p.x + p.dx - 20) < 1e-9 and math.abs(p.y + p.dy - 20) < 1e-9).toBe(true)
				end
			end
			-- На дальнем плане — издалека (reach больше OrderReach).
			for _, p in SpectacleFx.order(20, 20, 30) do
				if p.kind == "chev" then
					T.expect(math.sqrt(p.dx * p.dx + p.dy * p.dy) > 29).toBe(true)
				end
			end
			local fw = SpectacleFx.fireworks(10, 10, 1, 3, 12)
			T.expect(count(fw, "spark")).toBe(36)
		end
	)

	T.it(
		"день и ночь: полдень светлый, полночь — MaxDark, плавно и по кругу",
		function()
			local cfg = Config.Render.DayNight
			T.expect(SpectacleFx.darkness(0)).toBe(0)
			T.expect(math.abs(SpectacleFx.darkness(cfg.CycleSec / 2) - cfg.MaxDark) < 1e-9).toBe(true)
			T.expect(SpectacleFx.darkness(cfg.CycleSec)).toBe(0)
			local a = SpectacleFx.darkness(cfg.CycleSec * 0.42)
			local b = SpectacleFx.darkness(cfg.CycleSec * 0.47)
			T.expect(a < b and b < cfg.MaxDark).toBe(true)
			T.expect(SpectacleFx.darkness(cfg.CycleSec * 0.2)).toBe(0) -- днём темноты нет
		end
	)
end)
