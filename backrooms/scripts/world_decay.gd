extends RefCounted

# WorldDecay: насколько запущено место, 0..1. Чем дальше от старта, тем
# хуже: у старта обои просто выцвели, на полпути к выходу по стенам ползут
# подтёки и плесень, ковёр промок, лампы мрут и мигают, плитки потолка
# выпадают. Кабинеты и чаща запущены сильнее, пустошь — чище (там жутко от
# пустоты, а не от грязи). Одна функция для стен, ламп и декора — они
# согласны друг с другом в каждом чанке.

const MazeZone = preload("res://scripts/maze_zone.gd")

# Полная порча — в 11.5 чанка (~370 м) от старта: третий предохранитель и
# дверь выхода лежат уже за ней
const START_CHUNKS: float = 1.5
const FULL_CHUNKS: float = 10.0
const STYLE_BONUS: Array = [0.0, 0.0, 0.1, -0.1, 0.15]


static func at(chunk_pos: Vector2i, style: int) -> float:
	var depth: float = clampf((Vector2(chunk_pos).length() - START_CHUNKS) / FULL_CHUNKS, 0.0, 1.0)
	var bonus: float = STYLE_BONUS[clampi(style, 0, STYLE_BONUS.size() - 1)]
	return clampf(depth + bonus * depth, 0.0, 1.0)
