extends RefCounted

# PropLocker: шкаф-укрытие. Собирается из палитры и примитивов prop_factory.
# Дверца — узел "hinge": укрытие открывает её поворотом (hiding_spot.gd),
# поэтому все накладки двери — дети петли и едут вместе с ней.

const PropFactory = preload("res://scripts/prop_factory.gd")

const HINGE_X: float = -0.35
const DOOR_Z: float = 0.44


static func build_locker() -> Dictionary:
	var root := Node3D.new()
	root.name = "Locker"
	var olive := PropFactory.material_named("olive")
	var trim := PropFactory.material_named("trim_dark")
	var steel := PropFactory.material_named("door_gray")
	var brass := PropFactory.material_named("brass")
	var rust := PropFactory.material_named("rust")

	# Корпус: цоколь, сам шкаф, крышка с вентрешёткой под потолком
	PropFactory.box(root, Vector3(0.9, 2.2, 0.9), Vector3(0, 1.1, 0), olive, true)
	PropFactory.box(root, Vector3(0.98, 0.12, 0.98), Vector3(0, 0.06, 0), trim)
	PropFactory.box(root, Vector3(1.02, 0.08, 1.02), Vector3(0, 2.25, 0), olive)
	for i in 3:
		PropFactory.box(root, Vector3(0.56, 0.035, 0.07),
			Vector3(0, 2.3, 0.42 - i * 0.1), trim, false, Vector3(0.7, 0, 0))

	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(HINGE_X, 1.05, DOOR_Z)
	root.add_child(hinge)
	PropFactory.box(hinge, Vector3(0.7, 2.04, 0.04), Vector3(0.35, 0, 0), steel)

	# Жалюзи на дверце: наклонные, чтобы читались как решётка, а не как полоски
	for i in 5:
		PropFactory.box(hinge, Vector3(0.5, 0.04, 0.05),
			Vector3(0.33, 0.72 + i * 0.12, 0.03), trim, false, Vector3(0.75, 0, 0))
	# Подтёки ржавчины по низу дверцы
	for i in 2:
		PropFactory.box(hinge, Vector3(0.02, 0.5 + i * 0.18, 0.012),
			Vector3(0.14 + i * 0.24, -0.32 - i * 0.08, 0.03), rust)
	# Номерок и замочная планка
	PropFactory.box(hinge, Vector3(0.16, 0.07, 0.02), Vector3(0.35, -0.86, 0.03), brass)
	for i in 2:
		PropFactory.box(hinge, Vector3(0.03, 0.035, 0.01),
			Vector3(0.3 + i * 0.08, -0.86, 0.045), trim)
	# Ручка-скоба и ответная планка с защёлкой
	PropFactory.box(hinge, Vector3(0.07, 0.16, 0.05), Vector3(0.63, 0, 0.03), brass)
	PropFactory.cylinder(hinge, 0.026, 0.36, Vector3(0.63, 0, 0.07), trim)
	PropFactory.box(hinge, Vector3(0.05, 0.2, 0.03), Vector3(0.02, 0, 0.03), trim)

	# Петли корпуса: бобышки, на которых дверца висит
	for i in 2:
		PropFactory.box(root, Vector3(0.06, 0.16, 0.06),
			Vector3(-0.42, 0.5 + i * 1.15, 0.44), trim)
		PropFactory.cylinder(root, 0.03, 0.14, Vector3(-0.42, 0.5 + i * 1.15, 0.44), steel)
	return {"root": root, "hinge": hinge}
