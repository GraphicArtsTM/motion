--!strict
--[[
	Публикация в Roblox (закрытый тест): товары магазина и звуки через Open Cloud — без ручной работы в Creator Hub.
	Запуск из frontir/:
	  lune run tools/roblox_publish products [--dry]          — 4 пропуска и 26 товаров разработчика: создаёт
	      недостающие (по названию — повторный запуск не плодит дубли), значок — центр карточки магазина
	      (assets/cards), id — в src/shared/Config.luau.
	  lune run tools/roblox_publish sounds <userId|group:ID> [--dry] — 17 звуков и 3 мелодии (assets/audio) как Audio
	      ассеты владельца игры; id «rbxassetid://…» — в Config.Sounds / Config.Music (уже заполненные — пропускает).
	Ключ API — переменная FRONTIR_API_KEY (Creator Hub → Open Cloud → API Keys; права на игру: developer-product
	read/write, game-pass read/write; asset read/write). Без неё заголовок ставит прокси среды (облачная сессия).
	Лимит Roblox на аудио: 10 загрузок в месяц без проверки личности (ID), 100 — с проверкой.
	HTTP — curl (есть в Windows 10+, macOS, Linux).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Png = require("./lib/Png")

local UNIVERSE = 1395386473 -- «World Conquer»: хаб 4316252648 и матч 135440328929805 (apis.roblox.com/universes/v1/places)
local API = "https://apis.roblox.com"
local CONFIG = "src/shared/Config.luau"
local args = process.args
local mode = args[1]
local dry = table.find(args, "--dry") ~= nil
local apiKey = process.env.FRONTIR_API_KEY or "proxy"

type Product = {
	section: string, -- где в Config: "Passes" | "Boosts" | "Packs" | "Items" | "All"
	key: string,
	pass: boolean, -- геймпасс (иначе товар разработчика)
	name: string,
	price: number,
	art: string, -- карточка assets/cards/<art>.png
	desc: string,
}

local function P(section: string, key: string, name: string, price: number, art: string, desc: string): Product
	return {
		section = section,
		key = key,
		pass = section == "Passes",
		name = name,
		price = price,
		art = art,
		desc = desc,
	}
end

-- Цены — как в Config (проверка ниже сверяет). Названия ≤ 50 знаков: русское · английское.
local PRODUCTS: { Product } = {
	P(
		"Passes",
		"HQ",
		"Штаб · Headquarters",
		399,
		"pass_hq",
		"Навсегда: +1 линия найма и +5% дохода. Forever: +1 recruit line, +5% income."
	),
	P(
		"Passes",
		"Intel",
		"Разведуправление · Intelligence",
		249,
		"pass_intel",
		"Навсегда: разведка вдвое дешевле и дольше. Forever: cheaper, longer intel."
	),
	P(
		"Passes",
		"Vip",
		"VIP",
		299,
		"pass_vip",
		"Навсегда: опыт ×1.5 и золотое имя. Forever: XP ×1.5 and a gold name."
	),
	P(
		"Passes",
		"AllCommanders",
		"Все генералы · All Commanders",
		199,
		"pass_allcommanders",
		"Навсегда: все генералы сразу. Forever: every commander unlocked."
	),
	P(
		"Boosts",
		"Mobilize",
		"Мобилизация · Mobilization",
		49,
		"boost_mobilize",
		"Гарнизон пополняется в бою. Instantly reinforces your garrison."
	),
	P(
		"Boosts",
		"Loan",
		"Военный заём · War Loan",
		39,
		"boost_loan",
		"Деньги сразу в казну. Money straight to your treasury."
	),
	P(
		"Boosts",
		"Research",
		"Срочное исследование · Rush Research",
		29,
		"boost_research",
		"Текущее исследование готово сразу. Finishes current research."
	),
	P(
		"Boosts",
		"Reserve",
		"Резерв генерала · Commander Reserve",
		25,
		"boost_reserve",
		"Перезарядка генерала сразу. Resets commander cooldowns."
	),
	P(
		"Boosts",
		"Guards",
		"Гвардия · Guards",
		59,
		"boost_guards",
		"Отряд опытных танков. A squad of veteran tanks."
	),
	P(
		"Boosts",
		"Airstrike",
		"Авиаудар · Airstrike",
		45,
		"ability_airstrike",
		"Удар с воздуха по выбранной клетке. Air strike on a chosen spot."
	),
	P(
		"Boosts",
		"Squadron",
		"Эскадра · Squadron",
		49,
		"boost_squadron",
		"Эсминец и транспорт у порта. A destroyer and a transport."
	),
	P(
		"Boosts",
		"AirWing",
		"Авиакрыло · Air Wing",
		49,
		"boost_airwing",
		"Истребитель и бомбардировщик. A fighter and a bomber."
	),
	P(
		"Packs",
		"Recruit",
		"Набор новобранца · Recruit Pack",
		99,
		"shop_recruit",
		"Жетоны и медали для старта. Tokens and medals to start."
	),
	P("Packs", "Medals", "Медали · Medals", 79, "shop_medals", "2000 медалей. 2000 medals."),
	P(
		"Packs",
		"Tokens",
		"Жетоны штаба · HQ Tokens",
		99,
		"shop_tokens",
		"3 жетона штаба. 3 HQ tokens."
	),
	P(
		"Packs",
		"Crate1",
		"Ящик снабжения · Supply Crate",
		49,
		"shop_crates",
		"1 ящик снабжения. 1 supply crate."
	),
	P(
		"Packs",
		"Crate5",
		"5 ящиков · 5 Crates",
		199,
		"shop_crates",
		"5 ящиков снабжения. 5 supply crates."
	),
	P(
		"Packs",
		"PathPremium",
		"Премиум-дорога · Premium Path",
		499,
		"shop_pathpremium",
		"Премиум-дорога «Пути командира» навсегда. Commander's Path premium track."
	),
	P(
		"Packs",
		"Weekly",
		"Предложение недели · Weekly Offer",
		119,
		"shop_weekly",
		"Набор недели. This week's bundle."
	),
	P(
		"Packs",
		"PathPremiumPlus",
		"Премиум + 10 уровней · Premium +10",
		699,
		"shop_pathpremiumplus",
		"Премиум-дорога и сразу +10 уровней. Premium track and +10 levels."
	),
	P(
		"Packs",
		"Levels5",
		"+5 уровней · +5 Levels",
		149,
		"shop_levels",
		"+5 уровней «Пути командира». +5 Commander's Path levels."
	),
	P(
		"Packs",
		"XpBoost1",
		"Опыт ×2 на сутки · XP ×2 Day",
		79,
		"shop_xpboost",
		"Двойной опыт на 24 часа. Double XP for 24 hours."
	),
	P(
		"Packs",
		"XpBoost7",
		"Опыт ×2 на неделю · XP ×2 Week",
		249,
		"shop_xpboost",
		"Двойной опыт на 7 дней. Double XP for 7 days."
	),
	P(
		"Packs",
		"ParadeSet",
		"Парадный набор · Parade Set",
		249,
		"shop_paradeset",
		"Узор, вспышка и титул. Pattern, capture flash and title."
	),
	P("Items", "Tanks", "Танки · Tanks", 99, "unlock_tanks", "Танки навсегда. Tanks forever."),
	P(
		"Items",
		"Intel",
		"Разведка · Intel",
		79,
		"pass_intel",
		"Разведка навсегда. Intel forever."
	),
	P(
		"Items",
		"Artillery",
		"Артиллерия · Artillery",
		99,
		"unlock_artillery",
		"Артиллерия навсегда. Artillery forever."
	),
	P(
		"Items",
		"AntiAir",
		"ПВО · Anti-Air",
		79,
		"unlock_antiair",
		"Зенитки навсегда. Anti-air forever."
	),
	P(
		"Items",
		"Missile",
		"Ракетная шахта · Missile Silo",
		149,
		"unlock_missile",
		"Ракетная шахта навсегда. Missile silo forever."
	),
	P(
		"All",
		"All",
		"Вся техника · All Units",
		299,
		"unlock_all",
		"Вся техника навсегда. Every unit forever."
	),
}

local SOUNDS = {
	"Click",
	"Error",
	"Capture",
	"Province",
	"Battle",
	"Explosion",
	"Plane",
	"Parachute",
	"Siren",
	"Offer",
	"Betrayal",
	"Victory",
	"Defeat",
	"Notify",
	"Coin",
	"Hire",
	"Build",
}
local MUSIC = { "Menu", "Match", "War" }

-- Где начинается раздел в Config (дальше ищем строку ключа).
local SECTION_START: { [string]: string } = {
	Passes = "\n\tPasses = {",
	Boosts = "\n\tBoosts = {",
	Packs = "\n\tPacks = {",
	Items = "\nConfig.Unlocks = {",
	All = "\nConfig.Unlocks = {",
	Sounds = "\nConfig.Sounds = {",
	Music = "\nConfig.Music = {",
}

local function sectionKeyAt(text: string, section: string, key: string): (number?, number?)
	local start = string.find(text, SECTION_START[section], 1, true)
	if start == nil then
		return nil, nil
	end
	local indent = if section == "Items"
		then "\t\t"
		elseif section == "All" or section == "Sounds" or section == "Music" then "\t"
		else "\t\t"
	local a, b = string.find(text, "\n" .. indent .. key .. " = {", start, true)
	return a, b
end

-- Значение поля id у ключа раздела (число или строка в кавычках) и его место.
local function idField(text: string, section: string, key: string): (string?, number?, number?)
	local _, b = sectionKeyAt(text, section, key)
	if b == nil then
		return nil, nil, nil
	end
	local s, e, value = string.find(text, "id = ([^,}]+)", b)
	if s == nil or s - b > 200 then
		return nil, nil, nil
	end
	return value, s, e
end

local function setId(text: string, section: string, key: string, value: string): string
	local _, s, e = idField(text, section, key)
	assert(s ~= nil and e ~= nil, "нет поля id: " .. section .. "." .. key)
	return string.sub(text, 1, s - 1) .. "id = " .. value .. string.sub(text, e + 1)
end

local function priceOf(text: string, section: string, key: string): number?
	local _, b = sectionKeyAt(text, section, key)
	if b == nil then
		return nil
	end
	local s, _, value = string.find(text, "price = (%d+)", b)
	if s == nil or s - b > 200 then
		return nil
	end
	return tonumber(value)
end

-- curl: тело ответа (JSON) или ошибка.
local function curl(params: { string }): (boolean, any)
	local all = { "-sS", "--max-time", "120", "-w", "\n%{http_code}", "-H", "x-api-key: " .. apiKey }
	for _, p in params do
		table.insert(all, p)
	end
	local r = process.exec("curl", all)
	if not r.ok then
		return false, r.stderr
	end
	local body, code = string.match(r.stdout, "^(.*)\n(%d+)$")
	local status = tonumber(code) or 0
	local okJson, decoded = pcall(serde.decode, "json" :: any, body or "")
	if status < 200 or status >= 300 then
		return false, "HTTP " .. tostring(status) .. ": " .. tostring(body)
	end
	return true, if okJson then decoded else body
end

local function listAll(path: string, field: string): { any }
	local out = {}
	local token: string? = nil
	repeat
		local url = API .. path .. "?pageSize=50" .. (if token ~= nil then "&pageToken=" .. token else "")
		local ok, res = curl({ url })
		assert(ok, "список не получен: " .. tostring(res))
		for _, item in res[field] or {} do
			table.insert(out, item)
		end
		token = res.nextPageToken
	until token == nil or token == ""
	return out
end

-- Значок: центр карточки 3:2 — квадрат (PNG без прозрачности).
local function icon(art: string): string
	local img = Png.decode(fs.readFile("assets/cards/" .. art .. ".png"))
	local side = math.min(img.width, img.height)
	local ox, oy = (img.width - side) // 2, (img.height - side) // 2
	local px = buffer.create(side * side * 3)
	for y = 0, side - 1 do
		for x = 0, side - 1 do
			local o = ((oy + y) * img.width + ox + x) * 4
			local t = (y * side + x) * 3
			buffer.writeu8(px, t, buffer.readu8(img.rgba, o))
			buffer.writeu8(px, t + 1, buffer.readu8(img.rgba, o + 1))
			buffer.writeu8(px, t + 2, buffer.readu8(img.rgba, o + 2))
		end
	end
	fs.writeDir("build/icons_upload")
	local path = "build/icons_upload/" .. art .. ".png"
	fs.writeFile(path, Png.encodeRgb(side, side, px))
	return path
end

local function products()
	local text = fs.readFile(CONFIG)
	-- Цены в инструменте и в Config должны совпадать (иначе игра покажет одну цену, а Roblox спишет другую).
	for _, p in PRODUCTS do
		local price = priceOf(text, p.section, p.key)
		assert(
			price == p.price,
			string.format(
				"%s.%s: цена в Config %s, в инструменте %d",
				p.section,
				p.key,
				tostring(price),
				p.price
			)
		)
	end
	local existing: { [string]: number } = {}
	if not dry then
		for _, g in listAll("/game-passes/v1/universes/" .. UNIVERSE .. "/game-passes/creator", "gamePasses") do
			existing["pass:" .. g.name] = g.gamePassId
		end
		for _, d in
			listAll(
				"/developer-products/v2/universes/" .. UNIVERSE .. "/developer-products/creator",
				"developerProducts"
			)
		do
			existing["product:" .. d.name] = d.productId
		end
	end
	local made, reused, skipped = 0, 0, 0
	for _, p in PRODUCTS do
		local current = idField(text, p.section, p.key)
		local tag = (if p.pass then "pass:" else "product:") .. p.name
		local id: number? = nil
		if current ~= nil and current ~= "0" then
			skipped += 1
			print(string.format("  = %s.%s уже id %s", p.section, p.key, current))
		elseif existing[tag] ~= nil then
			id = existing[tag]
			reused += 1
			print(string.format("  ↺ %s.%s — уже есть на Roblox: %d", p.section, p.key, id :: number))
		elseif dry then
			print(string.format("  + %s.%s «%s» R$%d (значок %s)", p.section, p.key, p.name, p.price, p.art))
		else
			local path = if p.pass
				then "/game-passes/v1/universes/" .. UNIVERSE .. "/game-passes"
				else "/developer-products/v2/universes/" .. UNIVERSE .. "/developer-products"
			local ok, res = curl({
				"-X",
				"POST",
				API .. path,
				"--form-string",
				"name=" .. p.name,
				"--form-string",
				"description=" .. p.desc,
				"--form-string",
				"price=" .. tostring(p.price),
				"--form-string",
				"isForSale=true",
				"-F",
				"imageFile=@" .. icon(p.art) .. ";type=image/png",
			})
			assert(ok, string.format("%s.%s не создан: %s", p.section, p.key, tostring(res)))
			id = if p.pass then res.gamePassId else res.productId
			made += 1
			print(string.format("  + %s.%s создан: %s", p.section, p.key, tostring(id)))
		end
		if id ~= nil then
			text = setId(text, p.section, p.key, tostring(id))
			fs.writeFile(CONFIG, text) -- после каждого: прервётся — созданное не потеряется
		end
	end
	print(
		string.format(
			"товары: создано %d, найдено готовых %d, уже были в Config %d",
			made,
			reused,
			skipped
		)
	)
end

local function sounds(owner: string?)
	assert(owner ~= nil, "нужен владелец игры: userId или group:ID")
	local creator = if string.sub(owner, 1, 6) == "group:"
		then { groupId = string.sub(owner, 7) }
		else { userId = owner }
	local text = fs.readFile(CONFIG)
	local list: { { section: string, key: string, file: string, mime: string } } = {}
	for _, k in SOUNDS do
		table.insert(
			list,
			{ section = "Sounds", key = k, file = "assets/audio/sfx/" .. k .. ".wav", mime = "audio/wav" }
		)
	end
	for _, k in MUSIC do
		table.insert(
			list,
			{ section = "Music", key = k, file = "assets/audio/music/" .. k .. ".mp3", mime = "audio/mpeg" }
		)
	end
	local made = 0
	for _, s in list do
		local current = idField(text, s.section, s.key)
		if current ~= nil and current ~= '""' then
			print(string.format("  = %s.%s уже %s", s.section, s.key, current))
			continue
		end
		assert(fs.isFile(s.file), "нет файла " .. s.file)
		if dry then
			print("  + " .. s.file)
			continue
		end
		local request = serde.encode("json", {
			assetType = "Audio",
			displayName = "Frontir " .. s.key,
			description = "World Conquer: " .. s.section .. " " .. s.key,
			creationContext = { creator = creator },
		})
		local ok, res = curl({
			"-X",
			"POST",
			API .. "/assets/v1/assets",
			"--form-string",
			"request=" .. request,
			"-F",
			"fileContent=@" .. s.file .. ";type=" .. s.mime,
		})
		assert(ok, s.key .. " не загружен: " .. tostring(res))
		local opPath = res.path -- "operations/<id>"
		local assetId: string? = nil
		for _ = 1, 60 do
			local okOp, op = curl({ API .. "/assets/v1/" .. opPath })
			assert(okOp, "операция " .. tostring(opPath) .. ": " .. tostring(op))
			if op.done then
				assert(
					op.response ~= nil,
					s.key .. ": загрузка не прошла: " .. serde.encode("json", op)
				)
				assetId = tostring(op.response.assetId)
				break
			end
			process.exec("sleep", { "2" })
		end
		assert(assetId ~= nil, s.key .. ": загрузка не закончилась за 2 минуты")
		text = setId(text, s.section, s.key, '"rbxassetid://' .. assetId .. '"')
		fs.writeFile(CONFIG, text)
		made += 1
		print(string.format("  + %s.%s → rbxassetid://%s", s.section, s.key, assetId))
	end
	print(string.format("звуки: загружено %d", made))
end

if mode == "products" then
	products()
elseif mode == "sounds" then
	sounds(args[2])
else
	print("lune run tools/roblox_publish products|sounds <userId|group:ID> [--dry]")
end
