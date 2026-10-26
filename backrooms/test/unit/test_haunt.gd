extends GutTest

# Помехи хозяина лабиринта: лампы рядом с ним срываются и возвращаются к
# норме, затмение гасит свет у игрока, «Наблюдатель» встаёт и уходит,
# возвращая мозг сущности, эхо шагов звучит только от далёкого бродяги.

const ChunkManager = preload("res://scripts/chunk_manager.gd")
const LampHaunt = preload("res://scripts/lamp_haunt.gd")
const EntityStalker = preload("res://scripts/entity_stalker.gd")
const EntityEcho = preload("res://scripts/entity_echo.gd")
const Navigator = preload("res://scripts/entity_navigator.gd")

const FAKE_HOST := "extends CharacterBody3D\nvar placed := true\nvar state := 0\n" \
	+ "var player_path := NodePath(\"../P\")\nvar placed_far := 0\n" \
	+ "func _place_far() -> bool:\n\tplaced_far += 1\n\treturn true\n" \
	+ "func _physics_process(_delta: float) -> void:\n\tpass\n"
const FAKE_PLAYER := "extends CharacterBody3D\nfunc is_hidden() -> bool:\n\treturn false\n"

var root_node: Node3D = null
var player: Node3D = null
var host: CharacterBody3D = null


func _script(source: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = source
	s.reload()
	return s


# Мир из чанков, игрок в группе "player" и сущность-заглушка с «голосом»
func _make_world() -> void:
	root_node = Node3D.new()
	player = CharacterBody3D.new()
	player.set_script(_script(FAKE_PLAYER))
	player.name = "P"
	player.add_to_group("player")
	root_node.add_child(player)
	player.position = Vector3(2, 0, 2)
	host = CharacterBody3D.new()
	host.set_script(_script(FAKE_HOST))
	root_node.add_child(host)
	var voice := Node.new()
	voice.add_to_group("entity_voice")
	host.add_child(voice)
	var manager = ChunkManager.new()
	manager.load_radius = 1
	manager.player_path = NodePath("../P")
	manager.set_process(false)
	root_node.add_child(manager)
	add_child_autofree(root_node)


func _haunt() -> Node:
	return get_tree().get_first_node_in_group("lamp_haunt")


# Лампы без своей болезни: у них свет целиком ведёт помеха
func _healthy(haunt) -> Array:
	var out: Array = []
	for pos in haunt.lamps.chunk_nodes:
		var e: Dictionary = haunt.lamps.chunk_nodes[pos]
		if not e["dark"] and e["flicker"] == null:
			out.append(e)
	return out


func test_haunt_falls_off_and_spares_watcher() -> void:
	assert_almost_eq(LampHaunt.haunt_amount(0.0, false), LampHaunt.HAUNT_MAX, 0.001)
	assert_eq(LampHaunt.haunt_amount(LampHaunt.REACH_FAR + 1.0, false), 0.0)
	var prev: float = 1.0
	for d in range(0, 30, 2):
		var a: float = LampHaunt.haunt_amount(float(d), false)
		assert_true(a <= prev, "помеха растёт с расстоянием на %d м" % d)
		prev = a
		# Пока стоит и смотрит, свет почти не трогаем — его должно быть видно
		assert_true(LampHaunt.haunt_amount(float(d), true) <= a * LampHaunt.PEEK_SCALE + 0.0001)


func test_lamps_stutter_near_entity_and_recover() -> void:
	_make_world()
	var haunt = _haunt()
	var lamps: Array = _healthy(haunt)
	assert_gt(lamps.size(), 0)
	var target: Dictionary = lamps[0]
	host.global_position = (target["light"] as Node3D).global_position * Vector3(1, 0, 1)
	var lowest: float = INF
	for i in 60:
		haunt._process(1.0 / 30.0)
		lowest = minf(lowest, (target["light"] as OmniLight3D).light_energy)
	assert_lt(lowest, float(target["energy"]) * 0.5, "лампа у сущности ни разу не провалилась")
	host.global_position = Vector3(5000, 0, 5000)
	haunt._process(1.0 / 30.0)
	for e in lamps:
		assert_almost_eq((e["light"] as OmniLight3D).light_energy, float(e["energy"]), 0.0001)
		assert_almost_eq((e["hum"] as AudioStreamPlayer3D).volume_db, float(e["hum_db"]), 0.0001)


func test_blackout_darkens_around_player_then_returns() -> void:
	_make_world()
	host.global_position = Vector3(5000, 0, 5000)
	var haunt = _haunt()
	haunt.blackout(0.9)
	haunt._process(0.1)
	var near: Array = []
	for e in _healthy(haunt):
		if haunt._flat((e["light"] as Node3D).global_position, player.global_position) < LampHaunt.BLACKOUT_RADIUS:
			near.append(e)
			assert_eq((e["light"] as OmniLight3D).light_energy, 0.0)
	assert_gt(near.size(), 0)
	haunt._process(1.0)
	haunt._process(0.1)
	for e in near:
		assert_almost_eq((e["light"] as OmniLight3D).light_energy, float(e["energy"]), 0.0001)


func test_stalker_appears_then_hands_back_the_brain() -> void:
	_make_world()
	var stalker = EntityStalker.new()
	host.add_child(stalker)
	var cell := Vector2i(5, 0)
	stalker._appear(cell)
	assert_false(host.is_physics_processing())
	assert_true(host.get_meta("peeking", false))
	assert_true(stalker.is_peeking())
	assert_eq(host.global_position, Navigator.cell_to_world(cell))
	# Стоит лицом к игроку
	var forward: Vector3 = -host.global_transform.basis.z
	var to: Vector3 = (player.global_position - host.global_position) * Vector3(1, 0, 1)
	assert_gt(forward.dot(to.normalized()), 0.99)
	stalker._vanish(false)
	stalker._physics_process(0.016)
	assert_true(host.is_physics_processing())
	assert_false(host.has_meta("peeking"))
	assert_false(stalker.is_peeking())
	assert_eq(host.placed_far, 1)
	assert_between(stalker.cooldown, EntityStalker.COOLDOWN_MIN, EntityStalker.COOLDOWN_MAX)


func test_stalker_waits_for_wandering_far_entity() -> void:
	_make_world()
	var stalker = EntityStalker.new()
	host.add_child(stalker)
	stalker.cooldown = 0.0
	# Погоня: не встаёт, а ждёт следующей попытки
	host.state = 2
	host.global_position = player.global_position + Vector3(60, 0, 0)
	stalker._wait(0.016)
	assert_false(stalker.is_peeking())
	assert_eq(stalker.cooldown, EntityStalker.RETRY)
	# Рядом с игроком — тоже нет: из-за угла под нос не прыгает
	host.state = 0
	stalker.cooldown = 0.0
	host.global_position = player.global_position + Vector3(10, 0, 0)
	stalker._wait(0.016)
	assert_false(stalker.is_peeking())


func test_echo_only_from_distant_wanderer() -> void:
	_make_world()
	var echo = EntityEcho.new()
	host.add_child(echo)
	host.global_position = player.global_position + Vector3(20, 0, 0)
	assert_true(echo.can_echo())
	host.global_position = player.global_position + Vector3(5, 0, 0)
	assert_false(echo.can_echo(), "вплотную это уже не эхо")
	host.global_position = player.global_position + Vector3(20, 0, 0)
	host.state = 2
	assert_false(echo.can_echo(), "в погоне эха нет")
	host.state = 0
	host.set_physics_process(false)
	assert_false(echo.can_echo(), "мозг стоит — эха нет")
