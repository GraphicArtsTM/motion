extends Node3D

# RoomBuilder: пол и потолок — по кваду на чанк, стены — короба
# толщиной 0.2 м целиком внутри своих ячеек. Совпадающих плоскостей
# нет (z-fighting невозможен), стыки sealed заходом за пол/потолок.
# Плинтус и дверные проёмы — room_trim.gd, порча чанка — world_decay.gd.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")

const CELL_SIZE: float = MazeChunk.CELL_SIZE
const WALL_HEIGHT: float = 2.8
const WALL_THICK: float = 0.2
const WALL_Y0: float = -0.05
const WALL_Y1: float = 2.79

const RoomTrim = preload("res://scripts/room_trim.gd")
const WorldDecay = preload("res://scripts/world_decay.gd")
const PropFactory = preload("res://scripts/prop_factory.gd")

var wallpaper_material: ShaderMaterial
var carpet_material: ShaderMaterial
var ceiling_material: ShaderMaterial
var baseboard_material: Material


func _ready() -> void:
	_load_materials()


# Шейдеры мира и фото-фактура к ним (Poly Haven, CC0, textures/CREDITS.md)
func _load_materials() -> void:
	wallpaper_material = _shader_material("wallpaper", {
		"paper_diff": "decrepit_wallpaper_diff_1k", "paper_nor": "decrepit_wallpaper_nor_gl_1k",
		"paper_arm": "decrepit_wallpaper_arm_1k"})
	carpet_material = _shader_material("carpet", {
		"carpet_diff": "dirty_carpet_diff_1k", "carpet_nor": "dirty_carpet_nor_gl_1k",
		"carpet_arm": "dirty_carpet_arm_1k"})
	ceiling_material = _shader_material("ceiling", {
		"tile_nor": "beige_wall_002_nor_gl_1k", "tile_arm": "beige_wall_002_arm_1k"})
	baseboard_material = PropFactory.material_named("baseboard")


func _shader_material(shader_name: String, textures: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/%s.gdshader" % shader_name) as Shader
	for uniform in textures:
		mat.set_shader_parameter(uniform, load("res://textures/%s.jpg" % textures[uniform]))
	return mat


func build_chunk_mesh(chunk) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var array_mesh := ArrayMesh.new()
	var size: float = MazeChunk.CHUNK_SIZE * CELL_SIZE
	_add_plane(array_mesh, 0.0, Vector3.UP, size, carpet_material)
	_add_plane(array_mesh, WALL_HEIGHT, Vector3.DOWN, size, ceiling_material)
	_add_walls(array_mesh, chunk)
	var trim: Dictionary = RoomTrim.build(chunk)
	_add_surface(array_mesh, trim["trim"], wallpaper_material)
	# Коллизия — до плинтуса и наличников: упереться в 2 см отделки нельзя,
	# а треугольники физики дорогие
	var collision: Shape3D = array_mesh.create_trimesh_shape()
	_add_surface(array_mesh, trim["base"], baseboard_material)
	mesh_instance.mesh = array_mesh
	mesh_instance.position = chunk.get_world_position()
	# Порча чанка: её читают шейдеры стен, ковра и потолка (instance uniform)
	mesh_instance.set_instance_shader_parameter("decay",
		WorldDecay.at(Vector2i(chunk.chunk_x, chunk.chunk_y), chunk.style))
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = collision
	static_body.add_child(collision_shape)
	mesh_instance.add_child(static_body)

	return mesh_instance


# Пол или потолок чанка — один квад; нормаль задаёт и сторону обхода
func _add_plane(array_mesh: ArrayMesh, y: float, normal: Vector3, size: float,
		mat: Material) -> void:
	var arrays: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]
	var corners: Array = [Vector3(0, y, 0), Vector3(size, y, 0), Vector3(size, y, size), Vector3(0, y, size)]
	if normal.y < 0.0:
		corners = [corners[0], corners[3], corners[2], corners[1]]
	for c in corners:
		arrays[0].append(c)
		arrays[1].append(normal)
		arrays[2].append(Vector2(c.x, c.z) / CELL_SIZE)
	arrays[3].append_array([0, 1, 2, 0, 2, 3])
	_add_surface(array_mesh, arrays, mat)


