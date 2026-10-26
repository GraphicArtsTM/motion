extends Node

# ThrowComponent: ПКМ или G — бросить банку вперёд. Банка — шумовая
# приманка: звенит и уводит сущность в сторону от игрока.
# Счётчик банок живёт рядом, в player_items.gd.

const CanProjectile = preload("res://scripts/can_projectile.gd")

# Руки игрока (viewmodel.gd) слушают этот сигнал и делают замах
signal thrown

@export var camera_path: NodePath
@export var items_path: NodePath
@export var cooldown: float = 0.6
@export var throw_speed: float = 13.0

var camera: Camera3D = null
var items = null
var body = null
var timer: float = 0.0


func _ready() -> void:
	camera = get_node_or_null(camera_path) as Camera3D
	items = get_node_or_null(items_path)
	body = get_parent()


func _process(delta: float) -> void:
	timer -= delta


# Ввод — только когда игра идёт: в паузе и на экранах узел не обрабатывает
func _unhandled_input(event: InputEvent) -> void:
	if timer > 0.0 or camera == null or items == null:
		return
	if not event.is_action_pressed("throw"):
		return
	if body != null and body.has_method("is_hidden") and body.is_hidden():
		return
	if not items.take_can():
		return
	timer = cooldown
	_throw()


func _throw() -> void:
	var forward: Vector3 = -camera.global_transform.basis.z
	var can = CanProjectile.new()
	get_tree().current_scene.add_child(can)
	can.global_position = camera.global_position + forward * 0.7 - Vector3(0, 0.15, 0)
	# Скорость игрока добавляется к броску — на бегу банка летит дальше
	var carry := Vector3.ZERO
	if body is CharacterBody3D:
		carry = (body as CharacterBody3D).velocity * 0.6
	can.linear_velocity = forward * throw_speed + Vector3(0, 1.8, 0) + carry
	can.angular_velocity = Vector3(0, 6.0, 0)
	can.start()
	thrown.emit()
