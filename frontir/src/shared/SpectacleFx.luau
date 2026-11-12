--!strict
--[[
	SpectacleFx — план зрелища (GDD §15х ч.9), без Roblox API. Частицы — в формате StrikeFx.Part (рисует
	StrikeFxLayer.spawn). Время — секунды, размеры и координаты — клетки.
	- wake — клуб кильватера позади корабля, идущего в направлении (dx, dy);
	- duels — пары «эсминец → цель» по правилу сервера (Fleet.fight: радиус Naval.DestroyerRange, сначала транспорты);
	- salvo — залп: вспышка у ствола, трассер, всплески у цели;
	- sinking — гибель корабля: взрыв, дым, масляное пятно, кольцо на воде, обломки;
	- capture — взятый город: флаг цвета державы поднимается, две волны её цвета, искры;
	- fallout / storm — порция огоньков заражения / дождя и тучи в круге;
	- order — шевроны сходятся к точке приказа;
	- fireworks — салют залпами;
	- darkness — темнота карты по времени матча (день и ночь).
]]

local Config = require("./Config")
local Rng = require("./Rng")
local StrikeFx = require("./StrikeFx")

type Part = StrikeFx.Part

export type ShipLike = { id: number, owner: number, kind: string, x: number, y: number }
export type Duel = { from: ShipLike, to: ShipLike }

local SpectacleFx = {}

local make = StrikeFx.make

local function inCircle(rng: Rng.Rng, x: number, y: number, r: number): (number, number)
	local a = Rng.nextFloat(rng) * math.pi * 2
	local d = math.sqrt(Rng.nextFloat(rng)) * r
	return x + math.cos(a) * d, y + math.sin(a) * d
end

function SpectacleFx.wake(x: number, y: number, dx: number, dy: number, seed: number): { Part }
	local cfg = Config.Render.Spectacle
	local ux, uy = StrikeFx.direction(dx, dy)
	local rng = Rng.new(seed)
	local out: { Part } = {}
	-- Два клуба позади кормы: расходятся в стороны «усами».
	for k = -1, 1, 2 do
		local p = make("wake", 0, cfg.WakeSec, x - ux * 1.2, y - uy * 1.2, 0.7, 2.2, "White")
		p.dx = -ux * 0.8 + -uy * k * 0.7 + (Rng.nextFloat(rng) - 0.5) * 0.2
		p.dy = -uy * 0.8 + ux * k * 0.7 + (Rng.nextFloat(rng) - 0.5) * 0.2
		table.insert(out, p)
	end
	return out
end

function SpectacleFx.duels(ships: { ShipLike }, width: number, atWar: (a: number, b: number) -> boolean): { Duel }
	local range = Config.Naval.DestroyerRange * width / Config.UnitsReferenceMapWidth
	local range2 = range * range
	local out: { Duel } = {}
	for _, d in ships do
		if d.kind == "Destroyer" then
			local best: ShipLike? = nil
			local bestW = range2
			for _, t in ships do
				if t.owner ~= d.owner and atWar(d.owner, t.owner) then
					local dx, dy = t.x - d.x, t.y - d.y
					local dd = dx * dx + dy * dy
					local weight = if t.kind == "Transport" then dd * 0.25 else dd
					if dd <= range2 and weight < bestW then
						best, bestW = t, weight
					end
				end
			end
			if best ~= nil then
				table.insert(out, { from = d, to = best })
			end
		end
	end
	return out
end

function SpectacleFx.salvo(sx: number, sy: number, tx: number, ty: number, seed: number): { Part }
	local cfg = Config.Render.Spectacle
	local rng = Rng.new(seed)
	local out: { Part } = {}
	table.insert(out, make("flash", 0, 0.15, sx, sy, 0.6, 2, "White"))
	local tr = make("tracer", 0, cfg.TracerSec, sx, sy, 0.6, 0.6, "Gold")
	tr.dx, tr.dy = tx - sx, ty - sy
	table.insert(out, tr)
	for k = 1, 2 do
		local hx, hy = inCircle(rng, tx, ty, 1.6)
		table.insert(out, make("splash", cfg.TracerSec + k * 0.05, 0.6, hx, hy, 0.6, 2.4, "Sky"))
		table.insert(out, make("flash", cfg.TracerSec + k * 0.05, 0.15, hx, hy, 0.4, 1.2, "White"))
	end
	return out
end

function SpectacleFx.sinking(x: number, y: number, seed: number): { Part }
	local cfg = Config.Render.Spectacle
	local rng = Rng.new(seed)
	local out: { Part } = {}
	table.insert(out, make("flash", 0, 0.2, x, y, 1, 4, "White"))
	table.insert(out, make("burst", 0, 0.6, x, y, 1, 4, "Gold"))
	table.insert(out, make("splash", 0.1, 0.9, x, y, 1, 6, "Sky"))
	table.insert(out, make("splash", 0.35, 1.1, x, y, 1, 8, "Sky"))
	table.insert(out, make("slick", 0.3, cfg.SinkSlickSec, x, y, 1.5, 4, "Ink"))
	for k = 1, 4 do
		local s = make("smoke", 0.2 + k * 0.3, 2, x, y, 1, 3, "Steel")
		s.dx, s.dy = 0.6, -2.5
		table.insert(out, s)
	end
	for _ = 1, 6 do
		local a = Rng.nextFloat(rng) * math.pi * 2
		local d = 1.5 + Rng.nextFloat(rng) * 2
		local p = make("debris", 0, 0.9, x, y, 0.6, 0.3, "Basalt")
		p.dx, p.dy = math.cos(a) * d, math.sin(a) * d
		table.insert(out, p)
	end
	return out
