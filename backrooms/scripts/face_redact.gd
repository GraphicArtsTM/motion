extends Node

# FaceRedact: лицо сущности на записи закрыто квадратами, как на выданных
# полицией роликах — так делает и Bodycam. Здесь только где лицо в кадре:
# проекция головы в координаты рендера и её размер. Сами квадраты рисует
# post_process.gdshader (face_uv, face_r), там же они гнутся объективом.

@export var camera_path: NodePath

# Лицо в системе модели сущности (prop_entity: глаза на 2.35, морда вынесена
# вперёд на -0.2 по Z) и его полуширина с запасом на челюсть и надбровье
const FACE_LOCAL := Vector3(0.0, 2.3, -0.18)
const FACE_HALF: float = 0.2
const MAX_DISTANCE: float = 40.0

@onready var camera: Camera3D = get_node_or_null(camera_path) as Camera3D

var material: ShaderMaterial = null
var host: Node3D = null


func _process(_delta: float) -> void:
	if material == null:
		_bind_post()
	if material == null or camera == null:
		return
	material.set_shader_parameter("face_r", 0.0)
	if host == null or not is_instance_valid(host):
		var voice: Node = get_tree().get_first_node_in_group("entity_voice")
		host = voice.get_parent() as Node3D if voice else null
	if host == null or not bool(host.get("placed")):
		return
	var face: Vector3 = host.global_transform * FACE_LOCAL
	if camera.is_position_behind(face) \
			or camera.global_position.distance_to(face) > MAX_DISTANCE \
			or not _visible(face):
		return
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var center: Vector2 = camera.unproject_position(face)
	var edge: Vector2 = camera.unproject_position(face
		+ camera.global_transform.basis.x * FACE_HALF)
	material.set_shader_parameter("face_uv", center / size)
	material.set_shader_parameter("face_r", center.distance_to(edge) / size.y)


# Лицо за стеной не закрываем: квадраты выдали бы сущность сквозь стену
func _visible(face: Vector3) -> bool:
	var exclude: Array[RID] = []
	if host is CollisionObject3D:
		exclude.append((host as CollisionObject3D).get_rid())
	var player: Node = get_parent()
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, face, 1, exclude)
	return camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _bind_post() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var post: ColorRect = hud.find_child("PostProcess", true, false) as ColorRect if hud else null
	if post and post.material is ShaderMaterial:
		material = post.material
