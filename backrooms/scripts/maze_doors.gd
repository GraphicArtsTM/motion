extends RefCounted

# MazeDoors: дверные проёмы. Снятая между клетками стена — это дыра во
# всю ширину клетки (4 м), и лабиринт читался как поле перегородок. Проём
# оставляет от стены косяки и перемычку сверху (геометрия — room_trim.gd):
# коридор становится коридором, комната — комнатой. Только флаги в данных,
# проходимость не меняется — сущность ходит теми же клетками.
# Внутри залов проёмов нет (зал остаётся залом), на прямых пролётах сетки
# тоже — там вся соль в сквозном виде. Флаг ставится обеим клеткам.

const MazeCell = preload("res://scripts/maze_cell.gd")
const MazeChunk = preload("res://scripts/maze_chunk.gd")

const CHUNK_SIZE: int = MazeChunk.CHUNK_SIZE
# Шанс проёма на границе чанков: решается сидом границы (maze_generator)
const BORDER_CHANCE: float = 0.45


static func mark(a, b, direction) -> void:
	if a == null or b == null:
		return
	a.doors |= direction
	b.doors |= a.get_opposite_wall(direction)


# Внутри чанка: каждая открытая пара «коридорных» клеток (у обеих по две
# стены и больше) с шансом chance. Решается сразу после вырезания, пока
# наружные стены ещё не прорублены, — от порядка загрузки не зависит
static func place(chunk, rng: RandomNumberGenerator, chance: float, halls: Array,
		blocked: Dictionary) -> void:
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var cell = chunk.get_cell(x, y)
			for step in [[MazeCell.Wall.EAST, Vector2i(1, 0)], [MazeCell.Wall.SOUTH, Vector2i(0, 1)]]:
				var other = chunk.get_cell(x + step[1].x, y + step[1].y)
				# Жребий тянем всегда: иначе последовательность rng зависела бы от стен
				var roll: float = rng.randf()
				if other == null or cell.has_wall(step[0]) or roll >= chance:
					continue
				if MazeCell.wall_count(cell) < 2 or MazeCell.wall_count(other) < 2:
					continue
				var here := Vector2i(x, y)
				var there: Vector2i = here + step[1]
				if blocked.has(here) and blocked.has(there):
					continue
				if _same_hall(halls, here, there):
					continue
				mark(cell, other, step[0])


static func _same_hall(halls: Array, a: Vector2i, b: Vector2i) -> bool:
	for hall in halls:
		if (hall as Rect2i).has_point(a) and (hall as Rect2i).has_point(b):
			return true
	return false
