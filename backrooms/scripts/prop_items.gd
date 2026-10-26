extends RefCounted

# PropItems: мелкие предметы — банка (летит, звенит, отвлекает) и
# предохранитель-маячок (светится и гудит). Собраны из палитры и примитивов
# prop_factory.gd. Поведение остаётся у владельцев: can_projectile.gd,
# fuse.gd, fuse_spawner.gd.

const PropFactory = preload("res://scripts/prop_factory.gd")

const CAN_RADIUS: float = 0.05
const CAN_HEIGHT: float = 0.14


# Предохранитель: толстая стеклянная трубка между двумя колпаками — как
# силовой предохранитель на планке. Трубка светится, поэтому маячок видно
# издалека. Свет и гул вешает fuse.gd
static func build_fuse() -> Dictionary:
	var root := Node3D.new()
	root.name = "Fuse"
	var glow := PropFactory.glow_material(Color(0.5, 1.0, 0.55), 2.4)
	glow.albedo_color = Color(0.32, 0.72, 0.38)
	var metal := PropFactory.material_named("can_metal")
	# Нижний колпак с фланцем
	PropFactory.cylinder(root, 0.06, 0.12, Vector3(0, 0.06, 0), metal)
	PropFactory.torus(root, 0.048, 0.07, Vector3(0, 0.12, 0), metal)
	# Стекло с нитью: светится изнутри
	PropFactory.cylinder(root, 0.046, 0.24, Vector3(0, 0.26, 0), glow)
	# Верхний колпак с фланцем и выводом
	PropFactory.torus(root, 0.048, 0.07, Vector3(0, 0.4, 0), metal)
	PropFactory.cylinder(root, 0.06, 0.12, Vector3(0, 0.46, 0), metal)
	PropFactory.taper(root, 0.028, 0.014, 0.05, Vector3(0, 0.545, 0), metal)
	return {"root": root, "glow": glow}


# Банка: корпус с этикеткой, ободы сверху и снизу, крышка с язычком.
# Меш отдельно от коллайдера — RigidBody3D видит только ПРЯМЫХ детей
static func build_can() -> Dictionary:
	var root := Node3D.new()
	root.name = "CanBody"
	var metal := PropFactory.material_named("can_metal")
	var paper := PropFactory.material_named("paper")
	PropFactory.cylinder(root, 0.048, 0.12, Vector3(0, 0.07, 0), metal)
	PropFactory.cylinder(root, 0.05, 0.08, Vector3(0, 0.07, 0), paper)
	PropFactory.torus(root, 0.04, 0.05, Vector3(0, 0.015, 0), metal)
	PropFactory.torus(root, 0.04, 0.05, Vector3(0, 0.125, 0), metal)
	PropFactory.cylinder(root, 0.032, 0.01, Vector3(0, 0.138, 0), metal)
	PropFactory.box(root, Vector3(0.03, 0.006, 0.014), Vector3(0.01, 0.146, 0), metal)
	var shape := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = CAN_RADIUS
	cylinder_shape.height = CAN_HEIGHT
	shape.shape = cylinder_shape
	shape.position.y = CAN_HEIGHT * 0.5
	# Снаряд сам добавит коллайдер себе: RigidBody3D видит только прямых детей
	return {"root": root, "shape": shape}
