extends RefCounted

# MazeZone: характер местности. Чанки сбиты в районы 2×2 (64×64 м): внутри
# района лабиринт одного типа, за границей — другой. Так у бесконечного
# мира появляются «места», и по виду коридора понятно, куда тебя занесло.
# Всё — чистая функция координат района и мирового сида.

const ZONE_SHIFT: int = 1 # 2×2 чанка на район

enum Style { HALLS, GRID, MAZE, OPEN }

# Доли районов по порядку Style. Сумма должна давать 1.0
const WEIGHTS: Array = [0.30, 0.28, 0.27, 0.15]

# Параметры вырезания: loop — доля снятых внутренних стен, halls — залы
# (ширина, высота), dead — доля открытых тупиков, pillar — шанс колонны
const PRESETS: Array = [
	# ЗАЛЫ: помещения 2×2 и 3×3 с колоннами, видно далеко, укрытий мало
	{"loop": 0.20, "halls": [Vector2i(3, 3), Vector2i(3, 2), Vector2i(2, 2)],
		"dead": 0.70, "pillar": 0.50},
	# СЕТКА: длинные прямые пролёты через чанк, между ними кварталы
	{"loop": 0.14, "halls": [Vector2i(2, 2)], "dead": 0.45, "pillar": 0.25,
		"grid": true},
	# ЧАЩА: плотный лабиринт, тупики остаются — здесь и теряются
	{"loop": 0.04, "halls": [], "dead": 0.15, "pillar": 0.0},
	# ПУСТОШЬ: почти всё снесено, редкая аномалия на несколько районов
	{"loop": 0.55, "halls": [Vector2i(4, 4), Vector2i(3, 3)], "dead": 0.85,
		"pillar": 0.60},
]


static func style_at(chunk_x: int, chunk_y: int, base_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = zone_seed(chunk_x, chunk_y, base_seed)
	var roll: float = rng.randf()
	var acc: float = 0.0
	for i in WEIGHTS.size():
		acc += float(WEIGHTS[i])
		if roll < acc:
			return i
	return WEIGHTS.size() - 1


# Сид района — общий для всех его чанков: по нему выбирается характер
# района, поэтому все его чанки одного типа
static func zone_seed(chunk_x: int, chunk_y: int, base_seed: int) -> int:
	var zone := Vector2i(chunk_x >> ZONE_SHIFT, chunk_y >> ZONE_SHIFT)
	return (base_seed ^ hash(zone)) & 0x7FFFFFFF


static func params(style: int) -> Dictionary:
	return PRESETS[clampi(style, 0, PRESETS.size() - 1)]
