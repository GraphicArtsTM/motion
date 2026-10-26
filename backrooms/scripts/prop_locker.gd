extends RefCounted

# PropLocker: стальной шкаф-укрытие. Корпус собран из панелей с толщиной:
# внутри полка, крючок и тёмная задняя стенка, поэтому из укрытия видно
# не мир насквозь, а нутро шкафа и полосы света сквозь жалюзи — щели в
# дверце настоящие. Дверца — узел "hinge": укрытие открывает её поворотом
# (hiding_spot.gd), все её детали едут вместе с ней. Геометрия — mesh_kit.gd,
# краска, вмятины и ржавчина — prop_factory.gd.

const PropFactory = preload("res://scripts/prop_factory.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")

const HINGE_X: float = -0.35
# Лицо корпуса на 0.45: дверца ложится на него, а не тонет внутри
const DOOR_Z: float = 0.45
const HINGE_Y: float = 1.08
const DOOR_W: float = 0.7
const DOOR_H: float = 1.92
const SHELL: float = 0.02


static func build_locker() -> Dictionary:
	var root := Node3D.new()
	root.name = "Locker"
	var paint := PropFactory.material_named("locker_paint")
	var inner := PropFactory.material_named("locker_inner")
	var frame := PropFactory.material_named("frame_dark")
	var steel := PropFactory.material_named("steel")
	root.add_child(PropFactory.cached_mesh("locker_body", func() -> MeshInstance3D:
		var kit := MeshKit.new()
		_body(kit, paint, inner, frame, steel)
		return kit.build("LockerBody")))
	PropFactory.solid_box(root, Vector3(0.9, 2.2, 0.9), Vector3(0, 1.1, 0))

	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(HINGE_X, HINGE_Y, DOOR_Z)
	root.add_child(hinge)
	hinge.add_child(PropFactory.cached_mesh("locker_door", func() -> MeshInstance3D:
		var kit := MeshKit.new()
		_door(kit, paint, steel, frame)
		return kit.build("LockerDoor")))
	return {"root": root, "hinge": hinge}


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


# Корпус: цоколь, боковины, спинка, крыша с козырьком, рамка проёма,
# внутри полка и крючок, на рамке — стволы петель
static func _body(kit: MeshKit, paint: Material, inner: Material, frame: Material,
		steel: Material) -> void:
	kit.box(frame, Vector3(0.88, 0.1, 0.84), _at(Vector3(0, 0.05, -0.02)), 0.01)
	for side in [-1.0, 1.0]:
		kit.box(paint, Vector3(SHELL, 2.1, 0.9), _at(Vector3(side * 0.44, 1.15, 0)), 0.008)
		# Стойки рамки проёма по бокам от дверцы
		kit.box(paint, Vector3(0.09, 2.1, SHELL), _at(Vector3(side * 0.395, 1.15, 0.44)), 0.006)
	kit.box(paint, Vector3(0.9, 2.1, SHELL), _at(Vector3(0, 1.15, -0.44)), 0.008)
	kit.box(inner, Vector3(0.84, 2.0, 0.005), _at(Vector3(0, 1.15, -0.425)), 0.0)
	kit.box(paint, Vector3(0.9, SHELL, 0.9), _at(Vector3(0, 0.11, 0)), 0.006)
	kit.box(paint, Vector3(0.9, 0.07, SHELL), _at(Vector3(0, 0.09, 0.44)), 0.006)
	kit.box(paint, Vector3(0.9, 0.1, SHELL), _at(Vector3(0, 2.1, 0.44)), 0.006)
	# Крыша с козырьком, наклонённым вперёд
	kit.box(paint, Vector3(0.96, 0.04, 0.96), _at(Vector3(0, 2.22, 0.01), Vector3(0.04, 0, 0)), 0.012)
	# Нутро: полка под шапку и крючок
	kit.box(paint, Vector3(0.86, 0.015, 0.8), _at(Vector3(0, 1.86, -0.02)), 0.004)
	kit.tube(steel, PackedVector3Array([Vector3(0, 1.75, -0.43), Vector3(0, 1.75, -0.36),
		Vector3(0, 1.8, -0.33)]), PackedFloat32Array([0.007, 0.007, 0.006]), Transform3D.IDENTITY, 6)
	# Петли: стволы на оси дверцы
	for y in [0.42, 1.08, 1.74]:
		kit.tube(steel, PackedVector3Array([Vector3(HINGE_X - 0.008, y - 0.06, DOOR_Z + 0.012),
			Vector3(HINGE_X - 0.008, y + 0.06, DOOR_Z + 0.012)]),
			PackedFloat32Array([0.011, 0.011]), Transform3D.IDENTITY, 8)


