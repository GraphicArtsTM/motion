--!strict
--[[
	SoundBank — как звучит каждый звук и каждая мелодия игры (этап 10б, GDD §13). Звуки — короткие 8-bit эффекты
	из нот Synth; мелодии — чиптюн-петли: бас, арпеджио, мелодия и ударные по последовательности аккордов.
	Имена совпадают с ключами Config.Sounds и Config.Music (тест Audio.spec это проверяет).
]]

local Synth = require("./Synth")

type Samples = { number }

local SoundBank = {}

local R = Synth.Rate
local M = Synth.midi

-- Ноты подряд: { частота, длительность, форма, громкость? }.
local function seq(notes: { { any } }, gap: number?): Samples
	local out: Samples = {}
	local at = 0
	for _, n in notes do
		local s = Synth.tone({
			wave = n[3],
			freq = n[1],
			freqEnd = n[5],
			dur = n[2],
			vol = n[4] or 0.5,
			decay = 0.04,
			sustain = 0.6,
			release = math.min(0.05, n[2] * 0.4),
		})
		Synth.mix(out, s, at)
		at += math.floor((n[2] + (gap or 0)) * R)
	end
	return out
end

local function layer(parts: { Samples }): Samples
	local out: Samples = {}
	for _, p in parts do
		Synth.mix(out, p, 0)
	end
	return out
end

local function at(samples: Samples, seconds: number): (Samples, number)
	return samples, math.floor(seconds * R)
end

SoundBank.Sounds = table.freeze({
	Click = function(): Samples
		return Synth.tone({
			wave = "square25",
			freq = 1200,
			freqEnd = 900,
			dur = 0.045,
			vol = 0.35,
			decay = 0.03,
			sustain = 0.2,
			release = 0.01,
		})
	end,
	Error = function(): Samples
		return seq({ { 220, 0.08, "square", 0.4 }, { 165, 0.12, "square", 0.4 } }, 0.02)
	end,
	Capture = function(): Samples
		return Synth.tone({
			wave = "triangle",
			freq = 660,
			freqEnd = 880,
			dur = 0.07,
			vol = 0.35,
			decay = 0.03,
			sustain = 0.5,
			release = 0.02,
		})
	end,
	Province = function(): Samples
		return seq({
			{ M(72), 0.07, "square25", 0.4 },
			{ M(76), 0.07, "square25", 0.4 },
			{ M(79), 0.16, "square25", 0.45 },
		})
	end,
	Battle = function(): Samples
		local out: Samples = {}
		for k = 0, 2 do
			local shot = Synth.tone({
				wave = "noise",
				freq = 2200,
				freqEnd = 600,
				dur = 0.06,
				vol = 0.5,
				decay = 0.05,
				sustain = 0.1,
				release = 0.01,
			})
			Synth.mix(out, at(shot, k * 0.09))
		end
		local thump = Synth.tone({
			wave = "triangle",
			freq = 90,
			freqEnd = 45,
			dur = 0.25,
			vol = 0.6,
			decay = 0.2,
			sustain = 0.2,
			release = 0.05,
		})
		Synth.mix(out, thump, 0)
		return out
	end,
	Explosion = function(): Samples
		return layer({
			Synth.tone({
				wave = "noise",
				freq = 1800,
				freqEnd = 120,
				dur = 0.9,
				vol = 0.8,
				attack = 0.002,
				decay = 0.25,
				sustain = 0.35,
				release = 0.5,
			}),
			Synth.tone({
				wave = "sine",
				freq = 95,
				freqEnd = 28,
				dur = 0.55,
				vol = 0.9,
				attack = 0.002,
				decay = 0.3,
				sustain = 0.3,
				release = 0.2,
			}),
		})
	end,
	Plane = function(): Samples
		return layer({
			Synth.tone({
				wave = "square12",
				freq = 100,
				freqEnd = 150,
				dur = 1.2,
				vol = 0.3,
				attack = 0.25,
				decay = 0.1,
				sustain = 0.8,
				release = 0.45,
				vibrato = 0.06,
				vibratoHz = 18,
			}),
			Synth.tone({
				wave = "noise",
				freq = 900,
				freqEnd = 1400,
				dur = 1.2,
				vol = 0.12,
				attack = 0.3,
				decay = 0.1,
				sustain = 0.8,
				release = 0.5,
			}),
		})
	end,
	Parachute = function(): Samples
		return layer({
			Synth.tone({
				wave = "noise",
				freq = 5000,
				freqEnd = 700,
				dur = 0.7,
				vol = 0.25,
				attack = 0.05,
				decay = 0.2,
				sustain = 0.5,
				release = 0.3,
			}),
			Synth.tone({
				wave = "triangle",
				freq = 880,
				freqEnd = 440,
				dur = 0.7,
				vol = 0.3,
				attack = 0.02,
				decay = 0.2,
				sustain = 0.6,
				release = 0.2,
			}),
		})
	end,
	Siren = function(): Samples
		local out: Samples = {}
		for k = 0, 1 do
			local up = Synth.tone({
				wave = "square",
				freq = 600,
				freqEnd = 950,
				dur = 0.35,
				vol = 0.35,
				attack = 0.02,
				sustain = 0.9,
				release = 0.02,
			})
			local down = Synth.tone({
				wave = "square",
				freq = 950,
				freqEnd = 600,
				dur = 0.35,
				vol = 0.35,
				attack = 0.01,
				sustain = 0.9,
				release = 0.05,
			})
			Synth.mix(out, at(up, k * 0.7))
			Synth.mix(out, at(down, k * 0.7 + 0.35))
		end
		return out
	end,
	Offer = function(): Samples
		return seq({ { M(79), 0.12, "triangle", 0.5 }, { M(84), 0.25, "triangle", 0.5 } }, 0.02)
	end,
	Betrayal = function(): Samples
		return seq({
			{ M(69), 0.12, "square", 0.4 },
			{ M(65), 0.12, "square", 0.4 },
			{ M(60), 0.12, "square", 0.4 },
			{ M(48), 0.45, "square", 0.45, M(46) },
		})
	end,
	Victory = function(): Samples
		local out = seq({
			{ M(72), 0.12, "square25", 0.4 },
			{ M(76), 0.12, "square25", 0.4 },
			{ M(79), 0.12, "square25", 0.4 },
			{ M(84), 0.35, "square25", 0.45 },
		})
		local chordAt = math.floor(0.36 * R)
		for _, note in { 72, 76, 79 } do
			Synth.mix(
				out,
				Synth.tone({
					wave = "triangle",
					freq = M(note),
					dur = 0.9,
					vol = 0.3,
					decay = 0.2,
					sustain = 0.6,
					release = 0.4,
				}),
				chordAt
			)
		end
		return out
	end,
	Defeat = function(): Samples
		return seq({
			{ M(67), 0.2, "triangle", 0.45 },
			{ M(66), 0.2, "triangle", 0.45 },
			{ M(65), 0.2, "triangle", 0.45 },
			{ M(60), 0.7, "triangle", 0.5, M(58) },
		}, 0.03)
	end,
	Notify = function(): Samples
		return seq({ { M(76), 0.08, "triangle", 0.45 }, { M(81), 0.16, "triangle", 0.45 } })
	end,
	Coin = function(): Samples
		return seq({ { M(83), 0.07, "square25", 0.35 }, { M(88), 0.22, "square25", 0.35 } })
	end,
	Hire = function(): Samples
		local out = seq({ { M(67), 0.06, "square25", 0.35 }, { M(72), 0.1, "square25", 0.35 } })
		Synth.mix(
			out,
			Synth.tone({
				wave = "noise",
				freq = 3000,
				dur = 0.05,
				vol = 0.25,
				decay = 0.04,
				sustain = 0.1,
				release = 0.01,
			}),
			0
		)
		return out
	end,
	Build = function(): Samples
		local out: Samples = {}
		for k = 0, 1 do
			Synth.mix(
				out,
				at(
					Synth.tone({
						wave = "noise",
						freq = 3500,
						dur = 0.04,
						vol = 0.45,
						decay = 0.03,
						sustain = 0.1,
						release = 0.01,
					}),
					k * 0.14
				)
			)
			Synth.mix(
				out,
				at(
					Synth.tone({
						wave = "square",
						freq = 196,
						freqEnd = 150,
						dur = 0.08,
						vol = 0.35,
						decay = 0.06,
						sustain = 0.2,
						release = 0.01,
					}),
					k * 0.14
				)
			)
		end
		return out
	end,
} :: { [string]: () -> Samples })

