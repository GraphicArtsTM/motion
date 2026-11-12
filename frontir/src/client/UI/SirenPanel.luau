--!strict
--[[
	SirenPanel — «Сирена» (§15х ч.3): ракета или бомба летит по вашей земле — красная строка сверху по центру:
	что летит, через сколько секунд, и прогноз вашей защиты (StrikeForecast — то же правило, что у сервера): «ваши
	ПВО ×N, ЗРК ×N, зарядов N из N — собьют» или «защиты нет — дойдёт». Кнопка «Показать» — камера к цели.
	Несколько ударов — ближайший по времени и «ещё N». Данные — cs.world.missiles (раз в секунду), отсчёт идёт сам.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Strings = require(Shared:WaitForChild("Strings"))
local StrikeForecast = require(Shared:WaitForChild("StrikeForecast"))

local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type ClientState = ClientState.ClientState

export type SirenPanel = {
	update: (now: number) -> (),
	frame: Frame,
}

local SirenPanel = {}

function SirenPanel.new(gui: ScreenGui, cs: ClientState, lang: Strings.Lang, focus: (cell: number) -> ()): SirenPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local frame = Instance.new("Frame")
	frame.Name = "Siren"
	frame.Size = UDim2.fromOffset(560, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.Colors.Alert
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	frame:SetAttribute("FrontirStyled", true)
	MenuKit.corner(frame, 10)
	MenuKit.pad(frame, 14, 10)
	local text = MenuKit.wrapLabel(frame, "", 15, Theme.color("White"))
	text.Size = UDim2.new(1, -120, 0, 0)
	text.FontFace = Theme.FontBold
	local show = MenuKit.button(frame, t("siren.show"), "normal", 40)
	show.AnchorPoint = Vector2.new(1, 0.5)
	show.Position = UDim2.fromScale(1, 0.5)
	show.Size = UDim2.fromOffset(110, 40)
	local target: number? = nil
	Session.connect(show.Activated, function()
		local c = target
		if c ~= nil then
			focus(c)
		end
	end)

	local function update(now: number)
		local me = cs.myNation
		if me == nil or cs.phase ~= "Play" then
			frame.Visible = false
			return
		end
		local rate = math.max(ClientState.simRate(cs), 1e-3)
		local best: { cell: number, left: number, warhead: string? }? = nil
		local count = 0
		for _, mi in cs.world.missiles do
			if mi.owner ~= me and ClientState.ownerAt(cs, mi.cell) == me then
				local left = math.max(0, mi.left - (now - cs.worldAt) * rate) / rate
				count += 1
				if best == nil or left < best.left then
					best = { cell = mi.cell, left = left, warhead = mi.warhead }
				end
			end
		end
		frame.Visible = best ~= nil
		if best == nil then
			target = nil
			return
		end
		target = best.cell
		local kind: StrikeForecast.Kind = if best.warhead == "atom"
			then "atom"
			elseif best.warhead == "hydrogen" then "hydrogen"
			else "missile"
		local defs: { StrikeForecast.Defense } = {}
		local batteries: { { cell: number, ready: number, max: number } } = cs.world.batteries or {}
		for _, b in batteries do
			local building = cs.buildings[b.cell]
			if building ~= nil then
				local kindName: string = building.kind
				local d: StrikeForecast.Defense =
					{ cell = b.cell, kind = kindName, ready = b.ready, max = b.max, level = building.level }
				table.insert(defs, d)
			end
		end
		local f = StrikeForecast.compute({
			width = cs.width,
			cell = best.cell,
			kind = kind,
			victim = me,
			ownerAt = function(i: number): number
				return ClientState.ownerAt(cs, i)
			end,
			friends = ClientState.trustFriendsOf(cs, me),
			defenses = defs,
		})
		local what = string.format(t("siren.incoming"), t("warhead." .. kind), math.ceil(best.left))
		local defense: string
		if #f.covers == 0 then
			defense = t("siren.open")
		else
			local sams, aas = 0, 0
			for _, c in f.covers do
				if c.long then -- §15х ч.6: дальняя ПВО ур. 3
					sams += 1
				else
					aas += 1
				end
			end
			defense = string.format(t("siren.covered"), aas, sams, f.ready, f.need)
				.. " "
				.. t(if f.stopped then "siren.stopped" else "siren.through")
		end
		text.Text = "⚠ "
			.. what
			.. "\n"
			.. defense
			.. (if count > 1 then "  " .. string.format(t("siren.more"), count - 1) else "")
		frame.BackgroundColor3 = if f.stopped then Theme.color("Orange") else Theme.Colors.Alert
	end

	return { update = update, frame = frame }
end

return table.freeze(SirenPanel)
