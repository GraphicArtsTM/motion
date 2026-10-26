extends Node3D

signal chunk_loaded(chunk_pos: Vector2i)
signal chunk_unloaded(chunk_pos: Vector2i)
signal chunk_generating(chunk)

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeGenerator = preload("res://scripts/maze_generator.gd")
const RoomBuilder = preload("res://scripts/room_builder.gd")
const LampManager = preload("res://scripts/lamp_manager.gd")
const DecorBuilder = preload("res://scripts/decor_builder.gd")
const HidingSpots = preload("res://scripts/hiding_spots.gd")
const FuseSpawner = preload("res://scripts/fuse_spawner.gd")
const NoteSpawner = preload("res://scripts/note_spawner.gd")

@export var world_seed: int = 12345
@export var load_radius: int = 2
@export var player_path: NodePath = NodePath("../Player")
# Сколько чанков из очереди строить за кадр: сборка одного ~3–4 мс
@export var builds_per_frame: int = 1

var player: Node3D
var generator
var room_builder
var lamp_manager
var decor_builder
var hiding_spots
var fuse_spawner
var note_spawner
var chunks: Dictionary = {}
var chunk_meshes: Dictionary = {}
var last_player_chunk: Vector2i = Vector2i.MAX
# Чанки, у которых уже есть данные, но ещё нет узлов: pos -> {chunk, touched}
var pending: Dictionary = {}
var pending_order: Array[Vector2i] = []


func _ready() -> void:
	player = get_node_or_null(player_path) as Node3D
	
	generator = MazeGenerator.new()
	add_child(generator)
	room_builder = RoomBuilder.new()
	add_child(room_builder)
	lamp_manager = LampManager.new()
	add_child(lamp_manager)
	decor_builder = DecorBuilder.new()
	add_child(decor_builder)
	hiding_spots = HidingSpots.new()
	add_child(hiding_spots)
	fuse_spawner = FuseSpawner.new()
	add_child(fuse_spawner)
	note_spawner = NoteSpawner.new()
	add_child(note_spawner)
	
	if player:
		force_update()
	else:
		push_error("[ChunkManager] Player not found at: " + str(player_path))


func _process(_delta: float) -> void:
	if not player:
		return
	
	var player_chunk: Vector2i = MazeChunk.world_to_chunk(player.global_position)
	
	# Кадр перехода уже занят расчётом данных новых чанков — строить
	# начинаем со следующего, чтобы не складывать обе стоимости в один кадр
	var crossed: bool = player_chunk != last_player_chunk
	if crossed:
		last_player_chunk = player_chunk
		_update_chunks()
	# Свой чанк игрок ждать не может: под ногами должен быть пол
	if pending.has(player_chunk):
		_build_pending(player_chunk)
	if crossed:
		return
	for i in builds_per_frame:
		if pending_order.is_empty():
			break
		_build_pending(pending_order[0])


# Данные новых чанков считаются сразу (генерация дешёвая и нужна, чтобы
# прорубить проходы), а узлы — меш, коллизия, лампы — строятся очередью,
# ближние первыми. Пока чанк в очереди, его нет в chunks: сущность туда
# не ходит и не встаёт, а значит не провалится сквозь пол без коллизии
func _update_chunks() -> void:
	var player_chunk: Vector2i = last_player_chunk
	var keep: Dictionary = {}
	for y in range(-load_radius, load_radius + 1):
		for x in range(-load_radius, load_radius + 1):
			keep[player_chunk + Vector2i(x, y)] = true
	
	for chunk_pos in chunks.keys():
		if not keep.has(chunk_pos):
			_unload_chunk(chunk_pos)
	for chunk_pos in pending.keys():
		if not keep.has(chunk_pos):
			pending.erase(chunk_pos)
			pending_order.erase(chunk_pos)
	
	var to_load: Array = []
	for chunk_pos in keep.keys():
		if not chunks.has(chunk_pos) and not pending.has(chunk_pos):
			to_load.append(chunk_pos)
	to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - player_chunk).length_squared() < (b - player_chunk).length_squared())
	for chunk_pos in to_load:
		_prepare_chunk(chunk_pos)


