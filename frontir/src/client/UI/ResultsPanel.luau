--!strict
--[[
	ResultsPanel — экран результатов (GDD §8, этап 4в): кто и как победил (заголовок цветом победителя),
	ваше место, места держав, график доли суши за матч (лучшие Render.ResultsChartLines держав).
	Виден в фазе Over; «Смотреть карту» прячет окно, «Итоги» возвращает. Новый матч сбрасывает окно.
	График — линии из повёрнутых Frame (точек не больше Render.ResultsChartPoints на линию).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type ResultsPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
}

local ResultsPanel = {}

local CHART_W, CHART_H = 380, 150
local BUTTON = Config.Render.MinTouchTargetPx

local function escape(s: string): string
	return (
		string.gsub(s, "[&<>\"']", {
			["&"] = "&amp;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function nationColor(cs: ClientState, id: number): Color3
	local n = cs.nations[id]
	if n == nil or n.colorIndex < 1 then
		return Theme.Colors.Text
	end
	local c = NationColors.Colors[n.colorIndex]
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- Доли державы из итога (ключи могут прийти строками после RemoteEvent).
local function sharesOf(result: Types.MatchResult, id: number): { number }?
	local shares = result.shares :: any
	return shares[id] or shares[tostring(id)]
end

local function label(parent: Instance, size: number, order: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.RichText = true
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.fromOffset(0, 0)
	t.FontFace = Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.LayoutOrder = order
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(0, BUTTON)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.FontFace = Theme.FontBold
	b.TextSize = 15
	b.TextColor3 = Theme.Colors.Gold
	b.Text = text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = b
	b.Parent = parent
	return b
end

function ResultsPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang): ResultsPanel
	local muted, gold = hex(Theme.Colors.Muted), hex(Theme.Colors.Gold)

	local panel = Instance.new("Frame")
	panel.Name = "Results"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 6
	panel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Gold
	stroke.Thickness = 2
	stroke.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel
	-- Узкий экран: окно ужимается масштабом, а не вылезает за край.
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local s = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min(s.X / (CHART_W + 60), s.Y / (CHART_H + 330)), 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	local title = label(panel, 26, 1)
	title.FontFace = Theme.FontBold
	local reason = label(panel, 15, 2)
	local yourPlace = label(panel, 17, 3)
	yourPlace.TextColor3 = Theme.Colors.Gold
	local placesText = label(panel, 14, 4)
	local chartTitle = label(panel, 13, 5)
	chartTitle.TextColor3 = Theme.Colors.Muted
	chartTitle.Text = Strings.get("result.chart", lang)
	local chart = Instance.new("Frame")
	chart.Name = "Chart"
	chart.Size = UDim2.fromOffset(CHART_W, CHART_H)
	chart.BackgroundColor3 = Theme.Colors.Backdrop
	chart.BorderSizePixel = 0
	chart.ClipsDescendants = true
	chart.LayoutOrder = 6
	chart.Parent = panel
	local chartStroke = Instance.new("UIStroke")
	chartStroke.Color = Theme.Colors.PanelBorder
	chartStroke.Thickness = Theme.BorderPx
	chartStroke.Parent = chart
	local footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.fromOffset(0, BUTTON)
	footer.AutomaticSize = Enum.AutomaticSize.X
	footer.LayoutOrder = 7
	footer.Parent = panel
	local footerLayout = Instance.new("UIListLayout")
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	footerLayout.Padding = UDim.new(0, 12)
	footerLayout.Parent = footer
	local countdown = label(footer, 14, 1)
	countdown.TextColor3 = Theme.Colors.Muted
	local hideButton = button(footer, Strings.get("result.hide", lang))
	hideButton.LayoutOrder = 2

	-- «Итоги» — вернуть спрятанное окно (по центру сверху, под баннером).
	local showButton = button(gui, Strings.get("result.show", lang))
	showButton.Name = "ShowResults"
	showButton.AnchorPoint = Vector2.new(0.5, 1)
	showButton.Position = UDim2.new(0.5, 0, 1, -12)
	showButton.Visible = false

	local hidden = false
	local builtFor = -1 -- matchId, для которого собрано окно
	Session.connect(hideButton.Activated, function()
		hidden = true
		panel.Visible = false
		showButton.Visible = true
	end)
	Session.connect(showButton.Activated, function()
		hidden = false
		panel.Visible = true
		showButton.Visible = false
	end)

	local function nameOf(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return escape(if lang == "en" then n.nameEn else n.name)
	end

	local function lastShare(result: Types.MatchResult, id: number): number
		local list = sharesOf(result, id)
		return if list ~= nil and #list > 0 then list[#list] else 0
	end

	-- Линия графика: отрезки из тонких повёрнутых рамок.
	local function drawLine(points: { Vector2 }, color: Color3, thick: number)
		for k = 1, #points - 1 do
			local a, b = points[k], points[k + 1]
			local d = b - a
			local seg = Instance.new("Frame")
			seg.BorderSizePixel = 0
			seg.BackgroundColor3 = color
			seg.AnchorPoint = Vector2.new(0.5, 0.5)
			seg.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			seg.Size = UDim2.fromOffset(d.Magnitude + 1, thick)
			seg.Rotation = math.deg(math.atan2(d.Y, d.X))
			seg.Parent = chart
		end
	end

	local function build(result: Types.MatchResult)
		local winnerHex = hex(nationColor(cs, result.winner))
		title.Text = string.format(
			Strings.get("result.title", lang),
			string.format('<font color="%s">%s</font>', winnerHex, nameOf(result.winner))
		)
		reason.Text = if result.reason == "land"
			then string.format(Strings.get("result.land", lang), lastShare(result, result.winner))
			else Strings.get("result." .. result.reason, lang)
		-- Команды (§5.1): побеждает команда; режим — в той же строке.
		local winnerInfo = cs.nations[result.winner]
		if winnerInfo ~= nil and winnerInfo.team ~= nil then
			reason.Text = string.format(Strings.get("result.team", lang), winnerInfo.team, reason.Text)
		end
		reason.Text ..= " · " .. string.format(
			Strings.get("result.mode", lang),
			Strings.get("mode." .. cs.mode.mode, lang)
		)

		local mine = 0
		for place, id in result.places do
			if id == cs.myNation then
				mine = place
			end
		end
		yourPlace.Visible = mine > 0
		yourPlace.Text = string.format(Strings.get("result.yourPlace", lang), mine, #result.places)

		local lines: { string } = {}
		for place = 1, math.min(#result.places, Config.Render.ResultsPlaces) do
			local id = result.places[place]
			local n = cs.nations[id]
			local line = string.format(
				Strings.get("result.place", lang),
				place,
				string.format('<font color="%s">%s</font>', hex(nationColor(cs, id)), nameOf(id)),
				lastShare(result, id)
			)
			if n ~= nil and not n.alive then
				line ..= string.format(' <font color="%s">· %s</font>', muted, Strings.get("result.out", lang))
			end
			if id == cs.myNation then
				line = string.format('<font color="%s">▶</font> %s', gold, line)
			end
			table.insert(lines, line)
		end
		placesText.Text = table.concat(lines, "\n")

		-- График: ось — 0…максимум доли, линии лучших держав (своя тоже, если не в списке).
		for _, child in chart:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local shown: { number } = {}
		for place = 1, math.min(#result.places, Config.Render.ResultsChartLines) do
			table.insert(shown, result.places[place])
		end
		if mine > Config.Render.ResultsChartLines and cs.myNation ~= nil then
			table.insert(shown, cs.myNation)
		end
		local count = #result.times
		if count < 2 then
			return
		end
		local top = 10
		for _, id in shown do
			local list = sharesOf(result, id)
			if list ~= nil then
				for _, v in list do
					top = math.max(top, v)
				end
			end
		end
		-- Не больше ResultsChartPoints точек на линию: шаг по индексам, последняя точка всегда своя.
		local step = math.max(1, math.ceil(count / Config.Render.ResultsChartPoints))
		local idx: { number } = {}
		for k = 1, count, step do
			table.insert(idx, k)
		end
		if idx[#idx] ~= count then
			table.insert(idx, count)
		end
		local t0, t1 = result.times[1], math.max(result.times[count], result.times[1] + 1)
		for order = #shown, 1, -1 do -- победитель рисуется последним, поверх
			local id = shown[order]
			local list = sharesOf(result, id)
			if list ~= nil then
				local points: { Vector2 } = {}
				for _, k in idx do
					local v = list[k]
					if v ~= nil then
						local x = (result.times[k] - t0) / (t1 - t0) * (CHART_W - 4) + 2
						local y = CHART_H - 2 - v / top * (CHART_H - 6)
						table.insert(points, Vector2.new(x, y))
					end
				end
				drawLine(points, nationColor(cs, id), if id == result.winner or id == cs.myNation then 3 else 2)
			end
		end
	end

	local function refresh()
		local result = cs.result
		local over = cs.phase == "Over" and result ~= nil
		if not over then
			hidden = false
			builtFor = -1
			panel.Visible = false
			showButton.Visible = false
			return
		end
		if result ~= nil and builtFor ~= cs.matchId then
			builtFor = cs.matchId
			build(result)
		end
		panel.Visible = not hidden
		showButton.Visible = hidden
	end

	local lastLeft = -1
	local function update(now: number)
		if not panel.Visible then
			return
		end
		local left = math.max(0, math.ceil(cs.phaseEndsAt - now))
		if left ~= lastLeft then
			lastLeft = left
			countdown.Text = string.format(Strings.get("result.next", lang), left)
		end
	end

	return { refresh = refresh, update = update }
end

return table.freeze(ResultsPanel)
