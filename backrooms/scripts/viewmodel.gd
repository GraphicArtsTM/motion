extends Node3D

# Viewmodel: руки игрока перед камерой. Модель процедурная (prop_viewmodel),
# а здесь — жизнь: дыхание в покое, покачивание в ходу, инерция при повороте
# мыши, замах и бросок банки. Узел висит на самой камере, поэтому в приседе,
# в укрытии и на экране смерти руки уезжают и гаснут вместе с ней.

const PropViewmodel = preload("res://scripts/prop_viewmodel.gd")

@export var player_path: NodePath
@export var throw_path: NodePath
@export var footsteps_path: NodePath

const LOOK_LAG: float = 2.2
const LAG_LIMIT: float = 0.05
const SWING_SPEED: float = 3.2

var player: PlayerController = null
var footsteps: FootstepComponent = null
var thrower = null
var items = null
var rig: Node3D = null
var hand: Node3D = null
var can: Node3D = null
var cans: int = 0
var swing: float = 0.0
var breath: float = 0.0
var lag := Vector2.ZERO
var prev_yaw: float = 0.0
var prev_pitch: float = 0.0


func _ready() -> void:
	player = get_node_or_null(player_path) as PlayerController
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
	prev_yaw = _yaw()
	prev_pitch = _pitch()
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
	_sway(delta, speed)
	_swing(delta)


# Покой и ходьба: дыхание, шаги от пройденного пути и инерция
# при повороте мыши — рука тянется за камерой, а не приклеена к ней
func _sway(delta: float, speed: float) -> void:
	var yaw: float = _yaw()
	var pitch: float = _pitch()
	var target := Vector2(
		clampf(wrapf(yaw - prev_yaw, -PI, PI) * LOOK_LAG, -LAG_LIMIT, LAG_LIMIT),
		clampf((pitch - prev_pitch) * LOOK_LAG, -LAG_LIMIT, LAG_LIMIT))
	prev_yaw = yaw
	prev_pitch = pitch
	lag = lag.lerp(target, clampf(delta * 9.0, 0.0, 1.0))

	breath += delta
	# Качка рук идёт от той же фазы шага, что и качка камеры: один цикл — два
	# шага. Иначе руки, камера и звук шагов жили в трёх ритмах и бились
	var step_phase: float = footsteps.stride_phase * 0.5 if footsteps else 0.0
	var walk: float = clampf(speed / 5.0, 0.0, 1.0)
	var bob_x: float = sin(step_phase) * 0.016 * walk
	var bob_y: float = -absf(cos(step_phase)) * 0.012 * walk
	rig.position = Vector3(bob_x, bob_y + sin(breath * 1.1) * 0.004, 0.0)
	rig.rotation = Vector3(lag.y + bob_y * 0.6, lag.x, -bob_x * 1.4)


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
