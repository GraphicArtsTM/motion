extends SpotLight3D

# Flashlight: фонарь носимой камеры. В тёмных участках лабиринта панели
# мертвы, и кадр держится только на нём: узкий тёплый конус, щелчок при
# включении, лёгкое гудение лампы. Висит на камере, поэтому светит туда,
# куда смотрит игрок, и повторяет все наклоны bodycam.

const Darkness = preload("res://scripts/darkness.gd")

const ENERGY_ON: float = 4.2
const RAMP_SPEED: float = 5.5
const CLICK_VOLUME: float = -13.0
const HINT_TEXT: String = "Темно. Фонарь — L"
# Подсказка приходит не сразу: сначала игрок 1.5 с стоит в темноте
const HINT_DELAY: float = 1.5

@export var toggle_action: StringName = &"flashlight"

var is_on: bool = false
var level: float = 0.0
var wobble: float = 0.0
var hint_shown: bool = false
var ever_used: bool = false
var dark_time: float = 0.0
var click_player: AudioStreamPlayer
var click_on: AudioStreamWAV
var click_off: AudioStreamWAV


func _ready() -> void:
	light_energy = 0.0
	click_on = _click_stream(true)
	click_off = _click_stream(false)
	click_player = AudioStreamPlayer.new()
	click_player.bus = "Mic"
	click_player.volume_db = CLICK_VOLUME
	add_child(click_player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		is_on = not is_on
		if is_on:
			ever_used = true
		_click(is_on)


func _process(delta: float) -> void:
	# Включение с разгоном: у лампы есть нить, мгновенного щелчка света нет
	level = move_toward(level, 1.0 if is_on else 0.0, delta * RAMP_SPEED)
	wobble += delta * 23.0
	light_energy = level * ENERGY_ON * (1.0 + sin(wobble) * 0.02)
	if level <= 0.001:
		_check_darkness(delta)


# Если игрок забрёл в мёртвый участок и ни разу не включал фонарь —
# подсказываем один раз. Чужую подсказку (укрытие, дверь, предохранитель)
# не перебиваем: ждём, пока строка освободится
func _check_darkness(delta: float) -> void:
	if hint_shown or ever_used:
		return
	if not Darkness.is_dark_at(global_position):
		dark_time = 0.0
		return
	dark_time += delta
	if dark_time < HINT_DELAY:
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("show_hint"):
		return
	if hud.has_method("can_show_hint") and not hud.call("can_show_hint"):
		return
	hint_shown = true
	hud.call("show_hint", HINT_TEXT, 4.0)


func _click(on: bool) -> void:
	if click_player == null:
		return
	click_player.stream = click_on if on else click_off
	click_player.play()


# Щелчок выключателя: короткий шум с быстрым спадом плюс низкий «тук» корпуса.
# Включение звонче выключения — так и щёлкает настоящий фонарь
func _click_stream(on: bool) -> AudioStreamWAV:
	const RATE: int = 22050
	var count: int = int(RATE * 0.055)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 if on else 7013
	for i in count:
		var t: float = float(i) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0) * exp(-t * 260.0) * 0.5
		var thud: float = sin(TAU * (210.0 if on else 150.0) * t) * exp(-t * 90.0) * 0.5
		data.encode_s16(i * 2, int(clampf((noise + thud) * 0.7, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
