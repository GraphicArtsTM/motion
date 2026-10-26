extends Node3D

# LampManager: панели на потолке каждой ячейки чанка (один меш на чанк,
# мерцание в шейдере) + один OmniLight на чанк + гул ламп в AudioStreamPlayer3D.
# Гул — синтезированная петля из audio_bank.gd, аудиофайлов нет вообще.
# В тёмных участках (darkness.gd) панели мертвы, света и гула нет — там
# остаётся только фонарь игрока.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const AudioBank = preload("res://scripts/audio_bank.gd")
const Darkness = preload("res://scripts/darkness.gd")

const PANEL_W: float = 1.2
const PANEL_D: float = 0.6
const WALL_H: float = 2.8
const LIGHT_ENERGY: float = 1.1
# 26, а не 20: лампа в центре чанка 32×32 м должна дотягиваться до углов
const LIGHT_RANGE: float = 26.0
const HUM_VOLUME_DB: float = -24.0

var lamp_shader: Shader
var chunk_nodes: Dictionary = {}


func _ready() -> void:
	lamp_shader = load("res://shaders/lamp_panel.gdshader") as Shader


func add_lamps(chunk) -> void:
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	if chunk_nodes.has(pos):
		return

	var origin: Vector3 = chunk.get_world_position()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_panels_mesh()
	mesh_instance.position = origin
	mesh_instance.add_to_group("lamp_panels")
	add_child(mesh_instance)

	# Тьма по чанкам: часть пролётов заметно темнее — статично,
	# детерминированно от координат, чтобы мир не «дышал» хором
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos) & 0x7FFFFFFF
	var dark: bool = Darkness.is_dark_chunk(pos)
	var brightness: float = 0.0 if dark else rng.randf_range(0.6, 1.15)
	var panel := mesh_instance.mesh.surface_get_material(0) as ShaderMaterial
	if panel:
		panel.set_shader_parameter("brightness", brightness)
		# Мёртвый участок: все панели погашены, свет даёт только фонарь
		panel.set_shader_parameter("dead_ratio", 1.0 if dark else 0.06)

	var light := OmniLight3D.new()
	var mid: float = MazeChunk.CHUNK_SIZE * MazeChunk.CELL_SIZE * 0.5
	light.position = origin + Vector3(mid, WALL_H - 0.3, mid)
	light.light_color = Color(1.0, 0.93, 0.78)
	light.visible = not dark
	light.light_energy = LIGHT_ENERGY * brightness * 1.15
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.add_to_group("lamp_lights")
	add_child(light)

	# Гул ламп: синтезированная петля, высота чуть гуляет по чанкам.
	# В тёмном участке лампа не гудит вовсе — тишина и есть примета тьмы
	var hum := AudioBank.source("Ambient", AudioBank.hum(), 6.0)
	hum.position = light.position
	hum.volume_db = -80.0 if dark else HUM_VOLUME_DB
	hum.pitch_scale = rng.randf_range(0.96, 1.04)
	add_child(hum)
	# Петля стартует не с нуля: синхронные гумы раскачивали реверб Ambient.
	# Смещение — через play(from), иначе seek() сразу после play() у
	# AudioStreamPlayer3D теряется и все гумы начинают с нуля
	hum.play(rng.randf_range(0.0, 1.5))

	chunk_nodes[pos] = {"mesh": mesh_instance, "light": light, "hum": hum}


func remove_lamps(chunk_pos: Vector2i) -> void:
	if not chunk_nodes.has(chunk_pos):
		return
	var entry: Dictionary = chunk_nodes[chunk_pos]
	(entry["mesh"] as MeshInstance3D).queue_free()
	(entry["light"] as OmniLight3D).queue_free()
	(entry["hum"] as AudioStreamPlayer3D).queue_free()
	chunk_nodes.erase(chunk_pos)


# Один меш: светящиеся панели + тёмные корпуса-ободки вокруг них
func _build_panels_mesh() -> ArrayMesh:
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
func _add_housing_rim(vertices: PackedVector3Array, uvs: PackedVector2Array,
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


func _add_rim_quad(vertices: PackedVector3Array, uvs: PackedVector2Array,
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


func _add_panel_quad(vertices: PackedVector3Array, uvs: PackedVector2Array,
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
