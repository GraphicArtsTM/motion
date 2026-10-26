extends RefCounted

# PropFactory: палитра и примитивы всего реквизита игры. Модели живут рядом:
# prop_entity.gd (сущность), prop_locker.gd (шкаф), prop_exit_door.gd (дверь
# выхода), prop_items.gd (баночка, предохранитель), prop_viewmodel.gd (руки
# игрока). Поведение (зоны, свет, скрипты) остаётся у владельцев.

static var _cache := {}


static func material_named(name: String) -> StandardMaterial3D:
	if _cache.has(name):
		return _cache[name]
	var mat := StandardMaterial3D.new()
	match name:
		"olive":
			mat.albedo_color = Color(0.23, 0.22, 0.18)
			mat.roughness = 0.7
			mat.metallic = 0.4
		"door_gray":
			mat.albedo_color = Color(0.32, 0.3, 0.24)
			mat.roughness = 0.6
			mat.metallic = 0.4
		"trim_dark":
			mat.albedo_color = Color(0.09, 0.08, 0.07)
			mat.roughness = 0.9
		"frame_dark":
			mat.albedo_color = Color(0.12, 0.11, 0.1)
			mat.roughness = 0.8
		"metal_dark":
			mat.albedo_color = Color(0.17, 0.17, 0.18)
			mat.roughness = 0.45
			mat.metallic = 0.6
		"rust":
			mat.albedo_color = Color(0.26, 0.14, 0.08)
			mat.roughness = 0.95
			mat.metallic = 0.15
		"hazard":
			mat.albedo_color = Color(0.52, 0.4, 0.07)
			mat.roughness = 0.8
		"glass_dark":
			mat.albedo_color = Color(0.04, 0.05, 0.05)
			mat.roughness = 0.22
			mat.metallic = 0.35
		"brass":
			# Петли, ручки, номерок — единственный тёплый металл в лабиринте
			mat.albedo_color = Color(0.4, 0.32, 0.15)
			mat.roughness = 0.45
			mat.metallic = 0.8
		"paper":
			# Этикетка банки: бумага не блестит и слабо светится в темноте
			mat.albedo_color = Color(0.56, 0.52, 0.4)
			mat.roughness = 0.95
			mat.emission_enabled = true
			mat.emission = Color(0.42, 0.39, 0.3)
			mat.emission_energy_multiplier = 0.1
		"entity_dark":
			mat.albedo_color = Color(0.035, 0.033, 0.03)
			mat.roughness = 0.85
		"entity_eye":
			mat.albedo_color = Color(0.9, 0.75, 0.5)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.72, 0.42)
			mat.emission_energy_multiplier = 1.4
		"can_metal":
			mat.albedo_color = Color(0.55, 0.56, 0.5)
			mat.roughness = 0.35
			mat.metallic = 0.7
		# Руки игрока (prop_viewmodel): свет в лабиринте тусклый, поэтому
		# у рукава и кожи слабое своё свечение — руки не тонут в черноте
		"sleeve":
			mat.albedo_color = Color(0.22, 0.21, 0.18)
			mat.roughness = 0.85
			mat.emission_enabled = true
			mat.emission = Color(0.19, 0.18, 0.15)
			mat.emission_energy_multiplier = 0.45
		"skin":
			mat.albedo_color = Color(0.5, 0.39, 0.32)
			mat.roughness = 0.75
			mat.emission_enabled = true
			mat.emission = Color(0.4, 0.32, 0.26)
			mat.emission_energy_multiplier = 0.15
		# Банка в руке: у снаряда металл бликует, в темноте же он просто чёрный
		"view_can":
			mat.albedo_color = Color(0.52, 0.52, 0.46)
			mat.roughness = 0.5
			mat.metallic = 0.2
			mat.emission_enabled = true
			mat.emission = Color(0.4, 0.4, 0.35)
			mat.emission_energy_multiplier = 0.1
	_cache[name] = mat
	return mat


# Свечение «на вырост»: свой материал на каждый объект, чтобы его
# можно было гасить и разжигать (дверь выхода, предохранители)
static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


# --- примитивы ---
# Всё, что ниже, — один и тот же узел с мешем: отличается только форма.
# Все модели игры собираются из этих пяти форм, ни одной внешней.

static func _place(parent: Node3D, shape: Mesh, pos: Vector3, mat: Material,
		rot: Vector3) -> MeshInstance3D:
	shape.material = mat
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = shape
	mesh_instance.position = pos
	mesh_instance.rotation = rot
	parent.add_child(mesh_instance)
	return mesh_instance


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		solid: bool = false, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var mesh_instance := _place(parent, shape, pos, mat, rot)
	if solid:
		var body := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		var shape_box := BoxShape3D.new()
		shape_box.size = size
		shape_node.shape = shape_box
		shape_node.position = pos
		shape_node.rotation = rot
		body.add_child(shape_node)
		parent.add_child(body)
	return mesh_instance


# Усечённый конус; при bottom == top это цилиндр, при top == 0 конус.
# Раструбы, зубцы, шипы, юбки, ножки — всё это он
static func taper(parent: Node3D, bottom: float, top: float, height: float,
		pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	return _place(parent, shape, pos, mat, rot)


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return taper(parent, radius, radius, height, pos, mat, rot)


# Капсула: конечности, пальцы, стеклянный бочонок. Коробка вблизи
# читается как обрезок, капсула — как живая кость или палец
static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var shape := CapsuleMesh.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	return _place(parent, shape, pos, mat, rot)


static func sphere(parent: Node3D, radius: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	return _place(parent, shape, pos, mat, Vector3.ZERO)


# Тор: кольцо в плоскости XZ. Обручи (рёбра), ободы (крышка банки),
# штурвал, петли — везде, где нужна скруглённая деталь
static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3,
		mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = inner
	shape.outer_radius = outer
	return _place(parent, shape, pos, mat, rot)


# Палка между двумя точками: рукав от плеча к кулаку. Подбирать углы
# Эйлера вручную тут бессмысленно, а так модель читается по координатам
static func rod(parent: Node3D, radius: float, from: Vector3, to: Vector3,
		mat: Material) -> MeshInstance3D:
	var center := (from + to) * 0.5
	var mesh_instance := cylinder(parent, radius, from.distance_to(to), center, mat)
	mesh_instance.look_at_from_position(center, to, Vector3.UP)
	# Цилиндр смотрит по +Y, а look_at наводит -Z: доворачиваем на четверть
	mesh_instance.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	return mesh_instance
