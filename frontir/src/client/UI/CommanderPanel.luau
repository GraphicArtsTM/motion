--!strict
--[[
	CommanderPanel — генерал игрока (GDD §6.15, этап 7в-2).
	- Лобби и выбор старта: снизу четыре карточки (имя, пассивка, способности Q / E); нажатие — выбор
	  (намерение commander), выбранная — золотая рамка.
	- Игра: слева сверху две кнопки способностей «Q — Авиаудар» / «E — Прорыв» с перезарядкой и строка действующего
	  эффекта. Q / E или кнопка: способность без цели применяется сразу, с целью — режим цели (строка сверху),
	  следующее нажатие на карту — цель (десантам — доля войск с ползунка атаки). Esc или нажатие на строку — отмена.
	Решения — на сервере; отказ показывает лента (rejected).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local StrikeMenu = require(Shared:WaitForChild("StrikeMenu"))
local Types = require(Shared:WaitForChild("Types"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local StrikeStatus = require(script.Parent:WaitForChild("StrikeStatus"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type CommanderPanel = {
	refresh: () -> (), -- пришли info / commander или сменилась фаза
	update: (now: number) -> (), -- обратные отсчёты
	tap: (cell: number) -> boolean, -- true — нажатие ушло в цель способности
	isOpen: () -> boolean, -- самопроверка: карточки (лобби) или кнопки способностей (игра) на экране
	pickerFrame: Frame, -- §15и: на время лобби переезжает в экран лобби
	aiming: () -> Types.Warhead?, -- §15х: ждём цель ракеты / бомбы — какой (для прогноза удара)
	setRaid: (start: () -> ()) -> (), -- §15х ч.4: строка «Налёт» включает выбор цели в AirPanel
}

local CommanderPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local CARD_W, CARD_H = 176, 112
local KEYS = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.R }
local KEY_NAMES = { "Q", "E" }
local MISSILE = 3 -- третий «слот» — ракета из своей шахты (§6.9, этап 7г)
local RAID = 4 -- §15х ч.4: четвёртая строка — налёт бомбардировщика (цель — нажатием на карту, AirPanel)
local HOW_SEC = 7 -- сколько висит подсказка «что сделать», когда удар не готов

local function stroke(parent: Instance, color: Color3): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = Theme.BorderPx
	s.Parent = parent
	return s
end

local function text(parent: Instance, size: number, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextWrapped = true
	t.FontFace = if bold then Theme.FontBold else Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Parent = parent
	return t
end

-- Пассивка генерала: подстановка чисел из Config.Commanders.
local function passive(c: Types.CommanderId, lang: Strings.Lang): string
	local cfg = Config.Commanders
	local fmt = Strings.get("commander.passive." .. c, lang)
	if c == "Marshal" then
		return string.format(fmt, math.round(cfg.TankDiscount * 100))
	elseif c == "Admiral" then
		return string.format(fmt, math.round(cfg.ShipDiscount * 100), cfg.PortVision)
	elseif c == "Scout" then
		return fmt -- мощь соседей видна всегда (без чисел)
	end
	return string.format(fmt, math.round(cfg.BuildDiscount * 100))
end

CommanderPanel.passive = passive -- §15ф Ф1: тот же текст — в Арсенале

function CommanderPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> (),
	percent: () -> number
): CommanderPanel
	local function me(): ClientState.NationInfo?
		return if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
	end
	local function choosing(): boolean
		if not Config.Match.LobbyVotes then
			return false -- §15ф Ф1: генерал выбирается в Арсенале, не в лобби
		end
		local n = me()
		return n ~= nil and (cs.phase == "Lobby" or cs.phase == "Pick" or cs.phase == "Waiting")
	end
	local function playing(): boolean
		local n = me()
		return cs.phase == "Play" and n ~= nil and n.alive
	end

	-- Карточки выбора (лобби и выбор старта).
	local picker = Instance.new("Frame")
	picker.Name = "CommanderPicker"
	picker.AnchorPoint = Vector2.new(0.5, 1)
	picker.Position = UDim2.new(0.5, 0, 1, -12)
	picker.Size = UDim2.fromOffset(4 * CARD_W + 3 * 6, CARD_H + 24)
	picker.BackgroundTransparency = 1
	picker.Visible = false
	picker.Parent = gui
	local pickScale = Instance.new("UIScale")
	pickScale.Parent = picker
	local function fit()
		pickScale.Scale = math.clamp((gui.AbsoluteSize.X - 24) / (4 * CARD_W + 18), 0.5, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()
	local pickTitle = text(picker, 15, true)
	pickTitle.Size = UDim2.new(1, 0, 0, 20)
	pickTitle.TextXAlignment = Enum.TextXAlignment.Center
	pickTitle.TextColor3 = Theme.Colors.Gold
	pickTitle.Text = Strings.get("commander.pick", lang)
	local cards: { [string]: { button: TextButton, edge: UIStroke, lock: TextLabel } } = {}
	for k, raw in Types.CommanderIds do
		local id: Types.CommanderId = raw :: any
		local b = Instance.new("TextButton")
		b.Name = id
		b.Position = UDim2.fromOffset((k - 1) * (CARD_W + 6), 24)
		b.Size = UDim2.fromOffset(CARD_W, CARD_H)
		b.BackgroundColor3 = Theme.Colors.PanelBg
		b.BackgroundTransparency = 0.05
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.Text = ""
		local edge = stroke(b, Theme.Colors.PanelBorder)
		local name = text(b, 15, true)
		name.Position = UDim2.fromOffset(8, 6)
		name.Size = UDim2.new(1, -16, 0, 18)
		name.Text = Strings.get("commander." .. id, lang)
		local body = text(b, 12)
		body.Position = UDim2.fromOffset(8, 28)
		body.Size = UDim2.new(1, -16, 1, -32)
		body.TextColor3 = Theme.Colors.Muted
		body.Text = string.format(
			"%s\nQ — %s\nE — %s",
			passive(id, lang),
			Strings.get("ability." .. Commanders.ability(id, 1), lang),
			Strings.get("ability." .. Commanders.ability(id, 2), lang)
		)
		b.Parent = picker
		-- Замок (§11.2): генерал откроется на уровне N или пассом «Все генералы».
		local lock = text(b, 12, true)
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -6, 0, 6)
		lock.Size = UDim2.fromOffset(90, 16)
		lock.TextXAlignment = Enum.TextXAlignment.Right
		lock.TextColor3 = Theme.Colors.Alert
		lock.Text =
			string.format(Strings.get("commander.locked", lang), (Config.Profile.CommanderLevels :: any)[id] or 1)
		lock.Visible = false
		cards[id] = { button = b, edge = edge, lock = lock }
		Session.connect(b.Activated, function()
			if choosing() then
				send("commander", { commander = id })
			end
		end)
	end

	-- §15х ч.4–5: панель «УДАРЫ» (игра) — четыре плитки: Q и E генерала, R ракета, налёт. У плитки картинка
	-- (ItemArt «strike.*»), клавиша, название, состояние («ГОТОВО» / «88 с» / «нужна шахта») и полоса перезарядки;
	-- готовая — яркая рамка цвета удара, не готовая — бледная. Наведение — что делает удар (строка внизу панели).
	local cfgS = Config.Render.Strikes
	local TILE_W, TILE_H, ART_H = cfgS.TileW, cfgS.TileH, cfgS.ArtH
	local PAD, GAP = 10, 6
	local bar = Instance.new("Frame")
	bar.Name = "Abilities"
	bar.Position = UDim2.fromOffset(12, 64)
	bar.Size = UDim2.fromOffset(2 * PAD + 4 * TILE_W + 3 * GAP, PAD + 22 + TILE_H + 8 + 34 + PAD)
	bar.BackgroundColor3 = Theme.Colors.PanelBg
	bar.BackgroundTransparency = 0.08
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar:SetAttribute("FrontirStyled", true)
	bar.Parent = gui
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 12)
	barCorner.Parent = bar
	stroke(bar, Theme.Colors.PanelBorder)
	local barScale = Instance.new("UIScale")
	barScale.Parent = bar
	local function fitBar()
		barScale.Scale = math.clamp(gui.AbsoluteSize.X * cfgS.MaxScreenShare / bar.Size.X.Offset, 0.6, 1)
	end
	Session.connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fitBar)
	fitBar()
	local header = text(bar, 14, true)
	header.Position = UDim2.fromOffset(PAD, PAD)
	header.Size = UDim2.new(1, -2 * PAD, 0, 18)
	header.RichText = true
	header.TextColor3 = Theme.Colors.Gold

	type Tile = {
		button: TextButton,
		art: ImageLabel,
		name: TextLabel,
		state: TextLabel,
		fill: Frame,
		edge: UIStroke,
		accent: Color3,
	}
	local ACCENTS = { Theme.Colors.Gold, Theme.Colors.Gold, Theme.Colors.Alert, Theme.color("Orange") }
	local tiles: { Tile } = {}
	local buttons: { TextButton } = {}
	local hovered: number? = nil
	for slot = 1, 4 do
		local b = Instance.new("TextButton")
		b.Name = if slot == RAID then "Raid" else "Ability" .. slot
		b.Position = UDim2.fromOffset(PAD + (slot - 1) * (TILE_W + GAP), PAD + 22)
		b.Size = UDim2.fromOffset(TILE_W, TILE_H)
		b.BackgroundColor3 = Theme.Colors.Backdrop
		b.BackgroundTransparency = 0.1
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.Text = ""
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = b
		local edge = stroke(b, Theme.Colors.PanelBorder)
		edge.Thickness = 2
		local art = CardKit.art(b, if slot == MISSILE then "strike.missile" else "strike.raid", TILE_W - 8, ART_H)
		art.Position = UDim2.fromOffset(4, 4)
		local artCorner = Instance.new("UICorner")
		artCorner.CornerRadius = UDim.new(0, 7)
		artCorner.Parent = art
		local key = text(b, 13, true)
		key.Name = "Key"
		key.Position = UDim2.fromOffset(8, 8)
		key.Size = UDim2.fromOffset(20, 20)
		key.BackgroundColor3 = Theme.color("Ink")
		key.BackgroundTransparency = 0.15
		key.TextXAlignment = Enum.TextXAlignment.Center
		key.TextYAlignment = Enum.TextYAlignment.Center
		key.TextColor3 = Theme.Colors.Gold
		key.Text = if slot == RAID then "✈" else (KEY_NAMES[slot] or "R")
		key.ZIndex = 3
		local keyCorner = Instance.new("UICorner")
		keyCorner.CornerRadius = UDim.new(0, 5)
		keyCorner.Parent = key
		local name = text(b, 13, true)
		name.Name = "Title"
		name.Position = UDim2.fromOffset(4, ART_H + 8)
		name.Size = UDim2.new(1, -8, 0, 16)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextWrapped = false
		local state = text(b, 12, true)
		state.Name = "State"
		state.Position = UDim2.fromOffset(4, ART_H + 26)
		state.Size = UDim2.new(1, -8, 0, 15)
		state.TextXAlignment = Enum.TextXAlignment.Center
		state.TextTruncate = Enum.TextTruncate.AtEnd
		state.TextWrapped = false
		-- Полоса перезарядки (у налёта — сколько бомбардировщиков на аэродроме).
		local track = Instance.new("Frame")
		track.Name = "Bar"
		track.Position = UDim2.new(0, 8, 1, -9)
		track.Size = UDim2.new(1, -16, 0, 4)
		track.BackgroundColor3 = Theme.color("Ink")
		track.BorderSizePixel = 0
		track.Parent = b
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = ACCENTS[slot]
		fill.Parent = track
		for _, f in { track, fill } do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = f
		end
		b.Parent = bar
		tiles[slot] =
			{ button = b, art = art, name = name, state = state, fill = fill, edge = edge, accent = ACCENTS[slot] }
		buttons[slot] = b
		Session.connect(b.MouseEnter, function()
			hovered = slot
		end)
		Session.connect(b.MouseLeave, function()
			if hovered == slot then
				hovered = nil
			end
		end)
	end
	-- Внизу: что делает удар под курсором; иначе — «ПКМ по врагу — все удары по нему».
	local hint = text(bar, 12)
	hint.Name = "Hint"
	hint.Position = UDim2.fromOffset(PAD, PAD + 22 + TILE_H + 8)
	hint.Size = UDim2.new(1, -2 * PAD, 0, 34)
	hint.TextColor3 = Theme.Colors.Muted
	hint.Text = Strings.get("strikes.hint", lang)

	-- Строка режима цели и действующего эффекта (сверху по центру).
	local modeLine = Instance.new("TextButton")
	modeLine.Name = "AbilityMode"
	modeLine.AnchorPoint = Vector2.new(0.5, 0)
	modeLine.Position = UDim2.new(0.5, 0, 0, 170)
	modeLine.Size = UDim2.fromOffset(420, BUTTON)
	modeLine.BackgroundColor3 = Theme.Colors.Backdrop
	modeLine.BackgroundTransparency = 0.2
	modeLine.BorderSizePixel = 0
	modeLine.FontFace = Theme.FontBold
	modeLine.TextSize = 14
	modeLine.TextWrapped = true
	modeLine.TextColor3 = Theme.Colors.Gold
	modeLine.Visible = false
	stroke(modeLine, Theme.Colors.Gold)
	modeLine.Parent = gui

	local pending: number? = nil -- слот, ждущий цели
	local howUntil = 0 -- §15х ч.4: до какого os.clock() висит подсказка «что сделать»
	local startRaid: () -> () = function() end
	local function showHow(kind: StrikeMenu.Kind, why: string, f: StrikeMenu.Facts)
		pending = nil
		modeLine.Text = StrikeStatus.how(kind, why, f, lang)
		modeLine.Visible = true
		howUntil = os.clock() + HOW_SEC
	end
	-- §15ж: боеголовка шахты — повторное R переключает «Ракета → Атомная → Водородная → отмена».
	local WARHEADS: { Types.Warhead } = { "missile", "atom", "hydrogen" }
	local warhead = 1
	local function warheadLine(): string
		local kind = WARHEADS[warhead]
		local name = Strings.get("warhead." .. kind, lang)
		local nuke = if kind == "atom"
			then Config.Nukes.Atom
			elseif kind == "hydrogen" then Config.Nukes.Hydrogen
			else nil
		if nuke == nil then
			return string.format(Strings.get("missile.targetWarhead", lang), name)
		end
		return string.format(
			Strings.get("missile.targetNuke", lang),
			name,
			Strings.formatInt(nuke.cost),
			Strings.formatInt(nuke.oil)
		)
	end
	local function abilityName(slot: number): string
		return Strings.get("ability." .. Commanders.ability(ClientState.myCommander(cs), slot), lang)
	end
	local function leftOf(slot: number, now: number): number
		if slot == MISSILE then
			return math.max(0, cs.world.missileLeft - (now - cs.worldAt) * ClientState.simRate(cs))
		end
		return math.max(0, cs.commander.left[slot] - (now - cs.commanderAt) * ClientState.simRate(cs))
	end
	local function cancel()
		pending = nil
		howUntil = 0
		modeLine.Visible = false
	end
	-- Готова ли способность слота: перезарядка; удар по врагу — только когда идёт война (как StrikeMenu.ability).
	local function abilityWhy(slot: number, atWar: boolean, now: number): string
		if leftOf(slot, now) > 0 then
			return "cooldown"
		end
		local ability = Commanders.ability(ClientState.myCommander(cs), slot)
		if StrikeMenu.EnemyAbilities[ability] and not atWar then
			return "notAtWar"
		end
		return "ok"
	end
	local function activate(slot: number)
		if not playing() then
			return
		end
		if slot == RAID then
			local f = StrikeStatus.facts(cs, nil, os.clock())
			local why = StrikeMenu.raid(f)
			if why ~= "ok" then
				showHow("raid", why, f)
				return
			end
			cancel()
			startRaid()
			return
		end
		if slot == MISSILE then
			local f = StrikeStatus.facts(cs, nil, os.clock())
			local why = StrikeMenu.missile(f)
			if why ~= "ok" and pending ~= slot then
				showHow("missile", why, f)
				return
			end
			if pending == slot then
				warhead += 1
				if warhead > #WARHEADS then
					warhead = 1
					cancel()
					return
				end
			else
				warhead = 1
			end
			pending = slot
			modeLine.Text = warheadLine()
			modeLine.Visible = true
			return
		end
		if pending == slot then
			cancel()
			return
		end
		local ability = Commanders.ability(ClientState.myCommander(cs), slot)
		local f = StrikeStatus.facts(cs, nil, os.clock())
		local why = abilityWhy(slot, f.atWar, os.clock())
		if why ~= "ok" then
			f.abilityLeft = leftOf(slot, os.clock())
			showHow("ability", why, f)
			return
		end
		if not Commanders.needsTarget(ability) then
			cancel()
			send("ability", { slot = slot })
			return
		end
		pending = slot
		modeLine.Text = string.format(Strings.get("ability.target", lang), abilityName(slot))
		modeLine.Visible = true
	end
	for slot, b in buttons do
		Session.connect(b.Activated, function()
			activate(slot)
		end)
	end
	Session.connect(modeLine.Activated, cancel)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		for slot, key in KEYS do
			if input.KeyCode == key then
				activate(slot)
			end
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			cancel()
		end
	end)

	local function update(now: number)
		if not bar.Visible then
			return
		end
		local facts = StrikeStatus.facts(cs, nil, now)
		local commander: Types.CommanderId = ClientState.myCommander(cs)
		for slot, tile in tiles do
			local why: string
			local progress: number
			if slot == RAID then
				why = StrikeMenu.raid(facts)
				progress = if facts.bombers > 0 then facts.bombersReady / facts.bombers else 0
				tile.name.Text = Strings.get("ring.raid", lang)
			elseif slot == MISSILE then
				why = StrikeMenu.missile(facts)
				local cd = Config.Buildings.MissileSilo.cooldownSec
				progress = if facts.silo then 1 - facts.missileLeft / cd else 0
				tile.name.Text = Strings.get("ring.missile", lang)
			else
				local ability = Commanders.ability(commander, slot)
				local left = leftOf(slot, now)
				why = abilityWhy(slot, facts.atWar, now)
				progress = 1 - left / math.max(1, Commanders.cooldown(commander, slot))
				tile.name.Text = Strings.get("ability." .. ability, lang)
			end
			local ready = why == "ok"
			local active = pending == slot
			local kind: StrikeMenu.Kind = if slot == RAID
				then "raid"
				elseif slot == MISSILE then "missile"
				else "ability"
			if ready then
				tile.state.Text = if slot == RAID
					then string.format(Strings.get("strikes.raidReady", lang), facts.bombersReady)
					else Strings.get("strikes.ready", lang)
			elseif why == "cooldown" then
				local left = if slot == MISSILE then facts.missileLeft else leftOf(slot, now)
				tile.state.Text = string.format(Strings.get("missile.cooldown", lang), math.ceil(left))
			else
				tile.state.Text = StrikeStatus.short(kind, why, facts, lang)
			end
			tile.state.TextColor3 = if ready
				then Theme.color("Lime")
				elseif why == "cooldown" then Theme.color("Orange")
				else Theme.Colors.Muted
			tile.name.TextColor3 = if ready then Theme.Colors.Text else Theme.Colors.Muted
			tile.art.ImageTransparency = if ready or active then 0 else 0.55
			tile.edge.Color = if active
				then Theme.Colors.Gold
				elseif ready then tile.accent
				else Theme.Colors.PanelBorder
			tile.edge.Thickness = if active then 3 else 2
			tile.fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
			tile.fill.BackgroundColor3 = if ready then tile.accent else Theme.Colors.Muted
		end
		-- Подсказка внизу панели: что делает удар под курсором.
		local h = hovered
		if h == nil then
			hint.Text = Strings.get("strikes.hint", lang)
		elseif h == RAID then
			hint.Text = Strings.get("strikes.desc.raid", lang)
		elseif h == MISSILE then
			hint.Text = Strings.get("strikes.desc.missile", lang)
		else
			-- «%%» в описании — шаблонный знак процента; сюда текст идёт аргументом, поэтому — «%».
			hint.Text = (
				string.gsub(Strings.get("ability.desc." .. Commanders.ability(commander, h), lang), "%%%%", "%%")
			)
		end
		-- Действующий эффект (прорыв, вспышка) — в строке режима, если не ждём цели и нет подсказки.
		if pending == nil and os.clock() < howUntil then
			modeLine.Visible = true
		elseif pending == nil then
			local elapsed = (now - cs.commanderAt) * ClientState.simRate(cs)
			local surge = cs.commander.surge - elapsed
			local reveal = cs.commander.reveal - elapsed
			if surge > 0 then
				modeLine.Text = string.format(
					Strings.get("ability.active", lang),
					Strings.get("ability.Surge", lang),
					math.ceil(surge)
				)
				modeLine.Visible = true
			elseif reveal > 0 then
				modeLine.Text = string.format(
					Strings.get("ability.active", lang),
					Strings.get("ability.Reveal", lang),
					math.ceil(reveal)
				)
				modeLine.Visible = true
			else
				modeLine.Visible = false
			end
		end
	end

	local function refresh()
		picker.Visible = choosing()
		if picker.Visible then
			local mine = ClientState.myCommander(cs)
			local profile = cs.profile
			for id, c in cards do
				c.edge.Color = if id == mine then Theme.Colors.Gold else Theme.Colors.PanelBorder
				c.edge.Thickness = if id == mine then 2 else Theme.BorderPx
				local locked = profile ~= nil and not profile.unlocked[id]
				c.lock.Visible = locked
				c.button.BackgroundTransparency = if locked then 0.5 else 0.05
			end
		end
		bar.Visible = playing()
		if bar.Visible then
			local commander: Types.CommanderId = ClientState.myCommander(cs)
			header.Text = string.format(
				'%s   <font color="#%s">%s</font>',
				Strings.get("strikes.title", lang),
				Theme.Colors.Muted:ToHex(),
				string.format(Strings.get("strikes.commander", lang), Strings.get("commander." .. commander, lang))
			)
			-- Картинки способностей — по генералу (сменился — перерисовать).
			for slot = 1, 2 do
				CardKit.repaint(tiles[slot].art, "strike." .. Commanders.ability(commander, slot))
			end
		else
			cancel()
		end
		update(os.clock())
	end

	local function tap(cell: number): boolean
		local slot = pending
		if slot == nil or not playing() then
			return false
		end
		cancel()
		if slot == MISSILE then
			send("missile", { cell = cell, warhead = WARHEADS[warhead] })
		else
			send("ability", { slot = slot, cell = cell, percent = percent() })
		end
		return true
	end

	refresh()
	return {
		aiming = function(): Types.Warhead?
			return if pending == MISSILE then WARHEADS[warhead] else nil
		end,
		pickerFrame = picker,
		setRaid = function(start: () -> ())
			startRaid = start
		end,
		refresh = refresh,
		update = update,
		tap = tap,
		isOpen = function(): boolean
			return picker.Visible or bar.Visible
		end,
	}
end

return table.freeze(CommanderPanel)
