extends GutTest

# ИИ хозяина лабиринта: упреждение по коридору, стены глушат шаги,
# режиссёр напряжения подводит и уводит, обход шкафов слышит одышку.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const Navigator = preload("res://scripts/entity_navigator.gd")
const EntityPredict = preload("res://scripts/entity_predict.gd")
const EntityDirector = preload("res://scripts/entity_director.gd")
const EntityLockers = preload("res://scripts/entity_lockers.gd")
const EntitySenses = preload("res://scripts/entity_senses.gd")
const ChunkManager = preload("res://scripts/chunk_manager.gd")

const FAKE_MANAGER := "extends Node3D\nvar chunks := {}\nvar hiding_spots = null\n"
const FAKE_HOST := "extends CharacterBody3D\nvar placed := true\nvar state := 0\n" \
	+ "var player_path := NodePath(\"../P\")\nvar chunk_manager = null\n" \
	+ "var rumors: Array = []\nvar retreats := 0\n" \
	+ "func hear_rumor(p: Vector3) -> void:\n\trumors.append(p)\n" \
	+ "func retreat() -> void:\n\tretreats += 1\n" \
	+ "func _physics_process(_d: float) -> void:\n\tpass\n"
const FAKE_PLAYER := "extends CharacterBody3D\nvar hidden := false\nvar stamina := 1.0\nvar noise := 0.0\n" \
	+ "func is_hidden() -> bool:\n\treturn hidden\n" \
	+ "func get_stamina_percent() -> float:\n\treturn stamina\n" \
	+ "func get_noise_radius() -> float:\n\treturn noise\n"
const FAKE_SPOT := "extends Node3D\nvar occupied := false\n"


func _node(base: Node, source: String) -> Node:
	var s := GDScript.new()
	s.source_code = source
	s.reload()
	base.set_script(s)
	return base


# Чанк (0,0) с прорубленными коридорами по списку клеток
func _manager(links: Array) -> Node3D:
	var m: Node3D = _node(Node3D.new(), FAKE_MANAGER)
	var chunk = MazeChunk.new(0, 0)
	for link in links:
		var a: Vector2i = link[0]
		var b: Vector2i = link[1]
		var dir: int = MazeCell.Wall.EAST if b.x > a.x else MazeCell.Wall.SOUTH
		MazeCell.open_between(chunk.get_cell(a.x, a.y), chunk.get_cell(b.x, b.y), dir)
	m.chunks[Vector2i.ZERO] = chunk
	add_child_autofree(m)
	return m


func _at(c: Vector2i) -> Vector3:
	return Navigator.cell_to_world(c)


func test_predict_runs_down_the_corridor() -> void:
	var m := _manager([[Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(2, 1), Vector2i(3, 1)], [Vector2i(3, 1), Vector2i(4, 1)]])
	assert_eq(EntityPredict.project(m, _at(Vector2i(0, 1)), Vector3(3, 0, 0), 3), _at(Vector2i(3, 1)))
	# Стоял — некуда упреждать; тупик по ходу — остаётся, назад не смотрит
	assert_eq(EntityPredict.project(m, _at(Vector2i(0, 1)), Vector3.ZERO, 3), _at(Vector2i(0, 1)))
	assert_eq(EntityPredict.project(m, _at(Vector2i(4, 1)), Vector3(3, 0, 0), 3), _at(Vector2i(4, 1)))


func test_predict_follows_bend_but_not_fork() -> void:
	# Изгиб: (0,1)→(1,1)→(1,2)→(1,3) — уходит за поворот
	var bend := _manager([[Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(1, 1), Vector2i(1, 2)],
		[Vector2i(1, 2), Vector2i(1, 3)]])
	assert_eq(EntityPredict.project(bend, _at(Vector2i(0, 1)), Vector3(3, 0, 0), 3), _at(Vector2i(1, 3)))
	# Развилка вверх и вниз: не угадать — встаёт на развилке
	var fork := _manager([[Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(1, 0), Vector2i(1, 1)],
		[Vector2i(1, 1), Vector2i(1, 2)]])
	assert_eq(EntityPredict.project(fork, _at(Vector2i(0, 1)), Vector3(3, 0, 0), 3), _at(Vector2i(1, 1)))


func _director_world() -> Array:
	var root := Node3D.new()
	var player: CharacterBody3D = _node(CharacterBody3D.new(), FAKE_PLAYER)
	player.name = "P"
	root.add_child(player)
	var host: CharacterBody3D = _node(CharacterBody3D.new(), FAKE_HOST)
	root.add_child(host)
	host.chunk_manager = _manager([[Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(2, 1), Vector2i(3, 1)], [Vector2i(3, 1), Vector2i(4, 1)], [Vector2i(4, 1), Vector2i(5, 1)]])
	var director = EntityDirector.new()
	host.add_child(director)
	add_child_autofree(root)
	director.set_physics_process(false)
	return [host, player, director]


