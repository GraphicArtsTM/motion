extends RefCounted

const MazeCell = preload("res://scripts/maze_cell.gd")

const CHUNK_SIZE: int = 8  # 8×8 ячеек
const CELL_SIZE: float = 4.0  # 4 метра

var chunk_x: int
var chunk_y: int
var cells: Array = []
var style: int = -1  # MazeZone.Style района, в который попал чанк
var is_generated: bool = false


func _init(cx: int, cy: int) -> void:
	chunk_x = cx
	chunk_y = cy
	_initialize_cells()


func _initialize_cells() -> void:
	cells.clear()
	cells.resize(CHUNK_SIZE * CHUNK_SIZE)
	
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var cell = MazeCell.new(x, y)
			cells[y * CHUNK_SIZE + x] = cell


func get_cell(local_x: int, local_y: int):
	if local_x < 0 or local_x >= CHUNK_SIZE or local_y < 0 or local_y >= CHUNK_SIZE:
		return null
	return cells[local_y * CHUNK_SIZE + local_x]


func get_world_position() -> Vector3:
	return Vector3(
		chunk_x * CHUNK_SIZE * CELL_SIZE,
		0.0,
		chunk_y * CHUNK_SIZE * CELL_SIZE
	)


func get_global_cell_pos(local_x: int, local_y: int) -> Vector2i:
	return Vector2i(
		chunk_x * CHUNK_SIZE + local_x,
		chunk_y * CHUNK_SIZE + local_y
	)


static func world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / (CHUNK_SIZE * CELL_SIZE)),
		floori(world_pos.z / (CHUNK_SIZE * CELL_SIZE))
	)


static func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / CELL_SIZE),
		floori(world_pos.z / CELL_SIZE)
	)
