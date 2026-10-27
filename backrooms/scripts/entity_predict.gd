extends RefCounted

# EntityPredict: упреждение. Игрок скрылся за углом — хозяин лабиринта
# бежит не на последнюю точку, где его видел, а туда, куда тот уходил.
# Чистая функция по сетке лабиринта (entity_navigator.gd).

const Navigator = preload("res://scripts/entity_navigator.gd")


# Куда ушёл игрок: от точки по направлению его хода, по коридору — на
# изгибе за поворотом, а на развилке, где не угадать, остановка. Не больше
# cells клеток; стена прямо по ходу — остаётся на месте
static func project(chunk_manager, from_pos: Vector3, dir: Vector3, cells: int) -> Vector3:
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 0.01:
		return from_pos
	flat = flat.normalized()
	var start: Vector2i = Navigator.world_to_cell(from_pos)
	var cur: Vector2i = start
	var prev := Vector2i.MAX
	for _i in cells:
		var options: Array = []
		var pick = null
		for d: Vector2i in Navigator.DIRECTIONS:
			# Назад, откуда он шёл, не смотрим
			if cur + d == prev or Vector2(d).dot(flat) < -0.5 \
					or not Navigator._open_between(chunk_manager, cur, cur + d):
				continue
			options.append(d)
			if Vector2(d).dot(flat) > 0.7:
				pick = d
		if pick == null and options.size() == 1:
			pick = options[0]
		if pick == null:
			break
		flat = Vector2(pick)
		prev = cur
		cur += pick
	return from_pos if cur == start else Navigator.cell_to_world(cur)
