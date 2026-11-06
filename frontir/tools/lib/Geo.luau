--!strict
--[[
	Geo — реальная география в сетку карты (tools/realmap, GDD §4). Чистые функции, тесты — tests/Geo.spec.

	- Проекция равнопромежуточная: окно [Lon0..Lon1] × [Lat0..Lat1] растягивается на сетку Width × Height.
	- fillPolygon — заливка многоугольника (внешнее кольцо и дыры, правило чёт-нечет) по центрам клеток.
	- drawPolyline — линия по клеткам без «дыр» по диагонали (реки должны быть сплошными для 4 соседей).
	- addElevation / finishElevation — средняя высота клетки из точек ETOPO, пустые клетки — от соседей.
	- classify — местность по высоте, перепаду, пустыням Natural Earth, широте и шуму лесов.
	- isNameAllowed — имя подписи без реальных стран и спорных территорий (§0: никаких реальных стран).
]]

local Config = require("../../src/shared/Config")
local Noise = require("../../src/shared/Noise")
local Types = require("../../src/shared/Types")

export type View = { lon0: number, lon1: number, lat0: number, lat1: number, width: number, height: number }
export type Ring = { { number } } -- точки { долгота, широта }
export type Polygon = { Ring } -- первое кольцо — внешнее, дальше дыры

local Geo = {}

function Geo.view(p: Types.RealMapParams): View
	return { lon0 = p.Lon0, lon1 = p.Lon1, lat0 = p.Lat0, lat1 = p.Lat1, width = p.Width, height = p.Height }
end

-- Долгота/широта → дробные координаты клетки (0..width, 0..height; y растёт к югу).
function Geo.toCell(v: View, lon: number, lat: number): (number, number)
	return (lon - v.lon0) / (v.lon1 - v.lon0) * v.width, (v.lat1 - lat) / (v.lat1 - v.lat0) * v.height
end

-- Центр клетки → долгота/широта.
function Geo.toLonLat(v: View, x: number, y: number): (number, number)
	return v.lon0 + (x + 0.5) / v.width * (v.lon1 - v.lon0), v.lat1 - (y + 0.5) / v.height * (v.lat1 - v.lat0)
end

-- Вызывает fn(i) для каждой клетки, чей центр внутри многоугольника (внешнее кольцо минус дыры).
function Geo.scanPolygon(v: View, poly: Polygon, fn: (i: number) -> ())
	local w, h = v.width, v.height
	type Edge = { x0: number, y0: number, x1: number, y1: number }
	local edges: { Edge } = {}
	local ymin, ymax = math.huge, -math.huge
	for _, ring in poly do
		local n = #ring
		for k = 1, n do
			local a, b = ring[k], ring[k % n + 1]
			local ax, ay = Geo.toCell(v, a[1], a[2])
			local bx, by = Geo.toCell(v, b[1], b[2])
			if ay ~= by then
				table.insert(edges, { x0 = ax, y0 = ay, x1 = bx, y1 = by })
				ymin = math.min(ymin, ay, by)
				ymax = math.max(ymax, ay, by)
			end
		end
	end
	if #edges == 0 then
		return
	end
	local rowFrom = math.max(0, math.ceil(ymin - 0.5))
	local rowTo = math.min(h - 1, math.floor(ymax - 0.5))
	local xs: { number } = {}
	for y = rowFrom, rowTo do
		local cy = y + 0.5
		table.clear(xs)
		for _, e in edges do
			if (e.y0 <= cy and e.y1 > cy) or (e.y1 <= cy and e.y0 > cy) then
				table.insert(xs, e.x0 + (cy - e.y0) / (e.y1 - e.y0) * (e.x1 - e.x0))
			end
		end
		table.sort(xs)
		for k = 1, #xs - 1, 2 do
			local xa = math.max(0, math.ceil(xs[k] - 0.5))
			local xb = math.min(w - 1, math.floor(xs[k + 1] - 0.5))
			for x = xa, xb do
				fn(y * w + x)
			end
		end
	end
end

-- Заливает в mask (u8 на клетку) значение value во всех клетках, чей центр внутри многоугольника.
function Geo.fillPolygon(mask: buffer, v: View, poly: Polygon, value: number)
	Geo.scanPolygon(v, poly, function(i: number)
		buffer.writeu8(mask, i, value)
	end)
end

