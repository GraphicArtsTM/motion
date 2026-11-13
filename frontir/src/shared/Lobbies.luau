--!strict
--[[
	Lobbies — матчи как серверы (GDD §15ц Ц2), чистые правила без Roblox API:
	- slots(now): постоянные пары «карта · режим» (Config.Lobbies.Slots, "Weekly" — режим недели);
	- board(entries, slots, rows): строки списка матчей в главном меню — сначала плейлист (сервер пары, куда можно
	  войти, или «Новое лобби»), ниже идущие и полные матчи;
	- request(raw): что прислал клиент или что пришло в данных перехода → карта, режим, «одному», сила ботов;
	- quick(entries, slots): «В БОЙ» — лучший открытый матч или новое лобби первой пары.
]]

local Config = require("./Config")
local Modes = require("./Modes")
local Places = require("./Places")
local Types = require("./Types")

export type Slot = { map: string, mode: Types.ModeId }

-- action: "join" — войти, "teams" — войти в команду, "watch" — смотреть, "full" — полон,
-- "new" — нового сервера пары ещё нет (войти = поднять его), "busy" — сервер один и на нём чужой матч.
export type Row = {
	id: string, -- JobId сервера ("" — сервера ещё нет)
	slot: number, -- номер пары плейлиста (0 — матч не из плейлиста)
	map: string,
	mode: string,
	phase: string, -- фаза сервера или "New"
	players: number,
	max: number,
	left: number,
	action: string,
}

export type Request = {
	map: string,
	mode: Types.ModeId,
	solo: boolean, -- «Играть одному»: свой сервер только для игрока
	level: Types.BotLevel?, -- сила всех ботов (только «одному»)
}

local Lobbies = {}

function Lobbies.slots(unixTime: number): { Slot }
	local out: { Slot } = {}
	for _, s in Config.Lobbies.Slots do
		local mode: Types.ModeId = if s.mode == "Weekly" then Modes.weekly(unixTime) else s.mode :: Types.ModeId
		table.insert(out, { map = s.map, mode = mode })
	end
	return out
end

function Lobbies.slotOf(slots: { Slot }, map: string, mode: string): number
	for k, s in slots do
		if s.map == map and s.mode == mode then
			return k
		end
	end
	return 0
end

local function rowOf(e: Places.Entry, slot: number): Row
	local action: string = Places.action(e)
	if action == "join" and e.mode == "Teams" then
		action = "teams"
	end
	return {
		id = e.id,
		slot = slot,
		map = e.map,
		mode = e.mode,
		phase = e.phase,
		players = e.players,
		max = e.max,
		left = e.left,
		action = action,
	}
end

function Lobbies.board(entries: { Places.Entry }, slots: { Slot }, rows: number): { Row }
	local sorted = Places.sorted(entries)
	local used: { [string]: boolean } = {}
	local out: { Row } = {}
	for k, s in slots do
		local found: Places.Entry? = nil
		for _, e in sorted do
			if not used[e.id] and e.map == s.map and e.mode == s.mode and Places.action(e) == "join" then
				found = e
				break
			end
		end
		if found ~= nil then
			used[found.id] = true
			table.insert(out, rowOf(found, k))
		else
			local p = (Config.RealMaps :: any)[s.map]
			local max: number = if p ~= nil then p.Nations else Config.Match.TargetNations
			local row: Row = {
				id = "",
				slot = k,
				map = s.map,
				mode = s.mode :: string,
				phase = "New",
				players = 0,
				max = max,
				left = 0,
				action = if s.mode == "Teams" then "teams" else "new",
			}
			table.insert(out, row)
		end
	end
	for _, e in sorted do
		if #out >= rows then
			break
		end
		if not used[e.id] then
			used[e.id] = true
			table.insert(out, rowOf(e, Lobbies.slotOf(slots, e.map, e.mode)))
		end
	end
	return out
end

-- Карта и режим, которые можно выбрать: карта из пула (и есть её параметры), режим — из Config.Lobbies.Modes.
function Lobbies.request(raw: any): Request?
	if type(raw) ~= "table" then
		return nil
	end
	local r = raw :: { [string]: any }
	local map, mode = r.map, r.mode
	if type(map) ~= "string" or table.find(Config.MapVote.Pool, map) == nil then
		return nil
	end
	if (Config.RealMaps :: any)[map] == nil then
		return nil
	end
	if type(mode) ~= "string" or table.find(Config.Lobbies.Modes, mode) == nil or not Modes.isMode(mode) then
		return nil
	end
	local solo = r.solo == true
	local level: Types.BotLevel? = nil
	if solo and r.level ~= nil then
		if table.find(Types.BotLevels, r.level) == nil then
			return nil
		end
		level = r.level :: Types.BotLevel
	end
	return { map = map, mode = mode :: Types.ModeId, solo = solo, level = level }
end

-- «В БОЙ»: открытый матч (Places.pick) или новое лобби первой пары плейлиста.
function Lobbies.quick(entries: { Places.Entry }, slots: { Slot }): (Places.Entry?, Request?)
	local e = Places.pick(entries)
	if e ~= nil then
		return e, nil
	end
	local s = slots[1]
	if s == nil then
		return nil, nil
	end
	return nil, { map = s.map, mode = s.mode, solo = false, level = nil }
end

return table.freeze(Lobbies)
