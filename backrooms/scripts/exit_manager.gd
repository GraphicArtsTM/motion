extends Node3D

# ExitManager: ставит дверь-выход в расчищенную площадь 3×3 далеко
# от старта, держит её жизнь вместе с чанком и решает победу.
# Устройство самой двери, её питание и подсказки — в exit_door.gd.

const MazeCell = preload("res://scripts/maze_cell.gd")
const ExitDoor = preload("res://scripts/exit_door.gd")
const ExitPower = preload("res://scripts/exit_power.gd")

const TARGET := Vector2i(144, -86)
const CHUNK_SIZE: int = 8
const CELL_METERS: float = 4.0

@export var hud_path: NodePath
@export var chunk_manager_path: NodePath = NodePath("../ChunkManager")

var hud
var door = null
var power = null
var has_won: bool = false


func _ready() -> void:
	hud = get_node_or_null(hud_path)
	# Питание живёт на менеджере: выгрузка чанка с дверью его не теряет
	power = ExitPower.new()
	var chunk_manager = get_node_or_null(chunk_manager_path)
	if chunk_manager:
		chunk_manager.chunk_generating.connect(_on_chunk_generating)
		chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
		chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)


func _process(_delta: float) -> void:
	if has_won or door == null or not door.player_inside:
		return
	if Input.is_action_just_pressed("interact") and door.interact():
		has_won = true
		if hud and hud.has_method("show_win"):
			hud.show_win("Ты запитал дверь и ушёл из Backrooms.")


func target_world_pos() -> Vector3:
	return Vector3((TARGET.x + 0.5) * CELL_METERS, 0.0,
		(TARGET.y + 0.5) * CELL_METERS)


func _plaza_rect() -> Rect2i:
	return Rect2i(TARGET - Vector2i(1, 1), Vector2i(3, 3))


# Расчистка площади: каждый чанк чистит стены СВОИХ клеток
# (вторую сторону чистит сосед при своей загрузке).
func _on_chunk_generating(chunk) -> void:
	var plaza := _plaza_rect()
	var dirs := [MazeCell.Wall.NORTH, MazeCell.Wall.EAST,
		MazeCell.Wall.SOUTH, MazeCell.Wall.WEST]
	for ly in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var cell = chunk.get_cell(lx, ly)
			if cell == null:
				continue
			var g := Vector2i(chunk.chunk_x * CHUNK_SIZE + lx,
				chunk.chunk_y * CHUNK_SIZE + ly)
			for direction in dirs:
				var offset: Vector2i = cell.get_neighbor_offset(direction)
				var n := g + offset
				if plaza.has_point(g) or plaza.has_point(n):
					var neighbor = chunk.get_cell(lx + offset.x, ly + offset.y)
					_open_both(cell, neighbor, direction)


func _open_both(cell, neighbor, direction) -> void:
	if cell:
		cell.remove_wall(direction)
	if neighbor:
		neighbor.remove_wall(cell.get_opposite_wall(direction))


func _on_chunk_loaded(chunk_pos: Vector2i) -> void:
	if door == null and _chunk_has_target(chunk_pos):
		door = ExitDoor.new()
		door.position = target_world_pos()
		door.setup(hud, get_tree().get_first_node_in_group("player_items"), power)
		add_child(door)


func _on_chunk_unloaded(chunk_pos: Vector2i) -> void:
	if door and _chunk_has_target(chunk_pos):
		door.queue_free()
		door = null
		if hud and hud.has_method("hide_hint"):
			hud.hide_hint()


func _chunk_has_target(chunk_pos: Vector2i) -> bool:
	return Rect2i(chunk_pos * CHUNK_SIZE,
		Vector2i(CHUNK_SIZE, CHUNK_SIZE)).has_point(TARGET)
