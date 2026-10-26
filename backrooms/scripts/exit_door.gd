extends Node3D

# ExitDoor: дверь-выход. Обесточена: пока в неё не вставлены три
# предохранителя из лабиринта, она лишь тускло тлеет и низко гудит —
# так её и находят на слух. Запитал → E → открылась.
# Само питание хранит exit_power.gd (оно переживает выгрузку чанка),
# где стоит дверь и когда победа — решает exit_manager.gd.

const PropExitDoor = preload("res://scripts/prop_exit_door.gd")
const AudioBank = preload("res://scripts/audio_bank.gd")
const ExitPower = preload("res://scripts/exit_power.gd")

# Вставка предохранителя под нагрузкой слышна всему ближнему лабиринту,
# а третий бьёт громче всех — финал перестаёт быть рутиной
const NOISE_RADIUS: float = 70.0
const NOISE_RADIUS_LAST: float = 100.0
const ROAR_DELAY: float = 2.0
const ROAR_DELAY_LAST: float = 0.5

var roar_timer: Timer = null
var hud = null
var items = null
var power = null
var glow_mat: StandardMaterial3D = null
var lamps: Array = []
var light: OmniLight3D = null
var player_inside: bool = false


func setup(hud_ref, items_ref, power_ref) -> void:
	hud = hud_ref
	items = items_ref
	power = power_ref


func _ready() -> void:
	var built: Dictionary = PropExitDoor.build_exit_door()
	var shell: Node3D = built["root"]
	glow_mat = built["glow"]
	lamps = built["lamps"]
	add_child(shell)

	light = OmniLight3D.new()
	light.position = Vector3(0, 2.0, 1.5)
	light.light_color = Color(0.5, 1.0, 0.6)
	light.omni_range = 12.0
	light.shadow_enabled = false
	shell.add_child(light)

	# Маяк-гул: по нему дверь и находят в бесконечном лабиринте. Это самый
	# дальнобойный звук в мире (150 м против 100 м у предохранителя) и
	# низкий против высокого: последний отрезок пути по нему и держат,
	# а саму дверь всё равно приходится искать ногами
	var beacon := AudioBank.source("Beacon", AudioBank.door_beacon(), 30.0)
	beacon.position = Vector3(0, 1.6, 0.6)
	beacon.max_distance = 150.0
	beacon.volume_db = -2.0
	beacon.autoplay = true
	shell.add_child(beacon)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.5, 3.0)
	shape.shape = box
	shape.position.y = 1.2
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	shell.add_child(area)

	# Ответ хозяина: рёв приходит с задержкой, когда игрок уже отвлёкся
	roar_timer = Timer.new()
	roar_timer.one_shot = true
	roar_timer.wait_time = ROAR_DELAY
	roar_timer.timeout.connect(_on_roar_timeout)
	add_child(roar_timer)

	_apply_power()


# E у двери: копим предохранители, с третьим дверь оживает, дальше
# E открывает выход. true — игрок вышел и его ждёт экран победы.
func interact() -> bool:
	if power == null:
		return false
	if power.powered:
		return true
	if items == null or not items.take_fuse():
		_show_hint("Дверь обесточена: нужно %d предохранителя из лабиринта." % ExitPower.NEEDED)
		return false
	power.insert()
	AudioBank.play_one_shot(get_tree(), global_position + Vector3(0, 1.2, 1.0),
		AudioBank.insert_clunk(), 8.0)
	_announce_power()
	_apply_power()
	if power.powered:
		if hud and hud.has_method("set_powered"):
			hud.set_powered()
		_show_hint("Питание есть — ОНО услышало гул. Жми F.", 5.0)
	else:
		_show_hint("Вставлено %d/%d — дверь загудела. ОНО услышало."
			% [power.inserted, ExitPower.NEEDED])
	return false


# Мир узнал, где ты: шум-тревога ловит слух сущности (noise_bus), ток бьёт
# по всему этажу, а через пару секунд хозяин отвечает рёвом оттуда, где он есть
func _announce_power() -> void:
	var last: bool = power.powered
	var radius: float = NOISE_RADIUS_LAST if last else NOISE_RADIUS
	var bus = get_tree().get_first_node_in_group("noise_bus")
	if bus:
		bus.emit_noise(global_position, radius, true)
	AudioBank.play_one_shot(get_tree(), global_position + Vector3(0, 1.0, 0.6),
		AudioBank.power_surge(), 40.0)
	# Последний ответ откладывать нельзя: игрок сразу жмёт E, дерево встаёт
	# на паузу — и отложенный рёв не прозвучал бы вовсе
	roar_timer.start(ROAR_DELAY_LAST if last else ROAR_DELAY)


func _on_roar_timeout() -> void:
	var voice = get_tree().get_first_node_in_group("entity_voice")
	if voice and voice.has_method("roar"):
		voice.roar()


# Чем больше вставлено, тем ярче тлеет рамка, свет и лампы на пульте
func _apply_power() -> void:
	var level: float = power.level() if power != null else 0.0
	if glow_mat:
		glow_mat.emission_energy_multiplier = 0.05 + 2.4 * level
	if light:
		light.light_energy = 0.12 + 1.6 * level
	var done: int = int(power.inserted) if power != null else 0
	if hud and hud.has_method("set_inserted"):
		hud.set_inserted(done)
	for i in lamps.size():
		var lamp: StandardMaterial3D = lamps[i]
		lamp.emission_energy_multiplier = 2.4 if i < done else 0.04


func _door_hint() -> String:
	if power == null:
		return ""
	if power.powered:
		return "Нажми F — ВЫХОД"
	var have: int = int(items.fuses) if items != null else 0
	if have > 0:
		return "Нажми F — вставить предохранитель (в руках %d)" % have
	if power.inserted > 0:
		return "Вставлено %d/%d. Остальные гудят в лабиринте." % [power.inserted, ExitPower.NEEDED]
	return "Дверь обесточена: нужно %d предохранителя. Они гудят в лабиринте." % ExitPower.NEEDED


func _show_hint(text: String, duration: float = 3.5) -> void:
	if hud and hud.has_method("show_hint"):
		hud.show_hint(text, duration)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_inside = true
		_show_hint(_door_hint(), 4.0)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_inside = false
		if hud and hud.has_method("hide_hint"):
			hud.hide_hint()
