--!strict
--[[
	Intents — разбор намерений, пришедших от клиента (GDD §12: валидация каждого запроса).
	Клиенту не доверяем: проверяем типы, конечность чисел, целочисленность и диапазоны.
	Смысловые проверки (фаза матча, соседство, хватает ли людей) — в MatchSim.applyIntent.
]]

local Config = require("./Config")
local Types = require("./Types")

local Intents = {}

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and math.abs(v) < 2 ^ 31
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Разбирает (kind, payload) с клиента. Возвращает намерение или текст ошибки.
function Intents.parse(kind: any, payload: any): (Types.Intent?, string?)
	if type(kind) ~= "string" or type(payload) ~= "table" then
		return nil, "bad shape"
	end
	if kind == "pick" then
		local cell = payload.cell
		if not isInt(cell) or cell < 0 then
			return nil, "bad cell"
		end
		return { kind = "pick", cell = cell }, nil
	elseif kind == "attack" then
		local target, percent, focus = payload.target, payload.percent, payload.focus
		if not isInt(target) or target < 0 then
			return nil, "bad target"
		end
		local cfg = Config.Expansion
		if not isFinite(percent) or percent < cfg.MinPercent - 1e-9 or percent > cfg.MaxPercent + 1e-9 then
			return nil, "bad percent"
		end
		if focus ~= nil and (not isInt(focus) or focus < 0) then
			return nil, "bad focus"
		end
		return { kind = "attack", target = target, percent = percent, focus = focus }, nil
	elseif kind == "hire" then
		local unit = payload.unit
		if type(unit) ~= "string" or table.find(Types.LandUnits, unit) == nil then
			return nil, "bad unit"
		end
		return { kind = "hire", unit = unit :: Types.LandUnit }, nil
	elseif kind == "cancel" then
		local target = payload.target
		if not isInt(target) or target < 0 then
			return nil, "bad target"
		end
		return { kind = "cancel", target = target }, nil
	elseif kind == "declare" then
		local target = payload.target
		if not isInt(target) or target <= 0 then
			return nil, "bad target"
		end
		return { kind = "declare", target = target }, nil
	elseif kind == "peace" then
		local target, terms = payload.target, payload.terms
		if not isInt(target) or target <= 0 then
			return nil, "bad target"
		end
		if terms ~= "white" and terms ~= "keep" and terms ~= "capitulate" then
			return nil, "bad terms"
		end
		return { kind = "peace", target = target, terms = terms :: Types.PeaceTerms }, nil
	elseif kind == "peaceReply" then
		local target, accept = payload.target, payload.accept
		if not isInt(target) or target <= 0 then
			return nil, "bad target"
		end
		if type(accept) ~= "boolean" then
			return nil, "bad accept"
		end
		return { kind = "peaceReply", target = target, accept = accept }, nil
	elseif kind == "build" then
		local building, cell = payload.building, payload.cell
		if type(building) ~= "string" or table.find(Config.Buildable, building) == nil then
			return nil, "bad building"
		end
		if not isInt(cell) or cell < 0 then
			return nil, "bad cell"
		end
		return { kind = "build", building = building :: Types.BuildingKind, cell = cell }, nil
	elseif kind == "offer" then
		local target, offer, province = payload.target, payload.offer, payload.province
		if not isInt(target) or target <= 0 then
			return nil, "bad target"
		end
		if offer ~= "pact3" and offer ~= "pact5" and offer ~= "alliance" and offer ~= "demand" and offer ~= "trade" then
			return nil, "bad offer"
		end
		if offer == "demand" and (not isInt(province) or province <= 0) then
			return nil, "bad province"
		end
		return {
			kind = "offer",
			target = target,
			offer = offer :: Types.OfferKind,
			province = if offer == "demand" then province else nil,
		},
			nil
	elseif kind == "offerReply" then
		local target, accept = payload.target, payload.accept
		if not isInt(target) or target <= 0 then
			return nil, "bad target"
		end
		if type(accept) ~= "boolean" then
			return nil, "bad accept"
		end
		return { kind = "offerReply", target = target, accept = accept }, nil
	elseif kind == "breakTreaty" then
		local target = payload.target
		if not isInt(target) or target <= 0 then
			return nil, "bad target"
		end
		return { kind = "breakTreaty", target = target }, nil
	elseif kind == "rebel" then
		return { kind = "rebel" }, nil
	elseif kind == "transfer" then
		local target = payload.target
		if not isInt(target) or target <= 0 then
			return nil, "bad target"
		end
		local money, oil, people = payload.money or 0, payload.oil or 0, payload.people or 0
		for _, v in { money, oil, people } do
			if not isFinite(v) or v < 0 or v > 1e9 then
				return nil, "bad amount"
			end
		end
		return {
			kind = "transfer",
			target = target,
			money = math.floor(money),
			oil = math.floor(oil),
			people = math.floor(people),
		},
			nil
	elseif kind == "embargo" then
		local target, on = payload.target, payload.on
		if not isInt(target) or target <= 0 then
			return nil, "bad target"
		end
		if type(on) ~= "boolean" then
			return nil, "bad on"
		end
		return { kind = "embargo", target = target, on = on }, nil
	elseif kind == "vote" then
		local option = payload.option
		if not isInt(option) or option < 1 or option > Config.Council.Options then
			return nil, "bad option"
		end
		return { kind = "vote", option = option }, nil
	elseif kind == "ping" then
		local cell, phrase = payload.cell, payload.phrase
		if not isInt(cell) or cell < 0 then
			return nil, "bad cell"
		end
		if type(phrase) ~= "string" or table.find(Config.Pings.Phrases, phrase) == nil then
			return nil, "bad phrase"
		end
		return { kind = "ping", cell = cell, phrase = phrase :: Types.Phrase }, nil
	end
	return nil, "unknown kind"
end

return table.freeze(Intents)
