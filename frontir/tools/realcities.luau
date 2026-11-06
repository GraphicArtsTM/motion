--!strict
--[[
	Реальные города на реальных картах (GDD §15д ч.4).
	Запуск из frontir/:  lune run tools/realcities <Имя>   (имя из Config.RealMaps; all — все карты)

	Данные: Natural Earth populated places 1:10m (public domain), скачиваются один раз в build/geo/.
	Для каждой страны — до Cities.RealPerCountry крупнейших городов (население не меньше Cities.RealMinPop; самый
	крупный в стране — всегда), по убыванию населения по всей карте, не ближе Cities.RealMinDistance друг к другу,
	на суше (точка в воде — ближайшая суша в 3 клетках). Названия — NAME_RU / NAME_EN; названия с корнями
	реальных стран отбрасываются (Geo.isCityNameAllowed — «никаких реальных стран»). Страна в игре не показывается:
	она нужна только, чтобы взять 2–3 города каждой.
	Пишет блок cities = { { клетка, "ru", "en" }, ... } в maps/<Имя>.luau (заменяет старый, если был).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local MapData = require("../src/shared/MapData")
local MapFormat = require("../src/shared/MapFormat")
local Types = require("../src/shared/Types")
local Geo = require("./lib/Geo")

local URL =
	"https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places.geojson"
local CACHE = "build/geo"
local FILE = "ne_10m_populated_places.geojson"

local function load(): { any }
	local path = CACHE .. "/" .. FILE
	if not fs.isFile(path) then
		if not fs.isDir(CACHE) then
			fs.writeDir(CACHE)
		end
		print("  скачиваю " .. FILE .. " …")
		local result = process.exec("curl", { "-sS", "--fail", "--max-time", "900", "-o", path, URL })
		if not result.ok then
			error("не удалось скачать " .. URL .. ": " .. result.stderr)
		end
	end
	local doc = serde.decode("json", fs.readFile(path))
	return doc.features
end

type City = { cell: number, ru: string, en: string, pop: number }

local function citiesFor(params: Types.RealMapParams, map: MapData.MapData, features: { any }): { City }
	local cfg = Config.Cities
	local v = Geo.view(params)
	local w, h = map.width, map.height
	-- Кандидаты по странам.
	local byCountry: { [string]: { any } } = {}
	for _, f in features do
		local p = f.properties
		local lon, lat = p.LONGITUDE, p.LATITUDE
		if
			type(lon) == "number"
			and type(lat) == "number"
			and lon >= params.Lon0
			and lon <= params.Lon1
			and lat >= params.Lat0
			and lat <= params.Lat1
		then
			local key = tostring(p.ADM0NAME or p.SOV0NAME or "?")
			local list = byCountry[key] or {}
			table.insert(list, p)
			byCountry[key] = list
		end
	end
	local picked: { any } = {}
	for _, list in byCountry do
		table.sort(list, function(a: any, b: any): boolean
			return (a.POP_MAX or 0) > (b.POP_MAX or 0)
		end)
		for k = 1, math.min(cfg.RealPerCountry, #list) do
			local p = list[k]
			if k == 1 or (p.POP_MAX or 0) >= cfg.RealMinPop then
				table.insert(picked, p)
			end
		end
	end
	table.sort(picked, function(a: any, b: any): boolean
		return (a.POP_MAX or 0) > (b.POP_MAX or 0)
	end)
	local function landNear(x: number, y: number): number?
		local best: number? = nil
		local bestD = math.huge
		for dy = -3, 3 do
			for dx = -3, 3 do
				local nx, ny = x + dx, y + dy
				if nx >= 1 and ny >= 1 and nx < w - 1 and ny < h - 1 then
					local i = ny * w + nx
					local t = MapData.getTerrain(map, i)
					local d = dx * dx + dy * dy
					if
						t ~= Types.Terrain.Water
						and t ~= Types.Terrain.River
						and MapData.getProvince(map, i) ~= 0
						and d < bestD
					then
						best, bestD = i, d
					end
				end
			end
		end
		return best
	end
	local out: { City } = {}
	local minD2 = cfg.RealMinDistance * cfg.RealMinDistance
	for _, p in picked do
		local ru = tostring(p.NAME_RU or "")
		local en = tostring(p.NAME_EN or p.NAME or "")
		if ru == "" then
			ru = en
		end
		if Geo.isCityNameAllowed(ru, en) then
			local fx, fy = Geo.toCell(v, p.LONGITUDE, p.LATITUDE)
			local cell = landNear(math.floor(fx), math.floor(fy))
			if cell ~= nil then
				local far = true
				for _, c in out do
					local dx, dy = c.cell % w - cell % w, c.cell // w - cell // w
					if dx * dx + dy * dy < minD2 then
						far = false
						break
					end
				end
				if far then
					table.insert(out, { cell = cell, ru = ru, en = en, pop = p.POP_MAX or 0 })
				end
			end
		end
	end
	return out
end

local function quote(s: string): string
	return '"' .. string.gsub(s, '[\\"]', "\\%0") .. '"'
end

local function write(name: string, cities: { City })
	local path = "maps/" .. name .. ".luau"
	local text = fs.readFile(path)
	-- Старый блок cities — убрать.
	text = string.gsub(text, "\n\tcities = %b{},", "")
	local lines = { "\n\tcities = {" }
	for _, c in cities do
		table.insert(lines, string.format("\t\t{ %d, %s, %s },", c.cell, quote(c.ru), quote(c.en)))
	end
	table.insert(lines, "\t},")
	local block = table.concat(lines, "\n")
	local at = string.find(text, "\n\tprovinceNames = {", 1, true)
	assert(at ~= nil, "нет provinceNames в " .. path)
	text = string.sub(text, 1, at - 1) .. block .. string.sub(text, at)
	fs.writeFile(path, text)
end

local arg = process.args[1] or "all"
local features = load()
for key, params in Config.RealMaps :: { [string]: Types.RealMapParams } do
	if arg == "all" or arg == key then
		local module = (require :: any)("../maps/" .. key)
		local map = MapFormat.fromModule(module)
		local cities = citiesFor(params, map, features)
		write(key, cities)
		local names: { string } = {}
		for k = 1, math.min(8, #cities) do
			table.insert(names, cities[k].ru)
		end
		print(string.format("%s: городов %d (%s …)", key, #cities, table.concat(names, ", ")))
	end
end
