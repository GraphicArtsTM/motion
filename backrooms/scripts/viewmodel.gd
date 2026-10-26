extends Node3D

# Viewmodel: руки игрока. Модель процедурная (prop_viewmodel), а здесь —
# жизнь: дыхание в покое, покачивание в ходу, дрожь от страха и одышки,
# замах и бросок банки. Как в Bodycam, руки принадлежат телу, а не камере:
# узел стоит там же, где камера, но поворачивается своей, более медленной
# пружиной и не получает тряску шагов. Поэтому кадр ходит отдельно от рук,
# а руки на рывке мышью отстают и доезжают в кадр.

const PropViewmodel = preload("res://scripts/prop_viewmodel.gd")

@export var player_path: NodePath
@export var throw_path: NodePath
@export var footsteps_path: NodePath
@export var camera_path: NodePath

const SWING_SPEED: float = 3.2
# Пружина рук мягче пружины взгляда (camera_look, 3.6 Гц): руки тяжелее
# головы и доезжают за ~0.2 с
const ARM_FREQUENCY: float = 2.2
const ARM_DAMPING: float = 0.75
const SUBSTEP: float = 1.0 / 120.0
# Дрожь рук, рад: страх (сущность рядом) и одышка после бега
const FEAR_TREMOR: float = 0.012
const TIRED_TREMOR: float = 0.005

var player: PlayerController = null
var camera: Camera3D = null
var presence: Node = null
var arm := Vector2.ZERO  # x — рыскание рук в мире, y — наклон
var arm_speed := Vector2.ZERO
var arm_started: bool = false
var tremor_time: float = 0.0
var noise := FastNoiseLite.new()
var footsteps: FootstepComponent = null
var thrower = null
var items = null
var rig: Node3D = null
var hand: Node3D = null
var can: Node3D = null
var cans: int = 0
var swing: float = 0.0
var breath: float = 0.0


func _ready() -> void:
	player = get_node_or_null(player_path) as PlayerController
	camera = get_node_or_null(camera_path) as Camera3D
	# Позицию берём у камеры, а поворот свой — родитель тут не нужен.
	# И считаемся после всех камерных узлов: иначе руки отставали бы на кадр
	top_level = true
	process_priority = 10
	noise.frequency = 1.0
	noise.seed = randi()
	footsteps = get_node_or_null(footsteps_path) as FootstepComponent
	thrower = get_node_or_null(throw_path)
	var built: Dictionary = PropViewmodel.build()
	rig = built["rig"] as Node3D
	hand = built["hand"] as Node3D
	can = built["can"] as Node3D
	add_child(rig)
	# Руки на слое 2: камера их видит (её cull_mask — все слои), а фонарь
	# (light_cull_mask = 1) не слепит вплотную. Иначе кисти в 30 см от
	# объектива выжигались в белое пятно
	_set_layer(rig, 2)
	if thrower and thrower.has_signal("thrown"):
		thrower.thrown.connect(_on_thrown)
	# Инвентарь ищем лениво: Viewmodel стоит в дереве раньше PlayerItems,
	# и на его _ready группа "player_items" ещё пуста
	_bind_items()


func _process(delta: float) -> void:
	if player == null:
		return
	if items == null:
		_bind_items()
	# В укрытии игра показывает шкаф, а не руки в нём
	visible = not player.is_hidden()
	if not visible:
		return
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	_follow_body(delta)
	_sway(delta, speed)
	_swing(delta)


# Руки тянутся за взглядом своей пружиной и стоят там, где камера.
# Подшаги — как в camera_look: на длинном кадре явная схема раскачивается
func _follow_body(delta: float) -> void:
	var target := Vector2(_yaw(), _pitch())
	if not arm_started:
		arm_started = true
		arm = target
	var step: float = minf(delta, 0.05)
	var count: int = maxi(ceili(step / SUBSTEP), 1)
	var dt: float = step / count
	var w: float = TAU * ARM_FREQUENCY
	for i in count:
		var accel: Vector2 = (target - arm) * w * w - arm_speed * 2.0 * ARM_DAMPING * w
		arm_speed += accel * dt
		arm += arm_speed * dt
	var origin: Vector3 = camera.global_position if camera else global_position
	global_transform = Transform3D(Basis.from_euler(Vector3(arm.y, arm.x, 0.0)), origin)


