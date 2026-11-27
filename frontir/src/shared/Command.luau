--!strict
--[[
	Command — §15ь Л1 «Принять командование», без Roblox API: выбывший игрок (или зритель, вошедший в идущий матч)
	берёт живую державу бота и играет дальше. Какую — бот со срединной сушей среди живых ботов (не сильнейший —
	честно, не слабейший — есть шанс); при равенстве — меньший id. Место державы — по суше среди живых.
]]

local Config = require("./Config")

export type Row = { id: number, land: number, bot: boolean, alive: boolean }
export type Facts = {
	phase: string,
	duel: boolean,
	tutorial: boolean,
	secLeft: number, -- до конца матча (math.huge — без лимита)
	used: boolean, -- уже брал в этом матче
	living: boolean, -- у игрока есть живая держава
}

local Command = {}

-- Держава для командования: живой бот со срединной сушей; nil — нет живых ботов.
function Command.candidate(rows: { Row }): number?
	local bots: { Row } = {}
	for _, r in rows do
		if r.bot and r.alive then
			table.insert(bots, r)
		end
	end
	if #bots == 0 then
		return nil
	end
	table.sort(bots, function(a: Row, b: Row): boolean
		if a.land ~= b.land then
			return a.land > b.land
		end
		return a.id < b.id
	end)
	return bots[(#bots + 1) // 2].id
end

-- Место державы по суше среди живых (1 — больше всех) и сколько живых; мёртвая — nil.
function Command.place(rows: { Row }, id: number): (number?, number)
	local alive: { Row } = {}
	for _, r in rows do
		if r.alive then
			table.insert(alive, r)
		end
	end
	table.sort(alive, function(a: Row, b: Row): boolean
		if a.land ~= b.land then
			return a.land > b.land
		end
		return a.id < b.id
	end)
	for k, r in alive do
		if r.id == id then
			return k, #alive
		end
	end
	return nil, #alive
end

-- Можно ли сейчас принять командование; нет — причина (ключ reject.*).
function Command.allowed(f: Facts): (boolean, string?)
	if f.phase ~= "Play" then
		return false, "notYet"
	end
	if f.duel or f.tutorial then
		return false, "commandMode"
	end
	if f.living then
		return false, "commandAlive"
	end
	if f.used and Config.Command.OncePerMatch then
		return false, "commandUsed"
	end
	if f.secLeft < Config.Command.MinSecLeft then
		return false, "commandLate"
	end
	return true, nil
end

return table.freeze(Command)
