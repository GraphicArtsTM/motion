extends Node
class_name BodycamComponent

# Bodycam: камера привинчена к груди и живёт своей жизнью — высота, качка шага,
# инерция разгона, крен, наклон корпуса, просадка приземления, дыхание и поле
# зрения. Куда она смотрит — camera_look.gd, чем видит — camera_lens.gd.

@export var player_path: NodePath
@export var camera_root_path: NodePath
@export var camera_path: NodePath
@export var footsteps_path: NodePath

@export_group("Высота")
# Грудь, а не глаза: мир читается ниже, а сущность кажется выше и страшнее
@export var stand_height: float = 1.35
@export var crouch_height: float = 0.85
@export var height_speed: float = 8.0

@export_group("Поле зрения")
@export var base_fov: float = 90.0
# Прибавка на разгоне, а не абсолютный угол: ползунок «Поле зрения» даёт
# 75–100, и фиксированные 95 при 100 сужали кадр на бегу вместо расширения
@export var sprint_fov_bonus: float = 5.0
@export var fov_speed: float = 3.5

@export_group("Качка")
# Частоту качки не задаём: её задаёт сам шаг (длина шага в footstep_component),
# поэтому камера, звук шагов и руки качаются в одном ритме
@export var walk_amplitude: float = 0.045
@export var sprint_amplitude: float = 0.10
@export var crouch_share: float = 0.5
@export var step_roll: float = 0.02
# Ползунок «тряска камеры»: 0 — камера приклеена жёстко, гаснет и смаз кадра
@export var shake_strength: float = 1.0

@export_group("Инерция")
@export var inertia_scale: float = 0.004
@export var inertia_limit: float = 0.09

@export_group("Крен и наклон")
@export var strafe_roll: float = 0.02
@export var turn_roll: float = 0.045
@export var lean_offset: float = 0.26
@export var lean_roll: float = 0.17
@export var lean_speed: float = 5.0

@export_group("Приземление")
@export var dip_stiffness: float = 90.0
@export var dip_damping: float = 10.0
@export var dip_impulse: float = 1.2

@onready var player: PlayerController = get_node_or_null(player_path) as PlayerController
@onready var camera_root: Node3D = get_node_or_null(camera_root_path) as Node3D
@onready var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var footsteps: FootstepComponent = get_node_or_null(footsteps_path) as FootstepComponent

var height: float = 0.0
var current_fov: float = 90.0
var dip := Vector2.ZERO
var inertia := Vector2.ZERO  # x — влево/вправо, y — вперёд/назад в кадре
# В Vector2 места под скорость нет, поэтому пружина инерции — на каждую ось
var inertia_spring_x := Vector2.ZERO
var inertia_spring_y := Vector2.ZERO
var lean: float = 0.0
var roll: float = 0.0
var walk_fade: float = 0.0  # 0 — стоим или толкаемся в стену, 1 — идём в силу
var breath: float = 0.0
var tired: float = 0.35
var prev_body_yaw: float = 0.0
var smooth_velocity := Vector3.ZERO
var prev_velocity := Vector3.ZERO


func _ready() -> void:
	height = stand_height
	current_fov = base_fov
	if player:
		prev_body_yaw = player.rotation.y
	if camera_root:
		camera_root.position.y = height
	if camera:
		camera.fov = current_fov


func _process(delta: float) -> void:
	if player == null or camera_root == null or camera == null:
		return
	# Рывок кадра не должен раскачивать пружины — иначе камера «взрывается»
	var step: float = minf(delta, 0.05)
	_update_height(step)
	_update_body(step)
	_update_roll(delta, step)
	_update_lean(step)
	_update_lens(step)


# Высота груди, в приседе ниже; просадка приземления — пружина к нулю
func _update_height(step: float) -> void:
	var target: float = crouch_height if player.is_crouching else stand_height
	height = lerpf(height, target, clampf(height_speed * step, 0.0, 1.0))
	dip = _spring(dip, 0.0, dip_stiffness, dip_damping, step)
	camera_root.position.y = height + dip.x


