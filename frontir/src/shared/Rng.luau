--!strict
--[[
	Rng — детерминированный генератор случайных чисел (xorshift32).
	Один и тот же сид даёт одну и ту же последовательность в Roblox и в Lune.
	Не используем math.random и Random: их состояние общее или недоступно в чистых модулях.
]]

local Bits = require("./Bits")

export type Rng = {
	state: number,
}

local Rng = {}

local TWO_32 = 4294967296

function Rng.new(seed: number): Rng
	local s = Bits.hash2(seed, 0x5EED, 0x1234567)
	if s == 0 then
		s = 0x6D2B79F5
	end
	return { state = s }
end

-- Отдельный поток для системы или державы (§12): числа одной системы не сдвигают другую.
-- (seed, a, b) — сид матча и любые два числа (номер системы, держава, цель).
function Rng.stream(seed: number, a: number, b: number?): Rng
	return Rng.new(Bits.hash2(a, b or 0, seed))
end

-- Следующее число в [0, 2^32).
function Rng.nextU32(rng: Rng): number
	local x = rng.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	rng.state = x
	return x
end

-- Число в [0, 1).
function Rng.nextFloat(rng: Rng): number
	return Rng.nextU32(rng) / TWO_32
end

-- Целое в [lo, hi] включительно.
function Rng.range(rng: Rng, lo: number, hi: number): number
	return lo + math.floor(Rng.nextFloat(rng) * (hi - lo + 1))
end

return table.freeze(Rng)
