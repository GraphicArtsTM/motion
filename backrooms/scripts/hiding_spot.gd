extends Node3D

# HidingSpot: шкаф-укрытие от сущности. F рядом — залезть
# (движение блокируется, шум глушится), F внутри — вылезти.
# Сущность проверяет player.is_hidden(): в шкафу игрок невидим и неслышим.

const PropLocker = preload("res://scripts/prop_locker.gd")

var occupied: bool = false
var player_near: bool = false
var player_ref = null
var hud_ref = null

const STATE_IDLE := 0
const STATE_ENTERING := 1
const STATE_HIDDEN := 2
const STATE_EXITING := 3
const ENTER_TIME := 0.55
const EXIT_TIME := 0.4
const DOOR_OPEN_ANGLE := -1.8
const DOOR_SPEED := 8.0

var state := STATE_IDLE
var seq_t := 0.0
var seq_from := Vector3.ZERO
var door_hinge: Node3D = null


func setup(player, hud) -> void:
	player_ref = player
	hud_ref = hud


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_update_door(delta)
	if player_ref == null:
		return
	if state == STATE_ENTERING:
		seq_t += delta
		var k := smoothstep(0.0, 1.0, minf(seq_t / ENTER_TIME, 1.0))
		player_ref.global_position = seq_from.lerp(hide_global_position(), k)
		if seq_t >= ENTER_TIME:
			state = STATE_HIDDEN
		return
	if state == STATE_EXITING:
		seq_t += delta
		var k := smoothstep(0.0, 1.0, minf(seq_t / EXIT_TIME, 1.0))
		player_ref.global_position = seq_from.lerp(_exit_position(), k)
		if seq_t >= EXIT_TIME:
			_finish_exit()
		return
	if not player_near:
		return
	if Input.is_action_just_pressed("interact"):
		if state == STATE_HIDDEN:
			_begin_exit()
		elif state == STATE_IDLE and not player_ref.is_hidden():
			_enter_hide()


# Мгновенный выброс (выгрузка чанка) — без анимации
func _exit_hide() -> void:
	occupied = false
	state = STATE_IDLE
	if door_hinge:
		door_hinge.rotation.y = 0.0
	if player_ref:
		player_ref.global_position = _exit_position()
		player_ref.set_hidden(null)
	if hud_ref:
		hud_ref.hide_hint()


func hide_global_position() -> Vector3:
	return global_position


func _enter_hide() -> void:
	occupied = true
	state = STATE_ENTERING
	seq_t = 0.0
	seq_from = player_ref.global_position
	# Дверца у шкафа на локальной +Z, а взгляд игрока — вдоль -Z:
	# разворачиваем на пол-оборота, иначе смотрим в заднюю стенку.
	player_ref.face_yaw(global_rotation.y + PI)
	player_ref.set_hidden(self)
	if hud_ref:
		hud_ref.show_hint("F — выйти")


func _begin_exit() -> void:
	state = STATE_EXITING
	seq_t = 0.0
	seq_from = player_ref.global_position


func _finish_exit() -> void:
	occupied = false
	state = STATE_IDLE
	player_ref.global_position = _exit_position()
	player_ref.set_hidden(null)
	if hud_ref:
		hud_ref.hide_hint()


func _exit_position() -> Vector3:
	var forward := global_transform.basis.z
	forward.y = 0.0
	return global_position + forward.normalized() * 1.4


func _update_door(delta: float) -> void:
	if door_hinge == null:
		return
	var target := 0.0
	if state == STATE_ENTERING or state == STATE_EXITING:
		target = DOOR_OPEN_ANGLE
	door_hinge.rotation.y = move_toward(door_hinge.rotation.y, target, DOOR_SPEED * delta)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_near = true
		if hud_ref and not occupied and player_ref and not player_ref.is_hidden():
			hud_ref.show_hint("F — спрятаться")


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_near = false
		if hud_ref and not occupied:
			hud_ref.hide_hint()


func _build() -> void:
	var built: Dictionary = PropLocker.build_locker()
	add_child(built["root"])
	door_hinge = built["hinge"] as Node3D

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	shape.shape = sphere
	shape.position.y = 1.2
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)