# [вершины, нормали, UV, индексы] -> поверхность с материалом (пустые пропускаем)
func _add_surface(array_mesh: ArrayMesh, data: Array, mat: Material) -> void:
	if (data[0] as PackedVector3Array).is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data[0]
	arrays[Mesh.ARRAY_NORMAL] = data[1]
	arrays[Mesh.ARRAY_TEX_UV] = data[2]
	arrays[Mesh.ARRAY_INDEX] = data[3]
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, mat)


func _add_walls(array_mesh: ArrayMesh, chunk) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for y in MazeChunk.CHUNK_SIZE:
		for x in MazeChunk.CHUNK_SIZE:
			var cell = chunk.get_cell(x, y)
			if not cell:
				continue

			var cell_pos := Vector3(x * CELL_SIZE, 0, y * CELL_SIZE)

			if cell.has_wall(MazeCell.Wall.NORTH):
				_add_wall_box(vertices, uvs, normals, indices,
					cell_pos, Vector3.RIGHT, Vector3.BACK)
			if cell.has_wall(MazeCell.Wall.SOUTH):
				_add_wall_box(vertices, uvs, normals, indices,
					cell_pos + Vector3(0, 0, CELL_SIZE), Vector3.RIGHT, Vector3.FORWARD)
			if cell.has_wall(MazeCell.Wall.EAST):
				_add_wall_box(vertices, uvs, normals, indices,
					cell_pos + Vector3(CELL_SIZE, 0, 0), Vector3.BACK, Vector3.LEFT)
			if cell.has_wall(MazeCell.Wall.WEST):
				_add_wall_box(vertices, uvs, normals, indices,
					cell_pos, Vector3.BACK, Vector3.RIGHT)

	if vertices.size() > 0:
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices

		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, wallpaper_material)


# Короб: лицевая грань + 2 торца (грань к соседу всегда спрятана).
func _add_wall_box(vertices: PackedVector3Array, uvs: PackedVector2Array,
		normals: PackedVector3Array, indices: PackedInt32Array,
		edge: Vector3, tangent: Vector3, inward: Vector3) -> void:
	var height := Vector3.UP * (WALL_Y1 - WALL_Y0)
	var face_origin := edge + inward * WALL_THICK + Vector3(0, WALL_Y0, 0)

	_add_quad(vertices, uvs, normals, indices,
		face_origin, tangent * CELL_SIZE, height, inward)
	_add_quad(vertices, uvs, normals, indices,
		edge + Vector3(0, WALL_Y0, 0), inward * WALL_THICK, height, -tangent)
	_add_quad(vertices, uvs, normals, indices,
		edge + tangent * CELL_SIZE + Vector3(0, WALL_Y0, 0),
		inward * WALL_THICK, height, tangent)


func _add_quad(vertices: PackedVector3Array, uvs: PackedVector2Array,
		normals: PackedVector3Array, indices: PackedInt32Array,
		origin: Vector3, axis_u: Vector3, axis_v: Vector3, normal: Vector3) -> void:
	var start_index: int = vertices.size()

	vertices.append(origin)
	vertices.append(origin + axis_v)
	vertices.append(origin + axis_u + axis_v)
	vertices.append(origin + axis_u)

	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(0, axis_v.length()))
	uvs.append(Vector2(axis_u.length(), axis_v.length()))
	uvs.append(Vector2(axis_u.length(), 0))

	for i in 4:
		normals.append(normal)

	indices.append_array([
		start_index, start_index + 1, start_index + 2,
		start_index, start_index + 2, start_index + 3])
