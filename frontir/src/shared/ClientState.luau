--!strict
--[[
	ClientState — что клиент знает о матче: копия владельцев клеток, державы, фаза, статистика.
	Собирается только из сообщений сервера (Net/Protocol + таблица info), поэтому у всех клиентов
	одинаковые границы (критерий этапа 2). Чистый модуль: тест прогоняет матч через сериализацию
	и сравнивает копию клиента с сеткой сервера побайтно.
]]

local Config = require("./Config")
local Fog = require("./Fog")
local Modes = require("./Modes")
local ServerSettings = require("./ServerSettings")
local Protocol = require("./Net/Protocol")
local Types = require("./Types")

export type NationInfo = {
	id: number,
	name: string,
	nameEn: string,
	colorIndex: number,
	capital: number?,
	isBot: boolean,
	botLevel: Types.BotLevel?, -- уровень бота (§9.1), метка в таблице лидеров
	personality: Types.BotPersonality?,
	commander: Types.CommanderId?, -- генерал (§6.15)
	alive: boolean,
	team: number?, -- команда («Команды», §5.1)
	hunt: number?, -- исходных столиц врагов держит («Охота на столицы»)
	huntLeft: number?, -- секунд до победы охотой (держит нужное число)
}

-- Режим матча (§5.1, этап 8а): голосование в лобби, против ботов, пауза и ×2.
export type ModeInfo = {
	mode: Types.ModeId, -- выбранный (до конца лобби — «Каждый сам за себя»)
	options: { Types.ModeId }, -- варианты голосования
	counts: { number }, -- голоса по вариантам
	myVote: Types.ModeId?,
	humans: number, -- игроков в матче (один — выбор сложности)
	solo: boolean,
	difficulty: Types.BotLevel?,
	paused: boolean,
	fast: boolean,
}

-- Таблица, которую сервер шлёт при смене фазы и состава держав.
export type Info = {
	kind: "info",
	phase: Types.Phase,
	phaseLeft: number, -- секунд до конца фазы выбора
	time: number, -- секунд с начала игры
	myNation: number?, -- держава этого игрока (nil — зритель)
	nations: { NationInfo },
	cities: { number }?, -- клетки городов (владелец — по сетке)
	buildings: { Types.Building }?, -- все здания и уровни городов (§6.9)
	matchId: number?, -- новый матч — клиент сбрасывает состояние
	targetNations: number?,
	timeLimit: number?, -- лимит времени матча, с
	result: Types.MatchResult?, -- итог (фаза Over)
	mode: ModeInfo?,
	mapId: string?, -- карта матча (§5.2): другая — клиент загружает её заново
	mapVote: MapVoteInfo?, -- голосование за карту на экране итогов
	flood: { step: number, nextIn: number }?, -- «Потоп» (§5.3): ступень воды и секунд (часы матча) до следующей
	server: ServerInfo?, -- частный сервер (§5.4)
}

export type ServerInfo = { settings: ServerSettings.Settings, isOwner: boolean }

-- Профиль игрока (§11.2, этап 9а): сообщение profile от сервера.
export type ProfileInfo = {
	kind: "profile",
	level: number,
	xp: number, -- опыта внутри уровня
	need: number, -- до следующего уровня
	medals: number,
	tokens: number,
	matches: number,
	wins: number,
	stock: { [string]: number }, -- бусты в запасе
	passes: { [string]: boolean },
	premium: boolean,
	unlocked: { [string]: boolean }, -- открытые генералы
	used: { [string]: boolean }, -- бусты, взятые в этом матче
	boosts: boolean, -- бусты в этом матче разрешены
	packs: { [string]: boolean }, -- какие наборы можно купить
	reward: { xp: number, medals: number, levels: number }?, -- итог последнего матча
	-- Этап 9б (§11.3)
	crates: number,
	pityLeft: number, -- через сколько ящиков гарантированный джекпот
	season: { tier: number, xp: number, per: number, premium: boolean, left: number? }, -- left nil — без срока
	weekly: { offer: { stock: { [string]: number }, crates: number, tokens: number }, left: number },
	dailyStreak: number,
}

