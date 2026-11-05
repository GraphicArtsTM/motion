--!strict
--[[
	WorldPanel — случайные события (GDD §6.16, этап 7г).
	- Баннер сверху на Events.BannerSec: что случилось (нефть, шторм, урожай, наёмники, восстание, перебежчики).
	- Аукцион наёмников: окошко справа сверху — сколько войск, сколько осталось, текущая ставка и кто её сделал,
	  кнопки «Ставка $N» (минимальная) и «Ставка $N+5 000». Решает сервер (намерение bid), отказ — в ленте.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type WorldPanel = {
	refresh: () -> (), -- пришло world
	onEvents: (events: { any }) -> (),
	update: (now: number) -> (),
}

local WorldPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx

local function button(parent: Instance, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, BUTTON)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = Theme.FontBold
	b.TextSize = 14
	b.TextColor3 = Theme.Colors.Gold
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = b
	b.Parent = parent
	return b
end

function WorldPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	nameOf: (id: number) -> string
): WorldPanel
	local banner = Instance.new("TextLabel")
	banner.Name = "WorldBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 220)
	banner.Size = UDim2.fromOffset(520, 36)
	banner.BackgroundColor3 = Theme.Colors.Backdrop
	banner.BackgroundTransparency = 0.15
	banner.BorderSizePixel = 0
	banner.FontFace = Theme.FontBold
	banner.TextSize = 17
	banner.TextColor3 = Theme.Colors.Gold
	banner.TextWrapped = true
	banner.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Gold
	stroke.Parent = banner
	banner.Parent = gui
	local bannerUntil = 0

	local panel = Instance.new("Frame")
	panel.Name = "Auction"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 300)
	panel.Size = UDim2.fromOffset(250, 60 + BUTTON * 2 + 12)
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	local pstroke = Instance.new("UIStroke")
	pstroke.Color = Theme.Colors.Gold
	pstroke.Parent = panel
	panel.Parent = gui
	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(8, 6)
	title.Size = UDim2.new(1, -16, 0, 20)
	title.BackgroundTransparency = 1
	title.FontFace = Theme.FontBold
	title.TextSize = 14
	title.TextColor3 = Theme.Colors.Gold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	local top = Instance.new("TextLabel")
	top.Position = UDim2.fromOffset(8, 28)
	top.Size = UDim2.new(1, -16, 0, 28)
	top.BackgroundTransparency = 1
	top.FontFace = Theme.Font
	top.TextSize = 13
	top.TextWrapped = true
	top.RichText = true
	top.TextColor3 = Theme.Colors.Text
	top.TextXAlignment = Enum.TextXAlignment.Left
	top.Parent = panel
	local bidMin = button(panel, 234)
	bidMin.Position = UDim2.fromOffset(8, 60)
	local bidMore = button(panel, 234)
	bidMore.Position = UDim2.fromOffset(8, 60 + BUTTON + 6)
	local more = 5000

	local function minBid(): number
		local a = cs.world.auction
		return if a ~= nil then a.minBid else 0
	end
	bidMin.Activated:Connect(function()
		send("bid", { amount = minBid() })
	end)
	bidMore.Activated:Connect(function()
		send("bid", { amount = minBid() + more })
	end)

	local function update(now: number)
		if banner.Visible and now >= bannerUntil then
			banner.Visible = false
		end
		local a = cs.world.auction
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local left = if a ~= nil then a.left - (now - cs.worldAt) * Config.Match.Speed else 0
		panel.Visible = a ~= nil and left > 0 and cs.phase == "Play" and me ~= nil and me.alive
		if not panel.Visible or a == nil then
			return
		end
		title.Text = string.format(Strings.get("auction.title", lang), Config.Events.MercStrength, math.ceil(left))
		top.Text = if a.topId ~= 0
			then string.format(Strings.get("auction.top", lang), Strings.formatInt(a.top), nameOf(a.topId))
			else Strings.get("auction.none", lang)
		bidMin.Text = string.format(Strings.get("auction.bid", lang), Strings.formatInt(a.minBid))
		bidMore.Text = string.format(Strings.get("auction.bid", lang), Strings.formatInt(a.minBid + more))
	end

	local function show(text: string)
		banner.Text = text
		banner.Visible = true
		bannerUntil = os.clock() + Config.Events.BannerSec
	end

	local function onEvents(events: { any })
		for _, e in events do
			if type(e) ~= "table" then
				continue
			end
			if e.kind == "worldEvent" then
				local key = "world." .. tostring(e.event)
				if Strings.Table[key] == nil then
					continue
				end
				local fmt = Strings.get(key, lang)
				local arg = ""
				if e.event == "OilRush" and type(e.province) == "number" then
					arg = "#" .. e.province
				elseif type(e.nation) == "number" then
					arg = nameOf(e.nation)
				end
				show(if string.find(fmt, "%%s") then string.format(fmt, arg) else (string.gsub(fmt, "%%%%", "%%")))
			elseif e.kind == "mercs" then
				show(
					if (tonumber(e.nation) or 0) ~= 0
						then string.format(
							Strings.get("world.mercsWon", lang),
							nameOf(e.nation),
							Strings.formatInt(tonumber(e.amount) or 0)
						)
						else Strings.get("world.mercsNone", lang)
				)
			end
		end
	end

	return {
		refresh = function()
			update(os.clock())
		end,
		onEvents = onEvents,
		update = update,
	}
end

return table.freeze(WorldPanel)
