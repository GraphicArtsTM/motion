extends RefCounted

# EntitySenses: зрение и слух сущности. Отдельно от мозга —
# здесь только «вижу / слышу», никаких решений и движения.

const SIGHT_RANGE: float = 24.0
const SIGHT_HALF_ANGLE: float = 1.15  # половина угла обзора, ~66°
# Доля радиуса шума, которую пробивает стена
const WALL_MUFFLE: float = 0.55

const Flood = preload("res://scripts/flood.gd")

var entity: CharacterBody3D = null
var player = null
var _bus_ref: Node = null


func _init(entity_ref, player_ref) -> void:
	entity = entity_ref
	player = player_ref


# Конус обзора + прямая видимость. Запертый в шкафу игрок
# не виден: луч упирается в стенку шкафа.
func sees_player() -> bool:
	if player == null or player.is_hidden():
		return false
	var eye := eye_position()
	var target: Vector3 = player.global_position + Vector3(0, 1.2, 0)
	var to_target := target - eye
	var dist := to_target.length()
	if dist > SIGHT_RANGE:
		return false
	if dist > 0.05:
		var forward: Vector3 = -entity.global_transform.basis.z
		if forward.dot(to_target / dist) < cos(SIGHT_HALF_ANGLE):
			return false
	return line_clear(eye, target)


# Восприятие за кадр: что мозг понял. Порядок — «вижу игрока»,
# «слышу приманку» (звон громче шагов), «слышу шаги».
# Пусто — ничего; иначе {"seen": bool, "bait": bool, "pos": Vector3}.
func perceive() -> Dictionary:
	if sees_player():
		return {"seen": true, "bait": false, "pos": player.global_position}
	var event: Variant = _heard_event()
	if event != null:
		# Тревога не приманка: увести её нельзя, зато и погоню она не сбивает
		return {"seen": false, "bait": not bool(event.get("alarm", false)),
			"pos": event["pos"]}
	if hears_player():
		return {"seen": false, "bait": false, "pos": player.global_position}
	return {}


# Шум игрока: радиус задаёт сам игрок (присед 3 м, шаг 8 м, бег 20 м,
# в укрытии 0 — тогда не слышно вовсе), в воде (flood.gd) — дальше.
func hears_player() -> bool:
	if player == null:
		return false
	var radius: float = player.get_noise_radius() * Flood.noise_at(player.global_position)
	if radius <= 0.0:
		return false
	var dist: float = entity.global_position.distance_to(player.global_position)
	if dist > radius:
		return false
	# Стены глушат: за стеной шаги слышны только вблизи. Луч — лишь в
	# дальней части радиуса, ближе слышно в любом случае
	return dist <= radius * WALL_MUFFLE or line_clear(eye_position(), player.global_position + Vector3(0, 1.0, 0))


# Разовое событие шины шумов (звон банки, грохот двери) — целиком, или null
func _heard_event() -> Variant:
	var bus: Node = _noise_bus()
	if bus == null:
		return null
	return bus.poll(entity.global_position)


func _noise_bus() -> Node:
	if _bus_ref != null and is_instance_valid(_bus_ref):
		return _bus_ref
	_bus_ref = entity.get_tree().get_first_node_in_group("noise_bus")
	return _bus_ref


func eye_position() -> Vector3:
	return entity.global_position + Vector3(0, 2.15, 0)


# Луч не задевает ни мир, ни собственную капсулу, ни игрока.
func line_clear(from: Vector3, to: Vector3) -> bool:
	var exclude: Array[RID] = [entity.get_rid()]
	if player is CollisionObject3D:
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
	return entity.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
