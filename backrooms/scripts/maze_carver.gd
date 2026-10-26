extends RefCounted

# MazeCarver: как именно вырезается чанк. Поверх гарантированно связного
# backtracker'а стены только снимаются: залы, сетка коридоров, петли,
# прореживание тупиков. Единственное исключение — колонны: они в
# maze_pillars.gd, где закрытие клетки проверяется на связность.

const MazeCell = preload("res://scripts/maze_cell.gd")
const MazeZone = preload("res://scripts/maze_zone.gd")
const MazePillars = preload("res://scripts/maze_pillars.gd")

const CHUNK_SIZE: int = 8
const HALL_ATTEMPTS: int = 20
const GRID_LINES: Array = [2, 5]


func carve(chunk, rng: RandomNumberGenerator, style: int) -> void:
	var preset: Dictionary = MazeZone.params(style)
	var blocked: Dictionary = {}
	_carve_maze(chunk, rng)
	if preset.get("grid", false):
		_carve_grid(chunk)
		blocked = _grid_cells()
	var halls: Array = _carve_halls(chunk, rng, preset["halls"])
	_apply_loops(chunk, rng, float(preset["loop"]))
	_reduce_dead_ends(chunk, rng, float(preset["dead"]))
	MazePillars.place(chunk, rng, halls, float(preset["pillar"]), blocked)


# --- лабиринт ---

func _carve_maze(chunk, rng: RandomNumberGenerator) -> void:
	_recursive_backtracker(chunk, rng.randi_range(0, CHUNK_SIZE - 1),
		rng.randi_range(0, CHUNK_SIZE - 1), rng)


