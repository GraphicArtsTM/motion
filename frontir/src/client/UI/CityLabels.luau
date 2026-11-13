--!strict
--[[
	CityLabels — названия городов на карте (§15д ч.4): реальные (Лондон, Париж…), придуманные и основанные игроками.
	Крупнее у города выше уровнем; с общего плана — только города от Render.CityLabelBigLevel, ближе (зум
	Render.CityLabelZoom) — все в кадре. Пул меток, пересчёт при сдвиге камеры и смене городов или уровней.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local CitySprites = require(Shared:WaitForChild("CitySprites"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local Strings = require(Shared:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

type CameraState = CameraMath.CameraState
type ClientState = ClientState.ClientState

export type CityLabels = {
	onCamera: (state: CameraState) -> (),
	refresh: () -> (), -- города или их уровни поменялись
}

local CityLabels = {}

function CityLabels.new(
	canvas: Frame,
	cs: ClientState,
	provinces: Provinces.ProvinceSet,
	map: MapDataModule.MapData,
	lang: Strings.Lang
): CityLabels
	local cfg = Config.Render
	local w = map.width
	local pool: { TextLabel } = {}
	local last: CameraState? = nil

	local function label(k: number): TextLabel
		local existing: TextLabel? = pool[k]
		if existing then
			return existing
		end
		local made = Instance.new("TextLabel")
		made.Name = "CityName"
		made.AnchorPoint = Vector2.new(0.5, 0)
		made.Size = UDim2.fromOffset(200, 18)
		made.BackgroundTransparency = 1
		made.FontFace = Theme.FontBold
		made.TextColor3 = Theme.Colors.Text
		made.TextStrokeTransparency = 0.25
		made.TextStrokeColor3 = Theme.Colors.Backdrop
		made.ZIndex = 8
		made.Parent = canvas
		pool[k] = made
		return made
	end

	local function onCamera(state: CameraState)
		last = state
		local x0, y0 = state.x, state.y
		local x1, y1 = x0 + state.viewW / state.zoom, y0 + state.viewH / state.zoom
		local near = state.zoom >= cfg.CityLabelZoom
		local n = 0
		for _, cell in cs.cities do
			local level = ClientState.cityLevel(cs, cell)
			local cx, cy = cell % w, cell // w
			if
				(near or level >= cfg.CityLabelBigLevel)
				and cx >= x0
				and cx <= x1
				and cy >= y0
				and cy <= y1
				and n < cfg.CityLabelMax
			then
				n += 1
				local l = label(n)
				local name = Provinces.cityName(provinces, map, cell)
				l.Text = if lang == "en" then name.en else name.ru
				-- §15ш Ш4: текст растёт вместе с интерфейсом (на большом мониторе подписи были мелкими).
				local f = UiScale.factor()
				l.TextSize = math.round((cfg.CityLabelSize + 2 * (level - 1)) * f)
				l.Size = UDim2.fromOffset(200 * f, 18 * f)
				-- Город игрока — его цветом нет смысла (подпись поверх его земли); столица — золотом.
				local owner = ClientState.ownerAt(cs, cell)
				local capital = false
				for _, nation in cs.nations do
					if nation.id == owner and nation.capital == cell then
						capital = true
					end
				end
				l.TextColor3 = if capital then Theme.Colors.Gold else Theme.Colors.Text
				-- Под пиксельным городом (его сторона — CitySprites.size × масштаб зума).
				local scale = 1
				for _, step in cfg.CityScales do
					if state.zoom >= step.zoom then
						scale = step.scale
					end
				end
				l.Position = UDim2.fromOffset(
					CameraMath.cellEdge(state.zoom, cx + 0.5),
					CameraMath.cellEdge(state.zoom, cy + 0.5) + CitySprites.size(level) * scale / 2 + 2
				)
				l.Visible = true
			end
		end
		for k = n + 1, #pool do
			pool[k].Visible = false
		end
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

return table.freeze(CityLabels)
