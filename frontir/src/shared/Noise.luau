--!strict
--[[
	Noise — детерминированный value-noise и его производные (fbm, ridged) для генератора карт.
	Решётка значений строится хешем Bits.hash2, поэтому результат не зависит от платформы.
]]

local Bits = require("./Bits")

local Noise = {}

-- Поворот между октавами (~32°) убирает «квадратность» решётки value-noise.
local ROT_COS = math.cos(0.56)
local ROT_SIN = math.sin(0.56)

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Value-noise в точке (x, y), результат в [0, 1).
function Noise.value2(x: number, y: number, seed: number): number
	local ix = math.floor(x)
	local iy = math.floor(y)
	local fx = smooth(x - ix)
	local fy = smooth(y - iy)
	local a = Bits.hash2f(ix, iy, seed)
	local b = Bits.hash2f(ix + 1, iy, seed)
	local c = Bits.hash2f(ix, iy + 1, seed)
	local d = Bits.hash2f(ix + 1, iy + 1, seed)
	local top = a + (b - a) * fx
	local bottom = c + (d - c) * fx
	return top + (bottom - top) * fy
end

-- Фрактальный шум: сумма октав value-noise, нормированная в [0, 1).
function Noise.fbm(x: number, y: number, seed: number, octaves: number, lacunarity: number, gain: number): number
	local sum = 0
	local amp = 1
	local freq = 1
	local norm = 0
	local px, py = x, y
	for octave = 0, octaves - 1 do
		sum += amp * Noise.value2(px * freq, py * freq, (seed + octave * 7919) % 4294967296)
		norm += amp
		amp *= gain
		freq *= lacunarity
		px, py = px * ROT_COS - py * ROT_SIN + 17.31, px * ROT_SIN + py * ROT_COS + 9.73
	end
	return sum / norm
end

-- «Гребневый» шум: максимумы вытянуты в линии — для горных хребтов. Результат в [0, 1].
function Noise.ridged(x: number, y: number, seed: number, octaves: number, lacunarity: number, gain: number): number
	local sum = 0
	local amp = 1
	local freq = 1
	local norm = 0
	local px, py = x, y
	for octave = 0, octaves - 1 do
		local n = Noise.value2(px * freq, py * freq, (seed + octave * 104729) % 4294967296)
		local r = 1 - math.abs(2 * n - 1)
		sum += amp * r * r
		norm += amp
		amp *= gain
		freq *= lacunarity
		px, py = px * ROT_COS - py * ROT_SIN + 17.31, px * ROT_SIN + py * ROT_COS + 9.73
	end
	return sum / norm
end

return table.freeze(Noise)
