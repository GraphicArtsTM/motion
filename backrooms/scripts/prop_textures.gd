extends RefCounted

# PropTextures: процедурные карты реквизита для palette в prop_factory.gd.
# Внешних файлов нет: шум движка (FastNoiseLite) становится картой
# нормалей (вмятины, царапины, морщины, поры, ткань) или серой картой
# пятен (потёртость, грязь); полосы «опасность» и этикетку рисует код.
# Каждая карта строится один раз на игру.

static var _tex := {}

# Вид шума: [тип, частота, октавы, контраст]. Рельеф — карта нормалей,
# пятна — серая карта в узком диапазоне (0.65–1.0), чтобы не пачкать цвет
const NOISE := {
	"dents": [FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 3, 1.0],
	"scratch": [FastNoiseLite.TYPE_CELLULAR, 0.05, 2, 1.0],
	"wrinkle": [FastNoiseLite.TYPE_CELLULAR, 0.03, 3, 1.0],
	"pores": [FastNoiseLite.TYPE_SIMPLEX, 0.25, 2, 1.0],
	"fabric": [FastNoiseLite.TYPE_VALUE, 0.35, 1, 1.0],
	"wear": [FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 5, 1.1],
	"grime": [FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.03, 4, 1.3],
}


static func noise(kind: String, normal: bool) -> Texture2D:
	var key: String = kind + ("_n" if normal else "_a")
	if _tex.has(key):
		return _tex[key]
	var spec: Array = NOISE[kind]
	var gen := FastNoiseLite.new()
	gen.noise_type = spec[0]
	gen.frequency = spec[1]
	gen.fractal_octaves = spec[2]
	gen.seed = kind.hash() & 0xFFFF
	# Рельефу нужна детальность, пятнам хватит 128 — их ещё перекладывать в GDScript
	var size: int = 256 if normal else 128
	var img: Image = gen.get_seamless_image(size, size)
	img.convert(Image.FORMAT_RGBA8)
	if normal:
		img.bump_map_to_normal_map(1.5)
	else:
		img = _remap(img, spec[3])
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


# Пятна в узком диапазоне 0.8–1.0: материал не превращается в камуфляж,
# тон задаёт палитра. contrast > 1 — пятна резче (потёртость краски)
static func _remap(img: Image, contrast: float) -> Image:
	img.convert(Image.FORMAT_L8)
	var data: PackedByteArray = img.get_data()
	for i in data.size():
		var v: float = clampf((data[i] / 255.0 - 0.5) * contrast + 0.5, 0.0, 1.0)
		data[i] = int((0.8 + 0.2 * v) * 255.0)
	var out := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_L8, data)
	out.convert(Image.FORMAT_RGBA8)
	return out


# Полосы «опасность»: жёлтый по чёрному под 45°, краска чуть потёрта
static func stripes() -> Texture2D:
	if _tex.has("stripes"):
		return _tex["stripes"]
	var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var yellow: bool = ((x + y) / 16) % 2 == 0
			img.set_pixel(x, y, Color(0.62, 0.48, 0.08) if yellow else Color(0.05, 0.05, 0.045))
	img.generate_mipmaps()
	_tex["stripes"] = ImageTexture.create_from_image(img)
	return _tex["stripes"]


