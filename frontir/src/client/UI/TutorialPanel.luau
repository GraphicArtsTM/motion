--!strict
--[[
	TutorialPanel — «Обучение» (GDD §5.5, этап 10а): слева по центру шесть шагов, пройденные — ✓, текущий — золотой
	с подсказкой, что нажать. Шаги проверяет сервер (info.tutorialStep, события tutorial / tutorialDone).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type TutorialPanel = {
	refresh: () -> (),
	onEvents: (events: { any }) -> (),
}

local TutorialPanel = {}

function TutorialPanel.new(
	gui: ScreenGui,
	cs: ClientState,
	lang: Strings.Lang,
	toast: (text: string) -> ()
): TutorialPanel
	local panel = Instance.new("TextLabel")
	panel.Name = "Tutorial"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 12, 0.5, 0)
	panel.Size = UDim2.fromOffset(300, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.FontFace = Theme.Font
	panel.TextSize = 13
	panel.TextColor3 = Theme.Colors.Text
	panel.TextXAlignment = Enum.TextXAlignment.Left
	panel.TextYAlignment = Enum.TextYAlignment.Top
	panel.TextWrapped = true
	panel.RichText = true
	panel.Visible = false
	panel.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Gold
	stroke.Thickness = Theme.BorderPx
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = panel

	local function hex(c: Color3): string
		return "#" .. c:ToHex()
	end

	local function refresh()
		local step = cs.tutorialStep
		local steps = Config.Tutorial.Steps
		local show = cs.rules.tutorial and step ~= nil and (cs.phase == "Pick" or cs.phase == "Play")
		panel.Visible = show
		if not show or step == nil then
			return
		end
		local current = if cs.phase == "Pick" then 1 else step
		local lines = {
			string.format(
				'<font color="%s"><b>%s</b></font>',
				hex(Theme.Colors.Gold),
				Strings.get("tutorial.title", lang)
			),
		}
		for k, kind in steps do
			local name = Strings.get("tutorial." .. kind, lang)
			if k < current then
				table.insert(lines, string.format('<font color="%s">✓ %s</font>', hex(Theme.Colors.Muted), name))
			elseif k == current then
				table.insert(
					lines,
					string.format('<font color="%s"><b>▶ %s</b></font>', hex(Theme.Colors.Gold), name)
				)
				table.insert(lines, Strings.get("tutorial.hint." .. kind, lang))
			else
				table.insert(lines, string.format('<font color="%s">· %s</font>', hex(Theme.Colors.Muted), name))
			end
		end
		if current > #steps then
			table.insert(
				lines,
				string.format(
					'<font color="%s">%s</font>',
					hex(Theme.Colors.Gold),
					Strings.get("tutorial.finished", lang)
				)
			)
		end
		panel.Text = table.concat(lines, "\n")
	end

	return {
		refresh = refresh,
		onEvents = function(events: { any })
			for _, e in events do
				if e.nation == cs.myNation then
					if e.kind == "tutorial" then
						local kind = Config.Tutorial.Steps[tonumber(e.step) or 0]
						if kind ~= nil then
							toast(
								string.format(
									Strings.get("tutorial.stepDone", lang),
									Strings.get("tutorial." .. kind, lang)
								)
							)
						end
					elseif e.kind == "tutorialDone" then
						toast(
							string.format(
								Strings.get("tutorial.reward", lang),
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
