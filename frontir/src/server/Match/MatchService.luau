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
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Analytics = require(Shared:WaitForChild("Analytics"))
local Buildings = require(Shared:WaitForChild("Buildings"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Commanders = require(Shared:WaitForChild("Commanders"))
local Config = require(Shared:WaitForChild("Config"))
local DevTools = require(Shared:WaitForChild("DevTools"))
local Grid = require(Shared:WaitForChild("Grid"))
local Intents = require(Shared:WaitForChild("Intents"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local MatchSim = require(Shared:WaitForChild("MatchSim"))
local MatchStats = require(Shared:WaitForChild("Net"):WaitForChild("MatchStats"))
local Modes = require(Shared:WaitForChild("Modes"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local RateLimiter = require(Shared:WaitForChild("RateLimiter"))
local ServerSettings = require(Shared:WaitForChild("ServerSettings"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Profile = require(Shared:WaitForChild("Profile"))
local Quests = require(Shared:WaitForChild("Quests"))
local Shop = require(Shared:WaitForChild("Shop"))

local Services = script.Parent.Parent:WaitForChild("Services")
local ProfileStore = require(Services:WaitForChild("ProfileStore"))
local ShopService = require(Services:WaitForChild("ShopService"))
local Leaders = require(Services:WaitForChild("Leaders"))
local Telemetry = require(Services:WaitForChild("Telemetry"))
local Types = require(Shared:WaitForChild("Types"))

type MapData = MapDataModule.MapData

local MatchService = {}

function MatchService.start(firstMap: MapData, loadMap: (mapId: string) -> MapData)
	local map = firstMap
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
	local function newMatch(): MatchSim.Match
		local realMap = (Config.RealMaps :: any)[map.name] :: Types.RealMapParams?
		local match = MatchSim.new(map, seedRng:NextInteger(1, 2 ^ 31 - 1))
		match.settings = settings
		if settings ~= nil and settings.mode ~= nil then
			match.forcedMode = settings.mode
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
			tutorialStep = if m.rules.tutorial then m.tutorialStep else nil, -- «Обучение» (§5.5)
			server = if settings ~= nil
				then { settings = settings, isOwner = ownerId ~= nil and player.UserId == ownerId }
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
			dayLeft = 86400 - now % 86400,
			elo = d.elo,
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
		local open = Profile.unlockedCommanders(session.data, passes.AllCommanders == true)
		MatchSim.setUnlocked(m, id, open)
		local chosen = Commanders.of(m.commanders, id)
		if chosen ~= nil and not open[chosen] and m.phase ~= "Play" then
			Commanders.choose(m.commanders, id, "Marshal")
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

	local function onPlayerAdded(player: Player)
		if nationOf[player] ~= nil then
			return
		end
		if isPrivate and ownerId == nil then
			ownerId = player.UserId -- Studio (Dev.PrivateServer): владелец — первый вошедший
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
			m.infoDirty = true
		end
		limiters[player] = RateLimiter.new(Config.Sim.MaxIntentsPerSecond, Config.Sim.MaxIntentsPerSecond, os.clock())
		matchEvent:FireClient(player, infoFor(player))
		sendDiplo(player)
		if m.phase == "Play" then
			sendSnapshot(player) -- опоздавший — зритель: видит всю карту
		end
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
		limiters[player] = nil
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
			if m.phase == "Play" then
				sendSnapshot(player)
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
		table.clear(nationOf)
		for _, player in Players:GetPlayers() do
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
			acc += dt * devSpeed * soloSpeed -- «Время ×5» панели разработчика: больше шагов симуляции за кадр
		end
		statsAcc += dt
		local steps = 0
		while acc >= step and steps < Config.Net.MaxStepsPerFrame * devSpeed * soloSpeed do
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
		if acc > step * Config.Net.MaxStepsPerFrame * devSpeed * soloSpeed then
			acc = 0 -- сервер не успевает: лучше пропустить время, чем копить отставание
		end
		-- Результаты показаны — новый матч на той же карте (её меняет голосование в лобби, §15к), из F4 или
		-- настроек частного сервера (§5.4): все игроки снова в лобби.
		if m.phase == "Over" and m.phaseLeft <= 0 then
			local nextMap = devMap or (if settings ~= nil then settings.map else nil) or map.name
			devMap = nil
			startNewMatch(nextMap)
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

	print(
		string.format(
			"[Frontir] матч запущен, сид %d, держав по плану %d",
			seed,
			m.targetNations
		)
	)
end

return table.freeze(MatchService)
