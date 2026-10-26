extends RefCounted

# MazePillars: колонны. Клетку внутри зала закрывают со всех сторон — это
# единственное место, где карта стены ставит, а не снимает, поэтому каждая
# колонна проверяется на связность: соседние колонны могли бы отрезать
# угол зала, а в отрезанную клетку может попасть предохранитель.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")

const CHUNK_SIZE: int = MazeChunk.CHUNK_SIZE


static func place(chunk, rng: RandomNumberGenerator, halls: Array, chance: float,
		blocked: Dictionary = {}) -> void:
	for hall in halls:
		if rng.randf() >= chance:
			continue
		for attempt in 4:
			var x: int = rng.randi_range(hall.position.x, hall.end.x - 1)
			var y: int = rng.randi_range(hall.position.y, hall.end.y - 1)
			if blocked.has(Vector2i(x, y)):
				continue # здесь колонна перегородила бы прямой пролёт — берём другую
			if is_safe(chunk, x, y):
				_close(chunk, x, y)
			break


static func _close(chunk, x: int, y: int) -> void:
	var cell = chunk.get_cell(x, y)
	if cell == null:
		return
	for direction in MazeCell.directions():
		var offset: Vector2i = cell.get_neighbor_offset(direction)
		var neighbor = chunk.get_cell(x + offset.x, y + offset.y)
		cell.add_wall(direction)
		if neighbor:
			neighbor.add_wall(cell.get_opposite_wall(direction))


# Останутся ли связанными открытые клетки чанка, если закрыть (px, py)?
# Обход по открытым стенам; уже закрытые клетки-колонны пропускаются
static func is_safe(chunk, px: int, py: int) -> bool:
	var total: int = 0
	var start := Vector2i(-1, -1)
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if (x == px and y == py) or MazeCell.wall_count(chunk.get_cell(x, y)) == 4:
				continue
			total += 1
			if start.x < 0:
				start = Vector2i(x, y)
	if total == 0:
		return false
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		var cell = chunk.get_cell(cur.x, cur.y)
		for direction in MazeCell.directions():
			if cell.has_wall(direction):
				continue
			var offset: Vector2i = cell.get_neighbor_offset(direction)
			var nxt: Vector2i = cur + offset
			if nxt.x == px and nxt.y == py:
				continue
			if nxt.x < 0 or nxt.x >= CHUNK_SIZE or nxt.y < 0 or nxt.y >= CHUNK_SIZE:
				continue
			if seen.has(nxt):
				continue
			seen[nxt] = true
			queue.append(nxt)
	return seen.size() >= total
