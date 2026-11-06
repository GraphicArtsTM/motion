--!strict
--[[
	DoomBar — «часы судного дня» (GDD §15з) сверху по центру: за минуту до начала — отсчёт; потом — планка доли
	суши, ваша доля и когда следующая волна; если вы ниже планки — красная строка с отсчётом до распада. Ниже —
	кто ещё под угрозой (☠). Данные — cs.world.doom (раз в секунду), между сообщениями отсчёт идёт сам.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))

type ClientState = ClientState.ClientState

export type DoomBar = {
	update: (now: number) -> (),
}

local DoomBar = {}

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

function DoomBar.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, totalLand: number): DoomBar
	local frame = Instance.new("Frame")
	frame.Name = "DoomBar"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 8)
	frame.Size = UDim2.fromOffset(0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundColor3 = Theme.Colors.PanelBg
	frame.BackgroundTransparency = 0.15
	frame.Visible = false
	frame.Parent = gui
	Theme.decorate(frame)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = frame
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame
	local function line(order: number, size: number): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AutomaticSize = Enum.AutomaticSize.XY
		l.Size = UDim2.fromOffset(0, 0)
		l.FontFace = Theme.FontBold
		l.TextSize = size
		l.TextColor3 = Theme.Colors.Text
		l.LayoutOrder = order
		l.Parent = frame
		return l
	end
	local main = line(1, 15)
	local warn = line(2, 15)
	warn.TextColor3 = Theme.Colors.Alert
	local others = line(3, 12)
	others.TextColor3 = Theme.Colors.Muted

	local function update(now: number)
		local doom = cs.world.doom
		if doom == nil or cs.phase ~= "Play" then
			frame.Visible = false
			return
		end
		local passed = (now - cs.worldAt) * ClientState.simRate(cs)
		local me = cs.myNation
		if doom.wave == 0 then
			-- До начала — только последняя минута.
			local left = (doom.nextIn or math.huge) - passed
			frame.Visible = left <= 60
			main.Text = string.format(Strings.get("doom.soon", lang), clock(left))
			warn.Visible = false
			others.Visible = false
			return
		end
		frame.Visible = true
		local mine = 0
		if me ~= nil and cs.stats ~= nil then
			for _, s in cs.stats.nations do
				if s.id == me then
					mine = s.cells / math.max(1, totalLand)
				end
			end
		end
		local text = string.format(Strings.get("doom.bar", lang), doom.bar * 100, mine * 100)
		if doom.nextBar ~= nil and doom.nextIn ~= nil then
			text ..= string.format(Strings.get("doom.next", lang), doom.nextBar * 100, clock(doom.nextIn - passed))
		end
		main.Text = text
		local names: { string } = {}
		warn.Visible = false
		for _, e in doom.marked do
			local left = e.left - passed
			if e.id == me then
				warn.Visible = true
				warn.Text = string.format(Strings.get("doom.you", lang), clock(left))
			else
				local n = cs.nations[e.id]
				table.insert(names, string.format("%s %s", if n ~= nil then n.name else "?", clock(left)))
			end
		end
		others.Visible = #names > 0
		others.Text = "☠ " .. table.concat(names, " · ")
		-- Красная вспышка, пока вы под угрозой.
		frame.BackgroundColor3 = if warn.Visible and math.floor(now * 2) % 2 == 0
			then Theme.Colors.Alert:Lerp(Theme.Colors.PanelBg, 0.6)
			else Theme.Colors.PanelBg
	end

	return { update = update }
end

return table.freeze(DoomBar)
