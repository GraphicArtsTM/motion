--!strict
--[[
	Превью звуков (этап 10б): lune run tools/sfx_preview docs/previews/stage-10b.png
	Формы волн всех звуков (Config.Sounds) и начало каждой мелодии (Config.Music) — по полосе на звук,
	цвета палитры. Звук слушать — файлы assets/audio (lune run tools/sfx_gen).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local AudioCues = require("../src/shared/AudioCues")
local Palette = require("../src/shared/Palette")
local Png = require("./lib/Png")
local SoundBank = require("./lib/SoundBank")
local Synth = require("./lib/Synth")

local out = process.args[1] or "build/sfx.png"
local W, ROW = 800, 40
local tracks: { { name: string, samples: { number }, color: string } } = {}
for _, name in AudioCues.SoundNames do
	table.insert(tracks, { name = name, samples = Synth.finish(SoundBank.Sounds[name](), 0.85), color = "Lime" })
end
for _, name in AudioCues.MusicNames do
	local s = SoundBank.song(SoundBank.Songs[name])
	table.insert(tracks, { name = name, samples = s, color = "Gold" })
end
local H = #tracks * ROW
local px = buffer.create(W * H * 3)
local bg = Palette.rgb("Night")
local mid = Palette.rgb("Steel")
for i = 0, W * H - 1 do
	buffer.writeu8(px, i * 3, bg.r)
	buffer.writeu8(px, i * 3 + 1, bg.g)
	buffer.writeu8(px, i * 3 + 2, bg.b)
end
local function put(x: number, y: number, c: { r: number, g: number, b: number })
	if x >= 0 and y >= 0 and x < W and y < H then
		local i = (y * W + x) * 3
		buffer.writeu8(px, i, c.r)
		buffer.writeu8(px, i + 1, c.g)
		buffer.writeu8(px, i + 2, c.b)
	end
end
for k, t in tracks do
	local y0 = (k - 1) * ROW
	local c = Palette.rgb(t.color)
	for x = 0, W - 1 do
		put(x, y0 + ROW - 1, mid)
	end
	-- Звуки — целиком, мелодии — первые 4 секунды.
	local n = if t.color == "Gold" then math.min(#t.samples, 4 * SoundBank.MusicRate) else #t.samples
	for x = 0, W - 1 do
		local a = math.floor(x / W * n) + 1
		local b = math.max(a, math.floor((x + 1) / W * n))
		local lo, hi = 0, 0
		for i = a, b do
			local v = t.samples[i] or 0
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
		local cy = y0 + ROW / 2
		for y = math.floor(cy - hi * (ROW / 2 - 3)), math.floor(cy - lo * (ROW / 2 - 3)) do
			put(x, y, c)
		end
	end
	print(string.format("%2d  %s", k, t.name))
end
fs.writeFile(out, Png.encodeRgb(W, H, px))
print("→ " .. out)
