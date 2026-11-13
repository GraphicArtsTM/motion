--!strict
--[[
	AttackPanel — атаки в матче (GDD §15ф Ф2):
	- справа, под местом «#N · доля», — панель «АТАКИ»: свои атаки (цель, сила, полоса перевеса, «↩» — отозвать) и
	  атаки на вас (кто, сила, полоса обороны, «◎» — камера к фронту). Заголовок со счётом; нажатие на заголовок
	  сворачивает список. Нет атак — панели нет.
	- над нижней полосой по центру — фишки своих атак «сила · цель ×» (× — отменить). Пока снизу открыто окно
	  (стройка, порт, аэродром…), фишки спрятаны — окна стоят там же.
	Что показать и в каком порядке — чистый AttackList. Строки — пул (кнопки не пересоздаются).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AttackList = require(Shared:WaitForChild("AttackList"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type AttackPanel = {
	update: (now: number) -> (),
	setBlocked: (blocked: boolean) -> (), -- снизу открыто окно — фишки прячем
	setCollapsed: (collapsed: boolean) -> (), -- §15ц Ц5в: на узком экране панель стартует свёрнутой
	list: Frame, -- «Attacks» (справа, в столбике TopRight)
	chips: Frame, -- «AttackChips» (над полосой, ставит aboveBar)
}

local AttackPanel = {}

local function nationColor(cs: ClientState, id: number): Color3
	local n = cs.nations[id]
	if n == nil or n.colorIndex < 1 then
		return Theme.Colors.Muted
	end
	local c = NationColors.Colors[n.colorIndex]
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function escape(s: string): string
	return (string.gsub(s, "[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

local function powerText(p: number): string
	return if p < 0 then "?" else Strings.formatInt(p)
end

function AttackPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	show: (cell: number) -> () -- камера к клетке
): AttackPanel
	local cfg = Config.Render.AttackList
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local function nameOf(id: number): string
		if id == 0 then
			return t("hud.neutral")
		end
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end

	-- Панель «АТАКИ» справа.
	local list = Instance.new("Frame")
	list.Name = "Attacks"
	list.Size = UDim2.fromOffset(cfg.WidthPx, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundColor3 = Theme.Colors.PanelBg
	list.BackgroundTransparency = Theme.PanelAlpha
	list.BorderSizePixel = 0
	list.Visible = false
	list.Parent = gui
	MenuKit.corner(list, Theme.CornerPx)
	MenuKit.stroke(list, Theme.Colors.PanelBorder, 1)
	MenuKit.pad(list, 10, 8)
	MenuKit.list(list, 6)

	local head = Instance.new("TextButton")
	head.Name = "Head"
	head.Text = ""
	head.AutoButtonColor = false
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 24)
	head.LayoutOrder = 0
	head.Parent = list
	local title = MenuKit.label(head, "⚔  " .. t("attacks.title"), 14, Theme.Colors.Gold, true)
	title.Position = UDim2.fromOffset(0, 3)
	local count = MenuKit.label(head, "", 12, Theme.Colors.Muted, false)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, 0, 0, 5)
	count.TextXAlignment = Enum.TextXAlignment.Right
	local collapsed = false

	type Row = {
		frame: Frame,
		mark: TextLabel,
		name: TextLabel,
		power: TextLabel,
		bar: MenuKit.Bar,
		action: TextButton,
		kind: AttackList.Kind,
		other: number,
		focus: number?,
	}
	local rows: { Row } = {}
	for k = 1, cfg.MaxRows do
		local f = Instance.new("Frame")
		f.Name = "Row" .. k
		f.Size = UDim2.new(1, 0, 0, cfg.RowPx)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BackgroundTransparency = 0.2
		f.BorderSizePixel = 0
		f.LayoutOrder = k
		f.Visible = false
		f.Parent = list
		MenuKit.corner(f, 6)
		local mark = MenuKit.label(f, "⚔", 16, Theme.Colors.Sky, true)
		mark.Position = UDim2.fromOffset(8, 6)
		local name = MenuKit.label(f, "", 14, Theme.Colors.Text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(30, 6)
		name.Size = UDim2.new(1, -30 - 8 - cfg.RowPx - 70, 0, 18)
		local power = MenuKit.label(f, "", 14, Theme.Colors.Gold, true)
		power.AnchorPoint = Vector2.new(1, 0)
		power.Position = UDim2.new(1, -(cfg.RowPx + 4), 0, 6)
		power.TextXAlignment = Enum.TextXAlignment.Right
		local barHost = Instance.new("Frame")
		barHost.BackgroundTransparency = 1
		barHost.Position = UDim2.new(0, 30, 1, -12)
		barHost.Size = UDim2.new(1, -30 - cfg.RowPx - 4, 0, 4)
		barHost.Parent = f
		local bar = MenuKit.bar(barHost, 4, Theme.Colors.Sky)
		local action = Instance.new("TextButton")
		action.Name = "Action"
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, -4, 0.5, 0)
		action.Size = UDim2.fromOffset(cfg.RowPx - 8, cfg.RowPx - 8)
		action.BackgroundColor3 = Theme.Colors.PanelBg
		action.BorderSizePixel = 0
		action.FontFace = Theme.FontBold
		action.TextSize = 18
		action.TextColor3 = Theme.Colors.Text
		action.Text = "↩"
		action.Parent = f
		MenuKit.corner(action, 6)
		MenuKit.stroke(action, Theme.Colors.PanelBorder, 1)
		local row: Row = {
			frame = f,
			mark = mark,
			name = name,
			power = power,
			bar = bar,
			action = action,
			kind = "out",
			other = -1,
			focus = nil,
		}
		Session.connect(action.Activated, function()
			if row.other < 0 then
				return
			end
			if row.kind == "out" then
				send("cancel", { target = row.other }) -- отозвать: войска возвращаются домой
			else
				local cell = row.focus
				if cell == nil then
					local n = cs.nations[row.other]
					cell = if n ~= nil then n.capital else nil
				end
				if cell ~= nil then
					show(cell)
				end
			end
		end)
		table.insert(rows, row)
	end
	local more = MenuKit.label(list, "", 12, Theme.Colors.Muted, false, cfg.MaxRows + 1)
	Session.connect(head.Activated, function()
		collapsed = not collapsed
	end)

	-- Фишки своих атак над полосой.
	local chips = Instance.new("Frame")
	chips.Name = "AttackChips"
	chips.BackgroundTransparency = 1
	chips.AnchorPoint = Vector2.new(0.5, 1)
	chips.Position = UDim2.new(0.5, 0, 1, -100)
	chips.Size = UDim2.fromOffset(0, cfg.ChipPx)
	chips.AutomaticSize = Enum.AutomaticSize.X
	chips.Visible = false
	chips.Parent = gui
	MenuKit.list(chips, 8, true)
	type Chip = { frame: Frame, text: TextLabel, close: TextButton, target: number }
	local chipPool: { Chip } = {}
	for k = 1, cfg.MaxChips do
		local f = Instance.new("Frame")
		f.Name = "Chip" .. k
		f.Size = UDim2.fromOffset(0, cfg.ChipPx)
		f.AutomaticSize = Enum.AutomaticSize.X
		f.BackgroundColor3 = Theme.Colors.PanelBg
		f.BackgroundTransparency = Theme.PanelAlpha
		f.BorderSizePixel = 0
		f.LayoutOrder = k
		f.Visible = false
		f.Parent = chips
		MenuKit.corner(f, 6)
		MenuKit.stroke(f, Theme.Colors.Sky, 1)
		local inner = MenuKit.list(f, 8, true)
		inner.VerticalAlignment = Enum.VerticalAlignment.Center
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 10)
		p.PaddingRight = UDim.new(0, 4)
		p.Parent = f
		local text = MenuKit.label(f, "", 14, Theme.Colors.Text, true, 1)
		local close = Instance.new("TextButton")
		close.Name = "Cancel"
		close.LayoutOrder = 2
		close.Size = UDim2.fromOffset(cfg.ChipPx - 6, cfg.ChipPx - 6)
		close.BackgroundTransparency = 1
		close.FontFace = Theme.FontBold
		close.TextSize = 18
		close.TextColor3 = Theme.Colors.Alert
		close.Text = "×"
		close.Parent = f
		local chip: Chip = { frame = f, text = text, close = close, target = -1 }
		Session.connect(close.Activated, function()
			if chip.target >= 0 then
				send("cancel", { target = chip.target })
			end
		end)
		table.insert(chipPool, chip)
	end

	local blocked = false
	local nextAt = 0
	local function update(now: number)
		if now < nextAt then
			return
		end
		nextAt = now + cfg.RefreshSec
		local stats = cs.stats
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local playing = cs.phase == "Play" and stats ~= nil and me ~= nil and me.alive
		local attacks: { AttackList.Attack } = if playing and stats ~= nil then stats.attacks :: any else {}
		local myId = if playing then cs.myNation else nil
		local shown, counts = AttackList.rows(attacks, myId, cfg.MaxRows)
		list.Visible = #shown > 0
		count.Text = string.format(t("attacks.count"), counts.out, counts.inc)
			.. (if collapsed then "  ▸" else "  ▾")
		for k, row in rows do
			local r = shown[k]
			if r == nil or collapsed then
				row.frame.Visible = false
				row.other = -1
			else
				row.frame.Visible = true
				row.kind, row.other, row.focus = r.kind, r.other, r.focus
				local out = r.kind == "out"
				row.mark.Text = if out then "⚔" else "⚠"
				row.mark.TextColor3 = if out then Theme.Colors.Sky else Theme.Colors.Alert
				row.name.Text = (if out then "→ " else "← ") .. escape(nameOf(r.other))
				row.name.TextColor3 = if r.other == 0 then Theme.Colors.Muted else nationColor(cs, r.other)
				row.power.Text = powerText(r.power)
				row.bar.set(r.share)
				-- Голубая — наша сторона берёт верх, красная — уступает.
				local winning = (out and r.advancing) or (not out and not r.advancing)
				row.bar.fill.BackgroundColor3 = if winning then Theme.Colors.Sky else Theme.Colors.Alert
				row.action.Text = if out then "↩" else "◎"
				row.action.TextColor3 = if out then Theme.Colors.Gold else Theme.Colors.Text
			end
		end
		more.Visible = not collapsed and counts.hidden > 0
		more.Text = string.format(t("attacks.more"), counts.hidden)

		local own = AttackList.chips(attacks, myId, cfg.MaxChips)
		chips.Visible = #own > 0 and not blocked
		for k, chip in chipPool do
			local r = own[k]
			if r == nil then
				chip.frame.Visible = false
				chip.target = -1
			else
				chip.frame.Visible = true
				chip.target = r.other
				chip.text.Text = string.format(
					'<font color="#%s">%s</font>  %s',
					Theme.Colors.Sky:ToHex(),
					powerText(r.power),
					escape(nameOf(r.other))
				)
			end
		end
	end

	return {
		update = update,
		setBlocked = function(b: boolean)
			if blocked ~= b then
				blocked = b
				nextAt = 0
			end
		end,
		setCollapsed = function(c: boolean)
			if collapsed ~= c then
				collapsed = c
				nextAt = 0
			end
		end,
		list = list,
		chips = chips,
	}
end

return table.freeze(AttackPanel)
