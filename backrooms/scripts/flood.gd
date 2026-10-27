extends RefCounted

# Flood: затопленные сектора. Где-то лопнули трубы: ковёр под слоем
# мутной воды по щиколотку, с потолка капает. Вода меняет игру: шаг в ней
# — плеск, его слышно дальше (шум игрока ×1.6 для слуха сущности), идти
# тяжелее (ход ×0.8) — и самой сущности тоже, а её шаги по воде слышно
# издалека. Поле низкочастотное, как у darkness.gd: сектор — 2–4 чанка,
# у старта воды нет. Всё — функция координат чанка.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const AudioWater = preload("res://scripts/audio_water.gd")
const AudioBank = preload("res://scripts/audio_bank.gd")
const FuseSpawner = preload("res://scripts/fuse_spawner.gd")
const ExitManager = preload("res://scripts/exit_manager.gd")

const THRESHOLD: float = 0.6
const WATER_Y: float = 0.07
const NOISE_MULT: float = 1.6
const SPEED_MULT: float = 0.8

static var _material: ShaderMaterial = null


static func is_flooded_chunk(pos: Vector2i) -> bool:
	if absi(pos.x) <= 1 and absi(pos.y) <= 1:
		return false
	# Гладь непрозрачная: чанки предохранителей и двери выхода сухие,
	# иначе ключевое лежало бы под водой
	if pos == _chunk_of(ExitManager.TARGET):
		return false
	for cell: Vector2i in FuseSpawner.CELLS:
		if pos == _chunk_of(cell):
			return false
	# Свои волны, не как у тьмы: вода и мёртвый свет то совпадают, то нет
	var n: float = sin(pos.x * 0.37 - 0.4) * cos(pos.y * 0.41 + 2.2)
	n += 0.55 * cos(pos.x * 0.17 + 1.1) * sin(pos.y * 0.19 - 0.6)
	return n > THRESHOLD


static func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / MazeChunk.CHUNK_SIZE), floori(float(cell.y) / MazeChunk.CHUNK_SIZE))


static func is_flooded_at(world_pos: Vector3) -> bool:
	return is_flooded_chunk(MazeChunk.world_to_chunk(world_pos))


# Множитель хода: в воде медленнее и игрок, и сущность
static func speed_at(world_pos: Vector3) -> float:
	return SPEED_MULT if is_flooded_at(world_pos) else 1.0


static func noise_at(world_pos: Vector3) -> float:
	return NOISE_MULT if is_flooded_at(world_pos) else 1.0


# Гладь воды на весь чанк поверх ковра и капель с потолка. Зовёт
# room_builder.gd уже после коллизии: по дну ходят, а не по воде
static func add_water(array_mesh: ArrayMesh, mesh_instance: MeshInstance3D, chunk) -> void:
	if not is_flooded_chunk(Vector2i(chunk.chunk_x, chunk.chunk_y)):
		return
	var size: float = MazeChunk.CHUNK_SIZE * MazeChunk.CELL_SIZE
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, WATER_Y, 0), Vector3(size, WATER_Y, 0),
		Vector3(size, WATER_Y, size), Vector3(0, WATER_Y, size)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, material())
	# Капель: по одному источнику на угол чанка, петли разной высоты
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(chunk.chunk_x, chunk.chunk_y)) & 0x7FFFFFFF
	for i in 2:
		var drip := AudioBank.source("Ambient", AudioWater.drips(), 4.0)
		drip.position = Vector3(rng.randf_range(4.0, size - 4.0), 2.4, rng.randf_range(4.0, size - 4.0))
		drip.max_distance = 22.0
		drip.volume_db = -14.0
		drip.pitch_scale = rng.randf_range(0.85, 1.15)
		# Чанк попадёт в дерево позже — заиграет сам при входе
		drip.autoplay = true
		mesh_instance.add_child(drip)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/water.gdshader") as Shader
	return _material
