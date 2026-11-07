--!strict
--[[
	Polish — единое оформление интерфейса (§15г). Подключается к ScreenGui интерфейса один раз и оформляет всё,
	что в нём есть и появится потом, без правки каждого окна:
	- кнопки и окна — пиксельный вид (§15л ч.4, Theme.decorate): квадратные углы, рамка, фаска, полка под кнопкой;
	  наведение — золотая рамка, нажатие — кнопка «вдавливается»; все скругления в слое — квадратные (круги — нет);
	- окна и плашки (непрозрачный фон, не меньше MinPanel) — так же, без полки;
	- окно, которое становится видимым (имя на Panel / Window / Menu / Dialog / Picker), появляется с пружинкой.
	Мелкие детали (полосы, точки, значки) и эффекты со своим градиентом (виньетка) не трогает.
]]

local Theme = require(script.Parent:WaitForChild("Theme"))

local Polish = {}

local MIN_W, MIN_H = 80, 30
local WINDOW_SUFFIXES = { "Panel", "Window", "Menu", "Dialog", "Picker" }

local function isWindow(g: GuiObject): boolean
	for _, suffix in WINDOW_SUFFIXES do
		if string.sub(g.Name, -#suffix) == suffix then
			return true
		end
	end
	return false
end

local function style(inst: Instance)
	-- §15л ч.4: пиксельный вид — углы квадратные (скругление могут задать после вставки — проверяем позже).
	if inst:IsA("UICorner") then
		local corner = inst :: UICorner
		Theme.square(corner)
		task.defer(function()
			if corner.Parent ~= nil then
				Theme.square(corner)
			end
		end)
		return
	end
	if inst:IsA("GuiButton") then
		local b = inst :: GuiButton
		if b.BackgroundTransparency < 0.9 then
			Theme.decorate(b)
		end
	elseif inst:IsA("Frame") then
		local f = inst :: Frame
		if isWindow(f) then
			f:GetPropertyChangedSignal("Visible"):Connect(function()
				if f.Visible then
					Theme.popIn(f)
				end
			end)
		end
		-- Размер известен не сразу (AutomaticSize) — проверяем после раскладки.
		task.defer(function()
			-- Свой градиент — это эффект (виньетка, полосы), его не трогаем.
			if f.Parent == nil or f.BackgroundTransparency >= 0.6 or f:FindFirstChildOfClass("UIGradient") ~= nil then
				return
			end
			local size = f.AbsoluteSize
			if size.X >= MIN_W and size.Y >= MIN_H or f.AutomaticSize ~= Enum.AutomaticSize.None then
				Theme.decorate(f)
			end
		end)
	end
end

function Polish.attach(gui: ScreenGui)
	for _, inst in gui:GetDescendants() do
		style(inst)
	end
	gui.DescendantAdded:Connect(style)
end

return table.freeze(Polish)
