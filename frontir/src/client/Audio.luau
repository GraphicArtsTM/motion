--!strict
--[[
	Audio — звуки и музыка игры (GDD §13, этап 10б). Играет только у этого игрока.

	Откуда берётся звук name (по порядку):
	1. объект Sound с именем name в SoundService/FrontirAudio (положить в Studio, например из Creator Store) —
	   его Volume — базовая громкость;
	2. id из Config.Sounds[name] / Config.Music[name] («rbxassetid://…», загруженный файл из assets/audio);
	3. ни того ни другого — звук молчит, в Output один раз пишется, какого звука нет.
	Итоговая громкость = базовая × Config (volume) × громкость игрока (sfx / music).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

type Entry = { id: string, volume: number }

local Audio = {}

local sfxVolume = Config.Audio.DefaultSfx
local musicVolume = Config.Audio.DefaultMusic
local announced: { [string]: boolean } = {}
local sounds: { [string]: Sound } = {}
local tracks: { [string]: Sound } = {}
local current: string? = nil

-- Звук из папки SoundService/FrontirAudio (nil — нет).
local function fromFolder(name: string): Sound?
	local folder = SoundService:FindFirstChild(Config.Audio.Folder)
	local found = if folder ~= nil then folder:FindFirstChild(name) else nil
	return if found ~= nil and found:IsA("Sound") then found else nil
end

local function warnOnce(name: string)
	if not announced[name] then
		announced[name] = true
		print(
			string.format(
				"[Frontir] звука «%s» нет: впишите id в Config (Sounds / Music) или положите Sound «%s» в SoundService/%s",
				name,
				name,
				Config.Audio.Folder
			)
		)
	end
end

-- Объект Sound для имени (свой экземпляр, создаётся один раз); nil — звука нет.
local function make(name: string, entry: Entry?, cache: { [string]: Sound }, looped: boolean): Sound?
	local cached: Sound? = cache[name]
	if cached then
		return cached
	end
	local source = fromFolder(name)
	local sound: Sound
	if source ~= nil then
		sound = source:Clone()
		sound:SetAttribute("BaseVolume", source.Volume)
	elseif entry ~= nil and entry.id ~= "" then
		sound = Instance.new("Sound")
		sound.SoundId = entry.id
		sound:SetAttribute("BaseVolume", 1)
	else
		warnOnce(name)
		return nil
	end
	sound.Name = "Frontir_" .. name
	sound.Looped = looped
	sound.Parent = SoundService
	cache[name] = sound
	return sound
end

local function baseOf(sound: Sound): number
	local v = sound:GetAttribute("BaseVolume")
	return if type(v) == "number" then v else 1
end

-- Сыграть звук (эффект).
function Audio.play(name: string)
	local entry = (Config.Sounds :: any)[name] :: Entry?
	local sound = make(name, entry, sounds, false)
	if sound == nil or sfxVolume <= 0 then
		return
	end
	sound.Volume = baseOf(sound) * (if entry ~= nil then entry.volume else 1) * sfxVolume
	SoundService:PlayLocalSound(sound)
end

local function trackVolume(name: string, sound: Sound): number
	local entry = (Config.Music :: any)[name] :: Entry?
	return baseOf(sound) * (if entry ~= nil then entry.volume else 1) * musicVolume
end

-- Сменить мелодию (плавно); то же имя — ничего.
function Audio.music(name: string)
	if current == name then
		return
	end
	local fade = TweenInfo.new(Config.Audio.FadeSec)
	local old: Sound? = if current ~= nil then tracks[current] else nil
	if old then
		local tween = TweenService:Create(old, fade, { Volume = 0 })
		tween.Completed:Once(function()
			if current ~= nil and tracks[current] ~= old then
				old:Stop()
			end
		end)
		tween:Play()
	end
	current = name
	local sound = make(name, (Config.Music :: any)[name], tracks, true)
	if sound == nil then
		return
	end
	sound.Volume = 0
	if not sound.IsPlaying then
		sound:Play()
	end
	TweenService:Create(sound, fade, { Volume = trackVolume(name, sound) }):Play()
end

function Audio.currentMusic(): string?
	return current
end

-- Громкости игрока (0..1): эффекты и музыка.
function Audio.setVolumes(sfx: number, music: number)
	sfxVolume = math.clamp(sfx, 0, 1)
	musicVolume = math.clamp(music, 0, 1)
	if current ~= nil then
		local sound: Sound? = tracks[current]
		if sound then
			sound.Volume = trackVolume(current, sound)
		end
	end
end

function Audio.volumes(): (number, number)
	return sfxVolume, musicVolume
end

return table.freeze(Audio)
