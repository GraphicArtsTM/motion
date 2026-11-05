--!strict
--[[
	ServerSettings — настройки частного сервера (GDD §5.4, этап 8г). Чистый модуль: значения по умолчанию, разбор
	того, что прислал клиент (только значения из списков Config.PrivateServer), правила режима с настройками.
	Кто владелец — решает сервер (MatchService), не этот модуль.
]]

local Config = require("./Config")
local Modes = require("./Modes")
local Types = require("./Types")

export type Settings = {
	map: string?, -- nil — голосование за карту
	mode: Types.ModeId?, -- nil — голосование за режим
	nations: number, -- держав в матче (игроки + боты)
	botLevel: Types.BotLevel?, -- nil — смесь (Bots.LevelMix)
	speed: number, -- множитель поверх скорости режима
	startMoney: number,
	fog: boolean, -- туман на карте (обзор как в 7а, границы видны)
	diplomacy: boolean, -- false — только война и мир
}

local ServerSettings = {}

-- Наибольшее число держав на карте (RealMaps.<карта>.MaxPlayers).
function ServerSettings.maxNations(mapId: string): number
	local p = (Config.RealMaps :: any)[mapId]
	return if p ~= nil then p.MaxPlayers else Config.Match.MaxPlayers
end

function ServerSettings.defaults(mapId: string): Settings
	local p = (Config.RealMaps :: any)[mapId]
	local cfg = Config.PrivateServer
	return {
		map = nil,
		mode = nil,
		nations = if p ~= nil then p.Nations else Config.Match.TargetNations,
		botLevel = nil,
		speed = cfg.Speeds[1],
		startMoney = cfg.StartMoney[1],
		fog = false,
		diplomacy = true,
	}
end

-- Разбор настроек от клиента: каждое поле — только из своего списка. currentMap — для предела числа держав,
-- если карта не выбрана.
function ServerSettings.parse(payload: any, currentMap: string): (Settings?, string?)
	if type(payload) ~= "table" then
		return nil, "bad shape"
	end
	local cfg = Config.PrivateServer
	local map = payload.map
	if map ~= nil and (type(map) ~= "string" or table.find(Config.MapVote.Pool, map) == nil) then
		return nil, "bad map"
	end
	local mode = payload.mode
	if mode ~= nil and (not Modes.isMode(mode) or mode == "Duel") then
		return nil, "bad mode"
	end
	local nations = payload.nations
	local maxNations = ServerSettings.maxNations(map or currentMap)
	if
		type(nations) ~= "number"
		or nations ~= math.floor(nations)
		or nations < cfg.MinNations
		or nations > maxNations
	then
		return nil, "bad nations"
	end
	local level = payload.botLevel
	if level ~= nil and table.find(Types.BotLevels, level) == nil then
		return nil, "bad level"
	end
	if table.find(cfg.Speeds, payload.speed) == nil then
		return nil, "bad speed"
	end
	if table.find(cfg.StartMoney, payload.startMoney) == nil then
		return nil, "bad money"
	end
	if type(payload.fog) ~= "boolean" or type(payload.diplomacy) ~= "boolean" then
		return nil, "bad flags"
	end
	return {
		map = map,
		mode = mode,
		nations = nations,
		botLevel = level,
		speed = payload.speed,
		startMoney = payload.startMoney,
		fog = payload.fog,
		diplomacy = payload.diplomacy,
	},
		nil
end

-- Правила режима с настройками сервера: скорость поверх режима, туман на карте (границы видны), дипломатия.
function ServerSettings.applyRules(rules: Modes.Rules, s: Settings): Modes.Rules
	local r = table.clone(rules)
	r.speed *= s.speed
	if s.fog then
		r.fog = true
	end
	r.diplomacy = s.diplomacy
	return table.freeze(r)
end

return table.freeze(ServerSettings)
