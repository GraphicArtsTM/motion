--!strict
--[[
	CouncilPanel — Совет держав (GDD §8.2, этап 6б).
	- Идёт голосование — окно сверху: три резолюции (название, что делает, сколько голосов), таймер; нажатие —
	  голос (можно переголосовать, пока идёт голосование).
	- Действуют резолюции — строка под баннером: «Действует: Перемирие (0:42)».
	Все решения — на сервере: клиент шлёт намерение vote.
	§15л ч.10: резолюции — карточки с картинками ItemArt, полосой доли голосов и кнопкой «Голосовать».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type CouncilPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
}

local CouncilPanel = {}

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

	-- §15л ч.10: голосование — карточки резолюций (картинка ItemArt, что делает, полоса голосов, «Голосовать»).
	local CARD_W = 196
	local WIDTH = Config.Council.Options * CARD_W + (Config.Council.Options - 1) * 10 + 28
	local window = Instance.new("Frame")
	window.Name = "Council"
	window.AnchorPoint = Vector2.new(0.5, 0)
	window.Position = UDim2.new(0.5, 0, 0, 150)
	window.Size = UDim2.fromOffset(WIDTH, 0)
	window.AutomaticSize = Enum.AutomaticSize.Y
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Visible = false
	window.ZIndex = 4
	window.Parent = gui
	MenuKit.stroke(window, Theme.Colors.Gold, 2)
	MenuKit.pad(window, 14, 10)
	MenuKit.list(window, 8)
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		scale.Scale = math.clamp((gui.AbsoluteSize.X - 24) / WIDTH, 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()
	local title = MenuKit.label(window, "", 18, Theme.Colors.Gold, true, 1)
	local timerBar = MenuKit.bar(window, 6, Theme.Colors.Gold, 2)
	local cardsRow = MenuKit.box(window, "Options", 3)
	MenuKit.list(cardsRow, 10, true)
	local myVote = 0
	type Option = {
		frame: Frame,
		edge: UIStroke,
		art: ImageLabel?,
		kind: string,
		name: TextLabel,
		hint: TextLabel,
		bar: MenuKit.Bar,
		votes: TextLabel,
		vote: TextButton,
	}
	local options: { Option } = {}
	for k = 1, Config.Council.Options do
		local f = Instance.new("Frame")
		f.LayoutOrder = k
		f.Size = UDim2.fromOffset(CARD_W, 252)
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = cardsRow
		local edge = MenuKit.stroke(f, Theme.Colors.PanelBorder, 2)
		local name = MenuKit.label(f, "", 15, Theme.Colors.Text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Position = UDim2.fromOffset(8, 104)
		name.Size = UDim2.fromOffset(CARD_W - 16, 18)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local hint = MenuKit.label(f, "", 11, Theme.Colors.Muted)
		hint.AutomaticSize = Enum.AutomaticSize.None
		hint.Position = UDim2.fromOffset(8, 124)
		hint.Size = UDim2.fromOffset(CARD_W - 16, 44)
		hint.TextWrapped = true
		hint.TextYAlignment = Enum.TextYAlignment.Top
		local barHost = Instance.new("Frame")
		barHost.BackgroundTransparency = 1
		barHost.Position = UDim2.fromOffset(8, 172)
		barHost.Size = UDim2.fromOffset(CARD_W - 16, 8)
		barHost.Parent = f
		local bar = MenuKit.bar(barHost, 8, Theme.Colors.Sky)
		local votes = MenuKit.label(f, "", 12, Theme.Colors.Sky, true)
		votes.Position = UDim2.fromOffset(8, 182)
		local vote = MenuKit.button(f, "", "good", MenuKit.Touch)
		vote.AnchorPoint = Vector2.new(0, 1)
		vote.Position = UDim2.new(0, 8, 1, -8)
		vote.Size = UDim2.new(1, -16, 0, MenuKit.Touch)
		vote.TextSize = 15
		local opt: Option = {
			frame = f,
			edge = edge,
			art = nil,
			kind = "",
			name = name,
			hint = hint,
			bar = bar,
			votes = votes,
			vote = vote,
		}
		Session.connect(vote.Activated, function()
			local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
			if cs.diplo.council.vote ~= nil and cs.phase == "Play" and me ~= nil and me.alive then
				myVote = k
				send("vote", { option = k })
			end
		end)
		table.insert(options, opt)
	end
	local footer = MenuKit.label(window, "", 12, Theme.Colors.Muted, false, 9)

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
			local total = 0
			for k = 1, #options do
				total += vote.tallies[k] or 0
			end
			timerBar.set(math.clamp(left / math.max(1, Config.Council.VoteSec / cs.speed), 0, 1))
			for k, o in options do
				local option = vote.options[k]
				o.frame.Visible = option ~= nil
				if option ~= nil then
					if o.kind ~= option then
						o.kind = option
						local old = o.art
						if old ~= nil then
							old:Destroy()
						end
						local art = CardKit.art(o.frame, "council." .. option, CARD_W - 12, 92)
						art.Position = UDim2.fromOffset(6, 6)
						o.art = art
					end
					local count = vote.tallies[k] or 0
					o.name.Text = Strings.get("council.res." .. option, lang)
					o.hint.Text = Strings.get("council.res." .. option .. ".hint", lang)
					o.bar.set(count / math.max(1, total))
					o.votes.Text = string.format(Strings.get("council.votes", lang), count)
					local mine = myVote == k
					o.vote.Text = Strings.get(if mine then "council.myVote" else "council.voteBtn", lang)
					o.vote.BackgroundColor3 = Theme.color(if mine then "Gold" else "Forest")
					o.vote.TextColor3 = Theme.color(if mine then "Ink" else "White")
					o.edge.Color = if mine then Theme.Colors.Gold else Theme.Colors.PanelBorder
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
