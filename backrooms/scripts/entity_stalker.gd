extends Node

# EntityStalker: «Наблюдатель». Иногда хозяин лабиринта не охотится, а
# встаёт в конце коридора впереди игрока и молча смотрит. Задержишь на нём
# взгляд или пойдёшь навстречу — свет вокруг гаснет (lamp_haunt.gd), а
# когда загорается, его уже нет: переброшен далеко, как после потери следа.
# Пока стоит, мозг entity.gd выключен — не гонится и не хватает, а мета
# "peeking" говорит entity_presence.gd, что это не смерть и не пауза.
# Живёт ребёнком узла Entity (world.tscn), как entity_presence.gd.

const Navigator = preload("res://scripts/entity_navigator.gd")
const AudioEntity = preload("res://scripts/audio_entity.gd")
const AudioBank = preload("res://scripts/audio_bank.gd")
const Darkness = preload("res://scripts/darkness.gd")

enum Phase { IDLE, PEEK, VANISH }

const STATE_WANDER: int = 0 # Entity.State.WANDER
const FIRST_DELAY: float = 40.0
const COOLDOWN_MIN: float = 50.0
const COOLDOWN_MAX: float = 110.0
const RETRY: float = 3.0
# Встаёт, только если сам был далеко: не прыгает из-за угла под нос
const KEEP_AWAY: float = 30.0
const BAND_MIN: float = 14.0
const BAND_MAX: float = 26.0
# Впереди по взгляду, ~40° в обе стороны: заметить должны, а не наткнуться
const AHEAD_DOT: float = 0.75
const CHECKS: int = 24
# Взгляд «на нём»: ~25° от центра кадра и прямая видимость
const STARE_DOT: float = 0.9
const STARE_LIMIT: float = 1.3
const TOO_CLOSE: float = 9.0
const PEEK_TIMEOUT: float = 9.0
const BLACKOUT: float = 0.9
const VANISH_DELAY: float = 0.45
const BODY_MID: float = 1.6

var host = null
var player = null
var rng := RandomNumberGenerator.new()
var phase := Phase.IDLE
var cooldown: float = FIRST_DELAY
var stare: float = 0.0
var left: float = 0.0


func _ready() -> void:
	rng.randomize()
	host = get_parent()
	player = host.get_node_or_null(host.player_path)


func _physics_process(delta: float) -> void:
	if host == null or player == null:
		return
	match phase:
		Phase.IDLE:
			_wait(delta)
		Phase.PEEK:
			_watch(delta)
		Phase.VANISH:
			left -= delta
			if left <= 0.0:
				_release()


func is_peeking() -> bool:
	return phase != Phase.IDLE


# Ждём своего часа: сущность бродит далеко и игрок не в шкафу
func _wait(delta: float) -> void:
	if not host.placed or not host.is_physics_processing():
		return
	cooldown -= delta
	if cooldown > 0.0:
		return
	cooldown = RETRY
	if int(host.state) != STATE_WANDER or player.is_hidden():
		return
	if _flat(host.global_position, player.global_position) < KEEP_AWAY:
		return
	var cell: Variant = pick_cell()
	if cell != null:
		_appear(cell)


# Клетка впереди по взгляду, под живой лампой (в мёртвом участке его не
# разглядеть), до которой с глаз игрока ничего не заслоняет
func pick_cell() -> Variant:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var forward: Vector3 = _flat_dir(-cam.global_transform.basis.z)
	var ahead: Array = []
	for cell: Vector2i in Navigator.cells_in_band(host.chunk_manager,
			Navigator.world_to_cell(player.global_position), BAND_MIN, BAND_MAX):
		var at: Vector3 = Navigator.cell_to_world(cell)
		if _flat_dir(at - player.global_position).dot(forward) >= AHEAD_DOT and not Darkness.is_dark_at(at):
			ahead.append(cell)
	for _check in mini(CHECKS, ahead.size()):
		var cell: Vector2i = ahead.pop_at(rng.randi_range(0, ahead.size() - 1))
		var at: Vector3 = Navigator.cell_to_world(cell) + Vector3(0, BODY_MID, 0)
		if host.senses.line_clear(cam.global_position, at):
			return cell
	return null


func _appear(cell: Vector2i) -> void:
	host.set_physics_process(false)
	host.set_meta("peeking", true)
	host.velocity = Vector3.ZERO
	host.global_position = Navigator.cell_to_world(cell)
	_face_player(1.0)
	phase = Phase.PEEK
	stare = 0.0
	left = PEEK_TIMEOUT


# Стоит и поворачивает голову следом. Взгляд копится, отвёл — тает медленно
func _watch(delta: float) -> void:
	left -= delta
	_face_player(clampf(delta * 3.0, 0.0, 1.0))
	var seen: bool = is_stared_at()
	stare = stare + delta if seen else maxf(stare - delta * 0.5, 0.0)
	if stare > STARE_LIMIT or _flat(host.global_position, player.global_position) < TOO_CLOSE:
		_vanish(true)
	elif left <= 0.0:
		# Не заметили — уходит тихо; смотрят прямо сейчас — со вспышкой тьмы
		_vanish(seen)


func is_stared_at() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	var target: Vector3 = host.global_position + Vector3(0, BODY_MID, 0)
	var dir: Vector3 = (target - cam.global_position).normalized()
	if dir.dot(-cam.global_transform.basis.z) < STARE_DOT:
		return false
	return host.senses.line_clear(cam.global_position, target)


func _vanish(loud: bool) -> void:
	phase = Phase.VANISH
	left = VANISH_DELAY if loud else 0.0
	if not loud:
		return
	var haunt: Node = get_tree().get_first_node_in_group("lamp_haunt")
	if haunt:
		haunt.blackout(BLACKOUT)
	AudioBank.play_one_shot(get_tree(), host.global_position + Vector3(0, 2.2, 0),
		AudioEntity.whisper(), 9.0, "Entity")


# Свет вернулся — его нет. Не нашлось места вдали — entity.gd поставит сам
func _release() -> void:
	phase = Phase.IDLE
	cooldown = rng.randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	host.remove_meta("peeking")
	if not host._place_far():
		host.placed = false
	host.set_physics_process(true)


func _face_player(weight: float) -> void:
	var to: Vector3 = player.global_position - host.global_position
	host.rotation.y = lerp_angle(host.rotation.y, atan2(-to.x, -to.z), weight)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _flat_dir(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()
