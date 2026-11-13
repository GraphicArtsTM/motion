--!strict
--[[
	IconImage — иконка здания или юнита (§15ш Ш5) из Shared.IconArt: пиксели → EditableImage, одна на иконку
	за сессию (кеш; при смене карты Session уничтожает картинки и чистит кеш). Без памяти под EditableImage — nil
	(тогда остаётся прежний рисунок кодом).
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IconArt = require(Shared:WaitForChild("IconArt"))

local Session = require(script.Parent.Parent:WaitForChild("Session"))

local IconImage = {}

local cache: { [string]: Content } = {}
local tracked = false

function IconImage.content(name: string): Content?
	local hit = cache[name]
	if hit then
		return hit
	end
	local pixels = IconArt.paint(name)
	if pixels == nil then
		return nil
	end
	local n = IconArt.Size
	local ok, image = pcall(function(): EditableImage?
		return AssetService:CreateEditableImage({ Size = Vector2.new(n, n) })
	end)
	if not ok or image == nil then
		return nil
	end
	local editable = image :: EditableImage
	if not tracked then
		tracked = true
		-- Уборщик сессии: картинки уничтожит Session.reset — кеш должен забыть их вместе с ними.
		Session.track({
			Destroy = function()
				table.clear(cache)
				tracked = false
			end,
		})
	end
	Session.track(editable)
	editable:WritePixelsBuffer(Vector2.zero, Vector2.new(n, n), pixels)
	local content = Content.fromObject(editable)
	cache[name] = content
	return content
end

-- Картинка-иконка: ImageLabel по центру родителя (size — сторона, условные px); nil — иконки нет.
function IconImage.label(parent: Instance, name: string, size: number): ImageLabel?
	local content = IconImage.content(name)
	if content == nil then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromOffset(size, size)
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.ScaleType = Enum.ScaleType.Fit
	img.ImageContent = content
	img.Parent = parent
	return img
end

return table.freeze(IconImage)
