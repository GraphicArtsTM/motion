extends RefCounted

# DecorHorror: следы того, что здесь кто-то был и не выбрался. На стенах —
# отпечатки ладоней (иногда цепочкой вниз, как будто сползал), счёт дней
# чёрточками, надписи, вентрешётки и розетки; на полу — следы волочения,
# лужи, бумаги, упавшие плитки потолка. Сколько всего — решает порча чанка
# (world_decay.gd): у старта почти чисто, в глубине страшно. Декали — квады
# одним мешем на материал, повторяющиеся предметы — общий меш из кэша
# PropFactory. Всё детерминировано сидом чанка. Зовёт decor_builder.gd.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")
const PropWorld = preload("res://scripts/prop_world.gd")
const PropFactory = preload("res://scripts/prop_factory.gd")
const WorldDecay = preload("res://scripts/world_decay.gd")

const CELL: float = MazeChunk.CELL_SIZE
const FACE: float = 0.205
const WRITINGS := ["ОНО СЛЫШИТ", "НЕ БЕГИ", "ВЫХОДА НЕТ", "ТИШЕ", "ОНО ЗА СТЕНОЙ",
	"НЕ ВЕРЬ ЗЕЛЁНОМУ СВЕТУ", "Я ЗДЕСЬ 41 ДЕНЬ", "НЕ ОГЛЯДЫВАЙСЯ", "СЧИТАЙ ЛАМПЫ", "МАМА"]


static func add(parent: Node3D, chunk, world_seed: int) -> void:
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	var rng := RandomNumberGenerator.new()
	rng.seed = ((world_seed ^ hash(pos)) + 7919) & 0x7FFFFFFF
	var decay: float = WorldDecay.at(pos, chunk.style)
	var walls: Array = _walls(chunk)
	var floors: Array = _floors(chunk)
	if walls.is_empty() or floors.is_empty():
		return
	var decals: Dictionary = {}
	# Ладони: одна, а в глубине — цепочка вниз по стене
	if rng.randf() < 0.15 + 0.55 * decay:
		var w: Array = walls[rng.randi_range(0, walls.size() - 1)]
		var trail: int = 1 + int(rng.randf() * 4.0 * decay)
		var along: float = rng.randf_range(0.6, 2.6)
		for i in trail:
			var h: float = 1.55 - i * 0.28 + rng.randf_range(-0.05, 0.05)
			_wall_decal(decals, "blood", w, along + i * rng.randf_range(0.12, 0.3), h, 0.2, 0.24,
				rng.randf_range(-0.35, 0.35))
	if rng.randf() < 0.12 + 0.3 * decay:
		var w: Array = walls[rng.randi_range(0, walls.size() - 1)]
		_wall_decal(decals, "scratch", w, rng.randf_range(0.8, 3.2), rng.randf_range(1.0, 1.5), 0.62, 0.23, 0.0)
	if rng.randf() < 0.15 + 0.35 * decay:
		_drag(decals, floors[rng.randi_range(0, floors.size() - 1)], chunk, rng)
	for i in rng.randi_range(0, 1 + int(4.0 * decay)):
		var f: Vector3 = _spot(floors, rng)
		var size: float = rng.randf_range(0.6, 1.6)
		_floor_decal(decals, "puddle", f, size, size * rng.randf_range(0.5, 0.9), rng.randf() * TAU)
	for i in rng.randi_range(1, 5):
		_floor_decal(decals, "paper", _spot(floors, rng), 0.21, 0.297, rng.randf() * TAU)
	parent.add_child(_build(decals))
	if rng.randf() < 0.1 + 0.35 * decay:
		_writing(parent, walls[rng.randi_range(0, walls.size() - 1)], rng)
	if rng.randf() < 0.1 + 0.4 * decay:
		var tile: MeshInstance3D = PropFactory.cached_mesh("fallen_tile", PropWorld.fallen_tile)
		tile.position = _spot(floors, rng) + Vector3(0, 0.02, 0)
		tile.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
		parent.add_child(tile)
	if rng.randf() < 0.6:
		_on_wall(parent, PropFactory.cached_mesh("vent", PropWorld.vent), walls[rng.randi_range(0, walls.size() - 1)],
			rng.randf_range(0.6, 3.4), 2.45)
	for i in rng.randi_range(0, 2):
		_on_wall(parent, PropFactory.cached_mesh("outlet", PropWorld.outlet), walls[rng.randi_range(0, walls.size() - 1)],
			rng.randf_range(0.4, 3.6), 0.3)


# Стены клеток: [угол, вдоль стены, внутрь клетки] — как в decor_builder
static func _walls(chunk) -> Array:
	var out: Array = []
	for y in MazeChunk.CHUNK_SIZE:
		for x in MazeChunk.CHUNK_SIZE:
			var cell = chunk.get_cell(x, y)
			if MazeCell.wall_count(cell) == 4:
				continue
			var p := Vector3(x * CELL, 0, y * CELL)
			for w in [[MazeCell.Wall.NORTH, p, Vector3.RIGHT, Vector3.BACK],
					[MazeCell.Wall.SOUTH, p + Vector3(0, 0, CELL), Vector3.RIGHT, Vector3.FORWARD],
					[MazeCell.Wall.EAST, p + Vector3(CELL, 0, 0), Vector3.BACK, Vector3.LEFT],
					[MazeCell.Wall.WEST, p, Vector3.BACK, Vector3.RIGHT]]:
				if cell.has_wall(w[0]):
					out.append([w[1], w[2], w[3]])
	return out


