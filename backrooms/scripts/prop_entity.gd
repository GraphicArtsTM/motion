extends RefCounted

# PropEntity: хозяин лабиринта. Истощённое высокое существо: сгорбленный
# хребет с позвонками наружу, грудная клетка рёбрами под кожей, впалый
# живот, руки до колен с суставчатыми пальцами и когтями, лапы с когтями.
# Вытянутый череп, надбровье, глубокие глазницы с точками света и
# отвисшая челюсть с зубами. Кожа почти без альбедо, но с морщинистым
# рельефом и обводкой по кромке — в темноте читается силуэт.
# Всё — трубки и эллипсоиды mesh_kit одним мешем на материал (было 70
# узлов и 165 тыс. треугольников). Взгляд в -Z, ступни на y = 0, лицо около
# (0, 2.3, -0.18) — его закрывает face_redact.gd. Качает модель
# entity_presence.gd.

const PropFactory = preload("res://scripts/prop_factory.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")
const MeshCurve = preload("res://scripts/mesh_curve.gd")

const SPINE := [Vector3(0, 1.04, 0.03), Vector3(0, 1.32, 0.08), Vector3(0, 1.62, 0.13),
	Vector3(0, 1.9, 0.1), Vector3(0, 2.03, 0.02), Vector3(0, 2.15, -0.06)]


static func build_entity() -> Node3D:
	var root := Node3D.new()
	root.name = "EntityBody"
	var kit := MeshKit.new()
	var skin := PropFactory.material_named("entity_skin")
	var bone := PropFactory.material_named("entity_bone")
	_torso(kit, skin)
	for side in [-1.0, 1.0]:
		_arm(kit, skin, bone, side)
		_leg(kit, skin, bone, side)
	_head(kit, skin, bone)
	root.add_child(kit.build("EntityMesh"))
	return root


static func _chain(kit: MeshKit, mat: Material, points: Array, radii: Array, sides: int = 8) -> void:
	kit.tube(mat, MeshCurve.smooth(PackedVector3Array(points)),
		MeshCurve.spread(PackedFloat32Array(radii)), Transform3D.IDENTITY, sides)


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


# Хребет, позвонки, клетка с рёбрами, впалый живот, таз, ключицы
static func _torso(kit: MeshKit, skin: Material) -> void:
	_chain(kit, skin, SPINE, [0.075, 0.07, 0.07, 0.065, 0.05, 0.045], 10)
	for i in 9:
		var t: float = float(i) / 8.0
		var p: Vector3 = (SPINE[0] as Vector3).lerp(SPINE[4], t) + Vector3(0, 0, 0.06 + 0.03 * sin(t * PI))
		kit.ellipsoid(skin, Vector3(0.026, 0.02, 0.022), _at(p), 4, 8)
	var chest := Vector3(0, 1.66, 0.06)
	kit.ellipsoid(skin, Vector3(0.15, 0.24, 0.11), _at(chest, Vector3(-0.15, 0, 0)), 8, 16)
	# Рёбра: от хребта сзади вокруг клетки к грудине, к низу всё ниже
	for side in [-1.0, 1.0]:
		for i in 6:
			var y: float = 1.5 + i * 0.06
			var k: float = 0.82 + 0.18 * sin(float(i + 1) / 7.0 * PI)
			var pts: Array = []
			for j in 5:
				var a: float = lerpf(1.35, -1.25, float(j) / 4.0)
				pts.append(chest + Vector3(side * cos(a) * 0.158 * k, y - chest.y - 0.05 * (1.0 - sin(a)) * 0.5,
					-sin(a) * 0.118 * k))
			_chain(kit, skin, pts, [0.012, 0.013, 0.013, 0.012, 0.01], 6)
	# Живот впалый, под ним таз с торчащими остями
	_chain(kit, skin, [Vector3(0, 1.44, 0.0), Vector3(0, 1.25, 0.0), Vector3(0, 1.08, 0.01)],
		[0.1, 0.075, 0.1], 12)
	kit.ellipsoid(skin, Vector3(0.15, 0.09, 0.1), _at(Vector3(0, 1.02, 0.02)), 6, 14)
	for side in [-1.0, 1.0]:
		kit.ellipsoid(skin, Vector3(0.035, 0.03, 0.04), _at(Vector3(side * 0.13, 1.08, -0.03)), 4, 8)
		_chain(kit, skin, [Vector3(side * 0.02, 1.93, -0.02), Vector3(side * 0.13, 1.97, 0.0),
			Vector3(side * 0.25, 1.95, 0.06)], [0.022, 0.02, 0.03], 6)


