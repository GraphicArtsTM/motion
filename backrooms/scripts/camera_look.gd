extends Node

# CameraLook: куда смотрит нагрудная камера. Рыскание идёт ровно за мышью —
# разница между взглядом и корпусом уходит в сам узел камеры, поэтому корпус
# доворачивается с задержкой, а прицел не плывёт. Наклон доезжает по
# экспоненте: перебега нет, значит камера не проходит через вертикаль.

@export var player_path: NodePath
@export var camera_root_path: NodePath
# Скорость доезда наклона, 1/с: 12 — камера догоняет взгляд примерно за 0.2 с
@export var pitch_speed: float = 12.0

@onready var player: PlayerController = get_node_or_null(player_path) as PlayerController
@onready var camera_root: Node3D = get_node_or_null(camera_root_path) as Node3D


func _process(delta: float) -> void:
	if camera_root == null or player == null:
		return
	# Рывок кадра не должен дёргать наклон — та же политика, что в bodycam
	var step: float = minf(delta, 0.05)
	var pitch: float = lerpf(camera_root.rotation.x, player.camera_rotation_x,
		clampf(pitch_speed * step, 0.0, 1.0))
	camera_root.rotation = Vector3(pitch,
		wrapf(player.look_yaw - player.rotation.y, -PI, PI), 0.0)
