--!strict
--[[
	MapRenderer — карта на экране через EditableImage (GDD §3).

	Карта режется на чанки Config.Render.ChunkSize (лимит Roblox — 1024×1024 на изображение).
	Каждый чанк — свой EditableImage в ImageLabel с ResampleMode = Pixelated: одна клетка = один пиксель
	текстуры, зум — это просто размер ImageLabel, поэтому без размытия.
	Камера двигает и масштабирует общий Frame-холст; текстуры при этом не перерисовываются.

	Ограничения Roblox (create.roblox.com/docs, EditableImage / AssetService):
	- за кадр на экране обновляется только один EditableImage — поэтому чанков мало и правки копим;
	- на клиенте строгий бюджет памяти: при исчерпании CreateEditableImage возвращает nil;
	- в опубликованной игре нужно включить Allow Mesh / Image APIs, иначе создание падает с ошибкой.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local MapPaint = require(Shared:WaitForChild("MapPaint"))

type MapData = MapDataModule.MapData

type Chunk = {
	x0: number,
	y0: number,
	w: number,
	h: number,
	image: EditableImage,
	label: ImageLabel,
}

export type CreateError = "Disabled" | "Budget"

export type MapView = {
	canvas: Frame,
	chunkCount: number,
	memoryBytes: number,
	setView: (zoom: number, offsetX: number, offsetY: number) -> (),
	destroy: () -> (),
}

local MapRenderer = {}

function MapRenderer.create(parent: GuiObject, map: MapData, colors: buffer): (MapView?, CreateError?, string?)
	local canvas = Instance.new("Frame")
	canvas.Name = "MapCanvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Active = false

	local chunks: { Chunk } = {}
	local memoryBytes = 0

	local function cleanup()
		for _, chunk in chunks do
			chunk.image:Destroy()
		end
		canvas:Destroy()
	end

	local size = Config.Render.ChunkSize
	for y0 = 0, map.height - 1, size do
		for x0 = 0, map.width - 1, size do
			local w = math.min(size, map.width - x0)
			local h = math.min(size, map.height - y0)
			local ok, result = pcall(function(): EditableImage?
				return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
			end)
			if not ok then
				cleanup()
				return nil, "Disabled", tostring(result)
			end
			local image = result :: EditableImage?
			if image == nil then
				cleanup()
				return nil, "Budget", nil
			end
			image:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), MapPaint.copyRect(colors, map.width, x0, y0, w, h))

			local label = Instance.new("ImageLabel")
			label.Name = string.format("Chunk_%d_%d", x0 // size, y0 // size)
			label.BackgroundTransparency = 1
			label.BorderSizePixel = 0
			label.Active = false
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.ImageContent = Content.fromObject(image)
			label.Parent = canvas

			table.insert(chunks, { x0 = x0, y0 = y0, w = w, h = h, image = image, label = label })
			memoryBytes += w * h * 4
		end
	end

	local lastZoom = -1
	local function setView(zoom: number, offsetX: number, offsetY: number)
		canvas.Position = UDim2.fromOffset(offsetX, offsetY)
		if zoom ~= lastZoom then
			lastZoom = zoom
			canvas.Size = UDim2.fromOffset(map.width * zoom, map.height * zoom)
			-- Позиции и размеры в целых пикселях: чанки стыкуются без щелей.
			for _, chunk in chunks do
				chunk.label.Position = UDim2.fromOffset(chunk.x0 * zoom, chunk.y0 * zoom)
				chunk.label.Size = UDim2.fromOffset(chunk.w * zoom, chunk.h * zoom)
			end
		end
	end

	canvas.Parent = parent

	return {
		canvas = canvas,
		chunkCount = #chunks,
		memoryBytes = memoryBytes,
		setView = setView,
		destroy = cleanup,
	},
		nil,
		nil
end

return table.freeze(MapRenderer)
