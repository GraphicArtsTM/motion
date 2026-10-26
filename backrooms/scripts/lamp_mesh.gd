extends RefCounted

# LampMesh: меш светильников чанка — светящиеся панели в каждой клетке и
# тёмные ободки корпусов вокруг них, всё одним мешем на чанк (мерцание —
# в шейдере панелей). Свет, гул и порчу ламп решает lamp_manager.gd.

const MazeChunk = preload("res://scripts/maze_chunk.gd")

const PANEL_W: float = 1.2
const PANEL_D: float = 0.6
const WALL_H: float = 2.8


# Один меш: светящиеся панели + тёмные корпуса-ободки вокруг них
static func build(lamp_shader: Shader) -> ArrayMesh:
	var array_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var dvert := PackedVector3Array()
	var duv := PackedVector2Array()
	var dnorm := PackedVector3Array()
	var didx := PackedInt32Array()

	for y in MazeChunk.CHUNK_SIZE:
		for x in MazeChunk.CHUNK_SIZE:
			var cx := x * MazeChunk.CELL_SIZE + MazeChunk.CELL_SIZE * 0.5
			var cz := y * MazeChunk.CELL_SIZE + MazeChunk.CELL_SIZE * 0.5
			_add_panel_quad(vertices, uvs, normals, indices,
				Vector3(cx, WALL_H - 0.05, cz))
			_add_housing_rim(dvert, duv, dnorm, didx, Vector3(cx, WALL_H - 0.05, cz))

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = lamp_shader
	array_mesh.surface_set_material(0, material)

	if dvert.size() > 0:
		var dark := []
		dark.resize(Mesh.ARRAY_MAX)
		dark[Mesh.ARRAY_VERTEX] = dvert
		dark[Mesh.ARRAY_TEX_UV] = duv
		dark[Mesh.ARRAY_NORMAL] = dnorm
		dark[Mesh.ARRAY_INDEX] = didx
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, dark)
		var housing_mat := StandardMaterial3D.new()
		housing_mat.albedo_color = Color(0.2, 0.19, 0.17)
		housing_mat.roughness = 0.7
		array_mesh.surface_set_material(1, housing_mat)
	return array_mesh


# Ободок корпуса: 4 боковые грани вокруг панели
static func _add_housing_rim(vertices: PackedVector3Array, uvs: PackedVector2Array,
		normals: PackedVector3Array, indices: PackedInt32Array, center: Vector3) -> void:
	var hw := PANEL_W * 0.5 + 0.05
	var hd := PANEL_D * 0.5 + 0.05
	var top := center.y + 0.08
	var bottom := center.y
	_add_rim_quad(vertices, uvs, normals, indices,
		Vector3(center.x - hw, bottom, center.z - hd), Vector3(center.x + hw, bottom, center.z - hd),
		Vector3(center.x + hw, top, center.z - hd), Vector3(center.x - hw, top, center.z - hd), Vector3.FORWARD)
	_add_rim_quad(vertices, uvs, normals, indices,
		Vector3(center.x + hw, bottom, center.z + hd), Vector3(center.x - hw, bottom, center.z + hd),
		Vector3(center.x - hw, top, center.z + hd), Vector3(center.x + hw, top, center.z + hd), Vector3.BACK)
	_add_rim_quad(vertices, uvs, normals, indices,
		Vector3(center.x + hw, bottom, center.z - hd), Vector3(center.x + hw, bottom, center.z + hd),
		Vector3(center.x + hw, top, center.z + hd), Vector3(center.x + hw, top, center.z - hd), Vector3.RIGHT)
	_add_rim_quad(vertices, uvs, normals, indices,
		Vector3(center.x - hw, bottom, center.z + hd), Vector3(center.x - hw, bottom, center.z - hd),
		Vector3(center.x - hw, top, center.z - hd), Vector3(center.x - hw, top, center.z + hd), Vector3.LEFT)


static func _add_rim_quad(vertices: PackedVector3Array, uvs: PackedVector2Array,
		normals: PackedVector3Array, indices: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var start_index: int = vertices.size()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	vertices.append(d)
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(1, 0))
	uvs.append(Vector2(1, 1))
	uvs.append(Vector2(0, 1))
	for i in 4:
		normals.append(normal)
	indices.append_array([start_index, start_index + 1, start_index + 2,
		start_index, start_index + 2, start_index + 3])


static func _add_panel_quad(vertices: PackedVector3Array, uvs: PackedVector2Array,
		normals: PackedVector3Array, indices: PackedInt32Array, center: Vector3) -> void:
	var start_index: int = vertices.size()
	var hw := PANEL_W * 0.5
	var hd := PANEL_D * 0.5

	vertices.append(center + Vector3(-hw, 0, -hd))
	vertices.append(center + Vector3(hw, 0, -hd))
	vertices.append(center + Vector3(hw, 0, hd))
	vertices.append(center + Vector3(-hw, 0, hd))

	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(1, 0))
	uvs.append(Vector2(1, 1))
	uvs.append(Vector2(0, 1))

	for i in 4:
		normals.append(Vector3.DOWN)

	indices.append_array([
		start_index, start_index + 1, start_index + 2,
		start_index, start_index + 2, start_index + 3])
