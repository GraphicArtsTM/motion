extends RefCounted

# AudioWater: звуки затопленных секторов (flood.gd) — плеск шага по воде
# по щиколотку и капель с потолка. Синтез как в audio_bank.gd, кэш общий.

const AudioBank = preload("res://scripts/audio_bank.gd")

const RATE: int = AudioBank.RATE

static var _cache := {}


# Шаг по воде: шлепок (шум с быстрым спадом), шелест расходящейся воды и
# пара «бульков» — коротких тонов, уходящих вверх
static func splash(variant: int) -> AudioStreamWAV:
	var key := "splash_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501 + variant * 61
	var count: int = int(RATE * 0.38)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smooth: float = 0.0
	var bubbles: Array = []
	for b in 3:
		bubbles.append([rng.randf_range(0.02, 0.16), rng.randf_range(380.0, 900.0)])
	for i in count:
		var t: float = float(i) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		smooth += (noise - smooth) * 0.45
		var slap: float = noise * exp(-t * 55.0) * 0.6
		var hiss: float = smooth * exp(-t * 9.0) * 0.32
		var v: float = slap + hiss
		for b in bubbles:
			var dt: float = t - float(b[0])
			if dt > 0.0:
				var f: float = float(b[1]) * (1.0 + dt * 6.0)
				v += sin(TAU * f * dt) * exp(-dt * 60.0) * 0.18
		AudioBank.write_sample(data, i, v)
	var stream := AudioBank.build(data, false)
	_cache[key] = stream
	return stream


# Капель: петля 3 с, капли падают в воду в случайные моменты — щелчок и
# тон, проседающий вниз, с хвостом отзвука
static func drips() -> AudioStreamWAV:
	if _cache.has("drips"):
		return _cache["drips"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7307
	var count: int = int(RATE * 3.0)
	var data := PackedByteArray()
	data.resize(count * 2)
	var drops: Array = []
	for d in 5:
		drops.append([rng.randf_range(0.05, 2.6), rng.randf_range(900.0, 1700.0), rng.randf_range(0.3, 0.7)])
	for i in count:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for d in drops:
			var dt: float = t - float(d[0])
			if dt > 0.0 and dt < 0.35:
				var f: float = float(d[1]) * (1.0 - dt * 1.5)
				v += sin(TAU * f * dt) * exp(-dt * 22.0) * float(d[2])
		AudioBank.write_sample(data, i, v * 0.6)
	var stream := AudioBank.build(data, true)
	_cache["drips"] = stream
	return stream
