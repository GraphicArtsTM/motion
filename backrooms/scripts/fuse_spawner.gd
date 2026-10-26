extends Node3D

# FuseSpawner: три предохранителя в дальних чанках. Клетки заданы жёстко
# и уводят игрока от старта в сторону выхода: дорога получается связной,
# а не «где-то в бесконечном лабиринте». Маяки разнесены на 250 м, а гул
# слышен на 100 м: в середине каждого перегона не слышно НИ ОДНОГО, и
# этот участок игрок проходит по памяти и по сторонам. Первый стоит
# в 54 м от старта — на нём механика и объясняется. Собранные не возвращаются.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const Fuse = preload("res://scripts/fuse.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const PropItems = preload("res://scripts/prop_items.gd")

const CHUNK_SIZE: int = MazeChunk.CHUNK_SIZE
const CELL_METERS: float = MazeChunk.CELL_SIZE
const CELLS: Array = [Vector2i(13, -4), Vector2i(66, -37), Vector2i(119, -70)]

var items_ref = null
var hud_ref = null
var placed: Dictionary = {}
var collected: Dictionary = {}


func _ready() -> void:
	items_ref = get_tree().get_first_node_in_group("player_items")
	# Прогрев мешей предохранителя и банки: собрать на загрузке, а не в игре
	(PropItems.build_fuse()["root"] as Node).free()
	var can: Dictionary = PropItems.build_can()
	(can["root"] as Node).free()
	(can["shape"] as Node).free()
	hud_ref = get_tree().get_first_node_in_group("hud")


func add_fuses(chunk, world_seed: int) -> void:
	var chunk_pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	for id in CELLS.size():
		if collected.has(id) or placed.has(id):
			continue
		if _chunk_of(CELLS[id]) != chunk_pos:
			continue
		var cell: Vector2i = _pick_cell(chunk, CELLS[id])
		if cell == Vector2i.MAX:
			continue
		var fuse = Fuse.new()
		fuse.position = chunk.get_world_position() + Vector3(
			(cell.x + 0.5) * CELL_METERS, 0.0, (cell.y + 0.5) * CELL_METERS)
		fuse.setup(items_ref, hud_ref)
		fuse.picked_up.connect(_on_picked_up.bind(id))
		add_child(fuse)
		placed[id] = [fuse, chunk_pos]


func remove_fuses(chunk_pos: Vector2i) -> void:
	for id in placed.keys():
		var entry: Array = placed[id]
		if entry[1] == chunk_pos:
			(entry[0] as Node3D).queue_free()
			placed.erase(id)


func _on_picked_up(id: int) -> void:
	collected[id] = true
	placed.erase(id)
	if hud_ref == null:
		return
	if collected.size() >= CELLS.size():
		hud_ref.show_hint("Все предохранители у тебя. Теперь найди дверь выхода — она гудит низко.", 4.0)
	else:
		hud_ref.show_hint("Предохранитель взят (%d/%d). Следующий гудит дальше в лабиринте."
			% [collected.size(), CELLS.size()], 4.0)


# Клетка чанка, где встанет предохранитель: ближайшая к заданной, но
# сначала среди открытых (стен не больше двух — такую видно из коридора,
# а не со дна тупика), и лишь если такой в чанке нет — любая проходимая.
# Наружные стены краевых клеток прорубает connect_chunks, и только когда
# соседний чанк уже в памяти. Для выбора считаем их всегда закрытыми —
# иначе клетка предохранителя зависела бы от порядка загрузки
# и «переезжала» при возвращении назад.
func _pick_cell(chunk, target: Vector2i) -> Vector2i:
	var best := _nearest_open(chunk, target, 2)
	if best == Vector2i.MAX:
		best = _nearest_open(chunk, target, 3)
	return best


# Ближайшая к заданной клетка чанка с числом открытых стен не больше предела
func _nearest_open(chunk, target: Vector2i, max_walls: int) -> Vector2i:
	var best := Vector2i.MAX
	var best_dist: int = 99999
	for ly in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var cell = chunk.get_cell(lx, ly)
			var walls: int = MazeCell.wall_count(cell)
			if walls > max_walls:
				continue
			if walls + _outer_walls(cell, lx, ly) > max_walls:
				continue
			var world := Vector2i(chunk.chunk_x * CHUNK_SIZE + lx,
				chunk.chunk_y * CHUNK_SIZE + ly)
			var dist: int = absi(world.x - target.x) + absi(world.y - target.y)
			if dist < best_dist:
				best_dist = dist
				best = Vector2i(lx, ly)
	return best


# Сколько наружных стен клетки открыто (за ними — соседний чанк)
func _outer_walls(cell, lx: int, ly: int) -> int:
	var count: int = 0
	if lx == 0 and not cell.has_wall(MazeCell.Wall.WEST):
		count += 1
	if lx == CHUNK_SIZE - 1 and not cell.has_wall(MazeCell.Wall.EAST):
		count += 1
	if ly == 0 and not cell.has_wall(MazeCell.Wall.NORTH):
		count += 1
	if ly == CHUNK_SIZE - 1 and not cell.has_wall(MazeCell.Wall.SOUTH):
		count += 1
	return count


func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_SIZE),
		floori(float(cell.y) / CHUNK_SIZE))