# Качка, инерция и дыхание — всё, что живёт внутри нагрудного крепления.
# Позицию пишем один раз, иначе слагаемые перебивают друг друга
func _update_body(step: float) -> void:
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var k: float = clampf(speed / maxf(player.sprint_speed, 0.1), 0.0, 1.0)
	var amp: float = lerpf(walk_amplitude, sprint_amplitude, k) * shake_strength
	amp *= crouch_share if player.is_crouching else 1.0
	# На малом ходу качка гаснет: у стены игрок толкается на месте, шагов нет,
	# и камера не должна ни качаться, ни стоять с постоянным креном в бок
	walk_fade = clampf(speed / 0.6, 0.0, 1.0)
	# Вертикаль — вдох на каждый шаг, бок — цикл на два шага: вес уходит
	# то влево, то вправо, а в момент постановки ступни камера внизу
	var amp_step: float = amp * walk_fade if footsteps else 0.0
	var phase: float = _step_phase()
	var bob_x: float = cos(phase * 0.5) * amp_step * 0.5
	var bob_y: float = -cos(phase) * amp_step

	# Инерция: на разгоне камеру сносит назад, на торможении — вперёд, на дуге
	# уводит в сторону. Скорость сглажена: физика и рендер идут вразнобой
	smooth_velocity = smooth_velocity.lerp(player.velocity, clampf(12.0 * step, 0.0, 1.0))
	var accel: Vector3 = (smooth_velocity - prev_velocity) / maxf(step, 0.001)
	prev_velocity = smooth_velocity
	accel = player.global_transform.basis.inverse() * accel
	var push: Vector2 = (Vector2(-accel.x, -accel.z) * inertia_scale * shake_strength) \
		.limit_length(inertia_limit)
	inertia_spring_x = _spring(inertia_spring_x, push.x, 45.0, 10.0, step)
	inertia_spring_y = _spring(inertia_spring_y, push.y, 45.0, 10.0, step)
	inertia = Vector2(inertia_spring_x.x, inertia_spring_y.x)

	# Дыхание: захлёбывается после бега и тихо дышит всегда — кадр не стоит
	breath += step
	var low: float = 1.0 if player.get_stamina_percent() < 0.3 else 0.35
	tired = lerpf(tired, low, clampf(2.0 * step, 0.0, 1.0))
	var drift: float = sin(breath * TAU * 0.25) * 0.012 * tired * shake_strength

	# Смещения собираем в системе корпуса (камера-то привинчена к груди), а
	# camera.position живёт в системе CameraRoot, уже развёрнутой к взгляду:
	# без пересчёта на резком развороте боковую инерцию уводило вперёд-назад
	var offset := Vector3(lean * lean_offset + bob_x + inertia.x,
		bob_y + drift, inertia.y)
	camera.position = camera_root.global_transform.basis.inverse() \
		* (player.global_transform.basis * offset)


# Крен: наклон корпуса, боковой шаг и разворот. Живёт на самой камере,
# поэтому на развороте он же ведёт кадр — как у камеры на ремне
func _update_roll(delta: float, step: float) -> void:
	var turn: float = wrapf(player.rotation.y - prev_body_yaw, -PI, PI) / maxf(delta, 0.001)
	prev_body_yaw = player.rotation.y
	var swing: float = -player.strafe_input * strafe_roll \
		+ clampf(turn, -2.0, 2.0) * turn_roll \
		- cos(_step_phase() * 0.5) * step_roll * walk_fade
	roll = lerpf(roll, swing * shake_strength - lean * lean_roll, clampf(6.0 * step, 0.0, 1.0))
	camera.rotation.z = roll


# Наклон корпуса на Q/E: камера уезжает в сторону и заваливается. В беге
# и в приседе наклон снимается — тело там занято другим
func _update_lean(step: float) -> void:
	var target: float = 0.0
	if not player.is_sprinting and not player.is_crouching:
		var right: float = 1.0 if Input.is_action_pressed("lean_right") else 0.0
		var left: float = 1.0 if Input.is_action_pressed("lean_left") else 0.0
		target = right - left
	lean = lerpf(lean, target, clampf(lean_speed * step, 0.0, 1.0))


# Поле зрения: разгон расширяет кадр постепенно, а не рывком на Shift.
# Отсчёт идёт от ходьбы: шаг и присед кадр не трогают, настройка честная
func _update_lens(step: float) -> void:
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var span: float = maxf(player.sprint_speed - player.walk_speed, 0.1)
	var k: float = clampf((speed - player.walk_speed) / span, 0.0, 1.0)
	current_fov = lerpf(current_fov, base_fov + sprint_fov_bonus * k,
		clampf(fov_speed * step, 0.0, 1.0))
	camera.fov = current_fov


func add_landing_impact(strength: float) -> void:
	dip.y -= clampf(strength, 0.0, 1.0) * dip_impulse


# Фаза шага из ног: 0 — ступня поставлена, TAU — следующий шаг
func _step_phase() -> float:
	return footsteps.stride_phase if footsteps else 0.0


# Полунеявная пружина: Vector2(x — значение, y — скорость). Дешевле lerp по
# строкам и даёт живой переезд вместо приклеенного к мыши кадра
func _spring(state: Vector2, target: float, stiffness: float, damping: float,
		delta: float) -> Vector2:
	state.y += (target - state.x) * stiffness * delta
	state.y *= exp(-damping * delta)
	return Vector2(state.x + state.y * delta, state.y)
