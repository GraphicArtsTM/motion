extends RefCounted

# EntityGrab: когда хозяин хватает игрока. В упор и на прямой видимости —
# как раньше; а если он видел, как игрок залез в шкаф, — шкаф не спасает:
# сущность запоминает именно это укрытие, идёт к нему и вскрывает.
# Спрятался вне поля зрения — укрытие честное, о нём никто не знает.

const CATCH_DISTANCE: float = 1.35
# Сколько секунд после последнего взгляда прятаться уже поздно
const SEEN_GRACE: float = 0.35
# Дотянуться до шкафа: корпус 0.9 м, дверца смотрит в проход
const SPOT_REACH: float = 2.0
# Запомненный шкаф не держит сущность вечно, если путь к нему не нашёлся
const SPOT_MEMORY: float = 12.0

var entity: CharacterBody3D = null
var player = null
var senses = null
var seen_ago: float = INF
var spot: Node3D = null
var spot_timer: float = 0.0


func _init(entity_ref: CharacterBody3D, player_ref, senses_ref) -> void:
	entity = entity_ref
	player = player_ref
	senses = senses_ref


# Раз в кадр физики, до восприятия: время с последнего взгляда и
# «видел, как спрятался» — укрытие запоминается в первый кадр пряток
func tick(delta: float, chasing: bool) -> void:
	seen_ago += delta
	if not player.is_hidden():
		spot = null
		return
	if spot != null:
		spot_timer -= delta
		if spot_timer <= 0.0 or not is_instance_valid(spot):
			spot = null
		return
	if chasing and seen_ago <= SEEN_GRACE:
		spot = player.hidden_spot as Node3D
		spot_timer = SPOT_MEMORY


func saw_player() -> void:
	seen_ago = 0.0


func hunting_spot() -> bool:
	return spot != null and is_instance_valid(spot)


# Куда идти к запомненному шкафу: на точку перед дверцей, а не в корпус
func spot_target() -> Vector3:
	if spot.has_method("_exit_position"):
		return spot.call("_exit_position")
	return spot.global_position


func forget_spot() -> void:
	spot = null


# Текст экрана смерти или пустая строка, если хватать некого
func check() -> String:
	if player.is_hidden():
		if hunting_spot() and _flat_distance(spot.global_position) <= SPOT_REACH:
			return "Оно видело, как ты спрятался."
		return ""
	if _flat_distance(player.global_position) > CATCH_DISTANCE:
		return ""
	if not senses.line_clear(senses.eye_position(),
			player.global_position + Vector3(0, 1.1, 0)):
		return ""
	if player.is_sprinting:
		return "Оно нашло тебя. Не надо было бежать."
	return "Оно нашло тебя."


func _flat_distance(pos: Vector3) -> float:
	return Vector2(pos.x - entity.global_position.x,
		pos.z - entity.global_position.z).length()
