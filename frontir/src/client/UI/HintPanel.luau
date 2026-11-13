--!strict
--[[
	HintPanel — подсказка «что делать дальше» (§15д ч.5): плашка с лампочкой под полосой ресурсов. Какую показать,
	решает Shared.Hints по тому, что видит игрок; «Понятно» — больше не показывать эту в матче. Сделали — уходит
	сама. Новая подсказка появляется плавно (Theme.popIn). В обучении — нет (там UI/TutorialPanel).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Hints = require(Shared:WaitForChild("Hints"))
local PixelIcons = require(Shared:WaitForChild("PixelIcons"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type HintPanel = {
	update: (now: number) -> (),
	onEvents: (events: { any }) -> (), -- налёт по нам — подсказка про ПВО
}

local HintPanel = {}

function HintPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang): HintPanel
	local panel = Instance.new("Frame")
	panel.Name = "HintPanel"
	-- §15ш Ш2: внизу слева, над лентой событий (Main.client кладёт в «AttackArea»); ширина — как у ленты.
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 12, 1, -160)
	panel.Size = UDim2.fromOffset(320, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	Theme.decorate(panel)
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke ~= nil then
		stroke.Color = Theme.Colors.Gold
	end
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(pad :: any)[side] = UDim.new(0, 8)
	end
	pad.PaddingBottom = UDim.new(0, 40) -- кнопка «Понятно» — внутри рамки, не на строке ленты под ней
	pad.Parent = panel
	local scale = 3
	local icon = Instance.new("Frame")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(PixelIcons.Size * scale, PixelIcons.Size * scale)
	icon.Parent = panel
	for _, p in PixelIcons.Icons.hint do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Theme.color(p.color)
		f.Position = UDim2.fromOffset(p.x * scale, p.y * scale)
		f.Size = UDim2.fromOffset(p.w * scale, p.h * scale)
		f.Parent = icon
	end
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(PixelIcons.Size * scale + 8, 0)
	text.Size = UDim2.new(1, -(PixelIcons.Size * scale + 8), 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.TextWrapped = true
	text.FontFace = Theme.Font
	text.TextSize = 14
	text.TextColor3 = Theme.Colors.Text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Parent = panel
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 1, 4)
	close.Size = UDim2.fromOffset(96, 28)
	close.BackgroundColor3 = Theme.Colors.Slate
	close.BorderSizePixel = 0
	close.FontFace = Theme.FontBold
	close.TextSize = 13
	close.TextColor3 = Theme.Colors.Gold
	close.Text = Strings.get("hint.close", lang)
	close.Parent = panel

	local dismissed: { [string]: boolean } = {}
	local current: string? = nil
	local nextAt = 0
	local matchId: any = nil

	Session.connect(close.Activated, function()
		if current ~= nil then
			dismissed[current] = true
		end
		current = nil
		panel.Visible = false
	end)

	-- Когда нас бомбили в последний раз (событие raid по нам; onEvents из Main).
	local bombedAt = -math.huge
	-- §15т ч.2: своя высадка, налёт и пуск уже были в этом матче (подсказка уходит).
	local done: { [string]: boolean } = {}
	local function facts(now: number): Hints.Facts?
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local stats = cs.stats
		local forces = cs.myForces
		if me == nil or not me.alive or stats == nil or forces == nil or cs.phase ~= "Play" then
			return nil
		end
		local mine = nil
		for _, s in stats.nations do
			if s.id == me.id then
				mine = s
			end
		end
		if mine == nil then
			return nil
		end
		local attacks = 0
		for _, a in stats.attacks do
			if a.attacker == me.id then
				attacks += 1
			end
		end
		local factories, batteries, cities, cityLevels = 0, 0, 0, 0
		local ports, airfields, silos = 0, 0, 0
		for cell, b in cs.buildings do
			if ClientState.ownerAt(cs, cell) == me.id then
				if b.kind == "Factory" then
					factories += 1
				elseif b.kind == "AirDefense" then
					batteries += 1
				elseif b.kind == "Port" then
					ports += 1
				elseif b.kind == "Airfield" then
					airfields += 1
				elseif b.kind == "MissileSilo" then
					silos += 1
				end
			end
		end
		local ships, transports, planes, bombers = 0, 0, 0, 0
		for _, ship in cs.ships.ships do
			if ship.owner == me.id and ship.kind ~= "Merchant" then
				ships += 1
				if ship.kind == "Transport" then
					transports += 1
				end
			end
		end
		for _, plane in cs.air.planes do
			if plane.owner == me.id then
				planes += 1
				if plane.kind == "Bomber" then
					bombers += 1
				end
			end
		end
		for _, c in cs.cities do
			if ClientState.ownerAt(cs, c) == me.id then
				cities += 1
				cityLevels += ClientState.cityLevel(cs, c)
			end
		end
		local atWar = false
		for _, war in cs.wars.wars do
			if war.active and (war.a == me.id or war.b == me.id) then
				atWar = true
			end
		end
		local troops = 0
		for _, k in forces.kinds do
			troops += k.home
		end
		return {
			time = ClientState.matchTime(cs, os.clock()),
			tutorial = cs.rules.tutorial == true,
			attacks = attacks,
			people = mine.people,
			maxPeople = mine.maxPeople,
			money = forces.economy.money,
			barracks = forces.economy.barracks,
			factories = factories,
			cityLevels = cityLevels,
			cities = cities,
			troops = troops,
			atWar = atWar,
			bombed = now - bombedAt < Config.Hints.BombedSec,
			batteries = batteries,
			lowStability = cs.stability.lowCells > 0,
			ports = ports,
			ships = ships,
			transports = transports,
			landed = done.landed == true,
			airfields = airfields,
			planes = planes,
			bombers = bombers,
			raided = done.raid == true,
			silos = silos,
			launched = done.missileLaunched == true,
		}
	end

	local function update(now: number)
		if now < nextAt then
			return
		end
		nextAt = now + Config.Hints.ShowEverySec
		if cs.matchId ~= matchId then
			matchId = cs.matchId
			table.clear(dismissed)
			table.clear(done)
		end
		local f = facts(now)
		local key = if f ~= nil then Hints.pick(f, dismissed) else nil
		if key ~= current then
			current = key
			if key ~= nil then
				text.Text = Strings.get("hint." .. key, lang)
				panel.Visible = true
				Theme.popIn(panel)
			else
				panel.Visible = false
			end
		end
	end

	return {
		update = update,
		onEvents = function(events: { any })
			for _, e in events do
				if type(e) == "table" and e.kind == "raid" and e.target == cs.myNation then
					bombedAt = os.clock()
				end
				-- §15т ч.2: своя высадка, налёт, пуск — подсказка «как это делать» больше не нужна.
				if
					type(e) == "table"
					and cs.myNation ~= nil
					and e.nation == cs.myNation
					and (e.kind == "landed" or e.kind == "raid" or e.kind == "missileLaunched")
				then
					done[e.kind] = true
				end
			end
		end,
	}
end

return table.freeze(HintPanel)
