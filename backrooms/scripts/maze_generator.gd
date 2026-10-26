extends Node

# MazeGenerator: во что превращается чанк. Характер берётся из MazeZone
# (районы 2×2 чанка), сам лабиринт вырезает MazeCarver. Здесь только
# сид, порядок и проходы между чанками. Всё — функция координат, а не
# порядка загрузки: выгруженный и загруженный снова чанк тот же самый.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const MazeZone = preload("res://scripts/maze_zone.gd")
const MazeCarver = preload("res://scripts/maze_carver.gd")

const CHUNK_SIZE: int = MazeChunk.CHUNK_SIZE
const BORDER_MIN: int = 2
const BORDER_MAX: int = 4

var carver = MazeCarver.new()


func generate_chunk(chunk, seed_value: int) -> void:
	if chunk.is_generated:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _get_chunk_seed(chunk.chunk_x, chunk.chunk_y, seed_value)
	chunk.style = MazeZone.style_at(chunk.chunk_x, chunk.chunk_y, seed_value)
	carver.carve(chunk, rng, chunk.style)
	chunk.is_generated = true


func _get_chunk_seed(chunk_x: int, chunk_y: int, base_seed: int) -> int:
	var hash_val := hash(Vector2i(chunk_x, chunk_y))
	return (base_seed ^ hash_val) & 0x7FFFFFFF


# Проходы между чанками: 2–4 в разных рядах, в ЛЮБУЮ сторону.
# Старый код молча пропускал запад/север — границы оставались глухими.
func connect_chunks(chunk1, chunk2, base_seed: int) -> void:
	if not chunk1 or not chunk2:
		return
	var dx: int = chunk2.chunk_x - chunk1.chunk_x
	var dy: int = chunk2.chunk_y - chunk1.chunk_y
	if abs(dx) + abs(dy) != 1:
		return
	# Сид от самой границы (пара чанков), а не от того, кто загрузился
	# первым: иначе при возвращении назад проходы вставали бы иначе
	var rng := RandomNumberGenerator.new()
	rng.seed = _border_seed(chunk1, chunk2, base_seed)
	var used: Array[int] = []
	# У СЕТКИ проход ставится на линию пролёта — коридор идёт дальше
	if _is_grid(chunk1) or _is_grid(chunk2):
		for t in MazeCarver.GRID_LINES:
			used.append(t)
	var want: int = rng.randi_range(BORDER_MIN, BORDER_MAX)
	var guard := 0
	while used.size() < want and guard < 16:
		guard += 1
		var t: int = rng.randi_range(0, CHUNK_SIZE - 1)
		if not used.has(t):
			used.append(t)
	for t in used:
		if dx > 0:
			MazeCell.open_between(chunk1.get_cell(CHUNK_SIZE - 1, t),
				chunk2.get_cell(0, t), MazeCell.Wall.EAST)
		elif dx < 0:
			MazeCell.open_between(chunk2.get_cell(CHUNK_SIZE - 1, t),
				chunk1.get_cell(0, t), MazeCell.Wall.EAST)
		elif dy > 0:
			MazeCell.open_between(chunk1.get_cell(t, CHUNK_SIZE - 1),
				chunk2.get_cell(t, 0), MazeCell.Wall.SOUTH)
		else:
			MazeCell.open_between(chunk2.get_cell(t, CHUNK_SIZE - 1),
				chunk1.get_cell(t, 0), MazeCell.Wall.SOUTH)


# Сид границы: пара чанков в каноническом порядке, обе стороны получают
# один и тот же список рядов независимо от порядка загрузки
func _border_seed(chunk1, chunk2, base_seed: int) -> int:
	var a := Vector2i(chunk1.chunk_x, chunk1.chunk_y)
	var b := Vector2i(chunk2.chunk_x, chunk2.chunk_y)
	var lo: Vector2i = a
	var hi: Vector2i = b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		lo = b
		hi = a
	return (base_seed ^ (hash(lo) * 31 + hash(hi))) & 0x7FFFFFFF


func _is_grid(chunk) -> bool:
	return bool(MazeZone.params(chunk.style).get("grid", false))
