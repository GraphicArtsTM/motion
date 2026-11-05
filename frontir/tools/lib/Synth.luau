--!strict
--[[
	Synth — простой 8-bit синтезатор для звуков и музыки (этап 10б). Без Roblox API, без зависимостей.
	Сэмплы — числа -1..1 в таблице; WAV — 16 бит, моно. Всё детерминировано (свой генератор шума).

	- tone(...) — одна нота: форма волны, частота (со скольжением), огибающая ADSR, вибрато.
	- mix(dst, src, at) — сложить src в dst с позиции at (в сэмплах).
	- wav(samples, rate) — buffer с файлом WAV.
]]

local Synth = {}

export type Wave = "square" | "square25" | "square12" | "triangle" | "saw" | "sine" | "noise"

export type Tone = {
	wave: Wave,
	freq: number, -- Гц в начале
	freqEnd: number?, -- Гц в конце (скольжение)
	dur: number, -- секунд
	vol: number?, -- 0..1
	attack: number?,
	decay: number?,
	sustain: number?, -- уровень 0..1
	release: number?,
	vibrato: number?, -- глубина (доля частоты)
	vibratoHz: number?,
}

Synth.Rate = 22050

-- Шум: свой линейный конгруэнтный генератор (детерминированно в любом Lua).
local noiseState = 12345
local function noise(): number
	noiseState = (noiseState * 1103515245 + 12345) % 2147483648
	return noiseState / 1073741824 - 1
end

function Synth.seed(s: number)
	noiseState = s % 2147483648
end

local function osc(wave: Wave, phase: number): number
	local p = phase % 1
	if wave == "square" then
		return if p < 0.5 then 1 else -1
	elseif wave == "square25" then
		return if p < 0.25 then 1 else -1
	elseif wave == "square12" then
		return if p < 0.125 then 1 else -1
	elseif wave == "triangle" then
		return if p < 0.5 then 4 * p - 1 else 3 - 4 * p
	elseif wave == "saw" then
		return 2 * p - 1
	elseif wave == "sine" then
		return math.sin(2 * math.pi * p)
	end
	return noise()
end

-- Огибающая ADSR в момент t из dur.
local function envelope(t: number, dur: number, a: number, d: number, s: number, r: number): number
	if t < a then
		return t / a
	end
	if t < a + d then
		return 1 - (1 - s) * (t - a) / d
	end
	local relStart = math.max(a + d, dur - r)
	if t < relStart then
		return s
	end
	if r <= 0 then
		return s
	end
	return s * math.max(0, 1 - (t - relStart) / r)
end

function Synth.tone(spec: Tone, rate: number?): { number }
	local sr = rate or Synth.Rate
	local n = math.max(1, math.floor(spec.dur * sr))
	local out = table.create(n, 0)
	local a, d = spec.attack or 0.005, spec.decay or 0.05
	local s, r = spec.sustain or 0.7, spec.release or 0.05
	local vol = spec.vol or 0.5
	local f0, f1 = spec.freq, spec.freqEnd or spec.freq
	local vib, vibHz = spec.vibrato or 0, spec.vibratoHz or 6
	local phase = 0
	-- Шум «по-8-битному»: новое значение раз в период частоты (выше частота — светлее шум).
	local held, heldPhase = 0, -1
	for i = 1, n do
		local t = (i - 1) / sr
		local k = t / spec.dur
		local f = f0 * (f1 / f0) ^ k
		if vib > 0 then
			f *= 1 + vib * math.sin(2 * math.pi * vibHz * t)
		end
		phase += f / sr
		local v: number
		if spec.wave == "noise" then
			local step = math.floor(phase)
			if step ~= heldPhase then
				heldPhase = step
				held = noise()
			end
			v = held
		else
			v = osc(spec.wave, phase)
		end
		out[i] = v * vol * envelope(t, spec.dur, a, d, s, r)
	end
	return out
end

function Synth.silence(seconds: number, rate: number?): { number }
	return table.create(math.max(0, math.floor(seconds * (rate or Synth.Rate))), 0)
end

-- Сложить src в dst начиная с сэмпла at (0 — с начала); dst растёт при необходимости.
function Synth.mix(dst: { number }, src: { number }, at: number, gain: number?)
	local g = gain or 1
	for i = 1, #src do
		local j = at + i
		dst[j] = (dst[j] or 0) + src[i] * g
	end
	for j = 1, at do
		if dst[j] == nil then
			dst[j] = 0
		end
	end
end

-- Нота MIDI → Гц (69 = ля 440).
function Synth.midi(note: number): number
	return 440 * 2 ^ ((note - 69) / 12)
end

-- Ограничить пики мягко (tanh-подобно) и нормировать до peak.
function Synth.finish(samples: { number }, peak: number?): { number }
	local p = peak or 0.9
	local maxAbs = 0
	for i, v in samples do
		local c = v / (1 + math.abs(v) * 0.3) -- мягкое ограничение
		samples[i] = c
		maxAbs = math.max(maxAbs, math.abs(c))
	end
	if maxAbs > 0 then
		local k = p / maxAbs
		for i, v in samples do
			samples[i] = v * k
		end
	end
	return samples
end

-- Файл WAV: PCM 16 бит, моно.
function Synth.wav(samples: { number }, rate: number?): buffer
	local sr = rate or Synth.Rate
	local n = #samples
	local dataSize = n * 2
	local b = buffer.create(44 + dataSize)
	buffer.writestring(b, 0, "RIFF")
	buffer.writeu32(b, 4, 36 + dataSize)
	buffer.writestring(b, 8, "WAVE")
	buffer.writestring(b, 12, "fmt ")
	buffer.writeu32(b, 16, 16)
	buffer.writeu16(b, 20, 1) -- PCM
	buffer.writeu16(b, 22, 1) -- моно
	buffer.writeu32(b, 24, sr)
	buffer.writeu32(b, 28, sr * 2)
	buffer.writeu16(b, 32, 2)
	buffer.writeu16(b, 34, 16)
	buffer.writestring(b, 36, "data")
	buffer.writeu32(b, 40, dataSize)
	for i = 1, n do
		local v = math.clamp(samples[i], -1, 1)
		buffer.writei16(b, 44 + (i - 1) * 2, math.round(v * 32767))
	end
	return b
end

return table.freeze(Synth)
