extends RefCounted

# PropItems: мелкие предметы — банка (летит, звенит, отвлекает) и
# предохранитель-маячок (светится и гудит). Геометрия — mesh_kit.gd,
# материалы — prop_factory.gd. Поведение остаётся у владельцев:
# can_projectile.gd, fuse.gd, fuse_spawner.gd. Банка одна и та же в руке
# (prop_viewmodel) и в полёте: раньше в кулаке была в 1.6 раза меньше.

const PropFactory = preload("res://scripts/prop_factory.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")

# Банка 330 мл: радиус 33 мм, высота 115 мм. Коллайдер чуть толще модели —
# мелкая быстрая банка иначе цепляется за кромки стен
const CAN_RADIUS: float = 0.036
const CAN_HEIGHT: float = 0.115


# Корпус банки по профилю: вогнутое дно с ножкой, стенка, сужение горлышка,
# завальцованный край и утопленная крышка; этикетка — кольцо поверх стенки,
# язычок — пластинка на крышке. Начало координат — на дне
static func can_mesh(kit: MeshKit, xf: Transform3D, metal: Material, label: Material) -> void:
	kit.lathe(metal, PackedVector2Array([
		Vector2(0.0, 0.009), Vector2(0.018, 0.006), Vector2(0.026, 0.0),
		Vector2(0.031, 0.003), Vector2(0.033, 0.012), Vector2(0.033, 0.099),
		Vector2(0.029, 0.108), Vector2(0.0272, 0.112), Vector2(0.0278, 0.1152),
		Vector2(0.0262, 0.1158), Vector2(0.0252, 0.1115), Vector2(0.0, 0.1115)]), xf, 24)
	kit.lathe(label, PackedVector2Array([Vector2(0.0333, 0.016), Vector2(0.0333, 0.094)]),
		xf, 24)
	kit.box(metal, Vector3(0.011, 0.0016, 0.019),
		xf * Transform3D(Basis(), Vector3(0.0, 0.1125, 0.006)), 0.0007)
	kit.torus(metal, 0.0025, 0.0009, xf * Transform3D(Basis(), Vector3(0.0, 0.1128, 0.0)), 8, 4)


# Банка-снаряд: модель отдельно от коллайдера — RigidBody3D видит только
# ПРЯМЫХ детей, поэтому снаряд сам добавит "shape" себе
static func build_can() -> Dictionary:
	var root := Node3D.new()
	root.name = "CanBody"
	root.add_child(PropFactory.cached_mesh("can", func() -> MeshInstance3D:
		var kit := MeshKit.new()
		can_mesh(kit, Transform3D.IDENTITY, PropFactory.material_named("can_metal"),
			PropFactory.material_named("can_label"))
		return kit.build("Can")))
	var shape := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = CAN_RADIUS
	cylinder_shape.height = CAN_HEIGHT
	shape.shape = cylinder_shape
	shape.position.y = CAN_HEIGHT * 0.5
	return {"root": root, "shape": shape}


# Предохранитель: силовой картридж лежит на боку. Стеклянная колба между
# латунными колпаками с насечкой, внутри светится спираль — по ней маячок
# видно издалека. Из колпаков торчат ножевые контакты. Свет и гул вешает
# fuse.gd
static func build_fuse() -> Dictionary:
	var root := Node3D.new()
	root.name = "Fuse"
	root.add_child(PropFactory.cached_mesh("fuse", _fuse_mesh))
	return {"root": root}


static func _fuse_mesh() -> MeshInstance3D:
	var kit := MeshKit.new()
	var brass := PropFactory.material_named("brass")
	var glass := PropFactory.material_named("fuse_glass")
	var ceramic := PropFactory.material_named("ceramic")
	var filament := PropFactory.glow_material(Color(0.55, 1.0, 0.6), 3.0)
	# Лёжа: ось картриджа вдоль X, центр на высоте радиуса колпака
	var lay := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.058, 0.0))
	for side in [-1.0, 1.0]:
		var cap: Transform3D = lay * Transform3D(Basis.from_scale(Vector3(1, side, 1)),
			Vector3(0.0, side * 0.12, 0.0))
		# Колпак: рифлёные кольца и фланец к стеклу
		# Профиль снизу вверх по внешней стороне — так mesh_kit ставит нормали
		kit.lathe(brass, PackedVector2Array([
			Vector2(0.05, 0.0), Vector2(0.056, 0.006), Vector2(0.056, 0.028),
			Vector2(0.052, 0.036), Vector2(0.056, 0.044), Vector2(0.052, 0.052),
			Vector2(0.056, 0.06), Vector2(0.05, 0.075), Vector2(0.03, 0.08),
			Vector2(0.0, 0.08)]), cap, 22)
		# Ножевой контакт и заклёпка
		kit.box(brass, Vector3(0.05, 0.07, 0.008),
			cap * Transform3D(Basis(), Vector3(0.0, 0.11, 0.0)), 0.002)
		kit.ellipsoid(brass, Vector3(0.007, 0.004, 0.007),
			cap * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.12, 0.004)), 4, 8)
	# Колба и керамическая шкала-поясок посередине
	kit.lathe(glass, PackedVector2Array([Vector2(0.046, -0.13), Vector2(0.046, 0.13)]), lay, 22)
	kit.lathe(ceramic, PackedVector2Array([Vector2(0.0475, -0.018), Vector2(0.0475, 0.018)]),
		lay, 22)
	# Спираль: шесть витков от колпака до колпака
	var coil := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 73:
		var t: float = float(i) / 72.0
		var a: float = t * TAU * 6.0
		coil.append(Vector3(cos(a) * 0.014, lerpf(-0.12, 0.12, t), sin(a) * 0.014))
		radii.append(0.0032)
	kit.tube(filament, coil, radii, lay, 5)
	return kit.build("FuseMesh")