export type MapVoteInfo = { options: { string }, counts: { number }, myVote: string? }

-- Договоры (§8.1) глазами клиента: сообщение diplo. Сроки — в секундах игрового времени от момента отправки.
export type DiploTreaty = { kind: Types.TreatyKind, a: number, b: number, left: number?, breakLeft: number? }
export type DiploOffer = { kind: Types.OfferKind, from: number, to: number, province: number?, left: number }
export type DiploMessage = {
	kind: "diplo",
	treaties: { DiploTreaty },
	offers: { DiploOffer },
	traitors: { { id: number, left: number } },
	vassals: { { vassal: number, overlord: number, rebelLeft: number } },
	history: { { kind: string, a: number, b: number, minutes: number? } },
	-- §8.2: торговые соглашения, эмбарго (from → to), Совет держав
	trade: { { a: number, b: number } },
	embargoes: { { from: number, to: number } },
	council: DiploCouncil,
}

export type DiploCouncil = {
	vote: { options: { Types.Resolution }, left: number, tallies: { number } }?,
	active: { { kind: Types.Resolution, left: number, target: number? } },
	nextLeft: number,
}

-- Стабильность (§6.10, этап 7а): своя (средняя, провинции) и повстанцы на карте. Сроки — секунды игрового времени.
export type StabilityMessage = {
	kind: "stability",
	average: number, -- средняя стабильность своих провинций (по клеткам), целое
	lowCells: number, -- клеток с половинным доходом
	ids: { number }, -- свои провинции…
	values: { number }, -- …и их стабильность (целые)
	rebels: { number }, -- провинции повстанцев…
	rebelLeft: { number }, -- …и сколько им осталось
}

-- Технологии (§6.14, этап 7в-1): свои уровни веток и текущее исследование (осталось — игровые секунды).
export type TechMessage = {
	kind: "tech",
	levels: { Army: number, Economy: number, Fleet: number },
	research: { branch: Types.TechBranch, level: number, left: number, total: number }?,
}

-- Генерал (§6.15, этап 7в-2): свой генерал, до готовности способностей Q / E, действующие эффекты (игровые секунды).
export type CommanderMessage = {
	kind: "commander",
	commander: Types.CommanderId,
	left: { number },
	surge: number,
	reveal: number,
}

-- Мир (§6.16, §6.9, этап 7г): шторм, аукцион наёмников, ракеты в полёте, новые нефтяные поля, своя шахта.
-- Сроки — игровые секунды «осталось» на момент сообщения.
export type WorldMessage = {
	kind: "world",
	storm: { cell: number, radius: number, left: number }?,
	auction: { left: number, top: number, topId: number, minBid: number }?,
	missiles: { { cell: number, owner: number, left: number } },
	oilExtra: { number },
	silo: boolean, -- у меня есть работающая шахта
	missileLeft: number, -- до готовности пуска
}

export type ApplyResult = "snapshot" | "delta" | "stats" | "forces" | "wars" | "ships" | "air" | "partial" | "ignored"

