extends RefCounted

# MicBank: звуки самой камеры, а не мира — запись. Корпус камеры стучит и
# шуршит тканью на шаге, на бегу микрофон ловит ветер, лента шипит, при
# включении камера пищит. Слой утилит (RATE/build/write_sample) берём у
# AudioBank, чтобы копии не разошлись; здесь только своё содержимое.

const AudioBank = preload("res://scripts/audio_bank.gd")

static var _cache: Dictionary = {}


# Удар корпуса камеры о грудь на шаге: низкий туп плюс шорох ткани.
# Три варианта тона, чтобы шаги не звучали циклом
static func rustle(variant: int) -> AudioStreamWAV:
	var key := "rustle_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6101 + variant * 131
	var count: int = int(AudioBank.RATE * 0.14)
	var data := PackedByteArray()
	data.resize(count * 2)
	var low: float = 0.0
	var band: float = 0.0
	for i in count:
		var t: float = float(i) / AudioBank.RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.10
		band += (noise - band) * 0.55
		# Туп корпуса: 62–74 Гц, гаснет за 80 мс
		var thump: float = sin(TAU * (62.0 + variant * 6.0) * t) * exp(-t * 24.0) * 0.55
		# Ткань: разность двух сглаживаний срезает низ и оставляет шорох
		var cloth: float = (band - low) * exp(-t * 18.0) * 0.5
		AudioBank.write_sample(data, i, (thump + cloth) * exp(-t * 9.0) * 0.8)
	return store(key, AudioBank.build(data, false))


# Ветер в микрофоне: широкополосный шум, сшитый кроссфейдом, — петля без
# щелчка на стыке. Громкость медленно «порхает», как настоящий ветер
static func wind_loop() -> AudioStreamWAV:
	if _cache.has("wind"):
		return _cache["wind"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4243
	var loop_count: int = int(round(AudioBank.RATE * 3.0))
	var fade_count: int = int(round(AudioBank.RATE * 0.25))
	var src := PackedFloat32Array()
	src.resize(loop_count + fade_count)
	var lp: float = 0.0
	for i in src.size():
		var t: float = float(i) / AudioBank.RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.18
		src[i] = lp * (0.55 + 0.45 * sin(TAU * 0.7 * t))
	return store("wind", _seam(src, loop_count, fade_count, 0.6))


# Шипение ленты: ровный шум всю запись. Тихий, но без него «телевизор»
# читается только глазами
static func hiss_loop() -> AudioStreamWAV:
	if _cache.has("hiss"):
		return _cache["hiss"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9127
	var loop_count: int = int(round(AudioBank.RATE * 3.0))
	var fade_count: int = int(round(AudioBank.RATE * 0.25))
	var src := PackedFloat32Array()
	src.resize(loop_count + fade_count)
	var lp: float = 0.0
	for i in src.size():
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.55
		src[i] = lp * 0.55 + noise * 0.45
	return store("hiss", _seam(src, loop_count, fade_count, 0.3))


# Включение записи: два коротких писка камеры. Мягкие края, чтобы не щёлкало
static func start_beep() -> AudioStreamWAV:
	if _cache.has("beep"):
		return _cache["beep"]
	var count: int = int(AudioBank.RATE * 0.22)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / AudioBank.RATE
		var local: float = -1.0
		if t < 0.075:
			local = t
		elif t > 0.105 and t < 0.18:
			local = t - 0.105
		var value: float = 0.0
		if local >= 0.0:
			var env: float = clampf(minf(local * 500.0, (0.075 - local) * 500.0), 0.0, 1.0)
			value = sin(TAU * 1240.0 * local) * env * 0.5
		AudioBank.write_sample(data, i, value)
	return store("beep", AudioBank.build(data, false))


# Петля из шума: хвост уходит в начало кроссфейдом, поэтому стык не щёлкает
static func _seam(src: PackedFloat32Array, loop_count: int, fade_count: int,
		level: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(loop_count * 2)
	for i in loop_count:
		var value: float = src[i]
		if i < fade_count:
			var w: float = float(i) / float(fade_count)
			value = src[i] * w + src[i + loop_count] * (1.0 - w)
		AudioBank.write_sample(data, i, value * level)
	return AudioBank.build(data, true)


static func store(key: String, stream: AudioStreamWAV) -> AudioStreamWAV:
	_cache[key] = stream
	return stream
