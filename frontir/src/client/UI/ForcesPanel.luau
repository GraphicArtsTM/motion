--!strict
--[[
	ForcesPanel — войска державы в интерфейсе (GDD §6.6, §10, модель «Фронты»):
	- снизу по центру — карточки найма (пехота, танки, артиллерия, ПВО; клавиши Z/X/C/V), на карточке
	  клавиша, цена в людях, время найма и сколько таких юнитов уже в очереди;
	- справа — панель «Войска»: общая сила, по типам — звёзды ветеранов, сила дома и на фронтах,
	  очередь найма с оставшимся временем.
	Войска — общая боевая мощь державы, отрядами вручную не управляют: при атаке на державу доля войск
	(ползунок атаки) уходит на фронт сама. Все кнопки от 44 px (телефоны).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Forces = require(Shared:WaitForChild("Forces"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type ForcesPanel = {
	refresh: () -> (),
}

local ForcesPanel = {}

local CARD_W, CARD_H = 172, 56
-- Клавиши найма по порядку Types.LandUnits (GDD §10: Z/X/C/V; WASD занята камерой).
local KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V }
local KEY_NAMES = { "Z", "X", "C", "V" }

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function makeCard(parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(CARD_W, CARD_H)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.RichText = true
	b.FontFace = Theme.FontBold
	b.TextSize = 15
	b.TextColor3 = Theme.Colors.Text
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = b
	b.Parent = parent
	return b
end

function ForcesPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): ForcesPanel
	local gold, sky, muted, alert =
		hex(Theme.Colors.Gold), hex(Theme.Colors.Sky), hex(Theme.Colors.Muted), hex(Theme.Colors.Alert)

	local function canCommand(): boolean
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return cs.phase == "Play" and me ~= nil and me.alive
	end

	local function hire(k: number)
		if canCommand() then
			send("hire", { unit = Types.LandUnits[k] })
		end
	end

	-- Снизу по центру: карточки найма.
	local cards = Instance.new("Frame")
	cards.Name = "HireCards"
	cards.BackgroundTransparency = 1
	cards.Size = UDim2.fromOffset(0, CARD_H)
	cards.AutomaticSize = Enum.AutomaticSize.X
	cards.Parent = gui
	local cardsLayout = Instance.new("UIListLayout")
	cardsLayout.FillDirection = Enum.FillDirection.Horizontal
	cardsLayout.Padding = UDim.new(0, 6)
	cardsLayout.Parent = cards
	-- Узкий экран (телефон): по центру карточки налезут на ползунок атаки слева — прижимаем вправо
	-- и складываем в две строки.
	local function placeCards()
		if gui.AbsoluteSize.X < Config.Render.NarrowScreenPx then
			cards.AnchorPoint = Vector2.new(1, 1)
			cards.Position = UDim2.new(1, -12, 1, -12)
			cards.AutomaticSize = Enum.AutomaticSize.Y
			cards.Size = UDim2.fromOffset(2 * CARD_W + 6, 0)
			cardsLayout.Wraps = true
		else
			cards.AnchorPoint = Vector2.new(0.5, 1)
			cards.Position = UDim2.new(0.5, 0, 1, -12)
			cards.AutomaticSize = Enum.AutomaticSize.X
			cards.Size = UDim2.fromOffset(0, CARD_H)
			cardsLayout.Wraps = false
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeCards)
	placeCards()

	local cardButtons: { TextButton } = {}
	for k in Types.LandUnits do
		local b = makeCard(cards)
		b.Name = "Hire" .. Types.LandUnits[k]
		b.Activated:Connect(function()
			hire(k)
		end)
		table.insert(cardButtons, b)
	end

	-- Справа по центру: войска.
	local panel = Instance.new("Frame")
	panel.Name = "Forces"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -12, 0.5, 0)
	panel.Size = UDim2.fromOffset(0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = panel
	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.RichText = true
	info.AutomaticSize = Enum.AutomaticSize.XY
	info.Size = UDim2.fromOffset(0, 0)
	info.FontFace = Theme.Font
	info.TextSize = 14
	info.TextColor3 = Theme.Colors.Text
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.Parent = panel

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		for k, key in KEYS do
			if input.KeyCode == key then
				hire(k)
			end
		end
	end)

	local function starsText(n: number): string
		if n <= 0 then
			return ""
		end
		return string.format(' <font color="%s">%s</font>', gold, string.rep("★", n))
	end

	local function refresh()
		local playing = canCommand()
		cards.Visible = playing
		panel.Visible = playing
		if not playing then
			return
		end
		local myStats = if cs.myNation ~= nil then ClientState.statsOf(cs, cs.myNation) else nil
		local forces = cs.myForces
		local queued: { number } = {}
		if forces ~= nil then
			for _, q in forces.queue do
				queued[q.kind] = (queued[q.kind] or 0) + 1
			end
		end

		-- Карточки: клавиша, тип; деньги и нефть, люди и время; без завода техника недоступна.
		local economy = if forces ~= nil then forces.economy else nil
		local hasFactory = economy ~= nil and economy.factories > 0
		for k, b in cardButtons do
			local stats = Forces.stats(k)
			local inQueue = queued[k] or 0
			local needsFactory = stats.requires == "Factory" and not hasFactory
			local price = string.format(Strings.get("hire.money", lang), Strings.formatInt(stats.cost))
			if stats.oil > 0 then
				price ..= " · " .. string.format(Strings.get("hire.oil", lang), Strings.formatInt(stats.oil))
			end
			local second = if needsFactory
				then string.format('<font color="%s">%s</font>', alert, Strings.get("hire.needFactory", lang))
				else string.format(
					'<font color="%s">%s</font> · %s',
					gold,
					price,
					string.format(Strings.get("hire.cost", lang), Strings.formatInt(stats.people), stats.recruitSec)
				)
			b.Text = string.format(
				'<font color="%s">%s</font> %s%s\n<font size="11" color="%s">%s</font>',
				gold,
				KEY_NAMES[k],
				Strings.get("unit." .. Types.LandUnits[k], lang),
				if inQueue > 0 then string.format(' <font color="%s">+%d</font>', sky, inQueue) else "",
				sky,
				second
			)
			local affordable = myStats ~= nil
				and myStats.people >= stats.people
				and economy ~= nil
				and economy.money >= stats.cost
				and economy.oil >= stats.oil
				and not needsFactory
			b.TextTransparency = if affordable then 0 else 0.5
		end

		-- Панель войск.
		local lines: { string } = { "<b>" .. Strings.get("forces.title", lang) .. "</b>" }
		local homeTotal, frontTotal = 0, 0
		if forces ~= nil then
			for k, kf in forces.kinds do
				homeTotal += kf.home
				frontTotal += kf.front
				if kf.home + kf.front >= 1 then
					local stars = Forces.stars({ strength = kf.home, xp = kf.xp })
					table.insert(
						lines,
						string.format(
							Strings.get("forces.kind", lang),
							Strings.get("unit." .. Types.LandUnits[k], lang) .. starsText(stars),
							string.format('<font color="%s">%s</font>', gold, Strings.formatInt(kf.home)),
							string.format('<font color="%s">%s</font>', sky, Strings.formatInt(kf.front))
						)
					)
				end
			end
		end
		if homeTotal + frontTotal < 1 then
			table.insert(lines, string.format('<font color="%s">%s</font>', alert, Strings.get("forces.empty", lang)))
		else
			table.insert(
				lines,
				2,
				string.format(
					Strings.get("forces.total", lang),
					string.format('<font color="%s">%s</font>', gold, Strings.formatInt(homeTotal)),
					string.format('<font color="%s">%s</font>', sky, Strings.formatInt(frontTotal))
				)
			)
		end
		if forces ~= nil and #forces.queue > 0 then
			local items: { string } = {}
			for _, q in forces.queue do
				table.insert(
					items,
					string.format(
						Strings.get("forces.queueItem", lang),
						Strings.get("unit." .. Types.LandUnits[q.kind], lang),
						math.max(1, math.ceil(q.left))
					)
				)
			end
			table.insert(
				lines,
				string.format(
					'<font color="%s">%s</font>',
					sky,
					string.format(Strings.get("forces.queue", lang), table.concat(items, ", "))
				)
			)
		end
		table.insert(
			lines,
			string.format('<font size="12" color="%s">%s</font>', muted, Strings.get("forces.hint", lang))
		)
		info.Text = table.concat(lines, "\n")
	end

	return { refresh = refresh }
end

return table.freeze(ForcesPanel)
