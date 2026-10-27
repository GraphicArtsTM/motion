extends RefCounted

# PropFactory: палитра реквизита. Геометрия — в mesh_kit.gd, модели рядом:
# prop_entity.gd (сущность), prop_locker.gd (шкаф), prop_exit_door.gd (дверь
# выхода), prop_items.gd (банка, предохранитель), prop_viewmodel.gd (руки),
# prop_camp.gd (лагерь разведчика).
# Внешних текстур нет: фактуру (вмятины, потёртости, ржавчина, морщины,
# ткань) рисует шум движка, полосы и этикетку — код (prop_textures.gd).
# Всё кэшируется: текстура и материал создаются один раз на игру.

const PropTextures = preload("res://scripts/prop_textures.gd")

static var _cache := {}
static var _meshes := {}

# name: [albedo, roughness, metallic, рельеф (вид шума), сила рельефа,
#        пятна (вид шума), свечение]
const PALETTE := {
	"locker_paint": [Color(0.38, 0.4, 0.32), 0.62, 0.2, "dents", 0.25, "wear", 0.0],
	"locker_inner": [Color(0.05, 0.05, 0.045), 0.9, 0.0, "", 0.0, "", 0.0],
	"door_paint": [Color(0.3, 0.33, 0.3), 0.6, 0.3, "dents", 0.2, "wear", 0.0],
	"frame_dark": [Color(0.16, 0.155, 0.145), 0.75, 0.3, "dents", 0.15, "grime", 0.0],
	"steel": [Color(0.5, 0.5, 0.48), 0.42, 0.8, "scratch", 0.15, "grime", 0.0],
	"rust": [Color(0.3, 0.15, 0.07), 0.95, 0.1, "dents", 0.6, "grime", 0.0],
	"brass": [Color(0.55, 0.42, 0.2), 0.35, 0.9, "scratch", 0.25, "grime", 0.0],
	"rubber": [Color(0.04, 0.04, 0.04), 0.9, 0.0, "", 0.0, "", 0.0],
	"entity_skin": [Color(0.07, 0.06, 0.053), 0.78, 0.0, "wrinkle", 0.7, "grime", 0.0],
	"entity_bone": [Color(0.42, 0.37, 0.28), 0.6, 0.0, "dents", 0.4, "grime", 0.0],
	"entity_eye": [Color(0.9, 0.75, 0.5), 0.2, 0.0, "", 0.0, "", 1.4],
	"entity_mouth": [Color(0.14, 0.025, 0.02), 0.5, 0.0, "", 0.0, "", 0.15],
	"skin": [Color(0.55, 0.42, 0.34), 0.62, 0.0, "pores", 0.2, "", 0.1],
	"nail": [Color(0.66, 0.55, 0.48), 0.35, 0.0, "", 0.0, "", 0.15],
	"sleeve": [Color(0.2, 0.21, 0.2), 0.9, 0.0, "fabric", 0.6, "", 0.45],
	"can_metal": [Color(0.62, 0.63, 0.6), 0.28, 0.85, "dents", 0.15, "", 0.0],
	"ceramic": [Color(0.78, 0.76, 0.7), 0.3, 0.0, "", 0.0, "grime", 0.0],
	# Банка в руке: руки на своём слое, фонарь их не освещает — металл
	# слегка светится сам, иначе в темноте кулак держит пустоту
	"view_metal": [Color(0.62, 0.63, 0.6), 0.4, 0.3, "dents", 0.15, "", 0.12],
	# Мир: плинтус и наличники, упавшая плитка потолка, бумаги, решётки
	"baseboard": [Color(0.23, 0.19, 0.14), 0.55, 0.0, "dents", 0.15, "grime", 0.0],
	"ceiling_tile": [Color(0.78, 0.75, 0.66), 0.9, 0.0, "pores", 0.3, "grime", 0.0],
	"paper": [Color(0.74, 0.71, 0.62), 0.9, 0.0, "", 0.0, "grime", 0.0],
	# Лагерь разведчика (prop_camp.gd): спальник, рюкзак, пенка
	"camp_bag": [Color(0.3, 0.34, 0.2), 0.85, 0.0, "fabric", 0.5, "grime", 0.0],
	"camp_pack": [Color(0.42, 0.2, 0.08), 0.7, 0.0, "fabric", 0.4, "grime", 0.0],
	"camp_mat": [Color(0.16, 0.25, 0.38), 0.8, 0.0, "pores", 0.3, "", 0.0],
}

