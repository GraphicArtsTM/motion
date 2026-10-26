extends Node

# CameraLens: оптика носимой камеры. Смотрит на настоящее движение кадра
# (поворот камеры и боковой ход игрока) и подмешивает в пост-обработку смаз
# движения и перекос строк — как у камеры, висящей на ремне. Про управление
# ничего не решает, поэтому живёт отдельно от bodycam_component.gd.

@export var camera_path: NodePath
@export var player_path: NodePath
@export var bodycam_path: NodePath

const MOTION_SCALE: float = 0.011   # рад/с поворота -> доли кадра
const SIDE_SCALE: float = 0.004     # м/с бокового хода -> доли кадра
const SHUTTER_SCALE: float = 0.012  # рад/с -> перекос строк
const MOTION_LIMIT: float = 0.05
const SHUTTER_LIMIT: float = 0.06
# Рывок кадра считаем по кламленному шагу, как и пружины bodycam: движение
# за кадр в 200 мс всё равно не восстановить, лучше недомешать смаз
const MAX_STEP: float = 0.05
# Автоусиление матрицы: при включении камера на мгновение пересвечивает кадр,
# потом съезжает в норму. Дальше усиление едва дышит — это читается как AGC
const BOOT_TIME: float = 0.7
const BOOT_GAIN: float = 0.3
const BREATH_GAIN: float = 0.012
# Доля тряски, на которую сдвигается рамка корпуса (рад -> доли кадра)
const BORDER_FOLLOW: float = 0.45

@onready var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var player: PlayerController = get_node_or_null(player_path) as PlayerController
@onready var bodycam: BodycamComponent = get_node_or_null(bodycam_path) as BodycamComponent

var material: ShaderMaterial = null
var motion := Vector2.ZERO
var shutter: float = 0.0
var gain: float = 1.0
var age: float = 0.0
var tape_time: float = 0.0
var booted: bool = false
var prev_yaw: float = 0.0
var prev_pitch: float = 0.0


func _ready() -> void:
	# Смаз надо гасить и на паузе: сцена на паузе не тикает, и кадр застыл бы
	# со смазом. Камера стоит — значит, смаз сам сойдёт на ноль
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_post()
	if camera:
		var angles: Vector2 = _look_angles()
		prev_yaw = angles.x
		prev_pitch = angles.y


func _process(delta: float) -> void:
	if material == null:
		_bind_post()
	if camera == null or material == null:
		return
	var angles: Vector2 = _look_angles()
	var step: float = clampf(delta, 0.0001, MAX_STEP)
	var yaw_vel: float = wrapf(angles.x - prev_yaw, -PI, PI) / step
	var pitch_vel: float = (angles.y - prev_pitch) / step
	prev_yaw = angles.x
	prev_pitch = angles.y

	# Вектор смаза: резкий бросок мышью и шаг в сторону моют кадр,
	# в покое он чистый — иначе оптика «плывёт» на ровном месте
	var strength: float = bodycam.shake_strength if bodycam else 1.0
	var target := Vector2(yaw_vel * MOTION_SCALE, pitch_vel * MOTION_SCALE)
	if player:
		var side: float = player.global_transform.basis.x.dot(player.velocity)
		target.x -= side * SIDE_SCALE
	target = target.limit_length(MOTION_LIMIT) * strength
	var target_shutter: float = clampf(-yaw_vel * SHUTTER_SCALE, -SHUTTER_LIMIT,
		SHUTTER_LIMIT) * strength
	var weight: float = clampf(12.0 * step, 0.0, 1.0)
	motion = motion.lerp(target, weight)
	shutter = lerpf(shutter, target_shutter, weight)
	material.set_shader_parameter("motion", motion)
	material.set_shader_parameter("shutter", shutter)
	# Рыбий глаз пересчитывается от фактического угла рендера: его меняет
	# ползунок «Поле зрения», и кадр не должен ни резаться, ни чернеть
	material.set_shader_parameter("src_fov", camera.fov)
	# Рамка корпуса ходит за тряской (наклон и рыскание самой Camera3D —
	# их пишет bodycam_shake): объектив болтается внутри корпуса
	material.set_shader_parameter("border_shift",
		Vector2(-camera.rotation.y, camera.rotation.x) * BORDER_FOLLOW)

	# Автоусиление: включаемся с пересветом, потом живём с еле заметным
	# дыханием. Считаем по своему времени, а не по камере — стекло не движется.
	# Первый кадр берёт фактическую тряску: настройки применяет HUD уже после
	# _ready игрока, и при «Тряске 0» вспышки быть не должно
	if not booted:
		booted = true
		gain = 1.0 + BOOT_GAIN * strength
	if not get_tree().paused:
		age += step
		tape_time += step
	elif age < BOOT_TIME:
		age = BOOT_TIME
	var boot: float = clampf(1.0 - age / BOOT_TIME, 0.0, 1.0)
	var target_gain: float = 1.0 + (boot * boot * BOOT_GAIN \
		+ sin(age * 1.7) * BREATH_GAIN) * strength
	gain = 1.0 if strength <= 0.0 else lerpf(gain, target_gain, clampf(9.0 * step, 0.0, 1.0))
	material.set_shader_parameter("gain", gain)
	# Часы ленты: на паузе стоят вместе с записью, поэтому зерно, полоса и
	# выпадения строк не живут поверх застывшего кадра
	material.set_shader_parameter("tape_time", tape_time)


# Углы направления камеры: рыскание и наклон. Считаем от вектора взгляда, а не
# от углов Эйлера — у полюса и под креном Эйлер лжёт, и смаз дёргался
func _look_angles() -> Vector2:
	var forward: Vector3 = -camera.global_transform.basis.z
	return Vector2(atan2(forward.x, forward.z), asin(clampf(forward.y, -1.0, 1.0)))


# Пост-обработка живёт в HUD и на _ready может быть ещё не готова,
# поэтому пробуем привязаться, пока не найдём
func _bind_post() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var post: ColorRect = null
	if hud:
		post = hud.find_child("PostProcess", true, false) as ColorRect
	if post and post.material is ShaderMaterial:
		material = post.material
