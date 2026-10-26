extends Node

# MicComponent: микрофон носимой камеры. Шаги, гул и сущность — это мир,
# а здесь звук самой записи: корпус камеры подпрыгивает на каждом шаге,
# ткань шуршит, на бегу в микрофон дует ветер, лента шипит, при включении
# камера пищит. Поэтому живёт поверх шагов, а не вместо них.

const MicBank = preload("res://scripts/mic_bank.gd")

const RUSTLE_WALK: float = -20.0
const RUSTLE_SPRINT: float = -14.0
const RUSTLE_CROUCH: float = -26.0
const RUSTLE_LAND: float = -10.0
# Ветер — текстура, а не событие: включается только на бегу и очень тихо
const WIND_FROM: float = 2.7
const WIND_FULL: float = 5.0
const WIND_PEAK: float = 0.08
const WIND_RAMP: float = 0.5
# Шипение ленты слышно всегда: это и есть «запись»
const HISS_VOLUME: float = -32.0
const BEEP_VOLUME: float = -20.0

@export var footsteps_path: NodePath
@export var player_path: NodePath
@export var rustle_player: AudioStreamPlayer
@export var wind_player: AudioStreamPlayer
@export var hiss_player: AudioStreamPlayer

var wind_level: float = 0.0
var rng := RandomNumberGenerator.new()

@onready var footsteps: FootstepComponent = get_node_or_null(footsteps_path) as FootstepComponent
@onready var player: PlayerController = get_node_or_null(player_path) as PlayerController


func _ready() -> void:
	rng.randomize()
	# Прогреваем варианты шороха: первый шаг не должен синтезировать звук
	for variant in 3:
		MicBank.rustle(variant)
	if hiss_player:
		hiss_player.stream = MicBank.hiss_loop()
		hiss_player.volume_db = HISS_VOLUME
		hiss_player.play()
	if wind_player:
		wind_player.stream = MicBank.wind_loop()
		wind_player.volume_db = -80.0
		wind_player.play()
	if footsteps:
		footsteps.stepped.connect(_on_step)
		footsteps.landed.connect(_on_landed)
	_play_boot_beep()


func _process(delta: float) -> void:
	if wind_player == null or player == null:
		set_process(false)
		return
	# Ветер нарастает только на бегу: у ходьбы микрофон чистый
	var speed: float = player.velocity.length()
	var target: float = clampf((speed - WIND_FROM) / (WIND_FULL - WIND_FROM), 0.0, 1.0)
	wind_level = move_toward(wind_level, target, delta / WIND_RAMP)
	var level: float = wind_level * WIND_PEAK
	wind_player.volume_db = linear_to_db(level) if level > 0.001 else -80.0


# Шаг: корпус камеры качнулся на креплении. Громче на бегу, тише в приседе
func _on_step(_speed: float, sprinting: bool, crouching: bool) -> void:
	if rustle_player == null:
		return
	var volume: float = RUSTLE_WALK
	if sprinting:
		volume = RUSTLE_SPRINT
	elif crouching:
		volume = RUSTLE_CROUCH
	_play_rustle(volume)


# Приземление: самый сильный удар корпуса за всю запись
func _on_landed() -> void:
	_play_rustle(RUSTLE_LAND)


func _play_rustle(volume: float) -> void:
	rustle_player.volume_db = volume
	rustle_player.pitch_scale = rng.randf_range(0.9, 1.12)
	rustle_player.stream = MicBank.rustle(rng.randi_range(0, 2))
	rustle_player.play()


# Писк включения живёт своей репликой: шаг не должен его обрывать
func _play_boot_beep() -> void:
	var beep := AudioStreamPlayer.new()
	beep.bus = "Mic"
	beep.stream = MicBank.start_beep()
	beep.volume_db = BEEP_VOLUME
	add_child(beep)
	beep.finished.connect(beep.queue_free)
	beep.play()
