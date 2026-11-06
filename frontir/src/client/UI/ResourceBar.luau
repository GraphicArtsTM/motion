--!strict
--[[
	ResourceBar — полоса ресурсов «как в игре» (§15д ч.5): слева сверху плашки со значками 8×8 (Shared.PixelIcons):
	деньги, нефть, люди, войска, земля — число крупно и прирост в секунду мелко. Числа «бегут» к новому значению,
	при росте плашка коротко вспыхивает зелёным, при падении — красным. Значения даёт MatchHud.refresh (set),
	анимация — update(now) каждый кадр.
	У людей (§15е) — столбик «сколько от максимума» с зелёной зоной Render.PeopleZone: рост логистический, быстрее
	всего около половины; при наведении — подсказка.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PixelIcons = require(Shared:WaitForChild("PixelIcons"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

export type Values = {
	money: number,
	income: number,
	oil: number,
	oilIncome: number,
	people: number,
	maxPeople: number,
	growth: number,
	army: number,
	land: number, -- доля суши, %
}

export type ResourceBar = {
	frame: Frame,
	set: (v: Values) -> (),
	update: (now: number) -> (),
	setVisible: (on: boolean) -> (),
}

type Chip = {
	frame: Frame,
	value: TextLabel,
	delta: TextLabel,
	shown: number,
	target: number,
	format: (n: number) -> string,
}

local ResourceBar = {}

local ICON_SCALE = 3

local function iconFrame(parent: Instance, key: string): Frame
	local size = PixelIcons.Size * ICON_SCALE
	local root = Instance.new("Frame")
	root.Name = "Icon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size, size)
	root.LayoutOrder = 1
	root.Parent = parent
	for _, p in PixelIcons.Icons[key] do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Theme.color(p.color)
		f.Position = UDim2.fromOffset(p.x * ICON_SCALE, p.y * ICON_SCALE)
		f.Size = UDim2.fromOffset(p.w * ICON_SCALE, p.h * ICON_SCALE)
		f.Parent = root
	end
	return root
end

function ResourceBar.new(gui: ScreenGui, lang: Strings.Lang): ResourceBar
	local bar = Instance.new("Frame")
	bar.Name = "ResourceBar"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromOffset(12, 8)
	bar.Size = UDim2.fromOffset(0, 40)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Visible = false
	bar.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = bar

	local chips: { [string]: Chip } = {}
	local function chip(order: number, key: string, tip: string, format: (n: number) -> string): Chip
		local f = Instance.new("Frame")
		f.Name = "Res_" .. key
		f.LayoutOrder = order
		f.BackgroundColor3 = Theme.Colors.PanelBg
		f.BackgroundTransparency = 0.1
		f.BorderSizePixel = 0
		f.Size = UDim2.fromOffset(0, 40)
		f.AutomaticSize = Enum.AutomaticSize.X
		f.Parent = bar
		Theme.decorate(f)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = f
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.Padding = UDim.new(0, 6)
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.Parent = f
		iconFrame(f, key)
		local texts = Instance.new("Frame")
		texts.LayoutOrder = 2
		texts.BackgroundTransparency = 1
		texts.Size = UDim2.fromOffset(0, 36)
		texts.AutomaticSize = Enum.AutomaticSize.X
		texts.Parent = f
		local value = Instance.new("TextLabel")
		value.BackgroundTransparency = 1
		value.Size = UDim2.fromOffset(0, 22)
		value.AutomaticSize = Enum.AutomaticSize.X
		value.FontFace = Theme.FontBold
		value.TextSize = 18
		value.TextColor3 = Theme.Colors.Text
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.Parent = texts
		local delta = Instance.new("TextLabel")
		delta.BackgroundTransparency = 1
		delta.Position = UDim2.fromOffset(0, 21)
		delta.Size = UDim2.fromOffset(0, 14)
		delta.AutomaticSize = Enum.AutomaticSize.X
		delta.FontFace = Theme.Font
		delta.TextSize = 12
		delta.TextColor3 = Theme.Colors.Sky
		delta.TextXAlignment = Enum.TextXAlignment.Left
		delta.Text = tip
		delta.Parent = texts
		local c: Chip = { frame = f, value = value, delta = delta, shown = 0, target = 0, format = format }
		chips[key] = c
		return c
	end
	local function int(n: number): string
		return Strings.formatInt(n)
	end
	chip(1, "money", "", function(n: number): string
		return "$" .. int(n)
	end)
	chip(2, "oil", "", int)
	chip(3, "people", "", int)
	chip(4, "army", Strings.get("res.army", lang), int)
	chip(5, "land", Strings.get("res.land", lang), function(n: number): string
		return string.format("%.1f%%", n)
	end)

	-- Столбик людей (§15е): заполнение снизу, зелёная зона лучшего роста, подсказка при наведении.
	local zone = Config.Render.PeopleZone
	local gauge = Instance.new("Frame")
	gauge.Name = "PeopleGauge"
	gauge.LayoutOrder = 3
	gauge.Size = UDim2.fromOffset(8, 34)
	gauge.BackgroundColor3 = Theme.Colors.Backdrop
	gauge.BorderSizePixel = 0
	gauge.Parent = chips.people.frame
	local band = Instance.new("Frame")
	band.BorderSizePixel = 0
	band.BackgroundColor3 = Theme.Colors.Good
	band.BackgroundTransparency = 0.55
	band.AnchorPoint = Vector2.new(0, 1)
	band.Position = UDim2.fromScale(0, 1 - zone[1])
	band.Size = UDim2.fromScale(1, zone[2] - zone[1])
	band.ZIndex = 2
	band.Parent = gauge
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.ZIndex = 3
	fill.BackgroundTransparency = 0.15
	fill.Parent = gauge
	local tipLabel = Instance.new("TextLabel")
	tipLabel.Name = "PeopleTip"
	tipLabel.AnchorPoint = Vector2.new(0, 0)
	tipLabel.Position = UDim2.new(0, 0, 1, 6)
	tipLabel.Size = UDim2.fromOffset(300, 0)
	tipLabel.AutomaticSize = Enum.AutomaticSize.Y
	tipLabel.BackgroundColor3 = Theme.Colors.PanelBg
	tipLabel.BorderSizePixel = 0
	tipLabel.FontFace = Theme.Font
	tipLabel.TextSize = 13
	tipLabel.TextWrapped = true
	tipLabel.TextXAlignment = Enum.TextXAlignment.Left
	tipLabel.TextColor3 = Theme.Colors.Text
	tipLabel.Text = Strings.get("res.peopleTip", lang)
	tipLabel.Visible = false
	tipLabel.ZIndex = 20
	tipLabel.Parent = chips.people.frame
	Session.connect(chips.people.frame.MouseEnter, function()
		tipLabel.Visible = true
	end)
	Session.connect(chips.people.frame.MouseLeave, function()
		tipLabel.Visible = false
	end)

	local FLASH = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function flash(c: Chip, up: boolean)
		c.frame.BackgroundColor3 = if up then Theme.Colors.Good else Theme.Colors.Alert
		TweenService:Create(c.frame, FLASH, { BackgroundColor3 = Theme.Colors.PanelBg }):Play()
	end

	local function setChip(key: string, target: number, deltaText: string?, deltaUp: boolean?)
		local c = chips[key]
		-- Заметное изменение (не обычный прирост по секундам) — вспышка.
		local jump = math.abs(target - c.target)
		if c.target ~= 0 and jump >= math.max(Config.Render.ResourceFlashMin, math.abs(c.target) * 0.05) then
			flash(c, target > c.target)
		end
		c.target = target
		if deltaText ~= nil then
			c.delta.Text = deltaText
			c.delta.TextColor3 = if deltaUp == false then Theme.Colors.Alert else Theme.Colors.Sky
		end
	end

	local function signed(n: number): string
		return (if n >= 0 then "+" else "") .. Strings.formatInt(n) .. Strings.get("res.perSec", lang)
	end

	local function set(v: Values)
		setChip("money", v.money, signed(v.income), v.income >= 0)
		setChip("oil", v.oil, signed(v.oilIncome), v.oilIncome >= 0)
		setChip(
			"people",
			v.people,
			string.format("/%s  %s", Strings.formatInt(v.maxPeople), signed(v.growth)),
			v.growth >= 0
		)
		-- Столбик людей: в зелёной зоне — зелёный, ниже — золотой (копим), выше — серый (рост замедлился, пора в атаку).
		local share = if v.maxPeople > 0 then math.clamp(v.people / v.maxPeople, 0, 1) else 0
		fill.Size = UDim2.fromScale(1, share)
		fill.BackgroundColor3 = if share < zone[1]
			then Theme.Colors.Gold
			elseif share <= zone[2] then Theme.Colors.Good
			else Theme.Colors.Muted
		setChip("army", v.army, nil, nil)
		setChip("land", v.land, nil, nil)
	end

	local last = os.clock()
	local function update(now: number)
		local dt = math.clamp(now - last, 0, 0.25)
		last = now
		local k = 1 - math.exp(-dt * Config.Render.ResourceLerpPerSec)
		for _, c in chips do
			if c.shown ~= c.target then
				c.shown += (c.target - c.shown) * k
				if math.abs(c.target - c.shown) < 0.5 then
					c.shown = c.target
				end
				c.value.Text = c.format(c.shown)
			end
		end
	end

	return {
		frame = bar,
		set = set,
		update = update,
		setVisible = function(on: boolean)
			bar.Visible = on
		end,
	}
end

return table.freeze(ResourceBar)
