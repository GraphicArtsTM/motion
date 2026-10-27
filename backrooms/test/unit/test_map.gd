extends GutTest

# Карта: затопленные сектора (вода не в коллизии, шаги громче, ход тише)
# и лагеря разведчика (тупик внутри чанка, лицом в проход, заначка одна).

const Flood = preload("res://scripts/flood.gd")
const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const MazeGenerator = preload("res://scripts/maze_generator.gd")
const RoomBuilder = preload("res://scripts/room_builder.gd")
const CampSpawner = preload("res://scripts/camp_spawner.gd")
const ChunkManager = preload("res://scripts/chunk_manager.gd")
const PlayerItems = preload("res://scripts/player_items.gd")
const FuseSpawner = preload("res://scripts/fuse_spawner.gd")
const ExitManager = preload("res://scripts/exit_manager.gd")


func _flooded_chunk() -> Vector2i:
	for r in range(2, 30):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if Flood.is_flooded_chunk(Vector2i(x, y)):
					return Vector2i(x, y)
	return Vector2i.MAX


func test_flood_field_sane() -> void:
	var wet: int = 0
	for y in range(-20, 20):
		for x in range(-20, 20):
			wet += int(Flood.is_flooded_chunk(Vector2i(x, y)))
	assert_between(wet / 1600.0, 0.08, 0.25)
	for y in range(-1, 2):
		for x in range(-1, 2):
			assert_false(Flood.is_flooded_chunk(Vector2i(x, y)), "у старта воды нет")
	var pos: Vector2i = _flooded_chunk()
	var at := Vector3((pos.x * 8 + 4) * 4.0, 0.0, (pos.y * 8 + 4) * 4.0)
	assert_eq(Flood.speed_at(at), Flood.SPEED_MULT)
	assert_eq(Flood.noise_at(at), Flood.NOISE_MULT)
	assert_eq(Flood.speed_at(Vector3(2, 0, 2)), 1.0)
	# Предохранители и дверь выхода никогда не под водой
	for cell: Vector2i in FuseSpawner.CELLS + [ExitManager.TARGET]:
		assert_false(Flood.is_flooded_at(Vector3(cell.x * 4.0 + 2.0, 0.0, cell.y * 4.0 + 2.0)))


func test_water_is_not_a_floor() -> void:
	var gen = MazeGenerator.new()
	var pos: Vector2i = _flooded_chunk()
	var chunk = MazeChunk.new(pos.x, pos.y)
	gen.generate_chunk(chunk, 12345)
	var builder = RoomBuilder.new()
	add_child_autofree(builder)
	var mi: MeshInstance3D = builder.build_chunk_mesh(chunk)
	add_child_autofree(mi)
	var drips: int = 0
	var faces := PackedVector3Array()
	for child in mi.get_children():
		if child is AudioStreamPlayer3D:
			drips += 1
		if child is StaticBody3D:
			faces = ((child.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()
	assert_eq(drips, 2, "капель над водой")
	assert_gt(faces.size(), 0)
	for v in faces:
		assert_false(absf(v.y - Flood.WATER_Y) < 0.001, "гладь воды попала в коллизию")
		if absf(v.y - Flood.WATER_Y) < 0.001:
			break
	gen.free()


func test_camp_in_inner_dead_end_facing_out() -> void:
	var gen = MazeGenerator.new()
	var found: int = 0
	for y in range(-8, 8):
		for x in range(-8, 8):
			var chunk = MazeChunk.new(x, y)
			gen.generate_chunk(chunk, 12345)
			var cell: Vector2i = CampSpawner.camp_cell(chunk, 12345)
			assert_eq(CampSpawner.camp_cell(chunk, 12345), cell)
			if cell == Vector2i.MAX:
				continue
			found += 1
			assert_false(Flood.is_flooded_chunk(Vector2i(x, y)), "лагерь в воде")
			assert_between(cell.x, 1, 6)
			assert_between(cell.y, 1, 6)
			var c = chunk.get_cell(cell.x, cell.y)
			assert_eq(MazeCell.wall_count(c), 3)
			# +Z лагеря после поворота смотрит в единственный проход
			var out := Vector3.BACK.rotated(Vector3.UP, CampSpawner.facing(c))
			var open_dir := Vector3.ZERO
			for d in [[MazeCell.Wall.NORTH, Vector3.FORWARD], [MazeCell.Wall.SOUTH, Vector3.BACK],
					[MazeCell.Wall.EAST, Vector3.RIGHT], [MazeCell.Wall.WEST, Vector3.LEFT]]:
				if not c.has_wall(d[0]):
					open_dir = d[1]
			assert_gt(out.dot(open_dir), 0.99)
	assert_between(found, 5, 60)
	gen.free()


func test_stash_taken_once() -> void:
	var root := Node3D.new()
	var player := Node3D.new()
	player.name = "Player"
	root.add_child(player)
	var items = PlayerItems.new()
	root.add_child(items)
	var manager = ChunkManager.new()
	manager.load_radius = 0
	manager.set_process(false)
	root.add_child(manager)
	add_child_autofree(root)
	# Ищем чанк с лагерем и строим его руками
	var gen = MazeGenerator.new()
	var chunk = null
	for x in range(2, 40):
		var c = MazeChunk.new(x, 3)
		gen.generate_chunk(c, manager.world_seed)
		if CampSpawner.camp_cell(c, manager.world_seed) != Vector2i.MAX:
			chunk = c
			break
	gen.free()
	assert_not_null(chunk)
	var spawner = manager.camp_spawner
	spawner.items_ref = items
	spawner.add_camps(chunk, manager.world_seed)
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	var camp = spawner.placed[pos]
	var before: int = items.cans
	items.add_cans(camp.take())
	assert_eq(items.cans, before + 2)
	assert_eq(camp.take(), 0, "заначка одна")
	spawner.remove_camps(pos)
	spawner.add_camps(chunk, manager.world_seed)
	assert_false(spawner.placed[pos].has_stash, "после выгрузки заначка не вернулась")
