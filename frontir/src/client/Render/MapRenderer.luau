--!strict
--[[
	MapRenderer — карта на экране через EditableImage (GDD §3).

	Карта режется на чанки Config.Render.ChunkSize (лимит Roblox — 1024×1024 на изображение).
	Каждый чанк — свой EditableImage в ImageLabel с ResampleMode = Pixelated: одна клетка = один пиксель
	текстуры, зум — это просто размер ImageLabel, поэтому без размытия (ближайший пиксель).
	Камера двигает и масштабирует общий Frame-холст; текстуры при этом не перерисовываются.

	Ограничения Roblox (create.roblox.com/docs, EditableImage / AssetService):
	- за кадр на экране обновляется только один EditableImage — поэтому чанков мало и правки копим;
	- на клиенте строгий бюджет памяти: при исчерпании CreateEditableImage возвращает nil;
	- в опубликованной игре нужно включить Allow Mesh / Image APIs, иначе создание падает с ошибкой.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
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
	pixels: buffer, -- копия пикселей чанка в памяти Luau (RGBA)
	-- Грязный прямоугольник в координатах чанка; dx0 = -1 — чистый.
	dx0: number,
	dy0: number,
	dx1: number,
	dy1: number,
}

export type CreateError = "Disabled" | "Budget"

export type MapView = {
	canvas: Frame,
	chunkCount: number,
	memoryBytes: number,
	setView: (zoom: number, offsetX: number, offsetY: number) -> (),
	-- Меняет цвет клетки в памяти; на экран попадёт при flush.
	setCellColor: (x: number, y: number, r: number, g: number, b: number) -> (),
	-- Выгружает изменения одного «грязного» чанка (за кадр на экране обновляется один EditableImage).
	flush: () -> (),
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
			local pixels = MapPaint.copyRect(colors, map.width, x0, y0, w, h)
			image:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)

			local label = Instance.new("ImageLabel")
			label.Name = string.format("Chunk_%d_%d", x0 // size, y0 // size)
			label.BackgroundTransparency = 1
			label.BorderSizePixel = 0
			label.Active = false
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.ImageContent = Content.fromObject(image)
			label.Parent = canvas

			table.insert(chunks, {
				x0 = x0,
				y0 = y0,
				w = w,
				h = h,
				image = image,
				label = label,
				pixels = pixels,
				dx0 = -1,
				dy0 = 0,
				dx1 = 0,
				dy1 = 0,
			})
			memoryBytes += w * h * 4
		end
	end

	local chunksX = math.ceil(map.width / size)

	local function setCellColor(x: number, y: number, r: number, g: number, b: number)
		local chunk = chunks[(y // size) * chunksX + (x // size) + 1]
		local lx, ly = x - chunk.x0, y - chunk.y0
		local o = (ly * chunk.w + lx) * 4
		buffer.writeu8(chunk.pixels, o, r)
		buffer.writeu8(chunk.pixels, o + 1, g)
		buffer.writeu8(chunk.pixels, o + 2, b)
		if chunk.dx0 < 0 then
			chunk.dx0, chunk.dy0, chunk.dx1, chunk.dy1 = lx, ly, lx, ly
		else
			chunk.dx0 = math.min(chunk.dx0, lx)
			chunk.dy0 = math.min(chunk.dy0, ly)
			chunk.dx1 = math.max(chunk.dx1, lx)
			chunk.dy1 = math.max(chunk.dy1, ly)
		end
	end

	-- По кругу: каждый кадр выгружаем следующий грязный чанк, только изменённый прямоугольник.
	local nextChunk = 1
	local function flush()
		for _ = 1, #chunks do
			local chunk = chunks[nextChunk]
			nextChunk = nextChunk % #chunks + 1
			if chunk.dx0 >= 0 then
				local w = chunk.dx1 - chunk.dx0 + 1
				local h = chunk.dy1 - chunk.dy0 + 1
				local region = if w == chunk.w and h == chunk.h
					then chunk.pixels
					else MapPaint.copyRect(chunk.pixels, chunk.w, chunk.dx0, chunk.dy0, w, h)
				chunk.image:WritePixelsBuffer(Vector2.new(chunk.dx0, chunk.dy0), Vector2.new(w, h), region)
				chunk.dx0 = -1
				return
			end
		end
	end

	local lastZoom = -1
	local function setView(zoom: number, offsetX: number, offsetY: number)
		canvas.Position = UDim2.fromOffset(offsetX, offsetY)
		if zoom ~= lastZoom then
			lastZoom = zoom
			canvas.Size = UDim2.fromOffset(CameraMath.cellEdge(zoom, map.width), CameraMath.cellEdge(zoom, map.height))
			-- Края чанков — округлённые границы клеток: при дробном зуме чанки стыкуются без щелей.
			for _, chunk in chunks do
				local left = CameraMath.cellEdge(zoom, chunk.x0)
				local top = CameraMath.cellEdge(zoom, chunk.y0)
				chunk.label.Position = UDim2.fromOffset(left, top)
				chunk.label.Size = UDim2.fromOffset(
					CameraMath.cellEdge(zoom, chunk.x0 + chunk.w) - left,
					CameraMath.cellEdge(zoom, chunk.y0 + chunk.h) - top
				)
			end
		end
	end

	canvas.Parent = parent

	return {
		canvas = canvas,
		chunkCount = #chunks,
		memoryBytes = memoryBytes,
		setView = setView,
		setCellColor = setCellColor,
		flush = flush,
		destroy = cleanup,
	},
		nil,
		nil
end

return table.freeze(MapRenderer)
