extends Node

# EntityDirector: режиссёр напряжения, как «чутьё» чужого в хоррорах.
# Хозяин лабиринта не знает, где игрок, но страх должен идти волнами:
# - затишье: если долго (CALM_LIMIT) ни погони, ни сущности рядом, она
#   «чует» игрока — бродячая идёт проверить точку в 10–22 м от него, не
#   точно на него. Сидишь в шкафу — не чует;
# - передышка: после жёсткой погони (напряжение выше HOT) она уходит прочь
#   на RELIEF_TIME и в это время не «чует».
# Сам ничего не видит и не слышит — только подсказывает entity.gd
# (hear_rumor, retreat). Живёт ребёнком Entity (world.tscn).

const Navigator = preload("res://scripts/entity_navigator.gd")

const STATE_WANDER: int = 0 # Entity.State
const STATE_CHASE: int = 2
const CALM_LIMIT: float = 75.0
const CALM_NEAR: float = 25.0
const RUMOR_MIN: float = 10.0
const RUMOR_MAX: float = 22.0
const RELIEF_TIME: float = 30.0
const HOT: float = 0.6
# Напряжение копится погоней и близостью, тает само
const HEAT_RATE: float = 0.25
const COOL_RATE: float = 0.03

var host = null
var player = null
var rng := RandomNumberGenerator.new()
var tension: float = 0.0
var calm: float = 0.0
var relief: float = 0.0
var last_state: int = STATE_WANDER


func _ready() -> void:
	rng.randomize()
	host = get_parent()
	player = host.get_node_or_null(host.player_path)


func _physics_process(delta: float) -> void:
	if host == null or player == null or not host.placed or not host.is_physics_processing():
		return
	tick(delta)


func tick(delta: float) -> void:
	var state: int = int(host.state)
	var dist: float = host.global_position.distance_to(player.global_position)
	var heat: float = 1.0 if state == STATE_CHASE else clampf(1.0 - dist / CALM_NEAR, 0.0, 1.0)
	tension = clampf(tension + (heat * HEAT_RATE - COOL_RATE) * delta, 0.0, 1.0)
	calm = 0.0 if state != STATE_WANDER or dist < CALM_NEAR else calm + delta
	relief = maxf(relief - delta, 0.0)
	# Погоня кончилась (сущность снова бродит), а трясло сильно — отступает
	if last_state != STATE_WANDER and state == STATE_WANDER and tension > HOT:
		relief = RELIEF_TIME
		tension *= 0.5
		host.retreat()
	last_state = state
	if relief <= 0.0 and calm >= CALM_LIMIT and not player.is_hidden():
		calm = 0.0
		var at: Variant = rumor_point()
		if at != null:
			host.hear_rumor(at)


# Точка «где-то рядом с игроком»: клетка кольца, куда можно дойти
func rumor_point() -> Variant:
	var cell: Variant = Navigator.random_cell_in_band(host.chunk_manager,
		Navigator.world_to_cell(player.global_position), RUMOR_MIN, RUMOR_MAX, rng)
	return null if cell == null else Navigator.cell_to_world(cell)
