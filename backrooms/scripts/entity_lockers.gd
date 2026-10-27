extends RefCounted

# EntityLockers: потеряв игрока, хозяин лабиринта обходит шкафы рядом с
# местом, где его потерял: встаёт у дверцы и слушает. Шкаф по-прежнему
# спасает — но только если отдышался. Залез в шкаф запыхавшись (выносливость
# ниже BREATH_LIMIT) — он услышит. В шкафу дыхание выравнивается
# (player_controller.gd), поэтому прятаться надо загодя, а не в последний миг.
# Зовёт entity.gd в состоянии SEARCH.

# Шкафы в этом радиусе от точки, где потерял, — проверяет
const RADIUS: float = 14.0
const LISTEN_TIME: float = 1.8
# Дотянуться до шкафа, как у entity_grab.gd: путь ведёт в клетку шкафа
const REACH: float = 2.0
const BREATH_LIMIT: float = 0.5
const CAUGHT_TEXT: String = "Оно услышало, как ты дышишь."
const HINT_TEXT: String = "Оно стоит у дверцы и слушает…"

var entity: CharacterBody3D = null
var player = null
var checked: Dictionary = {}
var target: Node3D = null
var listen: float = 0.0
var heard: bool = false
# Пусто — никого не нашёл; иначе текст экрана смерти
var verdict: String = ""


func _init(entity_ref: CharacterBody3D, player_ref) -> void:
	entity = entity_ref
	player = player_ref


# Новый поиск — новый обход
func reset() -> void:
	checked.clear()
	target = null
	listen = 0.0
	heard = false


func busy() -> bool:
	return target != null and is_instance_valid(target)


# Ближайший непроверенный шкаф у точки потери, или null
func pick(spots: Array, center: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist: float = RADIUS
	for spot: Node3D in spots:
		if not is_instance_valid(spot) or checked.has(spot.get_instance_id()):
			continue
		var d: float = _flat(spot.global_position, center)
		if d < best_dist:
			best_dist = d
			best = spot
	target = best
	listen = 0.0
	heard = false
	return best


func front(spot: Node3D) -> Vector3:
	return spot.call("_exit_position") if spot.has_method("_exit_position") else spot.global_position


# Кадр у шкафа. true — ещё занят (стоит или идёт к дверце)
func tick(delta: float, hud) -> bool:
	if not busy():
		target = null
		return false
	if _flat(target.global_position, entity.global_position) > REACH:
		return true
	if listen == 0.0 and bool(target.get("occupied")) and hud and hud.has_method("show_hint"):
		hud.show_hint(HINT_TEXT, LISTEN_TIME)
	listen += delta
	# Хватит и мига одышки, пока он у дверцы
	if bool(target.get("occupied")) and player.is_hidden() and heavy_breath():
		heard = true
	if listen < LISTEN_TIME:
		return true
	if heard:
		verdict = CAUGHT_TEXT
	checked[target.get_instance_id()] = true
	target = null
	return false


func heavy_breath() -> bool:
	return float(player.get_stamina_percent()) < BREATH_LIMIT


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
