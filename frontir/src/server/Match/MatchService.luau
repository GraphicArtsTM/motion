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

local Shared = ReplicatedStorage:WaitForChild("Shared")
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
local Types = require(Shared:WaitForChild("Types"))

type MapData = MapDataModule.MapData

local MatchService = {}

function MatchService.start(map: MapData)
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
	local realMap = (Config.RealMaps :: any)[map.name] :: Types.RealMapParams?
	local devMode: Types.ModeId? = nil -- F4 «Режим»: режим следующего матча без голосования
	local function newMatch(): MatchSim.Match
		local match = MatchSim.new(map, seedRng:NextInteger(1, 2 ^ 31 - 1))
		-- Режимы (§5.1): варианты голосования по времени сервера (режим недели), F4 — без голосования.
		MatchSim.openVote(match, os.time())
		if devMode ~= nil then
			match.forcedMode = devMode
		end
		-- Держав в матче: Dev.Nations (проверка в Studio, например игрок + 3 Генерала) или как у карты.
		match.targetNations = if Config.Dev.Nations > 0
			then Config.Dev.Nations
			elseif realMap ~= nil then realMap.Nations
			else Config.Match.TargetNations
		return match
	end
	local m = newMatch()
	local seed = m.seed
	local nationOf: { [Player]: number } = {}
	local limiters: { [Player]: RateLimiter.RateLimiter } = {}

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

	local function onPlayerAdded(player: Player)
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
			m.infoDirty = true
		end
		limiters[player] = RateLimiter.new(Config.Sim.MaxIntentsPerSecond, Config.Sim.MaxIntentsPerSecond, os.clock())
		matchEvent:FireClient(player, infoFor(player))
		sendDiplo(player)
		if m.phase == "Play" then
			sendSnapshot(player) -- опоздавший — зритель: видит всю карту
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		local id = nationOf[player]
		if id ~= nil then
			MatchSim.removePlayer(m, id)
		end
		nationOf[player] = nil
		limiters[player] = nil
	end)

	intentEvent.OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
		local limiter = limiters[player]
		if limiter == nil or not RateLimiter.allow(limiter, os.clock()) then
			return -- спам намерениями молча отбрасываем (кик за спам — этап 10)
		end
		local id = nationOf[player]
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
			elseif action == "botMissile" and target ~= nil then
				ok, reason = DevTools.botMissile(m, target, id)
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
			else
				ok, reason = false, "target"
			end
			if not ok then
				matchEvent:FireClient(player, { kind = "rejected", reason = reason or "?", intent = "dev" })
			end
		end)
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
			matchEvent:FireClient(player, Protocol.encodeWars(MatchStats.wars(m, known)))
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
			local t0 = os.clock()
			MatchSim.step(m, step)
			lastTickMs = (os.clock() - t0) * 1000

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
			end
		end
		if acc > step * Config.Net.MaxStepsPerFrame * devSpeed * soloSpeed then
			acc = 0 -- сервер не успевает: лучше пропустить время, чем копить отставание
		end
		-- Результаты показаны — новый матч на той же карте: все игроки снова в лобби (смена карты — этап 8).
		if m.phase == "Over" and m.phaseLeft <= 0 then
			m = newMatch()
			table.clear(nationOf)
			for _, player in Players:GetPlayers() do
				local id = MatchSim.addPlayer(m, player.UserId, player.DisplayName)
				if id ~= nil then
					nationOf[player] = id
				end
			end
			MatchSim.startLobby(m)
			sendInfoAll()
			print(string.format("[Frontir] новый матч, сид %d", m.seed))
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