func _recursive_backtracker(chunk, x: int, y: int, rng: RandomNumberGenerator) -> void:
	var cell = chunk.get_cell(x, y)
	if not cell:
		return
	cell.visited = true
	var directions: Array = cell.get_available_directions()
	# Тасование только через переданный rng: Array.shuffle() берёт глобальный
	# генератор движка, и один и тот же чанк после перезагрузки выходил другим
	for i in range(directions.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = directions[i]
		directions[i] = directions[j]
		directions[j] = tmp
	for direction in directions:
		var offset: Vector2i = cell.get_neighbor_offset(direction)
		var next_x: int = x + offset.x
		var next_y: int = y + offset.y
		var next_cell = chunk.get_cell(next_x, next_y)
		if next_cell and not next_cell.visited:
			cell.remove_wall(direction)
			next_cell.remove_wall(cell.get_opposite_wall(direction))
			_recursive_backtracker(chunk, next_x, next_y, rng)


# --- сетка коридоров ---

# Длинные прямые пролёты в обе стороны. Линии заданы жёстко, поэтому в
# соседних чанках того же стиля пролёты идут по тем же линиям, а проход
# на границе пробивается по линии (connect_chunks) — коридор не обрывается
func _carve_grid(chunk) -> void:
	for y in GRID_LINES:
		for x in range(CHUNK_SIZE - 1):
			MazeCell.open_between(chunk.get_cell(x, y), chunk.get_cell(x + 1, y),
				MazeCell.Wall.EAST)
	for x in GRID_LINES:
		for y in range(CHUNK_SIZE - 1):
			MazeCell.open_between(chunk.get_cell(x, y), chunk.get_cell(x, y + 1),
				MazeCell.Wall.SOUTH)


# Клетки прямых пролётов: колонна в любой из них перегородила бы сквозной ход,
# ради которого стиль и заведён (проверка «строки 2 и 5 открыты целиком»)
func _grid_cells() -> Dictionary:
	var cells: Dictionary = {}
	for y in GRID_LINES:
		for x in CHUNK_SIZE:
			cells[Vector2i(x, y)] = true
	for x in GRID_LINES:
		for y in CHUNK_SIZE:
			cells[Vector2i(x, y)] = true
	return cells


# --- залы ---

func _carve_halls(chunk, rng: RandomNumberGenerator, sizes: Array) -> Array:
	var halls: Array = []
	for size in sizes:
		_try_carve_hall(chunk, rng, halls, size)
	return halls


func _try_carve_hall(chunk, rng: RandomNumberGenerator, halls: Array, size: Vector2i) -> void:
	for attempt in HALL_ATTEMPTS:
		var rect := Rect2i(
			rng.randi_range(1, CHUNK_SIZE - size.x - 1),
			rng.randi_range(1, CHUNK_SIZE - size.y - 1), size.x, size.y)
		var overlaps := false
		for hall in halls:
			if rect.intersects(hall):
				overlaps = true
				break
		if overlaps:
			continue
		_open_rect(chunk, rect)
		halls.append(rect)
		return


func _open_rect(chunk, rect: Rect2i) -> void:
	# Только ВНУТРЕННИЕ стены зала: rect.end — исключающая граница, иначе зал
	# открывал бы ещё полосу клеток за своей восточной и южной кромкой.
	# Петли раздельные: у восточной стены свои границы (все строки зала),
	# у южной — свои (все столбцы); общая пара границ теряла бы последнюю
	# строку и последний столбец — в зале оставалась стена
	for yy in range(rect.position.y, rect.end.y):
		for xx in range(rect.position.x, rect.end.x - 1):
			MazeCell.open_between(chunk.get_cell(xx, yy), chunk.get_cell(xx + 1, yy),
				MazeCell.Wall.EAST)
	for yy in range(rect.position.y, rect.end.y - 1):
		for xx in range(rect.position.x, rect.end.x):
			MazeCell.open_between(chunk.get_cell(xx, yy), chunk.get_cell(xx, yy + 1),
				MazeCell.Wall.SOUTH)


# --- петли и тупики ---

# Петли: сносим часть внутренних стен (восток/юг — каждую пару раз).
# В чаще доля низкая, в пустоши стены сносятся почти все
func _apply_loops(chunk, rng: RandomNumberGenerator, ratio: float) -> void:
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var cell = chunk.get_cell(x, y)
			if cell == null:
				continue
			_try_loop_wall(chunk, cell, x + 1, y, MazeCell.Wall.EAST, rng, ratio)
			_try_loop_wall(chunk, cell, x, y + 1, MazeCell.Wall.SOUTH, rng, ratio)


func _try_loop_wall(chunk, cell, nx: int, ny: int, direction,
		rng: RandomNumberGenerator, ratio: float) -> void:
	var neighbor = chunk.get_cell(nx, ny)
	if neighbor == null:
		return
	if cell.has_wall(direction) and rng.randf() < ratio:
		MazeCell.open_between(cell, neighbor, direction)


# Прореживание тупиков: клетке с одним выходом пробиваем второй.
# Только внутрь чанка — границы синхронизирует connect_chunks
func _reduce_dead_ends(chunk, rng: RandomNumberGenerator, ratio: float) -> void:
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var cell = chunk.get_cell(x, y)
			if cell == null or MazeCell.wall_count(cell) != 3 or rng.randf() > ratio:
				continue
			var options: Array = []
			_try_dead_end_dir(chunk, cell, x, y, MazeCell.Wall.NORTH, options)
			_try_dead_end_dir(chunk, cell, x, y, MazeCell.Wall.EAST, options)
			_try_dead_end_dir(chunk, cell, x, y, MazeCell.Wall.SOUTH, options)
			_try_dead_end_dir(chunk, cell, x, y, MazeCell.Wall.WEST, options)
			if not options.is_empty():
				var pick: Array = options[rng.randi_range(0, options.size() - 1)]
				MazeCell.open_between(cell, pick[1], pick[0])


func _try_dead_end_dir(chunk, cell, x: int, y: int, direction, options: Array) -> void:
	if not cell.has_wall(direction):
		return
	var offset: Vector2i = cell.get_neighbor_offset(direction)
	var neighbor = chunk.get_cell(x + offset.x, y + offset.y)
	if neighbor == null:
		return
	options.append([direction, neighbor])
