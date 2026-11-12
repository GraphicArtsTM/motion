--!strict
-- Зрелищные удары и разрушения (§15х ч.7): план эффекта.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local StrikeFx = require("../src/shared/StrikeFx")

local cfg = Config.Render.StrikeFx

local function count(parts: { StrikeFx.Part }, kind: StrikeFx.PartKind): number
	local n = 0
	for _, p in parts do
		if p.kind == kind then
			n += 1
		end
	end
	return n
end

T.describe("План удара (§15х ч.7)", function()
	T.it("один сид — одна картинка; другой сид — другая", function()
		local a = StrikeFx.plan("missile", 50, 40, { radius = 6, seed = 7 })
		local b = StrikeFx.plan("missile", 50, 40, { radius = 6, seed = 7 })
		local c = StrikeFx.plan("missile", 50, 40, { radius = 6, seed = 8 })
		T.expect(#a).toBe(#b)
		for k = 1, #a do
			T.expect(a[k].x).toBe(b[k].x)
			T.expect(a[k].dy).toBe(b[k].dy)
		end
		local same = true
		for k = 1, math.min(#a, #c) do
			if a[k].x ~= c[k].x then
				same = false
			end
		end
		T.expect(same).toBe(false)
	end)

	T.it(
		"авиаудар: звено из JetCount самолётов с тенями, ковёр разрывов бежит по ходу самолётов",
		function()
			local r = Config.Commanders.StrikeRadius
			local parts = StrikeFx.plan("airstrike", 100, 100, { radius = r, seed = 3, dirX = 1, dirY = 0 })
			T.expect(count(parts, "jet")).toBe(cfg.JetCount)
			T.expect(count(parts, "shadow")).toBe(cfg.JetCount)
			T.expect(count(parts, "burst")).toBe(cfg.JetCount * cfg.CarpetPerLane)
			T.expect(count(parts, "cross")).toBe(1)
			-- Разрывы одной дорожки: чем дальше по ходу (x больше), тем позже.
			local bursts: { StrikeFx.Part } = {}
			for _, p in parts do
				if p.kind == "burst" then
					table.insert(bursts, p)
				end
			end
			for k = 2, cfg.CarpetPerLane do
				T.expect(bursts[k].t > bursts[k - 1].t).toBe(true)
				T.expect(bursts[k].x > bursts[k - 1].x).toBe(true)
			end
			-- Все разрывы внутри круга (с запасом на разброс), самолёты летят по направлению.
			for _, p in parts do
				if p.kind == "burst" then
					local dx, dy = p.x - 100, p.y - 100
					T.expect(math.sqrt(dx * dx + dy * dy) <= r * 1.1).toBe(true)
					T.expect(p.t >= 0.25 and p.t <= 0.25 + cfg.JetSec + 0.2).toBe(true)
				elseif p.kind == "jet" then
					T.expect(p.dx > 0 and math.abs(p.dy) < 1e-9).toBe(true)
					T.expect(p.rot).toBe(0)
				end
			end
			T.expect(count(parts, "scar") <= cfg.MaxScars).toBe(true)
		end
	)

	T.it(
		"заход сверху вниз: самолёты повёрнуты на 90°, разрывы бегут вниз",
		function()
			local parts = StrikeFx.plan("airstrike", 30, 30, { radius = 5, seed = 1, dirX = 0, dirY = 2 })
			local last = -math.huge
			local lastT = -math.huge
			local seen = 0
			for _, p in parts do
				if p.kind == "jet" then
					T.expect(math.abs(p.rot - 90) < 1e-6).toBe(true)
				elseif p.kind == "burst" and seen < cfg.CarpetPerLane then
					seen += 1
					T.expect(p.y > last and p.t > lastT).toBe(true)
					last, lastT = p.y, p.t
				end
			end
		end
	)

	T.it(
		"у каждого задетого здания — пожар (не больше MaxFires); здания вне круга не задеты",
		function()
			local width = 200
			local cells = { 10 * width + 10, 12 * width + 11, 40 * width + 40 }
			local hit = StrikeFx.buildingsIn(cells, width, 10.5, 10.5, 4)
			T.expect(#hit).toBe(2)
			local parts = StrikeFx.plan("missile", 10.5, 10.5, { radius = 4, seed = 5, buildings = hit })
			T.expect(count(parts, "fire")).toBe(2)
			local many: { StrikeFx.Point } = {}
			for k = 1, cfg.MaxFires + 5 do
				table.insert(many, { x = k, y = 1 })
			end
			local big = StrikeFx.plan("atom", 10, 10, { radius = 30, seed = 2, buildings = many })
			T.expect(count(big, "fire")).toBe(cfg.MaxFires)
		end
	)

	T.it(
		"ядерные: две волны, выжженная земля дольше у водородной; пределы обломков, воронок и углей",
		function()
			local atom = StrikeFx.plan("atom", 0, 0, { radius = 40, seed = 9 })
			local hydro = StrikeFx.plan("hydrogen", 0, 0, { radius = 80, seed = 9 })
			T.expect(count(atom, "ring")).toBe(2)
			T.expect(count(atom, "scorch")).toBe(3)
			local function scorchLife(parts: { StrikeFx.Part }): number
				for _, p in parts do
					if p.kind == "scorch" then
						return p.life
					end
				end
				return 0
			end
			T.expect(scorchLife(atom)).toBe(cfg.ScarNukeSec.atom)
			T.expect(scorchLife(hydro)).toBe(cfg.ScarNukeSec.hydrogen)
			T.expect(count(hydro, "debris") <= cfg.MaxDebris).toBe(true)
			T.expect(count(hydro, "scar") <= cfg.MaxScars).toBe(true)
			T.expect(count(hydro, "ember") <= cfg.MaxEmbers).toBe(true)
			T.expect(count(StrikeFx.plan("missile", 0, 0, { radius = 6, seed = 1 }), "scorch")).toBe(0)
		end
	)

	T.it(
		"перехват и зенитки — без пожаров и воронок; движение: обломки тормозят, самолёты ровно",
		function()
			local p = StrikeFx.plan("intercept", 5, 5, { radius = 2, seed = 4, buildings = { { x = 5, y = 5 } } })
			T.expect(count(p, "ring")).toBe(1)
			T.expect(count(p, "fire")).toBe(0)
			T.expect(count(p, "scar")).toBe(0)
			T.expect(count(StrikeFx.plan("flak", 5, 5, { radius = 4, seed = 4 }), "fire")).toBe(0)
			T.expect(StrikeFx.ease("jet", 0.5)).toBe(0.5)
			T.expect(StrikeFx.ease("debris", 0.5)).toBe(0.75)
			T.expect(StrikeFx.ease("debris", 2)).toBe(1)
			local ux, uy = StrikeFx.direction(0, 0)
			T.expect(ux).toBe(1)
			T.expect(uy).toBe(0)
		end
	)
end)
