--!strict
--[[
	TutorialPanel — «Обучение» (GDD §5.5, этап 10а; под новый экран — §15ц Ц5б).
	- Карточка слева: «ОБУЧЕНИЕ · шаг N из 6», полоса прогресса, текущий шаг крупно и подсказка, ниже — все шаги
	  (пройденные — ✓). Шаги проверяет сервер (info.tutorialStep, события tutorial / tutorialDone).
	- Подсветка места: вокруг того, что нажать на текущем шаге (Config.Tutorial.Focus — путь рамки в HUD), —
	  пульсирующая золотая рамка со стрелкой «▼». Рамка не ловит нажатия (под ней кнопка работает как обычно).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

type ClientState = ClientState.ClientState

export type TutorialPanel = {
	refresh: () -> (),
	update: (now: number) -> (),
	onEvents: (events: { any }) -> (),
}

local TutorialPanel = {}

local WIDTH = 340

function TutorialPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	toast: (text: string) -> ()
): TutorialPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local steps = Config.Tutorial.Steps
	local focusPaths = Config.Tutorial.Focus :: { [string]: string }

	-- Карточка шагов.
	local panel = Instance.new("Frame")
	panel.Name = "Tutorial"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 12, 0.5, 40)
	panel.Size = UDim2.fromOffset(WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	MenuKit.stroke(panel, Theme.Colors.Gold, 2)
	MenuKit.pad(panel, 14, 12)
	MenuKit.list(panel, 6)
	local head = MenuKit.label(panel, "", 13, Theme.Colors.Muted, true, 1)
	local barHost = Instance.new("Frame")
	barHost.BackgroundTransparency = 1
	barHost.Size = UDim2.new(1, 0, 0, 8)
	barHost.LayoutOrder = 2
	barHost.Parent = panel
	local bar = MenuKit.bar(barHost, 8, Theme.Colors.Gold)
	local current = MenuKit.label(panel, "", 22, Theme.Colors.Gold, true, 3)
	local hint = MenuKit.wrapLabel(panel, "", 15, Theme.Colors.Text, 4)
	local list = MenuKit.wrapLabel(panel, "", 13, Theme.Colors.Muted, 5)
	list.RichText = true

	-- Подсветка места: рамка поверх цели (не Active — нажатия проходят к кнопке под ней).
	local focus = Instance.new("Frame")
	focus.Name = "TutorialFocus"
	focus.BackgroundTransparency = 1
	focus.Active = false
	focus.Visible = false
	focus.ZIndex = 50
	focus.Parent = gui
	local ring = MenuKit.stroke(focus, Theme.Colors.Gold, 3)
	local arrow = MenuKit.label(focus, "▼", 24, Theme.Colors.Gold, true)
	arrow.AnchorPoint = Vector2.new(0.5, 1)
	arrow.Position = UDim2.new(0.5, 0, 0, -2)
	arrow.TextStrokeTransparency = 0.2
	arrow.ZIndex = 51

	local function stepNow(): number?
		local step = cs.tutorialStep
		local show = cs.rules.tutorial and step ~= nil and (cs.phase == "Pick" or cs.phase == "Play")
		if not show or step == nil then
			return nil
		end
		return if cs.phase == "Pick" then 1 else step
	end

	local function refresh()
		local k = stepNow()
		panel.Visible = k ~= nil
		if k == nil then
			return
		end
		local total = #steps
		local done = math.min(k - 1, total)
		head.Text = string.format(t("tutorial.head"), math.min(k, total), total)
		bar.set(done / total)
		local kind = steps[k]
		if kind ~= nil then
			current.Text = "▶ " .. t("tutorial." .. kind)
			hint.Text = t("tutorial.hint." .. kind)
		else
			current.Text = "✓ " .. t("tutorial.title")
			hint.Text = t("tutorial.finished")
		end
		local lines: { string } = {}
		for j, name in steps do
			local text = t("tutorial." .. name)
			if j < k then
				table.insert(lines, "✓ " .. text)
			elseif j == k then
				table.insert(
					lines,
					string.format('<font color="#%s"><b>▶ %s</b></font>', Theme.Colors.Gold:ToHex(), text)
				)
			else
				table.insert(lines, "· " .. text)
			end
		end
		list.Text = table.concat(lines, "\n")
	end

	-- Цель подсветки по пути «Рамка.Дочерняя…» от HUD.
	local function target(path: string): GuiObject?
		local node: Instance? = gui
		for part in string.gmatch(path, "[^%.]+") do
			node = if node ~= nil then node:FindFirstChild(part) else nil
		end
		return if node ~= nil and node:IsA("GuiObject") then node else nil
	end

	local function update(now: number)
		local k = stepNow()
		local kind = if k ~= nil then steps[k] else nil
		local path = if kind ~= nil then focusPaths[kind] else nil
		local g = if path ~= nil then target(path) else nil
		if g == nil or not g.Visible or g.AbsoluteSize.X <= 0 then
			focus.Visible = false
			return
		end
		-- Настоящие пиксели → условные (слой HUD в масштабе экрана, §15ц Ц1).
		local f = UiScale.factor()
		local pos = (g.AbsolutePosition - gui.AbsolutePosition) / f
		local size = g.AbsoluteSize / f
		focus.Position = UDim2.fromOffset(pos.X - 4, pos.Y - 4)
		focus.Size = UDim2.fromOffset(size.X + 8, size.Y + 8)
		local pulse = 0.5 + 0.5 * math.sin(now * 5)
		ring.Transparency = 0.5 * pulse
		arrow.Position = UDim2.new(0.5, 0, 0, -2 - 6 * pulse)
		focus.Visible = true
	end

	return {
		refresh = refresh,
		update = update,
		onEvents = function(events: { any })
			for _, e in events do
				if e.nation == cs.myNation then
					if e.kind == "tutorial" then
						local kind = Config.Tutorial.Steps[tonumber(e.step) or 0]
						if kind ~= nil then
							toast(string.format(t("tutorial.stepDone"), t("tutorial." .. kind)))
						end
					elseif e.kind == "tutorialDone" then
						toast(
							string.format(
								t("tutorial.reward"),
								Config.Tutorial.RewardTokens,
								Config.Tutorial.RewardMedals
							)
						)
					end
				end
			end
		end,
	}
end

return table.freeze(TutorialPanel)
