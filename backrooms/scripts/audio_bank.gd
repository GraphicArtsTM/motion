extends RefCounted

# AudioBank: звук синтезируется в рантайме — ни одного аудиофайла,
# как и с текстурами. Потоки 16 бит / 22050 Гц, кэшируются по имени.

const RATE: int = 22050

static var _cache := {}


# Шаг по ковру: глухой шум (сглаженный) + низкий «туп» веса тела
static func footstep(variant: int) -> AudioStreamWAV:
	var key := "step_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021 + variant * 97
	var count: int = int(RATE * 0.17)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	var start_phase: float = rng.randf_range(0.0, 1.0)
	for i in count:
		var t: float = float(i) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		smoothed += (noise - smoothed) * 0.16
		var thump: float = sin(TAU * (58.0 + variant * 5.0) * t + start_phase) \
			* exp(-t * 30.0) * 0.45
		var body: float = smoothed * 0.85 + thump
		write_sample(data, i, body * exp(-t * 32.0))
	return store(key, build(data, false))


# Гул люминесцентной лампы: 60/120/180 Гц с дрожанием сети.
# Частоты кратны 0.5 Гц — петля сходится почти без щелчка (шум не периодичен).
static func hum() -> AudioStreamWAV:
	if _cache.has("hum"):
		return _cache["hum"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 131
	var count: int = int(RATE * 2.0)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / RATE
		var v: float = sin(TAU * 60.0 * t) * 0.34
		v += sin(TAU * 120.0 * t + 0.7) * 0.22
		v += sin(TAU * 180.0 * t + 1.3) * 0.1
		v *= 0.86 + 0.08 * sin(TAU * 5.5 * t) + 0.06 * sin(TAU * 7.5 * t)
		v += rng.randf_range(-1.0, 1.0) * 0.015
		write_sample(data, i, v * 0.8)
	return store("hum", build(data, true))


# Звон брошенной банки: нестройные металлические частичные + щелчок
static func can_clang() -> AudioStreamWAV:
	if _cache.has("clang"):
		return _cache["clang"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var partials := [1180.0, 1970.0, 3260.0, 4410.0]
	var freqs: Array = []
	var gains: Array = []
	for k in partials.size():
		freqs.append(partials[k] * rng.randf_range(0.985, 1.015))
		gains.append(0.34 - k * 0.06)
	var count: int = int(RATE * 0.5)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t) * exp(-t * (11.0 + k * 4.0)) * gains[k]
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 55.0) * 0.5
		write_sample(data, i, v)
	return store("clang", build(data, false))


# Маяк предохранителя: высокий гул с пульсом — ищется на слух
static func fuse_hum() -> AudioStreamWAV:
	if _cache.has("fuse"):
		return _cache["fuse"]
	var count: int = int(RATE * 2.0)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / RATE
		var pulse: float = 0.5 + 0.5 * sin(TAU * 2.0 * t)
		var v: float = sin(TAU * 520.0 * t) * 0.34 + sin(TAU * 780.0 * t + 0.9) * 0.18
		v *= 0.35 + 0.65 * pulse
		v += sin(TAU * 1040.0 * t + 2.1) * 0.05
		write_sample(data, i, v)
	return store("fuse", build(data, true))


# Маяк двери выхода: низкий рокот, слышно за десятки метров
static func door_beacon() -> AudioStreamWAV:
	if _cache.has("beacon"):
		return _cache["beacon"]
	var count: int = int(RATE * 2.0)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / RATE
		var v: float = sin(TAU * 45.0 * t) * 0.4 + sin(TAU * 90.0 * t + 0.5) * 0.2
		v += sin(TAU * 135.0 * t + 1.1) * 0.09
		v *= 0.8 + 0.2 * sin(TAU * 0.5 * t)
		write_sample(data, i, v)
	return store("beacon", build(data, true))


# Вставленный предохранитель: механический щелчок с отдачей
static func insert_clunk() -> AudioStreamWAV:
	if _cache.has("clunk"):
		return _cache["clunk"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var count: int = int(RATE * 0.3)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		smoothed += (rng.randf_range(-1.0, 1.0) - smoothed) * 0.3
		var body: float = sin(TAU * 115.0 * t) * exp(-t * 26.0) * 0.6
		write_sample(data, i, (smoothed * 0.5 + body) * exp(-t * 18.0))
	return store("clunk", build(data, false))


# Вставка предохранителя под нагрузкой: щелчок контакта, гул трансформатора
# сползает вниз и тянется грязной сетью — низко и мощно, слышно издалека
static func power_surge() -> AudioStreamWAV:
	if _cache.has("surge"):
		return _cache["surge"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var count: int = int(RATE * 0.9)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed: float = 0.0
	var phase: float = 0.0
	for i in count:
		var t: float = float(i) / RATE
		phase += TAU * (92.0 - 54.0 * minf(t * 1.6, 1.0)) / RATE
		var v: float = sin(phase) * exp(-t * 3.4) * 0.55
		v += sin(phase * 2.0 + 0.6) * exp(-t * 5.0) * 0.16
		v += sin(TAU * 118.0 * t) * exp(-t * 2.4) * 0.12
		v += sin(TAU * 236.0 * t + 1.1) * exp(-t * 2.8) * 0.06
		v += sin(TAU * 760.0 * t) * exp(-t * 16.0) * 0.11 # звон контакта
		smoothed += (rng.randf_range(-1.0, 1.0) - smoothed) * 0.45
		write_sample(data, i, (v + smoothed * exp(-t * 42.0) * 0.45) * 0.7)
	return store("surge", build(data, false))


# Готовый источник на нужной шине: SFX / Ambient / Entity / Beacon (default_bus_layout.tres)
static func source(bus_name: String, stream: AudioStreamWAV, unit: float) -> AudioStreamPlayer3D:
	var node := AudioStreamPlayer3D.new()
	node.bus = bus_name
	node.stream = stream
	node.unit_size = unit
	return node


# Разовая реплика в мире: звук живёт сам, даже если владелец исчез
static func play_one_shot(tree: SceneTree, pos: Vector3, stream: AudioStreamWAV,
		unit: float, bus_name: String = "SFX") -> void:
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	var player := AudioStreamPlayer3D.new()
	player.bus = bus_name
	player.stream = stream
	player.unit_size = unit
	parent.add_child(player)
	player.global_position = pos
	player.play()
	player.finished.connect(player.queue_free)


static func write_sample(data: PackedByteArray, index: int, sample: float) -> void:
	data.encode_s16(index * 2, int(clampf(sample, -1.0, 1.0) * 32000.0))


static func build(data: PackedByteArray, looped: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = data.size() / 2
	return stream


static func store(key: String, stream: AudioStreamWAV) -> AudioStreamWAV:
	_cache[key] = stream
	return stream
