extends CharacterBody3D

# Entity: хозяин лабиринта. Бродит, слышит шаги и звон банок, видит игрока
# в конусе, преследует, убивает в упор. Чувства — entity_senses.gd, путь — entity_navigator.gd.

const Navigator = preload("res://scripts/entity_navigator.gd")
const EntitySenses = preload("res://scripts/entity_senses.gd")
const EntityRelocator = preload("res://scripts/entity_relocator.gd")
const PropEntity = preload("res://scripts/prop_entity.gd")

enum State { WANDER, INVESTIGATE, CHASE, SEARCH }

const WANDER_SPEED: float = 1.35
const INVESTIGATE_SPEED: float = 2.3
const CHASE_SPEED: float = 4.4
const CATCH_DISTANCE: float = 1.35
const REPATH_INTERVAL: float = 0.3
const MEMORY_TIME: float = 5.0
const SEARCH_TIME: float = 6.0
const RELOCATE_DISTANCE: float = 100.0
const TURN_SPEED: float = 7.0
const DREAD_RANGE: float = 18.0
const WAYPOINT_EPS: float = 0.55

@export var chunk_manager_path: NodePath = NodePath("../ChunkManager")
@export var player_path: NodePath = NodePath("../Player")
@export var hud_path: NodePath = NodePath("../HUD")

var state := State.WANDER
var player = null
var hud = null
var chunk_manager = null
var senses = null
var rng := RandomNumberGenerator.new()
var path: Array = []
var repath_timer: float = 0.0
var memory_timer: float = 0.0
var search_timer: float = 0.0
var idle_timer: float = 0.0
var last_seen := Vector3.ZERO
var prev_cell := Vector2i.MAX
var placed: bool = false


func _ready() -> void:
	rng.randomize()
	player = get_node_or_null(player_path)
	hud = get_node_or_null(hud_path)
	chunk_manager = get_node_or_null(chunk_manager_path)
	senses = EntitySenses.new(self, player)
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
	_sense()
	_step_state(delta)
	_walk(delta)
	_try_catch()


func _process(_delta: float) -> void:
	if not placed or hud == null or player == null or not hud.has_method("set_dread"):
		return
	var dist := global_position.distance_to(player.global_position)
	var dread := clampf(1.0 - dist / DREAD_RANGE, 0.0, 1.0)
	var floor_dread := 0.5 if state == State.CHASE else (0.22 if state != State.WANDER else 0.0)
	hud.set_dread(maxf(dread, floor_dread))


func _sense() -> void:
	var what: Dictionary = senses.perceive()
	if what.is_empty():
		return
	last_seen = what["pos"]
	if what["seen"]:
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
	state = State.INVESTIGATE
	repath_timer = 0.0


func _step_state(delta: float) -> void:
	if state == State.CHASE or state == State.INVESTIGATE:
		if state == State.CHASE and memory_timer <= 0.0:
			_begin_search()
		elif path.is_empty() or repath_timer <= 0.0:
			path = Navigator.path_to(chunk_manager, global_position, last_seen, prev_cell)
			repath_timer = REPATH_INTERVAL
			if path.is_empty() and state == State.INVESTIGATE:
				_begin_search(2.5)
		return
	if state == State.SEARCH:
		search_timer -= delta
		if search_timer <= 0.0:
			state = State.WANDER
			idle_timer = 0.0
			path = []
		elif path.is_empty():
			path = Navigator.path_in_band(chunk_manager, global_position,
				last_seen, 4.0, 13.0, rng)
		return
	# WANDER: дошёл — постоял, потом новый маршрут в дальний угол
	if path.is_empty():
		idle_timer -= delta
		if idle_timer <= 0.0:
			path = Navigator.path_in_band(chunk_manager, global_position,
				global_position, 18.0, 40.0, rng)
			if path.is_empty():
				idle_timer = 1.0


func _begin_search(seconds: float = SEARCH_TIME) -> void:
	state = State.SEARCH
	search_timer = seconds
	path = Navigator.path_in_band(chunk_manager, global_position, last_seen,
		1.0, 10.0, rng)


func _speed() -> float:
	match state:
		State.CHASE: return CHASE_SPEED
		State.INVESTIGATE: return INVESTIGATE_SPEED
		_: return WANDER_SPEED


func _walk(delta: float) -> void:
	var desired := Vector3.ZERO
	while path.size() > 0:
		var wp: Vector3 = Navigator.cell_to_world(path[0])
		var to_wp := wp - global_position
		to_wp.y = 0.0
		if to_wp.length() < WAYPOINT_EPS:
			prev_cell = path[0]
			path.pop_front()
			continue
		desired = to_wp.normalized()
		break
	if desired == Vector3.ZERO and state != State.WANDER and state != State.SEARCH \
			and last_seen.distance_to(global_position) > WAYPOINT_EPS \
			and senses.line_clear(senses.eye_position(), last_seen + Vector3(0, 1.1, 0)):
		desired = Vector3(last_seen.x - global_position.x, 0.0,
			last_seen.z - global_position.z).normalized()
	var speed := _speed()
	velocity.x = desired.x * speed
	velocity.z = desired.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 14.0 * delta
	move_and_slide()
	if desired != Vector3.ZERO:
		var yaw := atan2(-desired.x, -desired.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _try_catch() -> void:
	if not placed or player.is_hidden() or global_position.distance_to(player.global_position) > CATCH_DISTANCE:
		return
	if not senses.line_clear(senses.eye_position(),
			player.global_position + Vector3(0, 1.1, 0)):
		return
	if hud and hud.has_method("show_death"):
		hud.show_death("Оно нашло тебя. Не надо было бежать.")
	set_physics_process(false)
	set_process(false)


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
