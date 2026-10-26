extends Node3D

# DecorBuilder: мелочи жизни лабиринта. Строит один меш на чанк: ложное
# свечение выхода в тупике, царапины на стенах, мусор на полу; следы
# хоррора — decor_horror.gd. Всё детерминировано сидом чанка.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const DecorHorror = preload("res://scripts/decor_horror.gd")

const CELL_METERS: float = MazeChunk.CELL_SIZE

var glow_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var chunk_decor: Dictionary = {}


func _ready() -> void:
	glow_mat = StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.3, 1.0, 0.55)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.35, 1.0, 0.55)
	glow_mat.emission_energy_multiplier = 1.6
	dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.16, 0.13, 0.1)
	dark_mat.roughness = 0.95
	# Плоские наклейки декора: у половины квадов обход вершин идёт против
	# нормали, поэтому без отсечения задних граней часть наклеек пропадает
	dark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func build_decor(chunk, world_seed: int) -> void:
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	if chunk_decor.has(pos):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed ^ hash(pos)) & 0x7FFFFFFF

	var glow := _new_surface()
	var dark := _new_surface()
	_add_fake_exit(chunk, rng, glow)
	_add_wall_marks(chunk, rng, dark)
	_add_debris(chunk, rng, dark)
	_add_pipes(chunk, rng, dark)

	var array_mesh := ArrayMesh.new()
	_add_surface_if_filled(array_mesh, glow, glow_mat)
	_add_surface_if_filled(array_mesh, dark, dark_mat)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	mesh_instance.position = chunk.get_world_position()
	add_child(mesh_instance)
	DecorHorror.add(mesh_instance, chunk, world_seed)
	chunk_decor[pos] = mesh_instance


func clear_decor(chunk_pos: Vector2i) -> void:
	if chunk_decor.has(chunk_pos):
		(chunk_decor[chunk_pos] as MeshInstance3D).queue_free()
		chunk_decor.erase(chunk_pos)


func _new_surface() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()
	return arrays


func _add_surface_if_filled(array_mesh: ArrayMesh, surface: Array, mat: Material) -> void:
	var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	if vertices.size() == 0:
		return
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, mat)


# Ложный выход: зелёное свечение на глухой стене тупика.
func _add_fake_exit(chunk, rng: RandomNumberGenerator, glow: Array) -> void:
	var dead_ends: Array = []
	for y in MazeChunk.CHUNK_SIZE:
		for x in MazeChunk.CHUNK_SIZE:
			if MazeCell.wall_count(chunk.get_cell(x, y)) == 3:
				dead_ends.append(Vector2i(x, y))
	if dead_ends.is_empty() or rng.randf() > 0.45:
		return
	var pick: Vector2i = dead_ends[rng.randi_range(0, dead_ends.size() - 1)]
	var cell = chunk.get_cell(pick.x, pick.y)
	for direction in [MazeCell.Wall.NORTH, MazeCell.Wall.EAST,
			MazeCell.Wall.SOUTH, MazeCell.Wall.WEST]:
		if not cell.has_wall(direction):
			var frame := _wall_frame(pick.x, pick.y,
				cell.get_opposite_wall(direction))
			var center: Vector3 = frame[0] + frame[1] * 2.0 \
				+ Vector3(0, 1.4, 0) + frame[2] * 0.23
			_add_centered_quad(glow, center, 1.2, 1.8, frame[1], frame[2])
			return


# Тёмные царапины на случайных стенах.
func _add_wall_marks(chunk, rng: RandomNumberGenerator, dark: Array) -> void:
	for i in 3:
		var x: int = rng.randi_range(0, MazeChunk.CHUNK_SIZE - 1)
		var y: int = rng.randi_range(0, MazeChunk.CHUNK_SIZE - 1)
		var cell = chunk.get_cell(x, y)
		var walls: Array = cell.get_available_directions()
		if walls.is_empty():
			continue
		var direction = walls[rng.randi_range(0, walls.size() - 1)]
		var frame := _wall_frame(x, y, direction)
		var center: Vector3 = frame[0] + frame[1] * rng.randf_range(1.0, 3.0) \
			+ Vector3(0, rng.randf_range(0.8, 1.8), 0) + frame[2] * 0.23
		_add_centered_quad(dark, center, rng.randf_range(0.4, 0.6),
			rng.randf_range(0.7, 1.0), frame[1], frame[2])


