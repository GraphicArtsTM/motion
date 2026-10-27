extends Node3D

# CampSpawner: лагеря разведчика (camp.gd). Примерно в каждом
# одиннадцатом чанке — в тупике внутри чанка: туда, где спиной к глухим
# стенам видно единственный вход. Крайние клетки не берём — их стены
# прорубает соседний чанк, и выбор зависел бы от порядка загрузки.
# Заначку банок забирают один раз; сам лагерь остаётся ориентиром.
# Если в чанке есть записка, она лежит у спальника (note_spawner.gd).
# Зовёт chunk_manager.gd, как fuse_spawner.gd.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const Camp = preload("res://scripts/camp.gd")
const PropCamp = preload("res://scripts/prop_camp.gd")
const Flood = preload("res://scripts/flood.gd")

const CELL: float = MazeChunk.CELL_SIZE
const CHANCE: float = 0.09
# Дверца-проход тупика → поворот лагеря (+Z в проход), как у hiding_spots
const FACING := {MazeCell.Wall.SOUTH: 0.0, MazeCell.Wall.EAST: PI * 0.5,
	MazeCell.Wall.NORTH: PI, MazeCell.Wall.WEST: -PI * 0.5}

var hud_ref = null
var items_ref = null
var placed: Dictionary = {}
var looted: Dictionary = {}


func _ready() -> void:
	hud_ref = get_tree().get_first_node_in_group("hud")
	items_ref = get_tree().get_first_node_in_group("player_items")
	# Прогрев мешей лагеря: собрать на загрузке, а не при первой встрече
	for mesh: Node in [PropCamp.camp(), PropCamp.stash(), PropCamp.glass()]:
		mesh.free()


# Клетка лагеря в чанке (локальная) или Vector2i.MAX. Чистая функция
# данных чанка и сида
static func camp_cell(chunk, world_seed: int) -> Vector2i:
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	# В воде (flood.gd) не ночуют
	if (absi(pos.x) <= 1 and absi(pos.y) <= 1) or Flood.is_flooded_chunk(pos):
		return Vector2i.MAX
	var rng := RandomNumberGenerator.new()
	rng.seed = ((world_seed ^ hash(pos)) + 15485863) & 0x7FFFFFFF
	if rng.randf() >= CHANCE:
		return Vector2i.MAX
	var dead_ends: Array = []
	for y in range(1, MazeChunk.CHUNK_SIZE - 1):
		for x in range(1, MazeChunk.CHUNK_SIZE - 1):
			if MazeCell.wall_count(chunk.get_cell(x, y)) == 3:
				dead_ends.append(Vector2i(x, y))
	if dead_ends.is_empty():
		return Vector2i.MAX
	return dead_ends[rng.randi_range(0, dead_ends.size() - 1)]


# Поворот лагеря: +Z — в единственный проход тупика
static func facing(cell) -> float:
	for wall in FACING:
		if not cell.has_wall(wall):
			return FACING[wall]
	return 0.0


# Мировая точка и поворот лагеря чанка, или пустой словарь
static func camp_transform(chunk, world_seed: int) -> Dictionary:
	var cell: Vector2i = camp_cell(chunk, world_seed)
	if cell == Vector2i.MAX:
		return {}
	var at: Vector3 = chunk.get_world_position() + Vector3((cell.x + 0.5) * CELL, 0.0, (cell.y + 0.5) * CELL)
	return {"pos": at, "yaw": facing(chunk.get_cell(cell.x, cell.y))}


func add_camps(chunk, world_seed: int) -> void:
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	if placed.has(pos):
		return
	var xf: Dictionary = camp_transform(chunk, world_seed)
	if xf.is_empty():
		return
	var camp = Camp.new()
	camp.position = xf["pos"]
	camp.rotation.y = xf["yaw"]
	camp.has_stash = not looted.has(pos)
	camp.hud = hud_ref
	camp.items = items_ref
	camp.looted.connect(func() -> void: looted[pos] = true)
	add_child(camp)
	placed[pos] = camp


func remove_camps(chunk_pos: Vector2i) -> void:
	if placed.has(chunk_pos):
		(placed[chunk_pos] as Node3D).queue_free()
		placed.erase(chunk_pos)
