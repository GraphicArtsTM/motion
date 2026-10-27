extends CharacterBody3D

# Entity: хозяин лабиринта. Бродит, слышит шаги и звон банок, видит игрока
# в конусе, преследует. Чувства — entity_senses.gd, путь — entity_navigator.gd,
# шаг — entity_motion.gd, хватка — entity_grab.gd, поиск и обход шкафов —
# entity_search.gd и entity_lockers.gd. Потеряв игрока из виду, бежит не на последнюю точку, а
# туда, куда тот уходил. Когда прийти и когда отступить, подсказывает
# режиссёр напряжения (entity_director.gd).

const Navigator = preload("res://scripts/entity_navigator.gd")
const EntitySenses = preload("res://scripts/entity_senses.gd")
const EntityRelocator = preload("res://scripts/entity_relocator.gd")
const PropEntity = preload("res://scripts/prop_entity.gd")
const EntityGrab = preload("res://scripts/entity_grab.gd")
const EntityMotion = preload("res://scripts/entity_motion.gd")
const EntityLockers = preload("res://scripts/entity_lockers.gd")
const EntitySearch = preload("res://scripts/entity_search.gd")
const EntityPredict = preload("res://scripts/entity_predict.gd")

enum State { WANDER, INVESTIGATE, CHASE, SEARCH }

const REPATH_INTERVAL: float = 0.3
const MEMORY_TIME: float = 5.0
const RELOCATE_DISTANCE: float = 100.0
# Упреждение: на сколько секунд хода игрока вперёд, не дальше 3 клеток
const LEAD_TIME: float = 1.6
const LEAD_CELLS: int = 3

@export var chunk_manager_path: NodePath = NodePath("../ChunkManager")
@export var player_path: NodePath = NodePath("../Player")
@export var hud_path: NodePath = NodePath("../HUD")

var state := State.WANDER
var player = null
var hud = null
var chunk_manager = null
var senses = null
var grab = null
var lockers = null
var rng := RandomNumberGenerator.new()
var path: Array = []
var repath_timer: float = 0.0
var memory_timer: float = 0.0
var search_timer: float = 0.0
var idle_timer: float = 0.0
var last_seen := Vector3.ZERO
var prev_cell := Vector2i.MAX
var placed: bool = false
# Как игрок двигался, когда его видели последний раз, и видно ли его сейчас
var seen_velocity := Vector3.ZERO
var in_sight: bool = false


func _ready() -> void:
	rng.randomize()
	player = get_node_or_null(player_path)
	hud = get_node_or_null(hud_path)
	chunk_manager = get_node_or_null(chunk_manager_path)
	senses = EntitySenses.new(self, player)
	grab = EntityGrab.new(self, player, senses)
	lockers = EntityLockers.new(self, player)
	add_child(PropEntity.build_entity())
	add_child(PropEntity.entity_collider())


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if not placed:
		placed = _place_far()
	repath_timer -= delta
	memory_timer -= delta
	_keep_pressure()
	grab.tick(delta, state == State.CHASE)
	_sense()
	_step_state(delta)
	EntityMotion.walk(self, delta)
	_try_catch()


func _sense() -> void:
	# Видел, как игрок залез в шкаф: идёт к шкафу, приманки не слушает
	if grab.hunting_spot():
		last_seen = grab.spot_target()
		memory_timer = MEMORY_TIME
		state = State.CHASE
		return
	var what: Dictionary = senses.perceive()
	var seen: bool = bool(what.get("seen", false))
	if in_sight and not seen and state == State.CHASE:
		_lead_lost_target()
	in_sight = seen
	if what.is_empty():
		return
	var prev_target: Vector2i = Navigator.world_to_cell(last_seen)
	last_seen = what["pos"]
	if seen:
		grab.saw_player()
		seen_velocity = player.velocity
		memory_timer = MEMORY_TIME
		if state != State.CHASE:
			state = State.CHASE
			repath_timer = 0.0
		return
	# Приманка громче шагов и уводит даже из погони, а свои шаги в погоне
	# её не отменяют — только продлевают память.
	if state == State.CHASE and not what["bait"]:
		memory_timer = MEMORY_TIME
		return
	# Шаги слышны каждый кадр: новый путь — только если звук ушёл в другую клетку
	if state != State.INVESTIGATE or Navigator.world_to_cell(last_seen) != prev_target:
		repath_timer = 0.0
	state = State.INVESTIGATE


# Игрок скрылся за углом: цель — не последняя точка, а куда он бежал,
# по коридору до первой развилки (entity_predict.gd)
func _lead_lost_target() -> void:
	var cells: int = mini(LEAD_CELLS, ceili(seen_velocity.length() * LEAD_TIME / Navigator.CELL))
	if cells <= 0:
		return
	last_seen = EntityPredict.project(chunk_manager, last_seen, seen_velocity, cells)
	repath_timer = 0.0


func _step_state(delta: float) -> void:
	if state == State.CHASE or state == State.INVESTIGATE:
		if state == State.CHASE and memory_timer <= 0.0:
			EntitySearch.begin(self)
		elif path.is_empty() or repath_timer <= 0.0:
			path = Navigator.path_to(chunk_manager, global_position, last_seen, prev_cell)
			repath_timer = REPATH_INTERVAL
			if path.is_empty() and state == State.INVESTIGATE:
				EntitySearch.begin(self, 2.5)
		return
	if state == State.SEARCH:
		EntitySearch.step(self, delta)
		return
	# WANDER: дошёл — постоял, потом новый маршрут в дальний угол
	if path.is_empty():
		idle_timer -= delta
		if idle_timer <= 0.0:
			path = Navigator.path_in_band(chunk_manager, global_position,
				global_position, 18.0, 40.0, rng)
			if path.is_empty():
				idle_timer = 1.0


# Подсказка режиссёра: «где-то там» — бродячая сущность идёт проверить
func hear_rumor(pos: Vector3) -> void:
	if state != State.WANDER:
		return
	last_seen = pos
	state = State.INVESTIGATE
	repath_timer = 0.0


# Передышка после погони: уходит прочь от игрока
func retreat() -> void:
	if state == State.WANDER:
		path = Navigator.path_in_band(chunk_manager, global_position, player.global_position, 30.0, 45.0, rng)
		idle_timer = 4.0


func _try_catch() -> void:
	var reason: String = grab.check()
	if reason.is_empty():
		reason = lockers.verdict
	if reason.is_empty():
		return
	if hud and hud.has_method("show_death"):
		hud.show_death(reason)
	set_physics_process(false)


# Сущность нельзя «потерять»: далеко ушла или её клетку выгрузили — переброс ближе к игроку.
# Пока первый переброс не удался, сюда не заходим: его уже пробует _physics_process.
func _keep_pressure() -> void:
	if state == State.CHASE or not placed:
		return
	var far: bool = global_position.distance_to(player.global_position) > RELOCATE_DISTANCE
	if far or not Navigator.is_loaded(chunk_manager, Navigator.world_to_cell(global_position)):
		_place_far()


func _place_far() -> bool:
	if not EntityRelocator.place(self, chunk_manager, player, senses, rng):
		return false
	prev_cell = Vector2i.MAX
	path = []
	return true