# Дверца в системе петли: x от 0 до DOOR_W, y вокруг HINGE_Y, лицо на z>0.
# Низ — сплошное полотно с рёбрами, верх — рама с наклонными жалюзи
static func _door(kit: MeshKit, paint: Material, steel: Material, frame: Material) -> void:
	var half: float = DOOR_H * 0.5
	var t: float = 0.022
	var rust := PropFactory.material_named("rust")
	var brass := PropFactory.material_named("brass")
	kit.box(paint, Vector3(DOOR_W, 1.28, t), _at(Vector3(DOOR_W * 0.5, -half + 0.64, t * 0.5)), 0.006)
	for side in [0.04, DOOR_W - 0.04]:
		kit.box(paint, Vector3(0.08, 0.64, t), _at(Vector3(side, half - 0.32, t * 0.5)), 0.005)
	kit.box(paint, Vector3(DOOR_W, 0.07, t), _at(Vector3(DOOR_W * 0.5, half - 0.035, t * 0.5)), 0.005)
	# Жалюзи: щели насквозь, пластины наклонены — снаружи нутра не видно,
	# изнутри видно полосами
	for i in 7:
		kit.box(paint, Vector3(DOOR_W - 0.16, 0.06, 0.006),
			_at(Vector3(DOOR_W * 0.5, half - 0.12 - i * 0.075, t * 0.5), Vector3(0.65, 0, 0)), 0.002)
	# Рёбра жёсткости на полотне
	for y in [-0.55, -0.1]:
		kit.box(paint, Vector3(DOOR_W - 0.14, 0.03, 0.006), _at(Vector3(DOOR_W * 0.5, y, t + 0.002)), 0.003)
	# Защёлка: тёмная чашка, ручка-скоба, проушина с навесным замком
	var lock_x: float = DOOR_W - 0.075
	kit.box(frame, Vector3(0.05, 0.16, 0.006), _at(Vector3(lock_x, 0.02, t + 0.002)), 0.003)
	kit.tube(steel, PackedVector3Array([Vector3(lock_x, -0.05, t), Vector3(lock_x, -0.05, t + 0.03),
		Vector3(lock_x, 0.09, t + 0.03), Vector3(lock_x, 0.09, t)]),
		PackedFloat32Array([0.008, 0.008, 0.008, 0.008]), Transform3D.IDENTITY, 6)
	kit.box(steel, Vector3(0.03, 0.05, 0.012), _at(Vector3(lock_x, -0.12, t + 0.006)), 0.003)
	kit.box(brass, Vector3(0.042, 0.05, 0.018), _at(Vector3(lock_x, -0.2, t + 0.016), Vector3(0, 0, 0.08)), 0.005)
	kit.torus(steel, 0.013, 0.0035, _at(Vector3(lock_x, -0.165, t + 0.016), Vector3(PI * 0.5, 0, 0.08)), 12, 5)
	# Номерок над жалюзи
	kit.box(brass, Vector3(0.1, 0.035, 0.004), _at(Vector3(DOOR_W * 0.5, half - 0.035, t + 0.002)), 0.0015)
	# Подтёки ржавчины от низа жалюзи и у петель: сплющенная трубка,
	# сужается книзу и чуть виляет — подтёк, а не нарисованная полоса
	var flat := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.12)), Vector3(0, 0, t + 0.002))
	for i in 5:
		var x: float = 0.1 + i * 0.12 + fmod(i * 0.07, 0.04)
		var length: float = 0.16 + fmod(i * 0.37, 0.28)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for j in 5:
			var k: float = j / 4.0
			pts.append(Vector3(x + sin(k * 5.0 + i) * 0.006, 0.31 - length * k, 0.0))
			radii.append(lerpf(0.009 + 0.004 * (i % 2), 0.0015, k))
		kit.tube(rust, pts, radii, flat, 5)
	kit.ellipsoid(rust, Vector3(0.035, 0.08, 0.002), _at(Vector3(0.03, -half + 0.12, t + 0.002)), 3, 8)
