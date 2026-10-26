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

@export var world_seed: int = 12345
@export var load_radius: int = 2
@export var player_path: NodePath = NodePath("../Player")

var player: Node3D
var generator
var room_builder
var lamp_manager
var decor_builder
var hiding_spots
var fuse_spawner
var chunks: Dictionary = {}
var chunk_meshes: Dictionary = {}
var last_player_chunk: Vector2i = Vector2i.MAX


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
	
	if player:
		last_player_chunk = MazeChunk.world_to_chunk(player.global_position)
		_update_chunks()
	else:
		push_error("[ChunkManager] Player not found at: " + str(player_path))


func _process(_delta: float) -> void:
	if not player:
		return
	
	var player_chunk: Vector2i = MazeChunk.world_to_chunk(player.global_position)
	
	if player_chunk != last_player_chunk:
		last_player_chunk = player_chunk
		_update_chunks()


func _update_chunks() -> void:
	var player_chunk: Vector2i = last_player_chunk
	var chunks_to_load: Array[Vector2i] = []
	var chunks_to_keep: Array[Vector2i] = []
	
	for y in range(-load_radius, load_radius + 1):
		for x in range(-load_radius, load_radius + 1):
			var chunk_pos: Vector2i = player_chunk + Vector2i(x, y)
			chunks_to_keep.append(chunk_pos)
			
			if not chunks.has(chunk_pos):
				chunks_to_load.append(chunk_pos)
	
	for chunk_pos in chunks_to_load:
		_load_chunk(chunk_pos)
	
	var chunks_to_unload: Array[Vector2i] = []
	for chunk_pos in chunks.keys():
		if not chunks_to_keep.has(chunk_pos):
			chunks_to_unload.append(chunk_pos)
	
	for chunk_pos in chunks_to_unload:
		_unload_chunk(chunk_pos)


func _load_chunk(chunk_pos: Vector2i) -> void:
	if chunks.has(chunk_pos):
		return
	
	var chunk = MazeChunk.new(chunk_pos.x, chunk_pos.y)
	chunks[chunk_pos] = chunk
	
	generator.generate_chunk(chunk, world_seed)
	chunk_generating.emit(chunk)
	
	var touched_neighbors: Array[Vector2i] = []
	for neighbor_offset in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var neighbor_pos: Vector2i = chunk_pos + neighbor_offset
		if chunks.has(neighbor_pos):
			generator.connect_chunks(chunk, chunks[neighbor_pos], world_seed)
			touched_neighbors.append(neighbor_pos)
	
	_build_chunk_nodes(chunk_pos, chunk)
	
	# У соседей данные стен изменились (прорублен проход) —
	# их меши нужно перестроить, иначе проход останется глухой стеной
	for neighbor_pos in touched_neighbors:
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
	decor_builder.clear_decor(chunk_pos)
	chunk_unloaded.emit(chunk_pos)


func get_chunk_at_position(world_pos: Vector3):
	var chunk_pos: Vector2i = MazeChunk.world_to_chunk(world_pos)
	return chunks.get(chunk_pos)


func force_update() -> void:
	if player:
		last_player_chunk = MazeChunk.world_to_chunk(player.global_position)
		_update_chunks()
