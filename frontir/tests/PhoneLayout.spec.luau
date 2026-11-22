--!strict
-- Раскладка узкого экрана (§15ц Ц5в).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local PhoneLayout = require("../src/shared/PhoneLayout")
local UiFit = require("../src/shared/UiFit")

T.describe("Телефон (§15ц Ц5в)", function()
	T.it(
		"узкий экран: телефон и планшет — да, компьютер 1366×768 и шире — нет; флаг Studio включает",
		function()
			local function units(w: number, h: number): number
				local uw = UiFit.unitsSize(w, h)
				return uw
			end
			T.expect(PhoneLayout.narrow(units(844, 390))).toBe(true)
			T.expect(PhoneLayout.narrow(units(1024, 768))).toBe(true)
			T.expect(PhoneLayout.narrow(units(1366, 768))).toBe(false)
			T.expect(PhoneLayout.narrow(units(1920, 1080))).toBe(false)
			T.expect(PhoneLayout.narrow(units(3440, 1440))).toBe(false)
			T.expect(PhoneLayout.narrow(units(1920, 1080), true)).toBe(true)
		end
	)

	T.it(
		"полоса: широкий экран — одна строка; узкий — две, по нижней строке и в ширину экрана",
		function()
			local natural, second = 1800, 1000
			local wide = PhoneLayout.bar(natural, second, 1600, false)
			T.expect(wide.rows).toBe(1)
			T.expect(wide.width).toBe(natural)
			T.expect(math.abs(wide.scale - 1600 / natural) < 1e-9).toBe(true)
			local phone = PhoneLayout.bar(natural, second, 820, true)
			T.expect(phone.rows).toBe(2)
			T.expect(phone.width).toBe(second)
			T.expect(math.abs(phone.scale - 0.82) < 1e-9).toBe(true)
			-- Совсем узко — не мельче MinScale; широкий экран, где одна строка не влезает даже ужатой, — тоже две.
			T.expect(PhoneLayout.bar(natural, second, 300, true).scale).toBe(Config.Render.CommandBar.MinScale)
			T.expect(PhoneLayout.bar(natural, second, 900, false).rows).toBe(2)
		end
	)
end)

