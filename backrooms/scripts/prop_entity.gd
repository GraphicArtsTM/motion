extends RefCounted

# PropEntity: модель хозяина лабиринта. Высокий тощий силуэт почти без
# альбедо — читается вблизи светящимися щелями глаз и пасти. Кости собраны
# капсулами и кольцами: коробки вблизи выдавали в нём обрезки.
# Спина колесом, руки до колен, отвисшая челюсть, взгляд направлен в -Z.
# Качается и дышит модель сама — entity_presence.gd.

const PropFactory = preload("res://scripts/prop_factory.gd")


static func build_entity() -> Node3D:
	var root := Node3D.new()
	root.name = "EntityBody"
	var dark := PropFactory.material_named("entity_dark")
	var eye := PropFactory.material_named("entity_eye")
	var mouth := PropFactory.glow_material(Color(0.85, 0.2, 0.12), 1.0)
	_legs(root, dark)
	_arms(root, dark)
	_torso(root, dark)
	_head(root, dark, eye, mouth)
	return root


# Ноги: бедро, колено, голень, стопа-ладонь с тремя когтями.
# Пятки нет — существо не ходит, а тянется вперёд
static func _legs(root: Node3D, dark: Material) -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * 0.14
		PropFactory.capsule(root, 0.072, 0.54, Vector3(x, 0.94, 0.0), dark,
			Vector3(0.06, 0, 0))
		PropFactory.sphere(root, 0.076, Vector3(x, 0.68, 0.02), dark)
		PropFactory.capsule(root, 0.05, 0.5, Vector3(x, 0.42, 0.01), dark,
			Vector3(-0.06, 0, 0))
		PropFactory.sphere(root, 0.052, Vector3(x, 0.16, 0.0), dark)
		PropFactory.box(root, Vector3(0.13, 0.05, 0.24), Vector3(x, 0.03, -0.04), dark)
		for i in 3:
			PropFactory.taper(root, 0.022, 0.004, 0.09,
				Vector3(x + (i - 1) * 0.042, 0.025, -0.19), dark,
				Vector3(-PI * 0.5, 0, 0))


# Руки: плечо, локоть, предплечье — свисают вперёд до колен.
# Пальцы длинные и растопыренные, большой отставлен в сторону
static func _arms(root: Node3D, dark: Material) -> void:
	for side in [-1.0, 1.0]:
		PropFactory.sphere(root, 0.085, Vector3(side * 0.26, 2.0, 0.02), dark)
		PropFactory.capsule(root, 0.058, 0.5, Vector3(side * 0.36, 1.78, 0.06), dark,
			Vector3(0.3, 0, side * 0.24))
		PropFactory.sphere(root, 0.062, Vector3(side * 0.44, 1.52, 0.1), dark)
		PropFactory.capsule(root, 0.048, 0.56, Vector3(side * 0.47, 1.24, -0.02), dark,
			Vector3(0.22, 0, side * 0.06))
		PropFactory.sphere(root, 0.05, Vector3(side * 0.48, 0.98, -0.1), dark)
		PropFactory.box(root, Vector3(0.1, 0.17, 0.06), Vector3(side * 0.48, 0.9, -0.13), dark)
		for i in 4:
			PropFactory.capsule(root, 0.014, 0.21,
				Vector3(side * 0.48 + (i - 1.5) * 0.03, 0.75, -0.17), dark,
				Vector3(0.32, 0, (i - 1.5) * 0.14))
		PropFactory.capsule(root, 0.016, 0.13, Vector3(side * 0.53, 0.86, -0.1), dark,
			Vector3(0, 0, side * 0.9))


# Торс: таз, впалый живот, рёбра кольцами, горб на спине и вздёрнутые плечи
static func _torso(root: Node3D, dark: Material) -> void:
	PropFactory.box(root, Vector3(0.26, 0.18, 0.2), Vector3(0, 0.98, 0), dark)
	for side in [-1.0, 1.0]:
		PropFactory.sphere(root, 0.075, Vector3(side * 0.115, 0.96, 0), dark)
	PropFactory.capsule(root, 0.085, 0.34, Vector3(0, 1.16, 0.01), dark)
	for i in 5:
		var rib: MeshInstance3D = PropFactory.torus(root, 0.1, 0.17,
			Vector3(0, 1.36 + i * 0.085, 0.02), dark)
		rib.scale = Vector3(1.0, 0.5, 0.72)
	PropFactory.box(root, Vector3(0.34, 0.3, 0.24), Vector3(0, 1.86, 0.03), dark,
		false, Vector3(-0.1, 0, 0))
	PropFactory.sphere(root, 0.15, Vector3(0, 2.0, 0.12), dark)
	PropFactory.box(root, Vector3(0.7, 0.11, 0.24), Vector3(0, 2.04, 0.03), dark,
		false, Vector3(-0.12, 0, 0))


# Голова: позвонки шеи, выдвинутый вперёд череп, нависающее надбровье,
# глазницы под ним и отвисшая челюсть с зубами. Лицо вынесено ВПЕРЁД
# черепа: утопленные в него глаза не видно вовсе
static func _head(root: Node3D, dark: Material, eye: Material, mouth: Material) -> void:
	PropFactory.capsule(root, 0.06, 0.26, Vector3(0, 2.12, -0.01), dark,
		Vector3(0.35, 0, 0))
	for i in 2:
		PropFactory.sphere(root, 0.045, Vector3(0, 2.1 + i * 0.11, -0.02 - i * 0.05), dark)
	PropFactory.box(root, Vector3(0.24, 0.28, 0.24), Vector3(0, 2.36, -0.06), dark,
		false, Vector3(0.12, 0, 0))
	PropFactory.taper(root, 0.11, 0.06, 0.14, Vector3(0, 2.5, -0.09), dark,
		Vector3(0.15, 0, 0))
	# Козырёк лба и глаза-щели под ним
	PropFactory.box(root, Vector3(0.26, 0.06, 0.12), Vector3(0, 2.42, -0.2), dark,
		false, Vector3(0.5, 0, 0))
	for side in [-1.0, 1.0]:
		PropFactory.box(root, Vector3(0.115, 0.08, 0.1),
			Vector3(side * 0.068, 2.36, -0.15), dark, false, Vector3(0.1, side * 0.2, 0))
		PropFactory.box(root, Vector3(0.08, 0.022, 0.04),
			Vector3(side * 0.066, 2.35, -0.2), eye, false, Vector3(0.1, side * 0.28, 0))
	# Челюсть отвалилась вниз: пасть светится между зубами
	PropFactory.box(root, Vector3(0.17, 0.08, 0.2), Vector3(0, 2.2, -0.15), dark,
		false, Vector3(0.5, 0, 0))
	PropFactory.box(root, Vector3(0.12, 0.05, 0.08), Vector3(0, 2.24, -0.215), mouth,
		false, Vector3(0.5, 0, 0))
	for side in [-1.0, 1.0]:
		for i in 2:
			PropFactory.taper(root, 0.013, 0.002, 0.045,
				Vector3(side * 0.045 + (i - 0.5) * 0.04, 2.27, -0.235), dark,
				Vector3(PI + 0.5, 0, 0))
			PropFactory.taper(root, 0.012, 0.002, 0.04,
				Vector3(side * 0.045 + (i - 0.5) * 0.04, 2.21, -0.225), dark,
				Vector3(0.5, 0, 0))


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
