--!strict
--[[
	Trains — поезда по железным дорогам (§15ч Ч2). Чистый модуль: маршрут по сети станций, остановки с платой,
	движение по клеткам маршрута. MatchSim решает, когда отправить поезд и кому платить; клиент двигает поезд по
	тому же маршруту сам (Trains.at).
	- Маршрут — поиск в ширину по дорогам сети (Rails.Net.links) от завода до станции-цели; клетки дорог
	  склеиваются (первая клетка следующей дороги — та же станция).
	- Остановки — города и порты на пути (и цель), кроме станции отправления; платят не больше Rail.MaxPaidStops.
]]

local Config = require("./Config")
local Rails = require("./Rails")

export type Stop = { index: number, cell: number, money: number }
export type Train = {
	id: number,
	owner: number,
	cells: { number }, -- клетки маршрута по порядку
	stops: { Stop },
	nextStop: number, -- номер следующей неоплаченной остановки
	pos: number, -- сколько клеток проехал (1 — на станции отправления)
	speed: number, -- клеток в секунду
	start: number, -- игровое время отправления
	checkAt: number, -- когда проверить путь впереди
}

local Trains = {}

-- Плата остановки: город — по уровню, порт — постоянная; остальное — 0 (не остановка).
function Trains.stopMoney(kind: string, cityLevel: number): number
	local cfg = Config.Rail
	if kind == "City" then
		return cfg.StopMoney + cfg.StopCityLevelMoney * cityLevel
	elseif kind == "Port" then
		return cfg.PortStopMoney
	end
	return 0
end

-- Куда может ехать поезд: города и порты той же сети, кроме самой станции.
function Trains.destinations(net: Rails.Net, from: number): { number }
	local out: { number } = {}
	local comp = net.comp[from]
	if comp == nil then
		return out
	end
	for cell, c in net.comp do
		local kind = net.kinds[cell]
		if c == comp and cell ~= from and (kind == "City" or kind == "Port") then
			table.insert(out, cell)
		end
	end
	table.sort(out)
	return out
end

-- Маршрут от станции from до станции to: клетки и станции по пути (по порядку, с from и to). nil — пути нет.
function Trains.route(net: Rails.Net, from: number, to: number): ({ number }?, { number }?)
	type Edge = { to: number, link: Rails.Link }
	local adj: { [number]: { Edge } } = {}
	for _, link in net.links do
		adj[link.a] = adj[link.a] or {}
		adj[link.b] = adj[link.b] or {}
		table.insert(adj[link.a], { to = link.b, link = link })
		table.insert(adj[link.b], { to = link.a, link = link })
	end
	local prev: { [number]: number } = {}
	local via: { [number]: Rails.Link } = {}
	local seen: { [number]: boolean } = { [from] = true }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local s = queue[head]
		head += 1
		if s == to then
			break
		end
		local edges: { Edge } = adj[s] or {}
		for _, e in edges do
			if not seen[e.to] then
				seen[e.to] = true
				prev[e.to] = s
				via[e.to] = e.link
				table.insert(queue, e.to)
			end
		end
	end
	if not seen[to] then
		return nil, nil
	end
	-- Станции от from к to.
	local order: { number } = { to }
	while order[1] ~= from do
		table.insert(order, 1, prev[order[1]])
	end
	local cells: { number } = { from }
	for k = 2, #order do
		local a, b = order[k - 1], order[k]
		local link = via[b]
		local path = link.path
		if link.a == a then
			for j = 2, #path do
				table.insert(cells, path[j])
			end
		else
			for j = #path - 1, 1, -1 do
				table.insert(cells, path[j])
			end
		end
	end
	return cells, order
end

-- Поезд от завода from до цели to: маршрут и оплачиваемые остановки. cityLevel(cell) — уровень города.
function Trains.plan(
	net: Rails.Net,
	from: number,
	to: number,
	cityLevel: (cell: number) -> number
): ({ number }?, { Stop }?)
	local cells, order = Trains.route(net, from, to)
	if cells == nil or order == nil then
		return nil, nil
	end
	local index: { [number]: number } = {}
	for k, cell in cells do
		if index[cell] == nil then
			index[cell] = k
		end
	end
	local stops: { Stop } = {}
	for k = 2, #order do
		local cell = order[k]
		local money = Trains.stopMoney(net.kinds[cell] or "", cityLevel(cell))
		if money > 0 and #stops < Config.Rail.MaxPaidStops then
			table.insert(stops, { index = index[cell], cell = cell, money = money })
		end
	end
	return cells, stops
end

-- Скорость поезда на карте ширины width (клеток в секунду).
function Trains.speed(width: number): number
	return Config.Rail.TrainSpeed * width / Config.UnitsReferenceMapWidth
end

-- Продвинуть поезд на dt секунд: остановки, до которых доехал (по порядку), и доехал ли до конца.
function Trains.advance(train: Train, dt: number): ({ Stop }, boolean)
	train.pos = math.min(#train.cells, train.pos + train.speed * dt)
	local reached: { Stop } = {}
	while train.nextStop <= #train.stops and train.stops[train.nextStop].index <= train.pos do
		table.insert(reached, train.stops[train.nextStop])
		train.nextStop += 1
	end
	return reached, train.pos >= #train.cells
end

-- Точка на маршруте (в клетках, дробная) через t секунд после отправления; d — отступ назад (вагоны).
function Trains.at(cells: { number }, width: number, speed: number, t: number, d: number): (number, number)
	local p = math.clamp(1 + speed * t - d, 1, #cells)
	local k = math.floor(p)
	local f = p - k
	local a = cells[k]
	local b = cells[math.min(k + 1, #cells)]
	local ax, ay, bx, by = a % width, a // width, b % width, b // width
	return ax + (bx - ax) * f + 0.5, ay + (by - ay) * f + 0.5
end

return table.freeze(Trains)