# Покой и ходьба: дыхание, шаги от пройденного пути и дрожь
func _sway(delta: float, speed: float) -> void:
	breath += delta
	# Качка рук идёт от той же фазы шага, что и качка камеры: один цикл — два
	# шага. Иначе руки, камера и звук шагов жили в трёх ритмах и бились
	var step_phase: float = footsteps.stride_phase * 0.5 if footsteps else 0.0
	var walk: float = clampf(speed / 5.0, 0.0, 1.0)
	var bob_x: float = sin(step_phase) * 0.016 * walk
	var bob_y: float = -absf(cos(step_phase)) * 0.012 * walk
	rig.position = Vector3(bob_x, bob_y + sin(breath * 1.1) * 0.004, 0.0)
	var tremor: Vector2 = _tremor(delta)
	rig.rotation = Vector3(bob_y * 0.6 + tremor.y, tremor.x, -bob_x * 1.4)


# Дрожь рук: страх (чем ближе сущность) и одышка. Частая, мелкая — руки
# не трясутся как в припадке, а не могут держать ровно
func _tremor(delta: float) -> Vector2:
	if presence == null or not is_instance_valid(presence):
		presence = get_tree().get_first_node_in_group("entity_voice")
	var fear: float = float(presence.get("dread")) if presence else 0.0
	var tired: float = clampf(1.0 - player.get_stamina_percent() / 0.4, 0.0, 1.0)
	var amount: float = fear * FEAR_TREMOR + tired * TIRED_TREMOR
	tremor_time += delta * 9.0
	return Vector2(noise.get_noise_2d(tremor_time, 0.0),
		noise.get_noise_2d(0.0, tremor_time + 40.0)) * amount


# Замах и бросок: правая рука делает тычок вперёд и чуть вверх, банка
# исчезает из кулака. Смещения ставим, а не копим: узел руки держим
# нулём в покое, иначе замах прибавлялся бы к самому себе каждый кадр
func _swing(delta: float) -> void:
	if swing <= 0.0:
		if can:
			can.visible = cans > 0
		hand.position = Vector3.ZERO
		hand.rotation = Vector3.ZERO
		return
	swing = maxf(swing - delta * SWING_SPEED, 0.0)
	var k: float = sin(swing * PI)
	# Угол намеренно мал: узел крутится вокруг самой камеры, и большой
	# поворот вбрасывает в кадр рукав по локоть — на снимке это выглядело
	# как две трубы поперёк экрана
	hand.position = Vector3(0.0, 0.035 * k, -0.14 * k)
	hand.rotation = Vector3(0.2 * k, 0.0, -0.12 * k)
	# Банка ушла в полёт и вернётся в кулак только когда рука доехала
	# обратно (ветка выше). Раньше она всплывала через 0.08 с — на пике
	# замаха, из-за чего бросок читался как «банка мигнула»
	if can:
		can.visible = false


func _yaw() -> float:
	if player == null:
		return 0.0
	# Не rotation.y корпуса: корпус доворачивается с задержкой, а руки
	# должны тянуться за взглядом, то есть за мышью
	return float(player.look_yaw)


func _pitch() -> float:
	if player == null:
		return 0.0
	return float(player.camera_rotation_x)


func _bind_items() -> void:
	items = get_tree().get_first_node_in_group("player_items")
	if items == null or not items.has_signal("cans_changed"):
		items = null
		return
	items.cans_changed.connect(_on_cans_changed)
	_on_cans_changed(int(items.cans))


func _on_thrown() -> void:
	swing = 1.0


func _on_cans_changed(count: int) -> void:
	cans = count


# Слой 2 для всех мешей рук: фонарь их не освещает, остальной мир — да
func _set_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for child in node.get_children():
		_set_layer(child, layer)
