--!strict
--[[
	FeedbackLayer — отклик на действия игрока (GDD §15й Й4). Планы и числа — чистый FeedbackFx, частицы — общий
	движок StrikeFxLayer.spawn. На карте (canvas): «→ N» у точки нажатия атаки, вспышки своей новой земли (взятой у
	ничьих), искры и «Готово!» над достроенным зданием. На экране (HUD): «3 · 2 · 1» перед стартом и «В БОЙ!» (камера —
	к своей столице), монеты от места награды к деньгам на полосе, «пульс» денег и «+N» над готовыми войсками.
	Всё — пулы, на телефоне меньше (Render.Phone.Feedback), на карте — только в кадре.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local FeedbackFx = require(Shared:WaitForChild("FeedbackFx"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local StrikeFx = require(Shared:WaitForChild("StrikeFx"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local UiScale = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UiScale"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type Spawner = (parts: { StrikeFx.Part }, owner: number, delay: number, low: boolean) -> ()

export type Deps = {
	moneyLabel: TextLabel, -- куда летят монеты
	armyLabel: TextLabel, -- над чем всплывает «+N»
	army: () -> number, -- войска сейчас (дома и на фронтах)
	toCapital: (cell: number) -> (), -- камера к своей столице (старт матча)
}

export type FeedbackLayer = {
	sent: (cell: number, percent: number, people: number) -> (), -- нажатие атаки
	onEvents: (events: { any }) -> (),
	onSnapshot: () -> (),
	onDelta: (cells: { number }) -> (),
	update: (now: number, state: CameraState) -> (),
}

type Floater = { label: TextLabel, cell: number, born: number, life: number, rise: number }
type Flash = { frame: Frame, cell: number, born: number }
type Coin = { frame: Frame, x0: number, y0: number, k: number, n: number, born: number, done: boolean }

local FeedbackLayer = {}

function FeedbackLayer.new(
	canvas: Frame,
	hud: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	spawn: Spawner,
	deps: Deps
): FeedbackLayer
	local cfg = Config.Render.Feedback
	local phone = RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local maxGrow = if phone then Config.Render.Phone.Feedback.GrowFlashes else cfg.GrowFlashes
	local maxCoins = if phone then Config.Render.Phone.Feedback.Coins else cfg.Coins
	local w, h = cs.width, cs.height
	local memory = buffer.create(w * h) -- прежний владелец клетки (u8) — чтобы отличить рост от захвата
	local lastState: CameraState? = nil
	local seed = 0
	local white = Theme.color("White")

	local function ownerAt(i: number): number
		return ClientState.ownerAt(cs, i)
	end
	local function nationColor(id: number): Color3
		local ci = ClientState.colorIndexOf(cs, id)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Gold
	end
	local function inView(cell: number): boolean
		local st = lastState
		if st == nil then
			return false
		end
		local x0, y0, x1, y1 = CameraMath.visibleRect(st)
		local cx, cy = cell % w, cell // w
		return cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1
	end

	-- Надписи на карте («→ N», «Готово!»): поднимаются и тают.
	local floaters: { Floater } = {}
	local function floatText(cell: number, text: string, color: Color3, size: number, life: number)
		if #floaters >= 12 or not inView(cell) then
			return
		end
		local l = Instance.new("TextLabel")
		l.AnchorPoint = Vector2.new(0.5, 1)
		l.BackgroundTransparency = 1
		l.FontFace = Theme.FontBold
		l.TextSize = size
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.25
		l.Size = UDim2.fromOffset(180, size + 4)
		l.ZIndex = 46
		l.Text = text
		l.Parent = canvas
		table.insert(floaters, { label = l, cell = cell, born = os.clock(), life = life, rise = 26 })
	end

	-- Вспышки роста (пул).
	local flashPool: { Frame } = {}
	local flashes: { Flash } = {}
	local function takeFlash(): Frame
		local f = table.remove(flashPool)
		if f == nil then
			local made = Instance.new("Frame")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.BorderSizePixel = 0
			made.ZIndex = 3 -- над территорией, под подсветками и значками
			made.Parent = canvas
			f = made
		end
		local frame = f :: Frame
		frame.Visible = true
		return frame
	end

	-- Экран: отсчёт старта и «В БОЙ!».
	local big = Instance.new("TextLabel")
	big.Name = "StartCountdown"
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Position = UDim2.fromScale(0.5, 0.4)
	big.Size = UDim2.fromOffset(600, 140)
	big.BackgroundTransparency = 1
	big.FontFace = Theme.FontHeavy
	big.TextSize = 110
	big.TextColor3 = Theme.Colors.Gold
	big.TextStrokeTransparency = 0.2
	big.TextStrokeColor3 = Theme.Colors.Backdrop
	big.Visible = false
	big.ZIndex = 30
	big.Parent = hud
	local bigScale = Instance.new("UIScale")
	bigScale.Parent = big
	local shownCount: string? = nil
	local goUntil = 0
	local lastPhase = cs.phase

	local function pop(scale: UIScale, from: number, sec: number)
		scale.Scale = from
		TweenService:Create(scale, TweenInfo.new(sec, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	-- «Пульс» счётчика.
	local function pulse(label: GuiObject)
		local sc = label:FindFirstChild("FeedbackPulse") :: UIScale?
		if sc == nil then
			local made = Instance.new("UIScale")
			made.Name = "FeedbackPulse"
			made.Parent = label
			sc = made
		end
		pop(sc :: UIScale, cfg.PulseScale, 0.35)
	end

	-- Монеты: от места события к деньгам на полосе (HUD, условные px).
	local coins: { Coin } = {}
	local function hudPoint(abs: Vector2): Vector2
		return (abs - hud.AbsolutePosition) / math.max(UiScale.factor(), 1e-3)
	end
	local function flyCoins(cell: number)
		local st = lastState
		if st == nil or #coins > maxCoins * 3 then
			return
		end
		local start: Vector2
		if inView(cell) then
			local local_ = Vector2.new((cell % w + 0.5) * st.zoom, (cell // w + 0.5) * st.zoom)
			start = hudPoint(canvas.AbsolutePosition + local_)
		else
			start = hudPoint(Vector2.new(hud.AbsoluteSize.X / 2, hud.AbsoluteSize.Y / 3))
		end
		local now = os.clock()
		for k = 1, maxCoins do
			local c = Instance.new("Frame")
			c.Name = "Coin"
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.Size = UDim2.fromOffset(14, 14)
			c.BackgroundColor3 = Theme.Colors.Gold
			c.BorderSizePixel = 0
			c.ZIndex = 31
			c.Visible = false
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = c
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.color("Ochre")
			stroke.Thickness = 2
			stroke.Parent = c
			c.Parent = hud
			table.insert(coins, {
				frame = c,
				x0 = start.X,
				y0 = start.Y,
				k = k,
				n = maxCoins,
				born = now + (k - 1) * cfg.CoinStaggerSec,
				done = false,
			})
		end
	end

	local function onSnapshot()
		for i = 0, w * h - 1 do
			buffer.writeu8(memory, i, math.clamp(ownerAt(i), 0, 255))
		end
	end

	local function onDelta(cells: { number })
		local me = cs.myNation
		local grown: { number } = {}
		for _, i in cells do
			if i >= 0 and i < w * h then
				local old = buffer.readu8(memory, i)
				local new = math.clamp(ownerAt(i), 0, 255)
				buffer.writeu8(memory, i, new)
				if old == 0 and me ~= nil and new == me and cs.phase == "Play" and inView(i) then
					table.insert(grown, i)
				end
			end
		end
		if #grown == 0 then
			return
		end
		local now = os.clock()
		for _, k in FeedbackFx.growFlashes(#grown, maxGrow - #flashes) do
			table.insert(flashes, { frame = takeFlash(), cell = grown[k], born = now })
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
			local cell = if type(e.cell) == "number" then e.cell else nil
			if e.kind == "built" and cell ~= nil then
				seed += 1
				if inView(cell) then
					spawn(FeedbackFx.builtSparks(cell % w + 0.5, cell // w + 0.5, seed), me, 0, false)
				end
				floatText(cell, Strings.get("fx.built", lang), Theme.Colors.Gold, cfg.BuiltPx, 1.4)
			elseif (e.kind == "taskDone" or e.kind == "trophy" or e.kind == "trainStop") and cell ~= nil then
				flyCoins(cell)
			end
		end
	end

	local lastArmy = -1
	local function update(now: number, state: CameraState)
		lastState = state
		local zoom = state.zoom
		-- Отсчёт перед стартом и «В БОЙ!».
		if cs.phase == "Pick" then
			local digit = FeedbackFx.countdown(cs.phaseEndsAt - now)
			if digit ~= shownCount then
				shownCount = digit
				if digit ~= nil then
					big.Text = digit
					big.TextColor3 = Theme.Colors.Gold
					pop(bigScale, 1.8, 0.4)
				end
			end
			big.Visible = digit ~= nil
		elseif lastPhase == "Pick" and cs.phase == "Play" and cs.myNation ~= nil then
			shownCount = nil
			big.Text = Strings.get("fx.go", lang)
			big.TextColor3 = Theme.Colors.Alert
			big.Visible = true
			pop(bigScale, 0.6, 0.35)
			goUntil = now + cfg.GoSec
			local n = cs.nations[cs.myNation]
			if n ~= nil and n.capital ~= nil then
				deps.toCapital(n.capital)
			end
		elseif now >= goUntil then
			big.Visible = false
		end
		lastPhase = cs.phase
		-- Надписи на карте.
		local k = 1
		while k <= #floaters do
			local f = floaters[k]
			local t = (now - f.born) / f.life
			if t >= 1 then
				f.label:Destroy()
				table.remove(floaters, k)
			else
				local cx, cy = f.cell % w, f.cell // w
				f.label.Position = UDim2.fromOffset((cx + 0.5) * zoom, cy * zoom - f.rise * t)
				f.label.TextTransparency = t * t
				f.label.TextStrokeTransparency = 0.25 + 0.75 * t
				k += 1
			end
		end
		-- Вспышки роста.
		local me = cs.myNation
		local base = if me ~= nil then nationColor(me):Lerp(white, cfg.GrowLighten) else white
		-- На общем плане клетка — пара пикселей: вспышка не меньше GrowMinPx (условные px экрана), иначе её не видно.
		local side = math.max(cfg.GrowMinPx * UiScale.factor(), zoom * cfg.GrowCells)
		k = 1
		while k <= #flashes do
			local fl = flashes[k]
			local t = (now - fl.born) / cfg.GrowFlashSec
			if t >= 1 then
				fl.frame.Visible = false
				table.insert(flashPool, fl.frame)
				flashes[k] = flashes[#flashes]
				flashes[#flashes] = nil
			else
				local f = fl.frame
				f.BackgroundColor3 = base
				f.BackgroundTransparency = 0.15 + 0.85 * t
				f.Position = UDim2.fromOffset((fl.cell % w + 0.5) * zoom, (fl.cell // w + 0.5) * zoom)
				f.Size = UDim2.fromOffset(side * (1 + 0.5 * t), side * (1 + 0.5 * t))
				k += 1
			end
		end
		-- Монеты.
		local target = hudPoint(deps.moneyLabel.AbsolutePosition + deps.moneyLabel.AbsoluteSize / 2)
		k = 1
		local landed = false
		while k <= #coins do
			local c = coins[k]
			local t = (now - c.born) / cfg.CoinSec
			if t >= 1 then
				c.frame:Destroy()
				table.remove(coins, k)
				landed = true
			else
				if t >= 0 then
					local x, y = FeedbackFx.coin(c.x0, c.y0, target.X, target.Y, c.k, c.n, t)
					c.frame.Position = UDim2.fromOffset(x, y)
					c.frame.Visible = true
				end
				k += 1
			end
		end
		if landed then
			pulse(deps.moneyLabel)
		end
		-- Войска готовы: «+N» над числом армии.
		local army = math.floor(deps.army())
		if lastArmy >= 0 and army > lastArmy and cs.phase == "Play" then
			local l = deps.armyLabel
			pulse(l)
			local plus = Instance.new("TextLabel")
			plus.BackgroundTransparency = 1
			plus.AnchorPoint = Vector2.new(0.5, 1)
			plus.Size = UDim2.fromOffset(120, 20)
			local at = hudPoint(l.AbsolutePosition + Vector2.new(l.AbsoluteSize.X / 2, 0))
			plus.Position = UDim2.fromOffset(at.X, at.Y)
			plus.FontFace = Theme.FontBold
			plus.TextSize = 16
			plus.TextColor3 = Theme.Colors.Sky
			plus.TextStrokeTransparency = 0.3
			plus.Text = "+" .. Strings.formatInt(army - lastArmy)
			plus.ZIndex = 31
			plus.Parent = hud
			TweenService:Create(plus, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(at.X, at.Y - 30),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
			task.delay(0.95, function()
				plus:Destroy()
			end)
		end
		lastArmy = army
	end

	return {
		sent = function(cell: number, percent: number, people: number)
			local n = FeedbackFx.sent(people, percent)
			if n > 0 then
				floatText(cell, "→ " .. Strings.formatInt(n), Theme.color("White"), cfg.SentPx, cfg.SentFloatSec)
			end
		end,
		onEvents = onEvents,
		onSnapshot = onSnapshot,
		onDelta = onDelta,
		update = update,
	}
end

return table.freeze(FeedbackLayer)
