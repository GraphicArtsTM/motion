extends RefCounted

# EntityMotion: как хозяин лабиринта переставляет ноги. Идёт по клеткам
# пути, а в погоне, когда игрок на виду, срезает напрямую. Скорость — от
# состояния, в воде затопленного сектора (flood.gd) медленнее, как и игрок.
# Решения — в entity.gd, здесь только шаг.

const Navigator = preload("res://scripts/entity_navigator.gd")
const Flood = preload("res://scripts/flood.gd")

const WANDER_SPEED: float = 1.35
const INVESTIGATE_SPEED: float = 2.3
const CHASE_SPEED: float = 4.4
# Ищет потерянного быстрее, чем бродит, — но не бегом
const SEARCH_SPEED: float = 1.9
const TURN_SPEED: float = 7.0
const WAYPOINT_EPS: float = 0.55
const GRAVITY: float = 14.0
const STATE_INVESTIGATE: int = 1 # Entity.State
const STATE_CHASE: int = 2
const STATE_SEARCH: int = 3


static func speed(state: int, at: Vector3) -> float:
	var base: float = WANDER_SPEED
	if state == STATE_CHASE:
		base = CHASE_SPEED
	elif state == STATE_INVESTIGATE:
		base = INVESTIGATE_SPEED
	elif state == STATE_SEARCH:
		base = SEARCH_SPEED
	return base * Flood.speed_at(at)


# Шаг кадра: снять пройденные точки пути, повернуться и пройти
static func walk(host, delta: float) -> void:
	var desired := Vector3.ZERO
	while host.path.size() > 0:
		var wp: Vector3 = Navigator.cell_to_world(host.path[0])
		var to_wp: Vector3 = wp - host.global_position
		to_wp.y = 0.0
		if to_wp.length() < WAYPOINT_EPS:
			host.prev_cell = host.path[0]
			host.path.pop_front()
			continue
		desired = to_wp.normalized()
		break
	var state: int = int(host.state)
	var target: Vector3 = host.last_seen
	if desired == Vector3.ZERO and (state == STATE_CHASE or state == STATE_INVESTIGATE) \
			and target.distance_to(host.global_position) > WAYPOINT_EPS \
			and host.senses.line_clear(host.senses.eye_position(), target + Vector3(0, 1.1, 0)):
		desired = Vector3(target.x - host.global_position.x, 0.0,
			target.z - host.global_position.z).normalized()
	var v: float = speed(state, host.global_position)
	host.velocity.x = desired.x * v
	host.velocity.z = desired.z * v
	if host.is_on_floor():
		host.velocity.y = 0.0
	else:
		host.velocity.y -= GRAVITY * delta
	host.move_and_slide()
	if desired != Vector3.ZERO:
		face(host, desired, delta)


static func face(host, dir: Vector3, delta: float) -> void:
	var yaw: float = atan2(-dir.x, -dir.z)
	host.rotation.y = lerp_angle(host.rotation.y, yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
