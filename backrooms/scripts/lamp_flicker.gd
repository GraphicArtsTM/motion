extends Node

# LampFlicker: «больная» лампа чанка. Почти всё время горит, но то
# срывается в короткие провалы (лампа-стартер не держит дугу), то
# захлёбывается серией вспышек, а изредка гаснет на пару секунд — и в
# этой тьме гул срывается в треск. Ведёт свет чанка, его панели и гул
# разом. Ставит lamp_manager.gd — чаще в глубине, где всё запущено.

var light: OmniLight3D = null
var panel: ShaderMaterial = null
var hum: AudioStreamPlayer3D = null
var energy: float = 1.0
var brightness: float = 1.0
var hum_db: float = -24.0
var rng := RandomNumberGenerator.new()
var level: float = 1.0
var target: float = 1.0
var hold: float = 0.0
var burst: int = 0


func setup(light_ref: OmniLight3D, panel_ref: ShaderMaterial, hum_ref: AudioStreamPlayer3D,
		seed_value: int) -> void:
	light = light_ref
	panel = panel_ref
	hum = hum_ref
	energy = light.light_energy
	brightness = float(panel.get_shader_parameter("brightness")) if panel else 1.0
	hum_db = hum.volume_db if hum else -24.0
	rng.seed = seed_value


func _process(delta: float) -> void:
	if light == null:
		return
	hold -= delta
	if hold <= 0.0:
		_next()
	# Дуга загорается рывком, гаснет чуть мягче
	level = move_toward(level, target, delta * (40.0 if target > level else 18.0))
	var shimmer: float = 1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.75)
	light.light_energy = energy * level * shimmer
	if panel:
		panel.set_shader_parameter("brightness", brightness * level)
	if hum:
		hum.volume_db = hum_db + linear_to_db(maxf(level, 0.05)) * 0.6


# Следующее состояние: серия вспышек, провал, долгая тьма или ровный свет
func _next() -> void:
	if burst > 0:
		burst -= 1
		target = 1.0 if target < 0.5 else rng.randf_range(0.0, 0.25)
		hold = rng.randf_range(0.03, 0.09)
		return
	var roll: float = rng.randf()
	if roll < 0.12:
		burst = rng.randi_range(3, 9)
		target = 0.1
		hold = 0.05
	elif roll < 0.2:
		target = rng.randf_range(0.0, 0.08)
		hold = rng.randf_range(0.8, 2.6)
	elif roll < 0.45:
		target = rng.randf_range(0.2, 0.5)
		hold = rng.randf_range(0.04, 0.15)
	else:
		target = 1.0
		hold = rng.randf_range(0.4, 3.0)
