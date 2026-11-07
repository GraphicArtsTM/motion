--!strict
--[[
	Logo — логотип «WORLD CONQUER» (GDD §15л ч.5) из Shared.LogoArt: пиксели палитры → EditableImage, на экране без
	сглаживания (Pixelated) в scale раз крупнее. Памяти под EditableImage нет — nil (тогда остаётся надпись текстом).
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LogoArt = require(Shared:WaitForChild("LogoArt"))
local Palette = require(Shared:WaitForChild("Palette"))

local Session = require(script.Parent.Parent:WaitForChild("Session"))

local Logo = {}

function Logo.new(parent: Instance, scale: number): ImageLabel?
	local w, h = LogoArt.W, LogoArt.H
	local ok, image = pcall(function(): EditableImage?
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if not ok or image == nil then
		return nil
	end
	Session.track(image)
	local editable = image :: EditableImage
	local pixels = buffer.create(w * h * 4)
	for y, row in LogoArt.Rows do
		for x = 1, w do
			local ch = string.sub(row, x, x)
			local name = LogoArt.Keys[ch]
			if name ~= nil then
				local c = Palette.rgb(name)
				local i = ((y - 1) * w + (x - 1)) * 4
				buffer.writeu8(pixels, i, c.r)
				buffer.writeu8(pixels, i + 1, c.g)
				buffer.writeu8(pixels, i + 2, c.b)
				buffer.writeu8(pixels, i + 3, 255)
			end
		end
	end
	editable:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
	local label = Instance.new("ImageLabel")
	label.Name = "LogoImage"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(w * scale, h * scale)
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ImageContent = Content.fromObject(editable)
	label.Parent = parent
	return label
end

return table.freeze(Logo)