export type ClientState = {
	width: number,
	height: number,
	size: number,
	owners: buffer,
	hasSnapshot: boolean,
	snapshotTick: number,
	assembler: Protocol.Assembler,
	nations: { [number]: NationInfo },
	phase: Types.Phase,
	phaseEndsAt: number, -- по часам клиента
	timeAt: number, -- момент (часы клиента), когда пришло time
	time: number,
	myNation: number?,
	stats: Protocol.Stats?,
	cities: { number },
	myForces: Protocol.MyForces?, -- свои войска (только у игрока с державой)
	wars: Protocol.WarsMessage, -- войны и запреты после мира (§6.7а)
	buildings: { [number]: Types.Building }, -- клетка → здание (владелец — по сетке)
	warsAt: number, -- когда пришли wars (часы клиента; для обратных отсчётов)
	bytes: number, -- принято байт с начала (для F3: байт/с)
	matchId: number,
	targetNations: number,
	timeLimit: number,
	result: Types.MatchResult?,
	diplo: DiploMessage, -- договоры (§8.1)
	diploAt: number, -- когда пришло diplo (часы клиента; для обратных отсчётов)
	-- Туман (§6.11, этап 7а): обзор, последний увиденный владелец; fogOff — «Туман выкл» панели разработчика.
	fog: Fog.FogState,
	fogOff: boolean,
	stability: StabilityMessage, -- своя стабильность и повстанцы (§6.10)
	ships: Protocol.ShipsMessage, -- корабли в обзоре, заблокированные порты, своя очередь (§6.12)
	shipsAt: number, -- когда пришли ships (часы клиента; для плавного движения)
	air: Protocol.AirMessage, -- самолёты в обзоре, выведенные из строя здания, своя очередь (§6.13)
	airAt: number,
	rebelSet: { [number]: boolean }, -- провинции повстанцев (из stability)
	tech: TechMessage, -- свои технологии (§6.14)
	commander: CommanderMessage, -- свой генерал и способности (§6.15)
	commanderAt: number, -- когда пришло commander (часы клиента; для обратных отсчётов)
	world: WorldMessage, -- события и ракеты (§6.16, §6.9)
	worldAt: number,
	mode: ModeInfo, -- режим (§5.1)
	mapVote: MapVoteInfo?, -- голосование за карту (§5.2)
	flood: { step: number, nextIn: number }?, -- «Потоп» (§5.3)
	floodAt: number, -- когда пришла ступень (часы клиента)
	server: ServerInfo?, -- частный сервер (§5.4): настройки и владелец ли я
	profile: ProfileInfo?, -- профиль (§11.2)
	rules: Modes.Rules,
	speed: number, -- темп игрового времени: Match.Speed × режим («Блиц» — ×2)
}

local ClientState = {}

function ClientState.emptyMode(): ModeInfo
	return {
		mode = "Ffa",
		options = {},
		counts = {},
		myVote = nil,
		humans = 0,
		solo = false,
		difficulty = nil,
		paused = false,
		fast = false,
	}
end

-- Во сколько раз часы матча идут быстрее реальных: пауза — 0, ×2 «Против ботов» — 2.
function ClientState.clockRate(cs: ClientState): number
	if cs.mode.paused and cs.phase == "Play" then
		return 0
	end
	return if cs.mode.fast then Config.Modes.SoloFastSpeed else 1
end

-- Темп игрового времени относительно часов клиента (обратные отсчёты сроков, перезарядок).
function ClientState.simRate(cs: ClientState): number
	return cs.speed * ClientState.clockRate(cs)
end

-- Время матча сейчас (часы матча, с паузой и ×2).
function ClientState.matchTime(cs: ClientState, now: number): number
	return cs.time + (now - cs.timeAt) * ClientState.clockRate(cs)
end

function ClientState.emptyDiplo(): DiploMessage
	return {
		kind = "diplo",
		treaties = {},
		offers = {},
		traitors = {},
		vassals = {},
		history = {},
		trade = {},
		embargoes = {},
		council = { vote = nil, active = {}, nextLeft = 0 },
	}
end

function ClientState.new(width: number, height: number): ClientState
	return {
		width = width,
		height = height,
		size = width * height,
		owners = buffer.create(width * height * 2),
		hasSnapshot = false,
		snapshotTick = -1,
		assembler = Protocol.newAssembler(),
		nations = {},
		phase = "Waiting",
		phaseEndsAt = 0,
		timeAt = 0,
		time = 0,
		myNation = nil,
		stats = nil,
		cities = {},
		myForces = nil,
		wars = { wars = {}, cooldowns = {} },
		buildings = {},
		matchId = 0,
		targetNations = 0,
		timeLimit = 0,
		result = nil,
		diplo = ClientState.emptyDiplo(),
		diploAt = 0,
		warsAt = 0,
		bytes = 0,
		fog = Fog.new(width, height),
		fogOff = false,
		mode = ClientState.emptyMode(),
		mapVote = nil,
		flood = nil,
		floodAt = 0,
		server = nil,
		profile = nil,
		rules = Modes.rules("Ffa"),
		speed = Config.Match.Speed,
		stability = ClientState.emptyStability(),
		rebelSet = {},
		ships = { ships = {}, blocked = {}, queue = {} },
		shipsAt = 0,
		air = { planes = {}, disabled = {}, queue = {} },
		airAt = 0,
		tech = ClientState.emptyTech(),
		commander = ClientState.emptyCommander(),
		commanderAt = 0,
		world = ClientState.emptyWorld(),
		worldAt = 0,
	}
