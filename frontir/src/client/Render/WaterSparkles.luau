--!strict
--[[
	WaterSparkles — блики на воде (слой 1 из GDD §3). Это не перерисовка текстуры, а пул маленьких
	квадратов размером в одну клетку поверх холста карты: EditableImage обновлять каждый кадр нельзя
	(на экране обновляется лишь один EditableImage за кадр), а квадраты дешёвые.
	Блики появляются в видимой части моря на глубине от Config.Render.SparkleMinDepth и в океане за картой.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type MapData = MapDataModule.MapData
type CameraState = CameraMath.CameraState

type Sparkle = {
	frame: Frame,
	cx: number,
	cy: number,
	age: number,
	life: number,
	active: boolean,
}

local WaterSparkles = {}

-- Запускает блики; возвращает функцию остановки и колбэк для изменений камеры.
function WaterSparkles.start(
	canvas: Frame,
	map: MapData,
	mask: buffer, -- u8 на клетку: 1 — здесь можно блик
	state: CameraState
): (() -> (), (CameraState) -> ())
	local cfg = Config.Render
	local rng = Random.new()
	local color = Theme.color("Sky")
	local pool: { Sparkle } = {}
	for k = 1, cfg.SparkleMax do
		local frame = Instance.new("Frame")
		frame.Name = "Sparkle" .. k
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.Active = false
		frame.ZIndex = 2
		frame.Parent = canvas
		table.insert(pool, { frame = frame, cx = 0, cy = 0, age = 0, life = cfg.SparkleLifeSec, active = false })
	end

	local function place(s: Sparkle)
		local z = state.zoom
		local left = CameraMath.cellEdge(z, s.cx)
		local top = CameraMath.cellEdge(z, s.cy)
		s.frame.Position = UDim2.fromOffset(left, top)
		s.frame.Size = UDim2.fromOffset(
			math.max(1, CameraMath.cellEdge(z, s.cx + 1) - left),
			math.max(1, CameraMath.cellEdge(z, s.cy + 1) - top)
		)
	end

	local function onCamera(_: CameraState)
		for _, s in pool do
			if s.active then
				place(s)
			end
		end
	end

	local spawnDebt = 0
	local conn = RunService.RenderStepped:Connect(function(dt: number)
		spawnDebt += dt * cfg.SparklesPerSec
		local x0, y0, x1, y1 = CameraMath.viewRect(state)
		for _, s in pool do
			if s.active then
				s.age += dt
				if s.age >= s.life then
					s.active = false
					s.frame.Visible = false
				else
					-- Пиксельная вспышка: три ступени яркости вверх и вниз.
					local t = s.age / s.life
					local level = math.floor((1 - math.abs(2 * t - 1)) * 3 + 0.5) / 3
					s.frame.BackgroundTransparency = 1 - level * 0.85
				end
			elseif spawnDebt >= 1 and x1 >= x0 and y1 >= y0 then
				spawnDebt -= 1
				-- Несколько попыток найти воду в видимой области.
				for _ = 1, 6 do
					local cx = rng:NextInteger(x0, x1)
					local cy = rng:NextInteger(y0, y1)
					local outside = cx < 0 or cy < 0 or cx >= map.width or cy >= map.height
					if outside or buffer.readu8(mask, cy * map.width + cx) == 1 then
						s.cx, s.cy = cx, cy
						s.age = 0
						s.life = cfg.SparkleLifeSec * rng:NextNumber(0.7, 1.3)
						s.active = true
						s.frame.BackgroundTransparency = 1
						s.frame.Visible = true
						place(s)
						break
					end
				end
			end
		end
		spawnDebt = math.min(spawnDebt, cfg.SparkleMax)
	end)

	local function stop()
		conn:Disconnect()
		for _, s in pool do
			s.frame:Destroy()
		end
		table.clear(pool)
	end

	return stop, onCamera
end

return table.freeze(WaterSparkles)
