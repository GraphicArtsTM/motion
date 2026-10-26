extends Node

# EntityEcho: шаги за спиной. Пока хозяин лабиринта бродит поодаль, в
# темноте за игроком иногда кто-то ступает следом — его же шагом, с
# отставкой в полшага, и замолкает, стоит остановиться или обернуться.
# Это не он (он далеко, слух entity.gd этим шагам не верит) — только
# чтобы игрок оглядывался. В освещённом коридоре эхо — большая редкость.
# Живёт ребёнком узла Entity (world.tscn), как entity_presence.gd.

const AudioBank = preload("res://scripts/audio_bank.gd")
const Darkness = preload("res://scripts/darkness.gd")

const STATE_WANDER: int = 0 # Entity.State.WANDER
const MIN_DIST: float = 12.0
const MAX_DIST: float = 40.0
# Шанс начать серию на один шаг игрока: в темноте и при свете
const CHANCE_DARK: float = 0.05
const CHANCE_LIT: float = 0.006
const BEHIND: float = 7.0
const DELAY: float = 0.3
# Обернулся — серия обрывается: за спиной никого и не было
const LOOK_BACK_DOT: float = 0.3

var host = null
var player = null
var steps: Node = null
var rng := RandomNumberGenerator.new()
# Сколько шагов серии осталось
var echo_left: int = 0


func _ready() -> void:
	rng.randomize()
	host = get_parent()
	player = host.get_node_or_null(host.player_path)


func _process(_delta: float) -> void:
	if steps != null or player == null:
		return
	# Компонент шагов ищем лениво: игрок может собраться позже сущности
	steps = player.get_node_or_null("FootstepComponent")
	if steps:
		steps.stepped.connect(_on_player_step)


func can_echo() -> bool:
	if host == null or player == null or not host.placed or not host.is_physics_processing():
		return false
	if int(host.state) != STATE_WANDER or player.is_hidden():
		return false
	var dist: float = host.global_position.distance_to(player.global_position)
	return dist >= MIN_DIST and dist <= MAX_DIST


func _on_player_step(_speed: float, _sprinting: bool, crouching: bool) -> void:
	if not can_echo():
		echo_left = 0
		return
	if echo_left <= 0:
		# Присед глушит и своё, и чужое: новую серию не начинаем
		if crouching:
			return
		var dark: bool = Darkness.is_dark_at(player.global_position)
		if rng.randf() >= (CHANCE_DARK if dark else CHANCE_LIT):
			return
		echo_left = rng.randi_range(3, 7)
	echo_left -= 1
	get_tree().create_timer(DELAY, false).timeout.connect(_echo)


# Шаг звучит позади по ходу движения; смотришь туда — серия обрывается
func _echo() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not can_echo():
		echo_left = 0
		return
	var forward: Vector3 = _flat_dir(-cam.global_transform.basis.z)
	var back: Vector3 = _flat_dir(-(player.velocity as Vector3))
	if back == Vector3.ZERO:
		back = -forward
	if forward.dot(back) > LOOK_BACK_DOT:
		echo_left = 0
		return
	var at: Vector3 = player.global_position + back * BEHIND + Vector3(0, 0.1, 0)
	AudioBank.play_one_shot(get_tree(), at, AudioBank.footstep(rng.randi_range(0, 3)), 4.0, "Entity")


func _flat_dir(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()
