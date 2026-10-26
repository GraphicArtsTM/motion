extends RefCounted

# PropWorld: мелкий реквизит стен и пола для decor_horror.gd — упавшая
# плитка потолка с отколотым куском, вентрешётка с наклонными ламелями,
# розетка. Собираются один раз (кэш PropFactory.cached_mesh), у предмета
# на стене +Z смотрит из стены в клетку.

const MeshKit = preload("res://scripts/mesh_kit.gd")
const PropFactory = preload("res://scripts/prop_factory.gd")


static func fallen_tile() -> MeshInstance3D:
	var kit := MeshKit.new()
	var tile := PropFactory.material_named("ceiling_tile")
	kit.box(tile, Vector3(1.25, 0.016, 0.76), Transform3D.IDENTITY, 0.004)
	kit.box(tile, Vector3(0.32, 0.016, 0.22), Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.9, 0.0, 0.3)), 0.004)
	return kit.build("FallenTile")


static func vent() -> MeshInstance3D:
	var kit := MeshKit.new()
	var steel := PropFactory.material_named("steel")
	var dark := PropFactory.material_named("rubber")
	kit.box(dark, Vector3(0.5, 0.26, 0.01), Transform3D(Basis(), Vector3(0, 0, 0.004)), 0.001)
	kit.box(steel, Vector3(0.56, 0.32, 0.014), Transform3D(Basis(), Vector3(0, 0, 0.006)), 0.004)
	for i in 6:
		kit.box(steel, Vector3(0.48, 0.022, 0.006),
			Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0, -0.1 + i * 0.04, 0.016)), 0.002)
	return kit.build("Vent", false)


static func outlet() -> MeshInstance3D:
	var kit := MeshKit.new()
	var plastic := PropFactory.material_named("ceiling_tile")
	var dark := PropFactory.material_named("rubber")
	kit.box(plastic, Vector3(0.08, 0.12, 0.012), Transform3D(Basis(), Vector3(0, 0, 0.006)), 0.004)
	for s in [-1.0, 1.0]:
		kit.box(dark, Vector3(0.008, 0.016, 0.004), Transform3D(Basis(), Vector3(s * 0.012, 0.0, 0.013)), 0.001)
	return kit.build("Outlet", false)
