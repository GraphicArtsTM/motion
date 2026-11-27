--!strict
--[[
	Places — хаб и матч в разных местах одной игры (GDD §15л ч.3), чистые правила без Roblox API:
	- role: роль сервера по id места (Config.Places), Studio и частному серверу;
	- entry: проверка записи о сервере матча из MemoryStore (что угодно → Entry или nil);
	- action: что можно сделать с сервером из хаба — войти, смотреть, полон;
	- sorted: порядок строк «Матчи» в меню хаба; pick: куда «В БОЙ» (быстрый вход).
]]

local Config = require("./Config")

export type Role = "hub" | "match" | "combined"
export type Action = "join" | "watch" | "full"

-- Сервер матча, как он пишет о себе (MemoryStore) и как хаб шлёт его клиентам.
export type Entry = {
	id: string, -- JobId
	psid: string, -- PrivateServerId резервного сервера ("" — открытый сервер)
	map: string,
	mode: string,
	phase: string, -- Waiting / Lobby / Pick / Play / Over
	players: number,
	max: number,
	left: number, -- секунд до конца фазы (Lobby, Pick, Over) или секунд игры (Play)
	at: number, -- когда записано (os.time)
	users: { number }?, -- §15ъ: UserId игроков сервера (хаб находит, где друг)
}

local Places = {}

local PHASES = { Waiting = true, Lobby = true, Pick = true, Play = true, Over = true }
-- Быстрый вход: сначала лобби, потом выбор старта, потом итоги (следующий матч скоро); в идущую игру — нет.
local TIER: { [string]: number } = { Waiting = 1, Lobby = 1, Pick = 2, Over = 3 }

-- Роль сервера. devRole — Config.Dev.Role (только в Studio); privateOwner — PrivateServerOwnerId (0 — не частный).
-- reserved — резервный сервер (PrivateServerId есть, владельца нет: его поднял хаб). Игра из одного места
-- (Config.Places.Match = 0): обычные серверы места хаба — хаб, резервные — серверы матчей.
function Places.role(
	placeId: number,
	isStudio: boolean,
	privateOwner: number,
	devRole: string,
	reserved: boolean?
): Role
	if isStudio then
		if devRole == "hub" or devRole == "match" then
			return devRole :: Role
		end
		return "combined"
	end
	-- Частный сервер владельца — как раньше: меню поверх своего матча (настройки, свои правила).
	if privateOwner ~= 0 then
		return "combined"
	end
	if placeId == Config.Places.Hub and placeId ~= 0 then
		return if Config.Places.Match == 0 and reserved == true then "match" else "hub"
	elseif placeId == Config.Places.Match and placeId ~= 0 then
		return "match"
	end
	return "combined"
end

-- Куда ехать в матч: отдельное место матча или (одно место) резервный сервер места хаба.
function Places.matchPlace(): number
	return if Config.Places.Match ~= 0 then Config.Places.Match else Config.Places.Hub
end

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v >= 0 and v < 2 ^ 40 and math.floor(v) == v
end

-- Запись о сервере: что угодно (данные из MemoryStore) → Entry; старую (at раньше now − ExpireSec) — nil.
function Places.entry(raw: any, now: number): Entry?
	if type(raw) ~= "table" then
		return nil
	end
	local r = raw :: { [string]: any }
	if type(r.id) ~= "string" or #r.id == 0 or #r.id > 64 then
		return nil
	end
	if type(r.map) ~= "string" or type(r.mode) ~= "string" or type(r.phase) ~= "string" then
		return nil
	end
	if not PHASES[r.phase] or #r.map > 32 or #r.mode > 32 then
		return nil
	end
	if not (isInt(r.players) and isInt(r.max) and isInt(r.left) and isInt(r.at)) or r.max < 1 then
		return nil
	end
	if now - r.at > Config.Places.ExpireSec then
		return nil
	end
	local psid = if type(r.psid) == "string" and #r.psid <= 64 then r.psid else ""
	local users: { number }? = nil
	if type(r.users) == "table" then
		local list: { number } = {}
		for k, u in r.users :: { any } do
			if k > Config.Places.MaxUsersInEntry then
				break
			end
			if isInt(u) then
				table.insert(list, u)
			end
		end
		users = list
	end
	return {
		id = r.id,
		psid = psid,
		map = r.map,
		mode = r.mode,
		phase = r.phase,
		players = r.players,
		max = r.max,
		left = r.left,
		at = r.at,
		users = users,
	}
