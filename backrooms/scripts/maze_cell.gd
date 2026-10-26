extends RefCounted

# Направления стен
enum Wall { NORTH = 1, EAST = 2, SOUTH = 4, WEST = 8 }

var x: int
var y: int
var walls: int = 15  # Все стены (1111 в бинарном)
# Дверные проёмы на открытых сторонах — те же биты, что у стен (maze_doors.gd)
var doors: int = 0
var visited: bool = false


func _init(cell_x: int, cell_y: int) -> void:
	x = cell_x
	y = cell_y


func has_wall(direction: Wall) -> bool:
	return (walls & direction) != 0


func remove_wall(direction: Wall) -> void:
	walls &= ~direction


func add_wall(direction: Wall) -> void:
	walls |= direction


func get_opposite_wall(direction: Wall) -> Wall:
	match direction:
		Wall.NORTH: return Wall.SOUTH
		Wall.SOUTH: return Wall.NORTH
		Wall.EAST: return Wall.WEST
		Wall.WEST: return Wall.EAST
		_: return Wall.NORTH


func get_neighbor_offset(direction: Wall) -> Vector2i:
	match direction:
		Wall.NORTH: return Vector2i(0, -1)
		Wall.SOUTH: return Vector2i(0, 1)
		Wall.EAST: return Vector2i(1, 0)
		Wall.WEST: return Vector2i(-1, 0)
		_: return Vector2i.ZERO


# Прорубить стену между двумя клетками. Соседа может и не быть —
# тогда это граница чанка, и её трогает только connect_chunks
static func open_between(cell_a, cell_b, direction) -> void:
	if cell_a == null or cell_b == null:
		return
	cell_a.remove_wall(direction)
	cell_b.remove_wall(cell_a.get_opposite_wall(direction))


# Сколько стен у клетки. 4 — клетка замурована со всех сторон
static func wall_count(cell) -> int:
	if cell == null:
		return 4
	var count := 0
	var walls: int = cell.walls
	while walls > 0:
		count += walls & 1
		walls = walls >> 1
	return count


static func directions() -> Array:
	return [Wall.NORTH, Wall.EAST, Wall.SOUTH, Wall.WEST]


func get_available_directions() -> Array:
	var dirs: Array = []
	if has_wall(Wall.NORTH): dirs.append(Wall.NORTH)
	if has_wall(Wall.EAST): dirs.append(Wall.EAST)
	if has_wall(Wall.SOUTH): dirs.append(Wall.SOUTH)
	if has_wall(Wall.WEST): dirs.append(Wall.WEST)
	return dirs
