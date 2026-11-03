--!strict
--[[
	MinimapPaint — пиксели мини-карты (HUD v1, §10): уменьшенная карта, территории — цветом держав, ничья земля
	и вода — цветом местности (MapPaint). Чистая функция: клиент кладёт результат в EditableImage, тест сверяет.
]]

local MinimapPaint = {}

-- RGBA outW × outH. terrain — RGBA карты (MapPaint.paint), owners — u16 владельцы клеток,
-- colorOf(owner) — цвет державы (r, g, b) или nil (рисовать местность).
function MinimapPaint.paint(
	terrain: buffer,
	owners: buffer,
	mapW: number,
	mapH: number,
	outW: number,
	outH: number,
	colorOf: (owner: number) -> (number?, number?, number?)
): buffer
	local out = buffer.create(outW * outH * 4)
	for y = 0, outH - 1 do
		local cy = math.min(mapH - 1, math.floor((y + 0.5) * mapH / outH))
		for x = 0, outW - 1 do
			local cx = math.min(mapW - 1, math.floor((x + 0.5) * mapW / outW))
			local i = cy * mapW + cx
			local o = (y * outW + x) * 4
			local owner = buffer.readu16(owners, i * 2)
			local r, g, b = nil, nil, nil
			if owner ~= 0 then
				r, g, b = colorOf(owner)
			end
			if r ~= nil and g ~= nil and b ~= nil then
				buffer.writeu8(out, o, r)
				buffer.writeu8(out, o + 1, g)
				buffer.writeu8(out, o + 2, b)
			else
				buffer.writeu8(out, o, buffer.readu8(terrain, i * 4))
				buffer.writeu8(out, o + 1, buffer.readu8(terrain, i * 4 + 1))
				buffer.writeu8(out, o + 2, buffer.readu8(terrain, i * 4 + 2))
			end
			buffer.writeu8(out, o + 3, 255)
		end
	end
	return out
end

-- Размер мини-карты, вписанной в квадрат side × side с сохранением пропорций карты.
function MinimapPaint.size(mapW: number, mapH: number, side: number): (number, number)
	if mapW >= mapH then
		return side, math.max(1, math.floor(side * mapH / mapW + 0.5))
	end
	return math.max(1, math.floor(side * mapW / mapH + 0.5)), side
end

return table.freeze(MinimapPaint)