# Рука до колен: плечо, локоть, запястье, ладонь, четыре длинных пальца
# с когтями и отставленный большой
static func _arm(kit: MeshKit, skin: Material, bone: Material, side: float) -> void:
	var shoulder := Vector3(side * 0.26, 1.94, 0.06)
	var elbow := Vector3(side * 0.34, 1.42, 0.0)
	var wrist := Vector3(side * 0.37, 0.93, -0.1)
	kit.ellipsoid(skin, Vector3(0.065, 0.06, 0.065), _at(shoulder), 5, 10)
	_chain(kit, skin, [shoulder, shoulder.lerp(elbow, 0.5) + Vector3(side * 0.01, 0, 0), elbow],
		[0.052, 0.04, 0.042])
	_chain(kit, skin, [elbow, elbow.lerp(wrist, 0.5), wrist], [0.042, 0.032, 0.026])
	var palm := wrist + Vector3(side * 0.005, -0.06, -0.015)
	kit.ellipsoid(skin, Vector3(0.036, 0.06, 0.017), _at(palm, Vector3(0.15, 0, side * 0.08)), 5, 10)
	for i in 4:
		var spread: float = (i - 1.5) * 0.022
		var base := palm + Vector3(spread * side, -0.05, -0.005)
		var length: float = 0.19 - absf(i - 1.4) * 0.025
		var tip := base + Vector3(spread * side * 0.8, -length, -0.07)
		var mid := base.lerp(tip, 0.5) + Vector3(0, 0.0, -0.035)
		_chain(kit, skin, [base, mid, tip], [0.0105, 0.009, 0.007], 6)
		_claw(kit, bone, tip, (tip - mid).normalized(), 0.0065, 0.04)
	var thumb_base := palm + Vector3(-side * 0.03, 0.01, -0.02)
	var thumb_tip := thumb_base + Vector3(-side * 0.04, -0.09, -0.05)
	_chain(kit, skin, [thumb_base, thumb_base.lerp(thumb_tip, 0.5) + Vector3(0, 0, -0.02), thumb_tip],
		[0.012, 0.01, 0.008], 6)
	_claw(kit, bone, thumb_tip, (thumb_tip - thumb_base).normalized(), 0.007, 0.035)


# Нога: бедро, колено вперёд, голень, лапа с тремя пальцами и когтями
static func _leg(kit: MeshKit, skin: Material, bone: Material, side: float) -> void:
	var hip := Vector3(side * 0.11, 1.0, 0.02)
	var knee := Vector3(side * 0.13, 0.56, -0.07)
	var ankle := Vector3(side * 0.12, 0.1, 0.03)
	_chain(kit, skin, [hip, hip.lerp(knee, 0.5), knee], [0.072, 0.058, 0.05], 9)
	kit.ellipsoid(skin, Vector3(0.05, 0.05, 0.05), _at(knee + Vector3(0, 0, -0.012)), 5, 10)
	_chain(kit, skin, [knee, knee.lerp(ankle, 0.5) + Vector3(0, 0, 0.02), ankle], [0.046, 0.036, 0.03], 8)
	var heel := Vector3(side * 0.12, 0.035, 0.06)
	_chain(kit, skin, [ankle, heel], [0.032, 0.03], 8)
	for i in 3:
		var dx: float = (i - 1) * 0.035
		var ball := Vector3(side * 0.12 + dx, 0.03, -0.08)
		var tip := Vector3(side * 0.12 + dx * 1.6, 0.016, -0.2 + absf(i - 1) * 0.03)
		_chain(kit, skin, [heel, ball, tip], [0.026, 0.017, 0.012], 6)
		_claw(kit, bone, tip, (tip - ball).normalized(), 0.01, 0.05)


