--!strict
--[[
	DebugOverlay — окно F3 (GDD §12): FPS, карта, зум, камера, клетка под курсором, память EditableImage.
	В Studio открыто сразу, в игре — по F3. Время тика сервера, клеток за тик и пинг — строками extra.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Strings = require(Shared:WaitForChild("Strings"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Session = require(script.Parent.Parent:WaitForChild("Session"))

type MapData = MapDataModule.MapData
type CameraState = CameraMath.CameraState

export type DebugSource = {
	map: MapData,
	state: CameraState,
	chunkCount: number,
	memoryBytes: number,
	hover: () -> (number?, number?),
	extra: (() -> { string })?, -- дополнительные строки (сервер, пинг)
	bottomInset: number?, -- отступ снизу (над мини-картой)
}

local DebugOverlay = {}

local terrainNames: { [number]: string } = {}
for name, id in Types.Terrain :: { [string]: number } do
	terrainNames[id] = name
end

function DebugOverlay.create(parent: Instance, source: DebugSource, lang: Strings.Lang): () -> ()
	local panel = Instance.new("Frame")
	panel.Name = "DebugOverlay"
	-- Справа снизу: справа сверху — таблица лидеров, слева — панели игрока.
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -8, 1, -8 - (source.bottomInset or 0))
	panel.Size = UDim2.fromOffset(330, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Theme.Colors.PanelBg
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = RunService:IsStudio()
	panel.ZIndex = 10
	panel.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelBorder
	stroke.Thickness = Theme.BorderPx
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = panel

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.FontFace = Theme.Font
	text.TextSize = 14
	text.TextColor3 = Theme.Colors.Sky
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.ZIndex = 11
	text.Text = ""
	text.Parent = panel

	local frames = 0
	local elapsed = 0
	local fps = 0

	local function render()
		local map = source.map
		local s = source.state
		local lines = {
			Strings.get("debug.title", lang),
			string.format(Strings.get("debug.fps", lang), fps),
			string.format(
				Strings.get("debug.map", lang),
				Strings.get("map." .. map.name, lang),
				map.width,
				map.height,
				map.seed
			),
			string.format(Strings.get("debug.zoom", lang), s.zoom, CameraMath.minZoom(s)),
			string.format(Strings.get("debug.camera", lang), s.x, s.y),
		}
		local hx, hy = source.hover()
		local cx, cy = nil, nil
		if hx ~= nil and hy ~= nil then
			cx, cy = CameraMath.cellAt(s, hx, hy)
		end
		if cx ~= nil and cy ~= nil then
			local t = MapDataModule.getTerrain(map, MapDataModule.index(map, cx, cy))
			local terrain = Strings.get("terrain." .. (terrainNames[t] or "?"), lang)
			table.insert(lines, string.format(Strings.get("debug.cell", lang), cx, cy, terrain))
		else
			table.insert(lines, Strings.get("debug.cell.none", lang))
		end
		table.insert(
			lines,
			string.format(Strings.get("debug.memory", lang), source.chunkCount, source.memoryBytes / (1024 * 1024))
		)
		local extra = source.extra
		if extra then
			for _, line in extra() do
				table.insert(lines, line)
			end
		end
		text.Text = table.concat(lines, "\n")
	end

	local stepConn = Session.connect(RunService.RenderStepped, function(dt: number)
		frames += 1
		elapsed += dt
		if elapsed >= Config.Render.DebugRefreshSec then
			fps = math.round(frames / elapsed)
			frames = 0
			elapsed = 0
			if panel.Visible then
				render()
			end
		end
	end)

	local keyConn = Session.connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.F3 then
			panel.Visible = not panel.Visible
			render()
		end
	end)

	render()

	return function()
		stepConn:Disconnect()
		keyConn:Disconnect()
		panel:Destroy()
	end
end

return table.freeze(DebugOverlay)
