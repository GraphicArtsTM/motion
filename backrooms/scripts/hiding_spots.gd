extends Node3D

# HidingSpots: расставляет по одному шкафу-укрытию на чанк
# в случайной открытой клетке. Живёт и умирает вместе с чанком.

const HidingSpot = preload("res://scripts/hiding_spot.gd")
const Exit = preload("res://scripts/exit_manager.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")

const CHUNK_SIZE: int = 8
const CELL_METERS: float = 4.0

var spots: Dictionary = {}
var player_ref = null
var hud_ref = null


func _ready() -> void:
	player_ref = get_tree().get_first_node_in_group("player")
	hud_ref = get_tree().get_first_node_in_group("hud")


func add_spots(chunk, world_seed: int) -> void:
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	if spots.has(pos):
		return
	# Выходной чанк — не до пряток. Стартовый — чтобы игрок не родился в шкафу.
	if pos == _exit_chunk() or pos == _spawn_chunk():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed ^ hash(pos)) & 0x7FFFFFFF
	var open_cells: Array = []
	for ly in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			if _wall_count(chunk.get_cell(lx, ly)) <= 2:
				open_cells.append(Vector2i(lx, ly))
	if open_cells.is_empty():
		return
	var pick: Vector2i = open_cells[rng.randi_range(0, open_cells.size() - 1)]
	# Дверца — на свободную сторону клетки, иначе при выходе
	# игрок окажется в стене.
	var facing = _open_facing(chunk.get_cell(pick.x, pick.y), rng)
	if facing == null:
		return
	var spot = HidingSpot.new()
	spot.position = chunk.get_world_position() + Vector3(
		(pick.x + 0.5) * CELL_METERS, 0.0, (pick.y + 0.5) * CELL_METERS)
	spot.rotation.y = facing
	spot.setup(player_ref, hud_ref)
	add_child(spot)
	spots[pos] = [spot]


# Угол поворота шкафа так, чтобы его дверца (+Z) смотрела в проход.
# SOUTH открыт → 0, EAST → PI/2, NORTH → PI, WEST → -PI/2.
func _open_facing(cell, rng: RandomNumberGenerator):
	if cell == null:
		return null
	var angles: Array = []
	if not cell.has_wall(MazeCell.Wall.SOUTH):
		angles.append(0.0)
	if not cell.has_wall(MazeCell.Wall.EAST):
		angles.append(PI * 0.5)
	if not cell.has_wall(MazeCell.Wall.NORTH):
		angles.append(PI)
	if not cell.has_wall(MazeCell.Wall.WEST):
		angles.append(-PI * 0.5)
	if angles.is_empty():
		return null
	return angles[rng.randi_range(0, angles.size() - 1)]


func remove_spots(chunk_pos: Vector2i) -> void:
	if spots.has(chunk_pos):
		for spot in spots[chunk_pos]:
			if (spot as Node3D) and spot.occupied:
				spot._exit_hide()
			(spot as Node3D).queue_free()
		spots.erase(chunk_pos)


func _exit_chunk() -> Vector2i:
	return Vector2i(floori(float(Exit.TARGET.x) / CHUNK_SIZE),
		floori(float(Exit.TARGET.y) / CHUNK_SIZE))


func _spawn_chunk() -> Vector2i:
	return Vector2i.ZERO


func _wall_count(cell) -> int:
	if cell == null:
		return 99
	var count := 0
	var walls: int = cell.walls
	while walls > 0:
		count += walls & 1
		walls = walls >> 1
	return count