end

function ClientState.emptyWorld(): WorldMessage
	return { kind = "world", storm = nil, auction = nil, missiles = {}, oilExtra = {}, silo = false, missileLeft = 0 }
end

-- Мир (сообщение world). Возвращает новые нефтяные поля (провинции), которых клиент ещё не знал.
function ClientState.applyWorld(cs: ClientState, msg: any, now: number): { number }
	local fresh: { number } = {}
	if type(msg) ~= "table" or type(msg.missiles) ~= "table" or type(msg.oilExtra) ~= "table" then
		return fresh
	end
	local function num(v: any): number
		return if type(v) == "number" and v == v then v else 0
	end
	local storm = nil
	if type(msg.storm) == "table" then
		storm = { cell = num(msg.storm.cell), radius = num(msg.storm.radius), left = num(msg.storm.left) }
	end
	local auction = nil
	if type(msg.auction) == "table" then
		local a = msg.auction
		auction = { left = num(a.left), top = num(a.top), topId = num(a.topId), minBid = num(a.minBid) }
	end
	local missiles: { { cell: number, owner: number, left: number } } = {}
	for _, mi in msg.missiles do
		if type(mi) == "table" then
			table.insert(missiles, { cell = num(mi.cell), owner = num(mi.owner), left = num(mi.left) })
		end
	end
	local known: { [number]: boolean } = {}
	for _, p in cs.world.oilExtra do
		known[p] = true
	end
	local oil: { number } = {}
	for _, p in msg.oilExtra do
		if type(p) == "number" then
			table.insert(oil, p)
			if not known[p] then
				table.insert(fresh, p)
			end
		end
	end
	cs.world = {
		kind = "world",
		storm = storm,
		auction = auction,
		missiles = missiles,
		oilExtra = oil,
		silo = msg.silo == true,
		missileLeft = num(msg.missileLeft),
	}
	cs.worldAt = now
	return fresh
end

function ClientState.emptyCommander(): CommanderMessage
	return { kind = "commander", commander = "Marshal", left = { 0, 0 }, surge = 0, reveal = 0 }
end

-- Генерал (сообщение commander). Неверное сообщение не меняет состояние.
function ClientState.applyCommander(cs: ClientState, msg: any, now: number)
	if type(msg) ~= "table" or table.find(Types.CommanderIds, msg.commander) == nil or type(msg.left) ~= "table" then
		return
	end
	local function num(v: any): number
		return if type(v) == "number" and v == v then math.max(0, v) else 0
	end
	cs.commander = {
		kind = "commander",
		commander = msg.commander,
		left = { num(msg.left[1]), num(msg.left[2]) },
		surge = num(msg.surge),
		reveal = num(msg.reveal),
	}
	cs.commanderAt = now
end

-- Мой генерал: из сообщения commander в игре, до неё — из info (выбор в лобби).
function ClientState.myCommander(cs: ClientState): Types.CommanderId
	local me = if cs.myNation ~= nil then cs.nations[cs.myNation] else nil
	if cs.phase ~= "Play" and me ~= nil and me.commander ~= nil then
		return me.commander
	end
	return cs.commander.commander
end

-- Сколько секунд осталось «Радарной вспышке» (часы клиента, темп матча).
function ClientState.revealLeft(cs: ClientState, now: number): number
	return math.max(0, cs.commander.reveal - (now - cs.commanderAt) * ClientState.simRate(cs))
end

function ClientState.emptyTech(): TechMessage
	return { kind = "tech", levels = { Army = 0, Economy = 0, Fleet = 0 }, research = nil }
end

function ClientState.emptyStability(): StabilityMessage
	return { kind = "stability", average = 0, lowCells = 0, ids = {}, values = {}, rebels = {}, rebelLeft = {} }
