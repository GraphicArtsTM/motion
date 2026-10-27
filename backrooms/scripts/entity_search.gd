extends RefCounted

# EntitySearch: что хозяин лабиринта делает, потеряв игрока. Сначала
# обходит шкафы у места потери (entity_lockers.gd) — встаёт у дверцы лицом
# и слушает, — потом кружит по ближним клеткам, пока не выйдет время, и
# возвращается бродить. Состояние живёт в entity.gd, здесь только шаг.

const Navigator = preload("res://scripts/entity_navigator.gd")
const EntityMotion = preload("res://scripts/entity_motion.gd")

const STATE_WANDER: int = 0 # Entity.State
const STATE_SEARCH: int = 3
const SEARCH_TIME: float = 6.0
# Обход шкафов растягивает поиск: на каждый — дорога и прослушка
const LOCKER_SEARCH_TIME: float = 14.0


static func begin(host, seconds: float = SEARCH_TIME) -> void:
	host.state = STATE_SEARCH
	host.search_timer = seconds
	host.grab.forget_spot()
	host.lockers.reset()
	# Пустой путь: первым шагом поиска step() выберет шкаф, а нет шкафов —
	# круг по ближним клеткам
	host.path = []


static func step(host, delta: float) -> void:
	var lockers = host.lockers
	host.search_timer -= delta
	if host.search_timer <= 0.0:
		host.state = STATE_WANDER
		host.idle_timer = 0.0
		host.path = []
		lockers.reset()
	elif lockers.tick(delta, host.hud):
		if lockers.listen > 0.0:
			host.path = []
			EntityMotion.face(host, lockers.target.global_position - host.global_position, delta)
		elif host.path.is_empty():
			host.path = Navigator.path_to(host.chunk_manager, host.global_position,
				lockers.front(lockers.target), host.prev_cell)
	elif host.path.is_empty():
		var spot: Node3D = lockers.pick(nearby_spots(host.chunk_manager), host.last_seen)
		if spot:
			host.search_timer = maxf(host.search_timer, LOCKER_SEARCH_TIME)
			host.path = Navigator.path_to(host.chunk_manager, host.global_position,
				lockers.front(spot), host.prev_cell)
		else:
			host.path = Navigator.path_in_band(host.chunk_manager, host.global_position,
				host.last_seen, 4.0, 13.0, host.rng)


# Все шкафы загруженных чанков (hiding_spots.gd)
static func nearby_spots(chunk_manager) -> Array:
	var out: Array = []
	if chunk_manager and chunk_manager.get("hiding_spots"):
		for list in chunk_manager.hiding_spots.spots.values():
			out.append_array(list)
	return out
