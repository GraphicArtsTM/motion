--!strict
--[[
	MatchService — связь симуляции матча (Shared.MatchSim) с Roblox:
	- игроки входят и выходят, получают державы; первый игрок открывает лобби;
	- цикл матча: лобби → выбор старта → игра → результаты → новый матч на той же карте (этап 4в);
	- намерения клиентов: лимит запросов → разбор (Intents) → MatchSim.applyIntent;
	- тик 10 Гц на Heartbeat с фиксированным шагом;
	- рассылка: info (таблица) при смене фазы и держав, снимок сетки частями (начало игры, опоздавшие),
	  дельты изменений каждый тик (только изменённые клетки), Config.Net.StatsHz раз в секунду — статистика
	  (державы, фронты), войны и запреты после мира всем, войска с очередью найма — каждому игроку.
	Всё идёт по одному RemoteEvent ReplicatedStorage.Remotes.Match, поэтому порядок сообщений сохраняется.
	§15л ч.3 — роль сервера (Places.role): «hub» — главное меню без матча (игроки не получают держав, лобби не
	начинается; список матчей из ServerList и переход «В БОЙ»), «match» — сервер матча (пишет о себе в ServerList,
	«Главное меню» — переход в хаб), «combined» — как раньше (меню поверх матча).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Analytics = require(Shared:WaitForChild("Analytics"))
local Arsenal = require(Shared:WaitForChild("Arsenal"))
local Buildings = require(Shared:WaitForChild("Buildings"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Config = require(Shared:WaitForChild("Config"))
local DevTools = require(Shared:WaitForChild("DevTools"))
local Grid = require(Shared:WaitForChild("Grid"))
local Intents = require(Shared:WaitForChild("Intents"))
local Lobbies = require(Shared:WaitForChild("Lobbies"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local MatchSim = require(Shared:WaitForChild("MatchSim"))
local MatchStats = require(Shared:WaitForChild("Net"):WaitForChild("MatchStats"))
local Modes = require(Shared:WaitForChild("Modes"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local RateLimiter = require(Shared:WaitForChild("RateLimiter"))
local ServerSettings = require(Shared:WaitForChild("ServerSettings"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Places = require(Shared:WaitForChild("Places"))
local Profile = require(Shared:WaitForChild("Profile"))
local Quests = require(Shared:WaitForChild("Quests"))
local Shop = require(Shared:WaitForChild("Shop"))

local Services = script.Parent.Parent:WaitForChild("Services")
local ProfileStore = require(Services:WaitForChild("ProfileStore"))
local ShopService = require(Services:WaitForChild("ShopService"))
local Leaders = require(Services:WaitForChild("Leaders"))
local ServerList = require(Services:WaitForChild("ServerList"))
local Telemetry = require(Services:WaitForChild("Telemetry"))
local Types = require(Shared:WaitForChild("Types"))

type MapData = MapDataModule.MapData

local MatchService = {}

function MatchService.start(firstMap: MapData, loadMap: (mapId: string) -> MapData, role: Places.Role)
	local map = firstMap
	local isHub = role == "hub"
	local serverList: ServerList.ServerList? = if role ~= "combined" then ServerList.new() else nil
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local matchEvent = Instance.new("RemoteEvent")
	matchEvent.Name = "Match"
	matchEvent.Parent = remotes
	local intentEvent = Instance.new("RemoteEvent")
	intentEvent.Name = "Intent"
	intentEvent.Parent = remotes
	remotes.Parent = ReplicatedStorage

	local seedRng = Random.new()
	local devMode: Types.ModeId? = nil -- F4 «Режим»: режим следующего матча без голосования
	local devMap: string? = nil -- F4 «Карта»: карта следующего матча без голосования (§5.2)
	-- Частный сервер (§5.4): DataModel.PrivateServerId / PrivateServerOwnerId; в Studio — Config.Dev.PrivateServer.
	local isPrivate = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0)
		or (RunService:IsStudio() and Config.Dev.PrivateServer)
	local ownerId: number? = if game.PrivateServerOwnerId ~= 0 then game.PrivateServerOwnerId else nil
	local settings: ServerSettings.Settings? = if isPrivate then ServerSettings.defaults(map.name) else nil
	-- §15л ч.4 Свой матч по коду: резервный сервер узнаёт, что он «свой», по коду первого игрока (проверка — по
	-- записи в MemoryStore). До проверки о себе в общий список не пишет.
	local privateCode: string? = nil
	local privateState: string = if role == "match" and game.PrivateServerId ~= "" then "pending" else "public"
	-- §15ц Ц2: карта и режим сервера, выбранные первым игроком (строка плейлиста, «Играть одному», «Свой матч»);
	-- сервер держит их и после итогов. soloServer — «одному»: в общий список не пишет, ботам — выбранная сила.
	local serverMap: string? = nil
	local serverMode: Types.ModeId? = nil
	local soloServer = false
	local soloLevel: Types.BotLevel? = nil
	local function newMatch(): MatchSim.Match
		local realMap = (Config.RealMaps :: any)[map.name] :: Types.RealMapParams?
		local match = MatchSim.new(map, seedRng:NextInteger(1, 2 ^ 31 - 1))
		match.settings = settings
		if settings ~= nil and settings.mode ~= nil then
			match.forcedMode = settings.mode
		end
		if serverMode ~= nil then
			match.forcedMode = serverMode
		end
		if devMode ~= nil then
			match.forcedMode = devMode
		end
		-- Режимы (§5.1): варианты голосования по времени сервера (режим недели), F4 — без голосования.
		MatchSim.openVote(match, os.time())
		-- Держав в матче: Dev.Nations (проверка в Studio, например игрок + 3 Генерала) или как у карты.
		match.targetNations = if Config.Dev.Nations > 0
			then Config.Dev.Nations
			elseif settings ~= nil then math.min(settings.nations, ServerSettings.maxNations(map.name))
			elseif realMap ~= nil then realMap.Nations
			else Config.Match.TargetNations
		return match
	end
	local m = newMatch()
	local seed = m.seed
	local startNewMatch: (mapId: string) -> ()
	local startDemo: () -> ()
	local addToMatch: (player: Player) -> ()
	local joined: { [Player]: boolean } = {} -- §15л ч.7: кто нажал «В БОЙ» (или пришёл на сервер матча)
	local demoRunning = false -- идёт показательный бой ботов (хаб; «как раньше», пока все в меню)
	local demoSpeed = 1 -- показательный бой идёт быстрее (Hub.DemoSpeed)
	local travel: (players: { Player }, placeId: number, options: TeleportOptions?) -> TeleportAsyncResult?
	local travelToMatch: (player: Player, serverId: string?) -> ()
	local nationOf: { [Player]: number } = {}
	local limiters: { [Player]: RateLimiter.RateLimiter } = {}

	-- Косметика игроков (§11.4): UserId → то, что видят все. Обновляется при входе и в гардеробе.
	local cosmeticOf: { [number]: Cosmetics.Public } = {}

	local function infoFor(player: Player): ClientState.Info
		local nations: { ClientState.NationInfo } = {}
		for _, n in m.nations do
			table.insert(nations, {
				id = n.id,
				name = n.name,
				nameEn = n.nameEn,
				colorIndex = n.colorIndex,
				capital = n.capital,
				isBot = n.isBot,
				botLevel = n.botLevel,
				personality = n.personality,
				commander = Commanders.of(m.commanders, n.id),
				alive = n.alive,
				team = m.teams[n.id],
				cosmetic = if n.userId ~= nil then cosmeticOf[n.userId] else nil,
				hunt = if m.rules.capitalHunt then m.huntCount[n.id] or 0 else nil,
				huntLeft = if m.huntSince[n.id] ~= nil
					then math.max(0, Config.Modes.CapitalHunt.HoldSec - (m.time - m.huntSince[n.id]))
					else nil,
			})
		end
		local id = nationOf[player]
		return {
			kind = "info",
			phase = m.phase,
			phaseLeft = math.max(0, m.phaseLeft),
			time = m.time,
			myNation = nationOf[player],
			nations = nations,
			matchId = m.seed,
			targetNations = m.targetNations,
			timeLimit = m.rules.timeLimitSec,
			result = m.result,
			mapId = map.name,
			place = role, -- §15л ч.3: хаб, матч или «как раньше»
			demo = demoRunning, -- §15л ч.7: за меню — показательный бой (матча ещё нет)
			tutorialStep = if m.rules.tutorial then m.tutorialStep else nil, -- «Обучение» (§5.5)
			server = if settings ~= nil
				then {
					settings = settings,
					isOwner = ownerId ~= nil and player.UserId == ownerId,
					code = privateCode,
				}
				else nil,
			flood = if m.rules.flood
				then { step = m.flood.step, nextIn = math.max(0, m.flood.nextAt - m.time) }
				else nil,
			mapVote = if m.phase == "Lobby" and #m.mapOptions > 0
				then {
					options = m.mapOptions,
					counts = Modes.mapCounts(m.mapOptions, m.mapVotes),
					myVote = if id ~= nil then m.mapVotes[id] else nil,
				}
				else nil,
			mode = {
				mode = m.mode,
				options = m.modeOptions,
				counts = Modes.counts(m.modeOptions, m.modeVotes),
				myVote = if id ~= nil then m.modeVotes[id] else nil,
				humans = MatchSim.humans(m),
				solo = m.solo,
				difficulty = m.difficulty,
				paused = m.paused,
				fast = m.fast,
			},
			cities = MatchSim.cities(m),
			buildings = Buildings.list(m.buildings),
		}
	end

	-- Договоры (§8.1) — всем, когда что-то поменялось (и новому игроку при входе).
	local diploVersion, diploAt = -1, -math.huge
	local railsVersion, railsAt = -1, -math.huge -- §15ч Ч1
	local infoPhase, infoAt = "", -math.huge
	local function sendDiplo(player: Player?)
		local msg = MatchStats.diplo(m)
		if player ~= nil then
			matchEvent:FireClient(player, msg)
		else
			diploVersion, diploAt = m.diplo.version + m.council.version * 65536, os.clock()
			matchEvent:FireAllClients(msg)
		end
	end

	local function sendInfoAll()
		for _, player in Players:GetPlayers() do
			matchEvent:FireClient(player, infoFor(player))
		end
		sendDiplo(nil)
	end

	local function sendSnapshot(player: Player?)
		for _, part in Protocol.encodeSnapshot(m.tick, m.grid.owner, m.grid.size) do
			if player then
				matchEvent:FireClient(player, part)
			else
				matchEvent:FireAllClients(part)
			end
		end
		-- §15ч Ч1: вместе с сеткой — все железные дороги.
		local rails = MatchSim.railsMessage(m, true)
		if player then
			matchEvent:FireClient(player, rails)
		else
			matchEvent:FireAllClients(rails)
		end
	end

	-- Профиль и магазин (§11.1, §11.2, этап 9а) ---------------------------------------------------------
	local profiles = ProfileStore.new()
	local shop: ShopService.ShopService
	local rewards: { [Player]: { xp: number, medals: number, levels: number } } = {} -- итог последнего матча
	local crateRng = Random.new() -- ящики (§11.3): только сервер

	local function profileMessage(player: Player): { [string]: any }?
		local session = profiles.get(player.UserId)
		if session == nil then
			return nil
		end
		local d = session.data
		local level, into, need = Profile.levelOf(d.xp)
		local passes = shop.passes(player)
		local id = nationOf[player]
		local now = os.time()
		local packs: { [string]: boolean } = {}
		for _, key in Shop.PackKeys do
			packs[key] = Profile.packAvailable(d, key, now)
		end
		local per = Config.Season.XpPerTier
		return {
			kind = "profile",
			level = level,
			xp = into,
			need = need,
			medals = d.medals,
			tokens = d.tokens,
			matches = d.matches,
			wins = d.wins,
			stock = d.stock,
			passes = passes,
			premium = shop.premium(player),
			unlocked = Profile.unlockedCommanders(d, passes.AllCommanders == true),
			used = if id ~= nil then m.boostsUsed[id] or {} else {},
			boosts = m.rules.boosts,
			packs = packs,
			reward = rewards[player],
			-- Этап 9б (§11.3): ящики, пропуск, предложение недели — сроки настоящие (секунды до конца).
			crates = d.crates,
			pityLeft = Config.Crates.Pity - d.pity,
			season = {
				tier = Profile.seasonTier(d),
				xp = d.seasonXp % per,
				per = per,
				premium = d.seasonPremium,
				-- nil — сезон без срока (§11.3).
				left = if Config.Season.EndsUnix > 0 then math.max(0, Config.Season.EndsUnix - now) else nil,
			},
			weekly = {
				offer = (function(): { [string]: any }
					local o = Shop.weeklyOffer(now)
					return Profile.paidReward(
						{ medals = 0, tokens = o.tokens, crates = o.crates, stock = o.stock },
						d.noPaidRandom
					) :: any
				end)(),
				left = Shop.weekLeft(now),
			},
			noPaidRandom = d.noPaidRandom, -- сводная правка ч.4: ящики за Robux здесь не продаются
			dailyStreak = d.dailyStreak,
			-- Задания дня и рейтинг (§11.5).
			quests = (function(): { { [string]: any } }
				Quests.sync(d, Profile.dayOf(now), player.UserId)
				local out: { { [string]: any } } = {}
				for _, q in d.quests do
					local row = Config.Quests.Pool[q.pool]
					table.insert(out, {
						kind = row.kind,
						target = row.target,
						progress = q.progress,
						done = q.done,
						medals = row.medals,
						xp = row.xp,
					})
				end
				return out
			end)(),
			questsBonus = d.questsBonus,
			tutorialDone = d.tutorialDone, -- §15ф Ф1: кнопка «Обучение» в меню
			dayLeft = 86400 - now % 86400,
			elo = d.elo,
			-- §15л ч.6 Арсенал: открытое, взятое в бой, применено ли в этом матче.
			arsenal = {
				owned = d.arsenal,
				loadout = d.loadout,
				commander = d.commander, -- §15ф Ф1: генерал по умолчанию
				used = id ~= nil and m.arsenalUsed[id] == true,
			},
			volume = { sfx = d.sfx, music = d.music }, -- громкости (§13)
			-- Гардероб (§11.4): что открыто, что надето, флаг.
			wardrobe = (function(): { [string]: any }
				local owned: { [string]: boolean } = {}
				for _, raw in Cosmetics.Kinds do
					local kind: Cosmetics.Kind = raw :: any
					for _, it in Cosmetics.list(kind) do
						if Cosmetics.owns(d, kind, it.id) then
							owned[Cosmetics.key(kind, it.id)] = true
						end
					end
				end
				return { owned = owned, equipped = d.equipped, flag = d.flag or Cosmetics.defaultFlag() }
			end)(),
		}
	end
	local function sendProfile(player: Player)
		local msg = profileMessage(player)
		if msg ~= nil then
			matchEvent:FireClient(player, msg)
		end
	end
	-- Перки пассов и открытые генералы игрока — в текущий матч.
	local function applyProfile(player: Player)
		local s0 = profiles.get(player.UserId)
		if s0 ~= nil then
			cosmeticOf[player.UserId] = Cosmetics.public(s0.data, shop.passes(player).Vip == true)
			m.infoDirty = true
		end
		local id = nationOf[player]
		local session = profiles.get(player.UserId)
		if id == nil or session == nil then
			return
		end
		local passes = shop.passes(player)
		MatchSim.setPerks(m, id, Shop.perks(passes))
		MatchSim.setArsenal(m, id, session.data.loadout) -- §15л ч.6: предмет Арсенала в этот матч
		local open = Profile.unlockedCommanders(session.data, passes.AllCommanders == true)
		MatchSim.setUnlocked(m, id, open)
		local chosen = Commanders.of(m.commanders, id)
		if chosen ~= nil and not open[chosen] and m.phase ~= "Play" then
			Commanders.choose(m.commanders, id, "Marshal")
			m.infoDirty = true
		end
		-- §15ф Ф1: генерал из профиля (выбран в Арсенале) — до начала игры.
		local pref = session.data.commander
		if pref ~= nil and open[pref] and m.phase ~= "Play" and Commanders.of(m.commanders, id) ~= pref then
			Commanders.choose(m.commanders, id, pref :: any)
			m.infoDirty = true
		end
	end
	-- Буст из запаса (куплен за Robux) или за жетон (§11.1).
	local function useBoost(player: Player, key: string, pay: string, cell: number?): (boolean, string?)
		local id = nationOf[player]
		local session = profiles.get(player.UserId)
		if id == nil or session == nil then
			return false, "dead"
		end
		local d = session.data
		if pay == "stock" and (d.stock[key] or 0) <= 0 then
			return false, "noStock"
		end
		if pay == "token" and d.tokens <= 0 then
			return false, "noTokens"
		end
		if pay ~= "stock" and pay ~= "token" then
			return false, "target"
		end
		local ok, why = MatchSim.useBoost(m, id, key, cell)
		if not ok then
			return false, why
		end
		if pay == "stock" then
			d.stock[key] -= 1
			if d.stock[key] <= 0 then
				d.stock[key] = nil
			end
		else
			d.tokens -= 1
		end
		sendProfile(player)
		return true, nil
	end
	shop = ShopService.start(profiles, {
		onStock = function(player: Player, key: string)
			local id = nationOf[player]
			-- Купил в бою — сразу в дело (кроме «Авиаудара»: ему нужна цель — останется в запасе).
			if id ~= nil and key ~= "Airstrike" and MatchSim.canBoost(m, id, key) then
				useBoost(player, key, "stock")
			end
		end,
		onChanged = function(player: Player)
			applyProfile(player)
			sendProfile(player)
		end,
	})
	-- Таблицы лидеров (§11.5): всем — когда обновились.
	local leaders = Leaders.start(function(boards: Leaders.Boards)
		matchEvent:FireAllClients({ kind = "leaders", weekly = boards.weekly, duel = boards.duel })
	end)

	-- Итог матча в профили (§11.2): опыт, медали, жетоны за уровни. Один раз на матч.
	local rewardedSeed = 0
	local function giveRewards()
		local result = m.result
		if result == nil or rewardedSeed == m.seed then
			return
		end
		rewardedSeed = m.seed
		local co: { [number]: boolean } = {}
		local coWinners: { number } = result.coWinners or {}
		for _, id in coWinners do
			co[id] = true
		end
		local now = os.time()
		local day = Profile.dayOf(now)
		-- Рейтинг дуэлей (§11.5): только дуэль игроков без ботов; у стороны — средний рейтинг.
		local duelSides: { [number]: { number } }? = nil
		if m.rules.duel and MatchSim.humans(m) == #m.nations then
			local sides: { [number]: { number } } = {}
			for player, id in nationOf do
				local session = profiles.get(player.UserId)
				if session ~= nil then
					local side = m.teams[id] or id
					sides[side] = sides[side] or {}
					table.insert(sides[side], session.data.elo)
				end
			end
			duelSides = sides
		end
		local function avg(list: { number }): number
			local sum = 0
			for _, v in list do
				sum += v
			end
			return sum / math.max(1, #list)
		end
		for player, id in nationOf do
			local session = profiles.get(player.UserId)
			if session ~= nil then
				local place = table.find(result.places, id) or #result.places
				local won = id == result.winner or co[id] == true
				local mul = MatchSim.perksOf(m, id).xpMul
					* (if shop.premium(player) then Config.Profile.PremiumXpMul else 1)
				local levelBefore = Profile.levelOf(session.data.xp)
				local xp, medals =
					Profile.applyMatch(session.data, place, MatchSim.citiesOf(m, id), won, mul, os.time())
				rewards[player] = { xp = xp, medals = medals, levels = Profile.levelOf(session.data.xp) - levelBefore }
				-- Задания дня (§11.5).
				local landPercent = Grid.cellsOf(m.grid, id) / math.max(1, m.grid.capturableCount) * 100
				local outcome =
					{ place = place, won = won, cities = MatchSim.citiesOf(m, id), landPercent = landPercent }
				local done, tokens = Quests.onMatch(session.data, outcome, day, player.UserId, now)
				if #done > 0 or tokens > 0 then
					matchEvent:FireClient(player, { kind = "quests", done = done, tokens = tokens })
				end
				if won then
					leaders.addWin(player.UserId)
				end
				local sides = duelSides
				if sides ~= nil then
					local mySide = m.teams[id] or id
					local mine, other = 0, 0
					for side, list in sides do
						if side == mySide then
							mine = avg(list)
						else
							other = avg(list)
						end
					end
					session.data.elo += Quests.eloDelta(mine, other, if won then 1 else 0)
					leaders.setElo(player.UserId, session.data.elo)
				end
				task.spawn(profiles.save, player.UserId)
				sendProfile(player)
			end
		end
	end

	-- §15л ч.3 Переходы между местами. Профиль сохраняем до перехода (сервер-получатель ждёт блокировку).
	local travelling: { [Player]: number } = {} -- кто уже в пути (os.clock) — повторные нажатия не шлём
	local function travelFailed(player: Player, reason: string?)
		travelling[player] = nil
		if player.Parent ~= nil then
			matchEvent:FireClient(player, { kind = "travel", state = "failed", reason = reason })
		end
	end
	-- Перенести players в placeId; options nil — Roblox сам выберет сервер. Вернёт результат или nil.
	function travel(players: { Player }, placeId: number, options: TeleportOptions?): TeleportAsyncResult?
		local going: { Player } = {}
		for _, player in players do
			if player.Parent ~= nil then
				table.insert(going, player)
				travelling[player] = os.clock()
				matchEvent:FireClient(player, { kind = "travel", state = "going" })
			end
		end
		if #going == 0 then
			return nil
		end
		for _, player in going do
			profiles.save(player.UserId)
		end
		local ok, result = pcall(function(): TeleportAsyncResult
			return TeleportService:TeleportAsync(placeId, going, options)
		end)
		if not ok then
			warn("[Frontir] переход не удался:", result)
			for _, player in going do
				travelFailed(player)
			end
			return nil
		end
		return result
	end
	TeleportService.TeleportInitFailed:Connect(function(player: Player, _result: Enum.TeleportResult, message: string)
		warn("[Frontir] переход не удался:", message)
		travelFailed(player)
	end)

	-- Хаб: список матчей (раз в ListRefreshSec всем) и быстрый вход.
	local matches: { Places.Entry } = {}
	-- «В БОЙ» / «Новое лобби» без свободного матча: кто нажал за BatchSec, едут вместе на один новый сервер пары.
	local batches: { [string]: { Player } } = {}
	-- §15ц Ц2: «как раньше» (Studio, частный сервер) — один сервер, один матч: другой строкой можно перезапустить
	-- матч, только если на нём нет других вступивших игроков.
	local function freeFor(player: Player): boolean
		if demoRunning then
			return true
		end
		for p in joined do
			if p ~= player and p.Parent ~= nil then
				return false
			end
		end
		return true
	end
	local function hereEntry(): Places.Entry?
		if demoRunning then
			return nil
		end
		local humans = 0
		for p in joined do
			if p.Parent ~= nil then
				humans += 1
			end
		end
		local mode: string = if m.phase == "Waiting" or m.phase == "Lobby" then MatchSim.lobbyMode(m) else m.mode
		local max: number = Players.MaxPlayers
		local entry: Places.Entry = {
			id = "here",
			psid = "",
			map = map.name,
			mode = mode,
			phase = m.phase :: string,
			players = humans,
			max = max,
			left = if m.phase == "Play" then math.max(0, math.floor(m.time)) else math.max(0, math.ceil(m.phaseLeft)),
			at = os.time(),
		}
		return entry
	end
	local function rowsFor(player: Player): { Lobbies.Row }
		local slots = Lobbies.slots(os.time())
		if isHub then
			return Lobbies.board(matches, slots, Config.Lobbies.Rows)
		end
		local here = hereEntry()
		local rows = Lobbies.board(if here ~= nil then { here } else {}, slots, Config.Lobbies.Rows)
		if not freeFor(player) then
			for _, r in rows do
				if r.id == "" then
					r.action = "busy"
				end
			end
		end
		return rows
	end
	local function sendServers(player: Player?)
		local list = if player ~= nil then { player } else Players:GetPlayers()
		for _, p in list do
			matchEvent:FireClient(p, { kind = "servers", list = rowsFor(p) })
		end
	end
	function travelToMatch(player: Player, serverId: string?, req: Lobbies.Request?)
		local since = travelling[player]
		if since ~= nil and os.clock() - since < Config.Places.RetrySec then
			return
		end
		travelling[player] = os.clock()
		local list = serverList
		local e: Places.Entry? = nil
		if serverId ~= nil then
			for _, x in matches do
				if x.id == serverId and Places.action(x) ~= "full" then
					e = x
				end
			end
			if e == nil then
				travelFailed(player)
				return
			end
		elseif req ~= nil then
			-- Строка плейлиста: открытый сервер той же пары; «одному» — всегда свой новый сервер.
			if not req.solo then
				for _, x in Places.sorted(matches) do
					if x.map == req.map and x.mode == req.mode and Places.action(x) == "join" then
						e = x
						break
					end
				end
			end
		else
			e, req = Lobbies.quick(matches, Lobbies.slots(os.time()))
		end
		task.spawn(function()
			if e ~= nil and list ~= nil then
				local options = Instance.new("TeleportOptions")
				if e.psid ~= "" then
					local code = list.codeOf(e.psid)
					if code == nil then
						travelFailed(player)
						return
					end
					options.ReservedServerAccessCode = code
				else
					options.ServerInstanceId = e.id
				end
				travel({ player }, Config.Places.Match, options)
				return
			end
			-- Свободного матча нет — новый резервный сервер пары (карта и режим — в данных перехода); кто нажал за
			-- BatchSec, едут вместе. «Одному» — сразу и без попутчиков.
			local lobby = if req ~= nil
				then { map = req.map, mode = req.mode, solo = req.solo, level = req.level }
				else nil
			local key = if req == nil
				then ""
				elseif req.solo then "solo:" .. player.UserId
				else req.map .. "|" .. req.mode
			local group: { Player } = { player }
			if req == nil or not req.solo then
				local waiting = batches[key]
				if waiting ~= nil then
					table.insert(waiting, player)
					matchEvent:FireClient(player, { kind = "travel", state = "going" })
					return
				end
				batches[key] = group
				matchEvent:FireClient(player, { kind = "travel", state = "going" })
				task.wait(Config.Places.BatchSec)
				batches[key] = nil
			end
			local options = Instance.new("TeleportOptions")
			options.ShouldReserveServer = true
			if lobby ~= nil then
				options:SetTeleportData({ lobby = lobby })
			end
			local result = travel(group, Config.Places.Match, options)
			if result ~= nil and list ~= nil and (req == nil or not req.solo) then
				list.remember(result.PrivateServerId, result.ReservedServerAccessCode)
			end
		end)
	end
	-- §15л ч.4 Свой матч: новый резервный сервер, код — в MemoryStore (код → сервер и владелец).
	local codeRng = Random.new()
	local function busy(player: Player): boolean
		local since = travelling[player]
		return since ~= nil and os.clock() - since < Config.Places.RetrySec
	end
	local function privateCreate(player: Player, req: Lobbies.Request?)
		local list = serverList
		if list == nil or busy(player) then
			return
		end
		travelling[player] = os.clock()
		task.spawn(function()
			local code = Places.newCode(function(n: number): number
				return codeRng:NextInteger(1, n)
			end)
			if list.findPrivate(code) ~= nil then -- редкое совпадение — ещё раз
				code = Places.newCode(function(n: number): number
					return codeRng:NextInteger(1, n)
				end)
			end
			local options = Instance.new("TeleportOptions")
			options.ShouldReserveServer = true
			options:SetTeleportData({
				code = code,
				lobby = if req ~= nil then { map = req.map, mode = req.mode } else nil,
			})
			local result = travel({ player }, Config.Places.Match, options)
			if result ~= nil then
				list.savePrivate(code, {
					access = result.ReservedServerAccessCode,
					psid = result.PrivateServerId,
					owner = player.UserId,
				})
			end
		end)
	end
	local function privateJoin(player: Player, raw: any)
		local list = serverList
		if list == nil or busy(player) then
			return
		end
		local code = Places.normalizeCode(raw)
		if code == nil then
			travelFailed(player, "badCode")
			return
		end
		travelling[player] = os.clock()
		task.spawn(function()
			local rec = list.findPrivate(code)
			if rec == nil then
				travelFailed(player, "badCode")
				return
			end
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = rec.access
			options:SetTeleportData({ code = code })
			travel({ player }, Config.Places.Match, options)
		end)
	end
	-- Сервер матча: пришёл игрок с кодом — проверить код и стать «своим матчем» (владелец — создатель кода).
	local function checkPrivate(player: Player)
		if privateState ~= "pending" or serverList == nil then
			return
		end
		local list = serverList
		local okJoin, join = pcall(function(): any
			return player:GetJoinData()
		end)
		local data = if okJoin and type(join) == "table" then join.TeleportData else nil
		local code = if type(data) == "table" then Places.normalizeCode(data.code) else nil
		if code == nil then
			privateState = "public" -- обычный резервный сервер (быстрый вход)
			return
		end
		privateState = "checking"
		task.spawn(function()
			for _ = 1, Config.Places.VerifyTries do
				local rec = list.findPrivate(code)
				if rec ~= nil and rec.psid == game.PrivateServerId then
					privateState = "private"
					privateCode = code
					isPrivate = true
					ownerId = rec.owner
					local s0 = ServerSettings.defaults(map.name)
					-- §15ц Ц2: карта и режим, выбранные при создании, — настройки по умолчанию своего матча.
					if serverMap ~= nil then
						s0.map = serverMap
						s0.mode = serverMode
					end
					settings = s0
					if m.phase == "Waiting" or m.phase == "Lobby" then
						m.settings = s0
						m.targetNations = math.min(s0.nations, ServerSettings.maxNations(map.name))
						if s0.mode ~= nil then
							m.forcedMode = s0.mode
						end
					end
					m.infoDirty = true
					print(
						"[Frontir] свой матч, код " .. code .. ", владелец " .. tostring(rec.owner)
					)
					return
				end
				task.wait(Config.Places.VerifyWaitSec)
			end
			privateState = "public"
		end)
	end

	if isHub and serverList ~= nil then
		local list = serverList
		task.spawn(function()
			while true do
				matches = list.read()
				sendServers(nil)
				task.wait(Config.Places.ListRefreshSec)
			end
		end)
	elseif role == "combined" then
		task.spawn(function()
			while true do
				task.wait(Config.Places.ListRefreshSec)
				sendServers(nil)
			end
		end)
	end

	-- Сервер матча: раз в PublishSec — о себе в список (режим в лобби — лидер голосования).
	if role == "match" and serverList ~= nil then
		local list = serverList
		task.spawn(function()
			while true do
				-- Свой матч (§15л ч.4) и сервер, который ещё проверяет код, в общий список не пишут.
				if privateState ~= "public" or soloServer then
					task.wait(Config.Places.PublishSec)
					continue
				end
				local mode: string = m.mode
				if m.phase == "Lobby" or m.phase == "Waiting" then
					mode = Modes.tally(m.modeOptions, m.modeVotes)
				end
				list.publish({
					id = game.JobId,
					psid = game.PrivateServerId,
					map = map.name,
					mode = mode,
					phase = m.phase,
					players = #Players:GetPlayers(),
					max = Players.MaxPlayers,
					left = if m.phase == "Play"
						then math.max(0, math.floor(m.time))
						else math.max(0, math.ceil(m.phaseLeft)),
					at = os.time(),
				})
				task.wait(Config.Places.PublishSec)
			end
		end)
		game:BindToClose(function()
			list.remove()
		end)
	end

	-- §15л ч.7: игрок вступает в текущий матч (лобби начинается с первым; опоздавший в игре — зритель).
	function addToMatch(player: Player)
		if nationOf[player] ~= nil then
			return
		end
		if m.phase == "Waiting" then
			MatchSim.startLobby(m)
		end
		local id = MatchSim.addPlayer(m, player.UserId, player.DisplayName)
		if id ~= nil then
			nationOf[player] = id
		end
		-- Против ботов (§5.1): пришёл ещё кто-то — паузы и ×2 больше нет.
		if m.solo then
			m.solo, m.paused, m.fast = false, false, false
		end
		m.infoDirty = true
	end
	-- §15ц Ц2: матч с выбранной картой и режимом (первый игрок сервера матча; строка списка в «как раньше»).
	local function startRequested(req: Lobbies.Request)
		serverMap, serverMode = req.map, req.mode
		soloServer, soloLevel = req.solo, req.level
		startNewMatch(req.map)
	end
	-- После того как игрок вступил: «одному» — выбранная сила ботов и короткое лобби.
	local function soloSetup()
		if soloServer and (m.phase == "Waiting" or m.phase == "Lobby") and MatchSim.humans(m) == 1 then
			m.difficulty = soloLevel or Config.Lobbies.SoloLevel :: Types.BotLevel
			m.phaseLeft = math.min(m.phaseLeft, Config.Lobbies.SoloLobbySec)
			m.infoDirty = true
		end
	end
	local requestTaken = false
	local function joinRequest(player: Player): Lobbies.Request?
		local okJoin, join = pcall(function(): any
			return player:GetJoinData()
		end)
		local data = if okJoin and type(join) == "table" then join.TeleportData else nil
		return if type(data) == "table" then Lobbies.request(data.lobby) else nil
	end

	-- «В БОЙ» на сервере «как раньше»: идёт показательный бой — настоящий матч с лобби; иначе — в текущий.
	local function joinMatch(player: Player)
		if nationOf[player] ~= nil then
			return
		end
		joined[player] = true
		if demoRunning then
			startNewMatch(map.name) -- держав получают все вступившие (joined)
		else
			addToMatch(player)
			applyProfile(player)
			matchEvent:FireClient(player, infoFor(player))
			sendDiplo(player)
			if m.phase == "Play" then
				sendSnapshot(player)
			end
		end
		-- Новичок один в лобби — голос за «Обучение» стоит сам (§5.5), можно сменить.
		local session = profiles.get(player.UserId)
		local id = nationOf[player]
		if
			session ~= nil
			and id ~= nil
			and not session.data.tutorialDone
			and m.phase == "Lobby"
			and table.find(m.modeOptions, "Tutorial") ~= nil
		then
			m.modeVotes[id] = "Tutorial"
			m.infoDirty = true
		end
		sendProfile(player)
	end

	local function onPlayerAdded(player: Player)
		if nationOf[player] ~= nil then
			return
		end
		if isPrivate and ownerId == nil then
			ownerId = player.UserId -- Studio (Dev.PrivateServer): владелец — первый вошедший
		end
		limiters[player] = RateLimiter.new(Config.Sim.MaxIntentsPerSecond, Config.Sim.MaxIntentsPerSecond, os.clock())
		-- §15л ч.7: на сервере матча (пришли из хаба «В БОЙ») — сразу в матч; в хабе и «как раньше» — в меню,
		-- держава — только по «В БОЙ» (намерение joinMatch).
		if role == "match" then
			-- §15ц Ц2: первый игрок нового сервера приносит карту и режим (строка плейлиста, «одному», свой матч).
			if not requestTaken then
				requestTaken = true
				local req = joinRequest(player)
				if req ~= nil and (m.phase == "Waiting" or m.phase == "Lobby") then
					if req.solo then
						privateState = "solo" -- свой сервер одного игрока: не «свой матч» и не в общий список
					end
					startRequested(req)
				end
			end
			joined[player] = true
			addToMatch(player)
			soloSetup()
		end
		matchEvent:FireClient(player, infoFor(player))
		sendDiplo(player)
		if m.phase == "Play" then
			sendSnapshot(player) -- опоздавший — зритель: видит всю карту
		end
		if isHub or role == "combined" then
			sendServers(player)
		end
		checkPrivate(player)
		-- Профиль грузится в фоне (DataStore может ждать блокировку сессии).
		task.spawn(function()
			local session = profiles.load(player.UserId)
			shop.loadPasses(player)
			session.data.noPaidRandom = shop.noPaidRandom(player) ~= false
			if player.Parent ~= nil then
				applyProfile(player)
				-- Новичок один в лобби — голос за «Обучение» стоит сам (§5.5), можно сменить.
				local id = nationOf[player]
				if
					id ~= nil
					and not session.data.tutorialDone
					and (m.phase == "Lobby" or m.phase == "Waiting")
					and table.find(m.modeOptions, "Tutorial") ~= nil
				then
					m.modeVotes[id] = "Tutorial"
					m.infoDirty = true
				end
				-- Ежедневная награда за вход (§11.3).
				local streak, reward = Profile.claimDaily(session.data, Profile.dayOf(os.time()))
				if streak ~= nil then
					matchEvent:FireClient(player, { kind = "daily", streak = streak, reward = reward })
				end
				sendProfile(player)
				local boards = leaders.current()
				matchEvent:FireClient(player, { kind = "leaders", weekly = boards.weekly, duel = boards.duel })
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		local id = nationOf[player]
		if id ~= nil then
			-- Аналитика (§15, этап 10в): где и когда игрок вышел.
			for _, record in Analytics.leave(m, id) do
				Telemetry.custom(player, record)
			end
			MatchSim.removePlayer(m, id)
		end
		nationOf[player] = nil
		joined[player] = nil
		limiters[player] = nil
		travelling[player] = nil
		rewards[player] = nil
		shop.forget(player)
		task.spawn(profiles.release, player.UserId)
		cosmeticOf[player.UserId] = nil
	end)

	intentEvent.OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
		local limiter = limiters[player]
		if limiter == nil or not RateLimiter.allow(limiter, os.clock()) then
			return -- спам намерениями молча отбрасываем (кик за спам — этап 10)
		end
		local id = nationOf[player]
		-- Клиент загрузил карту заново (смена карты, §5.2) — шлём ему состояние заново.
		-- Настройки частного сервера (§5.4): только владелец, только значения из списков; в лобби — сразу.
		if kind == "settings" then
			if settings == nil or ownerId == nil or player.UserId ~= ownerId then
				matchEvent:FireClient(player, { kind = "rejected", reason = "notOwner", intent = "settings" })
				return
			end
			local parsed, why = ServerSettings.parse(payload, map.name)
			if parsed == nil then
				matchEvent:FireClient(player, { kind = "rejected", reason = why or "?", intent = "settings" })
				return
			end
			settings = parsed
			if m.phase == "Waiting" or m.phase == "Lobby" then
				startNewMatch(parsed.map or map.name)
			else
				sendInfoAll()
			end
			return
		end
		-- Буст магазина (§11.1): из запаса (куплен за Robux) или за жетон штаба.
		if kind == "boost" then
			local key = if type(payload) == "table" then payload.key else nil
			local pay = if type(payload) == "table" then payload.pay else nil
			local cell = if type(payload) == "table" then payload.cell else nil
			if not Shop.isBoost(key) or type(pay) ~= "string" then
				return
			end
			if cell ~= nil and (type(cell) ~= "number" or cell ~= math.floor(cell) or cell < 0) then
				return
			end
			local ok, why = useBoost(player, key, pay, cell)
			if not ok then
				matchEvent:FireClient(player, { kind = "rejected", reason = why or "?", intent = "boost" })
			end
			return
		end
		-- §15л ч.6 Арсенал: купить за медали, взять в бой (профиль), применить (матч).
		if kind == "arsenalBuy" or kind == "arsenalEquip" then
			local session = profiles.get(player.UserId)
			if session == nil or type(payload) ~= "table" then
				return
			end
			local d = session.data
			local ok, why
			if kind == "arsenalBuy" then
				ok, why = Arsenal.buy(d, payload.key, (Profile.levelOf(d.xp)))
			else
				ok, why = Arsenal.equip(d, payload.key)
			end
			if not ok then
				matchEvent:FireClient(player, { kind = "rejected", reason = why or "?", intent = kind })
				return
			end
			applyProfile(player)
			sendProfile(player)
			return
		end
		if kind == "arsenalUse" then
			local cell = if type(payload) == "table" then payload.cell else nil
			if cell ~= nil and (type(cell) ~= "number" or cell ~= math.floor(cell) or cell < 0) then
				return
			end
			if id == nil then
				return
			end
			local ok, why = MatchSim.useArsenal(m, id, cell)
			if not ok then
				matchEvent:FireClient(player, { kind = "rejected", reason = why or "?", intent = kind })
				return
			end
			sendProfile(player)
			return
		end
		-- Гардероб (§11.4): купить за медали, надеть, флаг из готовых частей.
		if kind == "buyCosmetic" or kind == "equip" or kind == "flag" then
			local session = profiles.get(player.UserId)
			if session == nil or type(payload) ~= "table" then
				return
			end
			local ok, why = false, "target" :: string?
			local cosKind = payload.kind
			if kind == "flag" then
				ok, why = Cosmetics.setFlag(session.data, payload.flag)
			elseif table.find(Cosmetics.Kinds, cosKind) ~= nil then
				local itemId = payload.id
				if kind == "buyCosmetic" and type(itemId) == "string" then
					ok, why = Cosmetics.buy(session.data, cosKind, itemId)
				elseif kind == "equip" and (itemId == nil or type(itemId) == "string") then
					ok, why = Cosmetics.equip(session.data, cosKind, itemId)
				end
			end
			if not ok then
				matchEvent:FireClient(player, { kind = "rejected", reason = why or "?", intent = kind })
				return
			end
			applyProfile(player)
			sendProfile(player)
			return
		end
		-- Громкости звука и музыки (§13): хранятся в профиле.
		-- §15ф Ф1: генерал по умолчанию (Арсенал) — в профиль; в лобби своего матча — сразу.
		if kind == "prefCommander" then
			local session = profiles.get(player.UserId)
			if session == nil or type(payload) ~= "table" then
				return
			end
			local ok, why =
				Profile.setCommander(session.data, payload.commander, shop.passes(player).AllCommanders == true)
			if not ok then
				matchEvent:FireClient(player, { kind = "rejected", reason = why or "?", intent = kind })
				return
			end
			applyProfile(player)
			sendProfile(player)
			return
		end
		-- §15ф Ф1: «Выйти» из ожидания игроков — держава убирается, игрок снова в меню.
		if kind == "leaveMatch" then
			local id = nationOf[player]
			if id ~= nil and (m.phase == "Waiting" or m.phase == "Lobby") then
				MatchSim.removePlayer(m, id)
				nationOf[player] = nil
				joined[player] = nil
				m.infoDirty = true
				matchEvent:FireClient(player, infoFor(player))
			end
			return
		end
		-- §15ф Ф1: «Обучение» из главного меню — вступить и (один в лобби) сыграть обучение.
		if kind == "playTutorial" then
			if role == "combined" then
				joinMatch(player)
				if (m.phase == "Waiting" or m.phase == "Lobby") and MatchSim.humans(m) == 1 then
					m.forcedMode = "Tutorial"
					m.mode = "Tutorial"
					-- §15ц Ц5б: обучение — одному, ждать некого: короткое лобби, как у «Играть одному».
					m.phaseLeft = math.min(m.phaseLeft, Config.Lobbies.SoloLobbySec)
					m.infoDirty = true
				end
			end
			return
		end
		if kind == "volume" then
			local session = profiles.get(player.UserId)
			if session == nil or type(payload) ~= "table" then
				return
			end
			local ok, why = Profile.setVolumes(session.data, payload.sfx, payload.music)
			if not ok then
				matchEvent:FireClient(player, { kind = "rejected", reason = why or "?", intent = kind })
				return
			end
			sendProfile(player)
			return
		end
		-- Ящик снабжения (§11.3): открывает сервер своим генератором случайных чисел.
		if kind == "openCrate" then
			local session = profiles.get(player.UserId)
			if session == nil then
				return
			end
			local key, unit, reward = Profile.openCrate(session.data, function(n: number): number
				return crateRng:NextInteger(1, n)
			end)
			if key == nil then
				matchEvent:FireClient(player, { kind = "rejected", reason = "noCrates", intent = "openCrate" })
				return
			end
			matchEvent:FireClient(player, { kind = "crate", key = key, unit = unit, reward = reward })
			sendProfile(player)
			return
		end
		if kind == "sync" then
			matchEvent:FireClient(player, infoFor(player))
			sendDiplo(player)
			-- §15ц Ц2: новая сессия клиента (смена карты) — профиль и список матчей заново.
			sendProfile(player)
			if isHub or role == "combined" then
				sendServers(player)
			end
			if m.phase == "Play" then
				sendSnapshot(player)
			end
			return
		end
		-- §15л ч.3: «В БОЙ» в хабе и «Главное меню» на сервере матча — переходы между местами.
		if kind == "play" then
			local server = if type(payload) == "table" and type(payload.server) == "string" then payload.server else nil
			local req = if server == nil then Lobbies.request(payload) else nil
			if isHub then
				travelToMatch(player, server, req)
			elseif role == "combined" then
				-- §15ц Ц2: один сервер — один матч. Своя строка или «В БОЙ» — вступить; другая пара — перезапустить
				-- матч сервера с ней, если на нём нет других вступивших.
				if req == nil then
					joinMatch(player)
				elseif not freeFor(player) then
					matchEvent:FireClient(player, { kind = "travel", state = "failed", reason = "busy" })
				else
					joined[player] = true
					startRequested(req)
					soloSetup()
				end
				sendServers(nil)
			end
			return
		end
		if kind == "joinMatch" then
			if role == "combined" then
				joinMatch(player)
			end
			return
		end
		if kind == "privateCreate" or kind == "privateJoin" then
			if isHub then
				if kind == "privateCreate" then
					privateCreate(player, Lobbies.request(payload))
				else
					privateJoin(player, if type(payload) == "table" then payload.code else nil)
				end
			end
			return
		end
		if kind == "toHub" then
			local since = travelling[player]
			if role == "match" and (since == nil or os.clock() - since >= Config.Places.RetrySec) then
				task.spawn(travel, { player }, Config.Places.Hub, nil)
			end
			return
		end
		if id == nil then
			return
		end
		local intent, parseError = Intents.parse(kind, payload)
		if intent == nil then
			warn(
				string.format(
					"[Frontir] неверное намерение от %s: %s",
					player.Name,
					tostring(parseError)
				)
			)
			return
		end
		local ok, reason = MatchSim.applyIntent(m, id, intent)
		if not ok then
			matchEvent:FireClient(player, { kind = "rejected", reason = reason or "?", intent = intent.kind })
		end
	end)

	-- Панель разработчика (F4): только в Studio. В опубликованной игре канала Remotes.Dev нет вовсе.
	local devSpeed = 1
	local devNoFog: { [Player]: boolean } = {} -- «Туман выкл»: игроку уходят все фронты
	if RunService:IsStudio() then
		local devEvent = Instance.new("RemoteEvent")
		devEvent.Name = "Dev"
		devEvent.Parent = remotes
		-- Самопроверка (сводная правка, часть 1): ошибки скриптов сервера, пока идёт проверка.
		local checkErrors: { string }? = nil
		ScriptContext.Error:Connect(function(message: string, trace: string)
			local list = checkErrors
			if list ~= nil and #list < 50 then
				table.insert(list, message .. " | " .. string.sub(trace, 1, 200))
			end
		end)
		devEvent.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
			local id = nationOf[player]
			if id == nil or type(action) ~= "string" then
				return
			end
			local target = if type(arg) == "number" and m.nations[arg] ~= nil then arg else nil
			local ok, reason = true, nil :: string?
			if action == "grant" and (arg == "forces" or arg == "people" or arg == "money") then
				ok, reason = DevTools.grant(m, id, arg)
			elseif action == "speed" then
				devSpeed = if devSpeed == 1 then Config.Dev.FastSpeed else 1
				matchEvent:FireClient(player, { kind = "dev", speed = devSpeed })
			elseif action == "war" and target ~= nil then
				ok, reason = DevTools.warNow(m, id, target)
			elseif action == "botWar" and target ~= nil then
				ok, reason = DevTools.warNow(m, target, id)
			elseif action == "peace" and target ~= nil then
				ok, reason = DevTools.peaceNow(m, id, target)
			elseif
				action == "offer"
				and type(arg) == "table"
				and type(arg.bot) == "number"
				and m.nations[arg.bot] ~= nil
				and (arg.offer == "alliance" or arg.offer == "pact" or arg.offer == "trade" or arg.offer == "demand")
			then
				ok, reason = DevTools.forceOffer(m, arg.bot, id, arg.offer)
			elseif action == "council" then
				ok, reason = DevTools.councilNow(m)
			elseif action == "end" then
				ok, reason = DevTools.endMatch(m)
			elseif action == "fog" then
				if devNoFog[player] then
					devNoFog[player] = nil
				else
					devNoFog[player] = true
				end
				matchEvent:FireClient(player, { kind = "dev", fog = not devNoFog[player] })
			elseif action == "stability" and (arg == "low" or arg == "high") then
				ok, reason = DevTools.setStability(m, id, arg == "high")
			elseif action == "revolt" then
				ok, reason = DevTools.revoltNow(m, id)
			elseif action == "navy" then
				ok, reason = DevTools.navy(m, id)
			elseif action == "giant" then
				ok, reason = DevTools.giant(m, id) -- §15м «Сверхдержава»
			elseif action == "trustAlly" then
				ok, reason = DevTools.trustAlly(m, id) -- §15у: союзник с полным доверием и враг за ним
			elseif action == "botLanding" and target ~= nil then
				ok, reason = DevTools.botLanding(m, target, id)
			elseif action == "airForce" then
				ok, reason = DevTools.airForce(m, id)
			elseif action == "botRaid" and target ~= nil then
				ok, reason = DevTools.botRaid(m, target, id)
			elseif action == "eventNow" then
				ok, reason = DevTools.eventNow(m)
			elseif action == "silo" then
				ok, reason = DevTools.silo(m, id)
			elseif action == "tradeNow" then
				ok, reason = DevTools.tradeNow(m, id)
			elseif action == "botMissile" and target ~= nil then
				ok, reason = DevTools.botMissile(m, target, id)
			elseif action == "botNuke" and target ~= nil then
				ok, reason = DevTools.botNuke(m, target, id)
			elseif action == "resetCooldowns" then
				ok, reason = DevTools.resetCooldowns(m, id)
			elseif action == "nextCommander" then
				ok, reason = DevTools.nextCommander(m, id)
			elseif action == "botAbility" and target ~= nil then
				ok, reason = DevTools.botAbility(m, target, id)
			elseif action == "researchAll" then
				ok, reason = DevTools.researchAll(m, id)
			elseif action == "finishResearch" then
				ok, reason = DevTools.finishResearch(m, id)
			elseif action == "mode" then
				-- Режим без голосования: по кругу; в лобби — сразу этот, иначе — со следующего матча.
				local k = if devMode ~= nil then table.find(Types.ModeIds, devMode) or 0 else 0
				devMode = Types.ModeIds[k % #Types.ModeIds + 1]
				if m.phase == "Waiting" or m.phase == "Lobby" then
					m.forcedMode = devMode
				end
				matchEvent:FireClient(player, { kind = "dev", mode = devMode })
			elseif action == "tokens" or action == "xp" or action == "medals" then
				-- Профиль (§11.2): жетоны штаба и опыт для проверки магазина и генералов по уровням.
				local session = profiles.get(player.UserId)
				if session == nil then
					ok, reason = false, "target"
				else
					if action == "medals" then
						session.data.medals += Config.Dev.GrantMedals -- гардероб (§11.4)
					elseif action == "tokens" then
						session.data.tokens += Config.Dev.GrantTokens
					else
						Profile.addXp(session.data, Config.Dev.GrantXp)
					end
					applyProfile(player)
					sendProfile(player)
				end
			elseif action == "flood" then
				ok, reason = DevTools.floodNow(m)
			elseif action == "selfAbility" and type(arg) == "table" and type(arg.commander) == "string" then
				ok, reason = DevTools.selfAbility(m, id, arg.commander, tonumber(arg.slot) or 0)
			elseif action == "worldEvent" and type(arg) == "string" then
				ok, reason = DevTools.worldEventKind(m, arg)
			elseif action == "selfCheck" and (arg == "start" or arg == "stop") then
				if arg == "start" then
					checkErrors = {}
				else
					matchEvent:FireClient(player, { kind = "dev", serverErrors = checkErrors or {} })
					checkErrors = nil
				end
			elseif action == "mapNow" then
				-- Смена карты сейчас (самопроверка): следующая карта пула, новый матч в лобби.
				local pool = Config.MapVote.Pool
				local k = table.find(pool, map.name) or 0
				task.defer(startNewMatch, pool[k % #pool + 1])
			elseif action == "map" then
				-- Карта следующего матча без голосования (§5.2): по кругу пула.
				local pool = Config.MapVote.Pool
				local k = table.find(pool, devMap or map.name) or 0
				devMap = pool[k % #pool + 1]
				matchEvent:FireClient(player, { kind = "dev", map = devMap })
			else
				ok, reason = false, "target"
			end
			if not ok then
				matchEvent:FireClient(player, { kind = "rejected", reason = reason or "?", intent = "dev" })
			end
			-- Подтверждение каждого действия (самопроверка ждёт его).
			matchEvent:FireClient(player, { kind = "dev", ack = action, ok = ok, reason = reason })
		end)
	end

	-- Новый матч на карте mapId (после итогов или по настройкам частного сервера в лобби): все игроки — в лобби.
	function startNewMatch(mapId: string)
		if mapId ~= map.name then
			map = loadMap(mapId)
		end
		m = newMatch()
		demoRunning = false
		demoSpeed = 1
		table.clear(nationOf)
		for _, player in Players:GetPlayers() do
			if not joined[player] then
				continue -- §15л ч.7: в меню — зритель
			end
			local id = MatchSim.addPlayer(m, player.UserId, player.DisplayName)
			if id ~= nil then
				nationOf[player] = id
			end
		end
		MatchSim.startLobby(m)
		for player in nationOf do
			applyProfile(player)
		end
		sendInfoAll()
		for player in nationOf do
			sendProfile(player)
		end
		print(string.format("[Frontir] новый матч, сид %d, карта %s", m.seed, map.name))
	end

	-- §15л ч.5 Хаб: показательный матч только из ботов (игроки — зрители), карты по кругу.
	local demoIndex = 0
	function startDemo()
		-- Хаб — карты по кругу; «как раньше» (§15л ч.7) — на текущей карте (без перезагрузки у игроков).
		if isHub then
			local pool = Config.Hub.DemoMaps
			demoIndex = demoIndex % #pool + 1
			local mapId = pool[demoIndex]
			if mapId ~= map.name and (Config.RealMaps :: any)[mapId] ~= nil then
				map = loadMap(mapId)
			end
		end
		if role == "combined" then
			serverMap, serverMode, soloServer, soloLevel = nil, nil, false, nil
		end
		demoRunning = true
		demoSpeed = Config.Hub.DemoSpeed
		m = newMatch()
		m.targetNations = Config.Hub.DemoNations
		m.forcedMode = "Ffa"
		table.clear(nationOf)
		MatchSim.startPick(m)
		sendInfoAll()
		print(string.format("[Frontir] хаб: показательный матч, карта %s", map.name))
	end

	local step = 1 / Config.Sim.TickRate
	local acc = 0
	local statsAcc = 0
	local stabilityAcc = 0
	local lastTickMs = 0
	local lastChanged = 0
	-- Кому из игроков туман не нужен: зритель (нет живой державы) и «Туман выкл» в панели разработчика.
	local function viewerOf(player: Player): number?
		local id = nationOf[player]
		local n = if id ~= nil then m.nations[id] else nil
		-- Радарная вспышка Разведчика (§6.15) — пока она идёт, видно всё.
		if n == nil or not n.alive or devNoFog[player] or MatchSim.revealing(m, n.id) then
			return nil
		end
		return id
	end

	-- Всем — статистика (державы одинаковые, фронты — каждому свои из-за тумана, §6.11) и войны;
	-- каждому игроку — его войска и очередь найма.
	local function sendStats()
		local full = MatchStats.build(m, lastTickMs, lastChanged)
		local head = Protocol.encodeStatsHead(full)
		local allWars = MatchStats.wars(m) -- один раз: захваченная земля считается по сетке (§6.11а)
		for _, player in Players:GetPlayers() do
			local viewer = viewerOf(player)
			-- Обзор считаем один раз: по нему и фронты, и корабли (§6.11, §6.12).
			local vision = if viewer ~= nil and MatchStats.fogOn(m) then MatchStats.vision(m, viewer) else nil
			-- Скрытая мощь (§6.11а): у кого есть держава — свой набор «чью мощь видно»; зритель видит всё.
			local id = nationOf[player]
			local alive = id ~= nil and m.nations[id] ~= nil and m.nations[id].alive
			local known = if alive and not devNoFog[player] then MatchSim.knownSet(m, id :: number) else nil
			local stats = MatchStats.forViewer(m, full, viewer, vision, known)
			matchEvent:FireClient(player, Protocol.encodeStats(stats, if known == nil then head else nil))
			matchEvent:FireClient(player, Protocol.encodeWars(MatchStats.hideWars(allWars, known)))
			-- Зритель и «Туман выкл» видят все корабли; груз и очередь — только свои.
			local ships = MatchStats.ships(m, nationOf[player], vision, viewer == nil)
			matchEvent:FireClient(player, Protocol.encodeShips(ships))
			local air = MatchStats.air(m, nationOf[player], vision, viewer == nil)
			matchEvent:FireClient(player, Protocol.encodeAir(air))
		end
		for player, id in nationOf do
			matchEvent:FireClient(player, Protocol.encodeForces(MatchStats.forcesOf(m, id)))
		end
	end

	-- Стабильность (§6.10): каждому — свои провинции и средняя, всем — повстанцы.
	local function sendStability()
		for _, player in Players:GetPlayers() do
			local id = nationOf[player]
			matchEvent:FireClient(player, MatchStats.stability(m, id))
			if id ~= nil then
				matchEvent:FireClient(player, MatchStats.tech(m, id)) -- технологии (§6.14) — тем же темпом
				matchEvent:FireClient(player, MatchStats.commander(m, id)) -- генерал (§6.15)
			end
			matchEvent:FireClient(player, MatchStats.world(m, id)) -- события и ракеты (§6.16, §6.9)
		end
	end

	RunService.Heartbeat:Connect(function(dt: number)
		-- «Против ботов» (§5.1): на паузе симуляция стоит, ×2 — вдвое больше шагов за кадр.
		local paused = m.paused and m.phase == "Play"
		local soloSpeed = if m.fast then Config.Modes.SoloFastSpeed else 1
		if paused then
			acc = 0
			if m.infoDirty and os.clock() >= infoAt + Config.Net.InfoMinSec then
				m.infoDirty = false
				infoAt = os.clock()
				sendInfoAll()
			end
		else
			acc += dt * devSpeed * soloSpeed * demoSpeed -- «Время ×5» панели разработчика: больше шагов симуляции за кадр
		end
		statsAcc += dt
		local steps = 0
		while acc >= step and steps < Config.Net.MaxStepsPerFrame * devSpeed * soloSpeed * demoSpeed do
			acc -= step
			steps += 1
			local wasPlaying = m.phase == "Play"
			local wasPick = m.phase == "Pick"
			local t0 = os.clock()
			MatchSim.step(m, step)
			-- Обучение — только на «Скандинавии» (сводная правка): другая карта — сменить и сразу к выбору старта.
			local tutorialMap = if not wasPick and m.phase == "Pick" then MatchSim.tutorialMap(m) else nil
			if tutorialMap ~= nil then
				startNewMatch(tutorialMap)
				m.forcedMode = "Tutorial"
				MatchSim.startPick(m)
				break
			end
			-- Голосование за карту в лобби (§15к): лобби кончилось и победила другая карта — загрузить её и сразу
			-- к выбору старта; режим (итог голосования) и выбранные генералы сохраняются.
			if not wasPick and m.phase == "Pick" and not m.rules.tutorial and MatchSim.mapWinner(m) ~= map.name then
				local mode = m.rules.mode
				local chosen: { [Player]: string } = {}
				for player, id in nationOf do
					chosen[player] = Commanders.of(m.commanders, id)
				end
				startNewMatch(MatchSim.mapWinner(m))
				m.forcedMode = mode :: any
				for player, id in nationOf do
					local c = chosen[player]
					if c ~= nil then
						Commanders.choose(m.commanders, id, c :: any)
					end
				end
				MatchSim.startPick(m)
				sendInfoAll()
				break
			end
			lastTickMs = (os.clock() - t0) * 1000
			-- Аналитика (этап 10в, §15в): записи по державам — тому игроку, кто сейчас за неё играет.
			local function sendEntries(entries: { Analytics.Entry })
				local players: { [number]: Player } = {}
				for player, id in nationOf do
					players[id] = player
				end
				for _, entry in entries do
					local player: Player? = players[entry.nation]
					if player then
						Telemetry.custom(player, entry.record)
					end
				end
			end
			local function commanderOf(id: number): string
				return Commanders.of(m.commanders, id)
			end
			if wasPlaying and m.phase == "Over" then
				giveRewards() -- опыт и медали за матч (§11.2)
				local record = Analytics.matchEnd(m) -- длина матча
				for player in nationOf do
					Telemetry.custom(player, record)
				end
				sendEntries(Analytics.results(m, commanderOf)) -- генерал и место
			end
			if not wasPlaying and m.phase == "Play" then
				sendEntries(Analytics.commanders(m, commanderOf)) -- выбор генералов
			end

			-- info — не чаще Net.InfoMinSec (смена фазы — сразу): выбывания подряд уходят одним сообщением.
			local phaseChanged = m.phase ~= infoPhase
			if m.infoDirty and (phaseChanged or os.clock() >= infoAt + Config.Net.InfoMinSec) then
				m.infoDirty = false
				infoPhase, infoAt = m.phase, os.clock()
				sendInfoAll()
			end
			local changes = Grid.takeChanges(m.grid)
			lastChanged = #changes
			if not wasPlaying and m.phase == "Play" then
				sendSnapshot(nil) -- начало игры: расстановка целиком
			elseif #changes > 0 then
				matchEvent:FireAllClients(Protocol.encodeDelta(m.tick, changes, m.grid.owner))
			end
			-- Новые здания и уровни городов — только изменения (полный список уходит в info).
			local built = Buildings.takeChanges(m.buildings)
			if #built > 0 then
				matchEvent:FireAllClients({ kind = "buildings", list = built })
			end
			-- §15ч Ч1: сменившиеся железные дороги — не чаще Net.RailsMinSec.
			if m.rails.version ~= railsVersion and os.clock() >= railsAt + Config.Net.RailsMinSec then
				railsVersion = m.rails.version
				railsAt = os.clock()
				matchEvent:FireAllClients(MatchSim.railsMessage(m, false))
			end
			-- Изменения договоров за Net.DiploMinSec уходят одним сообщением.
			local version = m.diplo.version + m.council.version * 65536 -- договоры и Совет — одним сообщением
			if version ~= diploVersion and os.clock() >= diploAt + Config.Net.DiploMinSec then
				sendDiplo(nil)
			end
			local events = MatchSim.takeEvents(m)
			if #events > 0 then
				matchEvent:FireAllClients({ kind = "events", events = events })
				-- Обучение пройдено (§5.5): награда в профиль один раз.
				for _, e in events do
					-- Воронка обучения (аналитика, этап 10в).
					local step = Analytics.funnel(e)
					if step ~= nil then
						for player, id in nationOf do
							if id == (e :: any).nation then
								Telemetry.funnel(player, step)
							end
						end
					end
					if e.kind == "tutorialDone" then
						for player, id in nationOf do
							local session = profiles.get(player.UserId)
							if id == e.nation and session ~= nil and Profile.finishTutorial(session.data) then
								task.spawn(profiles.save, player.UserId)
								sendProfile(player)
							end
						end
					end
				end
			end
		end
		if acc > step * Config.Net.MaxStepsPerFrame * devSpeed * soloSpeed * demoSpeed then
			acc = 0 -- сервер не успевает: лучше пропустить время, чем копить отставание
		end
		-- Результаты показаны — новый матч на той же карте (её меняет голосование в лобби, §15к), из F4 или
		-- настроек частного сервера (§5.4): все игроки снова в лобби.
		if m.phase == "Over" and m.phaseLeft <= 0 then
			local anyone = false
			for player in joined do
				if player.Parent ~= nil then
					anyone = true
				end
			end
			if isHub or (role == "combined" and not anyone) then
				startDemo() -- показательный бой: хаб — следующая карта; «как раньше» — все в меню (§15л ч.7)
			else
				-- §15ф Ф1: без голосований — следующая карта по кругу пула.
				local nextMap = devMap
					or serverMap
					or (if settings ~= nil then settings.map else nil)
					or (if m.lobbyVotes then map.name else Modes.nextMap(map.name))
				devMap = nil
				startNewMatch(nextMap)
			end
		end
		if m.phase == "Play" and statsAcc >= 1 / Config.Net.StatsHz then
			statsAcc = 0
			sendStats()
		end
		stabilityAcc += dt
		if m.phase == "Play" and stabilityAcc >= Config.Net.StabilityEverySec then
			stabilityAcc = 0
			sendStability()
		end
	end)

	-- Хаб и «как раньше» (§15л ч.7): пока никто не нажал «В БОЙ» — показательный бой ботов за меню.
	if isHub or role == "combined" then
		startDemo()
	end
	print(
		string.format(
			"[Frontir] матч запущен, сид %d, держав по плану %d",
			seed,
			m.targetNations
		)
	)
end

return table.freeze(MatchService)