static func _floors(chunk) -> Array:
	var out: Array = []
	for y in MazeChunk.CHUNK_SIZE:
		for x in MazeChunk.CHUNK_SIZE:
			if MazeCell.wall_count(chunk.get_cell(x, y)) < 4:
				out.append(Vector2i(x, y))
	return out


static func _spot(floors: Array, rng: RandomNumberGenerator) -> Vector3:
	var c: Vector2i = floors[rng.randi_range(0, floors.size() - 1)]
	return Vector3((c.x + rng.randf_range(0.2, 0.8)) * CELL, 0.0, (c.y + rng.randf_range(0.2, 0.8)) * CELL)


static func _wall_decal(decals: Dictionary, mat: String, w: Array, along: float, h: float,
		width: float, height: float, tilt: float) -> void:
	var t: Vector3 = w[1]
	var n: Vector3 = w[2]
	var c: Vector3 = (w[0] as Vector3) + t * clampf(along, width, CELL - width) + n * FACE + Vector3(0, h, 0)
	var right: Vector3 = (t * cos(tilt) + Vector3.UP * sin(tilt)) * width * 0.5
	var up: Vector3 = (Vector3.UP * cos(tilt) - t * sin(tilt)) * height * 0.5
	_quad(decals, mat, c, right, up, n)


static func _floor_decal(decals: Dictionary, mat: String, c: Vector3, width: float, length: float,
		angle: float) -> void:
	var right := Vector3(cos(angle), 0, sin(angle)) * width * 0.5
	var fwd := Vector3(-sin(angle), 0, cos(angle)) * length * 0.5
	_quad(decals, mat, c + Vector3(0, 0.004, 0), right, fwd, Vector3.UP)


# След волочения: от центра клетки в открытую сторону, к стене бледнеет
static func _drag(decals: Dictionary, cell_pos: Vector2i, chunk, rng: RandomNumberGenerator) -> void:
	var cell = chunk.get_cell(cell_pos.x, cell_pos.y)
	var dirs: Array = []
	for d in [[MazeCell.Wall.NORTH, Vector3.FORWARD], [MazeCell.Wall.SOUTH, Vector3.BACK],
			[MazeCell.Wall.EAST, Vector3.RIGHT], [MazeCell.Wall.WEST, Vector3.LEFT]]:
		if not cell.has_wall(d[0]):
			dirs.append(d[1])
	if dirs.is_empty():
		return
	var dir: Vector3 = dirs[rng.randi_range(0, dirs.size() - 1)]
	var c := Vector3((cell_pos.x + 0.5) * CELL, 0.0, (cell_pos.y + 0.5) * CELL) + dir * 1.3
	_quad(decals, "drag", c + Vector3(0, 0.005, 0), dir.cross(Vector3.UP) * 0.28, -dir * 1.4, Vector3.UP)


static func _quad(decals: Dictionary, mat: String, c: Vector3, right: Vector3, up: Vector3, n: Vector3) -> void:
	if not decals.has(mat):
		decals[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]
	var a: Array = decals[mat]
	var start: int = (a[0] as PackedVector3Array).size()
	for corner in [[-1.0, 1.0, Vector2(0, 0)], [1.0, 1.0, Vector2(1, 0)], [1.0, -1.0, Vector2(1, 1)], [-1.0, -1.0, Vector2(0, 1)]]:
		a[0].append(c + right * corner[0] + up * corner[1])
		a[1].append(n)
		a[2].append(corner[2])
	# Обход — по нормали: у вывернутого квада с двусторонним материалом
	# Godot переворачивает нормаль, и декаль на полу выходит чёрной
	if right.cross(up).dot(n) < 0.0:
		a[3].append_array([start, start + 2, start + 1, start, start + 3, start + 2])
	else:
		a[3].append_array([start, start + 1, start + 2, start, start + 2, start + 3])


static func _build(decals: Dictionary) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for mat in decals:
		var data: Array = decals[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		for i in 4:
			arrays[[Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX][i]] = data[i]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, PropFactory.material_named(mat))
	var mi := MeshInstance3D.new()
	mi.name = "HorrorDecals"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# Надпись на стене бурым — неровно, крупно, на уровне глаз
static func _writing(parent: Node3D, w: Array, rng: RandomNumberGenerator) -> void:
	var label := Label3D.new()
	label.text = WRITINGS[rng.randi_range(0, WRITINGS.size() - 1)]
	label.font_size = 72
	label.pixel_size = 0.0032
	# Бурое, как засохшая кровь, и чуть просвечивает — краска впиталась в бумагу
	label.modulate = Color(0.34, 0.05, 0.035, 0.88)
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	var n: Vector3 = w[2]
	label.basis = Basis(Vector3.UP.cross(n), Vector3.UP, n).rotated(n, rng.randf_range(-0.08, 0.08))
	label.position = (w[0] as Vector3) + (w[1] as Vector3) * CELL * 0.5 + n * (FACE + 0.003) \
		+ Vector3(0, rng.randf_range(1.3, 1.8), 0)
	parent.add_child(label)


# Предмет на стене: его +Z смотрит из стены в клетку
static func _on_wall(parent: Node3D, item: MeshInstance3D, w: Array, along: float, h: float) -> void:
	var n: Vector3 = w[2]
	item.basis = Basis(Vector3.UP.cross(n), Vector3.UP, n)
	item.position = (w[0] as Vector3) + (w[1] as Vector3) * along + n * FACE + Vector3(0, h, 0)
	parent.add_child(item)
