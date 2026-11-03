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
	end
	return nil, "unknown kind"
end

return table.freeze(Intents)