func test_director_sends_it_after_long_calm() -> void:
	var w: Array = _director_world()
	var host = w[0]
	var player = w[1]
	var director = w[2]
	player.global_position = _at(Vector2i(0, 1))
	host.global_position = player.global_position + Vector3(200, 0, 0)
	for i in int(EntityDirector.CALM_LIMIT) - 1:
		director.tick(1.0)
	assert_eq(host.rumors.size(), 0, "затишье ещё не кончилось")
	director.tick(1.5)
	assert_eq(host.rumors.size(), 1)
	var d: float = (host.rumors[0] as Vector3).distance_to(player.global_position)
	assert_between(d, EntityDirector.RUMOR_MIN - 0.01, EntityDirector.RUMOR_MAX + 0.01)
	# В шкафу не «чует»
	player.hidden = true
	for i in 100:
		director.tick(1.0)
	assert_eq(host.rumors.size(), 1)


func test_director_backs_off_after_hard_chase() -> void:
	var w: Array = _director_world()
	var host = w[0]
	var director = w[2]
	host.state = 2
	for i in 10:
		director.tick(1.0)
	assert_gt(director.tension, EntityDirector.HOT)
	host.state = 0
	director.tick(0.1)
	assert_eq(host.retreats, 1)
	assert_gt(director.relief, 0.0)
	# Пока передышка — никаких «чутьёв»
	host.global_position = Vector3(500, 0, 500)
	for i in int(EntityDirector.RELIEF_TIME) - 2:
		director.tick(1.0)
	assert_eq(host.rumors.size(), 0)


func _locker_case(stamina: float) -> EntityLockers:
	var entity: CharacterBody3D = CharacterBody3D.new()
	var player: CharacterBody3D = _node(CharacterBody3D.new(), FAKE_PLAYER)
	var near: Node3D = _node(Node3D.new(), FAKE_SPOT)
	var far: Node3D = _node(Node3D.new(), FAKE_SPOT)
	for n in [entity, player, near, far]:
		add_child_autofree(n)
	near.global_position = Vector3(6, 0, 0)
	far.global_position = Vector3(40, 0, 0)
	near.occupied = true
	player.hidden = true
	player.stamina = stamina
	var lockers := EntityLockers.new(entity, player)
	assert_eq(lockers.pick([far, near], Vector3.ZERO), near, "ближний шкаф в радиусе")
	assert_true(lockers.tick(0.1, null), "ещё идёт к шкафу")
	entity.global_position = Vector3(6, 0, 1.2)
	var t: float = 0.0
	while lockers.tick(0.1, null):
		t += 0.1
	assert_almost_eq(t, EntityLockers.LISTEN_TIME, 0.15)
	assert_null(lockers.pick([near], Vector3.ZERO), "проверенный второй раз не слушает")
	return lockers


func test_locker_hears_heavy_breathing() -> void:
	assert_eq(_locker_case(0.3).verdict, EntityLockers.CAUGHT_TEXT)


func test_locker_spares_calm_breathing() -> void:
	assert_eq(_locker_case(0.9).verdict, "")


func test_walls_muffle_steps() -> void:
	var root := Node3D.new()
	var player: CharacterBody3D = _node(CharacterBody3D.new(), FAKE_PLAYER)
	player.name = "Player"
	root.add_child(player)
	player.position = Vector3(2, 0, 2)
	var manager = ChunkManager.new()
	manager.load_radius = 1
	manager.set_process(false)
	root.add_child(manager)
	var entity := CharacterBody3D.new()
	root.add_child(entity)
	add_child_autofree(root)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var senses = EntitySenses.new(entity, player)
	# Клетка со стеной на восток и соседняя за ней: 4 м, шаг слышен на 6
	var pair: Array = _wall_pair(manager.chunks[Vector2i.ZERO])
	assert_false(pair.is_empty())
	player.noise = 6.0
	entity.global_position = _at(pair[0])
	player.global_position = _at(pair[1])
	assert_false(senses.hears_player(), "сквозь стену слышно как без неё")
	player.noise = 8.0
	assert_true(senses.hears_player(), "вплотную за стеной не слышно вовсе")


# Две соседние клетки через стену без обхода рядом: восточная стена
func _wall_pair(chunk) -> Array:
	for y in range(1, 7):
		for x in range(1, 6):
			if chunk.get_cell(x, y).has_wall(MazeCell.Wall.EAST):
				return [Vector2i(x, y), Vector2i(x + 1, y)]
	return []
