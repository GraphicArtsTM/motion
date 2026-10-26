extends Node

# NoiseBus: разовые шумовые события (звон брошенной банки, грохот двери).
# Сущность слушает их наравне с шумом игрока и идёт на точку звука.
# alarm — не приманка, а тревога: точку выдал сам игрок, увести её нельзя
# и погоню она не сбивает. Живёт вместе с миром, события истекают сами.

const LIFETIME: float = 1.5

var events: Array = []


func _ready() -> void:
	add_to_group("noise_bus")


func emit_noise(pos: Vector3, radius: float, alarm: bool = false) -> void:
	events.append({"pos": pos, "radius": radius, "ttl": LIFETIME, "alarm": alarm})


# Ближайшее событие, которое «докричалось» до точки. Разовое:
# среагировавшая сущность забирает его, чтобы не ходить по кругу.
func poll(pos: Vector3) -> Variant:
	var best: Variant = null
	var best_dist: float = INF
	for event in events:
		var dist: float = pos.distance_to(event["pos"])
		if dist <= float(event["radius"]) and dist < best_dist:
			best_dist = dist
			best = event
	if best != null:
		events.erase(best)
	return best


func _process(delta: float) -> void:
	if events.is_empty():
		return
	for event in events:
		event["ttl"] -= delta
	events = events.filter(func(event: Variant) -> bool: return float(event["ttl"]) > 0.0)
