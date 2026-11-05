--!strict
--[[
	Commanders — генералы игроков (GDD §6.15, этап 7в-2). Чистый модуль: кто какого генерала выбрал, перезарядки
	способностей, действующие эффекты (прорыв, вспышка, зоны авиаудара и укрепрайона), пассивки — множителями.
	Что делает способность с матчем, решает MatchSim (секция «Генералы»).

	В коде «Commander», чтобы не путать с уровнем бота «General» (§9.1); игроку — «Генерал».
]]

local Config = require("./Config")
local Types = require("./Types")

type CommanderId = Types.CommanderId

export type Ability =
	"Airstrike"
	| "Surge"
	| "SeaLanding"
	| "Blockade"
	| "Reveal"
	| "Propaganda"
	| "Fortify"
	| "Airdrop"

-- Зона на время: авиаудар (круг) или укрепрайон (провинция).
export type Strike = { owner: number, cell: number, untilTime: number }
export type FortZone = { owner: number, province: number, untilTime: number }

export type CommanderState = {
	chosen: { [number]: CommanderId },
	ready: { [number]: { number } }, -- держава → игровое время, когда готов слот 1 / 2
	surgeUntil: { [number]: number },
	revealUntil: { [number]: number },
	strikes: { Strike },
	forts: { FortZone },
	version: number,
}

local ABILITIES: { [string]: { Ability } } = {
	Marshal = { "Airstrike", "Surge" },
	Admiral = { "SeaLanding", "Blockade" },
	Scout = { "Reveal", "Propaganda" },
	Engineer = { "Fortify", "Airdrop" },
}

-- Способности без цели на карте.
local NO_TARGET: { [string]: boolean } = { Surge = true, Reveal = true }

local Commanders = {}

function Commanders.new(): CommanderState
	return { chosen = {}, ready = {}, surgeUntil = {}, revealUntil = {}, strikes = {}, forts = {}, version = 0 }
end

function Commanders.isValid(name: any): boolean
	return type(name) == "string" and ABILITIES[name] ~= nil
end

-- Генерал державы (не выбран — Config.Commanders.Default).
function Commanders.of(st: CommanderState, id: number): CommanderId
	return st.chosen[id] or (Config.Commanders.Default :: CommanderId)
end

function Commanders.choose(st: CommanderState, id: number, commander: CommanderId)
	st.chosen[id] = commander
	st.version += 1
end

-- Генерал бота по личности.
function Commanders.forPersonality(personality: Types.BotPersonality?): CommanderId
	local pick = (Config.Commanders.BotPick :: any)[personality or ""]
	return if pick ~= nil then pick else Config.Commanders.Default :: CommanderId
end

function Commanders.ability(commander: CommanderId, slot: number): Ability
	return ABILITIES[commander][slot]
end

function Commanders.needsTarget(ability: string): boolean
	return not NO_TARGET[ability]
end

function Commanders.cooldown(commander: CommanderId, slot: number): number
	return (Config.Commanders.Cooldown :: any)[commander][slot]
end

-- Сколько секунд до готовности слота (0 — готов).
function Commanders.left(st: CommanderState, id: number, slot: number, now: number): number
	local r = st.ready[id]
	return if r == nil then 0 else math.max(0, (r[slot] or 0) - now)
end

function Commanders.use(st: CommanderState, id: number, slot: number, now: number)
	local r = st.ready[id]
	if r == nil then
		r = { 0, 0 }
		st.ready[id] = r
	end
	r[slot] = now + Commanders.cooldown(Commanders.of(st, id), slot)
	st.version += 1
end

-- Панель разработчика: обе способности готовы.
function Commanders.resetCooldowns(st: CommanderState, id: number)
	st.ready[id] = nil
	st.version += 1
end

-- Пассивки — множители цены и обзора.
function Commanders.tankCostMul(c: CommanderId): number
	return if c == "Marshal" then 1 - Config.Commanders.TankDiscount else 1
end

function Commanders.shipCostMul(c: CommanderId): number
	return if c == "Admiral" then 1 - Config.Commanders.ShipDiscount else 1
end

function Commanders.buildCostMul(c: CommanderId): number
	return if c == "Engineer" then 1 - Config.Commanders.BuildDiscount else 1
end

function Commanders.visionMul(c: CommanderId): number
	return if c == "Scout" then Config.Commanders.VisionMul else 1
end

function Commanders.surging(st: CommanderState, id: number, now: number): boolean
	return (st.surgeUntil[id] or 0) > now
end

function Commanders.revealing(st: CommanderState, id: number, now: number): boolean
	return (st.revealUntil[id] or 0) > now
end

-- Убрать истёкшие зоны (раз в тик).
function Commanders.cleanup(st: CommanderState, now: number)
	for _, list in { st.strikes, st.forts } :: { { any } } do
		local k = 1
		while k <= #list do
			if list[k].untilTime <= now then
				table.remove(list, k)
			else
				k += 1
			end
		end
	end
end

function Commanders.removeNation(st: CommanderState, id: number)
	st.ready[id] = nil
	st.surgeUntil[id] = nil
	st.revealUntil[id] = nil
	for _, list in { st.strikes, st.forts } :: { { any } } do
		for k = #list, 1, -1 do
			if list[k].owner == id then
				table.remove(list, k)
			end
		end
	end
	st.version += 1
end

return table.freeze(Commanders)
