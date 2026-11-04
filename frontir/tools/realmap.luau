--!strict
--[[
	Карта с реальной географией (GDD §4, этап 4а).
	Запуск из frontir/:  lune run tools/realmap <Имя>   (имя из Config.RealMaps; all — все карты)
	Пишет maps/<Имя>.luau (ModuleScript для Roblox) и build/<Имя>.png (превью, в git не идёт).

	Данные (скачиваются один раз в build/geo/, в git не идут):
	- Natural Earth 1:50m (public domain): суша, озёра, реки, географические регионы (горы, пустыни, равнины —
	  для пустынь и имён провинций). Реальных стран и границ нет.
	- ETOPO1 (NOAA, свободное использование) через ERDDAP: высоты с шагом примерно в клетку.
	Шаги: суша минус озёра → чистка мелких островов и луж → пустыни, реки, высоты → местность (tools/lib/Geo) →
	провинции (MapGen.generateProvinces) → имена провинций от подписи региона («Альпы-2»), без реальных стран.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local MapData = require("../src/shared/MapData")
local MapFormat = require("../src/shared/MapFormat")
local MapGen = require("../src/shared/MapGen")
local MapPaint = require("../src/shared/MapPaint")
local NameGen = require("../src/shared/NameGen")
local Provinces = require("../src/shared/Provinces")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")
local Geo = require("./lib/Geo")
local Png = require("./lib/Png")

local NE_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/%s.geojson"
local ERDDAP_URL =
	"https://coastwatch.pfeg.noaa.gov/erddap/griddap/etopo180.csv?altitude%%5B(%s):%d:(%s)%%5D%%5B(%s):%d:(%s)%%5D"
local CACHE = "build/geo"

-- Классы регионов Natural Earth, чьи имена годятся для провинций (континенты — слишком крупно).
local NAME_CLASSES: { [string]: boolean } = {
	["Range/mtn"] = true,
	["Plateau"] = true,
	["Desert"] = true,
	["Plain"] = true,
	["Basin"] = true,
	["Lowland"] = true,
	["Valley"] = true,
	["Delta"] = true,
	["Tundra"] = true,
	["Foothills"] = true,
	["Wetlands"] = true,
	["Gorge"] = true,
	["Pen/cape"] = true,
	["Peninsula"] = true,
	["Isthmus"] = true,
	["Coast"] = true,
	["Geoarea"] = true,
	["Island"] = true,
	["Island group"] = true,
}

local function fetch(url: string, file: string): string
	local path = CACHE .. "/" .. file
	if not fs.isFile(path) then
		if not fs.isDir(CACHE) then
			fs.writeDir(CACHE)
		end
		print("  скачиваю " .. file .. " …")
		local result = process.exec("curl", { "-sS", "--fail", "--max-time", "900", "-o", path, url })
		if not result.ok then
			error("не удалось скачать " .. url .. ": " .. result.stderr)
		end
	end
	return fs.readFile(path)
end

local function naturalEarth(layer: string): { any }
	local text = fetch(string.format(NE_URL, layer), layer .. ".geojson")
	return (serde.decode("json", text) :: any).features
end

-- Многоугольники геометрии GeoJSON (Polygon / MultiPolygon).
local function polygonsOf(geometry: any): { Geo.Polygon }
	if geometry == nil then
		return {}
	elseif geometry.type == "Polygon" then
		return { geometry.coordinates }
	elseif geometry.type == "MultiPolygon" then
		return geometry.coordinates
	end
	return {}
end

-- Ломаные геометрии GeoJSON (LineString / MultiLineString).
local function linesOf(geometry: any): { { { number } } }
	if geometry == nil then
		return {}
	elseif geometry.type == "LineString" then
		return { geometry.coordinates }
	elseif geometry.type == "MultiLineString" then
		return geometry.coordinates
	end
	return {}
end

-- Площадь внешнего кольца в градусах² (для порядка: крупные регионы рисуем первыми, мелкие — поверх).
local function ringArea(ring: Geo.Ring): number
	local sum = 0
	for k = 1, #ring do
		local a, b = ring[k], ring[k % #ring + 1]
		sum += a[1] * b[2] - b[1] * a[2]
	end
	return math.abs(sum) / 2
end

local function build(p: Types.RealMapParams)
	local started = os.clock()
	local v = Geo.view(p)
	local w, h = p.Width, p.Height
	local n = w * h
	local cfg = Config.RealMapTerrain
	print(
		string.format(
			"%s: %d×%d, окно %.1f..%.1f° д., %.1f..%.1f° ш.",
			p.Name,
			w,
			h,
			p.Lon0,
			p.Lon1,
			p.Lat0,
			p.Lat1
		)
	)

	-- Суша минус озёра.
	local land = buffer.create(n)
	for _, f in naturalEarth("ne_50m_land") do
		for _, poly in polygonsOf(f.geometry) do
			Geo.fillPolygon(land, v, poly, 1)
		end
	end
	for _, f in naturalEarth("ne_50m_lakes") do
		for _, poly in polygonsOf(f.geometry) do
			Geo.fillPolygon(land, v, poly, 0)
		end
	end
	-- Мелкие острова — в воду, мелкие лужи (не моря) — в сушу.
	local landLabels, landSizes = MapGen.components(w, h, land, 1)
	for i = 0, n - 1 do
		local label = buffer.readu32(landLabels, i * 4)
		if label ~= 0 and landSizes[label] < cfg.MinIslandCells then
			buffer.writeu8(land, i, 0)
		end
	end
	local waterLabels, waterSizes, waterEdge = MapGen.components(w, h, land, 0)
	for i = 0, n - 1 do
		local label = buffer.readu32(waterLabels, i * 4)
		if label ~= 0 and not waterEdge[label] and waterSizes[label] < cfg.FillLakeCells then
			buffer.writeu8(land, i, 1)
		end
	end

	-- Пустыни и имена регионов.
	local regions = naturalEarth("ne_50m_geography_regions_polys")
	local desert = buffer.create(n)
	type Label = { ru: string, en: string, area: number, polys: { Geo.Polygon } }
	local labels: { Label } = {}
	for _, f in regions do
		local props = f.properties
		local polys = polygonsOf(f.geometry)
		if props.FEATURECLA == "Desert" then
			for _, poly in polys do
				Geo.fillPolygon(desert, v, poly, 1)
			end
		end
		local ru = Geo.cleanName(tostring(props.NAME_RU or ""))
		local en = Geo.cleanName(tostring(props.NAME_EN or props.NAME or ""))
		if NAME_CLASSES[tostring(props.FEATURECLA)] and Geo.isNameAllowed(ru, en) then
			local area = 0
			for _, poly in polys do
				area += ringArea(poly[1])
			end
			table.insert(labels, { ru = ru, en = en, area = area, polys = polys })
		end
	end
	-- Сетка подписей: крупные регионы сначала, мелкие поверх (более точное имя).
	table.sort(labels, function(a: Label, b: Label): boolean
		return a.area > b.area
	end)
	local labelGrid = buffer.create(n * 2)
	for k, label in labels do
		for _, poly in label.polys do
			Geo.scanPolygon(v, poly, function(i: number)
				buffer.writeu16(labelGrid, i * 2, k)
			end)
		end
	end

	-- Реки: только крупные (scalerank), только по суше.
	local river = buffer.create(n)
	for _, f in naturalEarth("ne_50m_rivers_lake_centerlines") do
		local props = f.properties
		if props.featurecla == "River" and (tonumber(props.scalerank) or 99) <= p.RiverMaxRank then
			for _, line in linesOf(f.geometry) do
				Geo.drawPolyline(river, v, line, 1)
			end
		end
	end
	for i = 0, n - 1 do
		if buffer.readu8(land, i) == 0 then
			buffer.writeu8(river, i, 0)
		end
	end

	-- Высоты ETOPO1: шаг выборки ≈ клетка (в угловых минутах).
	local cellMinutes = math.min((p.Lon1 - p.Lon0) / w, (p.Lat1 - p.Lat0) / h) * 60
	local stride = math.max(1, math.floor(cellMinutes))
	local url = string.format(
		ERDDAP_URL,
		tostring(p.Lat0),
		stride,
		tostring(p.Lat1),
		tostring(p.Lon0),
		stride,
		tostring(math.min(p.Lon1, 180))
	)
	local csv = fetch(url, string.format("etopo_%s_%d.csv", p.Name, stride))
	local elevation = Geo.newElevation(v)
	local points = Geo.addElevationCsv(elevation, v, csv)
	Geo.finishElevation(elevation, v)
	print(string.format("  высоты: %d точек (шаг %d′)", points, stride))

	-- Местность и провинции.
	local map = MapData.new(p.Name, p.Seed, w, h)
	map.terrain = Geo.classify(v, land, desert, river, elevation.value, p.Seed)
	local landCells = 0
	for i = 0, n - 1 do
		if buffer.readu8(map.terrain, i) ~= Types.Terrain.Water then
			landCells += 1
		end
	end
	local target = math.max(50, math.floor(landCells / p.Provinces))
	local provinceParams: Types.ProvinceParams = {
		ProvinceTargetCells = target,
		ProvinceMinCells = math.floor(target * cfg.ProvinceMinShare),
		ProvinceSeedSpacing = cfg.ProvinceSeedSpacing,
		ProvinceNoise = cfg.ProvinceNoise,
		ProvinceNoiseScale = cfg.ProvinceNoiseScale,
		ProvinceHillCost = cfg.ProvinceHillCost,
		ProvinceMountainCost = cfg.ProvinceMountainCost,
		ProvinceRiverCost = cfg.ProvinceRiverCost,
	}
	local count = MapGen.generateProvinces(map, provinceParams, Rng.new(p.Seed))

	-- Имена провинций: подпись региона в центре провинции (или ближайшая), одинаковые — с номером.
	local set = Provinces.build(map)
	local function labelNear(cell: number): number
		local direct = buffer.readu16(labelGrid, cell * 2)
		if direct ~= 0 then
			return direct
		end
		local cx, cy = cell % w, cell // w
		local best, bestD = 0, math.huge
		local r = cfg.LabelSearchCells
		for y = math.max(0, cy - r), math.min(h - 1, cy + r), 2 do
			for x = math.max(0, cx - r), math.min(w - 1, cx + r), 2 do
				local k = buffer.readu16(labelGrid, (y * w + x) * 2)
				if k ~= 0 then
					local d = (x - cx) ^ 2 + (y - cy) ^ 2
					if d < bestD then
						best, bestD = k, d
					end
				end
			end
		end
		return if bestD <= r * r then best else 0
	end
	local byLabel: { [number]: { number } } = {}
	local labelOf: { [number]: number } = {}
	for _, prov in set.list do
		local k = labelNear(prov.center)
		labelOf[prov.id] = k
		if k ~= 0 then
			local list = byLabel[k]
			if list == nil then
				list = {}
				byLabel[k] = list
			end
			table.insert(list, prov.id)
		end
	end
	local names: { { string } } = {}
	local rng = Rng.new(p.Seed + 17)
	local taken: { [string]: boolean } = {}
	local named = 0
	for k, ids in byLabel do
		table.sort(ids, function(a: number, b: number): boolean
			local ca, cb = set.list[a].center, set.list[b].center
			if ca // w ~= cb // w then
				return ca // w < cb // w
			end
			return ca < cb
		end)
		for idx, id in ids do
			local suffix = if #ids > 1 then "-" .. idx else ""
			names[id] = { labels[k].ru .. suffix, labels[k].en .. suffix }
			taken[names[id][1]] = true
			named += 1
		end
	end
	for id = 1, count do
		if names[id] == nil then
			-- Подписи рядом нет — выдуманное имя, тоже без корней реальных стран («Ulmirana» — нет).
			local g = NameGen.generate(rng, taken)
			while not Geo.isNameAllowed(g.ru, g.en) do
				taken[g.ru] = true
				g = NameGen.generate(rng, taken)
			end
			taken[g.ru] = true
			names[id] = { g.ru, g.en }
		end
	end

	-- Модуль карты.
	local chunks = MapFormat.toChunks(map, Config.MapFile.ChunkChars)
	local lines: { string } = {
		"--!strict",
		"-- @generated tools/realmap.luau — не редактировать вручную. Пересоздать: lune run tools/realmap "
			.. p.Name,
		"-- Данные: Natural Earth (public domain), ETOPO1 (NOAA). Реальных стран и границ нет.",
		"return {",
		string.format("\tname = %q,", map.name),
		string.format("\tseed = %d,", map.seed),
		string.format("\twidth = %d,", map.width),
		string.format("\theight = %d,", map.height),
		string.format("\tformatVersion = %d,", MapFormat.FORMAT_VERSION),
		"\tdata = {",
	}
	for _, chunk in chunks do
		table.insert(lines, string.format('\t\t"%s",', chunk))
	end
	table.insert(lines, "\t},")
	table.insert(lines, "\tprovinceNames = {")
	for id = 1, count do
		table.insert(lines, string.format("\t\t{ %q, %q },", names[id][1], names[id][2]))
	end
	table.insert(lines, "\t},")
	table.insert(lines, "}")
	table.insert(lines, "")
	local source = table.concat(lines, "\n")
	fs.writeFile("maps/" .. p.Name .. ".luau", source)

	-- Превью ×1 (PNG) теми же цветами, что у клиента.
	local colors = MapPaint.paint(map)
	local pixels = buffer.create(n * 3)
	for i = 0, n - 1 do
		buffer.writeu8(pixels, i * 3, buffer.readu8(colors, i * 4))
		buffer.writeu8(pixels, i * 3 + 1, buffer.readu8(colors, i * 4 + 1))
		buffer.writeu8(pixels, i * 3 + 2, buffer.readu8(colors, i * 4 + 2))
	end
	fs.writeFile("build/" .. p.Name .. ".png", Png.encodeRgb(w, h, pixels))

	local counts = MapData.terrainCounts(map)
	local parts: { string } = {}
	for name, id in Types.Terrain :: { [string]: number } do
		if id ~= Types.Terrain.Water then
			table.insert(parts, string.format("%s %.1f%%", name, (counts[id] or 0) / math.max(1, landCells) * 100))
		end
	end
	table.sort(parts)
	print(
		string.format(
			"  суша %.1f%%, провинций %d (с именами регионов %d), модуль %.0f КБ, %.1f с",
			landCells / n * 100,
			count,
			named,
			#source / 1024,
			os.clock() - started
		)
	)
	print("  " .. table.concat(parts, ", "))
end

local which = process.args[1] or Config.Match.DefaultMap
if which == "all" then
	for _, name in Config.RealMapOrder do
		build((Config.RealMaps :: any)[name])
	end
else
	local params = (Config.RealMaps :: any)[which] :: Types.RealMapParams?
	if params == nil then
		print(
			"Неизвестная карта: "
				.. which
				.. ". Есть: "
				.. table.concat(Config.RealMapOrder, ", ")
				.. ", all"
		)
		process.exit(1)
		return
	end
	build(params)
end
