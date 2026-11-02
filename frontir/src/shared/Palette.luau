--!strict
--[[
	Palette — единственная палитра игры: 32 цвета (GDD §3). Описание и назначение — docs/palette.md
	(тест tests/Palette.spec.luau проверяет, что документ и этот файл совпадают).
	Всё, что рисуется (карта, UI, эффекты), берёт цвета только отсюда.
]]

export type Rgb = { r: number, g: number, b: number }
export type Swatch = { name: string, hex: string }

local SWATCHES: { Swatch } = {
	{ name = "Ink", hex = "0b0e1a" },
	{ name = "Night", hex = "141a2e" },
	{ name = "Slate", hex = "262d4a" },
	{ name = "Steel", hex = "4a5378" },
	{ name = "Mist", hex = "8890b5" },
	{ name = "White", hex = "eef1f8" },
	{ name = "Abyss", hex = "0d2240" },
	{ name = "Sea", hex = "143a6b" },
	{ name = "Shallows", hex = "1d5592" },
	{ name = "River", hex = "3b7fc4" },
	{ name = "Sky", hex = "7cc8f0" },
	{ name = "Grass", hex = "5c9a3c" },
	{ name = "Meadow", hex = "7cb84e" },
	{ name = "Forest", hex = "2f6e35" },
	{ name = "Pine", hex = "1f4e2b" },
	{ name = "Hills", hex = "8f8a52" },
	{ name = "Ochre", hex = "6f6a3c" },
	{ name = "Rock", hex = "7d726b" },
	{ name = "Basalt", hex = "554c4b" },
	{ name = "Snow", hex = "dfe5ee" },
	{ name = "Sand", hex = "dcbc6e" },
	{ name = "Dune", hex = "c29a52" },
	{ name = "Tundra", hex = "9db3a4" },
	{ name = "Frost", hex = "c6d4cc" },
	{ name = "Gold", hex = "f0c440" },
	{ name = "Orange", hex = "e27b30" },
	{ name = "Red", hex = "c93c3c" },
	{ name = "Plum", hex = "8d2c60" },
	{ name = "Violet", hex = "5d3d9e" },
	{ name = "Teal", hex = "2a8f8a" },
	{ name = "Lime", hex = "b6de5a" },
	{ name = "Rose", hex = "e98bb2" },
}

local function hexToRgb(hex: string): Rgb
	assert(#hex == 6 and string.match(hex, "^%x+$") ~= nil, "неверный hex цвета: " .. hex)
	return table.freeze({
		r = tonumber(string.sub(hex, 1, 2), 16) :: number,
		g = tonumber(string.sub(hex, 3, 4), 16) :: number,
		b = tonumber(string.sub(hex, 5, 6), 16) :: number,
	})
end

local byName: { [string]: Rgb } = {}
for _, swatch in SWATCHES do
	table.freeze(swatch)
	byName[swatch.name] = hexToRgb(swatch.hex)
end

-- Цвет по имени; неизвестное имя — ошибка (опечатка не должна тихо давать чёрный).
local function rgb(name: string): Rgb
	local c = byName[name]
	if c == nil then
		error("в палитре нет цвета " .. name, 2)
	end
	return c
end

-- Упаковка RGB в одно число 0xRRGGBB (для быстрых проверок «цвет из палитры»).
local function pack(c: Rgb): number
	return c.r * 65536 + c.g * 256 + c.b
end

export type PaletteModule = {
	Swatches: { Swatch },
	ByName: { [string]: Rgb },
	rgb: (name: string) -> Rgb,
	hexToRgb: (hex: string) -> Rgb,
	pack: (c: Rgb) -> number,
}

local Palette: PaletteModule = {
	Swatches = table.freeze(SWATCHES),
	ByName = table.freeze(byName),
	rgb = rgb,
	hexToRgb = hexToRgb,
	pack = pack,
}

return table.freeze(Palette)