# Плоский мусор на полу: зацепиться не за что, коллизия не нужна.
func _add_debris(chunk, rng: RandomNumberGenerator, dark: Array) -> void:
	for i in 6:
		var x: float = rng.randi_range(0, MazeChunk.CHUNK_SIZE - 1) * CELL_METERS
		var z: float = rng.randi_range(0, MazeChunk.CHUNK_SIZE - 1) * CELL_METERS
		var center := Vector3(x + rng.randf_range(0.5, 3.5), 0.02,
			z + rng.randf_range(0.5, 3.5))
		_add_centered_quad(dark, center, rng.randf_range(0.3, 0.5),
			rng.randf_range(0.3, 0.5), Vector3.RIGHT, Vector3.UP, Vector3.BACK)


# Трубы под потолком вдоль стен: взгляд всегда цепляется за них,
# а стоят они ровно там, где панели не бьют светом
func _add_pipes(chunk, rng: RandomNumberGenerator, dark: Array) -> void:
	for i in 2:
		var x: int = rng.randi_range(0, MazeChunk.CHUNK_SIZE - 1)
		var y: int = rng.randi_range(0, MazeChunk.CHUNK_SIZE - 1)
		var cell = chunk.get_cell(x, y)
		var walls: Array = cell.get_available_directions()
		if walls.is_empty():
			continue
		var frame := _wall_frame(x, y, walls[rng.randi_range(0, walls.size() - 1)])
		var axis: Vector3 = frame[1]
		var inward: Vector3 = frame[2]
		# Отступ от стены: короб стены занимает 0.2 м, иначе труба вмурована
		var center: Vector3 = frame[0] + axis * 2.0 + inward * 0.28 \
			+ Vector3(0, 2.6, 0)
		_add_centered_quad(dark, center - Vector3.UP * 0.07, 4.0, 0.14, axis, Vector3.DOWN, inward)
		_add_centered_quad(dark, center + inward * 0.07, 4.0, 0.14, axis, inward, Vector3.UP)
		_add_centered_quad(dark, center - inward * 0.07, 4.0, 0.14, axis, -inward, Vector3.UP)



# Угол стены + касательная + нормаль внутрь (как в room_builder).
func _wall_frame(x: int, y: int, direction) -> Array:
	var cell_pos := Vector3(x * CELL_METERS, 0, y * CELL_METERS)
	match direction:
		MazeCell.Wall.NORTH:
			return [cell_pos, Vector3.RIGHT, Vector3.BACK]
		MazeCell.Wall.SOUTH:
			return [cell_pos + Vector3(0, 0, CELL_METERS), Vector3.RIGHT, Vector3.FORWARD]
		MazeCell.Wall.EAST:
			return [cell_pos + Vector3(CELL_METERS, 0, 0), Vector3.BACK, Vector3.LEFT]
		_:
			return [cell_pos, Vector3.BACK, Vector3.RIGHT]


func _add_centered_quad(arrays: Array, center: Vector3, width: float,
		height: float, tangent: Vector3, normal: Vector3,
		up: Vector3 = Vector3.UP) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var start_index: int = vertices.size()
	var hw := tangent * width * 0.5
	var hh := up * height * 0.5
	vertices.append(center - hw - hh)
	vertices.append(center - hw + hh)
	vertices.append(center + hw + hh)
	vertices.append(center + hw - hh)
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(0, 1))
	uvs.append(Vector2(1, 1))
	uvs.append(Vector2(1, 0))
	for i in 4:
		normals.append(normal)
	indices.append_array([start_index, start_index + 1, start_index + 2,
		start_index, start_index + 2, start_index + 3])
