--!strict
--[[
	CameraMath — 2D-камера карты без Roblox API (тестируется в Lune).
	Мир — клетки карты, экран — пиксели области просмотра. zoom = пикселей экрана на клетку.
	(x, y) — мировая координата (в клетках) левого верхнего угла экрана.

	Зум:
	- самый мелкий — «вся карта на экране» (fitZoom): дробный ниже IntegerZoomFrom, чтобы карта
	  занимала экран, а не висела маленькой картинкой посередине;
	- от IntegerZoomFrom (×2) колесо и щипок останавливаются только на целых значениях — все клетки
	  одного размера, пиксели ровные; в процессе плавной анимации зум бывает дробным.
	Границы клеток на экране округляются до целых пикселей (cellEdge) — без щелей и размытия.
]]

local Config = require("./Config")

export type CameraState = {
	x: number,
	y: number,
	zoom: number,
	viewW: number,
	viewH: number,
	mapW: number,
	mapH: number,
}

local CameraMath = {}

local EPS = 1e-6

-- Зум, при котором карта видна целиком (с отступом FitMargin).
function CameraMath.fitZoom(mapW: number, mapH: number, viewW: number, viewH: number): number
	local cfg = Config.Render
	local z = math.min(viewW / mapW, viewH / mapH) * cfg.FitMargin
	if z >= cfg.IntegerZoomFrom then
		z = math.floor(z)
	end
	return math.clamp(z, cfg.ZoomFloor, cfg.ZoomMax)
end

-- Самый мелкий допустимый зум для текущего экрана: дальше «всей карты» отдалять незачем.
function CameraMath.minZoom(s: CameraState): number
	return CameraMath.fitZoom(s.mapW, s.mapH, s.viewW, s.viewH)
end

function CameraMath.clampZoom(s: CameraState, z: number): number
	return math.clamp(z, CameraMath.minZoom(s), Config.Render.ZoomMax)
end

-- Ближайший «устойчивый» зум: от IntegerZoomFrom — целый.
function CameraMath.snapZoom(s: CameraState, z: number): number
	local c = CameraMath.clampZoom(s, z)
	if c >= Config.Render.IntegerZoomFrom then
		c = CameraMath.clampZoom(s, math.round(c))
	end
	return c
end

-- Цель зума после щелчка колеса (dir = +1 ближе, -1 дальше) от зума current.
function CameraMath.wheelTarget(s: CameraState, current: number, dir: number): number
	local t = CameraMath.snapZoom(s, current * Config.Render.WheelZoomFactor ^ dir)
	-- Округление не должно «съесть» шаг: каждый щелчок хоть немного меняет зум.
	if dir > 0 and t <= current + EPS then
		t = CameraMath.snapZoom(s, math.floor(current + EPS) + 1)
	elseif dir < 0 and t >= current - EPS then
		t = CameraMath.snapZoom(s, math.ceil(current - EPS) - 1)
	end
	return t
end

-- Держит карту в пределах экрана: если карта меньше экрана по оси — центрирует,
-- иначе не даёт утащить дальше, чем на PanMarginPx за край.
function CameraMath.clamp(s: CameraState)
	local margin = Config.Render.PanMarginPx / s.zoom
	local viewCellsW = s.viewW / s.zoom
	local viewCellsH = s.viewH / s.zoom
	if viewCellsW >= s.mapW then
		s.x = -(viewCellsW - s.mapW) / 2
	else
		s.x = math.clamp(s.x, -margin, s.mapW - viewCellsW + margin)
	end
	if viewCellsH >= s.mapH then
		s.y = -(viewCellsH - s.mapH) / 2
	else
		s.y = math.clamp(s.y, -margin, s.mapH - viewCellsH + margin)
	end
end

