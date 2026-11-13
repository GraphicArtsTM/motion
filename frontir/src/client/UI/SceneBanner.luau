--!strict
--[[
	SceneBanner — картинка-шапка окна (GDD §15л ч.8): сцена Shared.SceneArt в EditableImage, без сглаживания.
	- attach(window, key): шапка над окном во всю его ширину (отдельная рамка в том же ScreenGui; следует за окном —
	  положение, размер, видимость). Места над окном мало — шапка ниже (до Banner.MinPx), меньше — без шапки.
	- image(parent, key, height): картинка в раскладке карточки (главное меню, лобби) — во всю ширину родителя.
	Нет памяти под EditableImage — шапки нет (окно как было).
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Palette = require(Shared:WaitForChild("Palette"))
local SceneArt = require(Shared:WaitForChild("SceneArt"))

local Session = require(script.Parent.Parent:WaitForChild("Session"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

export type Banner = { frame: ImageLabel, setKey: (key: string) -> () }

local SceneBanner = {}

local function ink(): Color3
	local c = Palette.rgb("Ink")
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- Картинка сцены: EditableImage на сессию (Session снимет при смене карты).
local function content(key: string): Content?
	local ok, image = pcall(function(): EditableImage?
		return AssetService:CreateEditableImage({ Size = Vector2.new(SceneArt.W, SceneArt.H) })
	end)
	if not ok or image == nil then
		return nil
	end
	local editable = image :: EditableImage
	Session.track(editable)
	editable:WritePixelsBuffer(Vector2.zero, Vector2.new(SceneArt.W, SceneArt.H), SceneArt.paint(key))
	return Content.fromObject(editable)
end

local function label(key: string): (ImageLabel?, (string) -> ())
	local c = content(key)
	if c == nil then
		return nil, function(_k: string) end
	end
	local img = Instance.new("ImageLabel")
	img.Name = "SceneBanner"
	img.BackgroundColor3 = ink()
	img.BorderSizePixel = 0
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.ScaleType = Enum.ScaleType.Crop
	img.ImageContent = c :: Content
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Thickness = 2
	stroke.Color = ink()
	stroke.Parent = img
	local current = key
	local function setKey(k: string)
		if k == current then
			return
		end
		local nc = content(k)
		if nc ~= nil then
			current = k
			img.ImageContent = nc :: Content
		end
	end
	return img, setKey
end

function SceneBanner.attach(window: GuiObject, key: string): Banner?
	local gui = window:FindFirstAncestorWhichIsA("ScreenGui")
	if gui == nil then
		return nil
	end
	local img, setKey = label(key)
	if img == nil then
		return nil
	end
	local banner = img :: ImageLabel
	banner.ZIndex = window.ZIndex
	banner.Visible = false
	banner.Parent = gui
	local maxH = Config.Render.Banner.MaxPx
	local function place()
		local shown = window.Visible and window.Parent ~= nil
		local ancestor = window.Parent
		while shown and ancestor ~= nil and ancestor ~= gui do
			if ancestor:IsA("GuiObject") and not (ancestor :: GuiObject).Visible then
				shown = false
			end
			ancestor = ancestor.Parent
		end
		banner.Visible = shown
		if not shown then
			return
		end
		-- §15ц: слой в масштабе экрана — настоящие пиксели переводим в условные.
		local f = UiScale.factor()
		local size, pos = window.AbsoluteSize / f, (window.AbsolutePosition - (gui :: ScreenGui).AbsolutePosition) / f
		-- Высота — по ширине окна (не выше MaxPx и места над окном); места меньше MinPx — шапки нет.
		local h = math.floor(math.min(maxH, size.X * SceneArt.H / SceneArt.W, pos.Y - 2))
		if h < Config.Render.Banner.MinPx then
			banner.Visible = false
			return
		end
		banner.Position = UDim2.fromOffset(pos.X, pos.Y - 2 - h)
		banner.Size = UDim2.fromOffset(size.X, h)
	end
	Session.connect(window:GetPropertyChangedSignal("AbsolutePosition"), place)
	Session.connect(window:GetPropertyChangedSignal("AbsoluteSize"), place)
	Session.connect(window:GetPropertyChangedSignal("Visible"), place)
	Session.connect(window.AncestryChanged, place)
	place()
	return { frame = banner, setKey = setKey }
end

function SceneBanner.image(parent: Instance, key: string, height: number, order: number?): Banner?
	local img, setKey = label(key)
	if img == nil then
		return nil
	end
	local banner = img :: ImageLabel
	banner.Size = UDim2.new(1, 0, 0, height)
	banner.LayoutOrder = order or -1
	banner.Parent = parent
	return { frame = banner, setKey = setKey }
end

return table.freeze(SceneBanner)