-- Музыка ----------------------------------------------------------------------------------------

export type Song = {
	bpm: number,
	root: number, -- MIDI тоники
	chords: { { number } }, -- { ступень от тоники (полутоны), 0 — мажор / 1 — минор }
	scale: { number }, -- лад для мелодии (полутоны)
	drums: number, -- 0 — тихо (хэт), 1 — бочка и хэт, 2 — всё с малым барабаном
	bassEighths: boolean, -- бас восьмыми (иначе четвертями)
	arpWave: Synth.Wave,
	leadWave: Synth.Wave,
	seed: number,
}

SoundBank.MusicRate = 16000
SoundBank.Bars = 16

SoundBank.Songs = table.freeze({
	-- Лобби: спокойный мажор I–V–vi–IV.
	Lobby = {
		bpm = 92,
		root = 60,
		chords = { { 0, 0 }, { 7, 0 }, { 9, 1 }, { 5, 0 } },
		scale = { 0, 2, 4, 7, 9 },
		drums = 0,
		bassEighths = false,
		arpWave = "triangle",
		leadWave = "square25",
		seed = 11,
	},
	-- Игра: сдержанный минор i–VI–III–VII.
	Calm = {
		bpm = 108,
		root = 57,
		chords = { { 0, 1 }, { 8, 0 }, { 3, 0 }, { 10, 0 } },
		scale = { 0, 3, 5, 7, 10 },
		drums = 1,
		bassEighths = true,
		arpWave = "square25",
		leadWave = "triangle",
		seed = 23,
	},
	-- Финал: быстрый минор i–i–VI–VII, полная ударная.
	Finale = {
		bpm = 144,
		root = 62,
		chords = { { 0, 1 }, { 0, 1 }, { 8, 0 }, { 10, 0 } },
		scale = { 0, 2, 3, 5, 7, 8, 10 },
		drums = 2,
		bassEighths = true,
		arpWave = "square12",
		leadWave = "square",
		seed = 37,
	},
} :: { [string]: Song })

