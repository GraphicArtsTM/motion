extends RefCounted

# PropCamp: лагерь пропавшего разведчика в тупике. Спальник вдоль глухой
# стены со скатанной подушкой, рюкзак с пенкой, походный фонарь, пустые
# банки на боку — всё одним мешем из кэша. Заначка (три банки пирамидкой)
# — отдельный меш: её забирают (camp.gd). Локально +Z смотрит в проход,
# начало координат — центр клетки 4×4 м (стены — в 1.8 м от центра).

const MeshKit = preload("res://scripts/mesh_kit.gd")
const PropFactory = preload("res://scripts/prop_factory.gd")
const PropItems = preload("res://scripts/prop_items.gd")

const LANTERN_POS := Vector3(0.55, 0.0, -0.45)
const STASH_POS := Vector3(1.05, 0.0, -0.75)
# Свет фонаря — над стеклом
const FLAME_POS := LANTERN_POS + Vector3(0.0, 0.13, 0.0)
# Где листок записки, если в чанке есть записка (note_spawner.gd)
const NOTE_POS := Vector3(-0.15, 0.0, -0.35)


static func camp() -> MeshInstance3D:
	return PropFactory.cached_mesh("camp", _camp)


static func stash() -> MeshInstance3D:
	return PropFactory.cached_mesh("camp_stash", func() -> MeshInstance3D:
		var kit := MeshKit.new()
		var metal := PropFactory.material_named("can_metal")
		var label := PropFactory.material_named("can_label")
		for xz in [Vector2(-0.04, 0.0), Vector2(0.04, 0.0), Vector2(0.0, 0.0)]:
			var y: float = 0.0 if xz != Vector2.ZERO else PropItems.CAN_HEIGHT
			PropItems.can_mesh(kit, Transform3D(Basis(), Vector3(xz.x, y, xz.y)), metal, label)
		return kit.build("Stash"))


static func _camp() -> MeshInstance3D:
	var kit := MeshKit.new()
	var bag := PropFactory.material_named("camp_bag")
	var pack := PropFactory.material_named("camp_pack")
	var foam := PropFactory.material_named("camp_mat")
	var steel := PropFactory.material_named("steel")
	var rubber := PropFactory.material_named("rubber")
	# Спальник: длинный мягкий короб вдоль задней стены, капюшон — подушка
	kit.box(bag, Vector3(1.9, 0.13, 0.78), Transform3D(Basis(Vector3.UP, 0.04), Vector3(-0.2, 0.065, -1.3)), 0.05)
	kit.ellipsoid(bag, Vector3(0.16, 0.09, 0.3), Transform3D(Basis(), Vector3(-1.08, 0.13, -1.3)))
	# Откинутый край: клин поверх, как будто вылез и ушёл
	kit.box(bag, Vector3(0.7, 0.05, 0.8), Transform3D(Basis(Vector3.FORWARD, 0.12), Vector3(0.45, 0.15, -1.28)), 0.02)
	# Рюкзак у стены и скатанная пенка сверху
	var pack_xf := Transform3D(Basis(Vector3.UP, -0.3).rotated(Vector3.RIGHT, -0.12), Vector3(1.25, 0.27, -1.35))
	kit.box(pack, Vector3(0.36, 0.52, 0.24), pack_xf, 0.05)
	kit.box(pack, Vector3(0.28, 0.2, 0.08), pack_xf * Transform3D(Basis(), Vector3(0, -0.08, 0.15)), 0.03)
	kit.box(rubber, Vector3(0.04, 0.46, 0.02), pack_xf * Transform3D(Basis(), Vector3(-0.1, 0.0, -0.13)), 0.005)
	kit.box(rubber, Vector3(0.04, 0.46, 0.02), pack_xf * Transform3D(Basis(), Vector3(0.1, 0.0, -0.13)), 0.005)
	kit.lathe(foam, _cylinder(0.075, 0.5), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(1.0, 0.62, -1.35)), 14)
	# Фонарь: основание, колба, крышка с дужкой
	var lx := Transform3D(Basis(), LANTERN_POS)
	kit.lathe(steel, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.065, 0.0), Vector2(0.07, 0.01),
		Vector2(0.07, 0.05), Vector2(0.05, 0.06), Vector2(0.0, 0.06)]), lx, 16)
	kit.lathe(steel, PackedVector2Array([Vector2(0.0, 0.19), Vector2(0.05, 0.19), Vector2(0.06, 0.2),
		Vector2(0.03, 0.235), Vector2(0.0, 0.235)]), lx, 16)
	for a in 3:
		var ang: float = TAU * a / 3.0
		kit.box(steel, Vector3(0.008, 0.13, 0.008), lx * Transform3D(Basis(), Vector3(cos(ang) * 0.052, 0.125, sin(ang) * 0.052)), 0.002)
	kit.torus(steel, 0.05, 0.004, lx * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.27, 0)), 14, 4)
	# Пустые банки: две на боку, одна стоит
	var metal := PropFactory.material_named("can_metal")
	var label := PropFactory.material_named("can_label")
	PropItems.can_mesh(kit, Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, 0.7), Vector3(0.15, 0.034, -0.55)), metal, label)
	PropItems.can_mesh(kit, Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, 2.3), Vector3(-0.5, 0.034, -0.2)), metal, label)
	PropItems.can_mesh(kit, Transform3D(Basis(), Vector3(0.8, 0.0, -0.3)), metal, label)
	return kit.build("Camp")


# Колба фонаря: светится сама, свет даёт camp.gd
static func glass() -> MeshInstance3D:
	return PropFactory.cached_mesh("camp_glass", func() -> MeshInstance3D:
		var kit := MeshKit.new()
		kit.lathe(PropFactory.glow_material(Color(1.0, 0.62, 0.28), 2.2), _cylinder(0.045, 0.13), Transform3D(Basis(), Vector3(0, 0.06, 0)), 16)
		return kit.build("LanternGlass", false))


static func _cylinder(r: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0.0, 0.0), Vector2(r, 0.0), Vector2(r, h), Vector2(0.0, h)])
