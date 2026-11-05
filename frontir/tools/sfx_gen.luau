--!strict
--[[
	Генерация звуков и музыки (этап 10б): lune run tools/sfx_gen [имя]
	Пишет assets/audio/sfx/<Имя>.wav (Config.Sounds) и assets/audio/music/<Имя>.wav (Config.Music) —
	их загружают в Roblox (Creator Hub → Audio) и вписывают id в Config. Имя — только этот звук или мелодию.
	Звуки описаны в tools/lib/SoundBank.luau, синтезатор — tools/lib/Synth.luau.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local SoundBank = require("./lib/SoundBank")
local Synth = require("./lib/Synth")

local only = process.args[1]
local dirs = { "assets", "assets/audio", "assets/audio/sfx", "assets/audio/music" }
for _, d in dirs do
	if not fs.isDir(d) then
		fs.writeDir(d)
	end
end

local names: { string } = {}
for name in SoundBank.Sounds do
	table.insert(names, name)
end
table.sort(names)
local total = 0
for _, name in names do
	if only == nil or only == name then
		local samples = Synth.finish(SoundBank.Sounds[name](), 0.85)
		local file = Synth.wav(samples, Synth.Rate)
		fs.writeFile("assets/audio/sfx/" .. name .. ".wav", buffer.tostring(file))
		total += buffer.len(file)
		print(string.format("  sfx  %-10s %5.2f с  %6.1f КБ", name, #samples / Synth.Rate, buffer.len(file) / 1024))
	end
end
local songs: { string } = {}
for name in SoundBank.Songs do
	table.insert(songs, name)
end
table.sort(songs)
for _, name in songs do
	if only == nil or only == name then
		local samples = SoundBank.song(SoundBank.Songs[name])
		local file = Synth.wav(samples, SoundBank.MusicRate)
		fs.writeFile("assets/audio/music/" .. name .. ".wav", buffer.tostring(file))
		total += buffer.len(file)
		print(
			string.format(
				"  music %-9s %5.1f с  %6.1f КБ",
				name,
				#samples / SoundBank.MusicRate,
				buffer.len(file) / 1024
			)
		)
	end
end
print(string.format("Готово: %.1f МБ в assets/audio/", total / 1048576))
