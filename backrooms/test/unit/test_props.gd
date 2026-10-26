extends GutTest

# Модели реквизита: одним мешем на модель, общий меш у одинаковых, у двери
# свои материалы питания, дверца шкафа не утоплена, банка-снаряд по модели.

const PropEntity = preload("res://scripts/prop_entity.gd")
const PropLocker = preload("res://scripts/prop_locker.gd")
const PropExitDoor = preload("res://scripts/prop_exit_door.gd")
const PropItems = preload("res://scripts/prop_items.gd")
const PropViewmodel = preload("res://scripts/prop_viewmodel.gd")


func _meshes(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)
	return out


func test_entity_is_one_mesh() -> void:
	var entity: Node3D = autofree(PropEntity.build_entity())
	var meshes: Array = _meshes(entity)
	assert_eq(meshes.size(), 1)
	assert_lt((meshes[0] as MeshInstance3D).mesh.get_surface_count(), 7)
	assert_eq(entity.name, "EntityBody", "его качает entity_presence по имени")


# Ступни на полу, голова около лица, которое закрывает face_redact
func test_entity_proportions() -> void:
	var entity: Node3D = autofree(PropEntity.build_entity())
	var aabb: AABB = (_meshes(entity)[0] as MeshInstance3D).mesh.get_aabb()
	assert_almost_eq(aabb.position.y, 0.0, 0.02)
	assert_between(aabb.end.y, 2.4, 2.6)


func test_lockers_share_mesh() -> void:
	var a: Dictionary = PropLocker.build_locker()
	var b: Dictionary = PropLocker.build_locker()
	autofree(a["root"])
	autofree(b["root"])
	var ma: Array = _meshes(a["root"])
	var mb: Array = _meshes(b["root"])
	assert_eq(ma.size(), 2, "корпус и дверца")
	for i in ma.size():
		assert_same((ma[i] as MeshInstance3D).mesh, (mb[i] as MeshInstance3D).mesh)


# Дверца ложится на лицо корпуса (0.45), а не тонет в нём: полотно снаружи,
# внутрь проёма заходят только наклонные пластины жалюзи — не глубже рамки
func test_locker_door_on_face() -> void:
	var built: Dictionary = PropLocker.build_locker()
	autofree(built["root"])
	var door: MeshInstance3D = _meshes(built["hinge"])[0]
	var aabb: AABB = door.mesh.get_aabb()
	var z: float = (built["hinge"] as Node3D).position.z
	assert_almost_eq(z, 0.45, 0.001)
	assert_gte(z + aabb.end.z, 0.47, "лицо дверцы снаружи корпуса")
	assert_gte(z + aabb.position.z, 0.43, "внутрь не глубже рамки проёма")


func test_exit_doors_own_power_materials() -> void:
	var a: Dictionary = PropExitDoor.build_exit_door()
	var b: Dictionary = PropExitDoor.build_exit_door()
	autofree(a["root"])
	autofree(b["root"])
	assert_ne(a["glow"], b["glow"])
	for door in [a, b]:
		var mi: MeshInstance3D = _meshes(door["root"])[0]
		var used: Array = []
		for s in mi.mesh.get_surface_count():
			used.append(mi.get_surface_override_material(s))
		assert_has(used, door["glow"], "полоса питания — материал этой двери")
		for lamp in door["lamps"]:
			assert_has(used, lamp)


func test_can_collider_matches_model() -> void:
	var built: Dictionary = PropItems.build_can()
	autofree(built["root"])
	autofree(built["shape"])
	var aabb: AABB = (_meshes(built["root"])[0] as MeshInstance3D).mesh.get_aabb()
	var shape: CylinderShape3D = (built["shape"] as CollisionShape3D).shape
	assert_almost_eq(shape.height, aabb.size.y, 0.005)
	assert_between(shape.radius, aabb.size.x * 0.5, aabb.size.x * 0.5 + 0.005)


# Банка в руке — та же, что летит: размер совпадает
func test_hand_can_matches_thrown() -> void:
	var view: Dictionary = PropViewmodel.build()
	autofree(view["rig"])
	var thrown: Dictionary = PropItems.build_can()
	autofree(thrown["root"])
	autofree(thrown["shape"])
	var held: AABB = (_meshes(view["can"])[0] as MeshInstance3D).mesh.get_aabb()
	var flying: AABB = (_meshes(thrown["root"])[0] as MeshInstance3D).mesh.get_aabb()
	assert_almost_eq(held.size.x, flying.size.x, 0.001)
	assert_almost_eq(held.size.y, flying.size.y, 0.001)
