--!strict
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local WarFx = require("../src/shared/WarFx")

-- Карта w×h: левая половина — держава 1, правая — 2 (граница по x = w/2).
local function halves(w: number): (number) -> number
	return function(i: number): number
		return if i % w < w // 2 then 1 else 2
	end
end

T.describe("Зрелищная война (§15б)", function()
	T.it("общая граница: клетки a у b, не больше max, равномерно", function()
		local w, h = 20, 10
		local own = halves(w)
		local all = WarFx.borderSamples(own, w, h, 1, 2, 0, 0, w - 1, h - 1, 1, 100)
		T.expect(#all).toBe(h)
		for _, i in all do
			T.expect(i % w).toBe(w // 2 - 1)
		end
		T.expect(#WarFx.borderSamples(own, w, h, 1, 2, 0, 0, w - 1, h - 1, 1, 4)).toBe(4)
		T.expect(#WarFx.borderSamples(own, w, h, 1, 3, 0, 0, w - 1, h - 1, 1, 100)).toBe(0)
	end)

	T.it(
		"стрелки наступления: от нападающего к цели, куски по длине линии, в пределах прямоугольника",
		function()
			local w, h = 40, 60
			local own = halves(w)
			local list = WarFx.frontArrows(own, w, h, 1, 2, 0, 0, w - 1, h - 1, 1, 3, 10)
			T.expect(#list).toBe(3)
			for _, a in list do
				T.expect(a.dx).toBe(1)
				T.expect(a.dy).toBe(0)
				T.expect(math.abs(a.x - (w // 2 - 0.5)) < 1e-6).toBe(true)
			end
			-- Обратная сторона — к левой державе.
			T.expect(WarFx.frontArrows(own, w, h, 2, 1, 0, 0, w - 1, h - 1, 1, 1, 10)[1].dx).toBe(-1)
			-- Мало линии в окне — стрелок нет.
			T.expect(#WarFx.frontArrows(own, w, h, 1, 2, 0, 0, w - 1, 4, 1, 3, 10)).toBe(0)
		end
	)

	T.it(
		"вспышки захвата: только переход от державы к державе; ничья земля не считается",
		function()
			local owners = { 1, 1, 0, 2 }
			local function own(i: number): number
				return owners[i + 1]
			end
			local mem = WarFx.newMemory(4)
			WarFx.remember(mem, own)
			owners[1] = 2 -- захват у 1
			owners[3] = 2 -- ничья → 2
			owners[4] = 0 -- 2 → ничья (восстание)
			local got = WarFx.captures(mem, { 0, 2, 3 }, own)
			T.expect(#got).toBe(1)
			T.expect(got[1]).toBe(0)
			-- Второй раз то же — уже запомнено.
			T.expect(#WarFx.captures(mem, { 0, 2, 3 }, own)).toBe(0)
		end
	)

	T.it(
		"яркость стрелки: побеждающий фронт и «Первый удар» ярче; числа в Config",
		function()
			local full = Config.Combat.FullSpeedRatio
			T.expect(WarFx.arrowStrength(1, full, false) < WarFx.arrowStrength(full, full, false)).toBe(true)
			T.expect(WarFx.arrowStrength(1, full, true) > WarFx.arrowStrength(1, full, false)).toBe(true)
			T.expect(WarFx.arrowStrength(math.huge, full, false)).toBe(1)
			local cfg = Config.Render.WarFx
			T.expect(cfg.MaxArrows >= Config.Render.Phone.MaxArrows).toBe(true)
			T.expect(cfg.MaxCaptureFlashes >= Config.Render.Phone.MaxCaptureFlashes).toBe(true)
		end
	)

	T.it(
		"§15м: полосы перевеса, тряска экрана затухает, пределы телефона не больше обычных",
		function()
			local full, br = Config.Combat.FullSpeedRatio, Config.Combat.BreakthroughRatio
			T.expect(WarFx.ratioBand(0.7, full, br)).toBe("stall")
			T.expect(WarFx.ratioBand(1, full, br)).toBe("stall")
			T.expect(WarFx.ratioBand(1.4, full, br)).toBe("crawl")
			T.expect(WarFx.ratioBand(full, full, br)).toBe("full")
			T.expect(WarFx.ratioBand(br, full, br)).toBe("breakthrough")
			T.expect(WarFx.ratioBand(math.huge, full, br)).toBe("breakthrough")
			local sh = Config.Render.Shake
			local x0, y0 = WarFx.shake(1, sh.NukePx, sh.Hz, sh.Sec)
			T.expect(x0 == 0 and y0 == 0).toBe(true)
			local peak = 0
			for k = 0, 9 do
				local x, y = WarFx.shake(k / 10, sh.NukePx, sh.Hz, sh.Sec)
				T.expect(math.abs(x) <= sh.NukePx and math.abs(y) <= sh.NukePx).toBe(true)
				peak = math.max(peak, math.abs(x), math.abs(y))
			end
			T.expect(peak > 0).toBe(true)
			local late = 0
			for k = 80, 99 do
				local x, y = WarFx.shake(k / 100, sh.NukePx, sh.Hz, sh.Sec)
				late = math.max(late, math.abs(x), math.abs(y))
			end
			T.expect(late < peak * 0.1).toBe(true)
			local fx, phone = Config.Render.BattleFx, Config.Render.Phone
			T.expect(fx.MaxBadges >= phone.MaxBadges and fx.MaxRings >= phone.MaxRings).toBe(true)
			T.expect(fx.FireworkSparks >= phone.FireworkSparks).toBe(true)
		end
	)
end)