-- Камера, показывающая всю карту по центру.
function CameraMath.new(mapW: number, mapH: number, viewW: number, viewH: number): CameraState
	local s: CameraState = {
		x = 0,
		y = 0,
		zoom = CameraMath.fitZoom(mapW, mapH, viewW, viewH),
		viewW = viewW,
		viewH = viewH,
		mapW = mapW,
		mapH = mapH,
	}
	CameraMath.clamp(s)
	return s
end

function CameraMath.screenToWorld(s: CameraState, sx: number, sy: number): (number, number)
	return s.x + sx / s.zoom, s.y + sy / s.zoom
end

function CameraMath.worldToScreen(s: CameraState, wx: number, wy: number): (number, number)
	return (wx - s.x) * s.zoom, (wy - s.y) * s.zoom
end

-- Новый зум с сохранением точки мира под (sx, sy) экрана (курсор или центр щипка). Без округления.
function CameraMath.zoomAt(s: CameraState, newZoom: number, sx: number, sy: number)
	local z = CameraMath.clampZoom(s, newZoom)
	if math.abs(z - s.zoom) < EPS then
		return
	end
	local wx, wy = CameraMath.screenToWorld(s, sx, sy)
	s.zoom = z
	s.x = wx - sx / z
	s.y = wy - sy / z
	CameraMath.clamp(s)
end

-- Сдвиг на (dx, dy) пикселей экрана: карта едет вместе с пальцем или мышью.
function CameraMath.pan(s: CameraState, dx: number, dy: number)
	s.x -= dx / s.zoom
	s.y -= dy / s.zoom
	CameraMath.clamp(s)
end

function CameraMath.setViewSize(s: CameraState, viewW: number, viewH: number)
	s.viewW = viewW
	s.viewH = viewH
	s.zoom = CameraMath.clampZoom(s, s.zoom)
	CameraMath.clamp(s)
end

-- Центрирует камеру на клетке (wx, wy).
function CameraMath.centerOn(s: CameraState, wx: number, wy: number)
	s.x = wx - s.viewW / s.zoom / 2
	s.y = wy - s.viewH / s.zoom / 2
	CameraMath.clamp(s)
end

-- Смещение левого верхнего угла карты на экране в целых пикселях.
function CameraMath.canvasOffset(s: CameraState): (number, number)
	return math.round(-s.x * s.zoom), math.round(-s.y * s.zoom)
end

-- Граница клетки c (в клетках от края карты) в целых пикселях холста.
-- Соседние прямоугольники, посчитанные так, стыкуются без щелей и наложений.
function CameraMath.cellEdge(zoom: number, c: number): number
	return math.round(c * zoom)
end

-- Клетка под точкой экрана или nil, если вне карты.
function CameraMath.cellAt(s: CameraState, sx: number, sy: number): (number?, number?)
	local ox, oy = CameraMath.canvasOffset(s)
	local cx = math.floor((sx - ox) / s.zoom)
	local cy = math.floor((sy - oy) / s.zoom)
	if cx < 0 or cy < 0 or cx >= s.mapW or cy >= s.mapH then
		return nil, nil
	end
	return cx, cy
end

-- Видимый прямоугольник клеток (включительно) без обрезки по карте: за картой — океан.
function CameraMath.viewRect(s: CameraState): (number, number, number, number)
	return math.floor(s.x), math.floor(s.y), math.floor(s.x + s.viewW / s.zoom), math.floor(s.y + s.viewH / s.zoom)
end

-- Видимый прямоугольник клеток (включительно), обрезанный по карте.
function CameraMath.visibleRect(s: CameraState): (number, number, number, number)
	local x0 = math.max(0, math.floor(s.x))
	local y0 = math.max(0, math.floor(s.y))
	local x1 = math.min(s.mapW - 1, math.floor(s.x + s.viewW / s.zoom))
	local y1 = math.min(s.mapH - 1, math.floor(s.y + s.viewH / s.zoom))
	return x0, y0, x1, y1
end

return table.freeze(CameraMath)
