--!strict
--[[
	CityLabels — названия городов на карте (§15д ч.4): реальные (Лондон, Париж…), придуманные и основанные игроками.
	Крупнее у города выше уровнем; с общего плана — только города от Render.CityLabelBigLevel, ближе (зум
	Render.CityLabelZoom) — все в кадре. Пул меток, пересчёт при сдвиге камеры и смене городов или уровней.
	§15ы: подпись — под жетоном города (MapIcons.citySide); boxes() — занятые городами и подписями места в кадре
	(по ним ProvinceLabels не ставит названия провинций поверх).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local CitySprites = require(Shared:WaitForChild("CitySprites"))
local IconArt = require(Shared:WaitForChild("IconArt"))
local MapIcons = require(Shared:WaitForChild("MapIcons"))
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
	boxes: () -> { MapIcons.Rect }, -- §15ы: жетоны городов и их подписи в кадре (пиксели холста)
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
	local taken: { MapIcons.Rect } = {}

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
		made.ZIndex = 12 -- §15ы: поверх значков зданий (BuildingLayer — до 12)
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
		table.clear(taken)
		local ring = cfg.MapIcons.CityRingPx
		for _, cell in cs.cities do
			local level = ClientState.cityLevel(cs, cell)
			local cx, cy = cell % w, cell // w
			-- §15ы: жетон города занимает место (подписи провинций его обходят).
			local pictured = IconArt.has("City")
			-- Жетон уступает место соседним значкам (как в NationLabels); считаем только у городов в кадре.
			local inView = cx >= x0 - 4 and cx <= x1 + 4 and cy >= y0 - 4 and cy <= y1 + 4
			local badge = 0
			if pictured and inView then
				local around = MapIcons.buildingsNear(cs.buildings, cell, w, 10)
				badge = MapIcons.citySideAmong(level, state.zoom, around) + 2 * ring
				table.insert(taken, MapIcons.rect(cx, cy, state.zoom, badge))
			end
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
				-- §15ы: подпись — под жетоном города (с кантом).
				local side = if pictured then badge else CitySprites.size(level) * scale
				local lx = CameraMath.cellEdge(state.zoom, cx + 0.5)
				local ly = CameraMath.cellEdge(state.zoom, cy + 0.5) + side / 2 + 1
				l.Position = UDim2.fromOffset(lx, ly)
				l.Visible = true
				-- Ширина подписи — по числу букв (TextBounds обновляется не сразу).
				local half = utf8.len(l.Text) or #l.Text
				half = half * l.TextSize * 0.3
				table.insert(taken, { x0 = lx - half, y0 = ly, x1 = lx + half, y1 = ly + l.TextSize + 2 })
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
		boxes = function(): { MapIcons.Rect }
			return taken
		end,
	}
end

return table.freeze(CityLabels)
