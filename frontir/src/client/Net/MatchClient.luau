--!strict
--[[
	MatchClient — приём сообщений сервера и отправка намерений.
	Сервер шлёт всё по одному RemoteEvent (порядок сохраняется): buffer — бинарные сообщения
	(Net/Protocol), таблица — info / events / rejected. Состояние копится в Shared.ClientState,
	там же счётчик принятых байт (buffer — точно, таблицы — по длине JSON) для строки «Сеть» в F3.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientState = require(Shared:WaitForChild("ClientState"))

type ClientState = ClientState.ClientState

export type Handlers = {
	onInfo: (colorsChanged: boolean) -> (),
	onSnapshot: () -> (),
	onDelta: (cells: { number }) -> (),
	onStats: () -> (),
	onForces: () -> (),
	onWars: () -> (),
	onBuildings: () -> (),
	onDiplo: () -> (),
	onStability: (rebelsChanged: { number }) -> (), -- своя стабильность и повстанцы (§6.10)
	onTech: (() -> ())?, -- свои технологии пришли (§6.14)
	onCommander: (() -> ())?, -- свой генерал и способности (§6.15)
	onShips: () -> (), -- корабли (§6.12)
	onAir: () -> (), -- самолёты (§6.13)
	onDev: ((msg: any) -> ())?, -- ответ панели разработчика (только Studio)
	onEvents: (events: { any }) -> (),
	onRejected: (reason: string) -> (),
}

export type MatchClient = {
	send: (kind: string, payload: { [string]: any }) -> (),
}

local MatchClient = {}

function MatchClient.connect(cs: ClientState, handlers: Handlers): MatchClient
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local matchEvent = remotes:WaitForChild("Match") :: RemoteEvent
	local intentEvent = remotes:WaitForChild("Intent") :: RemoteEvent

	matchEvent.OnClientEvent:Connect(function(msg: any)
		if typeof(msg) == "buffer" then
			local ok, result, cells = pcall(ClientState.applyBuffer, cs, msg)
			if not ok then
				warn("[Frontir] не удалось разобрать сообщение сервера:", result)
				return
			end
			if result == "snapshot" then
				handlers.onSnapshot()
			elseif result == "delta" and cells ~= nil then
				handlers.onDelta(cells)
			elseif result == "stats" then
				handlers.onStats()
			elseif result == "forces" then
				handlers.onForces()
			elseif result == "wars" then
				cs.warsAt = os.clock()
				handlers.onWars()
			elseif result == "ships" then
				cs.shipsAt = os.clock()
				handlers.onShips()
			elseif result == "air" then
				cs.airAt = os.clock()
				handlers.onAir()
			end
		elseif type(msg) == "table" then
			-- Таблицы (info, events) редкие: их размер для F3 оцениваем по JSON.
			local okSize, json = pcall(HttpService.JSONEncode, HttpService, msg)
			if okSize then
				cs.bytes += #json
			end
			if msg.kind == "info" then
				handlers.onInfo(ClientState.applyInfo(cs, msg :: ClientState.Info, os.clock()))
			elseif msg.kind == "events" and type(msg.events) == "table" then
				handlers.onEvents(msg.events)
			elseif msg.kind == "diplo" then
				ClientState.applyDiplo(cs, msg, os.clock())
				handlers.onDiplo()
			elseif msg.kind == "buildings" and type(msg.list) == "table" then
				ClientState.applyBuildings(cs, msg.list)
				handlers.onBuildings()
			elseif msg.kind == "stability" then
				handlers.onStability(ClientState.applyStability(cs, msg))
			elseif msg.kind == "tech" then
				ClientState.applyTech(cs, msg)
				if handlers.onTech ~= nil then
					handlers.onTech()
				end
			elseif msg.kind == "commander" then
				ClientState.applyCommander(cs, msg, os.clock())
				if handlers.onCommander ~= nil then
					handlers.onCommander()
				end
			elseif msg.kind == "rejected" then
				handlers.onRejected(tostring(msg.reason))
			elseif msg.kind == "dev" and handlers.onDev ~= nil then
				handlers.onDev(msg)
			end
		end
	end)

	return {
		send = function(kind: string, payload: { [string]: any })
			intentEvent:FireServer(kind, payload)
		end,
	}
end

return table.freeze(MatchClient)
