--!strict
--[[
	StrikeStatus — факты для StrikeMenu из состояния клиента (§15х ч.4): шахта, аэродромы и бомбардировщики, генерал,
	война с целью. Общий для кольца действий (ПКМ по врагу) и панели «УДАРЫ». Подсказка «что сделать» — how().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Air = require(Shared:WaitForChild("Air"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Config = require(Shared:WaitForChild("Config"))
local StrikeMenu = require(Shared:WaitForChild("StrikeMenu"))
local Strings = require(Shared:WaitForChild("Strings"))

type ClientState = ClientState.ClientState

local StrikeStatus = {}

-- Слот генерала (1 — Q, 2 — E) с ударом по врагу или nil.
function StrikeStatus.abilitySlot(cs: ClientState): number?
	local commander = ClientState.myCommander(cs)
	for slot = 1, 2 do
		local name: string = Commanders.ability(commander :: any, slot)
		if StrikeMenu.EnemyAbilities[name] then
			return slot
		end
	end
	return nil
end

-- Факты о моих ударах; cell — цель (nil — «вообще», для панели: война хоть с кем-то, радиус не проверяем).
function StrikeStatus.facts(cs: ClientState, cell: number?, now: number): StrikeMenu.Facts
	local me = cs.myNation or 0
	local rate = ClientState.simRate(cs)
	local w = cs.width
	local atWar = false
	if cell ~= nil then
		local owner = ClientState.ownerAt(cs, cell)
		local war = if owner ~= 0 and owner ~= me then ClientState.warBetween(cs, me, owner) else nil
		atWar = war ~= nil and war.active
	else
		for _, war in ClientState.warsOf(cs, me) do
			if war.active then
				atWar = true
			end
		end
	end
	-- Аэродромы: свои, работающие; ближайший к цели — для радиуса (как MatchSim.inAirRange).
	local airfields = 0
	local best = math.huge
	for at, b in cs.buildings do
		if b.kind == "Airfield" and ClientState.ownerAt(cs, at) == me and not ClientState.isDisabled(cs, at) then
			airfields += 1
			if cell ~= nil then
				local dx, dy = at % w - cell % w, at // w - cell // w
				best = math.min(best, math.sqrt(dx * dx + dy * dy))
			end
		end
	end
	local bombers, ready = 0, 0
	for _, p in cs.air.planes do
		if p.owner == me and p.kind == "Bomber" then
			bombers += 1
			if p.state == "based" then
				ready += 1
			end
		end
	end
	local slot = StrikeStatus.abilitySlot(cs)
	local abilityLeft = 0
	if slot ~= nil then
		abilityLeft = math.max(0, (cs.commander.left[slot] or 0) - (now - cs.commanderAt) * rate)
	end
	return {
		atWar = atWar,
		armyLevel = cs.tech.levels.Army,
		fleetLevel = cs.tech.levels.Fleet,
		silo = cs.world.silo,
		missileLeft = math.max(0, cs.world.missileLeft - (now - cs.worldAt) * rate),
		airfields = airfields,
		inRange = cell == nil or best <= Config.Air.Range * Air.scale(w),
		bombers = bombers,
		bombersReady = ready,
		ability = if slot ~= nil then Commanders.ability(ClientState.myCommander(cs), slot) else nil,
		abilityLeft = abilityLeft,
	}
end

-- Подсказка «что сделать», чтобы удар стал доступен (пусто для «ok»).
function StrikeStatus.how(kind: StrikeMenu.Kind, why: string, f: StrikeMenu.Facts, lang: Strings.Lang): string
	if why == "ok" then
		return ""
	end
	local text = Strings.get(StrikeMenu.howKey(kind, why :: any), lang)
	if why == "cooldown" then
		local left = if kind == "missile" then f.missileLeft else f.abilityLeft
		return string.format(text, math.ceil(left))
	end
	return text
end

-- Короткая причина для кнопки («нужна шахта», «12 с»).
function StrikeStatus.short(kind: StrikeMenu.Kind, why: string, f: StrikeMenu.Facts, lang: Strings.Lang): string
	if why == "cooldown" then
		local left = if kind == "missile" then f.missileLeft else f.abilityLeft
		return string.format(Strings.get("missile.cooldown", lang), math.ceil(left))
	end
	return Strings.get("strikeShort." .. why, lang)
end

return table.freeze(StrikeStatus)
