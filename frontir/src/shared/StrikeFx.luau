--!strict
--[[
	StrikeFx — план зрелища удара (GDD §15х ч.7), без Roblox API: что показать, где и когда.
	plan(kind, x, y, options) → список частиц Part. У частицы: вид, задержка от начала t, длительность life,
	начало (x, y) и смещение за жизнь (dx, dy) в клетках, размер s0 → s1 (поперечник в клетках), цвет палитры
	(«nation» — цвет державы удара), слой z и поворот rot (градусы). Рисует Render/StrikeFxLayer, движение —
	ease(kind, t). Один сид — одна картинка.
	Виды ударов:
	- airstrike — прицел сжимается на цели, звено штурмовиков проходит над кругом по направлению (dirX, dirY), за
	  каждым — дорожка разрывов («ковёр»): вспышка, огненный шар, пыль, воронка; разрывы бегут по ходу самолёта;
	- raid — ковёр разрывов двумя дорожками без звена (бомбардировщик рисует AirLayer);
	- missile — обломки разлетаются, воронки, дым над целью (огненный шар и волна — WarFxLayer);
	- atom / hydrogen — то же крупнее, две ударные волны, выжженная земля и тлеющие угли;
	- intercept — белое кольцо и осколки в точке перехвата; flak — разрывы зениток над целью (налёт сбит).
	Задетые здания (options.buildings — центры клеток) — вторичный взрыв, пожар и дым.
]]

local Config = require("./Config")
local Rng = require("./Rng")

export type Kind = "airstrike" | "raid" | "missile" | "atom" | "hydrogen" | "intercept" | "flak"
export type PartKind =
	"cross"
	| "jet"
	| "shadow"
	| "flash"
	| "burst"
	| "dust"
	| "ring"
	| "scar"
	| "scorch"
	| "fire"
	| "smoke"
	| "debris"
	| "ember"

export type Part = {
	kind: PartKind,
	t: number,
	life: number,
	x: number,
	y: number,
	dx: number,
	dy: number,
	s0: number,
	s1: number,
	color: string,
	z: number,
	rot: number,
}

export type Point = { x: number, y: number }

export type Options = {
	radius: number,
	seed: number,
	dirX: number?, -- направление захода самолётов (не обязательно единичное)
	dirY: number?,
	buildings: { Point }?, -- задетые здания и города (центры клеток)
}

local StrikeFx = {}

-- Слои (ZIndex на canvas): земля → дым → огонь → взрывы → самолёты.
StrikeFx.Z = table.freeze({
	scorch = 8,
	scar = 9,
	ember = 10,
	dust = 11,
	smoke = 12,
	fire = 12,
	debris = 13,
	burst = 14,
	ring = 14,
	flash = 15,
	cross = 15,
	shadow = 16,
	jet = 17,
})

local function part(
	kind: PartKind,
	t: number,
	life: number,
	x: number,
	y: number,
	s0: number,
	s1: number,
	color: string
): Part
	return {
		kind = kind,
		t = t,
		life = life,
		x = x,
		y = y,
		dx = 0,
		dy = 0,
		s0 = s0,
		s1 = s1,
		color = color,
		z = (StrikeFx.Z :: any)[kind] or 12,
		rot = 0,
	}
end

-- Движение частицы за жизнь 0..1: самолёты — ровно, обломки — быстро и тормозят, дым — плавно.
function StrikeFx.ease(kind: PartKind, t: number): number
	t = math.clamp(t, 0, 1)
	if kind == "jet" or kind == "shadow" then
		return t
	end
	return 1 - (1 - t) * (1 - t)
end

-- Единичное направление (dx, dy); нулевое — слева направо.
function StrikeFx.direction(dx: number?, dy: number?): (number, number)
	local x, y = dx or 0, dy or 0
	local len = math.sqrt(x * x + y * y)
	if len < 1e-6 then
		return 1, 0
	end
	return x / len, y / len
end

