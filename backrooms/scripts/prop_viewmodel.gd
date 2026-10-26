extends RefCounted

# PropViewmodel: руки игрока перед камерой — рукава, кисти и баночка в
# правой. Собрано из тех же примитивов и палитры, что весь реквизит
# (prop_factory): ни одной внешней модели. Предплечье сужается к кисти,
# ладонь приплюснута, пальцы обжимают банку — так рука читается, а не
# висит шаром на трубе.
# Правая рука живёт в своём узле Hand: бросает только она, а не обе сразу.
# Тени выключены — иначе от рук на полу плясали бы чёрные силуэты.
# Поведение (качание, замах) живёт в viewmodel.gd.

const PropFactory = preload("res://scripts/prop_factory.gd")

const PALM_R: float = 0.048
const FINGER_R: float = 0.0095


static func build() -> Dictionary:
	var sleeve := PropFactory.material_named("sleeve")
	var skin := PropFactory.material_named("skin")
	var metal := PropFactory.material_named("view_can")
	var paper := PropFactory.material_named("paper")
	var rig := Node3D.new()
	rig.name = "Rig"
	var hand := Node3D.new()
	hand.name = "Hand"

	# Правая рука (бросающая): рукав из правого нижнего угла кадра, кисть
	# у нижней трети, банка зажата пальцами и смотрит вперёд-вверх
	_limb(hand, 0.036, 0.026, Vector3(0.38, -0.47, -0.14),
		Vector3(0.2, -0.23, -0.4), sleeve)
	PropFactory.cylinder(hand, 0.026, 0.05, Vector3(0.2, -0.23, -0.4), sleeve)
	_palm(hand, skin, Vector3(0.19, -0.215, -0.44))
	var can := _can(hand, metal, paper)
	# Пальцы обжимают банку: короткие, с костяшками на сгибе
	for i in 4:
		PropFactory.capsule(hand, FINGER_R, 0.062,
			Vector3(0.179, -0.238 + i * 0.027, -0.362), skin,
			Vector3(0, 0.2 - i * 0.1, PI * 0.5))
		PropFactory.sphere(hand, 0.0125, Vector3(0.211, -0.236 + i * 0.027, -0.368), skin)
	PropFactory.capsule(hand, 0.012, 0.07, Vector3(0.16, -0.243, -0.352), skin,
		Vector3(0.35, 0, 1.05))

	# Левая рука: свободная, ниже и ближе к кромке кадра, пальцы разжаты
	_limb(rig, 0.034, 0.025, Vector3(-0.39, -0.49, -0.12),
		Vector3(-0.22, -0.25, -0.4), sleeve)
	PropFactory.sphere(rig, 0.025, Vector3(-0.22, -0.25, -0.4), skin)
	_palm(rig, skin, Vector3(-0.215, -0.26, -0.44))
	for i in 4:
		PropFactory.capsule(rig, FINGER_R, 0.07,
			Vector3(-0.248 + i * 0.024, -0.302, -0.478), skin,
			Vector3(-1.75 + i * 0.07, 0, -0.12 + i * 0.08))
	PropFactory.capsule(rig, 0.011, 0.05, Vector3(-0.176, -0.288, -0.442), skin,
		Vector3(-1.2, 0, -0.8))

	rig.add_child(hand)
	# От рук не должно падать теней на лабиринт: они висят на камере
	_no_shadows(rig)

	return {"rig": rig, "hand": hand, "can": can}


# Банка в кулаке: корпус с этикеткой и ободами, крышка с язычком.
# Отдельным узлом, чтобы замах мог спрятать её одним visible
static func _can(parent: Node3D, metal: Material, paper: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Can"
	root.position = Vector3(0.175, -0.165, -0.42)
	root.rotation = Vector3(-0.2, 0, 0)
	parent.add_child(root)
	PropFactory.cylinder(root, 0.03, 0.11, Vector3.ZERO, metal)
	PropFactory.cylinder(root, 0.0315, 0.05, Vector3.ZERO, paper)
	PropFactory.torus(root, 0.024, 0.032, Vector3(0, -0.052, 0), metal)
	PropFactory.torus(root, 0.024, 0.032, Vector3(0, 0.052, 0), metal)
	PropFactory.cylinder(root, 0.02, 0.01, Vector3(0, 0.058, 0), metal)
	PropFactory.box(root, Vector3(0.02, 0.004, 0.01), Vector3(0.008, 0.064, 0), metal)
	return root


# Ладонь: приплюснутый шар. Круглая кисть читается как кулак, сплюснутая —
# как ладонь, которой держат предмет
static func _palm(parent: Node3D, mat: Material, pos: Vector3) -> void:
	var palm: MeshInstance3D = PropFactory.sphere(parent, PALM_R, pos, mat)
	palm.scale = Vector3(0.82, 1.15, 0.5)


# Предплечье: сужается от локтя к кисти. Тот же приём, что у rod
# в prop_factory: ставим по двум точкам, а не подбираем углы Эйлера
static func _limb(parent: Node3D, r_from: float, r_to: float, from: Vector3,
		to: Vector3, mat: Material) -> void:
	var center := (from + to) * 0.5
	var limb := PropFactory.taper(parent, r_from, r_to, from.distance_to(to), center, mat)
	limb.look_at_from_position(center, to, Vector3.UP)
	limb.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


static func _no_shadows(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_no_shadows(child)
