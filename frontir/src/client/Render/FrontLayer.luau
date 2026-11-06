--!strict
--[[
	FrontLayer — бой на линиях фронтов (GDD §6.7б).
	Сервер присылает фронты в STATS (стороны, сила, состав, точка удара, снабжение, идёт ли бой); где проходит
	линия, клиент видит сам по своей копии сетки. Раскладку юнитов даёт Shared.BattleLayout (та же, что в превью).

	- Раз в Render.FrontScanSec: линии фронтов в видимой области, сколько юнитов у каждой стороны (по силе),
	  куда им встать. Юниты не телепортируются: каждый идёт к своему месту, подкрепления выходят из тыла.
	- Стороны: войска фронта атакующего; напротив — войска встречного фронта или гарнизон защитника.
	  Между ними — ничейная полоса Render.Battle.NoMansLand клеток.
	- Пока идёт бой: пехота сходится к полосе и отходит, танки выезжают вперёд, артиллерия в тылу бьёт
	  снарядами по дуге; разрыв оставляет воронку, которая дымит Render.Battle.CraterSec секунд.
	- Сила стороны упала — часть её юнитов гибнет с пиксельным взрывом (на их место потом подходят новые,
	  если сила ещё позволяет).
	- Фронт без снабжения — юниты в красной обводке.
	Все кадры (юниты, снаряды, воронки, частицы) — из пулов; пределы — в Config.Render.Battle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleLayout = require(Shared:WaitForChild("BattleLayout"))
local CameraMath = require(Shared:WaitForChild("CameraMath"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local Config = require(Shared:WaitForChild("Config"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local Fog = require(Shared:WaitForChild("Fog"))
local MapDataModule = require(Shared:WaitForChild("MapData"))
local NationColors = require(Shared:WaitForChild("NationColors"))
local Types = require(Shared:WaitForChild("Types"))
local UnitSprites = require(Shared:WaitForChild("UnitSprites"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type ClientState = ClientState.ClientState
type CameraState = CameraMath.CameraState
type MapData = MapDataModule.MapData

local SHAPES = UnitSprites.Shapes
local SPRITE_W, SPRITE_H = UnitSprites.Width, UnitSprites.Height

type Unit = {
	root: Frame,
	shadow: Frame, -- тень под ногами (§15г)
	parts: { Frame },
	strokes: { UIStroke },
	kind: string,
	x: number, -- где стоит сейчас (клетки)
	y: number,
	tx: number, -- куда идёт
	ty: number,
	dx: number, -- шаг к врагу
	dy: number,
	phase: number,
	nextFire: number,
	firedAt: number,
	scale: number,
	flip: boolean,
}

type Side = {
	units: { Unit },
	owner: number,
	power: number,
	fighting: boolean,
	unsupplied: boolean,
	enemyKey: number?,
	seen: boolean,
}

type Particle = {
	frame: Frame,
	x: number,
	y: number,
	vx: number,
	vy: number,
	born: number,
	life: number,
	size0: number, -- в клетках
	size1: number,
	color0: Color3,
	color1: Color3,
	alpha0: number, -- прозрачность в начале
}

type Shell = { frame: Frame, x0: number, y0: number, x1: number, y1: number, born: number, flight: number }
type Crater = { frame: Frame, x: number, y: number, born: number, nextSmoke: number }

export type FrontLayer = {
	update: (now: number, state: CameraState) -> (),
}

-- Фронт из STATS, который нужен слою (поля Protocol.AttackStats).
type FrontView = {
	attacker: number,
	target: number,
	power: number,
	mix: { number },
	supplied: boolean,
	fighting: boolean,
	focus: number?,
}

local FrontLayer = {}

function FrontLayer.new(canvas: Frame, cs: ClientState, map: MapData): FrontLayer
	local cfg = Config.Render.Battle
	-- Телефон (этап 10в): меньше юнитов, частиц и воронок.
	local phone = RenderBudget.isPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local maxUnits = RenderBudget.limit("MaxUnitsOnScreen", phone)
	local maxParticles = RenderBudget.limit("MaxParticles", phone)
	local maxCraters = RenderBudget.limit("MaxCraters", phone)
	local rng = Random.new()
	local riverId = Types.Terrain.River
	local sides: { [number]: Side } = {}
	local unitPool: { [string]: { Unit } } = {}
	local framePool: { Frame } = {}
	local particles: { Particle } = {}
	local shells: { Shell } = {}
	local craters: { Crater } = {}
	local lastScan = -math.huge
	local lastZoom = -1
	local lastNow = os.clock()
	local flashDebt = 0
	local unitCount = 0

	local orange, red, gold = Theme.color("Orange"), Theme.color("Red"), Theme.Colors.Gold
	local smokeColor, craterColor = Theme.color("Mist"), Theme.color("Basalt")
	local ink = Theme.Colors.Backdrop

	local function ownerAt(i: number): number
		return ClientState.ownerAt(cs, i)
	end
	-- Туман (§6.11): юниты стоят только в клетках, которые видно.
	local function inSight(slots: { BattleLayout.Slot }): { BattleLayout.Slot }
		if cs.fog.all then
			return slots
		end
		local out: { BattleLayout.Slot } = {}
		local w, h = cs.width, cs.height
		for _, slot in slots do
			local x = math.clamp(math.floor(slot.x), 0, w - 1)
			local y = math.clamp(math.floor(slot.y), 0, h - 1)
			if Fog.isVisible(cs.fog, y * w + x) then
				table.insert(out, slot)
			end
		end
		return out
	end
	local function isRiver(i: number): boolean
		return MapDataModule.getTerrain(map, i) == riverId
	end

	local function colorOf(owner: number): Color3
		local ci = ClientState.colorIndexOf(cs, owner)
		if ci >= 1 then
			local c = NationColors.Colors[ci]
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return Theme.Colors.Muted
	end

	-- Пул простых квадратов (частицы, снаряды, воронки).
	local function takeFrame(z: number): Frame
		local f = table.remove(framePool)
		if f == nil then
			local made = Instance.new("Frame")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.BorderSizePixel = 0
			made.Parent = canvas
			f = made
		end
		local frame = f :: Frame
		frame.ZIndex = z
		frame.BackgroundTransparency = 0
		frame.Visible = true
		return frame
	end
	local function dropFrame(f: Frame)
		f.Visible = false
		table.insert(framePool, f)
	end

	-- Новый спрайт юнита (детали — Shared.UnitSprites).
	local function newUnit(kind: string): Unit
		local root = Instance.new("Frame")
		root.Name = "Unit" .. kind
		root.AnchorPoint = Vector2.new(0.5, 0.75)
		root.BackgroundTransparency = 1
		root.ZIndex = 6
		local parts: { Frame } = {}
		local strokes: { UIStroke } = {}
		-- Тень — мягкий тёмный овал под юнитом: юнит «стоит» на карте, а не плавает.
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow"
		shadow.BorderSizePixel = 0
		shadow.BackgroundColor3 = ink
		shadow.BackgroundTransparency = 0.55
		shadow.ZIndex = 6
		shadow.Parent = root
		local shadowCorner = Instance.new("UICorner")
		shadowCorner.CornerRadius = UDim.new(0.5, 0)
		shadowCorner.Parent = shadow
		for _, p in SHAPES[kind] or SHAPES.Infantry do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = 7
			f.Parent = root
			if p.ink then
				f.BackgroundColor3 = ink
			elseif p.shade == nil then
				-- Контур — только у основных деталей (у оттенков нет: иначе спрайт рябит линиями).
				local st = Instance.new("UIStroke")
				st.Thickness = 1
				st.Parent = f
				table.insert(strokes, st)
			end
			table.insert(parts, f)
		end
		root.Parent = canvas
		return {
			root = root,
			shadow = shadow,
			parts = parts,
			strokes = strokes,
			kind = kind,
			x = 0,
			y = 0,
			tx = 0,
			ty = 0,
			dx = 1,
			dy = 0,
			phase = 0,
			nextFire = 0,
			firedAt = -math.huge,
			scale = 0,
			flip = false,
		}
	end

	-- Размер и зеркало спрайта (смотрит на врага).
	local function shape(u: Unit, scale: number, flip: boolean)
		if u.scale == scale and u.flip == flip then
			return
		end
		u.scale, u.flip = scale, flip
		u.root.Size = UDim2.fromOffset(SPRITE_W * scale, SPRITE_H * scale)
		u.shadow.Position = UDim2.fromOffset(scale, (SPRITE_H - 1) * scale)
		u.shadow.Size = UDim2.fromOffset((SPRITE_W - 2) * scale, math.max(2, math.round(scale * 1.6)))
		for k, p in SHAPES[u.kind] or SHAPES.Infantry do
			local f = u.parts[k]
			local x = if flip then SPRITE_W - p.x - p.w else p.x
			f.Position = UDim2.fromOffset(x * scale, p.y * scale)
			f.Size = UDim2.fromOffset(p.w * scale, p.h * scale)
		end
	end

	local function setStroke(u: Unit, unsupplied: boolean)
		for _, st in u.strokes do
			st.Color = if unsupplied then Theme.Colors.Alert else ink
		end
	end

	local function takeUnit(kind: string, owner: number, unsupplied: boolean, now: number): Unit
		local list = unitPool[kind]
		local u = if list ~= nil and #list > 0 then table.remove(list) :: Unit else newUnit(kind)
		local color = colorOf(owner)
		local r, g, b = math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255)
		for k, p in SHAPES[kind] or SHAPES.Infantry do
			if not p.ink then
				u.parts[k].BackgroundColor3 = Color3.fromRGB(UnitSprites.shade(r, g, b, p.shade))
			end
		end
		setStroke(u, unsupplied)
		u.phase = rng:NextNumber(0, math.pi * 2)
		u.nextFire = now + rng:NextNumber(0, cfg.ArtilleryFireMaxSec)
		u.firedAt = -math.huge
		u.root.Visible = true
		unitCount += 1
		return u
	end

	local function dropUnit(u: Unit)
		u.root.Visible = false
		local list = unitPool[u.kind]
		if list == nil then
			list = {}
			unitPool[u.kind] = list
		end
		table.insert(list, u)
		unitCount -= 1
	end

	type Spark = {
		x: number,
		y: number,
		vx: number,
		vy: number,
		life: number,
		size0: number,
		size1: number,
		color0: Color3,
		color1: Color3,
		alpha0: number,
	}
	local function spawnParticle(p: Spark, now: number)
		if #particles >= maxParticles then
			return
		end
		local f = takeFrame(9)
		f.BackgroundColor3 = p.color0
		table.insert(particles, {
			frame = f,
			x = p.x,
			y = p.y,
			vx = p.vx,
			vy = p.vy,
			born = now,
			life = p.life,
			size0 = p.size0,
			size1 = p.size1,
			color0 = p.color0,
			color1 = p.color1,
			alpha0 = p.alpha0,
		})
	end

	-- Разрыв: растущий огненный квадрат и искры.
	local function explode(x: number, y: number, now: number)
		spawnParticle({
			x = x,
			y = y,
			vx = 0,
			vy = 0,
			life = 0.5,
			size0 = 0.8,
			size1 = 3.2,
			color0 = orange,
			color1 = red,
			alpha0 = 0,
		}, now)
		for _ = 1, 5 do
			local a = rng:NextNumber(0, math.pi * 2)
			local v = rng:NextNumber(2, 5)
			spawnParticle({
				x = x,
				y = y,
				vx = math.cos(a) * v,
				vy = math.sin(a) * v,
				life = rng:NextNumber(0.25, 0.5),
				size0 = 0.35,
				size1 = 0.2,
				color0 = gold,
				color1 = orange,
				alpha0 = 0,
			}, now)
		end
	end

	-- Воронка: тёмное пятно, дымит CraterSec секунд.
	local function addCrater(x: number, y: number, now: number)
		if #craters >= maxCraters then
			local oldest = table.remove(craters, 1) :: Crater
			dropFrame(oldest.frame)
		end
		local f = takeFrame(5)
		f.BackgroundColor3 = craterColor
		f.BackgroundTransparency = 0.2
		table.insert(craters, { frame = f, x = x, y = y, born = now, nextSmoke = now + 0.2 })
	end

	-- Гибель юнита: пиксельный разлёт цветом державы и огнём.
	local function killUnit(u: Unit, owner: number, now: number)
		local color = colorOf(owner)
		for k = 1, cfg.DeathSparks do
			local a = (k / cfg.DeathSparks) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local v = rng:NextNumber(1.5, 4)
			spawnParticle({
				x = u.x,
				y = u.y,
				vx = math.cos(a) * v,
				vy = math.sin(a) * v - 1,
				life = rng:NextNumber(0.35, 0.65),
				size0 = 0.45,
				size1 = 0.25,
				color0 = if k % 3 == 0 then color else orange,
				color1 = red,
				alpha0 = 0,
			}, now)
		end
		spawnParticle({
			x = u.x,
			y = u.y,
			vx = 0,
			vy = 0,
			life = 0.18,
			size0 = 0.6,
			size1 = 1.4,
			color0 = gold,
			color1 = orange,
			alpha0 = 0,
		}, now)
		dropUnit(u)
	end

	local function releaseSide(side: Side)
		for _, u in side.units do
			dropUnit(u)
		end
		table.clear(side.units)
	end

	type SideInfo = {
		owner: number,
		power: number,
		fighting: boolean,
		unsupplied: boolean,
		enemyKey: number?,
	}

	-- Привести юнитов стороны к раскладке slots. Сила упала — часть юнитов гибнет на месте.
	local function reconcile(key: number, slots: { BattleLayout.Slot }, info: SideInfo, now: number)
		local existing: Side? = sides[key]
		if existing ~= nil and existing.owner ~= info.owner then
			releaseSide(existing)
			existing = nil
		end
		local side: Side = existing
			or {
				units = {},
				owner = info.owner,
				power = info.power,
				fighting = info.fighting,
				unsupplied = info.unsupplied,
				enemyKey = info.enemyKey,
				seen = true,
			}
		sides[key] = side
		side.seen = true
		side.fighting, side.enemyKey = info.fighting, info.enemyKey
		-- Потери: гибнет такая же доля юнитов (случайные).
		if info.power < side.power and side.power > 0 and #side.units > 0 then
			local share = (side.power - info.power) / side.power * cfg.ChurnMul
			local kills = math.floor(share * #side.units + rng:NextNumber())
			for _ = 1, math.min(kills, #side.units) do
				local k = rng:NextInteger(1, #side.units)
				killUnit(side.units[k], info.owner, now)
				table.remove(side.units, k)
			end
		end
		side.power = info.power
		if side.unsupplied ~= info.unsupplied then
			side.unsupplied = info.unsupplied
			for _, u in side.units do
				setStroke(u, info.unsupplied)
			end
		end
		-- Лишние (не по потерям — например, сменился зум) уходят тихо.
		while #side.units > #slots do
			dropUnit(table.remove(side.units) :: Unit)
		end
		for k, slot in slots do
			local u = side.units[k]
			if u ~= nil and u.kind ~= slot.kind then
				-- Состав сменился: юнит другого типа встаёт на то же место.
				local x, y = u.x, u.y
				dropUnit(u)
				u = takeUnit(slot.kind, info.owner, info.unsupplied, now)
				u.x, u.y = x, y
				side.units[k] = u
			elseif u == nil then
				if unitCount >= maxUnits then
					break
				end
				-- Подкрепление выходит из тыла.
				u = takeUnit(slot.kind, info.owner, info.unsupplied, now)
				u.x = slot.x - slot.dx * cfg.ReinforceFromCells * 0.5
				u.y = slot.y - slot.dy * cfg.ReinforceFromCells * 0.5
				side.units[k] = u
			end
			local unit = u :: Unit
			unit.tx, unit.ty, unit.dx, unit.dy = slot.x, slot.y, slot.dx, slot.dy
		end
	end

	local function rescan(state: CameraState, now: number)
		for _, side in sides do
			side.seen = false
		end
		local stats = cs.stats
		if stats ~= nil and cs.hasSnapshot then
			local fronts: { FrontView } = {}
			local pairIndex: { [number]: number } = {}
			for _, a in stats.attacks do
				-- Скрытая мощь (§6.11а): сила < 0 — грубая оценка, юниты рисуются по модулю.
				if math.abs(a.power) > 0 and a.target ~= 0 and a.attacker ~= a.target then
					table.insert(fronts, a)
					pairIndex[a.attacker * 65536 + a.target] = #fronts
				end
			end
			if #fronts > 0 then
				local w, h = cs.width, cs.height
				local x0, y0, x1, y1 = CameraMath.visibleRect(state)
				local visible = (x1 - x0 + 1) * (y1 - y0 + 1)
				local stride = math.max(1, math.floor(math.sqrt(visible / 40000)))
				local rect = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
				local lineA, lineD = BattleLayout.scan(ownerAt, isRiver, w, h, rect, stride, pairIndex, #fronts)
				-- Сколько фронтов против каждой страны: её гарнизон делится между ними.
				local against: { [number]: number } = {}
				for _, a in fronts do
					against[a.target] = (against[a.target] or 0) + 1
				end
				-- Предел юнитов делят только фронты, которые видны на экране.
				local visibleFronts = 0
				for k = 1, #fronts do
					if #lineA[k] > 0 or #lineD[k] > 0 then
						visibleFronts += 1
					end
				end
				local cap = math.max(4, math.floor(maxUnits / (math.max(1, visibleFronts) * 2)))
				for k, a in fronts do
					local key = a.attacker * 65536 + a.target
					local counterKey = a.target * 65536 + a.attacker
					local hasCounter = pairIndex[counterKey] ~= nil
					if #lineA[k] > 0 then
						local n = math.min(BattleLayout.unitsFor(math.abs(a.power)), cap)
						local slots =
							inSight(BattleLayout.place(lineA[k], n, a.mix, a.focus, ownerAt, a.attacker, w, h))
						reconcile(key, slots, {
							owner = a.attacker,
							power = math.abs(a.power),
							fighting = a.fighting,
							unsupplied = not a.supplied,
							enemyKey = if hasCounter then counterKey else -key,
						}, now)
					end
					-- Защитники: встречный фронт рисуется сам, иначе — доля гарнизона цели.
					local def = ClientState.statsOf(cs, a.target)
					if not hasCounter and def ~= nil and math.abs(def.power) > 0 and #lineD[k] > 0 then
						local share = math.abs(def.power) / math.max(1, against[a.target] or 1)
						local n = math.min(BattleLayout.unitsFor(share), cap)
						local slots = inSight(BattleLayout.place(lineD[k], n, def.mix, nil, ownerAt, a.target, w, h))
						reconcile(-key, slots, {
							owner = a.target,
							power = share,
							fighting = a.fighting,
							unsupplied = false,
							enemyKey = key,
						}, now)
					end
				end
			end
		end
		for key, side in sides do
			if not side.seen then
				releaseSide(side)
				sides[key] = nil
			end
		end
	end

	-- Залп артиллерии: снаряд по дуге в случайного юнита врага (или за ничейную полосу).
	local function fire(u: Unit, enemy: Side?, now: number)
		local tx, ty
		if enemy ~= nil and #enemy.units > 0 then
			local target = enemy.units[rng:NextInteger(1, #enemy.units)]
			tx, ty = target.x + rng:NextNumber(-1, 1), target.y + rng:NextNumber(-1, 1)
		else
			local reach = cfg.ArtilleryBack + cfg.NoMansLand + rng:NextNumber(0, 3)
			tx, ty = u.tx + u.dx * reach, u.ty + u.dy * reach
		end
		local f = takeFrame(8)
		f.BackgroundColor3 = ink
		table.insert(shells, {
			frame = f,
			x0 = u.x + u.dx * 0.5,
			y0 = u.y + u.dy * 0.5 - 0.4,
			x1 = tx,
			y1 = ty,
			born = now,
			flight = cfg.ShellFlightSec * rng:NextNumber(0.85, 1.15),
		})
		u.firedAt = now
		spawnParticle({
			x = u.x + u.dx * 0.6,
			y = u.y + u.dy * 0.6 - 0.4,
			vx = 0,
			vy = -0.5,
			life = 0.15,
			size0 = 0.6,
			size1 = 1.0,
			color0 = gold,
			color1 = orange,
			alpha0 = 0,
		}, now)
	end

	local function placeFrame(f: Frame, x: number, y: number, size: number, zoom: number)
		local px = math.max(1, math.floor(size * zoom + 0.5))
		f.Size = UDim2.fromOffset(px, px)
		f.Position = UDim2.fromOffset(math.round(x * zoom), math.round(y * zoom))
	end

	local function update(now: number, state: CameraState)
		local dt = math.clamp(now - lastNow, 0, 0.25)
		lastNow = now
		local zoom = state.zoom
		if now - lastScan >= Config.Render.FrontScanSec or zoom ~= lastZoom then
			lastScan = now
			lastZoom = zoom
			rescan(state, now)
		end
		local scale = UnitSprites.scaleFor(zoom)
		local step = cfg.UnitMoveCellsPerSec * dt
		local shooters: { Unit } = {}

		for _, side in sides do
			for _, u in side.units do
				-- Идёт к своему месту.
				local ddx, ddy = u.tx - u.x, u.ty - u.y
				local dist = math.sqrt(ddx * ddx + ddy * ddy)
				local moving = dist > 0.05
				if dist <= step then
					u.x, u.y = u.tx, u.ty
				else
					u.x += ddx / dist * step
					u.y += ddy / dist * step
				end
				-- В бою: пехота сходится и отходит, танки выезжают вперёд, артиллерия стреляет и откатывается.
				local adv = 0
				if side.fighting then
					if u.kind == "Artillery" then
						adv = -0.35 * math.max(0, 1 - (now - u.firedAt) / 0.35)
						if now >= u.nextFire then
							u.nextFire = now + rng:NextNumber(cfg.ArtilleryFireMinSec, cfg.ArtilleryFireMaxSec)
							fire(u, if side.enemyKey ~= nil then sides[side.enemyKey] else nil, now)
						end
					else
						local amp = if u.kind == "Tanks" then cfg.TankAdvance else cfg.InfantryAdvance
						local speed = if u.kind == "Tanks" then 0.7 else 1.6
						adv = amp * (0.5 + 0.5 * math.sin(now * speed + u.phase))
						table.insert(shooters, u)
					end
				end
				local bob = if moving then math.floor(math.sin(now * 10 + u.phase) + 0.5) else 0
				shape(u, scale, u.dx < 0)
				u.root.Position =
					UDim2.fromOffset(math.round((u.x + u.dx * adv) * zoom), math.round((u.y + u.dy * adv) * zoom) + bob)
			end
		end

		-- Вспышки выстрелов пехоты и танков.
		if #shooters > 0 then
			flashDebt += dt * cfg.RifleFlashesPerSec * math.max(1, #shooters / 8)
			while flashDebt >= 1 do
				flashDebt -= 1
				local u = shooters[rng:NextInteger(1, #shooters)]
				spawnParticle({
					x = u.x + u.dx * 0.9,
					y = u.y + u.dy * 0.9 - 0.3,
					vx = 0,
					vy = 0,
					life = 0.1,
					size0 = 0.4,
					size1 = 0.5,
					color0 = gold,
					color1 = gold,
					alpha0 = 0,
				}, now)
			end
		else
			flashDebt = 0
		end

		-- Снаряды по дуге.
		local k = 1
		while k <= #shells do
			local sh = shells[k]
			local t = (now - sh.born) / sh.flight
			if t >= 1 then
				explode(sh.x1, sh.y1, now)
				addCrater(sh.x1, sh.y1, now)
				dropFrame(sh.frame)
				shells[k] = shells[#shells]
				shells[#shells] = nil
			else
				local range = math.sqrt((sh.x1 - sh.x0) ^ 2 + (sh.y1 - sh.y0) ^ 2)
				local x = sh.x0 + (sh.x1 - sh.x0) * t
				local y = sh.y0 + (sh.y1 - sh.y0) * t - cfg.ShellArc * range * 4 * t * (1 - t)
				placeFrame(sh.frame, x, y, 0.35, zoom)
				k += 1
			end
		end

		-- Воронки дымят и гаснут.
		k = 1
		while k <= #craters do
			local c = craters[k]
			local age = now - c.born
			if age >= cfg.CraterSec then
				dropFrame(c.frame)
				table.remove(craters, k)
			else
				local fade = math.clamp((age - (cfg.CraterSec - 3)) / 3, 0, 1)
				c.frame.BackgroundTransparency = 0.2 + 0.8 * math.floor(fade * 4) / 4
				placeFrame(c.frame, c.x, c.y, 1.6, zoom)
				if now >= c.nextSmoke then
					c.nextSmoke = now + cfg.SmokeEverySec * rng:NextNumber(0.7, 1.3)
					spawnParticle({
						x = c.x + rng:NextNumber(-0.4, 0.4),
						y = c.y,
						vx = rng:NextNumber(-0.2, 0.2),
						vy = -0.7,
						life = cfg.SmokeLifeSec,
						size0 = 1.0,
						size1 = 2.6,
						color0 = smokeColor,
						color1 = smokeColor,
						alpha0 = 0.35 + 0.5 * fade,
					}, now)
				end
				k += 1
			end
		end

		-- Частицы: летят, растут, гаснут ступенями (пиксельный стиль).
		k = 1
		while k <= #particles do
			local p = particles[k]
			local t = (now - p.born) / p.life
			if t >= 1 then
				dropFrame(p.frame)
				particles[k] = particles[#particles]
				particles[#particles] = nil
			else
				p.x += p.vx * dt
				p.y += p.vy * dt
				p.frame.BackgroundColor3 = if t < 0.5 then p.color0 else p.color1
				p.frame.BackgroundTransparency = p.alpha0 + (1 - p.alpha0) * math.floor(t * 4) / 4
				placeFrame(p.frame, p.x, p.y, p.size0 + (p.size1 - p.size0) * t, zoom)
				k += 1
			end
		end
	end

	return { update = update }
end

return table.freeze(FrontLayer)
