extends RefCounted

# PropViewmodel: руки игрока — рукава с манжетами, предплечья, кисти с
# суставчатыми пальцами и банка в правой. Пальцы — трубки по суставам
# (mesh_kit + mesh_curve): правая обхватывает банку по её окружности,
# большой палец лежит спереди; левая расслаблена, ладонью вниз.
# Координаты — в системе камеры: -Z вперёд, Y вверх. Правая рука живёт
# в своём узле Hand (бросает только она), банка — в узле Can внутри
# (замах прячет её одним visible). Тени выключены: руки висят у объектива,
# от них плясали бы чёрные силуэты. Поведение — viewmodel.gd.

const PropFactory = preload("res://scripts/prop_factory.gd")
const PropItems = preload("res://scripts/prop_items.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")
const MeshCurve = preload("res://scripts/mesh_curve.gd")

# Банка в кулаке: дно у ладони, верх чуть от себя
const CAN_XF := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.18, -0.26, -0.42))
const CAN_R: float = 0.033
const RIGHT_ELBOW := Vector3(0.44, -0.56, -0.08)
const LEFT_ELBOW := Vector3(-0.44, -0.58, -0.1)
# Левая кисть: центр ладони и куда смотрят пальцы
const LEFT_PALM := Vector3(-0.215, -0.27, -0.44)
const LEFT_FORWARD := Vector3(0.25, -0.35, -1.0)


static func build() -> Dictionary:
	var sleeve := PropFactory.material_named("sleeve")
	var skin := PropFactory.material_named("skin")
	var rig := Node3D.new()
	rig.name = "Rig"
	var hand := Node3D.new()
	hand.name = "Hand"
	rig.add_child(hand)

	var right := MeshKit.new()
	_right_hand(right, skin)
	var wrist: Vector3 = CAN_XF * Vector3(CAN_R + 0.035, 0.012, 0.006)
	_forearm(right, skin, sleeve, wrist, RIGHT_ELBOW)
	hand.add_child(right.build("RightArm", false))

	var can := Node3D.new()
	can.name = "Can"
	can.transform = CAN_XF
	var can_kit := MeshKit.new()
	PropItems.can_mesh(can_kit, Transform3D.IDENTITY, PropFactory.material_named("view_metal"),
		PropFactory.material_named("view_label"))
	can.add_child(can_kit.build("CanMesh", false))
	hand.add_child(can)

	var left := MeshKit.new()
	var basis := Basis.looking_at(LEFT_FORWARD.normalized(), Vector3.UP)
	var left_xf := Transform3D(basis, LEFT_PALM)
	_left_hand(left, skin, left_xf)
	_forearm(left, skin, sleeve, left_xf * Vector3(0.0, 0.006, 0.05), LEFT_ELBOW)
	rig.add_child(left.build("LeftArm", false))
	return {"rig": rig, "hand": hand, "can": can}


# Точка на окружности банки: угол от +X (ладонь) через дальнюю сторону (-Z)
static func _around(angle: float, y: float, r: float) -> Vector3:
	return CAN_XF * Vector3(cos(angle) * r, y, sin(angle) * r)