end

function ClientState.ownerAt(cs: ClientState, i: number): number
	return buffer.readu16(cs.owners, i * 2)
end

-- Владелец, которого игрок видит на карте: в тумане — последний увиденный (§6.11).
function ClientState.knownOwnerAt(cs: ClientState, i: number): number
	return Fog.knownOwner(cs.fog, i)
end

-- Владельцы клеток для рисования карты (последние увиденные).
function ClientState.knownOwners(cs: ClientState): buffer
	return cs.fog.known
end

-- Индекс цвета державы (1..24) или 0, если цвета ещё нет.
function ClientState.colorIndexOf(cs: ClientState, owner: number): number
	local n = cs.nations[owner]
	return if n ~= nil then n.colorIndex else 0
end

-- Применяет info. Возвращает true, если поменялись цвета держав (нужна полная перерисовка).
-- Новый матч (другой matchId) — сетка, статистика, войны, здания и войска сбрасываются.
function ClientState.applyInfo(cs: ClientState, info: Info, now: number): boolean
	local colorsChanged = false
	if info.matchId ~= nil and info.matchId ~= cs.matchId then
		if cs.matchId ~= 0 then
			buffer.fill(cs.owners, 0, 0)
			cs.hasSnapshot = false
			cs.snapshotTick = -1
			cs.assembler = Protocol.newAssembler()
			cs.stats = nil
			cs.myForces = nil
			cs.wars = { wars = {}, cooldowns = {} }
			cs.diplo = ClientState.emptyDiplo()
			table.clear(cs.buildings)
			cs.fog = Fog.new(cs.width, cs.height)
			cs.stability = ClientState.emptyStability()
			cs.rebelSet = {}
			cs.ships = { ships = {}, blocked = {}, queue = {} }
			cs.air = { planes = {}, disabled = {}, queue = {} }
			cs.tech = ClientState.emptyTech()
			cs.commander = ClientState.emptyCommander()
			cs.world = ClientState.emptyWorld()
			colorsChanged = true
		end
		cs.matchId = info.matchId
	end
	cs.targetNations = info.targetNations or cs.targetNations
	cs.timeLimit = info.timeLimit or cs.timeLimit
	cs.mapVote = info.mapVote
	cs.flood = info.flood
	cs.server = info.server
	cs.floodAt = now
	local mode = info.mode
	if mode ~= nil then
		cs.mode = mode
		cs.rules = Modes.rules(mode.mode)
		cs.speed = Config.Match.Speed * cs.rules.speed
		-- «Мгла» прячет чужие границы; до игры туман «видно всё», так что смена правила безопасна.
		cs.fog.hideTerritory = cs.rules.hideTerritory
	end
	cs.result = info.result
	local fresh: { [number]: NationInfo } = {}
	for _, n in info.nations do
		local old = cs.nations[n.id]
		if old == nil or old.colorIndex ~= n.colorIndex then
			colorsChanged = true
		end
		fresh[n.id] = n
	end
	cs.nations = fresh
	cs.phase = info.phase
	cs.phaseEndsAt = now + info.phaseLeft
	cs.time = info.time
	cs.timeAt = now
	cs.myNation = info.myNation
	if info.cities ~= nil then
		cs.cities = info.cities
	end
	if info.buildings ~= nil then
		table.clear(cs.buildings)
		ClientState.applyBuildings(cs, info.buildings)
	end
	return colorsChanged
end