-- Рисует ломаную (точки { долгота, широта }) клетками: соседние клетки линии всегда касаются стороной.
function Geo.drawPolyline(mask: buffer, v: View, points: { { number } }, value: number)
	local w, h = v.width, v.height
	local function put(x: number, y: number)
		if x >= 0 and y >= 0 and x < w and y < h then
			buffer.writeu8(mask, y * w + x, value)
		end
	end
	local px: number?, py: number? = nil, nil
	for k = 1, #points - 1 do
		local ax, ay = Geo.toCell(v, points[k][1], points[k][2])
		local bx, by = Geo.toCell(v, points[k + 1][1], points[k + 1][2])
		local steps = math.max(1, math.ceil(math.max(math.abs(bx - ax), math.abs(by - ay)) * 2))
		for s = 0, steps do
			local t = s / steps
			local x = math.floor(ax + (bx - ax) * t)
			local y = math.floor(ay + (by - ay) * t)
			if px ~= nil and py ~= nil and x ~= px and y ~= py then
				put(x, py) -- шаг по диагонали — добавляем угол, чтобы линия была сплошной
			end
			put(x, y)
			px, py = x, y
		end
	end
end

-- Накопление высот ETOPO: сумма и число точек на клетку.
export type Elevation = { sum: { number }, count: { number }, value: { number } }

function Geo.newElevation(v: View): Elevation
	local n = v.width * v.height
	return { sum = table.create(n, 0), count = table.create(n, 0), value = table.create(n, 0) }
end

-- Добавляет точки из CSV ERDDAP (строки «широта,долгота,высота»; шапки пропускаются). Возвращает число точек.
function Geo.addElevationCsv(e: Elevation, v: View, csv: string): number
	local added = 0
	for latText, lonText, altText in string.gmatch(csv, "([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)") do
		local lat, lon, alt = tonumber(latText), tonumber(lonText), tonumber(altText)
		if lat ~= nil and lon ~= nil and alt ~= nil then
			local cx, cy = Geo.toCell(v, lon, lat)
			local x, y = math.floor(cx), math.floor(cy)
			if x >= 0 and y >= 0 and x < v.width and y < v.height then
				local i = y * v.width + x + 1
				e.sum[i] += alt
				e.count[i] += 1
				added += 1
			end
		end
	end
	return added
end

-- Средние высоты; клетки без точек получают значение ближайших заполненных соседей (несколько проходов).
function Geo.finishElevation(e: Elevation, v: View)
	local w, h = v.width, v.height
	local n = w * h
	local known: { boolean } = table.create(n, false)
	for i = 1, n do
		if e.count[i] > 0 then
			e.value[i] = e.sum[i] / e.count[i]
			known[i] = true
		end
	end
	for _ = 1, 8 do
		local changed = false
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				local i = y * w + x + 1
				if not known[i] then
					local sum, cnt = 0, 0
					for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local nx, ny = x + d[1], y + d[2]
						if nx >= 0 and ny >= 0 and nx < w and ny < h and known[ny * w + nx + 1] then
							sum += e.value[ny * w + nx + 1]
							cnt += 1
						end
					end
					if cnt > 0 then
						e.value[i] = sum / cnt
						known[i] = true
						changed = true
					end
				end
			end
		end
		if not changed then
			break
		end
	end
end

