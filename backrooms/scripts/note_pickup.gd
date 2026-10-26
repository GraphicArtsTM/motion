extends Node3D

# NotePickup: сложенный листок из блокнота на полу — в линейку, исписан
# от руки. Светлее мусорной бумаги вокруг (decor_horror.gd), чтобы его
# выхватывал фонарь. Берётся на F: текст открывает note_view.gd, учёт —
# note_spawner.gd по сигналу read.

const PropFactory = preload("res://scripts/prop_factory.gd")

signal read

const PICK_RANGE: float = 1.7
const SHEET := Vector2(0.21, 0.27)
# Лист сложен пополам и чуть приоткрыт: половинки под углом к полу
const FOLD: float = 0.16

static var _texture: Texture2D = null

var hud = null
var player_inside: bool = false


func _ready() -> void:
	add_child(PropFactory.cached_mesh("note", _make_mesh))
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICK_RANGE
	shape.shape = sphere
	shape.position.y = 0.5
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _unhandled_input(event: InputEvent) -> void:
	if not player_inside or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	read.emit()
	queue_free()


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_inside = true
	if hud and hud.has_method("show_hint"):
		hud.show_hint("Нажми F — прочитать записку", 2.5)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_inside = false


# Две половинки листа от линии сгиба, каждая чуть приподнята краем
static func _make_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = SHEET.y * 0.5
	var w: float = SHEET.x * 0.5
	for side in [-1.0, 1.0]:
		var edge := Vector3(0.0, sin(FOLD) * half, side * cos(FOLD) * half)
		var n: Vector3 = Vector3(0, cos(FOLD), -side * sin(FOLD)).normalized()
		var v0: float = 0.5
		var v1: float = 0.5 + side * 0.5
		var quad: Array = [[Vector3(-w, 0.004, 0), Vector2(0, v0)], [Vector3(w, 0.004, 0), Vector2(1, v0)],
			[Vector3(w, 0.004, 0) + edge, Vector2(1, v1)], [Vector3(-w, 0.004, 0) + edge, Vector2(0, v1)]]
		# Лицевая сторона — вверх (в Godot лицо по часовой стрелке)
		var order: Array = [0, 2, 1, 0, 3, 2] if side < 0.0 else [0, 1, 2, 0, 2, 3]
		for i in order:
			st.set_normal(n)
			st.set_uv(quad[i][1])
			st.add_vertex(quad[i][0])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture()
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Материал — на меше: кэш PropFactory делит меш, а не узел
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Note"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# Лист в линейку: голубые строки, красное поле, строчки «почерка» —
# рваные тёмные штрихи. Рисуется раз на всю игру
static func texture() -> Texture2D:
	if _texture != null:
		return _texture
	var img := Image.create(128, 160, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4111
	img.fill(Color(0.86, 0.84, 0.76))
	for y in range(18, 160, 9):
		for x in 128:
			img.set_pixel(x, y, Color(0.6, 0.68, 0.78))
		var length: int = rng.randi_range(60, 112) if y < 140 else 40
		var x0: int = 20
		while x0 < length:
			var word: int = rng.randi_range(4, 14)
			for x in range(x0, mini(x0 + word, 126)):
				var lift: int = int(round(sin(x * 1.7 + y) * 1.5))
				img.set_pixel(x, y - 2 + lift, Color(0.12, 0.12, 0.16))
				img.set_pixel(x, y - 3 + lift, Color(0.2, 0.2, 0.25))
			x0 += word + rng.randi_range(3, 6)
	for y in 160:
		img.set_pixel(14, y, Color(0.78, 0.45, 0.42))
	img.generate_mipmaps()
	_texture = ImageTexture.create_from_image(img)
	return _texture
