--!strict
--!native
--[[
	Bits — 32-битная целочисленная арифметика поверх чисел Luau (double).
	Нужна для детерминированных хешей и ГСЧ: результат одинаков в Roblox и в Lune.
]]

local Bits = {}

local TWO_32 = 4294967296
local TWO_16 = 65536

-- Приводит число к беззнаковому 32-битному целому.
function Bits.u32(n: number): number
	return math.floor(n) % TWO_32
end

-- Умножение по модулю 2^32 без потери точности (произведение двух u32 не влезает в double).
function Bits.mul32(a: number, b: number): number
	local aLo = a % TWO_16
	local aHi = (a - aLo) / TWO_16
	return (aLo * b + ((aHi * b) % TWO_16) * TWO_16) % TWO_32
end

-- Хеш двух целых координат и сида в [0, 2^32).
function Bits.hash2(x: number, y: number, seed: number): number
	local h = Bits.u32(seed)
	h = Bits.mul32(bit32.bxor(h, Bits.u32(x)), 0x9E3779B1)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = Bits.mul32(bit32.bxor(h, Bits.u32(y)), 0x85EBCA77)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = Bits.mul32(h, 0xC2B2AE3D)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

-- Хеш координат в [0, 1).
function Bits.hash2f(x: number, y: number, seed: number): number
	return Bits.hash2(x, y, seed) / TWO_32
end

return table.freeze(Bits)
