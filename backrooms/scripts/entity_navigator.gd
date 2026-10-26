extends RefCounted

# EntityNavigator: пути по сетке лабиринта. BFS по загруженным чанкам —
# сущность ходит по центрам клеток, где проходы гарантированно открыты.
# Статический класс, состояний не держит.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")

const CELL: float = 4.0
const CHUNK_SIZE: int = MazeChunk.CHUNK_SIZE
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
# Предохранитель BFS. Загруженная область при radius=3 — 7×7 чанков = 3136
# клеток, поэтому лимит должен быть выше неё, иначе путь «пропадает».
const MAX_VISITED: int = 4096


static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL, 0.0, (cell.y + 0.5) * CELL)


static func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))


static func is_loaded(chunk_manager, cell: Vector2i) -> bool:
	return _cell_at(chunk_manager, cell) != null


# Путь от start до goal: массив клеток от следующей после start (goal в конце).
static func find_path(chunk_manager, start: Vector2i, goal: Vector2i) -> Array:
	if _cell_at(chunk_manager, start) == null or _cell_at(chunk_manager, goal) == null:
		return []
	var came: Dictionary = {start: start}
	var frontier: Array = [start]
	var head: int = 0
	var visited: int = 0
	while head < frontier.size() and visited < MAX_VISITED:
		var current: Vector2i = frontier[head]
		head += 1
		visited += 1
		if current == goal:
			return _rebuild(came, start, goal)
		for dir in DIRECTIONS:
			var next: Vector2i = current + dir
			if came.has(next) or not _open_between(chunk_manager, current, next):
				continue
			came[next] = current
			frontier.append(next)
	return []


# Мировой путь к точке. Если BFS не дал пути — жадный шаг в сторону цели,
# чтобы сущность не вставала как вкопанная. avoid — клетка, откуда пришли:
# без неё в тупике возможен цикл «шаг вперёд — шаг назад».
static func path_to(chunk_manager, from_pos: Vector3, goal_pos: Vector3,
		avoid := Vector2i.MAX) -> Array:
	var from: Vector2i = world_to_cell(from_pos)
	var to: Vector2i = world_to_cell(goal_pos)
	var found: Array = find_path(chunk_manager, from, to)
	if found.is_empty() and from != to:
		var step = _greedy_step(chunk_manager, from, to, avoid)
		if step != null:
			found = [step]
	return found


# Путь к случайной клетке в кольце [min_m, max_m] вокруг origin_pos.
static func path_in_band(chunk_manager, from_pos: Vector3, origin_pos: Vector3,
		min_m: float, max_m: float, rng: RandomNumberGenerator) -> Array:
	var pick = random_cell_in_band(chunk_manager, world_to_cell(origin_pos),
		min_m, max_m, rng)
	if pick == null:
		return []
	return find_path(chunk_manager, world_to_cell(from_pos), pick)


# Все клетки кольца [min_m, max_m] вокруг origin — одним обходом в ширину.
# Зовётся и для случайной точки маршрута (path_in_band), и для переброса
# сущности, которому нужен весь список кандидатов, а не один.
static func cells_in_band(chunk_manager, origin: Vector2i, min_m: float,
		max_m: float) -> Array:
	var came: Dictionary = {origin: origin}
	var frontier: Array = [origin]
	var head: int = 0
	var candidates: Array = []
	var min_cells: float = min_m / CELL
	var max_cells: float = max_m / CELL
	while head < frontier.size() and came.size() < MAX_VISITED:
		var current: Vector2i = frontier[head]
		head += 1
		var offset: Vector2 = Vector2(current - origin)
		if offset.length() > max_cells:
			continue
		if offset.length() >= min_cells:
			candidates.append(current)
		for dir in DIRECTIONS:
			var next: Vector2i = current + dir
			if came.has(next) or not _open_between(chunk_manager, current, next):
				continue
			came[next] = current
			frontier.append(next)
	return candidates


static func random_cell_in_band(chunk_manager, origin: Vector2i, min_m: float,
		max_m: float, rng: RandomNumberGenerator):
	var candidates: Array = cells_in_band(chunk_manager, origin, min_m, max_m)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _rebuild(came: Dictionary, start: Vector2i, goal: Vector2i) -> Array:
	var path: Array = []
	var current: Vector2i = goal
	while current != start:
		path.push_front(current)
		current = came[current]
	return path


static func _greedy_step(chunk_manager, from: Vector2i, to: Vector2i, avoid):
	var best = null
	var best_dist: float = INF
	var fallback = null
	var fallback_dist: float = INF
	for dir in DIRECTIONS:
		var next: Vector2i = from + dir
		if not _open_between(chunk_manager, from, next):
			continue
		var dist: float = Vector2(next - to).length()
		if next == avoid:
			# Назад только если других дверей нет вовсе (тупик)
			if dist < fallback_dist:
				fallback_dist = dist
				fallback = next
			continue
		if dist < best_dist:
			best_dist = dist
			best = next
	if best != null:
		return best
	return fallback


# Проход открыт: обе клетки загружены и между ними нет стены.
static func _open_between(chunk_manager, a: Vector2i, b: Vector2i) -> bool:
	var cell = _cell_at(chunk_manager, a)
	if cell == null or _cell_at(chunk_manager, b) == null:
		return false
	var dir: Vector2i = b - a
	if dir == Vector2i(0, -1):
		return not cell.has_wall(MazeCell.Wall.NORTH)
	if dir == Vector2i(1, 0):
		return not cell.has_wall(MazeCell.Wall.EAST)
	if dir == Vector2i(0, 1):
		return not cell.has_wall(MazeCell.Wall.SOUTH)
	if dir == Vector2i(-1, 0):
		return not cell.has_wall(MazeCell.Wall.WEST)
	return false


static func _cell_at(chunk_manager, cell: Vector2i):
	if chunk_manager == null:
		return null
	var chunk_pos := Vector2i(floori(float(cell.x) / CHUNK_SIZE),
		floori(float(cell.y) / CHUNK_SIZE))
	var chunk = chunk_manager.chunks.get(chunk_pos)
	if chunk == null:
		return null
	return chunk.get_cell(cell.x - chunk_pos.x * CHUNK_SIZE,
		cell.y - chunk_pos.y * CHUNK_SIZE)
