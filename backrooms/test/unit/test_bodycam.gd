extends GutTest

# Нагрудная камера: взгляд с весом не раскачивается ни на каком fps,
# толчок шага даёт заявленный кивок, тряска не трогает намерение игрока.

const PlayerScene = preload("res://scenes/player.tscn")

var player = null
var look = null
var shake = null
var root_node: Node3D = null
var camera: Camera3D = null


func before_each() -> void:
	root_node = Node3D.new()
	player = PlayerScene.instantiate()
	root_node.add_child(player)
	add_child_autofree(root_node)
	look = player.get_node("CameraLook")
	shake = player.get_node("BodycamShake")
	camera = player.get_node("CameraRoot/Camera3D")
	# Ведём узлы вручную, с нужным шагом кадра
	for node in [look, shake, player.get_node("BodycamComponent"), player.get_node("CameraLens")]:
		node.set_process(false)
	player.set_physics_process(false)


func _view_yaw() -> float:
	return player.rotation.y + player.get_node("CameraRoot").rotation.y


func test_aim_settles_at_any_fps() -> void:
	for fps in [10.0, 20.0, 30.0, 60.0, 144.0]:
		player.look_yaw = 0.0
		player.rotation.y = 0.0
		look.started = false
		look._process(1.0 / fps)
		player.look_yaw = deg_to_rad(90.0)
		var peak: float = 0.0
		for i in int(fps):
			look._process(1.0 / fps)
			peak = maxf(peak, rad_to_deg(_view_yaw()))
		assert_almost_eq(rad_to_deg(_view_yaw()), 90.0, 0.5, "не сошлось на %d fps" % fps)
		assert_lt(peak, 95.0, "перелёт на %d fps" % fps)


func test_aim_has_weight() -> void:
	look._process(1.0 / 60.0)
	player.look_yaw = deg_to_rad(90.0)
	look._process(1.0 / 60.0)
	# Через кадр после рывка мыши кадр ещё в пути, а не прибит к курсору
	assert_between(rad_to_deg(_view_yaw()), 1.0, 60.0)


func test_step_nod_matches_setting() -> void:
	shake._on_stepped(2.5, false, false)
	var lowest: float = 0.0
	for i in 60:
		shake._process(1.0 / 60.0)
		lowest = minf(lowest, rad_to_deg(shake.nod.x))
	assert_almost_eq(-lowest, shake.walk_nod, 0.12)
	assert_almost_eq(rad_to_deg(shake.nod.x), 0.0, 0.05, "кивок должен гаснуть")


func test_shake_does_not_touch_intent() -> void:
	player.look_yaw = 0.3
	player.camera_rotation_x = -0.2
	shake._on_stepped(5.0, true, false)
	for i in 30:
		shake._process(1.0 / 60.0)
	assert_eq(player.look_yaw, 0.3)
	assert_eq(player.camera_rotation_x, -0.2)
	assert_ne(camera.rotation.x, 0.0)


# Руки принадлежат телу: на рывке мышью кадр уже доехал, а руки ещё в пути
func test_arms_lag_behind_camera() -> void:
	var arms = player.get_node("Viewmodel")
	arms.set_process(false)
	look._process(1.0 / 60.0)
	arms._process(1.0 / 60.0)
	player.look_yaw = deg_to_rad(60.0)
	for i in 8:
		look._process(1.0 / 60.0)
		arms._process(1.0 / 60.0)
	var cam_yaw: float = rad_to_deg(_view_yaw())
	var arm_yaw: float = rad_to_deg(arms.arm.x)
	assert_gt(cam_yaw - arm_yaw, 5.0, "руки должны отставать от кадра")
	for i in 90:
		look._process(1.0 / 60.0)
		arms._process(1.0 / 60.0)
	assert_almost_eq(rad_to_deg(arms.arm.x), 60.0, 0.5, "и доезжать")


# Тряска шагов крутит камеру, но не руки
func test_arms_ignore_camera_shake() -> void:
	var arms = player.get_node("Viewmodel")
	arms.set_process(false)
	arms._process(1.0 / 60.0)
	var before: Basis = arms.global_transform.basis
	shake._on_stepped(5.0, true, false)
	for i in 10:
		shake._process(1.0 / 60.0)
	arms._process(1.0 / 60.0)
	assert_ne(camera.rotation.x, 0.0)
	assert_true(arms.global_transform.basis.is_equal_approx(before))
	assert_true(arms.global_position.is_equal_approx(camera.global_position))
