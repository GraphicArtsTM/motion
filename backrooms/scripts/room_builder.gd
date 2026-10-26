extends Node3D

# RoomBuilder: пол и потолок — по кваду на чанк, стены — короба
# толщиной 0.2 м целиком внутри своих ячеек. Совпадающих плоскостей
# нет (z-fighting невозможен), стыки sealed заходом за пол/потолок.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")

const CELL_SIZE: float = 4.0
const WALL_HEIGHT: float = 2.8
const WALL_THICK: float = 0.2
const WALL_Y0: float = -0.05
const WALL_Y1: float = 2.79

var wallpaper_material: ShaderMaterial
var carpet_material: ShaderMaterial
var ceiling_material: ShaderMaterial


func _ready() -> void:
	_load_materials()


func _load_materials() -> void:
	var wallpaper_shader := load("res://shaders/wallpaper.gdshader") as Shader
	var carpet_shader := load("res://shaders/carpet.gdshader") as Shader
	var ceiling_shader := load("res://shaders/ceiling.gdshader") as Shader

	wallpaper_material = ShaderMaterial.new()
	wallpaper_material.shader = wallpaper_shader
	carpet_material = ShaderMaterial.new()
	carpet_material.shader = carpet_shader
	ceiling_material = ShaderMaterial.new()
	ceiling_material.shader = ceiling_shader


func build_chunk_mesh(chunk) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var array_mesh := ArrayMesh.new()
	_add_floor(array_mesh, chunk)
	_add_ceiling(array_mesh, chunk)
	_add_walls(array_mesh, chunk)
	mesh_instance.mesh = array_mesh
	mesh_instance.position = chunk.get_world_position()
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()
	static_body.add_child(collision_shape)
	mesh_instance.add_child(static_body)

	return mesh_instance


func _add_floor(array_mesh: ArrayMesh, chunk) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var size: float = MazeChunk.CHUNK_SIZE * CELL_SIZE

	vertices.append(Vector3(0, 0, 0))
	vertices.append(Vector3(size, 0, 0))
	vertices.append(Vector3(size, 0, size))
	vertices.append(Vector3(0, 0, size))
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(size / CELL_SIZE, 0))
	uvs.append(Vector2(size / CELL_SIZE, size / CELL_SIZE))
	uvs.append(Vector2(0, size / CELL_SIZE))
	for i in 4:
		normals.append(Vector3.UP)
	indices.append_array([0, 1, 2, 0, 2, 3])

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, carpet_material)


func _add_ceiling(array_mesh: ArrayMesh, chunk) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var size: float = MazeChunk.CHUNK_SIZE * CELL_SIZE

	vertices.append(Vector3(0, WALL_HEIGHT, 0))
	vertices.append(Vector3(0, WALL_HEIGHT, size))
	vertices.append(Vector3(size, WALL_HEIGHT, size))
	vertices.append(Vector3(size, WALL_HEIGHT, 0))
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(0, size / CELL_SIZE))
	uvs.append(Vector2(size / CELL_SIZE, size / CELL_SIZE))
	uvs.append(Vector2(size / CELL_SIZE, 0))
	for i in 4:
		normals.append(Vector3.DOWN)
	indices.append_array([0, 1, 2, 0, 2, 3])

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, ceiling_material)


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
