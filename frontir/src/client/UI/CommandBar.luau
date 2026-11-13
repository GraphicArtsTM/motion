--!strict
--[[
	CommandBar — командная полоса матча (GDD §15л ч.2): одна полоса снизу по центру, только у живой державы в игре.
	Слева направо: держава (цвет, имя, «N% мира»); люди «N / максимум», прирост и столбик с зелёной зоной лучшего
	роста (Render.PeopleZone); атака — кнопки долей (Render.CommandBar.Percents) и «пошлёт N людей»; деньги и нефть
	с приростом; найм Z / X / C / V (значок юнита, цена, очередь, замок без казарм); стройка — клетки всех зданий
	(цена, клавиши 1–0; блёкло — не хватает денег или технологии); магазин.
	§15ц Ц3: у каждой группы заголовок (ДЕРЖАВА · ЛЮДИ · АТАКА · ДЕНЬГИ · ВОЙСКА · СТРОЙКА), в заголовке ВОЙСК
	справа — «в армии N» / красное «нет войск»; значки найма и стройки — своим цветом вида
	(Render.CommandBar.KindColors / UnitColors), под значком — короткое название.
	Подсказка при наведении на клетку — над ней. Числа берёт у MatchHud (values), найм — у ForcesPanel,
	стройку — у BuildPanel: логика окон не дублируется. Узкий экран — полоса ужимается (UIScale) до MinScale,
	дальше переносится в два ряда.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local PhoneLayout = require(Shared:WaitForChild("PhoneLayout"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))
local UnitSprites = require(Shared:WaitForChild("UnitSprites"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local ResourceBar = require(script.Parent:WaitForChild("ResourceBar"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type HireInfo = {
	cost: number,
	oil: number,
	people: number,
	sec: number,
	queued: number,
	needLevel: number?,
	affordable: boolean,
}

export type Deps = {
	values: () -> ResourceBar.Values?,
	percent: () -> number,
	setPercent: (p: number) -> (),
	hire: (k: number) -> (),
	hireInfo: (k: number) -> HireInfo,
	army: () -> (number, number), -- §15ц Ц3: войска дома и на фронтах
	armyTip: () -> string, -- состав войск (подсказка заголовка ВОЙСКА)
	build: {
		pick: (kind: Types.BuildingKind) -> (),
		price: (kind: Types.BuildingKind) -> number?,
		unlocked: (kind: Types.BuildingKind) -> boolean,
		selected: () -> Types.BuildingKind?,
		canBuild: () -> boolean,
		color: () -> Color3,
	},
	buildIcon: (parent: Instance, kind: string, color: Color3) -> Frame,
	shop: () -> (),
	-- §15л ч.6 Арсенал: взятый в бой предмет (nil — нет), применён ли; применить.
	arsenal: { info: () -> (string?, boolean), use: () -> (), icons: { [string]: string } },
}

export type CommandBar = {
	frame: Frame,
	update: (now: number) -> (),
	visible: () -> boolean,
}

local CommandBar = {}

local NATION_W, PEOPLE_W, ATTACK_W, MONEY_W, SHOP_W = 150, 170, 206, 130, 60
local GAP, PAD = 12, 10
local KEY_HIRE = { "Z", "X", "C", "V" }
local INK = Color3.fromRGB(11, 14, 26) -- Palette Ink

local function caption(parent: Instance, text: string): (TextLabel, TextLabel)
	local row = Instance.new("Frame")
	row.Name = "Caption"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 15) -- §15ш Ш4: заголовки групп — 12 (было 11)
	row.LayoutOrder = 0
	row.Parent = parent
	local left = MenuKit.label(row, text, 12, Theme.Colors.Muted, true)
	local right = MenuKit.label(row, "", 12, Theme.Colors.Sky, true)
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.TextXAlignment = Enum.TextXAlignment.Right
	return left, right
end

function CommandBar.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, deps: Deps): CommandBar
	local cfg = Config.Render.CommandBar
	local slotW, slotH = cfg.SlotW, cfg.SlotH
	local contentH = math.max(cfg.HeightPx - 2 * PAD, 18 + slotH)
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local function signed(n: number): string
		return (if n >= 0 then "+" else "") .. Strings.formatInt(n) .. t("res.perSec")
	end

	local root = Instance.new("Frame")
	root.Name = "CommandBar"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -cfg.BottomPx)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundColor3 = Theme.Colors.Backdrop
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Active = true -- клики по полосе не уходят в карту
	root.Visible = false
	root.Parent = gui
	MenuKit.corner(root, 10)
	MenuKit.stroke(root, Theme.Colors.PanelBorder, 2)
	MenuKit.pad(root, PAD, PAD)
	local list = MenuKit.list(root, GAP, true)
	list.Wraps = true
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local function section(name: string, width: number, order: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.LayoutOrder = order
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromOffset(width, contentH)
		f.Parent = root
		MenuKit.list(f, 3)
		return f
	end
	local function divider(order: number): Frame
		local d = Instance.new("Frame")
		d.Name = "Divider"
		d.LayoutOrder = order
		d.Size = UDim2.fromOffset(1, contentH - 8)
		d.BackgroundColor3 = Theme.Colors.Slate
		d.BorderSizePixel = 0
		d.Parent = root
		return d
	end

	-- Подсказка над клеткой.
	local tip = Instance.new("TextLabel")
	tip.Name = "CommandTip"
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Size = UDim2.fromOffset(0, 0)
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.BackgroundColor3 = Theme.Colors.PanelBg
	tip.BorderSizePixel = 0
	tip.FontFace = Theme.Font
	tip.TextSize = 13
	tip.RichText = true
	tip.TextColor3 = Theme.Colors.Text
	tip.TextXAlignment = Enum.TextXAlignment.Left
	tip.Visible = false
	tip.ZIndex = 30
	tip.Parent = gui
	MenuKit.corner(tip, 6)
	MenuKit.stroke(tip, Theme.Colors.PanelBorder)
	MenuKit.pad(tip, 10, 6)
	local tipFor: GuiObject? = nil
	local tipText: { [GuiObject]: () -> string } = {}
	local touchTipUntil: number? = nil -- §15ш Ш4: подсказка, открытая касанием (на телефоне нет наведения)
	local function withTip(g: GuiObject, text: () -> string)
		tipText[g] = text
		Session.connect(g.MouseEnter, function()
			tipFor = g
			touchTipUntil = nil
		end)
		Session.connect(g.InputBegan, function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				tipFor = g
				touchTipUntil = os.clock() + Config.Render.TouchTipSec
			end
		end)
		Session.connect(g.MouseLeave, function()
			if tipFor == g then
				tipFor = nil
			end
		end)
	end

	-- 1. Держава.
	local nation = section("Nation", NATION_W, 1)
	caption(nation, t("bar.nation"))
	local nameRow = MenuKit.box(nation, "Name", 1)
	MenuKit.list(nameRow, 6, true)
	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(14, 14)
	swatch.BorderSizePixel = 0
	swatch.LayoutOrder = 1
	swatch.Parent = nameRow
	MenuKit.corner(swatch, 3)
	local nameLabel = MenuKit.label(nameRow, "", 15, Theme.Colors.Text, true, 2)
	nameLabel.AutomaticSize = Enum.AutomaticSize.Y
	nameLabel.Size = UDim2.fromOffset(NATION_W - 20, 0)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local worldLabel = MenuKit.label(nation, "", 13, Theme.Colors.Sky, true, 2)
	divider(2)

	-- 2. Люди.
	local people = section("People", PEOPLE_W, 3)
	local _, growthLabel = caption(people, t("bar.people"))
	local peopleLabel = MenuKit.label(people, "", 18, Theme.Colors.Text, true, 1)
	local gauge = Instance.new("Frame")
	gauge.Name = "Gauge"
	gauge.LayoutOrder = 2
	gauge.Size = UDim2.new(1, 0, 0, 8)
	gauge.BackgroundColor3 = Theme.Colors.PanelBg
	gauge.BorderSizePixel = 0
	gauge.Parent = people
	MenuKit.corner(gauge, 4)
	local zone = Config.Render.PeopleZone
	local band = Instance.new("Frame")
	band.BorderSizePixel = 0
	band.BackgroundColor3 = Theme.Colors.Good
	band.BackgroundTransparency = 0.6
	band.Position = UDim2.fromScale(zone[1], 0)
	band.Size = UDim2.fromScale(zone[2] - zone[1], 1)
	band.Parent = gauge
	local peopleFill = Instance.new("Frame")
	peopleFill.BorderSizePixel = 0
	peopleFill.Size = UDim2.fromScale(0, 1)
	peopleFill.ZIndex = 2
	peopleFill.Parent = gauge
	MenuKit.corner(peopleFill, 4)
	withTip(people, function(): string
		return t("bar.peopleTip")
	end)
	divider(4)

	-- 3. Атака: кнопки долей.
	local attack = section("Attack", ATTACK_W, 5)
	local _, attackPercent = caption(attack, t("bar.attack"))
	attackPercent.TextColor3 = Theme.Colors.Gold
	local buttonsRow = MenuKit.box(attack, "Percents", 1)
	MenuKit.list(buttonsRow, 4, true)
	type PercentButton = { button: TextButton, value: number }
	local percentButtons: { PercentButton } = {}
	local buttonW = (ATTACK_W - 4 * (#cfg.Percents - 1)) // #cfg.Percents
	for k, value in cfg.Percents do
		local b = Instance.new("TextButton")
		b.Name = "P" .. math.round(value * 100)
		b.LayoutOrder = k
		b.Size = UDim2.fromOffset(buttonW, 24)
		b.BackgroundColor3 = Theme.Colors.Slate
		b.BorderSizePixel = 0
		b.FontFace = Theme.FontBold
		b.TextSize = 13
		b.TextColor3 = Theme.Colors.Text
		b.Text = string.format("%d%%", math.round(value * 100))
		b.Parent = buttonsRow
		MenuKit.corner(b, 4)
		Session.connect(b.Activated, function()
			deps.setPercent(value)
		end)
		withTip(b, function(): string
			return t("bar.attackTip")
		end)
		table.insert(percentButtons, { button = b, value = value })
	end
	local sendsLabel = MenuKit.label(attack, "", 13, Theme.Colors.Muted, false, 2)
	divider(6)

	-- 4. Деньги и нефть.
	local money = section("Money", MONEY_W, 7)
	local _, incomeLabel = caption(money, t("bar.money"))
	local moneyLabel = MenuKit.label(money, "", 18, Theme.Colors.Gold, true, 1)
	local oilLabel = MenuKit.label(money, "", 13, Theme.Colors.Muted, false, 2)
	-- §15ц Ц5в: на узком экране этот разделитель — линия во всю ширину: дальше вторая строка полосы.
	local rowBreak = divider(8)

	-- §15ц Ц3 клетка: значок своим цветом вида, под ним короткое название; клавиша — в левом верхнем уголке,
	-- цена — в правом; не хватает денег — блёкло, нет технологии или казарм — замок вместо цены.
	type Slot =
		{ button: TextButton, icon: Frame?, price: TextLabel, badge: TextLabel, name: TextLabel, edge: UIStroke }
	local function makeSlot(parent: Instance, name: string, order: number, key: string?, short: string): Slot
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = ""
		b.LayoutOrder = order
		b.Size = UDim2.fromOffset(slotW, slotH)
		b.BackgroundColor3 = Theme.Colors.PanelBg
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.Parent = parent
		MenuKit.corner(b, 6)
		local edge = MenuKit.stroke(b, Theme.Colors.Slate, 2)
		local price = MenuKit.label(b, "", 11, Theme.Colors.Gold, true) -- §15ш Ш4: было 10
		price.AnchorPoint = Vector2.new(1, 0)
		price.Position = UDim2.new(1, -3, 0, 1)
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.TextStrokeTransparency = 0.3
		price.ZIndex = 3
		local badge = MenuKit.label(b, key or "", 12, Theme.Colors.Gold, true)
		badge.Position = UDim2.fromOffset(4, 1)
		badge.TextStrokeTransparency = 0.3
		badge.ZIndex = 3
		badge.Visible = key ~= nil
		local caption2 = Instance.new("TextLabel")
		caption2.Name = "Short"
		caption2.BackgroundTransparency = 1
		caption2.AnchorPoint = Vector2.new(0.5, 1)
		caption2.Position = UDim2.new(0.5, 0, 1, -2)
		caption2.Size = UDim2.new(1, -4, 0, 13)
		caption2.FontFace = Theme.FontBold
		caption2.Text = short
		caption2.TextColor3 = Theme.Colors.Text
		caption2.TextScaled = true
		caption2.ZIndex = 3
		caption2.Parent = b
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 12
		limit.MinTextSize = 7
		limit.Parent = caption2
		return { button = b, icon = nil, price = price, badge = badge, name = caption2, edge = edge }
	end
	local function dim(s: Slot, on: boolean)
		local icon = s.icon
		if icon ~= nil then
			for _, f in icon:GetChildren() do
				if f:IsA("Frame") then
					f.BackgroundTransparency = if on then 0.6 else 0
				end
			end
		end
		s.price.TextColor3 = if on then Theme.Colors.Muted else Theme.Colors.Gold
		s.name.TextColor3 = if on then Theme.Colors.Muted else Theme.Colors.Text
	end
	-- Значок (¾ размера) по центру клетки: сверху строка «клавиша · цена», под значком — название.
	local function placeIcon(s: Slot, icon: Frame)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 14)
		local fit = Instance.new("UIScale")
		fit.Scale = 0.75
		fit.Parent = icon
		s.icon = icon
	end
	local function slotsRow(parent: Instance, name: string): Frame
		local row = MenuKit.box(parent, name, 1)
		MenuKit.list(row, 4, true)
		return row
	end

	-- Значок юнита 12×10 цветом державы (как на карте).
	local function unitIcon(parent: Instance, unit: string, color: Color3): Frame
		local k = 3
		local root2 = Instance.new("Frame")
		root2.Name = "Icon"
		root2.BackgroundTransparency = 1
		root2.AnchorPoint = Vector2.new(0.5, 0)
		root2.Position = UDim2.new(0.5, 0, 0, 3)
		root2.Size = UDim2.fromOffset(UnitSprites.Width * k, UnitSprites.Height * k)
		root2.Parent = parent
		local r, g, b = math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255)
		local shape: { UnitSprites.Part } = UnitSprites.Shapes[unit] or {}
		for _, p in shape do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = if p.ink then INK else Color3.fromRGB(UnitSprites.shade(r, g, b, p.shade))
			f.Position = UDim2.fromOffset(p.x * k, p.y * k)
			f.Size = UDim2.fromOffset(p.w * k, p.h * k)
			f.Parent = root2
		end
		return root2
	end

	-- 5. Войска: найм Z / X / C / V; в заголовке справа — «в армии N» (без войск — красное «нет войск»).
	local hire = section("Hire", 4 * slotW + 3 * 4, 9)
	local _, armyLabel = caption(hire, t("bar.forces"))
	withTip(armyLabel.Parent :: Frame, function(): string
		return deps.armyTip()
	end)
	local hireRow = slotsRow(hire, "Slots")
	local hireSlots: { Slot } = {}
	local queueBadges: { TextLabel } = {}
	for k, unit in Types.LandUnits do
		local s = makeSlot(hireRow, "Hire" .. unit, k, KEY_HIRE[k], t("unit." .. unit .. ".short"))
		placeIcon(s, unitIcon(s.button, unit, Theme.color(cfg.UnitColors[unit])))
		local q = MenuKit.label(s.button, "", 11, Theme.Colors.Sky, true)
		q.AnchorPoint = Vector2.new(1, 1)
		q.Position = UDim2.new(1, -3, 1, -14)
		q.TextStrokeTransparency = 0.3
		q.ZIndex = 3
		table.insert(queueBadges, q)
		Session.connect(s.button.Activated, function()
			deps.hire(k)
		end)
		withTip(s.button, function(): string
			local info = deps.hireInfo(k)
			local line = string.format(t("hire.money"), Strings.formatInt(info.cost))
			if info.oil > 0 then
				line ..= " · " .. string.format(t("hire.oil"), Strings.formatInt(info.oil))
			end
			local second = if info.needLevel ~= nil
				then string.format(t("hire.needBarracks"), info.needLevel)
				else string.format(t("hire.cost"), Strings.formatInt(info.people), info.sec)
			return string.format(
				"<b>%s</b> [%s]\n%s · %s",
				Strings.get("unit." .. unit, lang),
				KEY_HIRE[k],
				line,
				second
			)
		end)
		table.insert(hireSlots, s)
	end
	divider(10)

	-- 6. Стройка: все здания; первые 10 — клавиши 1–0.
	local buildKinds: { Types.BuildingKind } = {}
	for _, raw in Config.Buildable do
		local kind: Types.BuildingKind = raw :: any
		table.insert(buildKinds, kind)
	end
	local build = section("Build", #buildKinds * slotW + (#buildKinds - 1) * 4, 11)
	caption(build, t("bar.build"))
	local buildRow = slotsRow(build, "Slots")
	local buildSlots: { Slot } = {}
	for k, kind: Types.BuildingKind in buildKinds do
		local key = if k <= 9 then tostring(k) elseif k == 10 then "0" else nil
		local s = makeSlot(buildRow, "Build" .. kind, k, key, t("building." .. kind .. ".short"))
		local kindColor: string = (cfg.KindColors :: { [string]: string })[kind] or "Mist"
		placeIcon(s, deps.buildIcon(s.button, kind, Theme.color(kindColor)))
		Session.connect(s.button.Activated, function()
			deps.build.pick(kind)
		end)
		withTip(s.button, function(): string
			local price = deps.build.price(kind)
			local head = string.format(
				"<b>%s</b>%s  $%s",
				Strings.get("building." .. kind, lang),
				if key ~= nil then " [" .. key .. "]" else "",
				Strings.formatInt(price or 0)
			)
			local hint = if deps.build.unlocked(kind)
				then Strings.get("building." .. kind .. ".hint", lang)
				else t("build.locked")
			return head .. "\n" .. hint
		end)
		table.insert(buildSlots, s)
	end
	divider(12)

	-- 7. Арсенал (§15л ч.6): значок взятого в бой предмета; применён — притушен.
	local arsenalButton, arsenalSlot = MenuKit.tile(root, "Arsenal", t("bar.arsenal"), contentH, 13)
	arsenalButton.Size = UDim2.fromOffset(SHOP_W, contentH)
	arsenalButton.Visible = false
	local arsenalIcons: { [string]: Frame } = {}
	for key, icon in deps.arsenal.icons do
		local f = MenuKit.icon(arsenalSlot, icon, 3)
		MenuKit.center(f)
		f.Visible = false
		arsenalIcons[key] = f
	end
	Session.connect(arsenalButton.Activated, deps.arsenal.use)

	-- 8. Магазин.
	local shopButton, shopSlot = MenuKit.tile(root, "Shop", t("bar.shop"), contentH, 14)
	shopButton.Size = UDim2.fromOffset(SHOP_W, contentH)
	local shopIcon = MenuKit.icon(shopSlot, "shop", 3)
	MenuKit.center(shopIcon)
	Session.connect(shopButton.Activated, deps.shop)

	-- Ширина: всё в один ряд, ужимаем до MinScale; дальше (и на узком экране) — две строки (PhoneLayout.bar).
	local natural = NATION_W
		+ PEOPLE_W
		+ ATTACK_W
		+ MONEY_W
		+ (4 * slotW + 12)
		+ (#buildKinds * slotW + (#buildKinds - 1) * 4)
		+ 2 * SHOP_W -- арсенал и магазин
		+ GAP
		+ 6 -- шесть разделителей по 1 px
		+ 12 * GAP
		+ 2 * PAD
		+ 4
	-- §15ц Ц5в: нижняя строка на узком экране — войска, стройка, арсенал, магазин.
	local second = (4 * slotW + 12)
		+ (#buildKinds * slotW + (#buildKinds - 1) * 4)
		+ 2 * SHOP_W
		+ 2 -- два разделителя
		+ 4 * GAP
		+ 2 * PAD
		+ 4
	local function fit()
		local size = UiScale.size(gui)
		local narrow = PhoneLayout.narrow(size.X, RunService:IsStudio() and Config.Dev.PhoneLayout)
		local layout = PhoneLayout.bar(natural, second, size.X - 24, narrow)
		scale.Scale = layout.scale
		root.Size = UDim2.fromOffset(layout.width, 0)
		-- Две строки: разделитель после «Деньги» — линия во всю ширину (перенос), одна — обычная черта.
		rowBreak.Size = if layout.rows == 2 then UDim2.new(1, 0, 0, 1) else UDim2.fromOffset(1, contentH - 8)
	end
	UiScale.onResize(gui, fit)
	fit()

	local function myColor(): Color3
		local ci = if cs.myNation ~= nil then ClientState.colorIndexOf(cs, cs.myNation) else 0
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Sky
	end

	local nextAt = 0
	local function update(now: number)
		local v = deps.values()
		local on = v ~= nil and deps.build.canBuild()
		root.Visible = on
		local item, used = deps.arsenal.info()
		arsenalButton.Visible = item ~= nil
		for key, f in arsenalIcons do
			f.Visible = key == item
		end
		arsenalButton.BackgroundTransparency = if used then 0.6 else 0
		arsenalButton.AutoButtonColor = not used
		if not on then
			tip.Visible = false
			return
		end
		-- Подсказка — каждый кадр (идёт за наведённой клеткой).
		local tipEnd = touchTipUntil
		if tipEnd ~= nil and os.clock() > tipEnd then
			touchTipUntil = nil
			tipFor = nil
		end
		local hovered = tipFor
		if hovered ~= nil and hovered.Visible then
			local textFn = tipText[hovered]
			tip.Text = if textFn ~= nil then textFn() else ""
			-- §15ц: слой в масштабе экрана — настоящие пиксели переводим в условные.
			local f = UiScale.factor()
			local p = (hovered.AbsolutePosition - gui.AbsolutePosition) / f
			tip.Position = UDim2.fromOffset(p.X + hovered.AbsoluteSize.X / f / 2, p.Y - 8)
			tip.Visible = tip.Text ~= ""
		else
			tip.Visible = false
		end
		if now < nextAt or v == nil then
			return
		end
		nextAt = now + cfg.RefreshSec

		local color = myColor()
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		swatch.BackgroundColor3 = color
		nameLabel.Text = if me == nil then "" elseif lang == "en" then me.nameEn else me.name
		worldLabel.Text = string.format(t("bar.world"), v.land)

		peopleLabel.Text = Strings.formatInt(v.people) .. " / " .. Strings.formatInt(v.maxPeople)
		growthLabel.Text = signed(v.growth)
		growthLabel.TextColor3 = if v.growth >= 0 then Theme.Colors.Sky else Theme.Colors.Alert
		local share = if v.maxPeople > 0 then math.clamp(v.people / v.maxPeople, 0, 1) else 0
		peopleFill.Size = UDim2.fromScale(share, 1)
		-- В зелёной зоне — зелёный, ниже — золотой (копим), выше — серый (рост замедлился, пора в атаку).
		peopleFill.BackgroundColor3 = if share < zone[1]
			then Theme.Colors.Gold
			elseif share <= zone[2] then Theme.Colors.Good
			else Theme.Colors.Muted

		local pct = deps.percent()
		attackPercent.Text = string.format("%d%%", math.round(pct * 100))
		for _, pb in percentButtons do
			local active = math.abs(pb.value - pct) < 0.001
			pb.button.BackgroundColor3 = if active then Theme.Colors.Gold else Theme.Colors.Slate
			pb.button.TextColor3 = if active then INK else Theme.Colors.Text
		end
		sendsLabel.Text = string.format(t("bar.sends"), Strings.formatInt(math.floor(v.people * pct)))

		moneyLabel.Text = "$" .. Strings.formatInt(v.money)
		incomeLabel.Text = signed(v.income)
		incomeLabel.TextColor3 = if v.income >= 0 then Theme.Colors.Sky else Theme.Colors.Alert
		oilLabel.Text = string.format(t("bar.oil"), Strings.formatInt(v.oil)) .. "  " .. signed(v.oilIncome)

		local home, front = deps.army()
		local total = math.floor(home + front)
		armyLabel.Text = if total >= 1 then string.format(t("bar.army"), Strings.formatInt(total)) else t("bar.noArmy")
		armyLabel.TextColor3 = if total >= 1 then Theme.Colors.Sky else Theme.Colors.Alert
		for k, s in hireSlots do
			local info = deps.hireInfo(k)
			-- §15ш Ш2: причина замка — на клетке (на телефоне подсказки по наведению нет).
			s.price.Text = if info.needLevel ~= nil
				then string.format(t("bar.lockLevel"), info.needLevel :: number)
				else "$" .. Strings.formatInt(info.cost)
			queueBadges[k].Text = if info.queued > 0 then string.format(t("bar.queued"), info.queued) else ""
			dim(s, not info.affordable)
		end
		local selected = deps.build.selected()
		for k, s in buildSlots do
			local kind: Types.BuildingKind = buildKinds[k]
			local price = deps.build.price(kind)
			local unlocked = deps.build.unlocked(kind)
			s.price.Text = if not unlocked
				then t("bar.lockTech")
				elseif price ~= nil then "$" .. Strings.formatInt(price)
				else ""
			dim(s, not unlocked or price == nil or v.money < price)
			s.edge.Color = if selected == kind then Theme.Colors.Gold else Theme.Colors.Slate
		end
	end

	return {
		frame = root,
		update = update,
		visible = function(): boolean
			return root.Visible
		end,
	}
end

return table.freeze(CommandBar)
