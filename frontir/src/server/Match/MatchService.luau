--!strict
--[[
	MatchService — связь симуляции матча (Shared.MatchSim) с Roblox:
	- игроки входят и выходят, получают державы;
	- намерения клиентов: лимит запросов → разбор (Intents) → MatchSim.applyIntent;
	- тик 10 Гц на Heartbeat с фиксированным шагом;
	- рассылка: info (таблица) при смене фазы и держав, снимок сетки частями (начало игры, опоздавшие),
	  дельты изменений и армии каждый тик, статистика Config.Net.StatsHz раз в секунду.
	Всё идёт по одному RemoteEvent ReplicatedStorage.Remotes.Match, поэтому порядок сообщений сохраняется.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Armies = require(Shared:WaitForChild("Armies"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Grid = require(Shared:WaitForChild("Grid"))
local Intents = require(Shared:WaitForChild("Intents"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local MatchSim = require(Shared:WaitForChild("MatchSim"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local RateLimiter = require(Shared:WaitForChild("RateLimiter"))

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

	local seed = Random.new():NextInteger(1, 2 ^ 31 - 1)
	local m = MatchSim.new(map, seed)
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
				alive = n.alive,
			})
		end
		return {
			kind = "info",
			phase = m.phase,
			phaseLeft = math.max(0, m.phaseLeft),
			time = m.time,
			myNation = nationOf[player],
			nations = nations,
			cities = MatchSim.cities(m),
		}
	end

	local function sendInfoAll()
		for _, player in Players:GetPlayers() do
			matchEvent:FireClient(player, infoFor(player))
		end
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
			MatchSim.startPick(m)
		end
		local id = MatchSim.addPlayer(m, player.UserId, player.DisplayName)
		if id ~= nil then
			nationOf[player] = id
		end
		limiters[player] = RateLimiter.new(Config.Sim.MaxIntentsPerSecond, Config.Sim.MaxIntentsPerSecond, os.clock())
		matchEvent:FireClient(player, infoFor(player))
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

	local step = 1 / Config.Sim.TickRate
	local acc = 0
	local statsAcc = 0
	local lastTickMs = 0
	local lastChanged = 0
	local lastArmyCount = 0

	local function sendArmies()
		local list: { Protocol.ArmyView } = {}
		for _, a in m.armies do
			local progress = if a.state == "recruit"
				then 1 - a.recruitLeft / math.max(0.001, Armies.stats(a.kind).recruitSec)
				else Armies.captureProgress(a)
			table.insert(list, {
				id = a.id,
				owner = a.owner,
				kind = a.kind :: string, -- поля таблиц инвариантны: юнион-строку приводим к string явно
				x = a.x,
				y = a.y,
				strength = a.strength,
				maxStrength = a.maxStrength,
				state = a.state :: string,
				stars = a.stars,
				progress = progress,
				auto = a.auto,
			})
		end
		if #list > 0 or lastArmyCount > 0 then
			matchEvent:FireAllClients(Protocol.encodeArmies(m.tick, list))
		end
		lastArmyCount = #list
	end

	local function sendStats()
		local nations: { Protocol.NationStats } = {}
		for _, n in m.nations do
			local cells = Grid.cellsOf(m.grid, n.id)
			table.insert(nations, {
				id = n.id,
				people = n.people,
				maxPeople = Economy.maxPeople(cells),
				cells = cells,
				troops = MatchSim.troopsOf(m, n.id),
			})
		end
		local attacks: { Protocol.AttackStats } = {}
		for _, a in m.attacks do
			table.insert(attacks, { attacker = a.attacker, target = a.target, troops = a.troops })
		end
		matchEvent:FireAllClients(Protocol.encodeStats({
			tickMs = lastTickMs,
			changed = lastChanged,
			nations = nations,
			attacks = attacks,
		}))
	end

	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		statsAcc += dt
		local steps = 0
		while acc >= step and steps < Config.Net.MaxStepsPerFrame do
			acc -= step
			steps += 1
			local wasPlaying = m.phase == "Play"
			local t0 = os.clock()
			MatchSim.step(m, step)
			lastTickMs = (os.clock() - t0) * 1000

			if m.infoDirty then
				m.infoDirty = false
				sendInfoAll()
			end
			local changes = Grid.takeChanges(m.grid)
			lastChanged = #changes
			if not wasPlaying and m.phase == "Play" then
				sendSnapshot(nil) -- начало игры: расстановка целиком
			elseif #changes > 0 then
				matchEvent:FireAllClients(Protocol.encodeDelta(m.tick, changes, m.grid.owner))
			end
			if m.phase == "Play" then
				sendArmies()
			end
			local events = MatchSim.takeEvents(m)
			if #events > 0 then
				matchEvent:FireAllClients({ kind = "events", events = events })
			end
		end
		if acc > step * Config.Net.MaxStepsPerFrame then
			acc = 0 -- сервер не успевает: лучше пропустить время, чем копить отставание
		end
		if m.phase == "Play" and statsAcc >= 1 / Config.Net.StatsHz then
			statsAcc = 0
			sendStats()
		end
	end)

	print(
		string.format(
			"[Frontir] матч запущен, сид %d, держав по плану %d",
			seed,
			Config.Match.TargetNations
		)
	)
end

return table.freeze(MatchService)