func _prepare_chunk(chunk_pos: Vector2i) -> void:
	var chunk = MazeChunk.new(chunk_pos.x, chunk_pos.y)
	generator.generate_chunk(chunk, world_seed)
	chunk_generating.emit(chunk)
	
	# Соседа, у которого уже есть меш, после прорубки прохода надо
	# перестроить — но лишь когда встанет и этот чанк, иначе проход
	# откроется в пустоту. Соседей из очереди не трогаем: их меш ещё
	# не построен и сразу выйдет с проходом
	var touched: Array[Vector2i] = []
	for neighbor_offset in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var neighbor_pos: Vector2i = chunk_pos + neighbor_offset
		if chunks.has(neighbor_pos):
			generator.connect_chunks(chunk, chunks[neighbor_pos], world_seed)
			touched.append(neighbor_pos)
		elif pending.has(neighbor_pos):
			generator.connect_chunks(chunk, pending[neighbor_pos]["chunk"], world_seed)
	pending[chunk_pos] = {"chunk": chunk, "touched": touched}
	pending_order.append(chunk_pos)


func _build_pending(chunk_pos: Vector2i) -> void:
	var entry: Dictionary = pending[chunk_pos]
	pending.erase(chunk_pos)
	pending_order.erase(chunk_pos)
	chunks[chunk_pos] = entry["chunk"]
	_build_chunk_nodes(chunk_pos, entry["chunk"])
	for neighbor_pos in entry["touched"]:
		if chunks.has(neighbor_pos):
			_build_chunk_nodes(neighbor_pos, chunks[neighbor_pos])
	chunk_loaded.emit(chunk_pos)


# Постройка/перестройка узлов чанка (меш + лампы)
func _build_chunk_nodes(chunk_pos: Vector2i, chunk) -> void:
	if chunk_meshes.has(chunk_pos):
		(chunk_meshes[chunk_pos] as MeshInstance3D).queue_free()
	
	var mesh_instance: MeshInstance3D = room_builder.build_chunk_mesh(chunk)
	add_child(mesh_instance)
	chunk_meshes[chunk_pos] = mesh_instance
	lamp_manager.add_lamps(chunk)
	hiding_spots.add_spots(chunk, world_seed)
	fuse_spawner.add_fuses(chunk, world_seed)
	note_spawner.add_notes(chunk, world_seed)
	decor_builder.clear_decor(chunk_pos)
	decor_builder.build_decor(chunk, world_seed)


func _unload_chunk(chunk_pos: Vector2i) -> void:
	if not chunks.has(chunk_pos):
		return
	
	if chunk_meshes.has(chunk_pos):
		var mesh: MeshInstance3D = chunk_meshes[chunk_pos]
		mesh.queue_free()
		chunk_meshes.erase(chunk_pos)
	
	chunks.erase(chunk_pos)
	lamp_manager.remove_lamps(chunk_pos)
	hiding_spots.remove_spots(chunk_pos)
	fuse_spawner.remove_fuses(chunk_pos)
	note_spawner.remove_notes(chunk_pos)
	decor_builder.clear_decor(chunk_pos)
	chunk_unloaded.emit(chunk_pos)


func get_chunk_at_position(world_pos: Vector3):
	var chunk_pos: Vector2i = MazeChunk.world_to_chunk(world_pos)
	return chunks.get(chunk_pos)


# Без очереди: старт мира и смена дальности в настройках строят всё сразу
func force_update() -> void:
	if player:
		last_player_chunk = MazeChunk.world_to_chunk(player.global_position)
		_update_chunks()
		while not pending_order.is_empty():
			_build_pending(pending_order[0])