-- Здания в круге: клетки списка cells (ширина карты width) не дальше r от (x, y) — центры клеток.
function StrikeFx.buildingsIn(cells: { number }, width: number, x: number, y: number, r: number): { Point }
	local out: { Point } = {}
	local r2 = r * r
	for _, c in cells do
		local cx, cy = c % width + 0.5, c // width + 0.5
		local dx, dy = cx - x, cy - y
		if dx * dx + dy * dy <= r2 then
			table.insert(out, { x = cx, y = cy })
		end
	end
	table.sort(out, function(a: Point, b: Point): boolean
		if a.y ~= b.y then
			return a.y < b.y
		end
		return a.x < b.x
	end)
	return out
end

-- Случайная точка в круге радиуса r (равномерно по площади).
local function inCircle(rng: Rng.Rng, x: number, y: number, r: number): (number, number)
	local a = Rng.nextFloat(rng) * math.pi * 2
	local d = math.sqrt(Rng.nextFloat(rng)) * r
	return x + math.cos(a) * d, y + math.sin(a) * d
end

-- Разрыв бомбы: вспышка, огненный шар, пыль (сносит по ходу), воронка (если scar).
local function burst(
	out: { Part },
	t: number,
	x: number,
	y: number,
	size: number,
	ux: number,
	uy: number,
	scar: boolean
)
	local cfg = Config.Render.StrikeFx
	table.insert(out, part("flash", t, 0.18, x, y, size * 0.3, size * 1.1, "White"))
	table.insert(out, part("burst", t, cfg.BurstSec, x, y, size * 0.35, size, "Gold"))
	local dust = part("dust", t + 0.08, cfg.DustSec, x, y, size * 0.6, size * 1.7, "Rock")
	dust.dx, dust.dy = ux * size * 0.5, uy * size * 0.5
	table.insert(out, dust)
	if scar then
		table.insert(out, part("scar", t + 0.1, cfg.ScarSec, x, y, size * 0.55, size * 0.6, "Basalt"))
	end
end

-- Пожар над зданием: огонь мерцает, клубы дыма поднимаются (вверх по экрану — dy < 0).
local function fire(out: { Part }, rng: Rng.Rng, t: number, x: number, y: number)
	local cfg = Config.Render.StrikeFx
	table.insert(out, part("burst", t, cfg.BurstSec, x, y, 0.8, 2.4, "Gold"))
	table.insert(out, part("fire", t + 0.1, cfg.FireSec, x, y, 1.4, 1.1, "Orange"))
	local at = t + 0.3
	while at < t + cfg.FireSec - 0.5 do
		local s = part("smoke", at, 1.8, x + (Rng.nextFloat(rng) - 0.5) * 0.6, y, 0.9, 2.6, "Steel")
		s.dx, s.dy = 0.6 + Rng.nextFloat(rng) * 0.4, -3 - Rng.nextFloat(rng) * 1.5
		table.insert(out, s)
		at += cfg.SmokeEverySec
	end
end

-- Обломки: летят от центра во все стороны и тормозят.
local function debris(out: { Part }, rng: Rng.Rng, x: number, y: number, r: number, count: number, t: number)
	local cfg = Config.Render.StrikeFx
	for _ = 1, count do
		local a = Rng.nextFloat(rng) * math.pi * 2
		local d = r * cfg.DebrisReach * (0.35 + 0.65 * Rng.nextFloat(rng))
		local hot = Rng.nextFloat(rng) < 0.4
		local p = part(
			"debris",
			t + Rng.nextFloat(rng) * 0.1,
			cfg.DebrisSec * (0.7 + 0.5 * Rng.nextFloat(rng)),
			x,
			y,
			0.7,
			0.35,
			if hot then "Orange" else "Basalt"
		)
		p.dx, p.dy = math.cos(a) * d, math.sin(a) * d
		p.rot = Rng.nextFloat(rng) * 90
		table.insert(out, p)
	end
end

