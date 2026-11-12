--!strict
--[[
	EventFeed — лента событий по важности (§15т ч.1). Чистый модуль: уровень события для игрока и сама лента
	(строки, вытеснение, повторы «×N», сроки). Рисует её UI/MatchHud.

	Уровни: critical — по вам (война вам, удар по вам, высадка, предательство…), important — касается вас или
	союзников и большие события мира, background — чужие дела и своя рутина.
	Полная лента: новая строка вытесняет самую старую не важнее себя; если вся лента важнее — новая не показывается.
]]

local Config = require("./Config")

export type Level = "critical" | "important" | "background"

export type Line = {
	text: string,
	level: Level,
	count: number, -- сколько раз пришла та же строка
	born: number,
	untilTime: number,
}

export type Feed = { lines: { Line }, max: number }

local EventFeed = {}

EventFeed.Rank = table.freeze({ background = 1, important = 2, critical = 3 }) :: { [string]: number }

-- По вам (target — мы): всегда критично.
local ON_ME: { [string]: boolean } = {
	warDeclared = true,
	missileLaunched = true,
	nukeHit = true,
	landed = true,
	passageArrived = true, -- §15у: удар через союзника
	betrayal = true,
	breakAnnounced = true,
	ability = true,
	raid = true,
}
-- У нас (nation — мы): критично.
local MINE_CRITICAL: { [string]: boolean } = {
	eliminated = true,
	capitalLost = true,
	doomWarning = true,
	revoltSoon = true,
	revolt = true,
	blockade = true,
}
-- Своя рутина — фон, даже если касается нас.
local ROUTINE: { [string]: boolean } = {
	shipBuilt = true,
	planeBuilt = true,
	researched = true,
	tradeDelivered = true,
	cityFounded = true,
	boost = true,
	flood = true,
	ping = true,
}
-- Большие события мира — важно всем.
local WORLD: { [string]: boolean } = {
	eliminated = true,
	capitalLost = true,
	victory = true,
	doomCollapse = true,
	councilOpened = true,
	resolution = true,
	nukeHit = true,
}

-- Уровень события для игрока me (nil — зритель); friends — союзники, вассалы, сюзерен.
function EventFeed.level(e: { [string]: any }, me: number?, friends: { [number]: boolean }?): Level
	local kind = e.kind
	if type(kind) ~= "string" then
		return "background"
	end
	if me ~= nil then
		if e.target == me and ON_ME[kind] then
			return "critical"
		end
		if kind == "allyAttacked" and e.ally == me then
			return "critical"
		end
		if e.nation == me and MINE_CRITICAL[kind] and (kind ~= "blockade" or e.on == true) then
			return "critical"
		end
	end
	if kind == "missileLaunched" and (e.warhead == "atom" or e.warhead == "hydrogen") then
		return "important" -- ядерный пуск видят все
	end
	if WORLD[kind] then
		return "important"
	end
	-- §15у ч.2: о союзах и доверии между любыми державами узнают все.
	if
		(kind == "offerAccepted" and (e.offer == "alliance" or e.offer == "trust"))
		or kind == "trustRemoved"
		or (kind == "treatyBroken" and e.treaty == "alliance")
	then
		return "important"
	end
	if ROUTINE[kind] then
		return "background"
	end
	if me ~= nil then
		for _, field in { "nation", "target", "by", "ally" } do
			local id = e[field]
			if type(id) == "number" and id ~= 0 and (id == me or (friends ~= nil and friends[id])) then
				return "important"
			end
		end
	end
	return "background"
end

function EventFeed.new(max: number?): Feed
	return { lines = {}, max = max or Config.Render.FeedLines }
end

local function lifeOf(level: Level): number
	local cfg = Config.Feed
	return if level == "critical"
		then cfg.CriticalSec
		elseif level == "important" then cfg.ImportantSec
		else cfg.BackgroundSec
end

-- Новая строка. Возвращает строку, которую показать (новую или прежнюю с «×N»), и вытесненную (её убрать);
-- nil — строка не показана (лента занята более важным).
function EventFeed.push(feed: Feed, text: string, level: Level, now: number): (Line?, Line?)
	for _, line in feed.lines do
		if line.text == text then
			line.count += 1
			line.untilTime = now + lifeOf(level)
			if EventFeed.Rank[level] > EventFeed.Rank[line.level] then
				line.level = level
			end
			return line, nil
		end
	end
	local line: Line = { text = text, level = level, count = 1, born = now, untilTime = now + lifeOf(level) }
	if #feed.lines < feed.max then
		table.insert(feed.lines, line)
		return line, nil
	end
	-- Вытесняем самую старую строку самого низкого уровня, но не важнее новой.
	local rank = EventFeed.Rank[level]
	local victim: number? = nil
	for i, old in feed.lines do
		local r = EventFeed.Rank[old.level]
		if r <= rank then
			local best = if victim ~= nil then feed.lines[victim] else nil
			if
				best == nil
				or r < EventFeed.Rank[best.level]
				or (r == EventFeed.Rank[best.level] and old.born < best.born)
			then
				victim = i
			end
		end
	end
	if victim == nil then
		return nil, nil
	end
	local evicted = table.remove(feed.lines, victim)
	table.insert(feed.lines, line)
	return line, evicted
end

-- Убирает строки с истёкшим сроком; возвращает убранные.
function EventFeed.expire(feed: Feed, now: number): { Line }
	local gone: { Line } = {}
	local i = 1
	while i <= #feed.lines do
		local line = feed.lines[i]
		if now >= line.untilTime then
			table.insert(gone, table.remove(feed.lines, i) :: Line)
		else
			i += 1
		end
	end
	return gone
end

-- Текст строки: повтор — «×N».
function EventFeed.textOf(line: Line): string
	return if line.count > 1 then string.format("%s ×%d", line.text, line.count) else line.text
end

return table.freeze(EventFeed)
