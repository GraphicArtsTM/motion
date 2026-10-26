extends Node3D

# NoteSpawner: записки пропавшего разведчика (note_texts.gd). Лежат не в
# каждом чанке — примерно в каждом восьмом, клетка и поворот листа от сида
# чанка, поэтому при возвращении записка там же. Прочитанная не
# возвращается, а страница берётся по счёту прочитанных: дневник всегда
# идёт по порядку, где бы игрок ни шёл. Стартовый чанк чист — первая
# записка уже по дороге. Зовёт chunk_manager.gd, как fuse_spawner.gd.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const NotePickup = preload("res://scripts/note_pickup.gd")
const NoteTexts = preload("res://scripts/note_texts.gd")

const CELL: float = MazeChunk.CELL_SIZE
const CHANCE: float = 0.13
const START_CHUNK := Vector2i(0, 0)

var hud_ref = null
var placed: Dictionary = {}
var collected: Dictionary = {}
var read_count: int = 0


func _ready() -> void:
	hud_ref = get_tree().get_first_node_in_group("hud")


# Есть ли в чанке записка — только от сида и координат
static func has_note(pos: Vector2i, world_seed: int) -> bool:
	return pos != START_CHUNK and _rng(pos, world_seed).randf() < CHANCE


func add_notes(chunk, world_seed: int) -> void:
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	if placed.has(pos) or collected.has(pos) or read_count >= NoteTexts.count():
		return
	if not has_note(pos, world_seed):
		return
	var rng: RandomNumberGenerator = _rng(pos, world_seed)
	rng.randf() # жребий has_note
	var open: Array = []
	for y in MazeChunk.CHUNK_SIZE:
		for x in MazeChunk.CHUNK_SIZE:
			if MazeCell.wall_count(chunk.get_cell(x, y)) < 4:
				open.append(Vector2i(x, y))
	if open.is_empty():
		return
	var cell: Vector2i = open[rng.randi_range(0, open.size() - 1)]
	var note := NotePickup.new()
	note.hud = hud_ref
	note.position = chunk.get_world_position() + Vector3((cell.x + rng.randf_range(0.3, 0.7)) * CELL,
		0.0, (cell.y + rng.randf_range(0.3, 0.7)) * CELL)
	note.rotation.y = rng.randf() * TAU
	note.read.connect(_on_read.bind(pos))
	add_child(note)
	placed[pos] = note


func remove_notes(chunk_pos: Vector2i) -> void:
	if placed.has(chunk_pos):
		(placed[chunk_pos] as Node3D).queue_free()
		placed.erase(chunk_pos)


func _on_read(pos: Vector2i) -> void:
	collected[pos] = true
	placed.erase(pos)
	var index: int = read_count
	read_count += 1
	# Дневник кончился — лишние листки убираем, чтобы не читать последний дважды
	if read_count >= NoteTexts.count():
		for left in placed.values():
			(left as Node3D).queue_free()
		placed.clear()
	var view: Node = get_tree().get_first_node_in_group("note_view")
	if view:
		view.show_note(index, read_count, NoteTexts.count())


static func _rng(pos: Vector2i, world_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ((world_seed ^ hash(pos)) + 104729) & 0x7FFFFFFF
	return rng
