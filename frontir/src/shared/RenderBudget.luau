--!strict
--[[
	RenderBudget — пределы эффектов на этом устройстве (этап 10в). На телефоне (касание без клавиатуры) —
	Config.Render.Phone, иначе — обычные (Config.Render.Battle и Config.Render). Чистый модуль: устройство передаёт
	клиент (UserInputService), тест проверяет числа.
]]

local Config = require("./Config")

local RenderBudget = {}

-- Телефон ли это (флаги — из UserInputService у клиента).
function RenderBudget.isPhone(touch: boolean, keyboard: boolean): boolean
	return touch and not keyboard
end

-- Предел name (MaxUnitsOnScreen, MaxParticles, MaxCraters, SparkleMax) для устройства.
function RenderBudget.limit(name: string, phone: boolean): number
	local p = (Config.Render.Phone :: any)[name]
	if phone and p ~= nil then
		return p
	end
	local battle = (Config.Render.Battle :: any)[name]
	if battle ~= nil then
		return battle
	end
	return (Config.Render :: any)[name]
end

return table.freeze(RenderBudget)