local function scars(out: { Part }, rng: Rng.Rng, x: number, y: number, r: number, life: number)
	local cfg = Config.Render.StrikeFx
	local n = math.clamp(math.floor(r * cfg.ScarsPerRadius), 2, cfg.MaxScars)
	for _ = 1, n do
		local sx, sy = inCircle(rng, x, y, r * 0.8)
		local s = 1 + Rng.nextFloat(rng) * 1.6
		table.insert(out, part("scar", 0.1 + Rng.nextFloat(rng) * 0.3, life, sx, sy, s, s * 1.08, "Basalt"))
	end
end

-- Ковёр разрывов: дорожки (lanes) поперёк направления, разрывы бегут по ходу; laneOffset — сдвиг дорожки,
-- passT(a) — когда самолёт дорожки над точкой «a» вдоль пути (a от −r до r).
local function carpet(
	out: { Part },
	rng: Rng.Rng,
	x: number,
	y: number,
	r: number,
	ux: number,
	uy: number,
	lanes: { number },
	passT: (lane: number, along: number) -> number
)
	local cfg = Config.Render.StrikeFx
	local px, py = -uy, ux
	local n = cfg.CarpetPerLane
	local scarEvery = math.max(1, math.ceil(n * #lanes / cfg.MaxScars))
	local made = 0
	for li, off in lanes do
		-- Дорожка — по хорде круга: крайние дорожки короче, разрывы не вылезают за круг.
		local half = math.sqrt(math.max(0, (r * 0.92) ^ 2 - off * off)) * 0.9
		for i = 1, n do
			local along = -half + (i - 1) / math.max(1, n - 1) * half * 2 + (Rng.nextFloat(rng) - 0.5) * r * 0.1
			local side = off + (Rng.nextFloat(rng) - 0.5) * r * 0.2
			local bx, by = x + ux * along + px * side, y + uy * along + py * side
			made += 1
			local size = cfg.BurstSize * (0.8 + 0.4 * Rng.nextFloat(rng))
			burst(out, passT(li, along) + 0.12, bx, by, size, ux, uy, made % scarEvery == 0)
		end
	end
end

function StrikeFx.plan(kind: Kind, x: number, y: number, opt: Options): { Part }
	local cfg = Config.Render.StrikeFx
	local rng = Rng.new(opt.seed)
	local r = math.max(1, opt.radius)
	local ux, uy = StrikeFx.direction(opt.dirX, opt.dirY)
	local out: { Part } = {}
	local buildings: { Point } = opt.buildings or {}
	local scarNuke = if kind == "hydrogen" then cfg.ScarNukeSec.hydrogen else cfg.ScarNukeSec.atom

	if kind == "airstrike" then
		-- Прицел сжимается на цели.
		table.insert(out, part("cross", 0, 0.5, x, y, r * 2.6, r * 1.6, "Red"))
		-- Звено: строй «клин», самолёты идут через круг от края до края с запасом.
		local margin = r + 10
		local count = cfg.JetCount
		local lanes: { number } = {}
		local back: { number } = {}
		for k = 1, count do
			local mid = (count + 1) / 2
			-- Строй не теснее самолёта, дорожки — внутри круга.
			lanes[k] = (k - mid) * math.min(cfg.JetSize * cfg.JetSpacing, r * 0.8)
			back[k] = math.abs(k - mid) * cfg.JetSize * 0.9
		end
		local angle = math.deg(math.atan2(uy, ux))
		for k = 1, count do
			local px, py = -uy * lanes[k], ux * lanes[k]
			local sx = x - ux * (margin + back[k]) + px
			local sy = y - uy * (margin + back[k]) + py
			local jet = part("jet", 0.25, cfg.JetSec, sx, sy, cfg.JetSize, cfg.JetSize, "nation")
			jet.dx, jet.dy = ux * 2 * margin, uy * 2 * margin
			jet.rot = angle
			table.insert(out, jet)
			local shadow = part("shadow", 0.25, cfg.JetSec, sx + 1.2, sy + 1.8, cfg.JetSize, cfg.JetSize, "Ink")
			shadow.dx, shadow.dy = jet.dx, jet.dy
			shadow.rot = angle
			table.insert(out, shadow)
		end
		carpet(out, rng, x, y, r, ux, uy, lanes, function(lane: number, along: number): number
			local s = (along + margin + back[lane]) / (2 * margin)
			return 0.25 + math.clamp(s, 0, 1) * cfg.JetSec
		end)
	elseif kind == "raid" then
		local lanes = { -r * 0.3, r * 0.3 }
		carpet(out, rng, x, y, r, ux, uy, lanes, function(_lane: number, along: number): number
			return (along + r) / (2 * r) * 0.7
		end)
	elseif kind == "missile" or kind == "atom" or kind == "hydrogen" then
		local nuke = kind ~= "missile"
		if nuke then
			-- Две волны: быстрая белая и медленная огненная.
			local w1 = part("ring", 0, cfg.WaveSec[1], x, y, r * 0.4, r * 2 * cfg.WaveReach[1], "White")
			local w2 = part("ring", 0.1, cfg.WaveSec[2], x, y, r * 0.3, r * 2 * cfg.WaveReach[2], "Orange")
			table.insert(out, w1)
			table.insert(out, w2)
			-- Выжженная земля и угли.
			local life = scarNuke
			-- Три диска друг на друге: к центру темнее.
			for k, f in { 2, 1.4, 0.8 } do
				table.insert(out, part("scorch", 0.2 + k * 0.05, life, x, y, r * f * 0.8, r * f, "Basalt"))
			end
			local embers = math.min(cfg.MaxEmbers, math.floor(r * cfg.EmbersPerRadius) + 4)
			for _ = 1, embers do
				local ex, ey = inCircle(rng, x, y, r * 0.95)
				local e = part(
					"ember",
					0.4 + Rng.nextFloat(rng),
					life * (0.4 + 0.5 * Rng.nextFloat(rng)),
					ex,
					ey,
					0.9,
					0.5,
					"Orange"
				)
				table.insert(out, e)
			end
		end
		debris(out, rng, x, y, r, math.min(cfg.MaxDebris, math.floor(r * cfg.DebrisPerRadius) + 4), 0)
		scars(out, rng, x, y, r, if nuke then scarNuke else cfg.ScarSec)
		-- Дым над целью.
		for k = 1, if nuke then 6 else 3 do
			local s = part(
				"smoke",
				0.3 + k * 0.25,
				2.4,
				x + (Rng.nextFloat(rng) - 0.5) * r * 0.5,
				y,
				r * 0.4,
				r * 1.1,
				"Steel"
			)
			s.dx, s.dy = r * 0.15, -r * 0.6
			table.insert(out, s)
		end
	elseif kind == "intercept" then
		table.insert(out, part("flash", 0, 0.2, x, y, 1, 3, "White"))
		table.insert(out, part("ring", 0, cfg.InterceptRingSec, x, y, 1, cfg.InterceptRingSize, "White"))
		debris(out, rng, x, y, 2, 6, 0.02)
	elseif kind == "flak" then
		-- Налёт сбит: разрывы зениток вокруг цели, кольцо.
		table.insert(out, part("ring", 0, cfg.InterceptRingSec, x, y, 1, cfg.InterceptRingSize, "White"))
		for k = 1, 5 do
			local fx, fy = inCircle(rng, x, y, r * 0.8)
			table.insert(out, part("flash", k * 0.08, 0.2, fx, fy, 0.5, 1.6, "White"))
			table.insert(out, part("dust", k * 0.08, 1.2, fx, fy, 0.8, 2.2, "Steel"))
		end
	end

	-- Задетые здания: вторичный взрыв, пожар и дым.
	if kind ~= "intercept" and kind ~= "flak" then
		for k, b in buildings do
			if k > cfg.MaxFires then
				break
			end
			fire(out, rng, 0.15 + Rng.nextFloat(rng) * 0.6, b.x, b.y)
		end
	end
	return out
end

return table.freeze(StrikeFx)
