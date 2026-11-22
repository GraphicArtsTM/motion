--!strict
--[[
	NationCard — окно державы (GDD §15й Й7), без Roblox API: какие действия показать по отношению к чужой державе,
	можно ли их сейчас и почему нельзя (ключ причины для строки `nation.why.<причина>`). Правила — те же, что у
	сервера (он всё равно проверит намерения declare / offer / transfer / intel).
]]

export type Group = "war" | "diplo" | "intel" | "more"
export type Key =
	"declare"
	| "front"
	| "peace"
	| "demand"
	| "alliance"
	| "pact"
	| "trade"
	| "trust"
	| "gift"
	| "intel"
	| "capital"
	| "diplomacy"

export type Action = { key: Key, group: Group, enabled: boolean, why: string?, warn: string? }

export type Facts = {
	atWar: boolean, -- активная война
	mobilizing: boolean, -- война объявлена, идёт мобилизация
	treaty: string?, -- nil | "pact" | "alliance"
	breaking: boolean, -- договор рвётся
	trust: boolean, -- полное доверие уже есть
	trustWait: number, -- секунд до «Полного доверия» (≤ 0 — можно)
	trade: boolean, -- торговое соглашение уже есть
	cooldown: number, -- секунд до права объявить войну (после мира)
	diplomacy: boolean, -- договоры разрешены (частный сервер может выключить)
	teammate: boolean, -- своя команда («Команды»)
	intelOpen: boolean, -- разведка открыта (§15э Э1б)
	intelWait: number, -- секунд до новой разведки
	powerKnown: boolean, -- мощь уже видна
	money: number, -- свои деньги
	giftMoney: number, -- сколько дарит «Подарок»
}

local NationCard = {}

NationCard.Groups = table.freeze({ "war", "diplo", "intel", "more" } :: { Group })

local function add(out: { Action }, key: Key, group: Group, enabled: boolean, why: string?, warn: string?)
	table.insert(out, { key = key, group = group, enabled = enabled, why = if enabled then nil else why, warn = warn })
end

function NationCard.actions(f: Facts): { Action }
	local out: { Action } = {}
	local war = f.atWar or f.mobilizing
	-- ВОЙНА
	if war then
		add(out, "front", "war", true)
		add(out, "peace", "war", f.atWar, "mobilizing")
	elseif not f.teammate then
		local why = if f.cooldown > 0 then "cooldown" else nil
		add(out, "declare", "war", why == nil, why, if f.treaty ~= nil then "betray" else nil)
		if f.diplomacy then
			add(out, "demand", "war", true)
		end
	end
	-- ДИПЛОМАТИЯ
	if f.diplomacy and not war then
		if f.treaty == "alliance" then
			if not f.trust and not f.breaking then
				add(out, "trust", "diplo", f.trustWait <= 0, "trustWait")
			end
		else
			add(out, "alliance", "diplo", not f.breaking, "breaking")
			if f.treaty == nil then
				add(out, "pact", "diplo", true)
			end
		end
		if not f.trade then
			add(out, "trade", "diplo", true)
		end
		add(out, "gift", "diplo", f.money >= f.giftMoney, "money")
	end
	-- РАЗВЕДКА
	if not f.teammate then
		local why = if not f.intelOpen
			then "locked"
			elseif f.powerKnown then "known"
			elseif f.intelWait > 0 then "intelWait"
			else nil
		add(out, "intel", "intel", why == nil, why)
	end
	-- ЕЩЁ
	add(out, "capital", "more", true)
	if f.diplomacy then
		add(out, "diplomacy", "more", true)
	end
	return out
end

-- Действия одной группы (в порядке списка).
function NationCard.inGroup(list: { Action }, group: Group): { Action }
	local out: { Action } = {}
	for _, a in list do
		if a.group == group then
			table.insert(out, a)
		end
	end
	return out
end

-- Доля «моей» силы в паре 0..1 для полосы «кто сильнее» (скрытая сила врага — nil).
function NationCard.balance(mine: number, theirs: number?): number?
	if theirs == nil or theirs < 0 then
		return nil
	end
	local sum = math.max(0, mine) + theirs
	if sum <= 0 then
		return 0.5
	end
	return math.max(0, mine) / sum
end

return table.freeze(NationCard)
