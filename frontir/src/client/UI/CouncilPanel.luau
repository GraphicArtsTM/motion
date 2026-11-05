--!strict
--[[
	CouncilPanel — Совет держав (GDD §8.2, этап 6б).
	- Идёт голосование — окно сверху: три резолюции (название, что делает, сколько голосов), таймер; нажатие —
	  голос (можно переголосовать, пока идёт голосование).
	- Действуют резолюции — строка под баннером: «Действует: Перемирие (0:42)».
	Все решения — на сервере: клиент шлёт намерение vote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type CouncilPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
}

local CouncilPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

function CouncilPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): CouncilPanel
	local muted, gold = hex(Theme.Colors.Muted), hex(Theme.Colors.Gold)

	local window = Instance.new("Frame")
	window.Name = "Council"
	window.AnchorPoint = Vector2.new(0.5, 0)
	window.Position = UDim2.new(0.5, 0, 0, 120)
	window.Size = UDim2.fromOffset(420, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BackgroundTransparency = 0.05
	window.BorderSizePixel = 0
	window.Visible = false
	window.ZIndex = 4
	window.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Gold
	stroke.Thickness = 2
	stroke.Parent = window
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = window
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = window
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		scale.Scale = math.clamp(gui.AbsoluteSize.X / 460, 0.6, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.RichText = true
	title.Size = UDim2.new(1, 0, 0, 22)
	title.FontFace = Theme.FontBold
	title.TextSize = 17
	title.TextColor3 = Theme.Colors.Gold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 1
	title.Parent = window

	local myVote = 0
	local options: { TextButton } = {}
	for k = 1, Config.Council.Options do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 0, BUTTON + 6)
		b.BackgroundColor3 = Theme.Colors.PanelBg
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.RichText = true
		b.TextWrapped = true
		b.FontFace = Theme.FontBold
		b.TextSize = 15
		b.TextColor3 = Theme.Colors.Text
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.LayoutOrder = 1 + k
		local bpad = Instance.new("UIPadding")
		bpad.PaddingLeft = UDim.new(0, 8)
		bpad.Parent = b
		local bstroke = Instance.new("UIStroke")
		bstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bstroke.Color = Theme.Colors.PanelBorder
		bstroke.Thickness = Theme.BorderPx
		bstroke.Parent = b
		b.Activated:Connect(function()
			local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
			if cs.diplo.council.vote ~= nil and cs.phase == "Play" and me ~= nil and me.alive then
				myVote = k
				send("vote", { option = k })
			end
		end)
		b.Parent = window
		table.insert(options, b)
	end
	local footer = Instance.new("TextLabel")
	footer.BackgroundTransparency = 1
	footer.RichText = true
	footer.Size = UDim2.new(1, 0, 0, 16)
	footer.FontFace = Theme.Font
	footer.TextSize = 12
	footer.TextColor3 = Theme.Colors.Muted
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.LayoutOrder = 9
	footer.Parent = window

	-- Действующие резолюции — строка под баннером.
	local activeLine = Instance.new("TextLabel")
	activeLine.Name = "Resolutions"
	activeLine.AnchorPoint = Vector2.new(0.5, 0)
	activeLine.Position = UDim2.new(0.5, 0, 0, 96)
	activeLine.Size = UDim2.fromOffset(0, 20)
	activeLine.AutomaticSize = Enum.AutomaticSize.X
	activeLine.BackgroundColor3 = Theme.Colors.PanelBg
	activeLine.BackgroundTransparency = 0.2
	activeLine.BorderSizePixel = 0
	activeLine.RichText = true
	activeLine.FontFace = Theme.Font
	activeLine.TextSize = 13
	activeLine.TextColor3 = Theme.Colors.Text
	activeLine.Visible = false
	activeLine.Parent = gui
	local linePad = Instance.new("UIPadding")
	linePad.PaddingLeft = UDim.new(0, 8)
	linePad.PaddingRight = UDim.new(0, 8)
	linePad.Parent = activeLine

	local function clock(sec: number): string
		local s = math.max(0, math.ceil(sec))
		return string.format("%d:%02d", s // 60, s % 60)
	end
	local function nameOf(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		local c = if n.colorIndex >= 1 then NationColors.Colors[n.colorIndex] else nil
		local color = if c ~= nil then string.format("#%02x%02x%02x", c.r, c.g, c.b) else gold
		return string.format('<font color="%s">%s</font>', color, if lang == "en" then n.nameEn else n.name)
	end

	local function draw(now: number)
		local playing = cs.phase == "Play"
		local council = cs.diplo.council
		local vote = council.vote
		if vote == nil or not playing then
			window.Visible = false
			myVote = 0
		else
			window.Visible = true
			local left = ClientState.diploLeft(cs, vote.left, now, ClientState.simRate(cs)) / cs.speed
			title.Text = Strings.get("council.title", lang)
				.. string.format(
					'  <font size="13" color="%s">%s</font>',
					muted,
					string.format(Strings.get("council.vote", lang), math.ceil(left))
				)
			for k, b in options do
				local option = vote.options[k]
				b.Visible = option ~= nil
				if option ~= nil then
					local count = vote.tallies[k] or 0
					b.Text = string.format(
						'%s%s <font size="12" color="%s">· %s</font>\n<font size="12" color="%s">%s</font>',
						if myVote == k then "▶ " else "",
						Strings.get("council.res." .. option, lang),
						gold,
						string.format(Strings.get("council.votes", lang), count),
						muted,
						Strings.get("council.res." .. option .. ".hint", lang)
					)
					b.BackgroundTransparency = if myVote == k then 0.3 else 0
				end
			end
			footer.Text = if myVote > 0 then Strings.get("council.voted", lang) else ""
		end
		-- Действующие резолюции.
		local parts: { string } = {}
		for _, a in council.active do
			local left = ClientState.diploLeft(cs, a.left, now, ClientState.simRate(cs)) / cs.speed
			if left > 0 then
				local name = Strings.get("council.res." .. a.kind, lang)
				if a.kind == "sanctions" and a.target ~= nil then
					name ..= " → " .. nameOf(a.target)
				end
				table.insert(parts, string.format(Strings.get("council.active", lang), name, clock(left)))
			end
		end
		activeLine.Visible = playing and #parts > 0
		activeLine.Text = table.concat(parts, "   ")
	end

	local lastSecond = -1
	return {
		refresh = function()
			draw(os.clock())
		end,
		update = function(now: number)
			local second = math.floor(now)
			if second ~= lastSecond then
				lastSecond = second
				draw(now)
			end
		end,
	}
end

return table.freeze(CouncilPanel)
