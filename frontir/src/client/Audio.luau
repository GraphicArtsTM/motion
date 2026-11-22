--!strict
--[[
	Audio — звуки и музыка игры (GDD §13, этап 10б; правка звука 18.11.2026). Играет только у этого игрока.

	Откуда берётся звук name (по порядку):
	1. объект Sound с именем name в SoundService/FrontirAudio (положить в Studio, например из Creator Store) —
	   его Volume — базовая громкость;
	2. id из Config.Sounds[name] / Config.Music[name] («rbxassetid://…», загруженный файл из assets/audio);
	3. ни того ни другого — звук молчит, в Output один раз пишется, какого звука нет.
	Громкость: звук = базовая × Config (volume); группа (SoundGroup «FrontirSfx» / «FrontirMusic») = громкость игрока
	(sfx / music), у музыки ещё × приглушение на время громкого звука (Config.Audio.Duck).
	Мелодии — петли, смена плавная (одна гаснет, другая растёт); вернулись к мелодии — она идёт с того же места.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCues = require(Shared:WaitForChild("AudioCues"))
local Config = require(Shared:WaitForChild("Config"))

type Entry = { id: string, volume: number }

local Audio = {}

local sfxVolume = Config.Audio.DefaultSfx
local musicVolume = Config.Audio.DefaultMusic
local duckUntil = 0
local announced: { [string]: boolean } = {}
local sounds: { [string]: Sound } = {}
local tracks: { [string]: Sound } = {}
local current: string? = nil
local rng = Random.new()

local function group(name: string): SoundGroup
	local found = SoundService:FindFirstChild(name)
	if found ~= nil and found:IsA("SoundGroup") then
		return found
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Parent = SoundService
	return g
end
local sfxGroup = group("FrontirSfx")
local musicGroup = group("FrontirMusic")
sfxGroup.Volume = sfxVolume
musicGroup.Volume = musicVolume

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
local function make(
	name: string,
	entry: Entry?,
	cache: { [string]: Sound },
	looped: boolean,
	soundGroup: SoundGroup
): Sound?
	local cached: Sound? = cache[name]
	if cached then
		return cached
	end
	local source = fromFolder(name)
	local sound: Sound
	local base = 1
	if source ~= nil then
		sound = source:Clone()
		base = source.Volume
	elseif entry ~= nil and entry.id ~= "" then
		sound = Instance.new("Sound")
		sound.SoundId = entry.id
	else
		warnOnce(name)
		return nil
	end
	sound:SetAttribute("BaseVolume", base * (if entry ~= nil then entry.volume else 1))
	sound.Name = "Frontir_" .. name
	sound.Looped = looped
	sound.SoundGroup = soundGroup
	sound.Parent = SoundService
	cache[name] = sound
	return sound
end

local function baseOf(sound: Sound): number
	local v = sound:GetAttribute("BaseVolume")
	return if type(v) == "number" then v else 1
end

local function musicGroupVolume(): number
	return musicVolume * (if os.clock() < duckUntil then Config.Audio.Duck.Mul else 1)
end

local function applyMusicGroup(sec: number)
	TweenService:Create(musicGroup, TweenInfo.new(sec), { Volume = musicGroupVolume() }):Play()
end

-- Сыграть звук (эффект).
function Audio.play(name: string)
	local sound = make(name, (Config.Sounds :: any)[name] :: Entry?, sounds, false, sfxGroup)
	if sound == nil or sfxVolume <= 0 then
		return
	end
	sound.Volume = baseOf(sound)
	sound.PlaybackSpeed = AudioCues.pitch(name, rng:NextNumber())
	SoundService:PlayLocalSound(sound)
	-- Громкий звук — музыку приглушить и потом вернуть.
	if AudioCues.ducks(name) and musicVolume > 0 then
		local sec = Config.Audio.Duck.Sec
		duckUntil = os.clock() + sec
		applyMusicGroup(0.15)
		task.delay(sec, function()
			if os.clock() >= duckUntil then
				applyMusicGroup(0.8)
			end
		end)
	end
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
				old:Pause() -- вернёмся — продолжит с того же места
			end
		end)
		tween:Play()
	end
	current = name
	local sound = make(name, (Config.Music :: any)[name] :: Entry?, tracks, true, musicGroup)
	if sound == nil then
		return
	end
	if not sound.IsPlaying then
		sound.Volume = 0
		if sound.TimePosition > 0 then
			sound:Resume()
		else
			sound:Play()
		end
	end
	TweenService:Create(sound, fade, { Volume = baseOf(sound) }):Play()
end

function Audio.currentMusic(): string?
	return current
end

-- Громкости игрока (0..1): эффекты и музыка.
function Audio.setVolumes(sfx: number, music: number)
	sfxVolume = math.clamp(sfx, 0, 1)
	musicVolume = math.clamp(music, 0, 1)
	sfxGroup.Volume = sfxVolume
	musicGroup.Volume = musicGroupVolume()
end

function Audio.volumes(): (number, number)
	return sfxVolume, musicVolume
end

return table.freeze(Audio)
