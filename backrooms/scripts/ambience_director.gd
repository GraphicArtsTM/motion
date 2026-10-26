extends Node

# AmbienceDirector: звук пустого здания. Держит постоянную подложку
# (низкий гул вентиляции, шина Ambient) и редко подкидывает случайные
# события вокруг игрока — за стеной, над потолком или далеко. Источники
# не привязаны к чанкам, поэтому слышны и сквозь выгруженные стены.

const AudioBank = preload("res://scripts/audio_bank.gd")
const AudioAmbience = preload("res://scripts/audio_ambience.gd")

const DRONE_DB: float = -18.0
const FIRST_EVENT: float = 9.0
const EVENT_MIN: float = 11.0
const EVENT_MAX: float = 34.0
const EVENT_NEAR: float = 5.0
const EVENT_FAR: float = 20.0

var player: Node3D = null
var drone: AudioStreamPlayer = null
var rng := RandomNumberGenerator.new()
var next_event: float = FIRST_EVENT
var drift: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	drone = AudioStreamPlayer.new()
	drone.bus = "Ambient"
	drone.stream = AudioAmbience.drone()
	drone.volume_db = DRONE_DB
	add_child(drone)
	drone.play()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return
	# Пауза и экран смерти: подложка молчит, события не сыплются
	if get_tree().paused:
		if drone.playing:
			drone.stop()
		return
	if not drone.playing:
		drone.play()
	# Медленный уход высоты: ровный тон на слух «стоит», живой — дышит
	drift += delta
	drone.pitch_scale = 1.0 + 0.008 * sin(drift * 0.05)
	next_event -= delta
	if next_event <= 0.0:
		next_event = rng.randf_range(EVENT_MIN, EVENT_MAX)
		_play_event()


# Случайный звук в стороне от игрока: направление любое, высота — от пола
# до потолка. Стены не проверяем: так слышно сквозь них, и это правильно
func _play_event() -> void:
	var kind: int = rng.randi_range(0, 3)
	var dist: float = rng.randf_range(EVENT_NEAR, EVENT_FAR)
	var angle: float = rng.randf_range(0.0, TAU)
	var pos: Vector3 = player.global_position + Vector3(
		cos(angle) * dist, rng.randf_range(0.4, 3.2), sin(angle) * dist)
	var stream: AudioStreamWAV
	var unit: float
	if kind == 0:
		stream = AudioAmbience.drip()
		unit = 6.0
	elif kind == 1:
		stream = AudioAmbience.creak()
		unit = 11.0
	elif kind == 2:
		stream = AudioAmbience.slam()
		unit = 26.0
	else:
		stream = AudioAmbience.rumble()
		unit = 34.0
	AudioBank.play_one_shot(get_tree(), pos, stream, unit, "Ambient")
