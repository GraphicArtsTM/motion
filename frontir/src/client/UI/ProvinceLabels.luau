--!strict
--[[
	ProvinceLabels — названия провинций на карте с зума Render.ProvinceNameZoom (×6, сводная правка). Мелкий
	приглушённый текст в центре провинции, только у провинций в кадре (пул меток, не больше ProvinceNameMax).
	Едут вместе с холстом карты; при смене зума или сдвиге камеры набор меток пересчитывается.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

type CameraState = CameraMath.CameraState

export type ProvinceLabels = {
	onCamera: (state: CameraState) -> (),
}

local ProvinceLabels = {}

function ProvinceLabels.new(
	canvas: Frame,
	provinces: Provinces.ProvinceSet,
	width: number,
	lang: Strings.Lang
): ProvinceLabels
	local cfg = Config.Render
	local pool: { TextLabel } = {}
	local used = 0

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
		local show = state.zoom >= cfg.ProvinceNameZoom
		local n = 0
		if show then
			local x0, y0 = state.x, state.y
			local x1, y1 = x0 + state.viewW / state.zoom, y0 + state.viewH / state.zoom
			for _, p in provinces.list do
				local cx, cy = p.center % width, p.center // width
				if cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 and n < cfg.ProvinceNameMax then
					n += 1
					local l = label(n)
					l.Text = Provinces.shortName(if lang == "en" then p.nameEn else p.name)
					-- §15ш Ш4: текст растёт вместе с интерфейсом.
					local f = UiScale.factor()
					l.TextSize = math.round(12 * f)
					l.Size = UDim2.fromOffset(160 * f, 16 * f)
					l.Position = UDim2.fromOffset(
						CameraMath.cellEdge(state.zoom, cx + 0.5),
						CameraMath.cellEdge(state.zoom, cy + 0.5) + 14 * f -- под городом и столицей
					)
					l.Visible = true
				end
			end
		end
		for k = n + 1, used do
			pool[k].Visible = false
		end
		used = n
	end

	return { onCamera = onCamera }
end

return table.freeze(ProvinceLabels)
