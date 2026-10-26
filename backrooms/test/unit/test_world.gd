extends GutTest

# Мир: дверные проёмы (данные и геометрия), район «Кабинеты», порча по
# глубине и больная лампа.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const MazeGenerator = preload("res://scripts/maze_generator.gd")
const MazeZone = preload("res://scripts/maze_zone.gd")
const RoomTrim = preload("res://scripts/room_trim.gd")
const WorldDecay = preload("res://scripts/world_decay.gd")
const LampFlicker = preload("res://scripts/lamp_flicker.gd")

var generator = null


func before_each() -> void:
	generator = MazeGenerator.new()
	add_child_autofree(generator)


func _chunk(x: int, y: int):
	var chunk = MazeChunk.new(x, y)
	generator.generate_chunk(chunk, 12345)
	return chunk


# Проём с обеих сторон ребра и только там, где стены нет
func test_doors_symmetric_and_open() -> void:
	var doors := 0
	for i in 36:
		var c = _chunk(i % 6 - 3, i / 6 - 3)
		for y in 8:
			for x in 8:
				var cell = c.get_cell(x, y)
				for step in [[MazeCell.Wall.EAST, Vector2i(1, 0)], [MazeCell.Wall.SOUTH, Vector2i(0, 1)]]:
					var other = c.get_cell(x + step[1].x, y + step[1].y)
					if other == null:
						continue
					var here: bool = (cell.doors & step[0]) != 0
					assert_eq(here, (other.doors & cell.get_opposite_wall(step[0])) != 0)
					if here:
						doors += 1
						assert_false(cell.has_wall(step[0]), "проём в глухой стене")
	assert_gt(doors, 50, "проёмы вообще ставятся")


func test_border_doors_independent_of_order() -> void:
	for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
		var a1 = _chunk(2, 2)
		var b1 = _chunk(2 + offset.x, 2 + offset.y)
		generator.connect_chunks(a1, b1, 12345)
		var a2 = _chunk(2, 2)
		var b2 = _chunk(2 + offset.x, 2 + offset.y)
		generator.connect_chunks(b2, a2, 12345)
		for i in 64:
			assert_eq(a1.cells[i].doors, a2.cells[i].doors)
			assert_eq(b1.cells[i].doors, b2.cells[i].doors)


func test_rooms_style_registered() -> void:
	assert_eq(MazeZone.WEIGHTS.size(), MazeZone.PRESETS.size())
	var total := 0.0
	for w in MazeZone.WEIGHTS:
		total += float(w)
	assert_almost_eq(total, 1.0, 0.0001)
	assert_eq(MazeZone.Style.ROOMS, 4)


# Косяки и перемычка не залезают в проход: ниже перемычки по центру ребра
# на ширине проёма нет ни одной вершины отделки
func test_doorway_leaves_passage_free() -> void:
	var checked := 0
	for i in 16:
		var c = _chunk(i % 4, i / 4 + 5)
		var trim: Array = RoomTrim.build(c)["trim"]
		var verts: PackedVector3Array = trim[0]
		for y in 8:
			for x in 8:
				var cell = c.get_cell(x, y)
				if not cell.has_wall(MazeCell.Wall.EAST) and (cell.doors & MazeCell.Wall.EAST) != 0:
					checked += 1
					var edge_x: float = (x + 1) * 4.0
					var center_z: float = y * 4.0 + 2.0
					for v in verts:
						var inside: bool = absf(v.x - edge_x) < 0.15 and absf(v.z - center_z) < 0.9 \
							and v.y < RoomTrim.LINTEL_Y - 0.01
						assert_false(inside, "отделка в проходе у %s" % str(v))
	assert_gt(checked, 0)


func test_decay_grows_with_depth() -> void:
	assert_eq(WorldDecay.at(Vector2i.ZERO, MazeZone.Style.MAZE), 0.0, "у старта чисто")
	var prev := -1.0
	for d in 16:
		var v: float = WorldDecay.at(Vector2i(d, 0), MazeZone.Style.HALLS)
		assert_gte(v, prev)
		assert_between(v, 0.0, 1.0)
		prev = v
	assert_eq(WorldDecay.at(Vector2i(18, -11), MazeZone.Style.HALLS), 1.0, "у двери выхода — полная порча")


func test_flicker_stays_in_range() -> void:
	var light := OmniLight3D.new()
	light.light_energy = 1.2
	add_child_autofree(light)
	var flicker = LampFlicker.new()
	flicker.setup(light, null, null, 99)
	light.add_child(flicker)
	var low := 99.0
	var high := 0.0
	for i in 600:
		flicker._process(1.0 / 60.0)
		low = minf(low, light.light_energy)
		high = maxf(high, light.light_energy)
	assert_lte(high, 1.2 * 1.05)
	assert_lt(low, 0.6, "лампа хоть раз проваливается")
