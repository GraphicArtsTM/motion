--!strict
--[[
	Layering — порядок отрисовки окон в HUD. HUD (FrontirHud) рисуется в режиме ZIndexBehavior.Global: там элемент
	с ZIndex меньше, чем у его окна, рисуется ПОД фоном окна. Окна поднимают себе ZIndex (Дипломатия 5, Совет 4,
	Технологии 5, итоги 6…), а их содержимое по умолчанию — 1, и текст с кнопками прятались под фоном (найдено
	в Studio: пустое окно предложения союза, тусклая Дипломатия).

	lift(window) прибавляет ZIndex окна ко всему его содержимому (порядок внутри окна сохраняется) — и к тому,
	что добавят потом (карточки строятся при открытии). Каждый элемент — один раз (атрибут ZLifted).
]]

local Session = require(script.Parent.Parent:WaitForChild("Session"))

local Layering = {}

function Layering.lift(window: GuiObject)
	local base = window.ZIndex
	if base <= 1 then
		return
	end
	local function raise(d: Instance)
		if d:IsA("GuiObject") and d:GetAttribute("ZLifted") == nil then
			d:SetAttribute("ZLifted", true)
			d.ZIndex += base
		end
	end
	for _, d in window:GetDescendants() do
		raise(d)
	end
	Session.connect(window.DescendantAdded, raise)
end

-- Все окна HUD с поднятым ZIndex (прямые дети ScreenGui).
function Layering.liftAll(gui: ScreenGui)
	for _, c in gui:GetChildren() do
		if c:IsA("GuiObject") and c.ZIndex > 1 then
			Layering.lift(c)
		end
	end
end

return table.freeze(Layering)
