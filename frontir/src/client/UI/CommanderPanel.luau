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
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type CommanderPanel = {
	refresh: () -> (), -- пришли info / commander или сменилась фаза
	update: (now: number) -> (), -- обратные отсчёты
	tap: (cell: number) -> boolean, -- true — нажатие ушло в цель способности
}

local CommanderPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local CARD_W, CARD_H = 176, 112
local KEYS = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.R }
local KEY_NAMES = { "Q", "E" }
local MISSILE = 3 -- третий «слот» — ракета из своей шахты (§6.9, этап 7г)

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
		return string.format(fmt, tostring(cfg.VisionMul))
	end
	return string.format(fmt, math.round(cfg.BuildDiscount * 100))
end

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
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	local pickTitle = text(picker, 15, true)
	pickTitle.Size = UDim2.new(1, 0, 0, 20)
	pickTitle.TextXAlignment = Enum.TextXAlignment.Center
	pickTitle.TextColor3 = Theme.Colors.Gold
	pickTitle.Text = Strings.get("commander.pick", lang)
	local cards: { [string]: { button: TextButton, edge: UIStroke } } = {}
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
		cards[id] = { button = b, edge = edge }
		b.Activated:Connect(function()
			if choosing() then
				send("commander", { commander = id })
			end
		end)
	end

	-- Кнопки способностей (игра).
	local bar = Instance.new("Frame")
	bar.Name = "Abilities"
	bar.Position = UDim2.fromOffset(12, 64)
	bar.Size = UDim2.fromOffset(240, 3 * BUTTON + 12 + 20)
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = gui
	local header = text(bar, 13, true)
	header.Size = UDim2.new(1, 0, 0, 18)
	header.TextColor3 = Theme.Colors.Gold
	local buttons: { TextButton } = {}
	for slot = 1, 3 do
		local b = Instance.new("TextButton")
		b.Name = "Ability" .. slot
		b.Position = UDim2.fromOffset(0, 20 + (slot - 1) * (BUTTON + 6))
		b.Size = UDim2.new(1, 0, 0, BUTTON)
		b.BackgroundColor3 = Theme.Colors.PanelBg
		b.BackgroundTransparency = 0.1
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.FontFace = Theme.FontBold
		b.TextSize = 13
		b.TextWrapped = true
		b.TextXAlignment = Enum.TextXAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.Parent = b
		stroke(b, Theme.Colors.PanelBorder)
		b.Parent = bar
		buttons[slot] = b
	end

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
	local function abilityName(slot: number): string
		return Strings.get("ability." .. Commanders.ability(ClientState.myCommander(cs), slot), lang)
	end
	local function leftOf(slot: number, now: number): number
		if slot == MISSILE then
			return math.max(0, cs.world.missileLeft - (now - cs.worldAt) * Config.Match.Speed)
		end
		return math.max(0, cs.commander.left[slot] - (now - cs.commanderAt) * Config.Match.Speed)
	end
	local function cancel()
		pending = nil
		modeLine.Visible = false
	end
	local function activate(slot: number)
		if not playing() then
			return
		end
		if pending == slot then
			cancel()
			return
		end
		if slot == MISSILE then
			if not cs.world.silo then
				return
			end
			pending = slot
			modeLine.Text = Strings.get("missile.target", lang)
			modeLine.Visible = true
			return
		end
		local ability = Commanders.ability(ClientState.myCommander(cs), slot)
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
		b.Activated:Connect(function()
			activate(slot)
		end)
	end
	modeLine.Activated:Connect(cancel)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
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
		for slot, b in buttons do
			local left = leftOf(slot, now)
			if slot == MISSILE then
				b.Visible = cs.world.silo
				b.Text = string.format(
					Strings.get("missile.button", lang),
					if left > 0
						then string.format(Strings.get("missile.cooldown", lang), math.ceil(left))
						else Strings.get("missile.ready", lang)
				)
				b.TextColor3 = if left > 0
					then Theme.Colors.Muted
					elseif pending == slot then Theme.Colors.Gold
					else Theme.Colors.Alert
				continue
			end
			local key = KEY_NAMES[slot]
			if left > 0 then
				b.Text = string.format(
					Strings.get("ability.cooldown", lang),
					key .. " " .. abilityName(slot),
					math.ceil(left)
				)
				b.TextColor3 = Theme.Colors.Muted
			else
				b.Text = string.format(
					Strings.get("ability.ready", lang),
					key .. " " .. abilityName(slot),
					Strings.get("ability.desc." .. Commanders.ability(ClientState.myCommander(cs), slot), lang)
				)
				b.TextColor3 = if pending == slot then Theme.Colors.Gold else Theme.Colors.Text
			end
		end
		-- Действующий эффект (прорыв, вспышка) — в строке режима, если не ждём цели.
		if pending == nil then
			local elapsed = (now - cs.commanderAt) * Config.Match.Speed
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
			for id, c in cards do
				c.edge.Color = if id == mine then Theme.Colors.Gold else Theme.Colors.PanelBorder
				c.edge.Thickness = if id == mine then 2 else Theme.BorderPx
			end
		end
		bar.Visible = playing()
		if bar.Visible then
			header.Text = string.format(
				Strings.get("commander.label", lang),
				Strings.get("commander." .. ClientState.myCommander(cs), lang)
			)
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
			send("missile", { cell = cell })
		else
			send("ability", { slot = slot, cell = cell, percent = percent() })
		end
		return true
	end

	refresh()
	return { refresh = refresh, update = update, tap = tap }
end

return table.freeze(CommanderPanel)
