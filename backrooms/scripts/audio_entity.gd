extends RefCounted

# AudioEntity: голос хозяина лабиринта — тяжёлые шаги, дыхание за спиной,
# рёв погони и шёпот вблизи. Синтез тот же, что в audio_bank.gd, только
# ниже и грязнее; аудиофайлов в проекте по-прежнему нет.

const AudioBank = preload("res://scripts/audio_bank.gd")

const RATE: int = 22050

static var _cache := {}


# Шаг: вес тела падает с высоты — низкий удар с длинным хвостом и шорохом
static func step(variant: int = 0) -> AudioStreamWAV:
	var key := "ent_step_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717 + variant * 131
	var count: int = int(RATE * 0.42)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	var phase: float = rng.randf_range(0.0, 1.0)
	for i in count:
		var t: float = float(i) / RATE
		smoothed += (rng.randf_range(-1.0, 1.0) - smoothed) * 0.1
		var thud: float = sin(TAU * (34.0 + variant * 4.0) * t + phase) \
			* exp(-t * 13.0) * 0.7
		var creak: float = sin(TAU * (70.0 + variant * 9.0) * t) * exp(-t * 26.0) * 0.2
		AudioBank.write_sample(data, i, thud + creak + smoothed * 0.25 * exp(-t * 8.0))
	return AudioBank.store(key, AudioBank.build(data, false))


# Дыхание: два вздоха за петлю. Конверт замыкается в ноль на стыке,
# поэтому петля не щёлкает, хотя шум внутри неё не периодичен
static func breath() -> AudioStreamWAV:
	if _cache.has("ent_breath"):
		return _cache["ent_breath"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6120
	var seconds: float = 4.0
	var count: int = int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		var env: float = 0.5 - 0.5 * cos(TAU * t / seconds * 2.0)
		smoothed += (rng.randf_range(-1.0, 1.0) - smoothed) * 0.05
		var wheeze: float = smoothed * env * 0.9
		var rasp: float = sin(TAU * 88.0 * t) * env * 0.14
		AudioBank.write_sample(data, i, wheeze + rasp)
	return AudioBank.store("ent_breath", AudioBank.build(data, true))


# Рёв погони: пила с падающей высотой, хрип и дрожь — «оно увидело тебя»
static func roar() -> AudioStreamWAV:
	if _cache.has("ent_roar"):
		return _cache["ent_roar"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3181
	var count: int = int(RATE * 1.4)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		var env: float = exp(-t * 1.7) * (1.0 - exp(-t * 45.0))
		var freq: float = 62.0 + 30.0 * exp(-t * 1.9)
		phase += TAU * freq / RATE
		var saw: float = 2.0 * fposmod(phase, TAU) / TAU - 1.0
		var formant: float = sin(phase * 3.0) * 0.3 + sin(TAU * 214.0 * t) * 0.1
		var growl: float = 0.75 + 0.25 * sin(TAU * 18.0 * t)
		AudioBank.write_sample(data, i, (saw * 0.5 + formant
			+ rng.randf_range(-1.0, 1.0) * 0.18) * env * growl)
	return AudioBank.store("ent_roar", AudioBank.build(data, false))


# Шёпот: шипящий выдох с блуждающей формантой — оно рядом, но не видно
static func whisper() -> AudioStreamWAV:
	if _cache.has("ent_whisper"):
		return _cache["ent_whisper"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4409
	var count: int = int(RATE * 1.6)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		var env: float = sin(PI * t / 1.6)
		var raw: float = rng.randf_range(-1.0, 1.0)
		smoothed += (raw - smoothed) * 0.25
		var tone: float = sin(TAU * (300.0 + 90.0 * sin(TAU * 1.7 * t)) * t) * 0.08
		AudioBank.write_sample(data, i, (smoothed * 0.4 + (raw - smoothed) * 0.35
			+ tone) * env * (0.6 + 0.4 * sin(TAU * 3.5 * t)))
	return AudioBank.store("ent_whisper", AudioBank.build(data, false))