# Коготь: конус по направлению пальца
static func _claw(kit: MeshKit, bone: Material, at: Vector3, dir: Vector3, radius: float,
		length: float) -> void:
	var up: Vector3 = dir
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var xf := Transform3D(Basis(side, up, side.cross(up)), at)
	kit.lathe(bone, PackedVector2Array([Vector2(radius, 0.0), Vector2(radius * 0.6, length * 0.6),
		Vector2(0.0005, length)]), xf, 6)


# Череп вытянут назад-вверх, лицо выдвинуто: надбровье, скулы, глазницы
# с огоньками, пасть с зубами и отвисшая челюсть
static func _head(kit: MeshKit, skin: Material, bone: Material) -> void:
	var eye := PropFactory.material_named("entity_eye")
	var mouth := PropFactory.material_named("entity_mouth")
	var socket := PropFactory.material_named("rubber")
	# Череп вытянут назад и вверх — не купол «каски», а длинная голова
	kit.ellipsoid(skin, Vector3(0.088, 0.15, 0.11), _at(Vector3(0, 2.39, -0.04), Vector3(-0.55, 0, 0)), 8, 16)
	# Лицевая часть: без неё глазницы и пасть висели в пустоте под «каской»
	kit.ellipsoid(skin, Vector3(0.068, 0.075, 0.055), _at(Vector3(0, 2.29, -0.15)), 6, 12)
	# Надбровье — валик, сросшийся с лицом, а не козырёк трубкой
	kit.ellipsoid(skin, Vector3(0.078, 0.022, 0.035), _at(Vector3(0, 2.365, -0.175), Vector3(0.2, 0, 0)), 4, 12)
	for side in [-1.0, 1.0]:
		kit.ellipsoid(socket, Vector3(0.028, 0.022, 0.02), _at(Vector3(side * 0.045, 2.33, -0.19)), 5, 10)
		kit.ellipsoid(eye, Vector3(0.008, 0.006, 0.006), _at(Vector3(side * 0.045, 2.332, -0.208)), 4, 6)
		_chain(kit, skin, [Vector3(side * 0.08, 2.32, -0.16), Vector3(side * 0.06, 2.29, -0.2),
			Vector3(side * 0.025, 2.285, -0.205)], [0.012, 0.011, 0.009], 6)
	# Пасть: тёмно-красное нутро, верхние зубы вниз, челюсть подковой вниз-вперёд
	kit.ellipsoid(mouth, Vector3(0.04, 0.048, 0.03), _at(Vector3(0, 2.215, -0.16)), 6, 12)
	var jaw: Array = [Vector3(-0.075, 2.3, -0.1), Vector3(-0.06, 2.18, -0.16), Vector3(0, 2.13, -0.2),
		Vector3(0.06, 2.18, -0.16), Vector3(0.075, 2.3, -0.1)]
	_chain(kit, skin, jaw, [0.018, 0.022, 0.024, 0.022, 0.018], 7)
	for i in 8:
		var a: float = lerpf(-0.9, 0.9, float(i) / 7.0)
		var top := Vector3(sin(a) * 0.05, 2.27, -0.16 - cos(a) * 0.05)
		_claw(kit, bone, top, Vector3(0, -1, -0.1).normalized(), 0.0055, 0.035 + 0.01 * (i % 2))
	for i in 6:
		var a: float = lerpf(-0.8, 0.8, float(i) / 5.0)
		var low := Vector3(sin(a) * 0.055, 2.15, -0.17 - cos(a) * 0.03)
		_claw(kit, bone, low, Vector3(0, 1, -0.15).normalized(), 0.005, 0.03)


# Капсула сущности. Отдаётся отдельно: коллайдер обязан быть
# ПРЯМЫМ ребёнком тела, иначе физика его не увидит.
static func entity_collider() -> CollisionShape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.85
	return shape
