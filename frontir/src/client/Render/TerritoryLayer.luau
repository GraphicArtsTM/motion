--!strict
--[[
	TerritoryLayer — территории держав поверх местности (слои 3, 4, 6 из GDD §3).
	Цвет клетки считает Shared.TerritoryPaint; здесь — какие клетки перерисовать и когда:
	- после дельты: сама клетка и её 4 соседа (могла появиться или исчезнуть граница);
	- свежезахваченные клетки вспыхивают и гаснут ступенями за Config.Render.CaptureFlashSec;
	- после снимка или смены цветов — вся карта: местность (в тумане — затемнённая) одним куском, поверх —
	  клетки держав, обзора и повстанцев.
	Этап 7а: рисуется последний увиденный владелец (ClientState.knownOwners), вне обзора — темнее (§6.11);
	ничья земля повстанцев — штриховка; режим «Стабильность» (N) — свои провинции цветом стабильности (§6.10).
	Изменения пишутся в пиксели чанков и выгружаются по одному чанку за кадр (MapRenderer.flush).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Fog = require(Shared:WaitForChild("Fog"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local Provinces = require(Shared:WaitForChild("Provinces"))
local TerritoryPaint = require(Shared:WaitForChild("TerritoryPaint"))

local MapRenderer = require(script.Parent:WaitForChild("MapRenderer"))

type MapData = MapDataModule.MapData
type ClientState = ClientState.ClientState

export type TerritoryLayer = {
	repaintAll: () -> (),
	-- Клетки сменили владельца или видимость; flash — вспышка захвата (не для открывшихся из тумана).
	cellsChanged: (cells: { number }, now: number, flash: boolean?) -> (),
	-- Провинции целиком (повстанцы появились или ушли).
	provincesChanged: (ids: { number }) -> (),
	railsChanged: (cells: { number }) -> (), -- §15ч Ч1: рельсы появились или исчезли
	setStabilityMode: (on: boolean) -> (),
	stabilityMode: () -> boolean,
	stabilityChanged: () -> (), -- пришла новая стабильность своих провинций
	update: (now: number) -> (),
}

local TerritoryLayer = {}

function TerritoryLayer.new(
	view: MapRenderer.MapView,
	map: MapData,
	terrain: buffer,
	cs: ClientState,
	provinces: Provinces.ProvinceSet
): TerritoryLayer
	local w, h = map.width, map.height
	local size = w * h
	local dirty: { [number]: boolean } = {}
	local dirtyList: { number } = {}
	local flashStart: { [number]: number } = {}
	local flashLevel: { [number]: number } = {}
	local cfg = Config.Render
	local fogTerrain: buffer? = nil -- затемнённая местность (считается при первом тумане)
	local stabilityOn = false
	local paintedBucket: { [number]: number } = {} -- провинция → ступень стабильности, которой нарисована
	local extra: TerritoryPaint.Extra = {}

	local function colorOf(owner: number): number
		return ClientState.colorIndexOf(cs, owner)
	end

	local function paint(i: number, flash: number)
		local known = ClientState.knownOwners(cs)
		local owner = buffer.readu16(known, i * 2)
		local p = MapDataModule.getProvince(map, i)
		extra.fogged = not Fog.isVisible(cs.fog, i)
		extra.rebel = owner == 0 and p ~= 0 and cs.rebelSet[p] == true
		-- Косметика владельца (§11.4): узор и цвет вспышки захвата.
		local info = if owner ~= 0 then cs.nations[owner] else nil
		local cosmetic = if info ~= nil then info.cosmetic else nil
		extra.pattern = if cosmetic ~= nil then cosmetic.pattern else nil
		extra.flashColor = if cosmetic ~= nil then cosmetic.capture else nil
		extra.rail = cs.rails.cells[i] -- §15ч Ч1
		extra.stability = if stabilityOn
				and owner ~= 0
				and owner == cs.myNation
				and p ~= 0
			then ClientState.stabilityOf(cs, p)
			else nil
		local r, g, b = TerritoryPaint.cellColor(terrain, known, w, h, i, colorOf, flash, extra)
		view.setCellColor(i % w, i // w, r, g, b)
	end

	local function markDirty(i: number)
		if not dirty[i] then
			dirty[i] = true
			table.insert(dirtyList, i)
		end
	end

	-- Смена владельца клетки меняет вид клеток в радиусе ширины границы (§15х ч.8: граница в 2 клетки).
	local reach = math.max(1, Config.Render.BorderWidth)
	local function markAround(i: number)
		local x, y = i % w, i // w
		for dy = -reach, reach do
			local ny = y + dy
			if ny >= 0 and ny < h then
				local span = reach - math.abs(dy)
				for dx = -span, span do
					local nx = x + dx
					if nx >= 0 and nx < w then
						markDirty(ny * w + nx)
					end
				end
			end
		end
	end

	local function repaintAll()
		table.clear(dirty)
		table.clear(dirtyList)
		table.clear(flashStart)
		table.clear(flashLevel)
		table.clear(paintedBucket)
		local fs = cs.fog
		local base = terrain
		if not fs.all then
			if fogTerrain == nil then
				fogTerrain = TerritoryPaint.foggedTerrain(terrain)
			end
			base = fogTerrain :: buffer
		end
		view.blit(base)
		-- Поверх местности: клетки держав, клетки в обзоре (светлее тумана), ничья земля повстанцев.
		local known = ClientState.knownOwners(cs)
		for i = 0, size - 1 do
			if buffer.readu16(known, i * 2) ~= 0 then
				paint(i, 0)
			end
		end
		if not fs.all and fs.x0 <= fs.x1 then
			for y = fs.y0, fs.y1 do
				for x = fs.x0, fs.x1 do
					local i = y * w + x
					if buffer.readu16(known, i * 2) == 0 and Fog.isVisible(fs, i) then
						paint(i, 0)
					end
				end
			end
		end
		for p in cs.rebelSet do
			local province = provinces.list[p]
			if province ~= nil then
				for _, i in province.cells do
					if buffer.readu16(known, i * 2) == 0 then
						paint(i, 0)
					end
				end
			end
		end
		-- Мосты (§15ч Ч1) — на ничьих клетках реки.
		for i in cs.rails.cells do
			if buffer.readu16(known, i * 2) == 0 then
				paint(i, 0)
			end
		end
	end

	local function cellsChanged(cells: { number }, now: number, flash: boolean?)
		local known = ClientState.knownOwners(cs)
		for _, i in cells do
			markAround(i)
			if flash ~= false and buffer.readu16(known, i * 2) ~= 0 and Fog.isVisible(cs.fog, i) then
				flashStart[i] = now
				flashLevel[i] = -1
			end
		end
	end

	-- §15ч Ч1: рельсы появились или исчезли — перерисовать эти клетки (без вспышки).
	local function railsChanged(cells: { number })
		for _, i in cells do
			markDirty(i)
		end
	end

	local function provincesChanged(ids: { number })
		for _, p in ids do
			local province = provinces.list[p]
			if province ~= nil then
				for _, i in province.cells do
					markDirty(i)
				end
			end
		end
	end

	-- Ступень стабильности для перерисовки: значение меняется по 1 в секунду, цвет — заметно реже.
	local function bucketOf(value: number): number
		return value // 5
	end

	local function repaintOwnProvinces(all: boolean)
		local me = cs.myNation
		if me == nil then
			return
		end
		local known = ClientState.knownOwners(cs)
		local seenNow: { [number]: boolean } = {}
		for k, p in cs.stability.ids do
			seenNow[p] = true
			local bucket = if stabilityOn then bucketOf(cs.stability.values[k] or 0) else -1
			if all or paintedBucket[p] ~= bucket then
				paintedBucket[p] = bucket
				local province = provinces.list[p]
				if province ~= nil then
					for _, i in province.cells do
						if buffer.readu16(known, i * 2) == me then
							markDirty(i)
						end
					end
				end
			end
		end
		-- Провинция ушла из своих — её клетки уже перерисованы дельтой; просто забываем.
		for p in paintedBucket do
			if not seenNow[p] then
				paintedBucket[p] = nil
			end
		end
	end

	local function setStabilityMode(on: boolean)
		if on == stabilityOn then
			return
		end
		stabilityOn = on
		repaintOwnProvinces(true)
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
		provincesChanged = provincesChanged,
		railsChanged = railsChanged,
		setStabilityMode = setStabilityMode,
		stabilityMode = function(): boolean
			return stabilityOn
		end,
		stabilityChanged = function()
			if stabilityOn then
				repaintOwnProvinces(false)
			end
		end,
		update = update,
	}
end

return table.freeze(TerritoryLayer)
