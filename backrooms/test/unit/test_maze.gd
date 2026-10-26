extends GutTest

# Лабиринт: детерминизм, симметрия стен, связность чанка и проходы
# между чанками, не зависящие от порядка загрузки.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const MazeGenerator = preload("res://scripts/maze_generator.gd")

const SEEDS: Array = [12345, 1, 777, 424242]

var generator = null


func before_each() -> void:
	generator = MazeGenerator.new()
	add_child_autofree(generator)


func _chunk(x: int, y: int, seed_value: int):
	var chunk = MazeChunk.new(x, y)
	generator.generate_chunk(chunk, seed_value)
	return chunk


func _walls(chunk) -> Array:
	var out: Array = []
	for cell in chunk.cells:
		out.append(cell.walls)
	return out


func test_same_coords_same_chunk() -> void:
	for seed_value in SEEDS:
		for i in 10:
			var a = _chunk(i - 5, i * 3 - 7, seed_value)
			var b = _chunk(i - 5, i * 3 - 7, seed_value)
			assert_eq(_walls(a), _walls(b), "чанк %d зависит не только от координат" % i)


func test_walls_symmetric_inside_chunk() -> void:
	for seed_value in SEEDS:
		for i in 25:
			var chunk = _chunk(i % 5 - 2, i / 5 - 2, seed_value)
			for y in MazeChunk.CHUNK_SIZE:
				for x in MazeChunk.CHUNK_SIZE - 1:
					assert_eq(chunk.get_cell(x, y).has_wall(MazeCell.Wall.EAST),
						chunk.get_cell(x + 1, y).has_wall(MazeCell.Wall.WEST))
			for y in MazeChunk.CHUNK_SIZE - 1:
				for x in MazeChunk.CHUNK_SIZE:
					assert_eq(chunk.get_cell(x, y).has_wall(MazeCell.Wall.SOUTH),
						chunk.get_cell(x, y + 1).has_wall(MazeCell.Wall.NORTH))


# Все клетки чанка, кроме колонн, достижимы друг из друга изнутри чанка
func test_chunk_connected() -> void:
	for seed_value in SEEDS:
		for i in 49:
			var chunk = _chunk(i % 7 - 3, i / 7 - 3, seed_value)
			assert_true(_connected(chunk), "чанк %d (сид %d) распался" % [i, seed_value])


func _connected(chunk) -> bool:
	var open: Array = []
	for y in MazeChunk.CHUNK_SIZE:
		for x in MazeChunk.CHUNK_SIZE:
			if MazeCell.wall_count(chunk.get_cell(x, y)) < 4:
				open.append(Vector2i(x, y))
	if open.is_empty():
		return false
	var seen: Dictionary = {open[0]: true}
	var queue: Array = [open[0]]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		var cell = chunk.get_cell(cur.x, cur.y)
		for direction in MazeCell.directions():
			if cell.has_wall(direction):
				continue
			var nxt: Vector2i = cur + cell.get_neighbor_offset(direction)
			if chunk.get_cell(nxt.x, nxt.y) == null or seen.has(nxt):
				continue
			seen[nxt] = true
			queue.append(nxt)
	return seen.size() == open.size()


# Проходы на границе одинаковы, кто бы из пары ни загрузился первым
func test_border_independent_of_order() -> void:
	for seed_value in SEEDS:
		for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var a1 = _chunk(3, -2, seed_value)
			var b1 = _chunk(3 + offset.x, -2 + offset.y, seed_value)
			generator.connect_chunks(a1, b1, seed_value)
			var a2 = _chunk(3, -2, seed_value)
			var b2 = _chunk(3 + offset.x, -2 + offset.y, seed_value)
			generator.connect_chunks(b2, a2, seed_value)
			assert_eq(_walls(a1), _walls(a2))
			assert_eq(_walls(b1), _walls(b2))


func test_border_has_passages() -> void:
	for seed_value in SEEDS:
		var a = _chunk(0, 0, seed_value)
		var b = _chunk(1, 0, seed_value)
		generator.connect_chunks(a, b, seed_value)
		var open: int = 0
		for y in MazeChunk.CHUNK_SIZE:
			var east: bool = not a.get_cell(MazeChunk.CHUNK_SIZE - 1, y).has_wall(MazeCell.Wall.EAST)
			var west: bool = not b.get_cell(0, y).has_wall(MazeCell.Wall.WEST)
			assert_eq(east, west, "проход открыт только с одной стороны")
			if east:
				open += 1
		assert_between(open, MazeGenerator.BORDER_MIN, MazeChunk.CHUNK_SIZE)