end

function SpectacleFx.capture(x: number, y: number, seed: number): { Part }
	local cfg = Config.Render.Spectacle
	local rng = Rng.new(seed)
	local out: { Part } = {}
	local flag = make("flag", 0, cfg.FlagSec, x, y, cfg.FlagSize, cfg.FlagSize, "nation")
	flag.dy = -cfg.FlagRise
	table.insert(out, flag)
	table.insert(out, make("wave", 0.05, 1.1, x, y, 1, cfg.CaptureWave[1], "nation"))
	table.insert(out, make("wave", 0.3, 1.5, x, y, 1, cfg.CaptureWave[2], "nation"))
	for k = 1, 10 do
		local a = k / 10 * math.pi * 2 + Rng.nextFloat(rng) * 0.3
		local d = 3 + Rng.nextFloat(rng) * 2
		local p = make("spark", 0.05, 0.8, x, y, 0.7, 0.3, if k % 3 == 0 then "Gold" else "nation")
		p.dx, p.dy = math.cos(a) * d, math.sin(a) * d
		table.insert(out, p)
	end
	return out
end

function SpectacleFx.fallout(x: number, y: number, r: number, seed: number, n: number): { Part }
	local rng = Rng.new(seed)
	local out: { Part } = {}
	for _ = 1, n do
		local gx, gy = inCircle(rng, x, y, r * 0.95)
		local p = make("glow", Rng.nextFloat(rng) * 0.2, 1 + Rng.nextFloat(rng) * 0.6, gx, gy, 0.6, 1.6, "Lime")
		p.dy = -0.4
		table.insert(out, p)
	end
	return out
end

function SpectacleFx.storm(x: number, y: number, r: number, seed: number, n: number, clouds: number): { Part }
	local rng = Rng.new(seed)
	local out: { Part } = {}
	for _ = 1, clouds do
		local cx, cy = inCircle(rng, x, y, r * 0.8)
		local c = make("cloud", 0, 3, cx, cy, r * 0.35, r * 0.5, if Rng.nextFloat(rng) < 0.5 then "Slate" else "Steel")
		c.dx = r * 0.15
		table.insert(out, c)
	end
	for _ = 1, n do
		local rx, ry = inCircle(rng, x, y, r)
		local p = make("rain", Rng.nextFloat(rng) * 0.1, 0.45, rx, ry - 1.5, 0.35, 0.35, "Sky")
		p.dx, p.dy = 0.7, 2.4
		p.rot = 16
		table.insert(out, p)
	end
	return out
end

-- reach — откуда начинают (клеток; nil — Render.Spectacle.OrderReach): клиент растит его на дальнем плане.
function SpectacleFx.order(x: number, y: number, reach: number?): { Part }
	local cfg = Config.Render.Spectacle
	local out: { Part } = {}
	local from = math.max(cfg.OrderReach, reach or 0)
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local sx, sy = x + math.cos(a) * from, y + math.sin(a) * from
		local c = make("chev", 0, cfg.OrderSec, sx, sy, 1.6, 1.6, "Gold")
		c.dx, c.dy = x - sx, y - sy
		c.rot = math.deg(math.atan2(y - sy, x - sx)) -- остриём к точке
		table.insert(out, c)
	end
	table.insert(out, make("splash", cfg.OrderSec * 0.7, 0.5, x, y, 1, 3, "Gold"))
	return out
end

function SpectacleFx.fireworks(x: number, y: number, seed: number, volleys: number, sparks: number): { Part }
	local cfg = Config.Render.Spectacle
	local rng = Rng.new(seed)
	local out: { Part } = {}
	for v = 1, volleys do
		local t = (v - 1) * cfg.VictoryEverySec
		local cx, cy = inCircle(rng, x, y - 4, 4)
		table.insert(out, make("flash", t, 0.25, cx, cy, 1, 4, "White"))
		for k = 1, sparks do
			local a = k / sparks * math.pi * 2 + Rng.nextFloat(rng) * 0.2
			local d = 5 + Rng.nextFloat(rng) * 3
			local color = if k % 4 == 0 then "Gold" elseif k % 4 == 1 then "White" else "nation"
			local p = make("spark", t, 1.3, cx, cy, 0.8, 0.3, color)
			p.dx, p.dy = math.cos(a) * d, math.sin(a) * d + 1.5 -- искры чуть оседают
			table.insert(out, p)
		end
	end
	return out
end

-- Темнота 0..MaxDark по времени матча: полдень в 0, полночь в половине суток; ночь — пока «свет» ниже NightStart.
function SpectacleFx.darkness(matchTime: number): number
	local cfg = Config.Render.DayNight
	local phase = (math.max(0, matchTime) % cfg.CycleSec) / cfg.CycleSec
	local light = 0.5 + 0.5 * math.cos(phase * math.pi * 2)
	if light >= cfg.NightStart then
		return 0
	end
	local k = (cfg.NightStart - light) / cfg.NightStart
	return cfg.MaxDark * k * k * (3 - 2 * k) -- плавно
end

return table.freeze(SpectacleFx)
