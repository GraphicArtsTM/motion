extends RefCounted

# Darkness: где в бесконечном лабиринте лампы мертвы. Поле низкочастотное —
# тьма приходит участками по 2–4 чанка, а не одиночными пятнами, и одинаково
# отвечает всем, кто спросит: лампам, фонарю, подсказке HUD.
# Один чанк — 8×8 клеток по 4 м, то есть 32×32 метра.

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const THRESHOLD: float = 0.62


static func is_dark_chunk(pos: Vector2i) -> bool:
	# Стартовую площадку не трогаем: игра не должна начинаться в темноте
	if absi(pos.x) <= 1 and absi(pos.y) <= 1:
		return false
	# Две волны разной длины: крупные тёмные районы с рваным краем
	var n: float = sin(pos.x * 0.52 + 1.3) * cos(pos.y * 0.47 - 0.7)
	n += 0.6 * sin(pos.x * 0.21 - 2.1) * cos(pos.y * 0.24 + 1.9)
	return n > THRESHOLD


static func is_dark_at(world_pos: Vector3) -> bool:
	return is_dark_chunk(MazeChunk.world_to_chunk(world_pos))