# Декали хоррора: [текстура формы (prop_textures), цвет, шероховатость]
const DECALS := {
	"blood": ["handprint", Color(0.2, 0.035, 0.025), 0.45],
	"drag": ["drag", Color(0.17, 0.04, 0.03), 0.5],
	"scratch": ["tally", Color(0.07, 0.06, 0.05), 0.9],
	"puddle": ["puddle", Color(0.02, 0.022, 0.02), 0.03],
}


static func material_named(name: String) -> StandardMaterial3D:
	if _cache.has(name):
		return _cache[name]
	var mat := StandardMaterial3D.new()
	if name == "can_label" or name == "view_label":
		mat.albedo_texture = PropTextures.label()
		mat.roughness = 0.8
		# Высота этикетки 78 мм, а v у тела вращения в метрах: растягиваем
		mat.uv1_scale = Vector3(1.0, 12.8, 1.0)
		if name == "view_label":
			mat.emission_enabled = true
			mat.emission_texture = mat.albedo_texture
			mat.emission_energy_multiplier = 0.12
	elif name == "hazard":
		mat.albedo_texture = PropTextures.stripes()
		mat.roughness = 0.75
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	elif DECALS.has(name):
		var d: Array = DECALS[name]
		mat.albedo_texture = PropTextures.decal(d[0])
		mat.albedo_color = d[1]
		mat.roughness = d[2]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if name == "puddle":
			mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			mat.metallic_specular = 0.9
	elif name == "glass_dark":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.05, 0.08, 0.08, 0.55)
		mat.roughness = 0.05
		mat.metallic = 0.3
	elif name == "fuse_glass":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.6, 0.95, 0.7, 0.28)
		mat.roughness = 0.05
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.8, 0.45)
		mat.emission_energy_multiplier = 0.4
	else:
		_apply(mat, PALETTE[name])
	if name == "entity_skin":
		# Силуэт держится на кромке: в темноте видна обводка, а не масса
		mat.rim_enabled = true
		mat.rim = 0.45
		mat.rim_tint = 0.4
	if name == "locker_inner":
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[name] = mat
	return mat


static func _apply(mat: StandardMaterial3D, p: Array) -> void:
	mat.albedo_color = p[0]
	mat.roughness = p[1]
	mat.metallic = p[2]
	if p[3] != "":
		mat.normal_enabled = true
		mat.normal_texture = PropTextures.noise(p[3], true)
		mat.normal_scale = p[4]
	if p[5] != "":
		# Пятна: светлее/темнее по шуму — и в цвете, и в шероховатости
		mat.albedo_texture = PropTextures.noise(p[5], false)
		mat.roughness_texture = mat.albedo_texture
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0) * (8.0 if p[3] in ["pores", "fabric"] else 2.0)
	if p[6] > 0.0:
		mat.emission_enabled = true
		mat.emission = (p[0] as Color) * 0.8
		mat.emission_energy_multiplier = p[6]
		if mat.albedo_texture:
			mat.emission_texture = mat.albedo_texture


# Свечение «на вырост»: свой материал на каждый объект, чтобы его
# можно было гасить и разжигать (дверь выхода, предохранители)
static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


# Одинаковые модели (шкафы, банки, предохранители) собираются один раз:
# сборка в GDScript стоит десятки миллисекунд, а меш можно делить между
# экземплярами. make возвращает MeshInstance3D первой сборки
static func cached_mesh(key: String, make: Callable) -> MeshInstance3D:
	if not _meshes.has(key):
		var built: MeshInstance3D = make.call()
		# Храним сам меш, не узел: узел первой сборки могут освободить
		_meshes[key] = [built.mesh, built.name, built.cast_shadow]
		return built
	var entry: Array = _meshes[key]
	var mi := MeshInstance3D.new()
	mi.mesh = entry[0]
	mi.name = entry[1]
	mi.cast_shadow = entry[2]
	return mi


# Невидимый твёрдый короб: коллизия отдельно от красивой геометрии
static func solid_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape_box := BoxShape3D.new()
	shape_box.size = size
	shape_node.shape = shape_box
	shape_node.position = pos
	body.add_child(shape_node)
	parent.add_child(body)