function SoundBank.song(song: Song): Samples
	local rate = SoundBank.MusicRate
	Synth.seed(song.seed)
	local beat = 60 / song.bpm
	local bar = beat * 4
	local total = math.floor(SoundBank.Bars * bar * rate)
	local out: Samples = table.create(total, 0)
	local function put(spec: Synth.Tone, t: number, gain: number?)
		local s = Synth.tone(spec, rate)
		local start = math.floor(t * rate)
		for i = 1, #s do
			local j = start + i
			if j <= total then
				out[j] += s[i] * (gain or 1)
			end
		end
	end
	-- Мелодия: 2 такта фраза A, повтор с вариацией, фраза B, снова A — из лада, шаги ±1–2 ступени.
	local seedState = song.seed
	local function rnd(n: number): number
		seedState = (seedState * 1103515245 + 12345) % 2147483648
		return seedState % n
	end
	local function phrase(): { { number } }
		local notes: { { number } } = {}
		local idx = #song.scale + 1
		local t = 0
		while t < 8 do
			local len = if rnd(3) == 0 then 1 else 0.5
			if rnd(5) == 0 then
				table.insert(notes, { t, -1, len }) -- пауза
			else
				idx = math.clamp(idx + rnd(5) - 2, 1, #song.scale * 2)
				table.insert(notes, { t, idx, len })
			end
			t += len
		end
		return notes
	end
	local A, B = phrase(), phrase()
	local plan = { A, A, B, A, A, B, B, A }
	for barIdx = 0, SoundBank.Bars - 1 do
		local t0 = barIdx * bar
		local chord = song.chords[barIdx % #song.chords + 1]
		local rootNote = song.root + chord[1]
		local third = if chord[2] == 1 then 3 else 4
		local tones = { 0, third, 7 }
		-- Бас.
		local step = if song.bassEighths then beat / 2 else beat
		local k = 0
		while k * step < bar - 1e-6 do
			local note = rootNote - 24 + (if k % 4 == 3 then 7 else 0)
			put({
				wave = "triangle",
				freq = Synth.midi(note),
				dur = step * 0.9,
				vol = 0.55,
				decay = 0.05,
				sustain = 0.7,
				release = 0.03,
			}, t0 + k * step)
			k += 1
		end
		-- Арпеджио шестнадцатыми.
		for j = 0, 15 do
			local note = rootNote + tones[j % 3 + 1] + (if j % 6 >= 3 then 12 else 0)
			put({
				wave = song.arpWave,
				freq = Synth.midi(note),
				dur = beat / 4 * 0.8,
				vol = 0.16,
				decay = 0.03,
				sustain = 0.4,
				release = 0.02,
			}, t0 + j * beat / 4)
		end
		-- Мелодия: фраза на 2 такта (8 долей).
		local ph = plan[(barIdx // 2) % #plan + 1]
		local half = barIdx % 2
		for _, n in ph do
			if n[2] > 0 and n[1] >= half * 4 and n[1] < half * 4 + 4 then
				local deg = n[2]
				local octave = (deg - 1) // #song.scale
				local note = song.root + 12 + song.scale[(deg - 1) % #song.scale + 1] + 12 * octave
				put({
					wave = song.leadWave,
					freq = Synth.midi(note),
					dur = n[3] * beat * 0.9,
					vol = 0.22,
					decay = 0.08,
					sustain = 0.6,
					release = 0.06,
					vibrato = 0.004,
					vibratoHz = 5,
				}, t0 + (n[1] - half * 4) * beat)
			end
		end
		-- Ударные.
		for b = 0, 7 do
			local t = t0 + b * beat / 2
			put({
				wave = "noise",
				freq = 7000,
				dur = 0.03,
				vol = if song.drums == 0 then 0.06 else 0.1,
				decay = 0.02,
				sustain = 0.1,
				release = 0.01,
			}, t)
			if song.drums >= 1 and b % 4 == 0 then
				put({
					wave = "sine",
					freq = 120,
					freqEnd = 40,
					dur = 0.15,
					vol = 0.7,
					attack = 0.001,
					decay = 0.1,
					sustain = 0.2,
					release = 0.04,
				}, t)
			end
			if song.drums >= 2 and b % 4 == 2 then
				put(
					{ wave = "noise", freq = 2500, dur = 0.12, vol = 0.3, decay = 0.08, sustain = 0.15, release = 0.03 },
					t
				)
			end
		end
	end
	return Synth.finish(out, 0.8)
end

return table.freeze(SoundBank)
