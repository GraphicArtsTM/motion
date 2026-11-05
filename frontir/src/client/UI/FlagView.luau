--!strict
--[[
	FlagView — флаг державы из готовых частей (GDD §11.4, этап 9в): фон, раскладка (полосы, крест, диагональ «лесенкой»,
	кайма) и эмблема (круг, кольцо, квадрат, ромб, крест). Только рамки Frame, UICorner и UIStroke — без картинок и
	свободного рисования. Цвета — имена палитры (Theme.color).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))

local Theme = require(script.Parent:WaitForChild("Theme"))

export type FlagView = {
	frame: Frame,
	set: (flag: Cosmetics.Flag) -> (),
}

local FlagView = {}

local function part(parent: Instance, color: Color3, pos: UDim2, size: UDim2, z: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.ZIndex = z
	f.Parent = parent
	return f
end

function FlagView.new(parent: Instance, w: number, h: number, z: number): FlagView
	local frame = Instance.new("Frame")
	frame.Name = "Flag"
	frame.Size = UDim2.fromOffset(w, h)
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.ClipsDescendants = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Backdrop
	stroke.Thickness = 1
	stroke.Parent = frame
	frame.Parent = parent

	local layer = Instance.new("Folder")
	layer.Parent = frame

	local function set(flag: Cosmetics.Flag)
		layer:ClearAllChildren()
		frame.BackgroundColor3 = Theme.color(flag.bg)
		local lc = Theme.color(flag.layoutColor)
		local zz = z + 1
		local l = flag.layout
		if l == "HStripe" or l == "Cross" then
			part(layer, lc, UDim2.fromScale(0, 0.38), UDim2.fromScale(1, 0.24), zz)
		end
		if l == "VStripe" or l == "Cross" then
			part(layer, lc, UDim2.fromScale(0.38, 0), UDim2.fromScale(0.24, 1), zz)
		end
		if l == "Diagonal" then
			-- Повёрнутые рамки не обрезаются, поэтому диагональ — «лесенка» из квадратов.
			local steps = 6
			for k = 0, steps - 1 do
				part(layer, lc, UDim2.fromScale(k / steps, k / steps), UDim2.fromScale(1.6 / steps, 1.6 / steps), zz)
			end
		end
		if l == "Border" then
			local t = 0.14
			part(layer, lc, UDim2.fromScale(0, 0), UDim2.fromScale(1, t), zz)
			part(layer, lc, UDim2.fromScale(0, 1 - t), UDim2.fromScale(1, t), zz)
			part(layer, lc, UDim2.fromScale(0, 0), UDim2.fromScale(t, 1), zz)
			part(layer, lc, UDim2.fromScale(1 - t, 0), UDim2.fromScale(t, 1), zz)
		end
		local e = flag.emblem
		if e ~= "None" then
			local ec = Theme.color(flag.emblemColor)
			local size = math.min(w, h) * 0.5
			local em = part(layer, ec, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(size, size), z + 2)
			em.AnchorPoint = Vector2.new(0.5, 0.5)
			if e == "Circle" or e == "Ring" then
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = em
			end
			if e == "Ring" then
				em.BackgroundTransparency = 1
				local ring = Instance.new("UIStroke")
				ring.Color = ec
				ring.Thickness = math.max(1, size * 0.18)
				ring.Parent = em
			elseif e == "Diamond" then
				em.Size = UDim2.fromOffset(size * 0.75, size * 0.75)
				em.Rotation = 45
			elseif e == "Cross" then
				em.BackgroundTransparency = 1
				part(em, ec, UDim2.fromScale(0.35, 0), UDim2.fromScale(0.3, 1), z + 2)
				part(em, ec, UDim2.fromScale(0, 0.35), UDim2.fromScale(1, 0.3), z + 2)
			end
		end
	end

	set(Cosmetics.defaultFlag())
	return { frame = frame, set = set }
end

return table.freeze(FlagView)