# Этикетка банки без марки: выцветший кремовый фон, бордовая полоса
# и тонкие линии — читается как «консервы», а не как бренд
static func label() -> Texture2D:
	if _tex.has("label"):
		return _tex["label"]
	var img := Image.create(128, 64, true, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 128:
			var c := Color(0.72, 0.66, 0.5)
			if y > 22 and y < 42:
				c = Color(0.45, 0.12, 0.1)
			elif y == 18 or y == 46:
				c = Color(0.25, 0.2, 0.15)
			var fade: float = 0.9 + 0.1 * sin(x * 0.31 + y * 0.17)
			img.set_pixel(x, y, c * fade)
	img.generate_mipmaps()
	_tex["label"] = ImageTexture.create_from_image(img)
	return _tex["label"]


# --- декали хоррора (decor_horror.gd): форма — в альфе, цвет — в материале ---

static func decal(kind: String) -> Texture2D:
	match kind:
		"handprint": return handprint()
		"tally": return tally()
		"drag": return drag()
		_: return puddle()


static func _alpha_image(w: int, h: int, alpha: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(1, 1, 1, clampf(alpha.call(float(x) / w, float(y) / h), 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _grain(u: float, v: float) -> float:
	return fposmod(sin(u * 812.3 + v * 1931.7) * 43758.5, 1.0)


# Отпечаток ладони: ладонь, четыре пальца, большой в сторону и подтёки вниз
static func handprint() -> Texture2D:
	if not _tex.has("hand"):
		_tex["hand"] = _alpha_image(128, 128, func(u: float, v: float) -> float:
			var p := Vector2(u, v)
			var a: float = 1.0 - smoothstep(0.85, 1.05, Vector2((p.x - 0.5) / 0.19, (p.y - 0.6) / 0.21).length())
			for i in 4:
				var fx: float = 0.38 + i * 0.08
				var top: float = 0.18 + absf(i - 1.5) * 0.05
				if v > top and v < 0.45:
					a = maxf(a, 1.0 - smoothstep(0.022, 0.034, absf(u - fx - (0.45 - v) * (i - 1.5) * 0.08)))
			var thumb := Vector2(0.28, 0.5)
			a = maxf(a, 1.0 - smoothstep(0.03, 0.045, _seg(p, thumb, Vector2(0.38, 0.66))))
			# Подтёки: тонкие полосы от низа ладони вниз
			for k in 3:
				var dx: float = 0.42 + k * 0.08
				if v > 0.75 and absf(u - dx) < 0.012:
					a = maxf(a, 0.8 * (1.0 - smoothstep(0.78 + k * 0.05, 0.98, v)))
			return a * (0.65 + 0.35 * _grain(u, v)))
	return _tex["hand"]


static func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return (p - a - (b - a) * t).length()


# Счёт дней: группы по четыре черты, перечёркнутые пятой
static func tally() -> Texture2D:
	if not _tex.has("tally"):
		_tex["tally"] = _alpha_image(256, 96, func(u: float, v: float) -> float:
			var a: float = 0.0
			for g in 3:
				var gx: float = 0.06 + g * 0.31
				for k in 4:
					var x: float = gx + k * 0.045 + (v - 0.5) * 0.02
					a = maxf(a, 1.0 - smoothstep(0.004, 0.009, absf(u - x)))
				var slash: float = _seg(Vector2(u, v * 0.375), Vector2(gx - 0.02, 0.32), Vector2(gx + 0.17, 0.05))
				a = maxf(a, 1.0 - smoothstep(0.006, 0.012, slash))
			var band: float = smoothstep(0.08, 0.16, v) * (1.0 - smoothstep(0.84, 0.92, v))
			return a * band * (0.6 + 0.4 * _grain(u, v)))
	return _tex["tally"]


# След волочения: две рваные полосы, к концу бледнеют
static func drag() -> Texture2D:
	if not _tex.has("drag"):
		_tex["drag"] = _alpha_image(64, 256, func(u: float, v: float) -> float:
			var wob: float = sin(v * 23.0) * 0.02
			var a: float = 0.0
			for x in [0.3, 0.7]:
				a = maxf(a, 1.0 - smoothstep(0.06, 0.13, absf(u - x - wob)))
			return a * (1.0 - smoothstep(0.55, 1.0, v)) * (0.5 + 0.5 * _grain(u, v)))
	return _tex["drag"]


# Лужа: неровное пятно с мягким краем
static func puddle() -> Texture2D:
	if not _tex.has("puddle"):
		_tex["puddle"] = _alpha_image(128, 128, func(u: float, v: float) -> float:
			var p := Vector2(u - 0.5, v - 0.5)
			var ang: float = atan2(p.y, p.x)
			var r: float = 0.36 + 0.06 * sin(ang * 3.0) + 0.04 * sin(ang * 7.0 + 1.3)
			return 1.0 - smoothstep(r - 0.06, r, p.length()))
	return _tex["puddle"]
