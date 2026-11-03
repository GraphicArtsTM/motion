--!strict
--[[
	FrontLayer — войска на линии фронта (GDD §6.6–6.7, модель «Фронты»).
	Сервер присылает фронты в STATS (атакующий, цель, сила, доли типов, снабжение, бой); где проходит
	линия фронта, клиент видит сам — это граница между клетками атакующего и цели в его копии сетки.

	- Раз в Config.Render.FrontScanSec один проход по видимым клеткам находит линии всех фронтов;
	  вдоль каждой расставляются юниты (состав — как у фронта): атакующие на своей стороне, защитники
	  (если у цели есть гарнизон) — на своей.
	- Юниты чуть покачиваются (марш), в бою вспыхивают выстрелы и по линии фронта рвутся снаряды.
	- Фронт без снабжения — юниты в красной обводке.
	Спрайты программные (Shared.UnitSprites, пока нет арта): пехота, танки, артиллерия, ПВО — docs/ART_LIST.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Types = require(Shared:WaitForChild("Types"))
local UnitSprites = require(Shared:WaitForChild("UnitSprites"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState

local SHAPES = UnitSprites.Shapes
local SPRITE_W, SPRITE_H = UnitSprites.Width, UnitSprites.Height

type Sprite = {
	root: Frame,
	parts: { Frame },
	strokes: { UIStroke },
	kind: string,
	cell: number,
	phase: number,
}

type Effect = { frame: Frame, born: number, life: number, big: boolean }

export type FrontLayer = {
	update: (now: number, state: CameraState) -> (),
}

local FrontLayer = {}

-- Фронт из STATS, который нужен слою (поля Protocol.AttackStats).
type FrontView = {
	attacker: number,
	target: number,
	power: number,
	mix: { number },
	supplied: boolean,
	fighting: boolean,
}

function FrontLayer.new(canvas: Frame, cs: ClientState): FrontLayer
	local cfg = Config.Render
	local active: { Sprite } = {}
	-- Пул спрайтов по типам: линия пересчитывается дважды в секунду, а объекты переиспользуются.
	local pool: { [string]: { Sprite } } = {}
	local effects: { Effect } = {}
	local effectPool: { Frame } = {}
	local lastScan = -math.huge
	local lastZoom = -1
	local rng = Random.new()
	-- Клетки линий фронтов с боем — там рвутся снаряды.
	local battleLines: { { number } } = {}
	local orange, red = Theme.color("Orange"), Theme.color("Red")

	local function colorOf(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end

	local function releaseAll()
		for _, s in active do
			s.root.Visible = false
			local list = pool[s.kind]
			if list == nil then
				list = {}
				pool[s.kind] = list
			end
			table.insert(list, s)
		end
		table.clear(active)
	end

	local function newSprite(kind: string): Sprite
		local root = Instance.new("Frame")
		root.Name = "Unit" .. kind
		root.AnchorPoint = Vector2.new(0.5, 1)
		root.BackgroundTransparency = 1
		root.ZIndex = 6
		local parts: { Frame } = {}
		local strokes: { UIStroke } = {}
		for _, p in SHAPES[kind] or SHAPES.Infantry do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = 7
			f.Parent = root
			if not p.ink then
				local st = Instance.new("UIStroke")
				st.Thickness = 1
				st.Parent = f
				table.insert(strokes, st)
			else
				f.BackgroundColor3 = Theme.Colors.Backdrop
			end
			table.insert(parts, f)
		end
		root.Parent = canvas
		return { root = root, parts = parts, strokes = strokes, kind = kind, cell = 0, phase = 0 }
	end

	-- Спрайт из пула: цвет державы, обводка (красная — фронт без снабжения), размер под зум.
	local function place(kind: string, owner: number, cell: number, unsupplied: boolean, scale: number)
		local list = pool[kind]
		local s = if list ~= nil and #list > 0 then table.remove(list) :: Sprite else newSprite(kind)
		local color = colorOf(owner)
		local shape = SHAPES[kind] or SHAPES.Infantry
		for k, p in shape do
			local f = s.parts[k]
			if not p.ink then
				f.BackgroundColor3 = color
			end
			f.Position = UDim2.fromOffset(p.x * scale, p.y * scale)
			f.Size = UDim2.fromOffset(p.w * scale, p.h * scale)
		end
		for _, st in s.strokes do
			st.Color = if unsupplied then Theme.Colors.Alert else Theme.Colors.Backdrop
		end
		s.root.Size = UDim2.fromOffset(SPRITE_W * scale, SPRITE_H * scale)
		s.cell = cell
		s.phase = rng:NextNumber(0, math.pi * 2)
		s.root.Visible = true
		table.insert(active, s)
	end

	local kindAt = UnitSprites.kindAt
	local spread = UnitSprites.spread

	local function rescan(state: CameraState)
		releaseAll()
		table.clear(battleLines)
		local stats = cs.stats
		if stats == nil or not cs.hasSnapshot then
			return
		end
		-- Фронты с войсками: пара (атакующий, цель) → индекс фронта.
		local pairIndex: { [number]: number } = {}
		local fronts: { FrontView } = {}
		for _, a in stats.attacks do
			if a.power > 0 and a.attacker ~= a.target then
				table.insert(fronts, a)
				pairIndex[a.attacker * 65536 + a.target] = #fronts
			end
		end
		if #fronts == 0 then
			return
		end
		-- Один проход по видимым клеткам (на мелком зуме — с шагом): клетки атакующего у границы
		-- с целью и клетки цели напротив.
		local w, h = cs.width, cs.height
		local x0, y0, x1, y1 = CameraMath.visibleRect(state)
		local visible = (x1 - x0 + 1) * (y1 - y0 + 1)
		local stride = math.max(1, math.floor(math.sqrt(visible / 40000)))
		local attackerCells: { { number } } = {}
		local defenderCells: { { number } } = {}
		for k = 1, #fronts do
			attackerCells[k], defenderCells[k] = {}, {}
		end
		local function look(i: number, o: number, j: number)
			local p = ClientState.ownerAt(cs, j)
			if p == o then
				return
			end
			local k = pairIndex[o * 65536 + p]
			if k ~= nil then
				table.insert(attackerCells[k], i)
			end
			local back = pairIndex[p * 65536 + o]
			if back ~= nil then
				table.insert(defenderCells[back], i)
			end
		end
		for y = y0, y1, stride do
			for x = x0, x1, stride do
				local i = y * w + x
				local o = ClientState.ownerAt(cs, i)
				if o ~= 0 then
					-- По одному соседу на направление: клетка попадает в список не больше двух раз.
					if x + 1 < w then
						look(i, o, i + 1)
					end
					if y + 1 < h then
						look(i, o, i + w)
					end
					if x > 0 then
						look(i, o, i - 1)
					end
					if y > 0 then
						look(i, o, i - w)
					end
				end
			end
		end
		-- Расстановка с общим пределом спрайтов на экране.
		local budget = cfg.FrontSpritesTotal
		local perFront = math.min(cfg.FrontSpritesPerFront, math.max(4, math.floor(budget / #fronts)))
		local scale = UnitSprites.scaleFor(state.zoom)
		for k, a in fronts do
			-- Встречный фронт цели на этой границе: защитники идут его составом, иначе — пехота гарнизона.
			local counterIndex = pairIndex[a.target * 65536 + a.attacker]
			local counter = if counterIndex ~= nil then fronts[counterIndex] else nil
			local defenderStats = ClientState.statsOf(cs, a.target)
			local defended = counter == nil and defenderStats ~= nil and defenderStats.power > 0
			local nAttack = if defended then math.ceil(perFront * 0.65) else perFront
			local cellsA = spread(attackerCells[k], math.min(nAttack, budget))
			for idx, cell in cellsA do
				place(kindAt(a.mix, idx, #cellsA), a.attacker, cell, not a.supplied, scale)
			end
			budget -= #cellsA
			if defended then
				local cellsD = spread(defenderCells[k], math.min(perFront - nAttack, budget))
				for _, cell in cellsD do
					place(Types.LandUnits[1], a.target, cell, false, scale)
				end
				budget -= #cellsD
			end
			if a.fighting then
				local line = if #defenderCells[k] > 0 then defenderCells[k] else attackerCells[k]
				if #line > 0 then
					table.insert(battleLines, line)
				end
			end
		end
	end

	local function spawnEffect(cell: number, zoom: number, big: boolean, now: number)
		local f = table.remove(effectPool)
		if f == nil then
			local made = Instance.new("Frame")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.BorderSizePixel = 0
			made.ZIndex = 8
			made.Parent = canvas
			f = made
		end
		local frame = f :: Frame
		frame.BackgroundColor3 = if big then orange else Theme.Colors.Gold
		frame.BackgroundTransparency = 0
		local px = math.max(2, math.floor(zoom * (if big then 1.5 else 0.8)))
		frame.Size = UDim2.fromOffset(px, px)
		local cx, cy = cell % cs.width, cell // cs.width
		local left, top = CameraMath.cellEdge(zoom, cx), CameraMath.cellEdge(zoom, cy)
		local cw = math.max(1, CameraMath.cellEdge(zoom, cx + 1) - left)
		local ch = math.max(1, CameraMath.cellEdge(zoom, cy + 1) - top)
		frame.Position = UDim2.fromOffset(left + rng:NextInteger(0, cw), top + rng:NextInteger(0, ch))
		frame.Visible = true
		table.insert(effects, { frame = frame, born = now, life = if big then 0.45 else 0.12, big = big })
	end

	local effectDebt = 0
	local lastNow = os.clock()

	local function update(now: number, state: CameraState)
		local dt = math.clamp(now - lastNow, 0, 0.25)
		lastNow = now
		local zoom = state.zoom
		if now - lastScan >= cfg.FrontScanSec or zoom ~= lastZoom then
			lastScan = now
			lastZoom = zoom
			rescan(state)
		end
		-- Марш: лёгкое покачивание юнитов на пиксель вверх-вниз.
		local w = cs.width
		for _, s in active do
			local cx, cy = s.cell % w, s.cell // w
			local left = CameraMath.cellEdge(zoom, cx)
			local x = left + (CameraMath.cellEdge(zoom, cx + 1) - left) / 2
			local y = CameraMath.cellEdge(zoom, cy + 1) + math.floor(math.sin(now * 8 + s.phase) + 0.5)
			s.root.Position = UDim2.fromOffset(math.round(x), y)
		end
		-- Эффекты боя: выстрелы (мелкие золотые вспышки) и разрывы (оранжевые, растут, краснеют и гаснут).
		if #battleLines > 0 then
			effectDebt += dt * cfg.BattleEffectsPerSec * #battleLines
			while effectDebt >= 1 do
				effectDebt -= 1
				if #effects < cfg.BattleEffectsMax then
					local line = battleLines[rng:NextInteger(1, #battleLines)]
					spawnEffect(line[rng:NextInteger(1, #line)], zoom, rng:NextNumber() < 0.35, now)
				end
			end
		else
			effectDebt = 0
		end
		local k = 1
		while k <= #effects do
			local e = effects[k]
			local t = (now - e.born) / e.life
			if t >= 1 then
				e.frame.Visible = false
				table.insert(effectPool, e.frame)
				effects[k] = effects[#effects]
				effects[#effects] = nil
			else
				if e.big then
					local px = math.max(2, math.floor(zoom * (1.5 + t * 2)))
					e.frame.Size = UDim2.fromOffset(px, px)
					e.frame.BackgroundColor3 = if t < 0.4 then orange else red
				end
				e.frame.BackgroundTransparency = math.floor(t * 3) / 3
				k += 1
			end
		end
	end

	return { update = update }
end

return table.freeze(FrontLayer)
