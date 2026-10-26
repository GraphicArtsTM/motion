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