-- Доля леса на широте lat: линейно между точками Config.RealMapTerrain.ForestByLatitude.
function Geo.forestShare(lat: number): number
	local a = math.abs(lat)
	local points = Config.RealMapTerrain.ForestByLatitude
	if a <= points[1].lat then
		return points[1].share
	end
	for k = 2, #points do
		local p0, p1 = points[k - 1], points[k]
		if a <= p1.lat then
			return p0.share + (p1.share - p0.share) * (a - p0.lat) / (p1.lat - p0.lat)
		end
	end
	return points[#points].share
end

-- Местность суши по высоте (м), перепаду (м), пустыне, широте и шуму леса (fbm, около 0.5 ± ForestNoiseSpread).
-- tundraShift — сдвиг границы тундры в градусах (неровная граница вместо прямой линии).
-- reliefScale — во сколько раз поднять пороги перепада (крупные клетки, см. Geo.reliefScale).
function Geo.landTerrain(
	elev: number,
	relief: number,
	desert: boolean,
	lat: number,
	forestNoise: number,
	tundraShift: number?,
	reliefScale: number?
): number
	local cfg = Config.RealMapTerrain
	local T = Types.Terrain
	local k = reliefScale or 1
	local polar = math.abs(lat) + (tundraShift or 0) >= cfg.TundraLatitude
	-- Ледяные щиты и полярные плато (Гренландия): высоко, но ровно — тундра, а не горы.
	if polar and relief < cfg.MountainRelief * k then
		return T.Tundra
	end
	if elev >= cfg.MountainMeters or (elev >= cfg.MountainBaseMeters and relief >= cfg.MountainRelief * k) then
		return T.Mountains
	elseif elev >= cfg.HillMeters or relief >= cfg.HillRelief * k then
		return T.Hills
	elseif desert then
		return T.Desert
	elseif polar then
		return T.Tundra
	elseif forestNoise < 0.5 + (Geo.forestShare(lat) - 0.5) * 2 * cfg.ForestNoiseSpread then
		return T.Forest
	end
	return T.Plains
end

-- Во сколько раз поднять пороги перепада для клеток этой карты: √(размер клетки в км / ReliefRefCellKm).
function Geo.reliefScale(v: View): number
	local midLat = math.rad((v.lat0 + v.lat1) / 2)
	local latKm = (v.lat1 - v.lat0) / v.height * 111.32
	local lonKm = (v.lon1 - v.lon0) / v.width * 111.32 * math.cos(midLat)
	return math.max(1, math.sqrt(math.sqrt(latKm * lonKm) / Config.RealMapTerrain.ReliefRefCellKm))
end

-- Местность всей карты: land / desert / river — маски (u8), elevation — средние высоты по клеткам.
function Geo.classify(v: View, land: buffer, desert: buffer, river: buffer, elevation: { number }, seed: number): buffer
	local cfg = Config.RealMapTerrain
	local w, h = v.width, v.height
	local out = buffer.create(w * h)
	local reliefK = Geo.reliefScale(v)
	for y = 0, h - 1 do
		local _, lat = Geo.toLonLat(v, 0, y)
		for x = 0, w - 1 do
			local i = y * w + x
			if buffer.readu8(land, i) == 1 then
				local lo, hi = math.huge, -math.huge
				for dy = -1, 1 do
					for dx = -1, 1 do
						local nx, ny = x + dx, y + dy
						if nx >= 0 and ny >= 0 and nx < w and ny < h and buffer.readu8(land, ny * w + nx) == 1 then
							local e = elevation[ny * w + nx + 1]
							lo = math.min(lo, e)
							hi = math.max(hi, e)
						end
					end
				end
				local s = cfg.ForestNoiseScale
				local noise = Noise.fbm(x / s, y / s, seed, 3, 2.0, 0.5)
				local shift = (Noise.value2(x / s, y / s, seed + 101) * 2 - 1) * cfg.TundraJitter
				local isDesert = buffer.readu8(desert, i) == 1
				local t = Geo.landTerrain(elevation[i + 1], hi - lo, isDesert, lat, noise, shift, reliefK)
				if buffer.readu8(river, i) == 1 and t ~= Types.Terrain.Mountains then
					t = Types.Terrain.River
				end
				buffer.writeu8(out, i, t)
			else
				buffer.writeu8(out, i, Types.Terrain.Water)
			end
		end
	end
	return out
end

-- Корни названий реальных стран и спорных территорий: подпись с ними не становится именем провинции.
-- Русские — с заглавной (так пишутся в подписях), английские — в нижнем регистре.
local DENY_RU = {
	"Инди",
	"Китай",
	"Китая",
	"Япон",
	"Коре",
	"Монгол",
	"Иран",
	"Ирак",
	"Турец",
	"Турци",
	"Сири",
	"Ливан",
	"Израил",
	"Палестин",
	"Иордан",
	"Египет",
	"Ливи",
	"Тунис",
	"Алжир",
	"Марокк",
	"Эфиоп",
	"Сомали",
	"Судан",
	"Кени",
	"Танзани",
	"Конго",
	"Ангол",
	"Намиби",
	"Ботсван",
	"Мадагаскар",
	"Канад",
	"Мексик",
	"Бразил",
	"Аргентин",
	"Чили",
	"Перу",
	"Боливи",
	"Колумби",
	"Венесуэл",
	"Эквадор",
	"Парагва",
	"Уругва",
	"Гвиан",
	"Гайан",
	"Куба",
	"Гаити",
	"Ямайк",
	"Исланд",
	"Ирланд",
	"Британ",
	"Норвеж",
	"Норвег",
	"Швед",
	"Швеци",
	"Финлянд",
	"Финск",
	"Датск",
	"Дани",
	"Польск",
	"Польш",
	"Герман",
	"Немец",
	"Франц",
	"Испан",
	"Португал",
	"Итали",
	"Италь",
	"Греци",
	"Греч",
	"Болгар",
	"Румын",
	"Венгер",
	"Венгри",
	"Чехи",
	"Чешск",
	"Словак",
	"Серби",
	"Сербск",
	"Хорват",
	"Босни",
	"Албан",
	"Македон",
	"Черногор",
	"Украин",
	"Росси",
	"Русск",
	"Белорус",
	"Литв",
	"Латви",
	"Эстон",
	"Молдав",
	"Кипр",
	"Мальт",
	"Грузи",
	"Грузин",
	"Армян",
	"Армени",
	"Азербайдж",
	"Казах",
	"Узбек",
	"Туркмен",
	"Кирги",
	"Таджик",
	"Афган",
	"Пакистан",
	"Непал",
	"Бутан",
	"Бангладеш",
	"Шри-Ланк",
	"Мьянм",
	"Бирм",
	"Таиланд",
	"Тайланд",
	"Лаос",
	"Камбодж",
	"Вьетнам",
	"Малайзи",
	"Сингапур",
	"Филиппин",
	"Тайван",
	"Тибет",
	"Кашмир",
	"Крым",
	"Курд",
	"Косов",
	"Абхаз",
	"Осети",
	"Гвине",
	"Австрал",
	"Гренланд",
	"Курил",
	"Фолкленд",
	"Мальвин",
	"Спратли",
	"Парасел",
	"Сенкаку",
	"Микронез",
	"Саудов",
	"Соломон",
	"Самоа",
	"Фиджи",
	"Вануату",
	"Тувал",
	"Тонга",
	"Палау",
	"Науру",
	"Кирибат",
	"Маршалл",
	"Багам",
	"Тринидад",
	"Сейшел",
	"Маврики",
	"Комор",
	"Кабо-Верде",
	"Тимор",
	"Бахрейн",
	"Катар",
	"Кувейт",
	"Йемен",
	"Оман",
	"Сальвадор",
	"Гондурас",
	"Никарагуа",
	"Панам",
	"Коста-Рик",
	"Белиз",
	"Гватемал",
	"Доминик",
	"Пуэрто-Рико",
	"Бруней",
	"Эритре",
	"Джибути",
	"Уганд",
	"Руанд",
	"Бурунди",
	"Малави",
	"Мозамбик",
	"Зимбабв",
	"Замби",
	"Нигер",
	"Бенин",
	"Камерун",
	"Габон",
	"Мавритан",
	"Сенегал",
	"Гамби",
	"Либери",
	"Сьерра-Леоне",
	"Буркина",
	"Лесото",
	"Свазиленд",
	"Эсватини",
	"Бельги",
	"Нидерланд",
	"Голланд",
	"Люксембург",
	"Швейцар",
	"Австри",
	"Лихтенштейн",
	"Андорр",
	"Монако",
	"Сан-Марино",
	"Ватикан",
	"Словени",
}
local DENY_EN = {
	"india",
	"china",
	"chinese",
	"japan",
	"korea",
	"mongol",
	"iran",
	"iraq",
	"turk",
	"syria",
	"leban",
	"israel",
	"palestin",
	"jordan",
	"egypt",
	"libya",
	"tunis",
	"algeria",
	"morocc",
	"ethiop",
	"somali",
	"sudan",
	"kenya",
	"tanzan",
	"congo",
	"angola",
	"namibia",
	"botswan",
	"madagascar",
	"canad",
	"mexic",
	"brazil",
	"argentin",
	"chile",
	"peru",
	"bolivia",
	"colombia",
	"venezuel",
	"ecuador",
	"paragua",
	"urugua",
	"guian",
	"guyan",
	"cuba",
	"haiti",
	"jamaica",
	"iceland",
	"ireland",
	"irish",
	"britain",
	"british",
	"norw",
	"swed",
	"finland",
	"finn",
	"danish",
	"denmark",
	"poland",
	"polish",
	"german",
	"france",
	"french",
	"spain",
	"spanish",
	"portug",
	"ital",
	"greece",
	"greek",
	"bulgar",
	"romania",
	"hungar",
	"czech",
	"slovak",
	"serbia",
	"croat",
	"bosnia",
	"albania",
	"macedon",
	"monteneg",
	"ukrain",
	"russia",
	"belarus",
	"lithuan",
	"latvia",
	"eston",
	"moldov",
	"cyprus",
	"malta",
	"georgia",
	"armenia",
	"azerbai",
	"kazakh",
	"uzbek",
	"turkmen",
	"kyrgyz",
	"tajik",
	"afghan",
	"pakistan",
	"nepal",
	"bhutan",
	"bangladesh",
	"sri lanka",
	"myanmar",
	"burm",
	"thai",
	"laos",
	"cambod",
	"vietnam",
	"malaysia",
	"singapore",
	"philippin",
	"taiwan",
	"tibet",
	"kashmir",
	"crimea",
	"kurd",
	"kosov",
	"abkhaz",
	"osseti",
	"guinea",
	"austral",
	"greenland",
	"kuril",
	"falkland",
	"malvinas",
	"spratly",
	"paracel",
	"senkaku",
	"micronesia",
	"saudi",
	"solomon",
	"samoa",
	"fiji",
	"vanuatu",
	"tuvalu",
	"tonga",
	"palau",
	"nauru",
	"kiribati",
	"marshall",
	"bahama",
	"trinidad",
	"seychell",
	"mauriti",
	"comoro",
	"cape verde",
	"timor",
	"bahrain",
	"qatar",
	"kuwait",
	"yemen",
	"oman",
	"salvador",
	"hondura",
	"nicaragua",
	"panama",
	"costa rica",
	"belize",
	"guatemal",
	"dominic",
	"puerto rico",
	"brunei",
	"eritre",
	"djibouti",
	"uganda",
	"rwanda",
	"burundi",
	"malawi",
	"mozambi",
	"zimbabw",
	"zambia",
	"niger",
	"benin",
	"cameroon",
	"gabon",
	"mauritan",
	"senegal",
	"gambia",
	"liberia",
	"sierra leone",
	"burkina",
	"lesotho",
	"swazi",
	"eswatini",
	"belgi",
	"netherland",
	"holland",
	"dutch",
	"luxembourg",
	"switzerland",
	"swiss",
	"austria",
	"liechtenstein",
	"andorra",
	"monaco",
	"san marino",
	"vatican",
	"sloven",
}

-- Имя подписи без знаков ударения (в Natural Earth встречается «Эльбу́рс») и лишних пробелов.
function Geo.cleanName(name: string): string
	local out = string.gsub(name, "\u{301}", "")
	out = string.gsub(out, "^%s*(.-)%s*$", "%1")
	return out
end

-- Можно ли подпись (ru, en) сделать именем провинции: нет корней реальных стран и спорных территорий.
function Geo.isNameAllowed(ru: string, en: string): boolean
	if ru == "" or en == "" then
		return false
	end
	for _, stem in DENY_RU do
		if string.find(ru, stem, 1, true) ~= nil then
			return false
		end
	end
	local lower = string.lower(en)
	for _, stem in DENY_EN do
		if string.find(lower, stem, 1, true) ~= nil then
			return false
		end
	end
	return true
end

-- Название города (§15д ч.4): отбрасывается, если какое-то его слово — почти целиком корень реальной страны
-- (Алжир, Люксембург, Кувейт, Бразилиа, Андорра-ла-Велья), но не когда корень — лишь начало длинного слова
-- (Бирмингем — не «Бирма»). Слова — по пробелам и дефисам; доля длины корня в слове не меньше 0.6.
function Geo.isCityNameAllowed(ru: string, en: string): boolean
	if ru == "" or en == "" then
		return false
	end
	local function denied(name: string, stems: { string }, lower: boolean): boolean
		local text = if lower then string.lower(name) else name
		for word in string.gmatch(text, "[^%s%-]+") do
			local len = utf8.len(word) or #word
			for _, stem in stems do
				if string.sub(word, 1, #stem) == stem and (utf8.len(stem) or #stem) / len >= 0.6 then
					return true
				end
			end
		end
		return false
	end
	return not denied(ru, DENY_RU, false) and not denied(en, DENY_EN, true)
end

return table.freeze(Geo)
