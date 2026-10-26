extends RefCounted

# PropExitDoor: дверь выхода — тяжёлая гермодверь с косяком, штурвалом,
# окном, отбойкой и пультом на трёх лампах. Собирается из палитры и
# примитивов prop_factory. Пока питания нет, полотно только тлеет — дверь
# ищут на слух. Поведение (питание, подсказки, победа) — exit_door.gd.

const PropFactory = preload("res://scripts/prop_factory.gd")


# Возвращает узел, материал полотна (его гасит и разжигает exit_door.gd)
# и три материала ламп — по одной на предохранитель
static func build_exit_door() -> Dictionary:
	var root := Node3D.new()
	root.name = "ExitDoor"
	var frame := PropFactory.material_named("frame_dark")
	var steel := PropFactory.material_named("metal_dark")
	var brass := PropFactory.material_named("brass")
	var hazard_mat := PropFactory.material_named("hazard")
	var trim := PropFactory.material_named("trim_dark")
	var glass := PropFactory.material_named("glass_dark")
	var glow := PropFactory.glow_material(Color(0.35, 1.0, 0.6), 0.05)
	# Альбедо полотна почти чёрное: без питания дверь не светит, а тлеет
	glow.albedo_color = Color(0.06, 0.16, 0.1)

	# Косяк: стойки с болтами, отбойкой и перекладиной
	for side in [-1.0, 1.0]:
		PropFactory.box(root, Vector3(0.25, 2.4, 0.32),
			Vector3(side * 0.85, 1.2, 0), frame, true)
		for i in 5:
			PropFactory.sphere(root, 0.035, Vector3(side * 0.85, 0.35 + i * 0.42, 0.18), steel)
			PropFactory.box(root, Vector3(0.1, 0.1, 0.05),
				Vector3(side * 0.85, 0.35 + i * 0.42, 0.14), frame)
		# Полосатая отбойка у порога
		for j in 4:
			PropFactory.box(root, Vector3(0.3, 0.1, 0.04),
				Vector3(side * 0.85, 0.12 + j * 0.13, 0.17),
				hazard_mat if j % 2 == 0 else trim)
	PropFactory.box(root, Vector3(1.95, 0.25, 0.32), Vector3(0, 2.5, 0), frame)
	# Порог с насечкой (только вид: коллизии тут быть не должно)
	PropFactory.box(root, Vector3(1.9, 0.08, 0.5), Vector3(0, 0.04, 0), frame)
	for i in 4:
		PropFactory.box(root, Vector3(1.7, 0.02, 0.05),
			Vector3(0, 0.085, -0.15 + i * 0.1), steel)
	PropFactory.box(root, Vector3(1.5, 2.3, 0.04), Vector3(0, 1.1, -0.08), trim)

	# Полотно: светящаяся панель, наличники по бокам, отбойная планка снизу
	PropFactory.box(root, Vector3(1.4, 2.2, 0.12), Vector3(0, 1.1, 0), glow, true)
	for side in [-1.0, 1.0]:
		PropFactory.box(root, Vector3(0.07, 2.2, 0.05),
			Vector3(side * 0.62, 1.1, 0.12), glow)
	PropFactory.box(root, Vector3(1.3, 0.22, 0.05), Vector3(0, 0.16, 0.09), steel)
	for i in 3:
		PropFactory.box(root, Vector3(0.34, 0.1, 0.04),
			Vector3(-0.38 + i * 0.38, 0.16, 0.12), hazard_mat, false,
			Vector3(0, 0, -0.6 if i % 2 == 0 else 0.6))

	# Петли: по две с каждой стороны полотна
	for side in [-1.0, 1.0]:
		for i in 2:
			PropFactory.box(root, Vector3(0.1, 0.26, 0.07),
				Vector3(side * 0.66, 0.6 + i * 1.2, 0.11), steel)
			PropFactory.cylinder(root, 0.035, 0.3,
				Vector3(side * 0.66, 0.6 + i * 1.2, 0.15), brass)

	# Окно с тёмным стеклом — за ним ничего не видно, и это хуже всего
	PropFactory.box(root, Vector3(0.5, 0.46, 0.06), Vector3(0, 1.82, 0.07), glass)
	PropFactory.box(root, Vector3(0.58, 0.06, 0.08), Vector3(0, 1.6, 0.08), steel)
	PropFactory.box(root, Vector3(0.58, 0.06, 0.08), Vector3(0, 2.04, 0.08), steel)
	PropFactory.box(root, Vector3(0.05, 0.5, 0.08), Vector3(0, 1.82, 0.08), steel)

	# Штурвал: обод со спицами на валу
	PropFactory.cylinder(root, 0.035, 0.2, Vector3(0, 1.1, 0.12), steel,
		Vector3(PI * 0.5, 0, 0))
	PropFactory.torus(root, 0.13, 0.19, Vector3(0, 1.1, 0.16), steel,
		Vector3(PI * 0.5, 0, 0))
	for i in 4:
		PropFactory.box(root, Vector3(0.34, 0.032, 0.035), Vector3(0, 1.1, 0.16),
			steel, false, Vector3(0, 0, i * PI / 4.0))
	PropFactory.cylinder(root, 0.06, 0.1, Vector3(0, 1.1, 0.17), trim,
		Vector3(PI * 0.5, 0, 0))

	# Доводчик: тяжёлое полотно должно закрываться само
	PropFactory.box(root, Vector3(0.14, 0.1, 0.14), Vector3(0.5, 2.36, 0.1), steel)
	PropFactory.cylinder(root, 0.045, 0.34, Vector3(0.52, 2.24, 0.16), steel,
		Vector3(0.35, 0, 0.35))
	PropFactory.cylinder(root, 0.018, 0.26, Vector3(0.34, 2.08, 0.14), steel,
		Vector3(0.35, 0, 0.35))

	# Табличка над окном: тлеет даже без питания
	PropFactory.box(root, Vector3(0.46, 0.14, 0.03), Vector3(0, 2.22, 0.08), brass)
	var sign := PropFactory.glow_material(Color(0.9, 0.45, 0.15), 0.3)
	sign.albedo_color = Color(0.22, 0.1, 0.04)
	PropFactory.box(root, Vector3(0.36, 0.06, 0.02), Vector3(0, 2.22, 0.1), sign)

	# Пульт на правой стойке с тремя лампами — по одной на предохранитель
	PropFactory.box(root, Vector3(0.3, 0.52, 0.12), Vector3(0.85, 1.95, 0.19), steel)
	var lamps: Array = []
	for i in 3:
		var lamp := PropFactory.glow_material(Color(0.4, 1.0, 0.55), 0.04)
		lamp.albedo_color = Color(0.06, 0.16, 0.09)
		PropFactory.torus(root, 0.035, 0.055, Vector3(0.85, 1.74 + i * 0.14, 0.26),
			steel, Vector3(PI * 0.5, 0, 0))
		PropFactory.box(root, Vector3(0.09, 0.09, 0.03),
			Vector3(0.85, 1.74 + i * 0.14, 0.26), lamp)
		lamps.append(lamp)
	for i in 3:
		PropFactory.box(root, Vector3(0.035, 0.5, 0.035),
			Vector3(0.74 + i * 0.08, 2.3, 0.17), trim, false, Vector3(0, 0, -0.06))
	PropFactory.cylinder(root, 0.03, 0.44, Vector3(0.98, 2.5, 0.19), steel)
	return {"root": root, "glow": glow, "lamps": lamps}
