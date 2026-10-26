extends RefCounted

# MeshKit: сборщик процедурной геометрии реквизита. Вместо россыпи
# BoxMesh/SphereMesh (по узлу и draw call на деталь, по 4 тыс. треугольников
# на шарик) модель копится в одном наборе SurfaceTool — по одному на
# материал — и выходит одним MeshInstance3D. Формы: короб со скосами
# (кромки ловят свет), тело вращения по профилю, трубка по точкам
# (кости, пальцы, провода), эллипсоид. Нормали и UV свои, касательные
# считает SurfaceTool — на них ложатся процедурные карты нормалей. Лицевая
# грань в Godot — по часовой стрелке: _tri разворачивает её по нормали.

var tools: Dictionary = {}
var order: Array = []


func _tool(mat: Material) -> SurfaceTool:
	if not tools.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[mat] = st
		order.append(mat)
	return tools[mat]


func _tri(st: SurfaceTool, p: Array, n: Array, uv: Array) -> void:
	var face: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var order3: Array = [0, 2, 1] if face.dot(n[0] + n[1] + n[2]) > 0.0 else [0, 1, 2]
	for i in order3:
		st.set_normal(n[i])
		st.set_uv(uv[i])
		st.add_vertex(p[i])


func _quad(st: SurfaceTool, xf: Transform3D, p: Array, n: Array, uv: Array) -> void:
	var nb: Basis = xf.basis.inverse().transposed()
	var wp: Array = []; var wn: Array = []
	for i in 4:
		wp.append(xf * (p[i] as Vector3))
		wn.append((nb * (n[i] as Vector3)).normalized())
	_tri(st, [wp[0], wp[1], wp[2]], [wn[0], wn[1], wn[2]], [uv[0], uv[1], uv[2]])
	_tri(st, [wp[0], wp[2], wp[3]], [wn[0], wn[2], wn[3]], [uv[0], uv[2], uv[3]])


# Короб со скосом: на каждой грани сетка 3×3, крайние полосы загибаются
# на кромку. Плоскость остаётся плоской, а ребро — мягкий скос в свет
func box(mat: Material, size: Vector3, xf: Transform3D, bevel: float = 0.01) -> void:
	var st := _tool(mat)
	var h: Vector3 = size * 0.5
	var b: float = clampf(bevel, 0.0005, minf(h.x, minf(h.y, h.z)) * 0.9)
	var inner: Vector3 = h - Vector3(b, b, b)
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var u_ax: int = (axis + 1) % 3
			var v_ax: int = (axis + 2) % 3
			var us: Array = [-h[u_ax], -inner[u_ax], inner[u_ax], h[u_ax]]
			var vs: Array = [-h[v_ax], -inner[v_ax], inner[v_ax], h[v_ax]]
			for i in 3:
				for j in 3:
					var p: Array = []; var n: Array = []; var uv: Array = []
					for c in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
						var raw := Vector3.ZERO
						raw[axis] = h[axis] * sgn
						raw[u_ax] = us[c.x]
						raw[v_ax] = vs[c.y]
						var core: Vector3 = raw.clamp(-inner, inner)
						var dir: Vector3 = (raw - core).normalized()
						p.append(core + dir * b)
						n.append(dir)
						uv.append(Vector2(raw[u_ax], raw[v_ax]))
					_quad(st, xf, p, n, uv)


# Тело вращения: профиль Vector2(радиус, высота) от низа к верху по внешней
# стороне. Излом профиля острее 60° даёт жёсткую кромку, мягче — гладкую
func lathe(mat: Material, profile: PackedVector2Array, xf: Transform3D,
		segments: int = 20) -> void:
	var st := _tool(mat)
	var count: int = profile.size()
	var seg_n: Array = []
	for i in count - 1:
		var d: Vector2 = profile[i + 1] - profile[i]
		seg_n.append(Vector2(d.y, -d.x).normalized())
	var length: float = 0.0
	for i in count - 1:
		var n0: Vector2 = seg_n[i]
		var n1: Vector2 = seg_n[i]
		if i > 0 and n0.dot(seg_n[i - 1]) > 0.5:
			n0 = (n0 + seg_n[i - 1]).normalized()
		if i < count - 2 and n1.dot(seg_n[i + 1]) > 0.5:
			n1 = (n1 + seg_n[i + 1]).normalized()
		var seg_len: float = profile[i].distance_to(profile[i + 1])
		for s in segments:
			var a0: float = TAU * s / segments
			var a1: float = TAU * (s + 1) / segments
			var p: Array = [_rev(profile[i], a0), _rev(profile[i], a1),
				_rev(profile[i + 1], a1), _rev(profile[i + 1], a0)]
			var n: Array = [_rev(n0, a0), _rev(n0, a1), _rev(n1, a1), _rev(n1, a0)]
			var uv: Array = [Vector2(float(s) / segments, length),
				Vector2(float(s + 1) / segments, length),
				Vector2(float(s + 1) / segments, length + seg_len),
				Vector2(float(s) / segments, length + seg_len)]
			_quad(st, xf, p, n, uv)
		length += seg_len


