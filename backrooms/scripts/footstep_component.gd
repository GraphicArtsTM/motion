extends Node
class_name FootstepComponent

const AudioBank = preload("res://scripts/audio_bank.gd")

# Шаг совершился: слушает микрофон камеры (шорох корпуса). Мир слышит сам
# AudioStreamPlayer3D, поэтому сигнал — только для «записи»
signal stepped(speed: float, sprinting: bool, crouching: bool)
signal landed

@export var audio_player: AudioStreamPlayer3D

# Длина шага в метрах: шаг звучит через каждые N метров пути
@export_group("Stride")
@export var walk_stride: float = 1.25
@export var sprint_stride: float = 1.55
@export var crouch_stride: float = 1.0

# Громкость
@export_group("Volume")
@export var walk_volume: float = 0.3
@export var sprint_volume: float = 0.7
@export var crouch_volume: float = 0.1

@export var speed_threshold: float = 0.1

var step_accum: float = 0.0
# Фаза шага в радианах, без заворота: TAU приходится на шаг, на нуле ступня
# поставлена. Не заворачиваем намеренно — бок камеры и рук качается циклом
# в два шага (cos(phase * 0.5)), и на завороте он прыгал бы с края на край.
# Её читают камера и руки, поэтому звук, камера и руки в одном ритме
var stride_phase: float = 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func update_footsteps(distance_moved: float, speed: float, is_sprinting: bool, is_crouching: bool) -> void:
	# Определяем параметры в зависимости от состояния
	var stride: float
	var volume: float
	
	if is_crouching:
		stride = crouch_stride
		volume = crouch_volume
	elif is_sprinting:
		stride = sprint_stride
		volume = sprint_volume
	else:
		stride = walk_stride
		volume = walk_volume
	
	# Телепорт (выход из шкафа — 1.4 м разом, рестарт) — не шаг: иначе пачка
	# звуков и рывок фазы. Кадровый шаг даже в беге не больше ~0.1 м, поэтому
	# порог жёсткий: 2 * stride (2.5 м) выход из шкафа не ловил
	if distance_moved > 1.0:
		step_accum = 0.0
		return
	
	# Шаг через каждые stride метров реального смещения: у стены (толкаемся
	# на месте) шаги не частит. Фазу ведём всегда — её читают камера и руки,
	# и без звуковой карты качка пропадать не должна
	if speed > speed_threshold:
		step_accum += distance_moved
		stride_phase += distance_moved / stride * TAU
	else:
		# Фазу не сбрасываем: она общая и безразрывная. Стоя качка гаснет
		# сама — амплитуду в bodycam_component множит walk_fade
		step_accum = 0.0
	
	# Громкость ставим в момент шага: иначе приземление (play_footstep(0.9))
	# тут же перебивалось бы громкостью ходьбы в том же кадре. Заодно микрофон
	# слышит шаг и без мирового плеера: play_footstep() сам промолчит
	while step_accum >= stride:
		step_accum -= stride
		if audio_player:
			audio_player.volume_db = linear_to_db(volume)
		stepped.emit(speed, is_sprinting, is_crouching)
		play_footstep()


# Приземление: громкий шаг и отдельный сигнал — микрофон бьётся сильнее всех.
# Вызывается напрямую из контроллера, поэтому сигнал идёт отсюда, а не из
# update_footsteps
func land() -> void:
	play_footstep(0.9)
	landed.emit()


func play_footstep(volume_override: float = -1.0) -> void:
	if not audio_player:
		return
	if volume_override >= 0.0:
		audio_player.volume_db = linear_to_db(volume_override)
	# Синтезированный шаг: 4 варианта + случайная высота — не звучит как цикл
	audio_player.stream = AudioBank.footstep(rng.randi_range(0, 3))
	audio_player.pitch_scale = rng.randf_range(0.93, 1.07)
	audio_player.play()


func reset() -> void:
	step_accum = 0.0
	stride_phase = 0.0
	if audio_player and audio_player.playing:
		audio_player.stop()
