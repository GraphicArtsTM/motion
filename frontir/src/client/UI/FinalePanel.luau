--!strict
--[[
	FinalePanel — кульминация матча (GDD §15й Й3). Правило — чистый Finale.state (то же у сервера и музыки), данные —
	то, что у клиента уже есть: блок лидера (ClientState.victoryLeader), доля для победы и часы матча.
	- вход в финал — крупный баннер «ФИНАЛ» по центру (~Finale.BannerSec);
	- полоса «ФИНАЛ» в столбике TopCenter: кто лидер и сколько ему осталось или сколько времени до конца;
	- последние Finale.CountdownSec — крупный отсчёт в полосе, «пульс» каждую секунду, последние UrgentSec — красным;
	- верхняя полоса матча (topBar) — мигающая золотая рамка; лидер на карте — контур (setLeader → MapHighlightLayer).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Finale = require(Shared:WaitForChild("Finale"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type FinalePanel = {
	strip: Frame,
	update: (now: number) -> (),
}

local FinalePanel = {}

function FinalePanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	totalLand: number,
	topBar: GuiObject?,
	setLeader: (id: number) -> (),
	onEnter: () -> ()
): FinalePanel
	local cfg = Config.Finale
	local function t(key: string): string
		return Strings.get(key, lang)
	end

	-- Полоса в столбике сверху.
	local strip = Instance.new("Frame")
	strip.Name = "FinaleStrip"
	strip.Size = UDim2.fromOffset(0, 0)
	strip.AutomaticSize = Enum.AutomaticSize.XY
	strip.BackgroundColor3 = Theme.Colors.PanelBg
	strip.BackgroundTransparency = Theme.PanelAlpha
	strip.BorderSizePixel = 0
	strip.Visible = false
	strip.Parent = gui
	strip:SetAttribute("FrontirStyled", true)
	MenuKit.corner(strip, 10)
	MenuKit.pad(strip, 14, 6)
	local stripStroke = MenuKit.stroke(strip, Theme.Colors.Gold, 2)
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 10)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = strip
	local title = MenuKit.label(strip, "⭐ " .. t("finale.title"), 16, Theme.Colors.Gold, true, 1)
	local line = MenuKit.label(strip, "", 14, Theme.Colors.Text, true, 2)
	local countHost = Instance.new("Frame")
	countHost.Name = "Countdown"
	countHost.BackgroundTransparency = 1
	countHost.Size = UDim2.fromOffset(0, 0)
	countHost.AutomaticSize = Enum.AutomaticSize.XY
	countHost.LayoutOrder = 3
	countHost.Visible = false
	countHost.Parent = strip
	local countScale = Instance.new("UIScale")
	countScale.Parent = countHost
	local count = MenuKit.label(countHost, "", 30, Theme.Colors.Gold, true)
	count.FontFace = Theme.FontHeavy

	-- Баннер по центру при входе в финал.
	local banner = Instance.new("Frame")
	banner.Name = "FinaleBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.46) -- ниже баннера войны (WarFxLayer) и столбика сверху
	banner.Size = UDim2.fromOffset(560, 0)
	banner.AutomaticSize = Enum.AutomaticSize.Y
	banner.BackgroundColor3 = Theme.Colors.PanelBg
	banner.BackgroundTransparency = 0.05
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.ZIndex = 20
	banner.Parent = gui
	banner:SetAttribute("FrontirStyled", true)
	MenuKit.corner(banner, 12)
	MenuKit.pad(banner, 20, 12)
	MenuKit.stroke(banner, Theme.Colors.Gold, 3)
	local bannerList = Instance.new("UIListLayout")
	bannerList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bannerList.Padding = UDim.new(0, 4)
	bannerList.SortOrder = Enum.SortOrder.LayoutOrder
	bannerList.Parent = banner
	local bannerTitle = MenuKit.label(banner, "⭐ " .. t("finale.title") .. " ⭐", 44, Theme.Colors.Gold, true, 1)
	bannerTitle.FontFace = Theme.FontHeavy
	bannerTitle.TextXAlignment = Enum.TextXAlignment.Center
	local bannerText = MenuKit.wrapLabel(banner, "", 17, Theme.Colors.Text, 2)
	bannerText.TextXAlignment = Enum.TextXAlignment.Center
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	-- Мигающая рамка вокруг верхней полосы матча.
	local barStroke: UIStroke? = nil
	if topBar ~= nil then
		local s = Instance.new("UIStroke")
		s.Name = "FinaleEdge"
		s.Color = Theme.Colors.Gold
		s.Thickness = 2
		s.Enabled = false
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = topBar
		barStroke = s
	end

	local wasNear = false
	local shownReason: string? = nil
	local bannerUntil = 0
	local lastSecond = -1
	local leaderShown = 0

	local function nameOf(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end
	local function pct(x: number): string
		return string.format("%.1f", x * 100)
	end
	local function clock(sec: number): string
		local s = math.max(0, math.ceil(sec))
		return string.format("%d:%02d", s // 60, s % 60)
	end

	local function update(now: number)
		local playing = cs.phase == "Play" and cs.stats ~= nil
		local leader, land = ClientState.victoryLeader(cs)
		local limit = cs.rules.timeLimitSec
		local left = if limit > 0 then limit - ClientState.matchTime(cs, now) else nil
		local share = land / math.max(1, totalLand)
		local st = Finale.state({
			victoryShare = cs.rules.victoryShare,
			leaderShare = share,
			timeLeft = left,
			nearAllowed = Finale.nearAllowed(cs.rules),
		}, wasNear)
		if not playing then
			st = { on = false, reason = nil, countdown = false, urgent = false }
		end
		wasNear = st.reason == "near"
		-- Контур лидера — только в финале «лидер близко».
		local want = if wasNear then leader else 0
		if want ~= leaderShown then
			leaderShown = want
			setLeader(want)
		end
		strip.Visible = st.on
		if barStroke ~= nil then
			barStroke.Enabled = st.on
			if st.on then
				barStroke.Transparency = 0.5 - 0.5 * math.sin(now * math.pi * 2)
			end
		end
		if not st.on then
			shownReason = nil
			banner.Visible = false
			return
		end
		-- Блок лидера (как m.finaleBloc на сервере): лидер, его союзники и их вассалы. «Мы» — лидер сами или в блоке.
		local me = cs.myNation
		local mine = leader == me
		local ours = false
		if not mine and me ~= nil and leader ~= 0 then
			local heads = { leader }
			for _, ally in ClientState.alliesOf(cs, leader) do
				table.insert(heads, ally)
			end
			local lord = ClientState.overlordOf(cs, me)
			ours = table.find(heads, me) ~= nil or (lord ~= nil and table.find(heads, lord) ~= nil)
		end
		local speed = math.round((cfg.CoalitionSpeed - 1) * 100)
		local goal = pct(cs.rules.victoryShare)
		if st.reason == "near" then
			line.Text = if mine
				then string.format(t("finale.stripNearMe"), pct(share), goal, speed)
				elseif ours then string.format(t("finale.stripNearOurs"), nameOf(leader), pct(share), goal, speed)
				else string.format(t("finale.stripNear"), nameOf(leader), pct(share), goal, speed)
		else
			line.Text = string.format(t("finale.stripTime"), clock(left or 0), nameOf(leader), pct(share))
		end
		stripStroke.Transparency = 0.4 - 0.4 * math.sin(now * math.pi * 2)
		-- Вход в финал (или смена «время» → «лидер близко») — баннер.
		if st.reason ~= shownReason then
			shownReason = st.reason
			bannerUntil = now + cfg.BannerSec
			if st.reason == "near" then
				bannerText.Text = if mine
					then string.format(t("finale.nearMe"), pct(share), goal)
					elseif ours then string.format(t("finale.nearOurs"), nameOf(leader), pct(share), goal)
					else string.format(t("finale.near"), nameOf(leader), pct(share), goal, speed)
			else
				bannerText.Text = string.format(t("finale.time"), clock(left or 0))
			end
			banner.Visible = true
			bannerScale.Scale = 0.7
			TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
			onEnter()
		end
		if banner.Visible and now >= bannerUntil then
			banner.Visible = false
		end
		-- Последняя минута — крупный отсчёт, «пульс» на каждую секунду.
		countHost.Visible = st.countdown
		if st.countdown and left ~= nil then
			local sec = math.max(0, math.ceil(left))
			count.Text = clock(left)
			count.TextColor3 = if st.urgent then Theme.Colors.Alert else Theme.Colors.Gold
			if sec ~= lastSecond then
				lastSecond = sec
				countScale.Scale = if st.urgent then 1.35 else 1.15
				TweenService:Create(countScale, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
			end
		end
		title.TextColor3 = if st.urgent then Theme.Colors.Alert else Theme.Colors.Gold
	end

	return { strip = strip, update = update }
end

return table.freeze(FinalePanel)
