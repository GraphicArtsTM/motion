--!strict
--[[
	ProvinceLabels — названия провинций на карте с зума Render.ProvinceNameZoom (×6, сводная правка). Мелкий
	приглушённый текст в центре провинции, только у провинций в кадре (пул меток, не больше ProvinceNameMax).
	Едут вместе с холстом карты; при смене зума или сдвиге камеры набор меток пересчитывается.
	§15ы: название не ставится поверх города, его подписи и значков зданий (cityBoxes — от CityLabels и
	BuildingLayer): сдвиг ниже или выше, не влезает — названия нет. Раскладка — Shared.LabelLayout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))
local LabelLayout = require(Shared:WaitForChild("LabelLayout"))
local MapIcons = require(Shared:WaitForChild("MapIcons"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

type CameraState = CameraMath.CameraState

export type ProvinceLabels = {
	onCamera: (state: CameraState) -> (),
	refresh: () -> (), -- §15ы: города или здания поменялись — разложить заново
}

local ProvinceLabels = {}

function ProvinceLabels.new(
	canvas: Frame,
	provinces: Provinces.ProvinceSet,
	width: number,
	lang: Strings.Lang,
	cityBoxes: (() -> { MapIcons.Rect })?
): ProvinceLabels
	local cfg = Config.Render
	local pool: { TextLabel } = {}
	local used = 0
	local last: CameraState? = nil

	local function label(k: number): TextLabel
		local existing: TextLabel? = pool[k]
		if existing then
			return existing
		end
		local l: TextLabel
		do
			local made = Instance.new("TextLabel")
			made.Name = "ProvinceName"
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.Size = UDim2.fromOffset(160, 16)
			made.BackgroundTransparency = 1
			made.FontFace = Theme.Font
			made.TextSize = 12
			made.TextColor3 = Theme.Colors.Text
			made.TextTransparency = 0.25
			made.TextStrokeTransparency = 0.4
			made.TextStrokeColor3 = Theme.Colors.Backdrop
			made.ZIndex = 4
			made.Parent = canvas
			pool[k] = made
			l = made
		end
		return l
	end

	local function onCamera(state: CameraState)
		last = state
		local show = state.zoom >= cfg.ProvinceNameZoom
		local n = 0
		if show then
			local layout = LabelLayout.new()
			if cityBoxes ~= nil then
				for _, r in cityBoxes() do
					LabelLayout.take(layout, r)
				end
			end
			local f = UiScale.factor()
			local lineH = 16 * f
			local shifts = { 0, lineH, -lineH, 2 * lineH, -2 * lineH }
			local x0, y0 = state.x, state.y
			local x1, y1 = x0 + state.viewW / state.zoom, y0 + state.viewH / state.zoom
			for _, p in provinces.list do
				local cx, cy = p.center % width, p.center // width
				if cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 and n < cfg.ProvinceNameMax then
					local text = Provinces.shortName(if lang == "en" then p.nameEn else p.name)
					local px = CameraMath.cellEdge(state.zoom, cx + 0.5)
					local py = CameraMath.cellEdge(state.zoom, cy + 0.5)
					-- §15ы: ширина — по числу букв; поверх города и чужой подписи не ставим.
					local half = (utf8.len(text) or #text) * 12 * f * 0.29
					local want = { x0 = px - half, y0 = py - lineH / 2, x1 = px + half, y1 = py + lineH / 2 }
					-- §15й: то же имя региона рядом уже подписано — не повторяем.
					local same = LabelLayout.repeats(layout, text, px, py, cfg.SameNamePx * f)
					local dy = if same then nil else LabelLayout.place(layout, want, shifts)
					if dy ~= nil then
						LabelLayout.mark(layout, text, px, py)
						n += 1
						local l = label(n)
						l.Text = text
						-- §15ш Ш4: текст растёт вместе с интерфейсом.
						l.TextSize = math.round(12 * f)
						l.Size = UDim2.fromOffset(160 * f, lineH)
						l.Position = UDim2.fromOffset(px, py + dy)
						l.Visible = true
					end
				end
			end
		end
		for k = n + 1, used do
			pool[k].Visible = false
		end
		used = n
	end

	return {
		onCamera = onCamera,
		refresh = function()
			if last ~= nil then
				onCamera(last :: CameraState)
			end
		end,
	}
end

return table.freeze(ProvinceLabels)
