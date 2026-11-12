--!strict
--[[
	MapHighlightLayer — подсветки на карте для читаемости (GDD §15х ч.8), точки на canvas карты:
	- граница с врагом: на вашей стороне границы с каждой державой, с которой у вас война или мобилизация, — красные
	  метки, по ним бежит волна (WarFx.borderSamples, только в кадре);
	- держава под курсором: её контур светится точками её цвета ближе к белому (MapOutline.outline, в кадре);
	- котлы (cs.world.pockets, сервер раз в секунду): мигающий пунктир по краю куска (MapOutline.component) и подпись —
	  чужой «КОТЁЛ · 23 с» (пунктир и подпись золотом), свой «ВЫ В КОТЛЕ · 23 с» (пунктир белый, подпись красная);
	  котёл с городом — без секунд.
	Контуры пересчитываются раз в Render.MapHighlight.RefreshSec и при смене державы под курсором; шаг выборки растёт
	с размером кадра (MapOutline.stride). Точек не больше пределов Render.MapHighlight (телефон — Render.Phone).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MapOutline = require(Shared:WaitForChild("MapOutline"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local Strings = require(Shared:WaitForChild("Strings"))
local WarFx = require(Shared:WaitForChild("WarFx"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

export type MapHighlightLayer = {
	setHover: (owner: number?) -> (), -- держава под курсором (nil / 0 — никого)
	update: (now: number, state: CameraState) -> (),
}

type Pocket = { owner: number, cells: { number }, cx: number, cy: number, left: number, label: TextLabel }

local MapHighlightLayer = {}

function MapHighlightLayer.new(canvas: Frame, cs: ClientState, lang: Strings.Lang): MapHighlightLayer
	local cfg = Config.Render.MapHighlight
	local phone = RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local function limit(name: string): number
		local p = (Config.Render.Phone :: any)[name]
		return if phone and p ~= nil then p else (cfg :: any)[name]
	end
	local maxWar, maxHover, maxPocket = limit("WarDots"), limit("HoverDots"), limit("PocketDots")
	local w, h = cs.width, cs.height
	local function ownerAt(i: number): number
		return ClientState.ownerAt(cs, i)
	end

	-- Пул точек.
	local pool: { Frame } = {}
	local used = 0
	local function dot(k: number): Frame
		local f: Frame? = pool[k]
		if f == nil then
			local made = Instance.new("Frame")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.BorderSizePixel = 0
			made.ZIndex = 4 -- над территорией, под значками зданий (5)
			made.Parent = canvas
			pool[k] = made
			f = made
		end
		return f :: Frame
	end

	local hover = 0
	local warCells: { number } = {}
	local hoverCells: { number } = {}
	local pockets: { Pocket } = {}
	local labelPool: { TextLabel } = {}
	local nextScan = 0
	local pocketsAt = -1

	local function label(k: number): TextLabel
		local l: TextLabel? = labelPool[k]
		if l == nil then
			local made = Instance.new("TextLabel")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.AutomaticSize = Enum.AutomaticSize.XY
			made.Size = UDim2.fromOffset(0, 0)
			made.BackgroundColor3 = Theme.Colors.Backdrop
			made.BackgroundTransparency = 0.25
			made.BorderSizePixel = 0
			made.FontFace = Theme.FontBold
			made.TextSize = 14
			made.TextStrokeTransparency = 0.6
			made.ZIndex = 6
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 6)
			pad.PaddingRight = UDim.new(0, 6)
			pad.PaddingTop = UDim.new(0, 2)
			pad.PaddingBottom = UDim.new(0, 2)
			pad.Parent = made
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 4)
			c.Parent = made
			made.Parent = canvas
			labelPool[k] = made
			l = made
		end
		return l :: TextLabel
	end

	local function nationColor(id: number): Color3
		local ci = ClientState.colorIndexOf(cs, id)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Text
	end

	local function scan(state: CameraState)
		local x0, y0, x1, y1 = CameraMath.visibleRect(state)
		x0, y0, x1, y1 = x0 - 2, y0 - 2, x1 + 2, y1 + 2
		local stride = MapOutline.stride(x1 - x0 + 1, y1 - y0 + 1, cfg.MaxScan)
		-- Граница с врагом.
		table.clear(warCells)
		local me = cs.myNation
		if me ~= nil and cs.phase == "Play" then
			local enemies: { number } = {}
			for id in cs.nations do
				if id ~= me and ClientState.warBetween(cs, me, id) ~= nil then
					table.insert(enemies, id)
				end
			end
			table.sort(enemies)
			local per = if #enemies > 0 then math.max(8, maxWar // #enemies) else 0
			for _, e in enemies do
				for _, c in WarFx.borderSamples(ownerAt, w, h, me, e, x0, y0, x1, y1, stride, per) do
					table.insert(warCells, c)
				end
			end
		end
		-- Держава под курсором.
		table.clear(hoverCells)
		if hover ~= 0 then
			for _, c in MapOutline.outline(ownerAt, w, h, hover, x0, y0, x1, y1, stride, maxHover) do
				table.insert(hoverCells, c)
			end
		end
	end

	local function rebuildPockets()
		pockets = {}
		local list: { ClientState.PocketInfo } = cs.world.pockets or {}
		for _, p in list do
			if ownerAt(p.cell) == p.owner then
				local comp = MapOutline.component(ownerAt, w, h, p.cell, cfg.PocketMaxCells)
				table.insert(pockets, {
					owner = p.owner,
					cells = MapOutline.spread(comp.edge, maxPocket),
					cx = comp.cx,
					cy = comp.cy,
					left = p.left,
					label = label(#pockets + 1),
				})
			end
		end
		for k = #pockets + 1, #labelPool do
			labelPool[k].Visible = false
		end
	end

	local function update(now: number, state: CameraState)
		if cs.phase ~= "Play" then
			for k = 1, used do
				pool[k].Visible = false
			end
			used = 0
			for _, l in labelPool do
				l.Visible = false
			end
			return
		end
		if now >= nextScan then
			nextScan = now + cfg.RefreshSec
			scan(state)
		end
		if cs.worldAt ~= pocketsAt then
			pocketsAt = cs.worldAt
			rebuildPockets()
		end
		local zoom = state.zoom
		local size = math.max(cfg.DotMinPx, cfg.DotScale * zoom)
		local phase = now * cfg.PulseHz * math.pi * 2
		local n = 0
		local function put(cell: number, color: Color3, alpha: number)
			n += 1
			local f = dot(n)
			f.Visible = true
			f.BackgroundColor3 = color
			f.BackgroundTransparency = alpha
			f.Position = UDim2.fromOffset((cell % w + 0.5) * zoom, (cell // w + 0.5) * zoom)
			f.Size = UDim2.fromOffset(size, size)
		end
		-- Граница с врагом: бегущая волна.
		local red = Theme.Colors.Alert
		for k, c in warCells do
			local wave = 0.5 + 0.5 * math.sin(phase - k * 0.35)
			put(c, red, 0.85 - 0.7 * wave)
		end
		-- Контур державы под курсором.
		if hover ~= 0 and #hoverCells > 0 then
			local color = nationColor(hover):Lerp(Theme.color("White"), cfg.HoverLighten)
			local pulse = 0.5 + 0.5 * math.sin(phase)
			for _, c in hoverCells do
				put(c, color, 0.35 - 0.25 * pulse)
			end
		end
		-- Котлы: пунктир мигает (чётные и нечётные точки по очереди), подпись в центре.
		local blink = math.sin(phase * 1.5) > 0
		local rate = math.max(ClientState.simRate(cs), 1e-3)
		for k, p in pockets do
			local mine = p.owner == cs.myNation
			-- Свой котёл: пунктир белый (на любом цвете соседа виден), подпись красная; чужой — всё золотом.
			local color = if mine then Theme.Colors.Alert else Theme.Colors.Gold
			local dash = if mine then Theme.color("White") else Theme.Colors.Gold
			for j, c in p.cells do
				if (j % 2 == 0) == blink then
					put(c, dash, 0.1)
				end
			end
			local l = p.label
			local left = if p.left < 0 then -1 else math.max(0, math.ceil(p.left - (now - cs.worldAt) * rate))
			local key = if mine then "pocket.mine" else "pocket.label"
			l.Text = if left > 0 then string.format(Strings.get(key .. "Left", lang), left) else Strings.get(key, lang)
			l.TextColor3 = color
			l.Position = UDim2.fromOffset(p.cx * zoom, p.cy * zoom)
			l.Visible = true
			l.LayoutOrder = k
		end
		for k = n + 1, used do
			pool[k].Visible = false
		end
		used = n
	end

	return {
		setHover = function(owner: number?)
			local o = owner or 0
			if o ~= hover then
				hover = o
				nextScan = 0 -- контур — сразу
			end
		end,
		update = update,
	}
end

return table.freeze(MapHighlightLayer)