end

-- §15ъ: сервер матча, на котором сейчас игрок userId (вход «за другом»); nil — нет в списке.
function Places.serverOf(entries: { Entry }, userId: number): Entry?
	for _, e in entries do
		if e.users ~= nil and table.find(e.users, userId) ~= nil then
			return e
		end
	end
	return nil
end

-- §15ъ: данные приглашения (LaunchData — JSON, который уже разобрал вызывающий) → куда вести: сервер (psid
-- резервного сервера) или код своего матча. Что угодно другое — nil.
function Places.invite(raw: any): { psid: string?, code: string?, party: number? }?
	if type(raw) ~= "table" then
		return nil
	end
	local psid = if type(raw.psid) == "string" and #raw.psid > 0 and #raw.psid <= 64 then raw.psid else nil
	local code = Places.normalizeCode(raw.code)
	-- §15ь Л3: зовут в отряд (UserId лидера) — в хабе друг сразу в его отряде.
	local party = if type(raw.party) == "number"
			and raw.party >= 1
			and raw.party < 2 ^ 53
			and raw.party % 1 == 0
		then raw.party
		else nil
	if psid == nil and code == nil and party == nil then
		return nil
	end
	return { psid = psid, code = code, party = party }
end

function Places.action(e: Entry): Action
	if e.players >= e.max then
		return "full"
	end
	return if e.phase == "Play" then "watch" else "join"
end

-- Порядок строк «Матчи»: куда можно войти (лобби → выбор старта → итоги), потом «смотреть», полные — в конце;
-- внутри — больше игроков выше, при равенстве — по id (одинаково у всех).
function Places.sorted(list: { Entry }): { Entry }
	local out = table.clone(list)
	local function key(e: Entry): number
		local a = Places.action(e)
		if a == "full" then
			return 9
		elseif a == "watch" then
			return 5
		end
		return TIER[e.phase] or 4
	end
	table.sort(out, function(a: Entry, b: Entry): boolean
		local ka, kb = key(a), key(b)
		if ka ~= kb then
			return ka < kb
		end
		if a.players ~= b.players then
			return a.players > b.players
		end
		return a.id < b.id
	end)
	return out
end

-- Быстрый вход «В БОЙ»: лучший сервер, куда можно войти, или nil (нужен новый).
function Places.pick(list: { Entry }): Entry?
	for _, e in Places.sorted(list) do
		if Places.action(e) == "join" and TIER[e.phase] ~= nil then
			return e
		end
	end
	return nil
end

-- §15л ч.4 Свой матч по коду: запись «код → сервер» (MemoryStore, только сервер).
export type PrivateRecord = { access: string, psid: string, owner: number }

-- Новый код из CodeAlphabet; roll(n) — случайное целое 1..n.
function Places.newCode(roll: (n: number) -> number): string
	local abc = Config.Places.CodeAlphabet
	local out = table.create(Config.Places.CodeLength)
	for k = 1, Config.Places.CodeLength do
		local i = roll(#abc)
		out[k] = string.sub(abc, i, i)
	end
	return table.concat(out)
end

-- Что ввёл игрок → код или nil: заглавные, без пробелов и дефисов, длина и буквы — как у newCode.
function Places.normalizeCode(raw: any): string?
	if type(raw) ~= "string" or #raw > 32 then
		return nil
	end
	local code = string.upper((string.gsub(raw, "[%s%-]", "")))
	if #code ~= Config.Places.CodeLength then
		return nil
	end
	local abc = Config.Places.CodeAlphabet
	for k = 1, #code do
		if string.find(abc, string.sub(code, k, k), 1, true) == nil then
			return nil
		end
	end
	return code
end

-- Запись кода из MemoryStore → PrivateRecord или nil.
function Places.privateRecord(raw: any): PrivateRecord?
	if type(raw) ~= "table" then
		return nil
	end
	local r = raw :: { [string]: any }
	if type(r.access) ~= "string" or #r.access == 0 or type(r.psid) ~= "string" or #r.psid == 0 then
		return nil
	end
	if not isInt(r.owner) or r.owner <= 0 then
		return nil
	end
	return { access = r.access, psid = r.psid, owner = r.owner }
end

return table.freeze(Places)