-- Применяет бинарное сообщение. Возвращает, что это было, и изменённые клетки (для дельты).
function ClientState.applyBuffer(cs: ClientState, b: buffer): (ApplyResult, { number }?)
	local kind = Protocol.kind(b)
	cs.bytes += buffer.len(b)
	if kind == Protocol.FORCES then
		cs.myForces = Protocol.decodeForces(b)
		return "forces", nil
	end
	if kind == Protocol.WARS then
		cs.wars = Protocol.decodeWars(b)
		return "wars", nil
	end
	if kind == Protocol.SHIPS then
		cs.ships = Protocol.decodeShips(b)
		return "ships", nil
	end
	if kind == Protocol.AIR then
		cs.air = Protocol.decodeAir(b)
		return "air", nil
	end
	if kind == Protocol.SNAPSHOT then
		local owners = Protocol.assemble(cs.assembler, Protocol.decodeSnapshotPart(b), cs.size)
		if owners == nil then
			return "partial", nil
		end
		cs.owners = owners
		cs.hasSnapshot = true
		cs.snapshotTick = cs.assembler.tick
		if cs.fog.all then
			buffer.copy(cs.fog.known, 0, owners, 0, cs.size * 2)
		end
		return "snapshot", nil
	elseif kind == Protocol.DELTA then
		local d = Protocol.decodeDelta(b, cs.size)
		if not cs.hasSnapshot or d.tick <= cs.snapshotTick then
			return "ignored", nil -- изменения уже вошли в снимок
		end
		for k, i in d.cells do
			buffer.writeu16(cs.owners, i * 2, d.owners[k])
		end
		-- В тумане видны только изменения в обзоре (§6.11): их и возвращаем для перерисовки.
		return "delta", Fog.applyDelta(cs.fog, cs.owners, d.cells)
	elseif kind == Protocol.STATS then
		cs.stats = Protocol.decodeStats(b)
		return "stats", nil
	end
	return "ignored", nil
end

-- Статистика державы из последнего сообщения STATS.
function ClientState.statsOf(cs: ClientState, nationId: number): Protocol.NationStats?
	local s = cs.stats
	if s == nil then
		return nil
	end
	for _, n in s.nations do
		if n.id == nationId then
			return n
		end
	end
	return nil
end

-- Война между a и b (в мобилизации или идущая) или nil.
function ClientState.warBetween(cs: ClientState, a: number, b: number): Protocol.WarStats?
	for _, war in cs.wars.wars do
		if (war.a == a and war.b == b) or (war.a == b and war.b == a) then
			return war
		end
	end
	return nil
end

-- Войны державы.
function ClientState.warsOf(cs: ClientState, nation: number): { Protocol.WarStats }
	local out: { Protocol.WarStats } = {}
	for _, war in cs.wars.wars do
		if war.a == nation or war.b == nation then
			table.insert(out, war)
		end
	end
	return out
end

-- Сколько секунд (на момент прихода сообщения) a и b ещё не могут объявить друг другу войну.
function ClientState.cooldownBetween(cs: ClientState, a: number, b: number): number
	for _, c in cs.wars.cooldowns do
		if (c.a == a and c.b == b) or (c.a == b and c.b == a) then
			return c.left
		end
	end
	return 0
end

-- Новые здания (сообщение buildings или полный список из info). Неверные записи пропускаются.
function ClientState.applyBuildings(cs: ClientState, list: { any })
	for _, b in list do
		if
			type(b) == "table"
			and type(b.cell) == "number"
			and type(b.kind) == "string"
			and type(b.level) == "number"
		then
			cs.buildings[b.cell] = { kind = b.kind :: Types.BuildingKind, cell = b.cell, level = b.level }
		end
	end
end

-- Уровень города в клетке (1, если не улучшали).
function ClientState.cityLevel(cs: ClientState, cell: number): number
	local b = cs.buildings[cell]
	return if b ~= nil and b.kind == "City" then b.level else 1
end

-- Договоры (сообщение diplo). Неполное сообщение не ломает клиента.
function ClientState.applyDiplo(cs: ClientState, msg: any, now: number)
	if type(msg) ~= "table" then
		return
	end
	cs.diplo = {
		kind = "diplo",
		treaties = if type(msg.treaties) == "table" then msg.treaties else {},
		offers = if type(msg.offers) == "table" then msg.offers else {},
		traitors = if type(msg.traitors) == "table" then msg.traitors else {},
		vassals = if type(msg.vassals) == "table" then msg.vassals else {},
		history = if type(msg.history) == "table" then msg.history else {},
		trade = if type(msg.trade) == "table" then msg.trade else {},
		embargoes = if type(msg.embargoes) == "table" then msg.embargoes else {},
		council = if type(msg.council) == "table" and type(msg.council.active) == "table"
			then msg.council
			else { vote = nil, active = {}, nextLeft = 0 },
	}
	cs.diploAt = now
