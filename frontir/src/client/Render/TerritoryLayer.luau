--!strict
--[[
	TerritoryLayer — территории держав поверх местности (слои 3, 4, 6 из GDD §3).
	Цвет клетки считает Shared.TerritoryPaint; здесь — какие клетки перерисовать и когда:
	- после дельты: сама клетка и её 4 соседа (могла появиться или исчезнуть граница);
	- свежезахваченные клетки вспыхивают и гаснут ступенями за Config.Render.CaptureFlashSec;
	- после снимка или смены цветов — всё, что принадлежит державам или принадлежало раньше.
	Изменения пишутся в пиксели чанков и выгружаются по одному чанку за кадр (MapRenderer.flush).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local TerritoryPaint = require(Shared:WaitForChild("TerritoryPaint"))

local MapRenderer = require(script.Parent:WaitForChild("MapRenderer"))

type MapData = MapDataModule.MapData
type ClientState = ClientState.ClientState

export type TerritoryLayer = {
	repaintAll: () -> (),
	cellsChanged: (cells: { number }, now: number) -> (),
	update: (now: number) -> (),
}

local TerritoryLayer = {}

function TerritoryLayer.new(view: MapRenderer.MapView, map: MapData, terrain: buffer, cs: ClientState): TerritoryLayer
	local w, h = map.width, map.height
	local size = w * h
	local painted = buffer.create(size) -- 1 — клетка сейчас нарисована цветом державы
	local dirty: { [number]: boolean } = {}
	local dirtyList: { number } = {}
	local flashStart: { [number]: number } = {}
	local flashLevel: { [number]: number } = {}
	local cfg = Config.Render

	local function colorOf(owner: number): number
		return ClientState.colorIndexOf(cs, owner)
	end

	local function paint(i: number, flash: number)
		local r, g, b = TerritoryPaint.cellColor(terrain, cs.owners, w, h, i, colorOf, flash)
		view.setCellColor(i % w, i // w, r, g, b)
		buffer.writeu8(painted, i, if ClientState.ownerAt(cs, i) ~= 0 then 1 else 0)
	end

	local function markDirty(i: number)
		if not dirty[i] then
			dirty[i] = true
			table.insert(dirtyList, i)
		end
	end

	local function repaintAll()
		table.clear(dirty)
		table.clear(dirtyList)
		table.clear(flashStart)
		table.clear(flashLevel)
		for i = 0, size - 1 do
			if ClientState.ownerAt(cs, i) ~= 0 or buffer.readu8(painted, i) == 1 then
				paint(i, 0)
			end
		end
	end

	local function cellsChanged(cells: { number }, now: number)
		for _, i in cells do
			markDirty(i)
			local x = i % w
			if x > 0 then
				markDirty(i - 1)
			end
			if x < w - 1 then
				markDirty(i + 1)
			end
			if i >= w then
				markDirty(i - w)
			end
			if i + w < size then
				markDirty(i + w)
			end
			if ClientState.ownerAt(cs, i) ~= 0 then
				flashStart[i] = now
				flashLevel[i] = -1
			end
		end
	end

	local function flashOf(i: number, now: number): number
		local start = flashStart[i]
		if start == nil then
			return 0
		end
		local f = 1 - (now - start) / cfg.CaptureFlashSec
		if f <= 0 then
			return 0
		end
		return math.ceil(f * cfg.CaptureFlashSteps) / cfg.CaptureFlashSteps
	end

	local function update(now: number)
		for _, i in dirtyList do
			local f = flashOf(i, now)
			if flashStart[i] ~= nil then
				flashLevel[i] = f
			end
			paint(i, f)
		end
		table.clear(dirty)
		table.clear(dirtyList)
		-- Вспышки гаснут ступенями: перерисовываем клетку только при смене ступени.
		for i, _ in flashStart do
			local f = flashOf(i, now)
			if f ~= flashLevel[i] then
				flashLevel[i] = f
				paint(i, f)
			end
			if f <= 0 then
				flashStart[i] = nil
				flashLevel[i] = nil
			end
		end
		view.flush()
	end

	return {
		repaintAll = repaintAll,
		cellsChanged = cellsChanged,
		update = update,
	}
end

return table.freeze(TerritoryLayer)
