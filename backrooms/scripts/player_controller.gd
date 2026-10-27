extends CharacterBody3D
class_name PlayerController
const Flood = preload("res://scripts/flood.gd")

# PlayerController: ходьба, бег, присед и намерение взгляда. Мышь двигает
# только look_yaw — это «куда игрок навёл», — а корпус доворачивается за ним
# с задержкой: направление движения берётся от корпуса, поэтому резкий
# разворот игрок проходит по дуге и теряет ход. Как снята камера — в
# bodycam_component.gd.

@export_group("Движение")
@export var walk_speed: float = 2.5
@export var sprint_speed: float = 5.0
@export var crouch_speed: float = 1.5
# Тяжёлые разгон и торможение: ход набирается за полсекунды, а после
# отпускания клавиш игрок ещё катится почти полметра
@export var acceleration: float = 4.5
@export var friction: float = 6.5
@export var gravity: float = 15.0
# Доворот корпуса за взглядом: 9 — корпус догоняет примерно за 0.25 с
@export var turn_response: float = 9.0
# Цена разворота: чем острее угол между курсом и намерением, тем меньше ход
@export var turn_drag: float = 0.3

@export_group("Взгляд")
@export var mouse_sensitivity: float = 0.003
@export var invert_y: bool = false
@export var sprint_toggle_mode: bool = false
@export var crouch_toggle_mode: bool = true

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var stamina = $StaminaComponent
@onready var bodycam: BodycamComponent = $BodycamComponent
@onready var footsteps = $FootstepComponent

var is_crouching: bool = false
var is_sprinting: bool = false
var strafe_input: float = 0.0
var sprint_toggle_state: bool = false
# Куда наведена мышь. Камера смотрит ровно сюда, корпус идёт следом
var look_yaw: float = 0.0
# Наклон взгляда: читает viewmodel, руками тянется за камерой
var camera_rotation_x: float = 0.0
var was_on_floor: bool = true
var prev_position: Vector3
var hidden_spot = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	look_yaw = rotation.y
	prev_position = global_position


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw -= event.relative.x * mouse_sensitivity
		var y_amount: float = event.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
		camera_rotation_x = clampf(camera_rotation_x - y_amount, -deg_to_rad(89), deg_to_rad(89))


func _physics_process(delta: float) -> void:
	if hidden_spot != null:
		_update_hidden(delta)
		return
	_process_crouch()
	_turn_body(delta)
	_process_movement(delta)
	var fall_speed: float = -velocity.y
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	# Приземление: просадка + громкий шаг, но только с реальной высоты
	if not was_on_floor and is_on_floor():
		bodycam.add_landing_impact(clampf(fall_speed / 10.0, 0.0, 1.0))
		if fall_speed > 1.5:
			footsteps.land()
	was_on_floor = is_on_floor()
	var displacement: Vector3 = global_position - prev_position
	displacement.y = 0.0
	prev_position = global_position
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	footsteps.update_footsteps(displacement.length(), horizontal_speed, is_sprinting, is_crouching)


func _turn_body(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, look_yaw, 1.0 - exp(-turn_response * delta))


func _process_crouch() -> void:
	if crouch_toggle_mode:
		if Input.is_action_just_pressed("crouch"):
			is_crouching = not is_crouching
			_apply_crouch_collision()
	else:
		var pressed: bool = Input.is_action_pressed("crouch")
		if pressed != is_crouching:
			is_crouching = pressed
			_apply_crouch_collision()


func _apply_crouch_collision() -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if not capsule:
		return
	if is_crouching:
		capsule.height = 1.15
		collision_shape.position.y = 0.575
	else:
		capsule.height = 1.8
		collision_shape.position.y = 0.9


func _process_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	strafe_input = input_dir.x
	# hold — пока зажат Shift; toggle — вкл/выкл (только в движении).
	var wants_sprint: bool
	if sprint_toggle_mode:
		if Input.is_action_just_pressed("sprint") and not is_crouching \
				and input_dir != Vector2.ZERO:
			sprint_toggle_state = not sprint_toggle_state
		if stamina.current_stamina <= 0.0:
			sprint_toggle_state = false
		wants_sprint = sprint_toggle_state and not is_crouching \
			and input_dir != Vector2.ZERO
	else:
		wants_sprint = Input.is_action_pressed("sprint") and not is_crouching \
			and input_dir != Vector2.ZERO
	if wants_sprint and stamina.can_start_sprint():
		is_sprinting = true
		stamina.drain(delta)
	else:
		is_sprinting = false
		stamina.regenerate(delta, is_crouching)
	var target_speed: float
	if is_crouching:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = sprint_speed
	else:
		target_speed = walk_speed
	target_speed *= stamina.speed_multiplier() * Flood.speed_at(global_position)
	# Экспоненциальное затухание вместо accel*delta — кадро-независимо
	if direction != Vector3.ZERO:
		target_speed *= _turn_slowdown(direction)
		var target_velocity := direction * target_speed
		var weight: float = 1.0 - exp(-acceleration * delta)
		velocity.x = lerp(velocity.x, target_velocity.x, weight)
		velocity.z = lerp(velocity.z, target_velocity.z, weight)
	else:
		var stop_weight: float = 1.0 - exp(-friction * delta)
		velocity.x = lerp(velocity.x, 0.0, stop_weight)
		velocity.z = lerp(velocity.z, 0.0, stop_weight)


# Пока вектор движения не совпал с намерением (а на финте он смотрит
# в другую сторону), ход падает: переложить вес мгновенно нельзя
func _turn_slowdown(direction: Vector3) -> float:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 0.5:
		return 1.0
	var align: float = flat.normalized().dot(direction)
	return clampf(1.0 - (1.0 - align) * turn_drag, 0.4, 1.0)

# Шум для слуха сущности (присед 3 м, шаг 8 м, бег 20 м; в укрытии — тишина).
func get_noise_radius() -> float:
	if hidden_spot != null or Vector2(velocity.x, velocity.z).length() < 0.5:
		return 0.0
	if is_crouching:
		return 3.0
	return 20.0 if is_sprinting else 8.0


func get_stamina_percent() -> float:
	return stamina.get_stamina_percent()


# Внешний приказ развернуться (шкаф разворачивает игрока к дверце): ведём
# и корпус, и намерение взгляда, иначе камера вернёт прежний курс
func face_yaw(yaw: float) -> void:
	rotation.y = yaw
	look_yaw = yaw


func set_hidden(spot) -> void:
	hidden_spot = spot
	velocity = Vector3.ZERO


func is_hidden() -> bool:
	return hidden_spot != null


# В шкафу дыхание выравнивается: тяжёлое выдаёт укрытие (entity_lockers.gd)
func _update_hidden(delta: float) -> void:
	velocity = Vector3.ZERO
	stamina.recover_hidden(delta)
