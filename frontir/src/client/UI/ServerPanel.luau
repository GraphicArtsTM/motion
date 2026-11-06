--!strict
--[[
	ServerPanel — частный сервер (GDD §5.4, этап 8г).
	- Все в лобби: строка сверху «Частный сервер · карта · режим · держав · …».
	- Владелец: кнопка «Настройки сервера (O)» и окно — строки «◀ значение ▶» для каждой настройки, «Применить»
	  (намерение settings) и «Закрыть». Значения — только из списков Config.PrivateServer; проверяет сервер.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local ServerSettings = require(Shared:WaitForChild("ServerSettings"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type Settings = ServerSettings.Settings

export type ServerPanel = {
	refresh: () -> (), -- пришло info
	-- Самопроверка (сводная правка, часть 1): открыть/закрыть окно и узнать, открыто ли.
	toggle: () -> (),
	isOpen: () -> boolean,
}

local ServerPanel = {}

local BUTTON = Config.Render.MinTouchTargetPx
local W = 360
local ROW = BUTTON + 4

local function label(parent: Instance, size: number, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = if bold then Theme.FontBold else Theme.Font
	t.TextSize = size
	t.TextColor3 = Theme.Colors.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.RichText = true
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string, w: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, BUTTON)
	b.BackgroundColor3 = Theme.Colors.PanelBg
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = Theme.Font
	b.TextSize = 14
	b.TextColor3 = Theme.Colors.Text
	b.Text = text
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = Theme.Colors.PanelBorder
	s.Thickness = Theme.BorderPx
	s.Parent = b
	b.Parent = parent
	return b
end

-- Следующее значение по кругу списка.
local function cycle<T>(list: { T }, value: T, dir: number): T
	local k = table.find(list, value) or 1
	return list[(k - 1 + dir) % #list + 1]
end

function ServerPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	send: (string, { [string]: any }) -> ()
): ServerPanel
	local function onOff(v: boolean): string
		return Strings.get(if v then "server.on" else "server.off", lang)
	end
	local function mapName(id: string?): string
		return if id == nil then Strings.get("server.vote", lang) else Strings.get("map." .. id, lang)
	end
	local function modeName(id: Types.ModeId?): string
		return if id == nil then Strings.get("server.vote", lang) else Strings.get("mode." .. id, lang)
	end
	local function levelName(level: Types.BotLevel?): string
		return Strings.get("mode.level." .. (level or "Mix"), lang)
	end

	-- Строка для всех (лобби).
	local summary = label(gui, 13)
	summary.Name = "PrivateServer"
	summary.AnchorPoint = Vector2.new(0.5, 0)
	summary.Position = UDim2.new(0.5, 0, 0, 72)
	summary.Size = UDim2.fromOffset(640, 18)
	summary.TextXAlignment = Enum.TextXAlignment.Center
	summary.TextColor3 = Theme.Colors.Sky
	summary.Visible = false

	local openButton = button(gui, Strings.get("server.open", lang), 220)
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -12, 0, 72)
	openButton.Visible = false

	-- Окно настроек (владелец).
	local window = Instance.new("Frame")
	window.Name = "ServerSettings"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.BackgroundColor3 = Theme.Colors.PanelBg
	window.BorderSizePixel = 0
	window.Visible = false
	window.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = window
	local title = label(window, 16, true)
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.fromOffset(W - 24, 22)
	title.TextColor3 = Theme.Colors.Gold
	title.Text = Strings.get("server.title", lang)

	local draft: Settings? = nil
	type Row = { value: TextLabel, key: string }
	local rows: { Row } = {}
	local y = 38
	local function addRow(key: string, change: (s: Settings, dir: number) -> ())
		local name = label(window, 13)
		name.Position = UDim2.fromOffset(12, y)
		name.Size = UDim2.fromOffset(120, BUTTON)
		name.TextYAlignment = Enum.TextYAlignment.Center
		name.Text = Strings.get("server." .. key, lang)
		local prev = button(window, "◀", BUTTON)
		prev.Position = UDim2.fromOffset(136, y)
		local value = label(window, 13, true)
		value.Position = UDim2.fromOffset(136 + BUTTON + 4, y)
		value.Size = UDim2.fromOffset(W - 136 - 2 * BUTTON - 24, BUTTON)
		value.TextXAlignment = Enum.TextXAlignment.Center
		value.TextYAlignment = Enum.TextYAlignment.Center
		local nextButton = button(window, "▶", BUTTON)
		nextButton.Position = UDim2.fromOffset(W - 12 - BUTTON, y)
		local function step(dir: number)
			local s = draft
			if s ~= nil then
				change(s, dir)
				ServerPanel.draw(rows, s, mapName, modeName, levelName, onOff)
			end
		end
		Session.connect(prev.Activated, function()
			step(-1)
		end)
		Session.connect(nextButton.Activated, function()
			step(1)
		end)
		table.insert(rows, { value = value, key = key })
		y += ROW
	end

	local cfg = Config.PrivateServer
	local maps: { string } = { "" }
	for _, id in Config.MapVote.Pool do
		table.insert(maps, id)
	end
	local modes: { string } = { "" }
	for _, id in Types.ModeIds do
		if id ~= "Duel" then
			table.insert(modes, id)
		end
	end
	local levels: { string } = { "", "Novice", "Normal", "General" }
	addRow("map", function(s, dir)
		local v = cycle(maps, s.map or "", dir)
		s.map = if v == "" then nil else v
		local mapId = s.map or (ReplicatedStorage:GetAttribute("MapId") :: string?) or ""
		s.nations = math.min(s.nations, ServerSettings.maxNations(mapId))
	end)
	addRow("mode", function(s, dir)
		local v = cycle(modes, s.mode or "", dir)
		s.mode = if v == "" then nil else v :: Types.ModeId
	end)
	addRow("nations", function(s, dir)
		local mapId = s.map or (ReplicatedStorage:GetAttribute("MapId") :: string?) or ""
		s.nations = math.clamp(s.nations + dir, cfg.MinNations, ServerSettings.maxNations(mapId))
	end)
	addRow("bots", function(s, dir)
		local v = cycle(levels, s.botLevel or "", dir)
		s.botLevel = if v == "" then nil else v :: Types.BotLevel
	end)
	addRow("speed", function(s, dir)
		s.speed = cycle(cfg.Speeds, s.speed, dir)
	end)
	addRow("money", function(s, dir)
		s.startMoney = cycle(cfg.StartMoney, s.startMoney, dir)
	end)
	addRow("fog", function(s)
		s.fog = not s.fog
	end)
	addRow("diplomacy", function(s)
		s.diplomacy = not s.diplomacy
	end)
	addRow("boosts", function(s)
		s.boosts = not s.boosts
	end)
	local apply = button(window, Strings.get("server.apply", lang), 160)
	apply.Position = UDim2.fromOffset(12, y + 6)
	apply.TextColor3 = Theme.Colors.Gold
	local close = button(window, Strings.get("server.close", lang), 160)
	close.Position = UDim2.fromOffset(W - 12 - 160, y + 6)
	window.Size = UDim2.fromOffset(W, y + 6 + BUTTON + 12)

	local function isOwner(): boolean
		return cs.server ~= nil and cs.server.isOwner and (cs.phase == "Lobby" or cs.phase == "Waiting")
	end
	local function open()
		local info = cs.server
		if info == nil or not isOwner() then
			return
		end
		draft = table.clone(info.settings)
		ServerPanel.draw(rows, draft :: Settings, mapName, modeName, levelName, onOff)
		window.Visible = true
	end
	Session.connect(openButton.Activated, open)
	Session.connect(close.Activated, function()
		window.Visible = false
	end)
	Session.connect(apply.Activated, function()
		local s = draft
		if s ~= nil then
			send("settings", s :: any)
			window.Visible = false
		end
	end)
	Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.O then
			if window.Visible then
				window.Visible = false
			else
				open()
			end
		end
	end)

	local function refresh()
		local info = cs.server
		local lobby = cs.phase == "Lobby" or cs.phase == "Waiting"
		summary.Visible = info ~= nil and lobby
		openButton.Visible = info ~= nil and isOwner()
		if not isOwner() then
			window.Visible = false
		end
		if info ~= nil then
			local s = info.settings
			summary.Text = string.format(
				Strings.get("server.summary", lang),
				mapName(s.map),
				modeName(s.mode),
				s.nations,
				levelName(s.botLevel),
				tostring(s.speed),
				Strings.formatInt(s.startMoney),
				onOff(s.fog),
				onOff(s.diplomacy)
			)
		end
	end

	return {
		refresh = refresh,
		toggle = function()
			if window.Visible then
				window.Visible = false
			else
				open()
			end
		end,
		isOpen = function(): boolean
			return window.Visible
		end,
	}
end

-- Значения строк окна по черновику настроек.
function ServerPanel.draw(
	rows: { { value: TextLabel, key: string } },
	s: Settings,
	mapName: (string?) -> string,
	modeName: (Types.ModeId?) -> string,
	levelName: (Types.BotLevel?) -> string,
	onOff: (boolean) -> string
)
	for _, row in rows do
		local k = row.key
		row.value.Text = if k == "map"
			then mapName(s.map)
			elseif k == "mode" then modeName(s.mode)
			elseif k == "nations" then tostring(s.nations)
			elseif k == "bots" then levelName(s.botLevel)
			elseif k == "speed" then "×" .. tostring(s.speed)
			elseif k == "money" then "$" .. Strings.formatInt(s.startMoney)
			elseif k == "fog" then onOff(s.fog)
			elseif k == "boosts" then onOff(s.boosts)
			else onOff(s.diplomacy)
	end
end

return table.freeze(ServerPanel)
