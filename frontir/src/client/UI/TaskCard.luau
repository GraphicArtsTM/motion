--!strict
--[[
	TaskCard — задача матча (GDD §15й Й1): карточка «ЗАДАЧА» сверху по центру (столбик TopCenter): значок вида,
	что сделать, прогресс, таймер, награда и серия; нажатие — камера к цели, «×» — пропустить (намерение taskSkip).
	Цель-город на карте — «дышащее» золотое кольцо (рамка на canvas). Выполнено — карточка вспыхивает золотом
	«Выполнено! +$N», не успели — гаснет «Не успели»; новая — «выпрыгивает». Данные — cs.task (раз в секунду),
	таймер идёт сам (ClientState.taskLeft); события taskNew / taskDone / taskFailed — сразу.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MapData = require(Shared:WaitForChild("MapData"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type TaskCard = {
	frame: Frame,
	update: (now: number, state: CameraState) -> (),
	onEvents: (events: { any }) -> (),
	setCompact: (on: boolean) -> (),
}

local ICONS: { [string]: string } = { City = "City", Land = "land", Build = "build", Front = "army" }
local KEYS: { [string]: string } = { Barracks = "2", Factory = "3", Housing = "4" }

local TaskCard = {}

function TaskCard.new(
	gui: ScreenGui,
	canvas: Frame,
	cs: ClientState,
	map: MapData.MapData,
	provinces: Provinces.ProvinceSet,
	lang: Strings.Lang,
	send: (kind: string, payload: any) -> (),
	focus: (cell: number) -> ()
): TaskCard
	local cfg = Config.Render.Task
	local function t(key: string): string
		return Strings.get(key, lang)
	end

	local frame = Instance.new("Frame")
	frame.Name = "TaskCard"
	frame.Size = UDim2.fromOffset(cfg.WidthPx, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BackgroundTransparency = Theme.PanelAlpha
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	frame:SetAttribute("FrontirStyled", true)
	MenuKit.corner(frame, 10)
	MenuKit.pad(frame, 12, 8)
	MenuKit.stroke(frame, Theme.Colors.Gold, 1)
	local pop = Instance.new("UIScale")
	pop.Parent = frame
	-- Содержимое — столбиком в body; кнопка «к цели» — поверх body (вне раскладки).
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = frame
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = body

	-- Ряд 1: значок | «ЗАДАЧА · серия» и текст | награда и таймер | «×».
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 40)
	top.LayoutOrder = 1
	top.Parent = body
	local iconHost = Instance.new("Frame")
	iconHost.Name = "IconHost"
	iconHost.BackgroundTransparency = 1
	iconHost.Size = UDim2.fromOffset(36, 36)
	iconHost.Position = UDim2.fromOffset(0, 2)
	iconHost.Parent = top
	local head = MenuKit.label(top, t("task.title"), 12, Theme.Colors.Gold, true)
	head.Position = UDim2.fromOffset(44, 0)
	local text = MenuKit.label(top, "", 16, Theme.Colors.Text, true)
	text.Position = UDim2.fromOffset(44, 16)
	text.AutomaticSize = Enum.AutomaticSize.None
	text.Size = UDim2.new(1, -170, 0, 22)
	text.TextTruncate = Enum.TextTruncate.AtEnd
	local reward = MenuKit.label(top, "", 18, Theme.Colors.Gold, true)
	reward.AnchorPoint = Vector2.new(1, 0)
	reward.Position = UDim2.new(1, -30, 0, 0)
	reward.TextXAlignment = Enum.TextXAlignment.Right
	local timer = MenuKit.label(top, "", 14, Theme.Colors.Muted, true)
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, -30, 0, 22)
	timer.TextXAlignment = Enum.TextXAlignment.Right
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.fromScale(1, 0)
	skip.Size = UDim2.fromOffset(24, 24)
	skip.BackgroundColor3 = Theme.Colors.Slate
	skip.BorderSizePixel = 0
	skip.FontFace = Theme.FontBold
	skip.TextSize = 14
	skip.TextColor3 = Theme.Colors.Muted
	skip.Text = "×"
	skip.ZIndex = 3
	skip.Parent = top
	MenuKit.corner(skip, 6)

	-- Ряд 2: полоса прогресса и «сколько из скольких».
	local barRow = Instance.new("Frame")
	barRow.Name = "Progress"
	barRow.BackgroundTransparency = 1
	barRow.Size = UDim2.new(1, 0, 0, 14)
	barRow.LayoutOrder = 2
	barRow.Parent = body
	local bar = MenuKit.bar(barRow, 6, Theme.Colors.Gold)
	bar.frame.AnchorPoint = Vector2.new(0, 0.5)
	bar.frame.Position = UDim2.fromScale(0, 0.5)
	bar.frame.Size = UDim2.new(1, -96, 0, 6)
	local count = MenuKit.label(barRow, "", 12, Theme.Colors.Muted, true)
	count.AnchorPoint = Vector2.new(1, 0.5)
	count.Position = UDim2.fromScale(1, 0.5)
	count.TextXAlignment = Enum.TextXAlignment.Right

	-- Ряд 3: как это сделать.
	local hint = MenuKit.wrapLabel(body, "", 12, Theme.Colors.Muted, 3)
	hint.Name = "Hint"

	-- Нажатие на карточку — камера к цели (кнопка под «×»).
	local hit = Instance.new("TextButton")
	hit.Name = "Focus"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 2
	hit.Parent = frame

	-- Кольцо цели на карте.
	local ring = Instance.new("Frame")
	ring.Name = "TaskRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundColor3 = Theme.Colors.Gold
	ring.BackgroundTransparency = 0.88
	ring.BorderSizePixel = 0
	ring.Visible = false
	ring.ZIndex = 9
	ring.Parent = canvas
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Theme.Colors.Gold
	ringStroke.Thickness = 3
	ringStroke.Parent = ring

	local shownId = 0
	local shownKind = ""
	local flashUntil = 0
	local flashText = ""
	local flashGood = false
	local compact = false

	local function nationName(id: number): string
		local n = cs.nations[id]
		if n == nil then
			return "?"
		end
		return if lang == "en" then n.nameEn else n.name
	end
	local function cityName(cell: number): string
		local name = Provinces.cityName(provinces, map, cell)
		return if lang == "en" then name.en else name.ru
	end
	local function clock(sec: number): string
		local s = math.max(0, math.ceil(sec))
		return string.format("%d:%02d", s // 60, s % 60)
	end
	local function target(): number?
		local msg = cs.task
		local task = if msg ~= nil then msg.task else nil
		if task == nil then
			return nil
		end
		if task.kind == "City" then
			return task.cell
		elseif task.kind == "Front" then
			local n = cs.nations[task.target]
			return if n ~= nil then n.capital else nil
		end
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		return if me ~= nil then me.capital else nil
	end

	Session.connect(skip.Activated, function()
		send("taskSkip", {})
	end)
	Session.connect(hit.Activated, function()
		local c = target()
		if c ~= nil then
			focus(c)
		end
	end)

	local function setIcon(kind: string)
		for _, child in iconHost:GetChildren() do
			child:Destroy()
		end
		local icon = MenuKit.icon(iconHost, ICONS[kind] or "quests", if compact then 3 else 4)
		icon.Position = UDim2.fromOffset(2, 2)
	end

	local function fill(task: ClientState.TaskInfo, msg: ClientState.TaskMessage, now: number)
		if task.kind == "City" then
			text.Text = string.format(t("task.City"), cityName(task.cell))
			hint.Text = UiScale.touchText(frame, t(if task.target ~= 0 then "task.City.enemy" else "task.City.hint"))
		elseif task.kind == "Land" then
			local pct = math.floor(task.need / math.max(1, msg.land) * 1000 + 0.5) / 10
			text.Text = string.format(t("task.Land"), tostring(pct))
			hint.Text = t("task.Land.hint")
		elseif task.kind == "Build" then
			text.Text = string.format(t("task.Build"), t("building." .. task.building))
			hint.Text = UiScale.touchText(frame, string.format(t("task.Build.hint"), KEYS[task.building] or "B"))
		else
			text.Text = string.format(t("task.Front"), Strings.formatInt(task.need), nationName(task.target))
			hint.Text = t("task.Front.hint")
		end
		local mul = 1 + Config.Tasks.Streak.Step * msg.streak
		head.Text = t("task.title")
			.. (
				if msg.streak > 0
					then "  ·  " .. string.format(t("task.streak"), tostring(math.min(mul, Config.Tasks.Streak.Max)))
					else ""
			)
		reward.Text = string.format(t("task.reward"), Strings.formatInt(task.reward))
		local left = ClientState.taskLeft(cs, now) / math.max(ClientState.simRate(cs), 1e-3)
		timer.Text = clock(left)
		timer.TextColor3 = if left <= cfg.UrgentSec then Theme.Colors.Alert else Theme.Colors.Muted
		-- Прогресс: земля и фронт — клетками, город и стройка — временем (полоса тает).
		if task.kind == "Land" then
			local done = math.max(0, task.have - task.base)
			local need = math.max(1, task.need - task.base)
			bar.set(done / need)
			count.Text = string.format(t("task.progress"), Strings.formatInt(done), Strings.formatInt(need))
		elseif task.kind == "Front" then
			bar.set(task.have / math.max(1, task.need))
			count.Text = string.format(t("task.progress"), Strings.formatInt(task.have), Strings.formatInt(task.need))
		else
			bar.set(ClientState.taskLeft(cs, now) / math.max(1, task.total))
			count.Text = ""
		end
		hint.Visible = not compact
	end

	local function update(now: number, state: CameraState)
		local msg = cs.task
		local task = if msg ~= nil then msg.task else nil
		local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
		local playing = cs.phase == "Play" and me ~= nil and me.alive
		local flashing = now < flashUntil
		frame.Visible = playing and (task ~= nil or flashing)
		if not frame.Visible then
			ring.Visible = false
			return
		end
		skip.Visible = not flashing
		if flashing then
			text.Text = flashText
			text.TextColor3 = if flashGood then Theme.Colors.Gold else Theme.Colors.Muted
			reward.Text = ""
			timer.Text = ""
			count.Text = ""
			hint.Visible = false
			bar.set(if flashGood then 1 else 0)
			local k = math.clamp((flashUntil - now) / cfg.FlashSec, 0, 1)
			frame.BackgroundColor3 = if flashGood
				then Theme.Colors.PanelBg:Lerp(Theme.Colors.Gold, 0.35 * k)
				else Theme.Colors.PanelBg
			frame.BackgroundTransparency = if flashGood then Theme.PanelAlpha else 0.3 + 0.5 * (1 - k)
			ring.Visible = false
			return
		end
		frame.BackgroundColor3 = Theme.Colors.PanelBg
		frame.BackgroundTransparency = Theme.PanelAlpha
		text.TextColor3 = Theme.Colors.Text
		if task == nil or msg == nil then
			ring.Visible = false
			return
		end
		if task.id ~= shownId then
			shownId = task.id
			pop.Scale = 0.85
			TweenService:Create(pop, TweenInfo.new(cfg.SlideSec, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
		if task.kind ~= shownKind then
			shownKind = task.kind
			setIcon(task.kind)
		end
		fill(task, msg, now)
		-- Кольцо вокруг города-цели: «дышит», не меньше RingMinPx на экране.
		if task.kind == "City" then
			local zoom = state.zoom
			local cx, cy = task.cell % cs.width, task.cell // cs.width
			local x = (CameraMath.cellEdge(zoom, cx) + CameraMath.cellEdge(zoom, cx + 1)) / 2
			local y = (CameraMath.cellEdge(zoom, cy) + CameraMath.cellEdge(zoom, cy + 1)) / 2
			local pulse = 0.5 + 0.5 * math.sin(now * 2 * math.pi / cfg.PulseSec)
			local side = math.max(cfg.RingMinPx * 2, cfg.RingCells * 2 * zoom) * (1 + 0.15 * pulse)
			ring.Position = UDim2.fromOffset(x, y)
			ring.Size = UDim2.fromOffset(side, side)
			ringStroke.Transparency = 0.1 + 0.4 * pulse
			ring.Visible = true
		else
			ring.Visible = false
		end
	end

	local function onEvents(events: { any })
		local me = cs.myNation
		if me == nil then
			return
		end
		for _, e in events do
			if type(e) ~= "table" or e.nation ~= me then
				continue
			end
			if e.kind == "taskDone" then
				flashGood = true
				flashText = string.format(t("task.done"), Strings.formatInt(tonumber(e.reward) or 0))
				flashUntil = os.clock() + cfg.FlashSec
				pop.Scale = 1.08
				TweenService:Create(pop, TweenInfo.new(cfg.FlashSec * 0.5, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
			elseif e.kind == "taskFailed" then
				flashGood = false
				flashText = t("task.failed")
				flashUntil = os.clock() + cfg.FlashSec
			end
		end
	end

	local function setCompact(on: boolean)
		compact = on
		frame.Size = UDim2.fromOffset(if on then cfg.PhoneWidthPx else cfg.WidthPx, 0)
		hint.Visible = not on
		-- §15й: на телефоне карточка ниже и уже: значок меньше, задача в две строки мельче (имя цели не
		-- обрезается), награда и таймер — справа столбиком; полоса — тоньше.
		top.Size = UDim2.new(1, 0, 0, 40)
		iconHost.Size = UDim2.fromOffset(if on then 28 else 36, if on then 28 else 36)
		head.TextSize = if on then 10 else 12
		head.Position = UDim2.fromOffset(if on then 34 else 44, 0)
		text.TextSize = if on then 13 else 16
		text.TextWrapped = on
		text.TextTruncate = if on then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
		text.Position = UDim2.fromOffset(if on then 34 else 44, if on then 12 else 16)
		text.Size = UDim2.new(1, if on then -130 else -170, 0, if on then 30 else 22)
		reward.TextSize = if on then 15 else 18
		timer.TextSize = if on then 12 else 14
		timer.Position = UDim2.new(1, -30, 0, if on then 18 else 22)
		barRow.Size = UDim2.new(1, 0, 0, if on then 10 else 14)
		bar.frame.Size = UDim2.new(1, if on then -64 else -96, 0, if on then 4 else 6)
		count.TextSize = if on then 11 else 12
		shownKind = "" -- значок другого размера — перерисовать
	end

	return { frame = frame, update = update, onEvents = onEvents, setCompact = setCompact }
end

return table.freeze(TaskCard)