end

-- Сколько секунд осталось из «left» сообщения diplo (игровое время идёт в Match.Speed раз быстрее).
function ClientState.diploLeft(cs: ClientState, left: number, now: number, speed: number): number
	return math.max(0, left - (now - cs.diploAt) * speed)
end

function ClientState.treatyBetween(cs: ClientState, a: number, b: number): DiploTreaty?
	for _, t in cs.diplo.treaties do
		if (t.a == a and t.b == b) or (t.a == b and t.b == a) then
			return t
		end
	end
	return nil
end

function ClientState.overlordOf(cs: ClientState, vassal: number): number?
	for _, v in cs.diplo.vassals do
		if v.vassal == vassal then
			return v.overlord
		end
	end
	return nil
end

function ClientState.isTraitor(cs: ClientState, id: number, now: number, speed: number): boolean
	for _, t in cs.diplo.traitors do
		if t.id == id then
			return ClientState.diploLeft(cs, t.left, now, speed) > 0
		end
	end
	return false
end

function ClientState.hasTrade(cs: ClientState, a: number, b: number): boolean
	for _, t in cs.diplo.trade do
		if (t.a == a and t.b == b) or (t.a == b and t.b == a) then
			return true
		end
	end
	return false
end

-- Объявил ли from эмбарго to.
function ClientState.embargoBy(cs: ClientState, from: number, to: number): boolean
	for _, e in cs.diplo.embargoes do
		if e.from == from and e.to == to then
			return true
		end
	end
	return false
end

-- Друзья державы для обзора (§6.11): она сама, союзники, вассалы, сюзерен.
function ClientState.friendsOf(cs: ClientState, id: number): { [number]: boolean }
	local out: { [number]: boolean } = { [id] = true }
	for _, ally in ClientState.alliesOf(cs, id) do
		out[ally] = true
	end
	for _, v in cs.diplo.vassals do
		if v.overlord == id then
			out[v.vassal] = true
		elseif v.vassal == id then
			out[v.overlord] = true
		end
	end
	return out
end

-- Что даёт обзор игроку сейчас; nil — видно всё (нет своей живой державы, не фаза игры, туман выключен).
function ClientState.fogSources(cs: ClientState): Fog.Sources?
	local me = cs.myNation
	local n = if me ~= nil then cs.nations[me] else nil
	if
		me == nil
		or n == nil
		or not n.alive
		or cs.phase ~= "Play"
		or not Config.Fog.Enabled
		or not cs.rules.fog
		or cs.fogOff
	then
		return nil
	end
	-- Радарная вспышка Разведчика (§6.15): пока идёт — видно всё.
	if ClientState.revealLeft(cs, os.clock()) > 0 then
		return nil
	end
	local friends = ClientState.friendsOf(cs, me)
	local fronts: { { mine: number, other: number } } = {}
	local stats = cs.stats
	if stats ~= nil then
		for _, a in stats.attacks do
			if a.target ~= 0 then
				if friends[a.attacker] then
					table.insert(fronts, { mine = a.attacker, other = a.target })
				end
				if friends[a.target] then
					table.insert(fronts, { mine = a.target, other = a.attacker })
				end
			end
		end
	end
	local radars: { number } = {}
	local ports: { number } = {}
	local commander = cs.commander.commander
	for cell, b in cs.buildings do
		if b.kind == "Radar" and friends[ClientState.ownerAt(cs, cell)] then
			table.insert(radars, cell)
		elseif b.kind == "Port" and commander == "Admiral" and ClientState.ownerAt(cs, cell) == me then
			table.insert(ports, cell) -- Адмирал (§6.15): обзор вокруг своих портов больше
		end
	end
	local ships: { number } = {}
	for _, s in cs.ships.ships do
		if friends[s.owner] then
			table.insert(ships, math.floor(s.y) * cs.width + math.floor(s.x))
		end
	end
	local planes: { number } = {}
	for _, p in cs.air.planes do
		if friends[p.owner] then
			table.insert(planes, math.floor(p.y) * cs.width + math.floor(p.x))
		end
	end
	return {
		friends = friends,
		fronts = fronts,
		radars = radars,
		ships = ships,
		planes = planes,
		ports = ports,
		-- Разведчик (§6.15) и «Мгла» (§5.1).
		visionMul = (if commander == "Scout" then Config.Commanders.VisionMul else 1) * cs.rules.visionMul,
	}
