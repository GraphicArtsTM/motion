extends RefCounted

# PropExitDoor: дверь выхода — тяжёлая гермодверь в стальной раме. Полотно
# с выпуклыми филёнками и заклёпками, штурвал с ригелями, армированное окно
# с подсветкой, полосатая отбойка, петли-стволы. По кромке проёма идёт
# светодиодная полоса: без питания она едва тлеет, с каждым предохранителем
# разгорается (материал "glow" гасит и разжигает exit_door.gd). На правой
# стойке пульт с тремя лампами — по одной на предохранитель. Геометрия —
# mesh_kit.gd одним мешем на материал (было 79 узлов), фактура —
# prop_factory.gd. Поведение (питание, подсказки, победа) — exit_door.gd.

const PropFactory = preload("res://scripts/prop_factory.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


# Возвращает узел, материал полосы питания и три материала ламп пульта
static func build_exit_door() -> Dictionary:
	var root := Node3D.new()
	root.name = "ExitDoor"
	# Материалы питания свои на каждую дверь (их разжигает exit_door.gd), а
	# меш общий: дверь пересобирается при каждой загрузке её чанка
	var glow := PropFactory.glow_material(Color(0.35, 1.0, 0.6), 0.05)
	glow.albedo_color = Color(0.08, 0.2, 0.12)
	var lamps: Array = []
	for i in 3:
		var lamp := PropFactory.glow_material(Color(0.4, 1.0, 0.55), 0.04)
		lamp.albedo_color = Color(0.06, 0.16, 0.09)
		lamps.append(lamp)
	var mesh_instance: MeshInstance3D = PropFactory.cached_mesh("exit_door",
		func() -> MeshInstance3D: return _door_mesh(glow, lamps))
	_bind(mesh_instance, glow, lamps)
	root.add_child(mesh_instance)
	for side in [-1.0, 1.0]:
		PropFactory.solid_box(root, Vector3(0.22, 2.45, 0.36), Vector3(side * 0.86, 1.225, 0))
	PropFactory.solid_box(root, Vector3(1.5, 2.3, 0.12), Vector3(0, 1.17, 0))
	return {"root": root, "glow": glow, "lamps": lamps}


# Меш общий, а поверхности питания у каждой двери свои: подменяем материал
# на экземпляре (surface_override), глядя на материал в меше
static func _bind(mi: MeshInstance3D, glow: Material, lamps: Array) -> void:
	for s in mi.mesh.get_surface_count():
		var tag: String = str(mi.mesh.surface_get_material(s).get_meta("power", ""))
		if tag == "glow":
			mi.set_surface_override_material(s, glow)
		elif tag.begins_with("lamp"):
			mi.set_surface_override_material(s, lamps[int(tag.substr(4))])


static func _door_mesh(glow_src: Material, lamps_src: Array) -> MeshInstance3D:
	var kit := MeshKit.new()
	var glow: Material = glow_src.duplicate()
	glow.set_meta("power", "glow")
	var lamps: Array = []
	for i in 3:
		var lamp: Material = (lamps_src[i] as Material).duplicate()
		lamp.set_meta("power", "lamp%d" % i)
		lamps.append(lamp)
	var frame := PropFactory.material_named("frame_dark")
	var steel := PropFactory.material_named("steel")
	var paint := PropFactory.material_named("door_paint")
	_frame(kit, frame, steel, glow)
	_slab(kit, paint, steel, glow)
	_panel(kit, steel, frame, lamps)
	return kit.build("ExitDoorMesh")


# Рама: стойки на заклёпках, перекладина со знаком, порог, отбойка внизу
# стоек и светодиодная полоса по кромке проёма
static func _frame(kit: MeshKit, frame: Material, steel: Material, glow: Material) -> void:
	var hazard := PropFactory.material_named("hazard")
	for side in [-1.0, 1.0]:
		var x: float = side * 0.86
		kit.box(frame, Vector3(0.22, 2.45, 0.36), _at(Vector3(x, 1.225, 0)), 0.02)
		kit.box(steel, Vector3(0.05, 2.32, 0.38), _at(Vector3(side * 0.765, 1.16, 0)), 0.008)
		kit.box(hazard, Vector3(0.226, 0.42, 0.366), _at(Vector3(x, 0.21, 0)), 0.02)
		kit.box(glow, Vector3(0.012, 2.26, 0.02), _at(Vector3(side * 0.735, 1.16, 0.17)), 0.003)
		for i in 7:
			kit.ellipsoid(steel, Vector3(0.016, 0.016, 0.008),
				_at(Vector3(x + side * 0.06, 0.55 + i * 0.3, 0.181)), 3, 8)
	kit.box(frame, Vector3(1.94, 0.24, 0.36), _at(Vector3(0, 2.57, 0)), 0.02)
	kit.box(glow, Vector3(1.48, 0.012, 0.02), _at(Vector3(0, 2.33, 0.17)), 0.003)
	# Порог с рифлением
	kit.box(steel, Vector3(1.5, 0.05, 0.5), _at(Vector3(0, 0.025, 0)), 0.01)
	for i in 6:
		kit.box(steel, Vector3(1.4, 0.008, 0.02), _at(Vector3(0, 0.053, -0.18 + i * 0.07)), 0.003)
	# Световой знак над дверью: короб и стрелка на тлеющем стекле
	var sign := PropFactory.glow_material(Color(0.9, 0.45, 0.15), 0.3)
	sign.albedo_color = Color(0.22, 0.1, 0.04)
	kit.box(frame, Vector3(0.5, 0.17, 0.08), _at(Vector3(0, 2.57, 0.21)), 0.01)
	kit.box(sign, Vector3(0.44, 0.12, 0.01), _at(Vector3(0, 2.57, 0.25)), 0.002)
	var dark := PropFactory.material_named("rubber")
	kit.box(dark, Vector3(0.16, 0.025, 0.004), _at(Vector3(-0.02, 2.57, 0.256)), 0.001)
	for s in [-1.0, 1.0]:
		kit.box(dark, Vector3(0.06, 0.022, 0.004), _at(Vector3(0.07, 2.57 + s * 0.018, 0.257), Vector3(0, 0, -s * 0.75)), 0.001)


# Полотно: выпуклые филёнки, заклёпки по краю, окно, штурвал с ригелями,
# отбойная полоса и петли
static func _slab(kit: MeshKit, paint: Material, steel: Material, glow: Material) -> void:
	kit.box(paint, Vector3(1.46, 2.3, 0.12), _at(Vector3(0, 1.17, 0)), 0.02)
	kit.box(paint, Vector3(1.18, 0.86, 0.02), _at(Vector3(0, 0.62, 0.065)), 0.012)
	kit.box(paint, Vector3(1.18, 0.62, 0.02), _at(Vector3(0, 1.98, 0.065)), 0.012)
	for i in 12:
		var x: float = lerpf(-0.66, 0.66, float(i) / 11.0)
		for y in [0.1, 2.24]:
			kit.ellipsoid(steel, Vector3(0.013, 0.013, 0.007), _at(Vector3(x, y, 0.062)), 3, 8)
	kit.box(PropFactory.material_named("hazard"), Vector3(1.3, 0.14, 0.012), _at(Vector3(0, 0.12, 0.066)), 0.004)
	# Окно: рама, армированное стекло с сеткой, подсветка за стеклом
	var glass := PropFactory.material_named("glass_dark")
	kit.box(steel, Vector3(0.5, 0.4, 0.03), _at(Vector3(0, 1.98, 0.08)), 0.01)
	kit.box(glow, Vector3(0.4, 0.3, 0.004), _at(Vector3(0, 1.98, 0.07)), 0.001)
	kit.box(glass, Vector3(0.42, 0.32, 0.006), _at(Vector3(0, 1.98, 0.097)), 0.001)
	for i in 4:
		kit.box(steel, Vector3(0.0025, 0.32, 0.003), _at(Vector3(-0.15 + i * 0.1, 1.98, 0.101)), 0.0005)
		kit.box(steel, Vector3(0.42, 0.0025, 0.003), _at(Vector3(0, 1.86 + i * 0.08, 0.101)), 0.0005)
	# Штурвал: ступица, обод, четыре спицы; ригели к краям полотна
	var wheel := _at(Vector3(0, 1.17, 0.11), Vector3(PI * 0.5, 0, 0))
	kit.lathe(steel, PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.06, 0.05), Vector2(0.04, 0.07),
		Vector2(0.0, 0.07)]), wheel, 16)
	kit.torus(steel, 0.2, 0.018, wheel * _at(Vector3(0, 0.06, 0)), 28, 8)
	for i in 4:
		var a: float = i * PI * 0.5 + PI * 0.25
		kit.tube(steel, PackedVector3Array([Vector3(0, 1.17, 0.17),
			Vector3(cos(a) * 0.2, 1.17 + sin(a) * 0.2, 0.17)]), PackedFloat32Array([0.014, 0.012]),
			Transform3D.IDENTITY, 6, false)
	for side in [-1.0, 1.0]:
		kit.tube(steel, PackedVector3Array([Vector3(side * 0.07, 1.17, 0.085), Vector3(side * 0.68, 1.17, 0.085)]),
			PackedFloat32Array([0.022, 0.022]), Transform3D.IDENTITY, 8)
		for x in [0.3, 0.55]:
			kit.box(steel, Vector3(0.05, 0.07, 0.03), _at(Vector3(side * x, 1.17, 0.075)), 0.006)
	# Петли-стволы на левой кромке
	for y in [0.4, 1.17, 1.94]:
		kit.tube(steel, PackedVector3Array([Vector3(-0.745, y - 0.13, 0.08), Vector3(-0.745, y + 0.13, 0.08)]),
			PackedFloat32Array([0.035, 0.035]), Transform3D.IDENTITY, 10)


# Пульт на правой стойке: короб, три лампы в ободках, кабель в перекладину
static func _panel(kit: MeshKit, steel: Material, frame: Material, lamps: Array) -> void:
	kit.box(steel, Vector3(0.24, 0.5, 0.1), _at(Vector3(0.86, 1.6, 0.22)), 0.012)
	kit.box(frame, Vector3(0.2, 0.46, 0.01), _at(Vector3(0.86, 1.6, 0.272)), 0.004)
	for i in 3:
		var lamp: Material = lamps[i]
		var y: float = 1.46 + i * 0.14
		kit.torus(steel, 0.034, 0.008, _at(Vector3(0.86, y, 0.279), Vector3(PI * 0.5, 0, 0)), 14, 5)
		kit.ellipsoid(lamp, Vector3(0.028, 0.028, 0.014), _at(Vector3(0.86, y, 0.279)), 4, 10)
	kit.tube(steel, PackedVector3Array([Vector3(0.94, 1.85, 0.22), Vector3(0.94, 2.2, 0.22),
		Vector3(0.9, 2.42, 0.19)]), PackedFloat32Array([0.018, 0.018, 0.018]), Transform3D.IDENTITY, 6)
