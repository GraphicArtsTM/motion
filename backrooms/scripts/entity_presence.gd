extends Node

# EntityPresence: оживляет хозяина лабиринта — качает силуэт, тяжело
# стучит шагами по пройденному пути, дышит всё громче по мере приближения,
# рычит, увидев игрока, и шепчет, когда идёт по следу. Живёт ребёнком узла
# Entity (world.tscn): состояния и путь остаются в entity.gd, жизнь — здесь.

const AudioEntity = preload("res://scripts/audio_entity.gd")
const AudioBank = preload("res://scripts/audio_bank.gd")

const STATE_CHASE: int = 2 # Entity.State.CHASE
const STEP_DISTANCE: float = 1.25
const DREAD_RANGE: float = 24.0
const BREATH_FAR_DB: float = -42.0
const BREATH_NEAR_DB: float = -10.0
const WHISPER_MIN: float = 7.0
const WHISPER_MAX: float = 17.0

var host = null
var body: Node3D = null
var breath: AudioStreamPlayer3D = null
var player = null
var rng := RandomNumberGenerator.new()
var last_pos := Vector3.ZERO
var sway_time: float = 0.0
var step_accum: float = 0.0
var last_state: int = -1
var whisper_timer: float = 5.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("entity_voice")
	rng.randomize()
	host = get_parent()
	player = host.get_node_or_null(host.player_path)
	last_pos = host.global_position
	breath = AudioBank.source("Entity", AudioEntity.breath(), 6.0)
	breath.position = Vector3(0, 2.0, 0)
	breath.max_distance = 40.0
	breath.volume_db = BREATH_FAR_DB
	add_child(breath)


func _process(delta: float) -> void:
	if host == null or player == null or not host.placed:
		return
	# Дерево встало (пауза, смерть) или сущность погасла — замолкаем.
	# Поэтому узел работает и на паузе: PROCESS_MODE_ALWAYS в _ready.
	if get_tree().paused or not host.is_physics_processing():
		if breath.playing:
			breath.stop()
		return
	_sway(delta)
	_steps()
	_breath(delta)
	_voice(delta)


# Силуэт дышит и качается, в погоне наваливается вперёд.
# Модель ищется лениво: дети получают _ready раньше родителя-сущности.
func _sway(delta: float) -> void:
	if body == null:
		body = host.get_node_or_null("EntityBody")
		if body == null:
			return
	var chasing: bool = int(host.state) == STATE_CHASE
	sway_time += delta * (1.8 if chasing else 0.9)
	# Колебание вокруг нуля: модель стоит ступнями на полу, а не парит
	body.position.y = sin(sway_time * 1.6) * (0.035 if chasing else 0.02)
	body.rotation.z = sin(sway_time * 0.7) * (0.06 if chasing else 0.025)
	body.rotation.x = sin(sway_time * 1.1) * 0.02 - (0.06 if chasing else 0.0)


# Шаги по пройденной дистанции: рывок-переброс шагами не считается
func _steps() -> void:
	var moved: float = host.global_position.distance_to(last_pos)
	last_pos = host.global_position
	if moved > 1.0:
		step_accum = 0.0
		return
	step_accum += moved
	if step_accum < STEP_DISTANCE:
		return
	step_accum = 0.0
	AudioBank.play_one_shot(get_tree(), host.global_position + Vector3(0, 0.12, 0),
		AudioEntity.step(rng.randi_range(0, 3)), 7.0, "Entity")


# Дыхание: тихое вдалеке, громкое и частое за спиной
func _breath(delta: float) -> void:
	var chasing: bool = int(host.state) == STATE_CHASE
	var near: float = clampf(
		1.0 - host.global_position.distance_to(player.global_position) / DREAD_RANGE,
		0.0, 1.0)
	var target: float = lerpf(BREATH_FAR_DB, BREATH_NEAR_DB, near * near)
	if chasing:
		target += 5.0
	breath.volume_db = lerpf(breath.volume_db, target, clampf(delta * 2.5, 0.0, 1.0))
	breath.pitch_scale = lerpf(1.0, 1.35 if chasing else 1.15, near)
	if near > 0.06:
		if not breath.playing:
			breath.play()
	elif breath.playing:
		breath.stop()


# Рёв: и когда оно увидело игрока, и когда издалека отвечает на гул двери
func roar() -> void:
	if host == null or not host.placed:
		return
	AudioBank.play_one_shot(get_tree(), host.global_position + Vector3(0, 2.1, 0),
		AudioEntity.roar(), 14.0, "Entity")


# Рёв в момент, когда оно увидело игрока, и шёпот, когда идёт по следу
func _voice(delta: float) -> void:
	var state: int = int(host.state)
	if state != last_state:
		last_state = state
		if state == STATE_CHASE:
			roar()
	if state == 0: # WANDER: пока след не нащупан, оно молчит
		whisper_timer = maxf(whisper_timer, 4.0)
		return
	whisper_timer -= delta
	if whisper_timer > 0.0:
		return
	whisper_timer = rng.randf_range(WHISPER_MIN, WHISPER_MAX)
	if host.global_position.distance_to(player.global_position) < 26.0:
		AudioBank.play_one_shot(get_tree(), host.global_position + Vector3(0, 2.2, 0),
			AudioEntity.whisper(), 9.0, "Entity")
