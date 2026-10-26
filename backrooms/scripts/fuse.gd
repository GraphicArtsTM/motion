extends Node3D

# Fuse: предохранитель-маячок. Светится и гудит, поэтому его ищут
# глазами и на слух. Берётся на E. Собранные не возрождаются —
# это решает спавнер, он же слушает сигнал picked_up.

const PropItems = preload("res://scripts/prop_items.gd")
const AudioBank = preload("res://scripts/audio_bank.gd")

signal picked_up

const PICK_RANGE: float = 2.4
const NEAR_RANGE: float = 25.0

var items = null
var hud = null
var player: Node3D = null
var player_inside: bool = false
var announced: bool = false


func setup(items_ref, hud_ref) -> void:
	items = items_ref
	hud = hud_ref


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	var built: Dictionary = PropItems.build_fuse()
	var body: Node3D = built["root"]
	add_child(body)

	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.6, 0)
	light.light_color = Color(0.5, 1.0, 0.55)
	light.light_energy = 1.4
	light.omni_range = 13.0
	light.shadow_enabled = false
	add_child(light)

	# Маячок идёт на шину Beacon: её нельзя случайно убавить ползунком
	# «Атмосфера», иначе предохранитель не найти на слух ни за что.
	# Гул слышен на 100 м, на границе уровень уже невысокий. Между
	# предохранителями 250 м — середину перегона игрок проходит без
	# подсказки, иначе забег снова превращается в прогулку по маячкам
	# (проверено забегом на 2 мин). Оговорка: чанк с маяком выгружается
	# на 68–124 м, поэтому гул может оборваться ещё слышимым
	var hum := AudioBank.source("Beacon", AudioBank.fuse_hum(), 20.0)
	hum.max_distance = 100.0
	hum.volume_db = -1.0
	add_child(hum)
	hum.play()

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICK_RANGE
	shape.shape = sphere
	shape.position.y = 0.4
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


# Подойдя достаточно близко, игрок получает подсказку-направление
func _process(_delta: float) -> void:
	if announced or player == null:
		return
	if global_position.distance_to(player.global_position) < NEAR_RANGE:
		announced = true
		if hud and hud.has_method("show_hint"):
			hud.show_hint("Где-то рядом гудит предохранитель...", 3.5)


func _unhandled_input(event: InputEvent) -> void:
	if not player_inside or not event.is_action_pressed("interact"):
		return
	if items == null or hud == null:
		return
	items.add_fuse()
	AudioBank.play_one_shot(get_tree(), global_position + Vector3(0, 0.6, 0),
		AudioBank.insert_clunk(), 6.0)
	hud.show_hint("Предохранитель взят. Теперь найди дверь выхода.", 3.5)
	picked_up.emit()
	queue_free()


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_inside = true
	if hud and hud.has_method("show_hint"):
		hud.show_hint("Нажми F — взять предохранитель", 3.0)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_inside = false
