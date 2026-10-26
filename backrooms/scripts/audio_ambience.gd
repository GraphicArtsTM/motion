extends RefCounted

# AudioAmbience: голос самого здания — подложка-гул вентиляции и редкие
# звуки пустого лабиринта: далёкий обвал, капля, скрип, хлопок двери.
# Синтез тот же, что в audio_bank.gd: аудиофайлов в проекте нет.

const AudioBank = preload("res://scripts/audio_bank.gd")

const RATE: int = 22050

static var _cache := {}


# Синтез дорогой (подложка — ~90 мс, обвал — ~28 мс), поэтому готовый
# поток кладём ещё и в локальный кэш, иначе событие синтезировалось бы заново
static func _keep(key: String, data: PackedByteArray, looped: bool) -> AudioStreamWAV:
	var stream := AudioBank.store(key, AudioBank.build(data, looped))
	_cache[key] = stream
	return stream


# Подложка: вентиляция и низкий гул. Петля 16 секунд, все тональные
# частоты кратны 1/16 — стык сходится сам; непериодический шум выведен
# в ноль огибающей wind. Есть середина (128/172/256 Гц и полоса 70–370),
# иначе на динамиках ноутбука слышно только «бубнение» ниже 100 Гц
static func drone() -> AudioStreamWAV:
	if _cache.has("drone"):
		return _cache["drone"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var seconds: float = 16.0
	var count: int = int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var low: float = 0.0
	var band: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		# Три медленные огибающие (16 / 5.3 / 3.2 с): одна выдавала бы
		# себя слышимым «вуп-вуп» раз в петлю
		var env: float = 0.85 + 0.1 * sin(TAU * t / seconds) \
			+ 0.06 * sin(TAU * 3.0 * t / seconds + 1.2) \
			+ 0.05 * sin(TAU * 5.0 * t / seconds + 2.4)
		var wind: float = sin(PI * t / seconds)
		var raw: float = rng.randf_range(-1.0, 1.0)
		band += (raw - band) * 0.1
		low += (raw - low) * 0.02
		var v: float = sin(TAU * 32.0 * t) * 0.3
		v += sin(TAU * 41.0 * t + 0.6) * 0.14
		v += sin(TAU * 64.0 * t + 0.3) * 0.12
		v += sin(TAU * 82.0 * t + 1.1) * 0.08
		v += sin(TAU * 128.0 * t + 2.2) * 0.07
		v += sin(TAU * 172.0 * t + 0.4) * 0.04
		v += sin(TAU * 256.0 * t + 1.7) * 0.03
		v += (band - low) * 1.6 * wind
		v += low * 1.2 * wind
		AudioBank.write_sample(data, i, v * env * 0.55)
	return _keep("drone", data, true)


# Далёкий обвал: низкий грохот с падающей высотой и длинным хвостом
static func rumble() -> AudioStreamWAV:
	if _cache.has("rumble"):
		return _cache["rumble"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3313
	var count: int = int(RATE * 3.0)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	var phase: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		var env: float = exp(-t * 1.1) * (1.0 - exp(-t * 14.0))
		var freq: float = 26.0 + 12.0 * exp(-t * 1.6)
		phase += TAU * freq / RATE
		smoothed += (rng.randf_range(-1.0, 1.0) - smoothed) * 0.05
		var v: float = sin(phase) * 0.6 + sin(phase * 2.0) * 0.2 + smoothed * 0.9
		AudioBank.write_sample(data, i, v * env * 0.8)
	return _keep("rumble", data, false)


# Капля: свистящий глиссандр вниз с щелчком касания
static func drip() -> AudioStreamWAV:
	if _cache.has("drip"):
		return _cache["drip"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8123
	var count: int = int(RATE * 0.32)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		var env: float = exp(-t * 13.0)
		var freq: float = 700.0 + 900.0 * exp(-t * 24.0)
		phase += TAU * freq / RATE
		var v: float = sin(phase) * 0.6 + sin(phase * 2.7) * 0.16
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 220.0) * 0.3
		AudioBank.write_sample(data, i, v * env * 0.7)
	return _keep("drip", data, false)


# Скрип: металлическая струна, которую тянет рывками — дом «садится»
static func creak() -> AudioStreamWAV:
	if _cache.has("creak"):
		return _cache["creak"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6011
	var seconds: float = 1.5
	var count: int = int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	var phase: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		var env: float = sin(PI * minf(t / seconds, 1.0))
		var step: int = int(t / 0.5)
		var freq: float = 88.0 + 26.0 * float(step) + 8.0 * sin(TAU * 6.0 * t)
		phase += TAU * freq / RATE
		smoothed += (rng.randf_range(-1.0, 1.0) - smoothed) * 0.35
		var saw: float = 2.0 * fposmod(phase, TAU) / TAU - 1.0
		AudioBank.write_sample(data, i, (saw * 0.32 + smoothed * 0.25) * env * 0.55)
	return _keep("creak", data, false)


# Хлопок двери вдалеке: глухой удар, широкий шлепок и низкий хвост
static func slam() -> AudioStreamWAV:
	if _cache.has("slam"):
		return _cache["slam"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9141
	var count: int = int(RATE * 1.1)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		# Высокие срезаны сглаживанием: так звук идёт «сквозь стены»
		smoothed += (rng.randf_range(-1.0, 1.0) - smoothed) * 0.08
		var body: float = sin(TAU * 58.0 * t) * exp(-t * 9.0) * 0.6
		var slap: float = smoothed * exp(-t * 6.0) * 1.1
		var tail: float = sin(TAU * 40.0 * t) * exp(-t * 3.2) * 0.3
		AudioBank.write_sample(data, i, (body + slap + tail) * 0.8)
	return _keep("slam", data, false)
