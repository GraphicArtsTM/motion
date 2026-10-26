extends GutTest

# Загрузка чанков очередью: после перехода данные новых чанков готовы
# сразу, узлы строятся по кадрам, а итог совпадает с синхронной загрузкой.

const ChunkManager = preload("res://scripts/chunk_manager.gd")
const MazeChunk = preload("res://scripts/maze_chunk.gd")
const Navigator = preload("res://scripts/entity_navigator.gd")

var root_node: Node3D = null
var player: Node3D = null
var manager = null


func _make_world(pos: Vector3, radius: int) -> void:
	root_node = Node3D.new()
	player = Node3D.new()
	player.name = "Player"
	root_node.add_child(player)
	player.position = pos
	manager = ChunkManager.new()
	manager.name = "ChunkManager"
	manager.load_radius = radius
	manager.player_path = NodePath("../Player")
	# Сами строим очередь в тесте: узел не должен делать это за нас
	manager.set_process(false)
	root_node.add_child(manager)
	add_child_autofree(root_node)


func _drain() -> void:
	while not manager.pending_order.is_empty():
		manager._process(0.016)


func _cells(chunk) -> Array:
	var out: Array = []
	for cell in chunk.cells:
		out.append(cell.walls)
	return out


func test_start_is_built_at_once() -> void:
	_make_world(Vector3(2, 0, 2), 2)
	assert_eq(manager.chunks.size(), 25)
	assert_eq(manager.pending.size(), 0)
	assert_eq(manager.chunk_meshes.size(), 25)


func test_crossing_queues_far_chunks() -> void:
	_make_world(Vector3(2, 0, 2), 2)
	player.position += Vector3(MazeChunk.CHUNK_SIZE * MazeChunk.CELL_SIZE, 0, 0)
	manager._process(0.016)
	# Кадр перехода: данные посчитаны, ничего не построено
	assert_eq(manager.pending.size(), 5)
	assert_eq(manager.chunks.size(), 20)
	# Пока чанк в очереди, сущность его не видит и туда не ходит
	for pos in manager.pending.keys():
		var cell := Vector2i(pos.x * MazeChunk.CHUNK_SIZE, pos.y * MazeChunk.CHUNK_SIZE)
		assert_false(Navigator.is_loaded(manager, cell))
	manager._process(0.016)
	assert_eq(manager.pending.size(), 4, "по одному чанку за кадр")
	_drain()
	assert_eq(manager.chunks.size(), 25)
	assert_eq(manager.chunk_meshes.size(), 25)


func test_player_chunk_never_waits() -> void:
	_make_world(Vector3(2, 0, 2), 2)
	# Телепорт далеко: свой чанк должен встать в тот же кадр
	player.position = Vector3(1000, 0, 1000)
	manager._process(0.016)
	var own: Vector2i = MazeChunk.world_to_chunk(player.position)
	assert_true(manager.chunks.has(own))
	assert_true(manager.chunk_meshes.has(own))


# Прогулка с очередью даёт те же стены, что и синхронная загрузка с нуля.
# Сравниваем внутренние чанки: у краевых проходы в выгруженных соседей
# по-прежнему зависят от истории (известная проблема из PROGRESS.md)
func test_walk_matches_fresh_load() -> void:
	_make_world(Vector3(2, 0, 2), 2)
	var step := MazeChunk.CHUNK_SIZE * MazeChunk.CELL_SIZE
	for move in [Vector3(step, 0, 0), Vector3(step, 0, 0), Vector3(0, 0, step),
			Vector3(0, 0, -step), Vector3(0, 0, -step), Vector3(-step, 0, 0)]:
		player.position += move
		manager._process(0.016)
		_drain()
	var walked = manager
	var final_pos: Vector3 = player.position
	_make_world(final_pos, 2)
	var fresh = manager
	var center: Vector2i = MazeChunk.world_to_chunk(final_pos)
	for y in range(-1, 2):
		for x in range(-1, 2):
			var pos: Vector2i = center + Vector2i(x, y)
			assert_eq(_cells(walked.chunks[pos]), _cells(fresh.chunks[pos]),
				"чанк %s разошёлся" % str(pos))


# Меш каждого чанка построен по его текущим стенам: проходы, прорубленные
# соседом из очереди, не остаются глухими
func test_meshes_match_walls() -> void:
	_make_world(Vector3(2, 0, 2), 2)
	var step := MazeChunk.CHUNK_SIZE * MazeChunk.CELL_SIZE
	for i in 3:
		player.position += Vector3(step, 0, step)
		manager._process(0.016)
		_drain()
	for pos in manager.chunks.keys():
		var expected: MeshInstance3D = manager.room_builder.build_chunk_mesh(manager.chunks[pos])
		var actual: MeshInstance3D = manager.chunk_meshes[pos]
		assert_eq(_wall_vertices(actual), _wall_vertices(expected), "меш %s устарел" % str(pos))
		expected.free()


func _wall_vertices(mesh_instance: MeshInstance3D) -> int:
	var mesh: ArrayMesh = mesh_instance.mesh
	# Поверхности: пол, потолок, стены
	if mesh.get_surface_count() < 3:
		return 0
	return mesh.surface_get_array_len(2)