end

-- Пересчитать обзор. Возвращает: перерисовать всё (сменился режим «туман / видно всё») и клетки,
-- у которых сменилась видимость или известный владелец.
function ClientState.refreshFog(cs: ClientState): (boolean, { number })
	if not cs.hasSnapshot then
		return false, {}
	end
	local sources = ClientState.fogSources(cs)
	if sources == nil then
		return Fog.revealAll(cs.fog, cs.owners), {}
	end
	return Fog.compute(cs.fog, cs.owners, sources)
end

-- Стабильность (сообщение stability). Возвращает провинции, где появились или ушли повстанцы (перерисовать).
function ClientState.applyStability(cs: ClientState, msg: any): { number }
	local changed: { number } = {}
	if type(msg) ~= "table" or type(msg.ids) ~= "table" or type(msg.values) ~= "table" then
		return changed
	end
	local rebels = if type(msg.rebels) == "table" then msg.rebels else {}
	cs.stability = {
		kind = "stability",
		average = if type(msg.average) == "number" then msg.average else 0,
		lowCells = if type(msg.lowCells) == "number" then msg.lowCells else 0,
		ids = msg.ids,
		values = msg.values,
		rebels = rebels,
		rebelLeft = if type(msg.rebelLeft) == "table" then msg.rebelLeft else {},
	}
	local fresh: { [number]: boolean } = {}
	for _, p in rebels do
		if type(p) == "number" then
			fresh[p] = true
			if not cs.rebelSet[p] then
				table.insert(changed, p)
			end
		end
	end
	for p in cs.rebelSet do
		if not fresh[p] then
			table.insert(changed, p)
		end
	end
	cs.rebelSet = fresh
	return changed
end

-- Технологии (сообщение tech). Неверное сообщение не меняет состояние.
function ClientState.applyTech(cs: ClientState, msg: any)
	if type(msg) ~= "table" or type(msg.levels) ~= "table" then
		return
	end
	local function lvl(v: any): number
		return if type(v) == "number" then math.clamp(math.floor(v), 0, #Config.Tech.Cost) else 0
	end
	local r = msg.research
	local research = nil
	if
		type(r) == "table"
		and (r.branch == "Army" or r.branch == "Economy" or r.branch == "Fleet")
		and type(r.level) == "number"
		and type(r.left) == "number"
		and type(r.total) == "number"
	then
		research = { branch = r.branch, level = r.level, left = r.left, total = r.total }
	end
	cs.tech = {
		kind = "tech",
		levels = { Army = lvl(msg.levels.Army), Economy = lvl(msg.levels.Economy), Fleet = lvl(msg.levels.Fleet) },
		research = research,
	}
end

-- Выведено ли здание в клетке из строя налётом (§6.13).
function ClientState.isDisabled(cs: ClientState, cell: number): boolean
	for _, d in cs.air.disabled do
		if d.cell == cell then
			return true
		end
	end
	return false
end

-- Заблокирован ли порт в клетке (§6.12).
function ClientState.isBlocked(cs: ClientState, cell: number): boolean
	return table.find(cs.ships.blocked, cell) ~= nil
end

-- Стабильность своей провинции (nil — не своя).
function ClientState.stabilityOf(cs: ClientState, province: number): number?
	local k = table.find(cs.stability.ids, province)
	return if k ~= nil then cs.stability.values[k] else nil
end

function ClientState.alliesOf(cs: ClientState, id: number): { number }
	local out: { number } = {}
	for _, t in cs.diplo.treaties do
		if t.kind == "alliance" then
			if t.a == id then
				table.insert(out, t.b)
			elseif t.b == id then
				table.insert(out, t.a)
			end
		end
	end
	return out
end

return table.freeze(ClientState)