T.describe("Телефон от и до (§15ё)", function()
	T.it(
		"телефон — узкий или низкий экран; компьютер 1366×768 и шире — нет",
		function()
			local function phone(w: number, h: number): boolean
				local uw, uh = UiFit.unitsSize(w, h)
				return PhoneLayout.phone(uw, uh)
			end
			T.expect(phone(667, 375)).toBe(true)
			T.expect(phone(844, 390)).toBe(true)
			T.expect(phone(932, 430)).toBe(true)
			T.expect(phone(1366, 768)).toBe(false)
			T.expect(phone(1920, 1080)).toBe(false)
			-- Широкий, но низкий экран (окно Studio на половину высоты) — тоже телефон.
			T.expect(PhoneLayout.phone(1400, 400)).toBe(true)
			T.expect(PhoneLayout.phone(1920, 1080, true)).toBe(true)
		end
	)

	T.it(
		"полоса телефона — одна строка, в ширину экрана, не мельче MinScale",
		function()
			local b = PhoneLayout.phoneBar(800, 640)
			T.expect(b.rows).toBe(1)
			T.expect(math.abs(b.scale - 0.8) < 1e-9).toBe(true)
			T.expect(PhoneLayout.phoneBar(800, 1200).scale).toBe(1)
			T.expect(PhoneLayout.phoneBar(800, 100).scale).toBe(Config.Render.CommandBar.MinScale)
		end
	)

	T.it(
		"экран матча: нет наложений, всё в экране, кнопки не меньше пальца (667×300 … 1024×700)",
		function()
			local touch = Config.Render.MinTouchTargetPx
			local cfg = Config.Render.Phone.Hud
			local sizes = { { 667, 300 }, { 740, 310 }, { 844, 332 }, { 932, 372 }, { 1024, 700 } }
			local maps = { { 200, 100 }, { 200, 200 }, { 140, 200 } }
			for _, size in sizes do
				for _, m in maps do
					local w, h = size[1], size[2]
					local hud =
						PhoneLayout.hud(w, h, { strikes = 4, windows = 4, tools = 3, minimapW = m[1], minimapH = m[2] })
					local named: { [string]: PhoneLayout.Rect } = {
						menu = hud.menu,
						strikes = hud.strikes,
						windows = hud.windows,
						side = hud.side,
						bar = hud.bar,
						minimap = hud.minimap,
						tools = hud.tools,
						chips = hud.chips,
						feed = hud.feed,
					}
					local where = string.format("%d×%d, карта %d×%d", w, h, m[1], m[2])
					for a, ra in named do
						if not PhoneLayout.inside(ra, w, h) then
							error(where .. ": вне экрана — " .. a)
						end
						for b, rb in named do
							if a < b and PhoneLayout.overlap(ra, rb) then
								error(where .. ": наложение " .. a .. " и " .. b)
							end
						end
					end
					T.expect(hud.minimap.w > 40).toBe(true)
					T.expect(hud.feed.w >= 200).toBe(true)
					T.expect(hud.centerMaxW >= 260).toBe(true)
					-- Столбик по центру не налезает на колонку справа.
					T.expect((w - hud.centerMaxW) / 2 + hud.centerMaxW <= hud.side.x).toBe(true)
				end
			end
			-- Палец: кнопки верхней строки и квадраты у мини-карты.
			T.expect(cfg.StrikePx >= touch and cfg.WindowPx >= touch and cfg.ToolPx >= touch).toBe(true)
			T.expect(cfg.BarH - 2 * cfg.BarPad >= touch).toBe(true)
		end
	)

	T.it(
		"полоса Roblox: «меню», время и «Контроль суши», кнопки окон; удары — столбиком слева под полосой",
		function()
			local function counts(bandX: number, bandH: number): PhoneLayout.HudCounts
				return {
					strikes = 4,
					windows = 4,
					tools = 4,
					minimapW = 200,
					minimapH = 100,
					bandX = bandX,
					bandH = bandH,
				}
			end
			-- Безопасная зона: iPhone 16 Pro Max 956×440 (без выреза по бокам ~832, HUD ниже полосы — ~361), 750×381,
			-- 844×390, 667×375.
			for _, size in { { 832, 361 }, { 750, 323 }, { 844, 332 }, { 667, 317 } } do
				local w, h = size[1], size[2]
				local lay = PhoneLayout.hud(w, h, counts(164, 58))
				local where = string.format("%d×%d", w, h)
				T.expect(lay.inBand).toBe(true)
				-- В полосе: справа от кнопок Roblox, по высоте внутри неё, друг на друга не налезают.
				local band: { PhoneLayout.Rect } = { lay.menu, lay.windows }
				local top = lay.top
				if top ~= nil then
					table.insert(band, top)
				end
				for i, r in band do
					if not (r.x >= 164 and r.y >= 0 and r.y + r.h <= 58 and r.x + r.w <= w) then
						error(where .. ": вне полосы — " .. i)
					end
					for j, r2 in band do
						if i < j and PhoneLayout.overlap(r, r2) then
							error(where .. ": наложение в полосе " .. i .. " × " .. j)
						end
					end
				end
				-- В HUD: удары столбиком слева сверху, справа «#N» и «АТАКИ»; ничего не налезает и всё в экране.
				T.expect(lay.strikes.x).toBe(Config.Render.Phone.Hud.Edge)
				T.expect(lay.strikes.w).toBe(Config.Render.Phone.Hud.StrikePx)
				T.expect(lay.strikes.h > lay.strikes.w).toBe(true)
				T.expect(lay.feed.w >= 200).toBe(true)
				T.expect(lay.strikes.y).toBe(Config.Render.Phone.Hud.TopY)
				local named: { [string]: PhoneLayout.Rect } = {
					strikes = lay.strikes,
					side = lay.side,
					bar = lay.bar,
					minimap = lay.minimap,
					tools = lay.tools,
					chips = lay.chips,
					feed = lay.feed,
				}
				for a, ra in named do
					if not PhoneLayout.inside(ra, w, h) then
						error(where .. ": вне экрана — " .. a)
					end
					for b, rb in named do
						if a < b and PhoneLayout.overlap(ra, rb) then
							error(where .. ": наложение " .. a .. " × " .. b)
						end
					end
				end
				-- Столбик сверху по центру — между ударами и колонкой справа.
				T.expect(lay.centerX - lay.centerMaxW / 2 >= lay.strikes.x + lay.strikes.w).toBe(true)
				T.expect(lay.centerX + lay.centerMaxW / 2 <= lay.side.x).toBe(true)
				T.expect(lay.centerMaxW >= 200).toBe(true)
			end
			-- На широких телефонах время и «Контроль суши» — в полосе; на узком (667) — не влезают, остаются по центру.
			T.expect(PhoneLayout.hud(832, 361, counts(164, 58)).top ~= nil).toBe(true)
			T.expect(PhoneLayout.hud(750, 323, counts(164, 58)).top ~= nil).toBe(true)
			T.expect(PhoneLayout.hud(667, 317, counts(164, 58)).top == nil).toBe(true)
			-- Низкая полоса (старый верх Roblox), узкий экран или нет полосы — ряд в HUD, как раньше.
			T.expect(PhoneLayout.hud(750, 323, counts(164, 36)).inBand).toBe(false)
			T.expect(PhoneLayout.hud(400, 323, counts(164, 58)).inBand).toBe(false)
			T.expect(PhoneLayout.hud(750, 323, counts(0, 0)).inBand).toBe(false)
		end
	)
end)
