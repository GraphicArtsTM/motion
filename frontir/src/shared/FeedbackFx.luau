--!strict
--[[
	FeedbackFx — отклик на действия игрока (GDD §15й Й4), без Roblox API. Частицы — в формате StrikeFx.Part (рисует
	StrikeFxLayer.spawn; время — секунды, координаты — клетки), остальное — числа для клиента:
	- countdown — что показать перед стартом матча: «3», «2», «1» по секундам до конца выбора старта (иначе nil);
	- builtSparks — «Готово!»: вспышка и золотые искры над достроенным зданием;
	- growFlashes — какие из новых своих клеток вспыхнут (равномерно по списку, не больше предела);
	- coin — точка монеты на дуге от места события к счётчику денег (k-я из n, доля пути t 0..1);
	- sent — сколько людей уходит при нажатии (люди × доля атаки, целое).
]]

local Config = require("./Config")
local Rng = require("./Rng")
local StrikeFx = require("./StrikeFx")

type Part = StrikeFx.Part

local FeedbackFx = {}

-- Цифра отсчёта перед стартом: «3» / «2» / «1» в последние Render.Feedback.CountdownFrom секунд выбора старта.
function FeedbackFx.countdown(left: number): string?
	local from = Config.Render.Feedback.CountdownFrom
	if left <= 0 or left > from then
		return nil
	end
	return tostring(math.clamp(math.ceil(left), 1, from))
end

-- Искры «Готово!» над зданием в (x, y): вспышка, кольцо и золотые искры вверх-веером.
function FeedbackFx.builtSparks(x: number, y: number, seed: number): { Part }
	local cfg = Config.Render.Feedback
	local rng = Rng.new(seed)
	local out: { Part } = {}
	table.insert(out, StrikeFx.make("flash", 0, 0.3, x, y, 1, 3, "White"))
	table.insert(out, StrikeFx.make("ring", 0, 0.5, x, y, 1, 5, "Gold"))
	for k = 1, cfg.BuiltSparks do
		local a = -math.pi * (0.1 + 0.8 * (k - 1) / math.max(1, cfg.BuiltSparks - 1)) -- веер вверх
		local d = 2.5 + Rng.nextFloat(rng) * 1.5
		local p = StrikeFx.make(
			"spark",
			Rng.nextFloat(rng) * 0.1,
			0.8,
			x,
			y,
			0.6,
			0.2,
			if k % 3 == 0 then "White" else "Gold"
		)
		p.dx, p.dy = math.cos(a) * d, math.sin(a) * d
		table.insert(out, p)
	end
	return out
end

-- Индексы вспышек роста: из count новых клеток — не больше limit, равномерно (1-based, по возрастанию).
function FeedbackFx.growFlashes(count: number, limit: number): { number }
	local out: { number } = {}
	if count <= 0 or limit <= 0 then
		return out
	end
	local step = math.max(1, count / limit)
	local k = 1.0
	while k <= count and #out < limit do
		table.insert(out, math.floor(k))
		k += step
	end
	return out
end

-- Монета k из n на пути (x0, y0) → (x1, y1) (пиксели экрана), доля пути t (0..1): дуга вверх, монеты веером —
-- у каждой свой изгиб; на старте и на финише все в своих точках.
function FeedbackFx.coin(
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	k: number,
	n: number,
	t: number
): (number, number)
	local cfg = Config.Render.Feedback
	local u = math.clamp(t, 0, 1)
	local e = 1 - (1 - u) * (1 - u) -- быстро взлетает, плавно садится
	local spread = if n > 1 then ((k - 1) / (n - 1) - 0.5) * 2 else 0
	local lift = cfg.CoinArcPx * (1 + 0.3 * spread)
	local side = cfg.CoinSpreadPx * spread
	local bump = 4 * u * (1 - u) -- 0 на концах, 1 посередине
	return x0 + (x1 - x0) * e + side * bump, y0 + (y1 - y0) * e - lift * bump
end

-- Сколько людей уходит при нажатии атаки (как сервер: people × percent).
function FeedbackFx.sent(people: number, percent: number): number
	return math.floor(math.max(0, people) * math.clamp(percent, 0, 1))
end

return table.freeze(FeedbackFx)
