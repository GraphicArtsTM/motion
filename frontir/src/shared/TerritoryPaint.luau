--!strict
--[[
	TerritoryPaint — цвет клетки с учётом владельца (слои 3, 4 и 6 из GDD §3):
	3. цвет державы поверх местности: местность просвечивает (доля Config.Render.OwnerTint);
	4. граница державы — её цвет × Config.Nations.BorderShade, линия в 1 клетку по краю территории
	   (своя клетка, у которой сосед чужой, ничей или вода);
	6. вспышка свежезахваченной клетки: к белому на Config.Render.CaptureFlashStrength × flash.
	Слой 5 (границы провинций) — этап 3.
	Этап 7а: туман (клетка вне обзора темнее, §6.11), штриховка повстанцев на ничьей земле и режим карты
	«Стабильность» — свои клетки цветом стабильности провинции (§6.10).
]]

local Config = require("./Config")
local NationColors = require("./NationColors")
local Palette = require("./Palette")

-- Необязательное к клетке (этап 7а).
export type Extra = {
	fogged: boolean?, -- вне обзора
	rebel: boolean?, -- ничья земля провинции повстанцев
	stability: number?, -- своя клетка в режиме «Стабильность»: стабильность её провинции 0..100
}

local TerritoryPaint = {}

local function ownerAt(owners: buffer, i: number): number
	return buffer.readu16(owners, i * 2)
end

-- Граница территории: у клетки есть сосед (из 4) с другим владельцем или край карты.
function TerritoryPaint.isBorder(owners: buffer, width: number, height: number, i: number): boolean
	local o = ownerAt(owners, i)
	local x = i % width
	if x == 0 or x == width - 1 or i < width or i >= width * (height - 1) then
		return true
	end
	return ownerAt(owners, i - 1) ~= o
		or ownerAt(owners, i + 1) ~= o
		or ownerAt(owners, i - width) ~= o
		or ownerAt(owners, i + width) ~= o
end

local function mix(r: number, g: number, b: number, c: Palette.Rgb, t: number): (number, number, number)
	return r + (c.r - r) * t, g + (c.g - g) * t, b + (c.b - b) * t
end

-- Цвет стабильности 0..100: от первого цвета Render.StabilityColors через второй к третьему.
function TerritoryPaint.stabilityColor(value: number): (number, number, number)
	local names = Config.Render.StabilityColors
	local v = math.clamp(value, 0, 100) / 50
	local k = math.min(math.floor(v), 1)
	local a, b = Palette.rgb(names[k + 1]), Palette.rgb(names[k + 2])
	local t = v - k
	return math.floor(a.r + (b.r - a.r) * t + 0.5),
		math.floor(a.g + (b.g - a.g) * t + 0.5),
		math.floor(a.b + (b.b - a.b) * t + 0.5)
end

-- Цвет вне обзора (§6.11): к Render.FogColor на долю Render.FogDarken. Тот же, что у затемнённой местности.
function TerritoryPaint.fog(r: number, g: number, b: number): (number, number, number)
	local fr, fg, fb = mix(r, g, b, Palette.rgb(Config.Render.FogColor), Config.Render.FogDarken)
	return math.floor(fr + 0.5), math.floor(fg + 0.5), math.floor(fb + 0.5)
end

-- Затемнённая копия RGBA-карты местности (для быстрой перерисовки всей карты в тумане).
function TerritoryPaint.foggedTerrain(terrain: buffer): buffer
	local out = buffer.create(buffer.len(terrain))
	for o = 0, buffer.len(terrain) - 4, 4 do
		local r, g, b =
			TerritoryPaint.fog(buffer.readu8(terrain, o), buffer.readu8(terrain, o + 1), buffer.readu8(terrain, o + 2))
		buffer.writeu8(out, o, r)
		buffer.writeu8(out, o + 1, g)
		buffer.writeu8(out, o + 2, b)
		buffer.writeu8(out, o + 3, buffer.readu8(terrain, o + 3))
	end
	return out
end

-- Цвет клетки i. terrain — RGBA-буфер местности (MapPaint.paint), colorIndexOf — цвет державы по id
-- (0 — цвета нет), flash — сила вспышки захвата 0..1.
function TerritoryPaint.cellColor(
	terrain: buffer,
	owners: buffer,
	width: number,
	height: number,
	i: number,
	colorIndexOf: (owner: number) -> number,
	flash: number,
	extra: Extra?
): (number, number, number)
	local o = i * 4
	local r, g, b = buffer.readu8(terrain, o), buffer.readu8(terrain, o + 1), buffer.readu8(terrain, o + 2)
	local owner = ownerAt(owners, i)
	local ci = if owner ~= 0 then colorIndexOf(owner) else 0
	if ci < 1 or ci > NationColors.Count then
		-- Ничья земля (или цвета ещё нет): повстанцы — штриховка, в тумане — темнее.
		if extra ~= nil then
			if extra.rebel and (i % width + i // width) % Config.Render.RebelHatch == 0 then
				r, g, b = mix(r, g, b, Palette.rgb(Config.Render.RebelColor), Config.Render.RebelHatchMix)
				r, g, b = math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
			end
			if extra.fogged then
				return TerritoryPaint.fog(r, g, b)
			end
		end
		return r, g, b
	end
	if TerritoryPaint.isBorder(owners, width, height, i) then
		local c = NationColors.Borders[ci]
		r, g, b = c.r, c.g, c.b
	elseif extra ~= nil and extra.stability ~= nil then
		local sr, sg, sb = TerritoryPaint.stabilityColor(extra.stability)
		local t = Config.Render.StabilityTint
		r, g, b = r + (sr - r) * t, g + (sg - g) * t, b + (sb - b) * t
	else
		local c = NationColors.Colors[ci]
		local t = Config.Render.OwnerTint
		r = r + (c.r - r) * t
		g = g + (c.g - g) * t
		b = b + (c.b - b) * t
	end
	if extra ~= nil and extra.fogged then
		return TerritoryPaint.fog(r, g, b)
	end
	if flash > 0 then
		local f = math.clamp(flash, 0, 1) * Config.Render.CaptureFlashStrength
		r = r + (255 - r) * f
		g = g + (255 - g) * f
		b = b + (255 - b) * f
	end
	return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
end

return table.freeze(TerritoryPaint)
