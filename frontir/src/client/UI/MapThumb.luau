--!strict
--[[
	MapThumb — миниатюра карты для «МАТЧИ» в хабе (GDD §15л ч.6) из Shared.MapThumbs: пиксели палитры →
	EditableImage (одна на карту; кеш — свой у каждого MapThumb.new, то есть на сессию: при смене карты
	Session снимает и EditableImage, и меню). Нет памяти или карты — nil.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapThumbs = require(Shared:WaitForChild("MapThumbs"))
local Palette = require(Shared:WaitForChild("Palette"))

local Session = require(script.Parent.Parent:WaitForChild("Session"))

local MapThumb = {}

function MapThumb.new(): (mapId: string) -> Content?
	local cache: { [string]: Content } = {}
	return function(mapId: string): Content?
		if cache[mapId] then
			return cache[mapId]
		end
		local rows = (MapThumbs.Maps :: { [string]: { string } })[mapId]
		if rows == nil then
			return nil
		end
		local w, h = MapThumbs.W, MapThumbs.H
		local ok, image = pcall(function(): EditableImage?
			return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
		end)
		if not ok or image == nil then
			return nil
		end
		local editable = image :: EditableImage
		Session.track(editable)
		local pixels = buffer.create(w * h * 4)
		for y, row in rows do
			for x = 1, w do
				local k = string.find(MapThumbs.Keys, string.sub(row, x, x), 1, true) or 1
				local c = Palette.rgb(Palette.Swatches[k].name)
				local i = ((y - 1) * w + (x - 1)) * 4
				buffer.writeu8(pixels, i, c.r)
				buffer.writeu8(pixels, i + 1, c.g)
				buffer.writeu8(pixels, i + 2, c.b)
				buffer.writeu8(pixels, i + 3, 255)
			end
		end
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
		local content = Content.fromObject(editable)
		cache[mapId] = content
		return content
	end
end

return table.freeze(MapThumb)
