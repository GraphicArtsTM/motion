--!strict
--[[
	ResultsPanel — итоги матча одной карточкой (GDD §8, этап 4в; вид — §15л; §15ф Ф2): крупно «ПОБЕДА» /
	«ПОРАЖЕНИЕ» / «ИТОГИ» (зритель), кто и как победил; плитки 2×2 — «Место», «Пик суши», «Побеждено вами»
	(MatchResult.defeated), «Время матча»; награда за матч (опыт, медали, новый уровень) и полоса уровня; большая
	«В МЕНЮ», под ней «Смотреть карту» (прячет окно, «Итоги» возвращает) и «Подробнее» — места держав и график доли
	суши за матч (лучшие Render.ResultsChartLines держав), по умолчанию свёрнуты. Виден в фазе Over. Новый матч
	сбрасывает окно.
	График — линии из повёрнутых Frame (точек не больше Render.ResultsChartPoints на линию).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Ranks = require(Shared:WaitForChild("Ranks"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type ResultsPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
}

local ResultsPanel = {}

local TILE_W, TILE_H, TILE_GAP = 220, 64, 8
local PLACE_H = 40
local TILES_W = 2 * TILE_W + TILE_GAP -- ширина карточки (плитки 2×2)
local CHART_W, CHART_H = TILES_W, 150
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

-- Сколько держав выбила держава (§15ф Ф2; ключи могут прийти строками после RemoteEvent).
local function defeatedOf(result: Types.MatchResult, id: number): number
	local d = result.defeated :: any
	if d == nil then
		return 0
	end
	return d[id] or d[tostring(id)] or 0
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

function ResultsPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, onMenu: () -> ()): ResultsPanel
	local muted = hex(Theme.Colors.Muted)

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
	local expanded = false -- «Подробнее»: места и график
	local function fit()
		local s = gui.AbsoluteSize
		local h = if expanded then CHART_H + 640 else 520
		scale.Scale = math.clamp(math.min(s.X / (TILES_W + 60), s.Y / h), 0.45, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()

	-- Заголовок и «кто победил» — по центру карточки, строка переносится, а не раздвигает окно.
	local title = label(panel, 40, 1)
	title.FontFace = Theme.FontHeavy
	title.TextStrokeTransparency = 0.5
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.Size = UDim2.fromOffset(TILES_W, 0)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local reason = label(panel, 14, 2)
	reason.TextColor3 = Theme.Colors.Muted
	reason.AutomaticSize = Enum.AutomaticSize.Y
	reason.Size = UDim2.fromOffset(TILES_W, 0)
	reason.TextWrapped = true
	reason.TextXAlignment = Enum.TextXAlignment.Center
	-- Плитки: место, пик суши, время, выбыло держав (§15л).
	local tilesRow = Instance.new("Frame")
	tilesRow.Name = "Tiles"
	tilesRow.BackgroundTransparency = 1
	tilesRow.Size = UDim2.fromOffset(TILES_W, 2 * TILE_H + TILE_GAP)
	tilesRow.LayoutOrder = 3
	tilesRow.Parent = panel
	local tilesGrid = Instance.new("UIGridLayout")
	tilesGrid.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	tilesGrid.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	tilesGrid.SortOrder = Enum.SortOrder.LayoutOrder
	tilesGrid.Parent = tilesRow
	-- Плитка: картинка слева, подпись и число справа (§15л ч.11).
	local function tile(order: number, artKey: string, caption: string): TextLabel
		local f = Instance.new("Frame")
		f.Name = "Tile"
		f.LayoutOrder = order
		f.Size = UDim2.fromOffset(TILE_W, TILE_H)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = tilesRow
		MenuKit.stroke(f, Theme.Colors.PanelBorder, 2)
		local art = CardKit.art(f, artKey, 66, 44)
		art.Position = UDim2.fromOffset(6, 8)
		local cap = MenuKit.label(f, caption, 10, Theme.Colors.Muted, true)
		cap.AutomaticSize = Enum.AutomaticSize.None
		cap.Position = UDim2.fromOffset(78, 8)
		cap.Size = UDim2.fromOffset(TILE_W - 82, 22)
		cap.TextWrapped = true
		cap.TextYAlignment = Enum.TextYAlignment.Top
		local value = MenuKit.label(f, "—", 22, Theme.Colors.Text, true)
		value.FontFace = Theme.FontHeavy
		value.Position = UDim2.fromOffset(78, 30)
		return value
	end
	local placeValue = tile(1, "results.place", Strings.get("result.tile.place", lang))
	local peakValue = tile(2, "results.peak", Strings.get("result.tile.peak", lang))
	local defeatedValue = tile(3, "results.out", Strings.get("result.tile.defeated", lang))
	local timeValue = tile(4, "results.time", Strings.get("result.tile.time", lang))
	-- Награда за матч: картинка, опыт и медали, плашка «новый уровень».
	local rewardRow = Instance.new("Frame")
	rewardRow.Name = "Reward"
	rewardRow.LayoutOrder = 4
	rewardRow.Size = UDim2.fromOffset(TILES_W, 60)
	rewardRow.BackgroundColor3 = Theme.Colors.Backdrop
	rewardRow.BorderSizePixel = 0
	rewardRow.Parent = panel
	MenuKit.stroke(rewardRow, Theme.Colors.Gold, 2)
	local rewardArt = CardKit.art(rewardRow, "results.reward", 72, 48)
	rewardArt.Position = UDim2.fromOffset(6, 6)
	local rewardInfo = MenuKit.box(rewardRow, "Info")
	rewardInfo.Position = UDim2.fromOffset(90, 0)
	rewardInfo.Size = UDim2.fromScale(0, 1)
	rewardInfo.AutomaticSize = Enum.AutomaticSize.X
	MenuKit.list(rewardInfo, 12, true)
	local rewardText = MenuKit.label(rewardInfo, "", 17, Theme.Colors.Sky, true, 1)
	local levelUp = MenuKit.label(rewardInfo, "", 14, Theme.color("Ink"), true, 2)
	levelUp.BackgroundTransparency = 0
	levelUp.BackgroundColor3 = Theme.Colors.Gold
	MenuKit.pad(levelUp, 8, 2)
	local levelRow = MenuKit.box(panel, "Level", 5)
	MenuKit.list(levelRow, 10, true)
	local rankIcon = MenuKit.rankIcon(levelRow, 1, 2, 1)
	local levelText = MenuKit.label(levelRow, "", 13, Theme.Colors.Gold, true, 2)
	local levelBarHost = Instance.new("Frame")
	levelBarHost.BackgroundTransparency = 1
	levelBarHost.Size = UDim2.fromOffset(200, 6)
	levelBarHost.LayoutOrder = 3
	levelBarHost.Parent = levelRow
	local levelBar = MenuKit.bar(levelBarHost, 6, Theme.Colors.Sky)
	local levelXp = MenuKit.label(levelRow, "", 11, Theme.Colors.Muted, false, 4)
	-- Места держав: строки с медалью (1–3) или номером, цветом державы, долей суши.
	local placesList = MenuKit.box(panel, "Places", 8)
	placesList.Visible = false
	placesList.Size = UDim2.fromOffset(TILES_W, 0)
	local placesGrid = Instance.new("UIGridLayout")
	placesGrid.CellSize = UDim2.fromOffset((TILES_W - TILE_GAP) / 2, PLACE_H)
	placesGrid.CellPadding = UDim2.fromOffset(TILE_GAP, 4)
	placesGrid.FillDirection = Enum.FillDirection.Vertical
	placesGrid.FillDirectionMaxCells = math.ceil(Config.Render.ResultsPlaces / 2)
	placesGrid.SortOrder = Enum.SortOrder.LayoutOrder
	placesGrid.Parent = placesList
	local chartTitle = label(panel, 13, 5)
	chartTitle.TextColor3 = Theme.Colors.Muted
	chartTitle.LayoutOrder = 9
	chartTitle.Text = Strings.get("result.chart", lang)
	chartTitle.Visible = false
	local chart = Instance.new("Frame")
	chart.Name = "Chart"
	chart.Size = UDim2.fromOffset(CHART_W, CHART_H)
	chart.BackgroundColor3 = Theme.Colors.Backdrop
	chart.BorderSizePixel = 0
	chart.ClipsDescendants = true
	chart.LayoutOrder = 10
	chart.Visible = false
	chart.Parent = panel
	local chartStroke = Instance.new("UIStroke")
	chartStroke.Color = Theme.Colors.PanelBorder
	chartStroke.Thickness = Theme.BorderPx
	chartStroke.Parent = chart
	-- Большая «В МЕНЮ» во всю ширину карточки, под ней — отсчёт, «Смотреть карту», «Подробнее».
	local menuButton = MenuKit.button(panel, Strings.get("result.menu", lang), "good", 52, 6)
	menuButton.Size = UDim2.fromOffset(TILES_W, 52)
	Session.connect(menuButton.Activated, onMenu)
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
	local moreButton = button(footer, Strings.get("result.more", lang))
	moreButton.LayoutOrder = 3
	Session.connect(moreButton.Activated, function()
		expanded = not expanded
		placesList.Visible = expanded
		chartTitle.Visible = expanded
		chart.Visible = expanded
		moreButton.Text = Strings.get(if expanded then "result.less" else "result.more", lang)
		fit()
	end)

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
		local me = cs.myNation
		local won = me ~= nil
			and (result.winner == me or (result.coWinners ~= nil and table.find(result.coWinners, me) ~= nil))
		title.Text =
			Strings.get(if me == nil then "result.over" elseif won then "result.victory" else "result.defeat", lang)
		title.TextColor3 = if me == nil then Theme.Colors.Text elseif won then Theme.Colors.Gold else Theme.Colors.Alert
		reason.Text = if result.reason == "land"
			then string.format(Strings.get("result.land", lang), lastShare(result, result.winner))
			else Strings.get("result." .. result.reason, lang)
		-- Команды (§5.1): побеждает команда; режим — в той же строке.
		local winnerInfo = cs.nations[result.winner]
		if winnerInfo ~= nil and winnerInfo.team ~= nil then
			reason.Text = string.format(Strings.get("result.team", lang), winnerInfo.team, reason.Text)
		end
		reason.Text = string.format(
			Strings.get("result.winner", lang),
			string.format('<font color="%s"><b>%s</b></font>', winnerHex, nameOf(result.winner))
		) .. " · " .. reason.Text .. " · " .. string.format(
			Strings.get("result.mode", lang),
			Strings.get("mode." .. cs.mode.mode, lang)
		)

		local mine = 0
		for place, id in result.places do
			if id == cs.myNation then
				mine = place
			end
		end
		placeValue.Text = if mine > 0
			then string.format(Strings.get("result.tile.placeOf", lang), mine, #result.places)
			else "—"
		placeValue.TextColor3 = if mine == 1 then Theme.Colors.Gold else Theme.Colors.Text
		local peak = 0
		local own = if me ~= nil then sharesOf(result, me) else nil
		if own ~= nil then
			for _, v in own do
				peak = math.max(peak, v)
			end
		end
		peakValue.Text = if own ~= nil then string.format("%d%%", peak) else "—"
		local duration = if #result.times > 0 then result.times[#result.times] else 0
		timeValue.Text = MenuKit.clock(duration)
		defeatedValue.Text = if me ~= nil then tostring(defeatedOf(result, me)) else "—"

		for _, child in placesList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for place = 1, math.min(#result.places, Config.Render.ResultsPlaces) do
			local id = result.places[place]
			local n = cs.nations[id]
			local mineRow = id == cs.myNation
			local f = Instance.new("Frame")
			f.Name = "Place"
			f.LayoutOrder = place
			f.BackgroundColor3 = Theme.Colors.Backdrop
			f.BorderSizePixel = 0
			f.Parent = placesList
			MenuKit.stroke(f, if mineRow then Theme.Colors.Gold else Theme.Colors.PanelBorder, 2)
			if place <= 3 then
				local medal = CardKit.art(f, "results.medal" .. place, 48, 32)
				medal.Position = UDim2.fromOffset(4, 4)
			else
				local num = MenuKit.label(f, tostring(place), 18, Theme.Colors.Muted, true)
				num.AutomaticSize = Enum.AutomaticSize.None
				num.Position = UDim2.fromOffset(4, 4)
				num.Size = UDim2.fromOffset(48, 32)
				num.TextXAlignment = Enum.TextXAlignment.Center
			end
			local swatch = Instance.new("Frame")
			swatch.Name = "Swatch"
			swatch.BorderSizePixel = 0
			swatch.BackgroundColor3 = nationColor(cs, id)
			swatch.Position = UDim2.fromOffset(60, 10)
			swatch.Size = UDim2.fromOffset(20, 20)
			swatch.Parent = f
			MenuKit.stroke(swatch, Theme.color("Ink"), 2)
			local name = nameOf(id)
			if n ~= nil and not n.alive then
				name ..= string.format(' <font color="%s">· %s</font>', muted, Strings.get("result.out", lang))
			end
			local nameLabel = MenuKit.label(f, name, 15, if mineRow then Theme.Colors.Gold else Theme.Colors.Text, true)
			nameLabel.AutomaticSize = Enum.AutomaticSize.None
			nameLabel.Position = UDim2.fromOffset(88, 11)
			nameLabel.Size = UDim2.new(1, -88 - 84, 0, 18)
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			local share = MenuKit.label(
				f,
				string.format(Strings.get("result.share", lang), lastShare(result, id)),
				14,
				Theme.Colors.Sky,
				true
			)
			share.AnchorPoint = Vector2.new(1, 0)
			share.Position = UDim2.new(1, -12, 0, 11)
		end

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

	-- Награда приходит профилем чуть позже итогов — перечитываем раз в секунду.
	local function drawReward()
		local p = cs.profile
		local reward = if p ~= nil then p.reward else nil
		rewardRow.Visible = reward ~= nil and cs.myNation ~= nil
		if reward ~= nil then
			rewardText.Text = string.format(Strings.get("result.reward", lang), reward.xp, reward.medals)
			levelUp.Visible = reward.levels > 0
			levelUp.Text = if p ~= nil then string.format(Strings.get("result.levelUp", lang), p.level) else ""
		end
		levelRow.Visible = p ~= nil
		if p ~= nil then
			local rank = Ranks.of(p.level)
			MenuKit.setRank(rankIcon, rank, 2)
			levelText.Text = string.format(Strings.get("menu.level", lang), p.level)
				.. " · "
				.. Strings.get("rank." .. rank, lang)
			levelBar.set(if p.need > 0 then p.xp / p.need else 1)
			levelXp.Text = if p.need > 0
				then string.format(Strings.get("menu.xp", lang), p.xp, p.need)
				else Strings.get("menu.maxLevel", lang)
		end
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
			drawReward()
		end
	end

	return { refresh = refresh, update = update }
end

return table.freeze(ResultsPanel)
