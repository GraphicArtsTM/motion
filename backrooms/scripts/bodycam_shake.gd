extends Node
class_name BodycamShake

# BodycamShake: тряска носимой камеры поворотом. Камера на голове почти не
# ездит вверх-вниз, зато корпус её крутит: на каждой постановке ступни кадр
# кивает вниз и отскакивает, за два шага плечи поворачивают его влево-вправо,
# стоя тело еле заметно покачивается, после бега кадр ходит от одышки.
# Пишет наклон и рыскание самой Camera3D, крен отдаёт в bodycam_component.gd
# (там он складывается с наклоном корпуса и разворотом).

@export var player_path: NodePath
@export var camera_path: NodePath
@export var footsteps_path: NodePath
@export var bodycam_path: NodePath

@export_group("Шаг, градусы")
# Кивок на постановке ступни: удар пятки доходит до головы толчком
@export var walk_nod: float = 0.9
@export var sprint_nod: float = 2.2
# Поворот плеч за цикл в два шага
@export var walk_twist: float = 1.0
@export var sprint_twist: float = 2.4
@export var walk_roll: float = 1.1
@export var sprint_roll: float = 2.6
@export var crouch_share: float = 0.5

@export_group("Дрожь тела, градусы")
@export var idle_shake: float = 0.5
@export var walk_shake: float = 0.5
@export var sprint_shake: float = 1.2
# Одышка: кадр кивает в такт дыханию, когда выносливость на исходе
@export var breath_nod: float = 0.7

# Пружина кивка: жёсткая и быстро гаснущая — толчок, а не качели
const NOD_STIFFNESS: float = 170.0
const NOD_DAMPING: float = 13.0
# Импульс скорости на градус кивка: подобран замером, чтобы пик
# отклонения совпадал с walk_nod / sprint_nod
const NOD_KICK: float = 25.0

@onready var player: PlayerController = get_node_or_null(player_path) as PlayerController
@onready var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var footsteps: FootstepComponent = get_node_or_null(footsteps_path) as FootstepComponent
@onready var bodycam: BodycamComponent = get_node_or_null(bodycam_path) as BodycamComponent

var roll: float = 0.0  # рад, его забирает bodycam_component
var nod := Vector2.ZERO  # рад: x — угол, y — скорость
var noise := FastNoiseLite.new()
var noise_time: float = 0.0
var breath_time: float = 0.0
var tired: float = 0.0
var move: float = 0.0
var run: float = 0.0


func _ready() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.seed = randi()
	if footsteps:
		footsteps.stepped.connect(_on_stepped)
		footsteps.landed.connect(_on_landed)


func _process(delta: float) -> void:
	if player == null or camera == null:
		return
	var step: float = minf(delta, 0.05)
	var strength: float = bodycam.shake_strength if bodycam else 1.0
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var crouch: float = crouch_share if player.is_crouching else 1.0
	# Сколько в кадре ходьбы и бега: сглажено, чтобы на старте и у стены
	# тряска нарастала, а не включалась рывком
	var k: float = clampf(8.0 * step, 0.0, 1.0)
	move = lerpf(move, clampf(speed / maxf(player.walk_speed, 0.1), 0.0, 1.0), k)
	var span: float = maxf(player.sprint_speed - player.walk_speed, 0.1)
	run = lerpf(run, clampf((speed - player.walk_speed) / span, 0.0, 1.0), k)

	# Цикл в два шага из ног: на нуле фазы ступня поставлена
	var phase: float = footsteps.stride_phase if footsteps else 0.0
	var twist: float = lerpf(walk_twist, sprint_twist, run) * move * crouch * sin(phase * 0.5)
	var sway: float = -lerpf(walk_roll, sprint_roll, run) * move * crouch * cos(phase * 0.5)

	# Дрожь тела: медленная стоя, частая на бегу. Время шума копим со своей
	# частотой — смена частоты не даёт скачка
	var amp: float = lerpf(lerpf(idle_shake, walk_shake, move), sprint_shake, run) * crouch
	noise_time += step * lerpf(lerpf(0.35, 1.1, move), 2.3, run)
	var shake := Vector3(noise.get_noise_2d(noise_time, 0.0),
		noise.get_noise_2d(0.0, noise_time + 50.0),
		noise.get_noise_2d(noise_time + 100.0, 100.0)) * amp

	# Одышка: чем меньше выносливости, тем глубже кивки дыхания
	var low: float = clampf(1.0 - player.get_stamina_percent() / 0.5, 0.0, 1.0)
	tired = lerpf(tired, low, clampf(1.5 * step, 0.0, 1.0))
	breath_time += step * lerpf(0.25, 0.7, tired)
	var breath: float = sin(breath_time * TAU) * breath_nod * tired

	nod = _spring(nod, NOD_STIFFNESS, NOD_DAMPING, step)
	var pitch: float = rad_to_deg(nod.x) + shake.x + breath
	camera.rotation.x = deg_to_rad(pitch * strength)
	camera.rotation.y = deg_to_rad((twist + shake.y) * strength)
	roll = deg_to_rad((sway + shake.z * 0.6) * strength)


func _on_stepped(_speed: float, sprinting: bool, crouching: bool) -> void:
	var degrees: float = sprint_nod if sprinting else walk_nod
	if crouching:
		degrees *= crouch_share
	nod.y -= deg_to_rad(degrees) * NOD_KICK


# Приземление бьёт сильнее любого шага
func _on_landed() -> void:
	nod.y -= deg_to_rad(sprint_nod * 1.5) * NOD_KICK


# Полунеявная пружина к нулю: Vector2(x — значение, y — скорость)
func _spring(state: Vector2, stiffness: float, damping: float, delta: float) -> Vector2:
	state.y += -state.x * stiffness * delta
	state.y *= exp(-damping * delta)
	return Vector2(state.x + state.y * delta, state.y)
