extends RefCounted

# MeshCurve: кривые для трубок mesh_kit.gd. Сустав из двух отрезков
# читается как сломанная палка; дуга через те же точки — как кость
# или палец. Точки и радиусы сглаживаются согласованно: шаг кривой
# совпадает с шагом радиусов.

# Гладкая кривая через точки (Catmull-Rom): сустав сгибается дугой, а не углом
static func smooth(points: PackedVector3Array, steps: int = 3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in points.size() - 1:
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, points.size() - 1)]
		for s in steps:
			var t: float = float(s) / steps
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(points[points.size() - 1])
	return out


# Радиусы вдоль сглаженной кривой: линейно между заданными в суставах
static func spread(radii: PackedFloat32Array, steps: int = 3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in radii.size() - 1:
		for s in steps:
			out.append(lerpf(radii[i], radii[i + 1], float(s) / steps))
	out.append(radii[radii.size() - 1])
	return out
