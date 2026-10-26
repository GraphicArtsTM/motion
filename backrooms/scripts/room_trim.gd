extends RefCounted

# RoomTrim: отделка стен чанка — плинтус вдоль каждой стены и дверные
# проёмы (косяки, перемычка, наличник) там, где maze_doors.gd поставил флаг.
# Проём рисует клетка-хозяин ребра (восточное и южное), поэтому на границе
# чанков проём строится один раз. Геометрия — прямые квады в массивы:
# сборка через mesh_kit на каждый чанк стоила бы десятки миллисекунд.
# Ширина проёма — хеш координат ребра: от порядка загрузки не зависит.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const MazeCell = preload("res://scripts/maze_cell.gd")

const CELL: float = MazeChunk.CELL_SIZE
const WALL_THICK: float = 0.2
const Y0: float = -0.05
const Y1: float = 2.79
const BASE_H: float = 0.11
const BASE_OUT: float = 0.016
const LINTEL_Y: float = 2.15
const CASING: float = 0.07


# {"trim": стеновые детали проёмов, "base": плинтус и наличники} —
# в каждом массивы вершин, нормалей, UV и индексов
static func build(chunk) -> Dictionary:
	var trim: Array = _new_arrays()
	var base: Array = _new_arrays()
	for y in MazeChunk.CHUNK_SIZE:
		for x in MazeChunk.CHUNK_SIZE:
			var cell = chunk.get_cell(x, y)
			var pos := Vector3(x * CELL, 0, y * CELL)
			_baseboards(base, cell, pos)
			for step in [[MazeCell.Wall.EAST, Vector3(CELL, 0, 0), Vector3.BACK],
					[MazeCell.Wall.SOUTH, Vector3(0, 0, CELL), Vector3.RIGHT]]:
				if not cell.has_wall(step[0]) and (cell.doors & step[0]) != 0:
					var g: Vector2i = chunk.get_global_cell_pos(x, y)
					_doorway(trim, base, pos + step[1], step[2], _width(g, step[0]))
	return {"trim": trim, "base": base}


static func _width(g: Vector2i, dir: int) -> float:
	var h: float = fposmod(sin(g.x * 12.9898 + g.y * 78.233 + dir * 3.71) * 43758.5453, 1.0)
	return 1.9 + 0.5 * h


# Плинтус: на внутренней грани каждой стены клетки — лицо и верхняя кромка
static func _baseboards(arrays: Array, cell, pos: Vector3) -> void:
	for wall in [[MazeCell.Wall.NORTH, pos, Vector3.RIGHT, Vector3.BACK],
			[MazeCell.Wall.SOUTH, pos + Vector3(0, 0, CELL), Vector3.RIGHT, Vector3.FORWARD],
			[MazeCell.Wall.EAST, pos + Vector3(CELL, 0, 0), Vector3.BACK, Vector3.LEFT],
			[MazeCell.Wall.WEST, pos, Vector3.BACK, Vector3.RIGHT]]:
		if not cell.has_wall(wall[0]):
			continue
		var face: Vector3 = wall[1] + wall[3] * WALL_THICK
		var out: Vector3 = wall[3] * BASE_OUT
		var along: Vector3 = wall[2] * CELL
		var top: Vector3 = Vector3.UP * BASE_H
		_quad(arrays, face + out, face + out + along, face + out + along + top, face + out + top, wall[3])
		_quad(arrays, face + top, face + along + top, face + along + out + top, face + out + top, Vector3.UP)


# Проём на ребре: start — угол ребра, along — направление ребра, косяки
# толщиной в две стены у концов, перемычка над проёмом, наличник с обеих сторон
static func _doorway(trim: Array, base: Array, start: Vector3, along: Vector3, width: float) -> void:
	var across: Vector3 = along.cross(Vector3.UP).normalized()
	var stub: float = (CELL - width) * 0.5
	var mid_h: float = (Y1 - Y0) * 0.5
	for side in [0.0, CELL - stub]:
		var c: Vector3 = start + along * (side + stub * 0.5) + Vector3(0, Y0 + mid_h, 0)
		_box(trim, c, along * stub * 0.5, Vector3(0, mid_h, 0), across * WALL_THICK, false)
	var lc: Vector3 = start + along * CELL * 0.5 + Vector3(0, (LINTEL_Y + Y1) * 0.5, 0)
	_box(trim, lc, along * width * 0.5, Vector3(0, (Y1 - LINTEL_Y) * 0.5, 0), across * WALL_THICK * 0.9, true)
	# Наличник: две стойки и верх, на палец выступают из стены с обеих сторон
	var depth: Vector3 = across * (WALL_THICK + 0.02)
	for s in [-1.0, 1.0]:
		var post: Vector3 = start + along * (CELL * 0.5 + s * (width * 0.5 + CASING * 0.5))
		_box(base, post + Vector3(0, LINTEL_Y * 0.5, 0), along * CASING * 0.5,
			Vector3(0, LINTEL_Y * 0.5, 0), depth, false)
	_box(base, start + along * CELL * 0.5 + Vector3(0, LINTEL_Y + CASING * 0.5, 0),
		along * (width * 0.5 + CASING), Vector3(0, CASING * 0.5, 0), depth, true)


# Короб по центру и трём полуосям; низ рисуем только у висящих деталей
static func _box(arrays: Array, c: Vector3, a: Vector3, b: Vector3, d: Vector3, bottom: bool) -> void:
	for axis in [[a, b, d], [d, b, a], [a, d, b]]:
		for s in [-1.0, 1.0]:
			if axis[2] == b and s < 0.0 and not bottom:
				continue
			var n: Vector3 = (axis[2] as Vector3) * s
			var f: Vector3 = c + n
			var u: Vector3 = axis[0]
			var v: Vector3 = axis[1]
			_quad(arrays, f - u - v, f + u - v, f + u + v, f - u + v, n.normalized())


static func _new_arrays() -> Array:
	return [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]


# Квад по четырём точкам; обход разворачивается по нормали (лицевая грань
# в Godot — по часовой стрелке), UV — мировые метры на плоскости грани
static func _quad(arrays: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var start: int = (arrays[0] as PackedVector3Array).size()
	var flip: bool = (b - a).cross(c - a).dot(normal) > 0.0
	for v: Vector3 in [a, b, c, d]:
		arrays[0].append(v)
		arrays[1].append(normal)
		arrays[2].append(Vector2(v.x + v.z, v.y))
	if flip:
		arrays[3].append_array([start, start + 2, start + 1, start, start + 3, start + 2])
	else:
		arrays[3].append_array([start, start + 1, start + 2, start, start + 2, start + 3])