func _rev(p: Vector2, a: float) -> Vector3:
	return Vector3(p.x * cos(a), p.y, p.x * sin(a))


# Эллипсоид: полукруг вращения, растянутый базисом xf
func ellipsoid(mat: Material, radii: Vector3, xf: Transform3D, rings: int = 8,
		segments: int = 14) -> void:
	var profile := PackedVector2Array()
	for i in rings + 1:
		var a: float = -PI * 0.5 + PI * i / rings
		profile.append(Vector2(cos(a), sin(a)))
	lathe(mat, profile, xf * Transform3D(Basis.from_scale(radii), Vector3.ZERO), segments)


# Тор в плоскости XZ: кольца, ободы, штурвал
func torus(mat: Material, ring_r: float, tube_r: float, xf: Transform3D,
		segments: int = 20, sides: int = 8) -> void:
	var profile := PackedVector2Array()
	for i in sides + 1:
		var a: float = -PI * 0.5 + TAU * i / sides
		profile.append(Vector2(ring_r + tube_r * cos(a), tube_r * sin(a)))
	lathe(mat, profile, xf, segments)


# Трубка по точкам с радиусом в каждой: кость, палец, рукав (сгладить
# сустав дугой — mesh_curve.gd). Рамка несётся
# параллельным переносом — трубка не перекручивается на изгибах. Концы
# скруглены полусферой (cap), как сустав или кончик пальца
func tube(mat: Material, points: PackedVector3Array, radii: PackedFloat32Array,
		xf: Transform3D = Transform3D.IDENTITY, sides: int = 8, cap: bool = true) -> void:
	var st := _tool(mat)
	var pts: Array = []; var rad: Array = []; var tilt: Array = []
	var count: int = points.size()
	var t_first: Vector3 = (points[1] - points[0]).normalized()
	var t_last: Vector3 = (points[count - 1] - points[count - 2]).normalized()
	if cap:
		for k in [1.4, 1.0, 0.5]:
			pts.append(points[0] - t_first * radii[0] * sin(k))
			rad.append(radii[0] * cos(k))
			tilt.append(-k)
	for i in count:
		pts.append(points[i])
		rad.append(radii[i])
		tilt.append(0.0)
	if cap:
		for k in [0.5, 1.0, 1.4]:
			pts.append(points[count - 1] + t_last * radii[count - 1] * sin(k))
			rad.append(radii[count - 1] * cos(k))
			tilt.append(k)
	var frames: Array = _frames(pts)
	for i in pts.size() - 1:
		for s in sides:
			var p: Array = []; var n: Array = []; var uv: Array = []
			for c in [Vector2i(i, s), Vector2i(i, s + 1), Vector2i(i + 1, s + 1), Vector2i(i + 1, s)]:
				var a: float = TAU * c.y / sides
				var f: Array = frames[c.x]
				var radial: Vector3 = (f[1] as Vector3) * cos(a) + (f[2] as Vector3) * sin(a)
				p.append((pts[c.x] as Vector3) + radial * float(rad[c.x]))
				var k: float = tilt[c.x]
				n.append((radial * cos(k) + (f[0] as Vector3) * sin(k)).normalized())
				uv.append(Vector2(float(c.y) / sides, float(c.x) * 0.25))
			_quad(st, xf, p, n, uv)


func _frames(pts: Array) -> Array:
	var out: Array = []
	var prev_n := Vector3.ZERO
	for i in pts.size():
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var t: Vector3 = (b - a).normalized() if b != a else Vector3.UP
		var n: Vector3
		if prev_n == Vector3.ZERO:
			n = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			n = (prev_n - t * prev_n.dot(t)).normalized()
		prev_n = n
		out.append([t, n, t.cross(n).normalized()])
	return out


func build(name: String, shadows: bool = true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for mat in order:
		var st: SurfaceTool = tools[mat]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