# Правая: ладонь прижата к банке справа, четыре пальца обходят дальнюю
# сторону и выглядывают слева, большой ложится поперёк ближней стороны
static func _right_hand(kit: MeshKit, skin: Material) -> void:
	var palm_xf: Transform3D = CAN_XF * Transform3D(Basis(Vector3.UP, 0.15),
		Vector3(CAN_R + 0.016, 0.056, -0.004))
	# Тыльная сторона кисти — скруглённая, с бугорками костяшек у пальцев
	kit.ellipsoid(skin, Vector3(0.017, 0.05, 0.04), palm_xf, 6, 12)
	for i in 4:
		kit.ellipsoid(skin, Vector3(0.011, 0.0105, 0.011),
			Transform3D(Basis(), _around(0.4, 0.088 - i * 0.021, CAN_R + 0.019)), 4, 8)
	# Пальцы: указательный сверху, мизинец снизу и короче
	for i in 4:
		var y: float = 0.088 - i * 0.021
		var reach: float = 1.0 - i * 0.12
		var r: float = CAN_R + 0.009
		var joints := PackedVector3Array([
			_around(0.35, y, r + 0.012), _around(-0.35, y, r),
			_around(-1.2 * reach, y - 0.002, r), _around(-2.0 * reach, y - 0.004, r)])
		var radii := PackedFloat32Array([0.0098, 0.0094, 0.0086, 0.0074])
		kit.tube(skin, MeshCurve.smooth(joints), MeshCurve.spread(radii), Transform3D.IDENTITY, 7)
	# Большой: от основания ладони через ближнюю сторону вверх-влево
	var thumb := PackedVector3Array([
		_around(0.55, 0.03, CAN_R + 0.022), _around(1.05, 0.05, CAN_R + 0.012),
		_around(1.55, 0.072, CAN_R + 0.01), _around(1.95, 0.08, CAN_R + 0.009)])
	kit.tube(skin, MeshCurve.smooth(thumb), MeshCurve.spread(PackedFloat32Array(
		[0.013, 0.011, 0.0098, 0.0085])), Transform3D.IDENTITY, 7)
	# Подушка у основания большого пальца
	kit.ellipsoid(skin, Vector3(0.018, 0.026, 0.014),
		CAN_XF * Transform3D(Basis(), Vector3(CAN_R + 0.012, 0.03, 0.02)), 5, 8)


# Левая: ладонь вниз, пальцы вперёд и чуть подогнуты, большой — справа
static func _left_hand(kit: MeshKit, skin: Material, xf: Transform3D) -> void:
	kit.ellipsoid(skin, Vector3(0.038, 0.013, 0.044), xf, 6, 12)
	for i in 4:
		kit.ellipsoid(skin, Vector3(0.01, 0.009, 0.01),
			xf * Transform3D(Basis(), Vector3(-0.028 + i * 0.019, 0.004, -0.036)), 4, 8)
	for i in 4:
		var x: float = -0.028 + i * 0.019
		var length: float = 1.0 - absf(i - 1.3) * 0.1
		var joints := PackedVector3Array([Vector3(x, 0.0, -0.038),
			Vector3(x, -0.006, -0.038 - 0.035 * length),
			Vector3(x, -0.022, -0.04 - 0.062 * length),
			Vector3(x, -0.04, -0.04 - 0.074 * length)])
		var radii := PackedFloat32Array([0.0095, 0.009, 0.0082, 0.007])
		kit.tube(skin, MeshCurve.smooth(joints), MeshCurve.spread(radii), xf, 7)
	var thumb := PackedVector3Array([Vector3(0.03, -0.004, 0.018), Vector3(0.05, -0.012, -0.012),
		Vector3(0.058, -0.022, -0.04), Vector3(0.056, -0.03, -0.058)])
	kit.tube(skin, MeshCurve.smooth(thumb), MeshCurve.spread(PackedFloat32Array(
		[0.013, 0.011, 0.0095, 0.0082])), xf, 7)


# Предплечье от запястья к локтю за кадром: кожа до манжеты, дальше рукав.
# Манжета — кольцо вдоль оси руки (раньше вертикальный цилиндр торчал
# поперёк диагонального предплечья «таблеткой»)
static func _forearm(kit: MeshKit, skin: Material, sleeve: Material, wrist: Vector3,
		elbow: Vector3) -> void:
	var axis: Vector3 = (elbow - wrist).normalized()
	var cuff: Vector3 = wrist + axis * 0.075
	kit.tube(skin, PackedVector3Array([wrist, cuff + axis * 0.02]),
		PackedFloat32Array([0.021, 0.026]), Transform3D.IDENTITY, 9)
	kit.tube(sleeve, PackedVector3Array([cuff, cuff + axis * 0.12, elbow]),
		PackedFloat32Array([0.038, 0.043, 0.05]), Transform3D.IDENTITY, 10, false)
	var side: Vector3 = axis.cross(Vector3.FORWARD).normalized()
	var ring_basis := Basis(side, axis, side.cross(axis).normalized())
	kit.torus(sleeve, 0.036, 0.007, Transform3D(ring_basis, cuff), 14, 6)
