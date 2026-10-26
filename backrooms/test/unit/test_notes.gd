extends GutTest

# Записки разведчика: лежат редко и всегда в тех же чанках, прочитанная
# не возвращается, дневник читается по порядку, счётчик на планшете.

const ChunkManager = preload("res://scripts/chunk_manager.gd")
const NoteSpawner = preload("res://scripts/note_spawner.gd")
const NoteTexts = preload("res://scripts/note_texts.gd")
const NoteView = preload("res://scripts/note_view.gd")

var root_node: Node3D = null
var manager = null


func _make_world() -> void:
	root_node = Node3D.new()
	var player := Node3D.new()
	player.name = "Player"
	root_node.add_child(player)
	player.position = Vector3(2, 0, 2)
	manager = ChunkManager.new()
	manager.load_radius = 2
	manager.player_path = NodePath("../Player")
	manager.set_process(false)
	root_node.add_child(manager)
	add_child_autofree(root_node)


func test_texts_complete() -> void:
	assert_eq(NoteTexts.count(), 10)
	for i in NoteTexts.count():
		assert_false(NoteTexts.title(i).is_empty())
		assert_gt(NoteTexts.body(i).length(), 40)
	assert_eq(NoteView.counter_text(3, 10), "ЗАПИСКИ 3/10")


func test_notes_sparse_and_deterministic() -> void:
	assert_false(NoteSpawner.has_note(NoteSpawner.START_CHUNK, 12345))
	var hits: int = 0
	var total: int = 0
	for y in range(-20, 20):
		for x in range(-20, 20):
			var pos := Vector2i(x, y)
			var has: bool = NoteSpawner.has_note(pos, 12345)
			assert_eq(NoteSpawner.has_note(pos, 12345), has)
			hits += int(has)
			total += 1
	var share: float = float(hits) / total
	assert_between(share, NoteSpawner.CHANCE * 0.6, NoteSpawner.CHANCE * 1.4)


func test_read_note_never_returns() -> void:
	_make_world()
	var spawner = manager.note_spawner
	var expected: Array = []
	for pos in manager.chunks:
		if NoteSpawner.has_note(pos, manager.world_seed):
			expected.append(pos)
	assert_eq(spawner.placed.size(), expected.size())
	if expected.is_empty():
		pass_test("в стартовой области записок нет")
		return
	var pos: Vector2i = expected[0]
	var first_spot: Vector3 = (spawner.placed[pos] as Node3D).global_position
	# Выгрузили и вернулись — записка там же
	spawner.remove_notes(pos)
	spawner.add_notes(manager.chunks[pos], manager.world_seed)
	assert_eq((spawner.placed[pos] as Node3D).global_position, first_spot)
	spawner._on_read(pos)
	assert_eq(spawner.read_count, 1)
	assert_false(spawner.placed.has(pos))
	spawner.add_notes(manager.chunks[pos], manager.world_seed)
	assert_false(spawner.placed.has(pos), "прочитанная записка вернулась")


func test_diary_ends_and_clears_leftovers() -> void:
	_make_world()
	var spawner = manager.note_spawner
	spawner.read_count = NoteTexts.count() - 1
	var any: Vector2i = Vector2i(99, 99)
	spawner._on_read(any)
	assert_eq(spawner.read_count, NoteTexts.count())
	assert_eq(spawner.placed.size(), 0)
	for pos in manager.chunks:
		spawner.add_notes(manager.chunks[pos], manager.world_seed)
	assert_eq(spawner.placed.size(), 0, "после последней страницы новых записок нет")
