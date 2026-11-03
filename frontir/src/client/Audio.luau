--!strict
--[[
	Audio — звуки игры (GDD §14). Пока заглушка: id ассетов в Config.Sounds пустые (звуки — этап 10),
	play() только один раз пишет в Output, какой звук должен был прозвучать. Когда id появится, звук
	играет локально у этого игрока через SoundService:PlayLocalSound.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Audio = {}

local announced: { [string]: boolean } = {}
local sounds: { [string]: Sound } = {}

function Audio.play(name: string)
	local id = (Config.Sounds :: { [string]: string })[name]
	if id == nil or id == "" then
		if not announced[name] then
			announced[name] = true
			print("[Frontir] звук (заглушка):", name)
		end
		return
	end
	local sound: Sound? = sounds[name]
	if not sound then
		local made = Instance.new("Sound")
		made.Name = name
		made.SoundId = id
		made.Parent = SoundService
		sounds[name] = made
		sound = made
	end
	SoundService:PlayLocalSound(sound :: Sound)
end

return table.freeze(Audio)
