extends Node

# CameraLook: куда смотрит нагрудная камера. Мышь задаёт намерение (look_yaw
# и наклон у игрока), а кадр догоняет его пружиной: у камеры на теле есть
# масса — на рывке она чуть отстаёт и слегка перелетает, а не прибита к
# курсору, как глаз в обычном шутере. Разница между взглядом и корпусом
# уходит в сам узел камеры, корпус доворачивается своей скоростью.

@export var player_path: NodePath
@export var camera_root_path: NodePath
# Собственная частота пружины, Гц: 3.6 — кадр доходит до цели за ~0.1 с,
# прицел остаётся послушным
@export var aim_frequency: float = 3.6
# Затухание: меньше 1 — лёгкий перелёт (~4% при 0.68), 1 — без перелёта
@export var aim_damping: float = 0.68

const PITCH_LIMIT: float = deg_to_rad(89.0)
# Пружину интегрируем подшагами не длиннее этого: явная схема на длинном
# кадре (меньше ~25 fps) раскачивается и уносит кадр, а подшаги держат её
# устойчивой при любом fps
const SUBSTEP: float = 1.0 / 120.0

@onready var player: PlayerController = get_node_or_null(player_path) as PlayerController
@onready var camera_root: Node3D = get_node_or_null(camera_root_path) as Node3D

var view := Vector2.ZERO  # x — рыскание в мире (без заворота), y — наклон
var view_speed := Vector2.ZERO
var started: bool = false


func _process(delta: float) -> void:
	if camera_root == null or player == null:
		return
	var target := Vector2(player.look_yaw, player.camera_rotation_x)
	if not started:
		started = true
		view = target
	# Рывок кадра не должен раскачать пружину — та же политика, что в bodycam
	var step: float = minf(delta, 0.05)
	var count: int = maxi(ceili(step / SUBSTEP), 1)
	var dt: float = step / count
	var w: float = TAU * aim_frequency
	for i in count:
		var accel: Vector2 = (target - view) * w * w - view_speed * 2.0 * aim_damping * w
		view_speed += accel * dt
		view += view_speed * dt
	view.y = clampf(view.y, -PITCH_LIMIT, PITCH_LIMIT)
	camera_root.rotation = Vector3(view.y,
		wrapf(view.x - player.rotation.y, -PI, PI), 0.0)
