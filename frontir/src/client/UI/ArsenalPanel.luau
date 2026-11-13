--!strict
--[[
	ArsenalPanel — окно «Арсенал» (GDD §15л ч.6): особое оружие навсегда за медали, в бой — одно.
	§15ц Ц5а: витрина шаблона CardKit, как Магазин и Гардероб — медали в шапке, вкладки «Оружие» и «Генералы»,
	карточки с картинкой, что даёт, ценой и кнопкой; внизу — подсказка, где взять медали.
	- Оружие: «Купить за 🏅 N» / «🔒 ур. N» / «Взять в бой» / «В бою ✓ (снять)»; метка «ПО КЛЕТКЕ» / «СРАЗУ».
	- Генералы (§15ф Ф1): картинка первой способности, пассивка, Q и E; «Генерал в бой» / «В бою ✓» / «🔒 ур. N».
	  Выбранный сохраняется в профиле (намерение prefCommander) и ставится в каждый матч до начала игры.
	Открывается из главного меню и меню игры (U).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local CommanderPanel = require(script.Parent:WaitForChild("CommanderPanel"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type ArsenalPanel = {
	toggle: () -> (),
	isOpen: () -> boolean,
	refresh: () -> (),
	window: Frame,
}

local ArsenalPanel = {}

local ICONS: { [string]: string } = {
	Reinforce = "reinforce",
	Convoy = "convoy",
	HqReserve = "hqReserve",
	Barrage = "barrage",
	Jammer = "jammer",
}
ArsenalPanel.Icons = ICONS

function ArsenalPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): ArsenalPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local order = Config.Arsenal.Order
	local items = Config.Arsenal.Items

	local win = CardKit.window(gui, "ArsenalWindow", t("arsenal.title"), t("arsenal.subtitle"), 860, 720, {
		{ key = "items", label = t("arsenal.tab.items") },
		{ key = "generals", label = t("arsenal.tab.generals") },
	}, nil, true)
	local window = win.frame
	local medalsChip = CardKit.chip(win.chips, "money", 1)
	local foot = win.footer :: CardKit.Footer
	local function hint(tab: string)
		foot.set("", false, t(if tab == "generals" then "arsenal.generalsHint" else "arsenal.hint"))
	end
	win.onTab(hint)
	hint(win.tab())

	local function level(): number
		local p = cs.profile
		return if p ~= nil then p.level else 1
	end
	local function arsenal(): { owned: { [string]: boolean }, loadout: string?, used: boolean }
		local p = cs.profile
		local a = if p ~= nil then p.arsenal else nil
		return a or { owned = {}, loadout = nil, used = false }
	end
	local function medals(): number
		local p = cs.profile
		return if p ~= nil then p.medals else 0
	end

	-- Оружие.
	type ItemCard = { key: string, card: CardKit.Card, action: TextButton }
	local itemCards: { ItemCard } = {}
	for k, key in order do
		local card =
			CardKit.card(win.page("items"), "arsenal." .. key, t("arsenal.item." .. key), t("arsenal.desc." .. key), k)
		card.tag.Visible = true
		card.tag.Text = t(if items[key].target then "arsenal.tagTarget" else "arsenal.tagInstant")
		local action = CardKit.button(card.actions, "", "primary", 1)
		Session.connect(action.Activated, function()
			local a = arsenal()
			local it = items[key]
			if a.loadout == key then
				send("arsenalEquip", {}) -- снять (ничего не брать)
			elseif a.owned[key] then
				send("arsenalEquip", { key = key })
			elseif level() >= it.level and medals() >= it.price then
				send("arsenalBuy", { key = key })
			end
		end)
		table.insert(itemCards, { key = key, card = card, action = action })
	end

	-- Генералы.
	type GeneralCard = { id: Types.CommanderId, card: CardKit.Card, action: TextButton }
	local generalCards: { GeneralCard } = {}
	for k, raw in Types.CommanderIds do
		local id: Types.CommanderId = raw :: any
		local desc = string.format(
			"%s\nQ — %s · E — %s",
			CommanderPanel.passive(id, lang),
			t("ability." .. Commanders.ability(id, 1)),
			t("ability." .. Commanders.ability(id, 2))
		)
		local card =
			CardKit.card(win.page("generals"), "strike." .. Commanders.ability(id, 1), t("commander." .. id), desc, k)
		local action = CardKit.button(card.actions, "", "primary", 1)
		Session.connect(action.Activated, function()
			local need = (Config.Profile.CommanderLevels :: any)[id] or 1
			if level() >= need then
				send("prefCommander", { commander = id })
			end
		end)
		table.insert(generalCards, { id = id, card = card, action = action })
	end

	local function style(b: TextButton, enabled: boolean)
		b.Active = enabled
		b.AutoButtonColor = enabled
		b.BackgroundTransparency = if enabled then 0 else 0.45
	end

	local function draw()
		local have = medals()
		local a = arsenal()
		medalsChip.Text = Strings.formatInt(have)
		for _, c in itemCards do
			local it = items[c.key]
			local owned = a.owned[c.key] == true
			local inBattle = a.loadout == c.key
			c.card.price.Text = if inBattle
				then t("arsenal.inBattle")
				elseif owned then t("arsenal.owned")
				else string.format(t("arsenal.progress"), Strings.formatInt(have), Strings.formatInt(it.price))
			c.card.price.TextColor3 = if inBattle
				then Theme.Colors.Good
				elseif owned then Theme.Colors.Sky
				else Theme.Colors.Gold
			c.card.edge.Color = if inBattle then Theme.Colors.Good else Theme.Colors.PanelBorder
			c.card.dim.Visible = not owned and level() < it.level
			if inBattle then
				c.action.Text = t("arsenal.inBattleBtn")
				style(c.action, true)
			elseif owned then
				c.action.Text = t("arsenal.equip")
				style(c.action, true)
			elseif level() < it.level then
				c.action.Text = string.format(t("arsenal.lockLevel"), it.level)
				style(c.action, false)
			else
				c.action.Text = string.format(t("arsenal.buy"), Strings.formatInt(it.price))
				style(c.action, have >= it.price)
			end
		end
		local p = cs.profile
		local pref = (if p ~= nil and p.arsenal ~= nil then p.arsenal.commander else nil) or "Marshal"
		for _, g in generalCards do
			local need = (Config.Profile.CommanderLevels :: any)[g.id] or 1
			local locked = level() < need
			local on = g.id == pref
			g.card.dim.Visible = locked
			g.card.edge.Color = if on then Theme.Colors.Gold else Theme.Colors.PanelBorder
			g.card.edge.Thickness = if on then 3 else 2
			g.card.price.Text = ""
			if locked then
				g.action.Text = string.format(t("commander.locked"), need)
				style(g.action, false)
			elseif on then
				g.action.Text = t("arsenal.generalOn")
				style(g.action, false)
			else
				g.action.Text = t("arsenal.generalPick")
				style(g.action, true)
			end
		end
	end

	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
			draw()
		end
	end
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.U then
			toggle()
		end
	end)

	return {
		toggle = toggle,
		isOpen = function(): boolean
			return window.Visible
		end,
		refresh = function()
			if window.Visible then
				draw()
			end
		end,
		window = window,
	}
end

return table.freeze(ArsenalPanel)
