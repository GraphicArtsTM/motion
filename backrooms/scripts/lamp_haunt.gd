extends Node

# LampHaunt: свет боится хозяина лабиринта. Чем ближе он к лампе, тем чаще
# она срывается в провалы и трещит — по больному свету игрок понимает, что
# оно рядом, раньше, чем увидит. Лампа одна на чанк 32×32 м, поэтому свет
# не гаснет насовсем, а захлёбывается: в погоне игрок должен видеть, куда
# бежать. Фонарь в руке тоже срывается, когда оно в паре шагов. Пока
# «Наблюдатель» стоит (entity_stalker.gd), свет почти не трогаем — его должно
# быть видно; зато потом «затмение» гасит всё вокруг игрока на миг, пока
# сущность исчезает. Работает поверх нормы лампы (её помнит lamp_manager) и
# поверх больной лампы (lamp_flicker.gd считается раньше — приоритет ниже).

const REACH_NEAR: float = 8.0
const REACH_FAR: float = 24.0
# Сила помехи вплотную и пока оно стоит и смотрит
const HAUNT_MAX: float = 0.8
const PEEK_SCALE: float = 0.3
const BLACKOUT_RADIUS: float = 30.0
const TORCH_NEAR: float = 5.0
const TORCH_FAR: float = 13.0
const TORCH_MAX: float = 0.85

var lamps: Node = null
var entity: Node3D = null
var torch: SpotLight3D = null
var haunted: Dictionary = {}
var blackout_left: float = 0.0
var blackout_len: float = 1.0
var time: float = 0.0


func _ready() -> void:
	add_to_group("lamp_haunt")
	process_priority = 20


# Затмение вокруг игрока: свет гаснет сразу, загорается рывками к концу
func blackout(seconds: float) -> void:
	blackout_left = seconds
	blackout_len = seconds


# Помеха от сущности на расстоянии dist: 0 — нет, HAUNT_MAX — вплотную
static func haunt_amount(dist: float, peeking: bool) -> float:
	var amount: float = HAUNT_MAX * (1.0 - smoothstep(REACH_NEAR, REACH_FAR, dist))
	return amount * PEEK_SCALE if peeking else amount


func _process(delta: float) -> void:
	time += delta
	blackout_left = maxf(blackout_left - delta, 0.0)
	if entity == null or not is_instance_valid(entity):
		var voice: Node = get_tree().get_first_node_in_group("entity_voice")
		entity = voice.get_parent() as Node3D if voice else null
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var active: bool = entity != null and bool(entity.get("placed"))
	var peeking: bool = active and bool(entity.get_meta("peeking", false))
	var still: Dictionary = {}
	for pos in lamps.chunk_nodes:
		var e: Dictionary = lamps.chunk_nodes[pos]
		if e["dark"]:
			continue
		var at: Vector3 = (e["light"] as Node3D).global_position
		var amount: float = 0.0
		if active:
			amount = haunt_amount(_flat(at, entity.global_position), peeking)
		var factor: float = 1.0 - amount * _stutter(pos, amount)
		if blackout_left > 0.0 and player and _flat(at, player.global_position) < BLACKOUT_RADIUS:
			factor = minf(factor, _blackout_factor(pos))
		if factor >= 1.0:
			if haunted.has(pos):
				_apply(e, 1.0)
			continue
		still[pos] = true
		_apply(e, factor)
	haunted = still
	_torch(player)


# Затмение: первые две трети — тьма, дальше свет пробивается вспышками
func _blackout_factor(pos: Vector2i) -> float:
	if blackout_left / blackout_len > 0.35:
		return 0.0
	return 1.0 - _stutter(pos, 0.7)


# Глубина провала на этот кадр: шум по времени, своя фаза у каждого чанка.
# Чем сильнее помеха, тем чаще лампа проваливается целиком, а между
# провалами только чуть дрожит
func _stutter(pos: Vector2i, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var n: float = fposmod(sin((floor(time * 14.0) + pos.x * 13.1 + pos.y * 7.7) * 12.9898) * 43758.5, 1.0)
	return 1.0 if n < amount * 0.55 else 0.12


# Фонарь игрока: flashlight.gd уже выставил свет на кадр — только приглушаем
func _torch(player: Node3D) -> void:
	if player == null:
		return
	if torch == null or not is_instance_valid(torch):
		torch = player.get_node_or_null("CameraRoot/Camera3D/Flashlight") as SpotLight3D
		if torch == null:
			return
	var factor: float = 1.0
	if entity and bool(entity.get("placed")):
		var amount: float = TORCH_MAX * (1.0 - smoothstep(TORCH_NEAR, TORCH_FAR,
			_flat(player.global_position, entity.global_position)))
		factor = 1.0 - amount * _stutter(Vector2i(-7, 3), amount)
	if blackout_left > 0.0:
		factor = minf(factor, _blackout_factor(Vector2i(-7, 3)))
	torch.light_energy *= factor


func _apply(e: Dictionary, factor: float) -> void:
	var light: OmniLight3D = e["light"]
	var panel: ShaderMaterial = e["panel"]
	var hum: AudioStreamPlayer3D = e["hum"]
	if e["flicker"] != null:
		# Больная лампа уже выставила свет на этот кадр — только приглушаем
		light.light_energy *= factor
		return
	light.light_energy = float(e["energy"]) * factor
	if panel:
		panel.set_shader_parameter("brightness", float(e["brightness"]) * factor)
	if hum:
		hum.volume_db = float(e["hum_db"]) + linear_to_db(maxf(factor, 0.05)) * 0.8


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
