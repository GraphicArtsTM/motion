--!strict
--[[
	SelfCheck — самопроверка в Studio (сводная правка, часть 1). Кнопка F4 «Самопроверка» запускает шаги:
	окна (открыть и закрыть), панель генерала, действия F4, меню аэродрома и порта, все способности всех генералов,
	все случайные события, ракета, две смены карты. После каждого шага в Output — PASS / FAIL с причиной (SKIP —
	шаг здесь невозможен, в итог не входит), в конце «Итог: N из M». Ошибки скриптов клиента и сервера за время
	проверки тоже считаются как FAIL.
	§15ц Ц5г: окна ещё проверяются на «влезает в экран» (frame), блок «Экран матча» — заголовки групп полосы, кнопки
	у мини-карты, без наложений главных рамок HUD, одно окно за раз.

	Модуль живёт над сессиями (смена карты пересоздаёт сессию): каждая сессия зовёт attach со своими окнами.
	Только Studio: действия идут через Remotes.Dev, которого в опубликованной игре нет.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Types = require(Shared:WaitForChild("Types"))
local WorldEvents = require(Shared:WaitForChild("WorldEvents"))

type ClientState = ClientState.ClientState

-- frame — имя рамки окна в слое (FrontirHud / FrontirWindows): §15ц Ц5г «влезает в экран».
export type Window = { name: string, toggle: () -> (), isOpen: () -> boolean, skip: (() -> string?)?, frame: string? }
export type Menu = { tap: (cell: number, zoom: number) -> boolean, close: () -> (), isOpen: () -> boolean }

export type Context = {
	cs: ClientState,
	mapId: string,
	windows: { Window },
	commanderOpen: () -> boolean,
	air: Menu,
	naval: Menu,
	zoom: () -> number,
	hud: ScreenGui, -- §15ц Ц5г: экран матча (полоса, кнопки, наложения)
}

local SelfCheck = {}

local ctx: Context? = nil
local running = false
local acks: { [string]: { ok: boolean, reason: string? } } = {}
local serverErrors: { string }? = nil

function SelfCheck.attach(c: Context)
	ctx = c
end

-- Сообщения dev от сервера: подтверждения действий и ошибки сервера за проверку.
function SelfCheck.onDev(msg: any)
	if type(msg) ~= "table" then
		return
	end
	if type(msg.ack) == "string" then
		acks[msg.ack] = { ok = msg.ok == true, reason = if type(msg.reason) == "string" then msg.reason else nil }
	end
	if type(msg.serverErrors) == "table" then
		serverErrors = msg.serverErrors
	end
end

local function waitFor(cond: () -> boolean, timeout: number): boolean
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		if cond() then
			return true
		end
		task.wait(0.1)
	end
	return cond()
end

local function remote(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local dev = if remotes ~= nil then remotes:FindFirstChild("Dev") else nil
	return if dev ~= nil and dev:IsA("RemoteEvent") then dev else nil
end

-- Действие F4 на сервере; ждёт подтверждения. Возвращает ok и причину отказа.
local function dev(action: string, arg: any): (boolean, string?)
	local event = remote()
	if event == nil then
		return false, "нет Remotes.Dev (не Studio?)"
	end
	acks[action] = nil
	event:FireServer(action, arg)
	if not waitFor(function(): boolean
		return acks[action] ~= nil
	end, 8) then
		return false, "сервер не ответил за 8 с"
	end
	local a = acks[action] :: { ok: boolean, reason: string? }
	return a.ok, a.reason
end

local function myBuilding(cs: ClientState, kind: string): number?
	local me = cs.myNation
	for cell, b in cs.buildings do
		if b.kind == kind and ClientState.ownerAt(cs, cell) == me then
			return cell
		end
	end
	return nil
end

-- §15ц Ц5г: рамка окна по имени среди окон слоёв игрока.
local function findFrame(hud: ScreenGui, name: string): GuiObject?
	local pg = hud.Parent
	if pg == nil then
		return nil
	end
	for _, layer in pg:GetChildren() do
		if layer:IsA("ScreenGui") then
			local f = layer:FindFirstChild(name)
			if f ~= nil and f:IsA("GuiObject") then
				return f
			end
		end
	end
	return nil
end

-- Рамка целиком в своём слое (±2 px); иначе — что вылезло.
local function insideLayer(g: GuiObject): (boolean, string?)
	local layer = g:FindFirstAncestorWhichIsA("ScreenGui")
	if layer == nil then
		return false, "нет слоя"
	end
	local p, s, area = g.AbsolutePosition - layer.AbsolutePosition, g.AbsoluteSize, layer.AbsoluteSize
	if p.X < -2 or p.Y < -2 or p.X + s.X > area.X + 2 or p.Y + s.Y > area.Y + 2 then
		return false,
			string.format("рамка %dx%d в (%d, %d), экран %dx%d", s.X, s.Y, p.X, p.Y, area.X, area.Y)
	end
	return true, nil
end

-- Пересекаются ли две видимые рамки больше чем на 2 px по каждой оси.
local function overlaps(a: GuiObject, b: GuiObject): boolean
	local pa, sa, pb, sb = a.AbsolutePosition, a.AbsoluteSize, b.AbsolutePosition, b.AbsoluteSize
	local w = math.min(pa.X + sa.X, pb.X + sb.X) - math.max(pa.X, pb.X)
	local h = math.min(pa.Y + sa.Y, pb.Y + sb.Y) - math.max(pa.Y, pb.Y)
	return w > 2 and h > 2
end

-- Видна ли рамка на экране (и все её предки).
local function shown(g: GuiObject): boolean
	if g.AbsoluteSize.X <= 0 or g.AbsoluteSize.Y <= 0 then
		return false
	end
	local node: Instance? = g
	while node ~= nil and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node ~= nil and (node :: ScreenGui).Enabled
end

local function anyBot(cs: ClientState): number?
	for id, n in cs.nations do
		if n.isBot and n.alive and id ~= cs.myNation then
			return id
		end
	end
	return nil
end

local function run()
	local passed, total, skipped = 0, 0, 0
	local clientErrors: { string } = {}
	local conn = ScriptContext.Error:Connect(function(message: string, trace: string)
		if #clientErrors < 50 then
			table.insert(clientErrors, message .. " | " .. string.sub(trace, 1, 200))
		end
	end)
	local function report(name: string, ok: boolean?, reason: string?)
		if ok == nil then
			skipped += 1
			print(string.format("[Самопроверка] SKIP  %s — %s", name, reason or ""))
			return
		end
		total += 1
		if ok then
			passed += 1
			print(string.format("[Самопроверка] PASS  %s", name))
		else
			warn(string.format("[Самопроверка] FAIL  %s — %s", name, reason or "?"))
		end
	end
	-- Шаг: функция возвращает ok (nil — SKIP) и причину; ошибка внутри — FAIL.
	local function step(name: string, fn: () -> (boolean?, string?))
		local okCall, ok, reason = pcall(fn)
		if not okCall then
			report(name, false, "ошибка шага: " .. tostring(ok))
		else
			report(name, ok, reason)
		end
	end
	local function f4(name: string, action: string, arg: any, allowed: { string }?)
		step("F4: " .. name, function(): (boolean?, string?)
			local ok, reason = dev(action, arg)
			if not ok and allowed ~= nil and reason ~= nil and table.find(allowed, reason) ~= nil then
				return true, nil
			end
			return ok, reason
		end)
	end

	print("[Самопроверка] начало")
	serverErrors = nil
	dev("selfCheck", "start")

	local c = ctx
	if c == nil then
		report("сессия клиента", false, "нет сессии")
	else
		local cs = c.cs
		step("игра идёт (фаза Play)", function(): (boolean?, string?)
			local ok = waitFor(function(): boolean
				return cs.phase == "Play"
			end, 120)
			return ok, if ok then nil else "фаза " .. cs.phase .. " — дождитесь игры"
		end)

		-- 1. Окна.
		for _, w in c.windows do
			step("окно «" .. w.name .. "»: открыть и закрыть", function(): (boolean?, string?)
				local why = if w.skip ~= nil then w.skip() else nil
				if why ~= nil then
					return nil, why
				end
				if w.isOpen() then
					w.toggle()
					task.wait(0.2)
				end
				w.toggle()
				task.wait(0.3)
				if not w.isOpen() then
					return false, "не открылось"
				end
				-- §15ц Ц5г: окно влезает в экран.
				local frameName = w.frame
				if frameName ~= nil then
					local f = findFrame(c.hud, frameName)
					if f == nil then
						w.toggle()
						return false, "нет рамки " .. frameName
					end
					local inside, why2 = insideLayer(f)
					if not inside then
						w.toggle()
						return false, "не влезает в экран: " .. tostring(why2)
					end
				end
				w.toggle()
				task.wait(0.3)
				if w.isOpen() then
					return false, "не закрылось"
				end
				return true, nil
			end)
		end
		step("панель генерала на экране", function(): (boolean?, string?)
			return c.commanderOpen(), "нет кнопок способностей"
		end)

		-- 1а. Экран матча (§15ц Ц3–Ц5).
		local hud = c.hud
		step("полоса: шесть групп с заголовками", function(): (boolean?, string?)
			local bar = hud:FindFirstChild("CommandBar")
			if bar == nil or not bar:IsA("GuiObject") or not shown(bar) then
				return false, "полосы нет на экране"
			end
			for _, group in { "Nation", "People", "Attack", "Money", "Hire", "Build" } do
				local g = bar:FindFirstChild(group)
				local caption = if g ~= nil then g:FindFirstChild("Caption") else nil
				if caption == nil then
					return false, "нет заголовка у группы " .. group
				end
			end
			return true, nil
		end)
		step("кнопки окон и зум у мини-карты", function(): (boolean?, string?)
			local buttons = hud:FindFirstChild("MapButtons")
			local zoom = hud:FindFirstChild("ZoomButtons")
			if buttons == nil or not buttons:IsA("GuiObject") or not shown(buttons) then
				return false, "кнопок окон нет на экране"
			end
			if zoom == nil or not zoom:IsA("GuiObject") or not shown(zoom) then
				return false, "кнопок зума нет на экране"
			end
			local n = 0
			for _, b in buttons:GetChildren() do
				if b:IsA("GuiButton") and b.Visible then
					n += 1
				end
			end
			return n >= 4, string.format("видно кнопок %d из 4", n)
		end)
		step(
			"без наложений: полоса, мини-карта, столбики, «УДАРЫ», лента",
			function(): (boolean?, string?)
				local names = {
					"CommandBar",
					"MapButtons",
					"ZoomButtons",
					"Minimap",
					"TopCenter",
					"TopRight",
					"Abilities",
					"AttackArea",
					"AttackChips",
					"MenuButton",
				}
				local frames: { GuiObject } = {}
				for _, name in names do
					local g = hud:FindFirstChild(name)
					if g ~= nil and g:IsA("GuiObject") and shown(g) then
						table.insert(frames, g)
					end
				end
				local bad: { string } = {}
				for i = 1, #frames do
					for j = i + 1, #frames do
						if overlaps(frames[i], frames[j]) then
							table.insert(bad, frames[i].Name .. " × " .. frames[j].Name)
						end
					end
				end
				return #bad == 0, table.concat(bad, ", ")
			end
		)
		step(
			"одно окно за раз: Дипломатия → Технологии",
			function(): (boolean?, string?)
				local diplo: Window? = nil
				local tech: Window? = nil
				for _, w in c.windows do
					if w.name == "дипломатия" then
						diplo = w
					elseif w.name == "технологии" then
						tech = w
					end
				end
				if diplo == nil or tech == nil then
					return nil, "нет окон в списке"
				end
				local d, t = diplo :: Window, tech :: Window
				if not d.isOpen() then
					d.toggle()
				end
				task.wait(0.3)
				t.toggle()
				task.wait(0.4)
				local ok = t.isOpen() and not d.isOpen()
				if t.isOpen() then
					t.toggle()
				end
				if d.isOpen() then
					d.toggle()
				end
				return ok,
					"Дипломатия не закрылась, когда открылись Технологии"
			end
		)

		-- 2. Действия F4 (основные кнопки).
		local bot = anyBot(cs)
		-- §15ц Ц5г: сначала земля — со стартом в одну провинцию внутри материка нет берега (порт, десант), провинции
		-- для восстания и места под шахту и аэродром: такие шаги падали не из-за игры, а из-за старта.
		f4("сверхдержава (земля для проверок)", "giant", nil, { "noLand" })
		task.wait(1)
		f4("+войска", "grant", "forces")
		f4("+люди", "grant", "people")
		f4("+деньги", "grant", "money")
		f4("жетоны", "tokens", nil)
		f4("опыт", "xp", nil)
		f4("медали", "medals", nil)
		f4("Совет сейчас", "council", nil)
		f4("стабильность низкая", "stability", "low")
		f4("стабильность высокая", "stability", "high")
		f4("восстание", "revolt", nil, { "target" })
		f4("изучить все технологии", "researchAll", nil)
		f4("закончить исследование", "finishResearch", nil, { "noResearch" })
		f4("время ×5", "speed", nil)
		f4("время ×1", "speed", nil)
		f4("туман", "fog", nil)
		f4("туман обратно", "fog", nil)
		f4("способности готовы", "resetCooldowns", nil)
		f4("следующий генерал", "nextCommander", nil)
		f4("торговое судно", "tradeNow", nil, { "needCoast", "noPartner" }) -- §15е
		if bot ~= nil then
			f4("война сейчас", "war", bot)
			f4("бот: десант на вас", "botLanding", bot, { "noPort", "target", "occupied" })
			f4("бот: налёт на вас", "botRaid", bot, { "target", "occupied" })
			f4("бот: способности по вам", "botAbility", bot, { "target" })
			f4("бот: ракета по вам", "botMissile", bot, { "target", "occupied" })
			f4("бот: атомная бомба по вам", "botNuke", bot, { "target", "occupied", "cooldown" }) -- §15ж
			f4("белый мир", "peace", bot, { "notAtWar", "target" })
		else
			report("F4: действия с ботом", nil, "нет живого бота")
		end

		-- 3. Меню аэродрома и порта.
		local function menu(name: string, action: string, kind: string, m: Menu)
			step("меню «" .. name .. "»: открыть и закрыть", function(): (boolean?, string?)
				local ok, reason = dev(action, nil)
				if not ok then
					return false, "F4 " .. action .. ": " .. tostring(reason)
				end
				local cell: number? = nil
				if
					not waitFor(function(): boolean
						cell = myBuilding(cs, kind)
						return cell ~= nil
					end, 5)
				then
					return false, "здание " .. kind .. " не пришло клиенту"
				end
				m.tap(cell :: number, c.zoom())
				task.wait(0.3)
				if not m.isOpen() then
					return false, "не открылось по нажатию на здание"
				end
				m.close()
				task.wait(0.2)
				if m.isOpen() then
					return false, "не закрылось"
				end
				return true, nil
			end)
		end
		menu("аэродром", "airForce", "Airfield", c.air)
		menu("порт", "navy", "Port", c.naval)

		-- 4. Способности всех генералов и события.
		for _, commander in Types.CommanderIds do
			for slot = 1, 2 do
				step(
					string.format("способность %s %s", commander, if slot == 1 then "Q" else "E"),
					function()
						return dev("selfAbility", { commander = commander, slot = slot })
					end
				)
			end
		end
		for _, kind in WorldEvents.Kinds do
			step("событие " .. kind, function()
				return dev("worldEvent", kind)
			end)
		end
		f4("ракетная шахта", "silo", nil)

		-- 5. Смена карты дважды (сессия клиента пересоздаётся).
		for k = 1, 2 do
			step("смена карты " .. k, function(): (boolean?, string?)
				local before = (ctx :: Context).mapId
				local ok, reason = dev("mapNow", nil)
				if not ok then
					return false, reason
				end
				local changed = waitFor(function(): boolean
					local now = ctx
					return now ~= nil and now.mapId ~= before
				end, 60)
				if not changed then
					return false, "карта не сменилась за 60 с"
				end
				return true, nil
			end)
		end
	end

	-- 6. Ошибки скриптов за время проверки.
	dev("selfCheck", "stop")
	waitFor(function(): boolean
		return serverErrors ~= nil
	end, 5)
	conn:Disconnect()
	for _, e in clientErrors do
		report("без ошибок клиента", false, e)
	end
	local fromServer: { string } = serverErrors or {}
	for _, e in fromServer do
		report("без ошибок сервера", false, e)
	end
	if #clientErrors == 0 then
		report("без ошибок клиента", true)
	end
	if serverErrors ~= nil and #(serverErrors :: { string }) == 0 then
		report("без ошибок сервера", true)
	elseif serverErrors == nil then
		report(
			"без ошибок сервера",
			false,
			"сервер не прислал список ошибок"
		)
	end
	local summary =
		string.format("[Самопроверка] Итог: %d из %d (пропущено %d)", passed, total, skipped)
	if passed == total then
		print(summary)
	else
		warn(summary)
	end
end

-- Запуск (кнопка F4); второй запуск, пока идёт первый, — ничего.
function SelfCheck.start()
	if running or not RunService:IsStudio() then
		return
	end
	running = true
	task.spawn(function()
		local ok, err = pcall(run :: any)
		if not ok then
			warn("[Самопроверка] прервана: " .. tostring(err))
		end
		running = false
	end)
end

return table.freeze(SelfCheck)
